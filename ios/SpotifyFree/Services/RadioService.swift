import Foundation

/// Fetches radio candidate tracks from the backend `/radio` endpoint.
/// Called by QueueManager to keep the `autoplayQueue` filled to `radioTargetSize`.
actor RadioService {
    static let shared = RadioService()

    private let baseURL: URL
    private let session: URLSession

    // 6h in-memory candidate pool per seed artist — avoids hammering the endpoint
    // every time a track ends.
    private struct PoolEntry {
        let tracks: [Track]
        let expiresAt: Date
    }
    private var poolCache: [String: PoolEntry] = [:]

    init(session: URLSession = .shared) {
        self.session = session
        let fromPlist = Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_FREE_BACKEND_URL") as? String
        let raw = (fromPlist?.isEmpty == false ? fromPlist! : "http://localhost:3000")
        self.baseURL = URL(string: raw) ?? URL(string: "http://localhost:3000")!
    }

    /// Return up to `want` radio candidates for the given artist, excluding the
    /// provided track IDs (already playing, already queued, recent history).
    func candidates(forArtist name: String, excluding: Set<Int>, want: Int) async -> [Track] {
        let pool = await fetchPool(for: name)
        let filtered = pool.filter { !excluding.contains($0.itunesTrackId) }
        return Array(filtered.prefix(want))
    }

    // MARK: - Private

    private func fetchPool(for artist: String) async -> [Track] {
        let key = artist.lowercased()
        let now = Date()
        if let entry = poolCache[key], entry.expiresAt > now {
            return entry.tracks
        }

        var comps = URLComponents(url: baseURL.appendingPathComponent("radio"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "limit", value: "50"),
        ]
        guard let url = comps.url else { return [] }

        do {
            var req = URLRequest(url: url, timeoutInterval: 8)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let decoded = try JSONDecoder().decode(RadioResponse.self, from: data)
            let tracks = decoded.tracks.compactMap(mapTrack)
            // Shuffle locally so different devices get different orders from same cache
            let shuffled = tracks.shuffled()
            poolCache[key] = PoolEntry(tracks: shuffled, expiresAt: Date(timeIntervalSinceNow: 6 * 3600))
            return shuffled
        } catch {
            return []
        }
    }

    private struct RadioResponse: Decodable {
        let tracks: [RadioTrack]
    }

    private struct RadioTrack: Decodable {
        let itunesTrackId: Int
        let name: String
        let artistName: String
        let albumName: String?
        let artistId: Int?
        let durationMs: Int?
        let artworkUrl: String?
        let isrc: String?
        let previewUrl: String?
        let videoId: String?
    }

    private func mapTrack(_ r: RadioTrack) -> Track? {
        Track(
            itunesTrackId: r.itunesTrackId,
            isrc: r.isrc,
            name: r.name,
            artistName: r.artistName,
            artistId: r.artistId,
            albumName: r.albumName,
            durationMs: r.durationMs ?? 0,
            artworkUrl: r.artworkUrl.flatMap { URL(string: $0) },
            previewUrl: r.previewUrl.flatMap { URL(string: $0) },
            videoId: r.videoId
        )
    }
}
