import Foundation

/// Track search now goes to the Python semantic-search backend (`POST /search`,
/// `SEARCH_BACKEND_URL`): a ranked pool of YouTube videoIds. The new backend
/// returns tracks only, so albums/artists still come from iTunes (concurrently).
/// If the search backend is unreachable, we fall back to iTunes track search.
///
/// `artistTopTracks` still hits the Node backend (`SPOTIFY_FREE_BACKEND_URL`).
actor SearchService {
    static let shared = SearchService()

    struct SearchResults {
        var tracks: [Track] = []
        var albums: [Album] = []
        var artists: [Artist] = []
    }

    private let baseURL: URL        // Node backend (artist-top-tracks)
    private let searchURL: URL      // Python semantic-search backend
    private let session: URLSession
    private let itunesClient = iTunesClient.shared

    init(session: URLSession = .shared) {
        self.session = session
        self.baseURL = Self.url(forKey: "SPOTIFY_FREE_BACKEND_URL", fallback: "http://localhost:3000")
        self.searchURL = Self.url(forKey: "SEARCH_BACKEND_URL", fallback: "http://localhost:8000")
    }

    private static func url(forKey key: String, fallback: String) -> URL {
        let fromPlist = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let raw = (fromPlist?.isEmpty == false ? fromPlist! : fallback)
        return URL(string: raw) ?? URL(string: fallback)!
    }

    func search(_ term: String) async -> SearchResults {
        // Tracks from the semantic backend; albums/artists from iTunes — in parallel.
        async let semanticTracks = semanticSearch(term)
        async let albums = (try? await itunesClient.searchAlbums(term)) ?? []
        async let artists = (try? await itunesClient.searchArtists(term)) ?? []

        let tracks: [Track]
        if let semantic = await semanticTracks, !semantic.isEmpty {
            tracks = semantic
        } else {
            // Backend down or empty — fall back to iTunes track search.
            tracks = (try? await itunesClient.searchTracks(term)) ?? []
        }
        return SearchResults(tracks: tracks, albums: await albums, artists: await artists)
    }

    /// POST /search to the Python backend. Returns nil on any failure so the
    /// caller can fall back to iTunes; an empty array means "reached it, no hits".
    private func semanticSearch(_ term: String) async -> [Track]? {
        let url = searchURL.appendingPathComponent("search")
        do {
            // 12s: a cold semantic query (LLM understand + adapter fan-out) can
            // run several seconds; too tight a timeout silently drops to iTunes.
            var req = URLRequest(url: url, timeoutInterval: 12)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.httpBody = try JSONEncoder().encode(SearchQuery(query: term, top_k: 10))
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(SemanticSearchResponse.self, from: data)
            return decoded.results.compactMap(mapSemanticTrack)
        } catch {
            return nil
        }
    }

    /// Fetch top tracks for an artist, ranked by Last.fm popularity.
    func artistTopTracks(name: String, artistId: Int?) async -> [Track] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("artist-top-tracks"), resolvingAgainstBaseURL: false)!
        var qi: [URLQueryItem] = [URLQueryItem(name: "artist", value: name)]
        if let id = artistId { qi.append(URLQueryItem(name: "artistId", value: "\(id)")) }
        comps.queryItems = qi
        guard let url = comps.url else { return [] }

        do {
            var req = URLRequest(url: url, timeoutInterval: 8)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let decoded = try JSONDecoder().decode(BackendTracksResponse.self, from: data)
            return decoded.tracks.compactMap(mapTrack)
        } catch {
            return []
        }
    }

    // MARK: - Semantic-search decoding (Python backend)

    private struct SearchQuery: Encodable {
        let query: String
        let top_k: Int
    }

    private struct SemanticSearchResponse: Decodable {
        let results: [SemanticTrack]
    }

    private struct SemanticTrack: Decodable {
        let track_id: String
        let title: String
        let artist: String
        let album: String?
        let duration_sec: Int?
        let video_id: String
        let source_kind: String?
        let score: Double?
    }

    /// The semantic backend returns no iTunes id or artwork — only a videoId.
    /// Mirror the app's existing YouTube-result convention: a stable *negative*
    /// pseudo-id derived from the videoId (so it never collides with real iTunes
    /// ids, and `SearchView` shows the "YT" badge + gradient artwork). Playback
    /// uses `videoId` directly.
    private func mapSemanticTrack(_ s: SemanticTrack) -> Track? {
        guard !s.video_id.isEmpty else { return nil }
        return Track(
            itunesTrackId: Self.ytPseudoId(s.video_id),
            isrc: nil,
            name: s.title,
            artistName: s.artist,
            artistId: nil,
            albumName: s.album,
            albumId: nil,
            durationMs: (s.duration_sec ?? 0) * 1000,
            artworkUrl: nil,
            previewUrl: nil,
            videoId: s.video_id
        )
    }

    /// Stable negative Int id from a videoId (djb2). Matches the old Node
    /// backend's `ytPseudoId` so YT-only results keep a consistent identity.
    static func ytPseudoId(_ videoId: String) -> Int {
        var h = 5381
        for u in videoId.unicodeScalars {
            h = ((h &* 33) ^ Int(u.value)) & 0x7fffffff
        }
        return -h
    }

    // MARK: - Node artist-top-tracks decoding

    private struct BackendTracksResponse: Decodable {
        let tracks: [BackendTrack]
    }

    private struct BackendTrack: Decodable {
        let itunesTrackId: Int
        let name: String
        let artistName: String
        let albumName: String?
        let artistId: Int?
        let albumId: Int?
        let durationMs: Int?
        let artworkUrl: String?
        let isrc: String?
        let previewUrl: String?
        let videoId: String?
        let source: String?
    }

    private func mapTrack(_ b: BackendTrack) -> Track? {
        Track(
            itunesTrackId: b.itunesTrackId,
            isrc: b.isrc,
            name: b.name,
            artistName: b.artistName,
            artistId: b.artistId,
            albumName: b.albumName,
            albumId: b.albumId,
            durationMs: b.durationMs ?? 0,
            artworkUrl: b.artworkUrl.flatMap { URL(string: $0) },
            previewUrl: b.previewUrl.flatMap { URL(string: $0) },
            videoId: b.videoId
        )
    }
}
