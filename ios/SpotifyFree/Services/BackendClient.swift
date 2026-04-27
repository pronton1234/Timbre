import Foundation

/// Calls the spotify-free backend (`/resolve`) to map an iTunes track to a
/// YouTube `videoId`. Stream URL extraction happens on-device via
/// `StreamResolver` — see that file for why.
///
/// Base URL is read from Info.plist key `SPOTIFY_FREE_BACKEND_URL` so we can
/// point at localhost in dev and DuckDNS in prod without a rebuild flag.
actor BackendClient {
    static let shared = BackendClient()

    /// Backend returns a videoId (and a few diagnostic fields). We decode the
    /// fields that matter and ignore anything else (legacy `streamUrl` etc.).
    struct MatchedVideo: Decodable {
        let videoId: String
        let source: String?          // "cache" | "fresh"
        let matchScore: Int?
    }

    enum BackendError: Error { case badResponse(Int, String), misconfigured }

    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared) {
        self.session = session
        let fromPlist = (Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_FREE_BACKEND_URL") as? String)
        let fallback = "http://localhost:3000"
        let raw = (fromPlist?.isEmpty == false ? fromPlist! : fallback)
        self.baseURL = URL(string: raw) ?? URL(string: fallback)!
    }

    /// Map an iTunes track to a YouTube videoId via the backend's match service.
    func matchVideoId(track: Track) async throws -> MatchedVideo {
        var comps = URLComponents(url: baseURL.appendingPathComponent("resolve"), resolvingAgainstBaseURL: false)!
        var q: [URLQueryItem] = [
            URLQueryItem(name: "title", value: track.name),
            URLQueryItem(name: "artist", value: track.artistName),
            URLQueryItem(name: "durationMs", value: "\(track.durationMs)"),
            URLQueryItem(name: "itunesTrackId", value: "\(track.itunesTrackId)"),
        ]
        if let isrc = track.isrc { q.append(URLQueryItem(name: "isrc", value: isrc)) }
        comps.queryItems = q
        guard let url = comps.url else { throw BackendError.misconfigured }
        return try await getJSON(url: url)
    }

    // MARK: - Private

    private func getJSON<T: Decodable>(url: URL) async throws -> T {
        var attempt = 0
        while true {
            do {
                var req = URLRequest(url: url, timeoutInterval: 5)
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else { throw BackendError.badResponse(-1, "no http") }
                if (200..<300).contains(http.statusCode) {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    return try decoder.decode(T.self, from: data)
                }
                if http.statusCode == 429 || (500..<600).contains(http.statusCode), attempt < 2 {
                    // fall through to backoff
                } else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    throw BackendError.badResponse(http.statusCode, body)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if attempt >= 2 { throw error }
            }
            attempt += 1
            let backoffMs = UInt64((200 << attempt) + .random(in: 0..<80))
            try? await Task.sleep(nanoseconds: backoffMs * 1_000_000)
        }
    }
}
