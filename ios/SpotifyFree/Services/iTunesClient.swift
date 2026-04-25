import Foundation

/// Thin async client for Apple's iTunes Search API (public, no auth).
/// https://performance-partners.apple.com/search-api
actor iTunesClient {
    static let shared = iTunesClient()

    private let base = URL(string: "https://itunes.apple.com")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    enum Entity: String { case song, album, musicArtist, artistAlbum }

    // MARK: - Public API

    func searchTracks(_ term: String, limit: Int = 25) async throws -> [Track] {
        let payload: ITunesResponse = try await get("/search", query: [
            "term": term, "entity": Entity.song.rawValue, "limit": "\(limit)", "media": "music",
        ])
        return payload.results.compactMap(Self.mapTrack)
    }

    func searchAlbums(_ term: String, limit: Int = 25) async throws -> [Album] {
        let payload: ITunesResponse = try await get("/search", query: [
            "term": term, "entity": Entity.album.rawValue, "limit": "\(limit)",
        ])
        return payload.results.compactMap(Self.mapAlbum)
    }

    func searchArtists(_ term: String, limit: Int = 25) async throws -> [Artist] {
        let payload: ITunesResponse = try await get("/search", query: [
            "term": term, "entity": Entity.musicArtist.rawValue, "limit": "\(limit)",
        ])
        return payload.results.compactMap(Self.mapArtist)
    }

    func lookupTrack(_ itunesTrackId: Int) async throws -> Track? {
        let payload: ITunesResponse = try await get("/lookup", query: ["id": "\(itunesTrackId)"])
        return payload.results.compactMap(Self.mapTrack).first
    }

    func albumsByArtist(_ artistId: Int, limit: Int = 25) async throws -> [Album] {
        let payload: ITunesResponse = try await get("/lookup", query: [
            "id": "\(artistId)", "entity": "album", "limit": "\(limit)",
        ])
        return payload.results.compactMap(Self.mapAlbum)
    }

    func tracksByAlbum(_ collectionId: Int) async throws -> [Track] {
        let payload: ITunesResponse = try await get("/lookup", query: [
            "id": "\(collectionId)", "entity": "song",
        ])
        return payload.results.compactMap(Self.mapTrack)
    }

    // MARK: - Private

    private func get<T: Decodable>(_ path: String, query: [String: String]) async throws -> T {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { throw URLError(.badURL) }

        // Retry with jitter for transient network / 5xx
        var attempt = 0
        while true {
            do {
                let (data, resp) = try await session.data(from: url)
                guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if (200..<300).contains(http.statusCode) {
                    return try JSONDecoder().decode(T.self, from: data)
                }
                if http.statusCode == 429 || (500..<600).contains(http.statusCode) {
                    if attempt >= 2 { throw URLError(.badServerResponse) }
                } else {
                    throw URLError(.badServerResponse)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if attempt >= 2 { throw error }
            }
            attempt += 1
            let backoffMs = UInt64((150 << attempt) + .random(in: 0..<50))
            try? await Task.sleep(nanoseconds: backoffMs * 1_000_000)
        }
    }

    // MARK: - Mapping

    static func upscaleArtwork(_ raw: URL?) -> URL? {
        guard let raw else { return nil }
        let s = raw.absoluteString
        // Replace any NNNxNNNbb with 600x600bb
        let re = try! NSRegularExpression(pattern: "/\\d+x\\d+bb\\.(jpg|png)", options: [])
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        let replaced = re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "/600x600bb.$1")
        return URL(string: replaced)
    }

    static func mapTrack(_ r: ITunesItem) -> Track? {
        guard let id = r.trackId, let name = r.trackName, let artist = r.artistName else { return nil }
        return Track(
            itunesTrackId: id,
            isrc: r.isrc,
            name: name,
            artistName: artist,
            artistId: r.artistId,
            albumName: r.collectionName,
            albumId: r.collectionId,
            durationMs: r.trackTimeMillis ?? 0,
            artworkUrl: upscaleArtwork(r.artworkUrl100.flatMap(URL.init)),
            previewUrl: r.previewUrl.flatMap(URL.init)
        )
    }

    static func mapAlbum(_ r: ITunesItem) -> Album? {
        guard let id = r.collectionId, let name = r.collectionName, let artist = r.artistName else { return nil }
        let releaseDate: Date? = r.releaseDate.flatMap { ISO8601DateFormatter().date(from: $0) }
        return Album(
            itunesCollectionId: id,
            name: name,
            artistName: artist,
            artistId: r.artistId,
            artworkUrl: upscaleArtwork(r.artworkUrl100.flatMap(URL.init)),
            trackCount: r.trackCount,
            releaseDate: releaseDate
        )
    }

    static func mapArtist(_ r: ITunesItem) -> Artist? {
        guard let id = r.artistId, let name = r.artistName else { return nil }
        return Artist(
            itunesArtistId: id,
            name: name,
            primaryGenre: r.primaryGenreName,
            artistLinkUrl: r.artistLinkUrl.flatMap(URL.init)
        )
    }
}

// MARK: - Wire DTOs

struct ITunesResponse: Decodable {
    let resultCount: Int
    let results: [ITunesItem]
}

struct ITunesItem: Decodable {
    let wrapperType: String?
    let kind: String?
    let trackId: Int?
    let trackName: String?
    let artistId: Int?
    let artistName: String?
    let collectionId: Int?
    let collectionName: String?
    let trackTimeMillis: Int?
    let artworkUrl100: String?
    let previewUrl: String?
    let isrc: String?
    let releaseDate: String?
    let trackCount: Int?
    let primaryGenreName: String?
    let artistLinkUrl: String?
}
