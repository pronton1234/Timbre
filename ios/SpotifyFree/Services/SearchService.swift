import Foundation

/// Calls the backend `/search` endpoint.
/// Falls back to the iTunes client if the backend is unreachable.
actor SearchService {
    static let shared = SearchService()

    struct SearchResults {
        var tracks: [Track] = []
        var albums: [Album] = []
        var artists: [Artist] = []
    }

    private let baseURL: URL
    private let session: URLSession
    private let itunesClient = iTunesClient.shared

    init(session: URLSession = .shared) {
        self.session = session
        let fromPlist = Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_FREE_BACKEND_URL") as? String
        let raw = (fromPlist?.isEmpty == false ? fromPlist! : "http://localhost:3000")
        self.baseURL = URL(string: raw) ?? URL(string: "http://localhost:3000")!
    }

    func search(_ term: String) async -> SearchResults {
        var comps = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "q", value: term), URLQueryItem(name: "limit", value: "25")]
        guard let url = comps.url else { return await fallback(term) }

        do {
            var req = URLRequest(url: url, timeoutInterval: 5)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return await fallback(term)
            }
            let decoded = try JSONDecoder().decode(BackendSearchResponse.self, from: data)
            return SearchResults(
                tracks: decoded.tracks.compactMap(mapTrack),
                albums: decoded.albums.compactMap(mapAlbum),
                artists: decoded.artists.compactMap(mapArtist)
            )
        } catch {
            return await fallback(term)
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

    // MARK: - Fallback

    private func fallback(_ term: String) async -> SearchResults {
        async let t  = (try? await itunesClient.searchTracks(term))  ?? []
        async let al = (try? await itunesClient.searchAlbums(term))  ?? []
        async let ar = (try? await itunesClient.searchArtists(term)) ?? []
        let (tv, av, arv) = await (t, al, ar)
        return SearchResults(tracks: tv, albums: av, artists: arv)
    }

    // MARK: - Decoding

    private struct BackendSearchResponse: Decodable {
        let tracks: [BackendTrack]
        let albums: [BackendAlbum]
        let artists: [BackendArtist]
    }

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

    private struct BackendAlbum: Decodable {
        let itunesCollectionId: Int
        let name: String
        let artistName: String
        let artistId: Int?
        let artworkUrl: String?
        let trackCount: Int?
        let releaseDate: String?
    }

    private struct BackendArtist: Decodable {
        let itunesArtistId: Int
        let name: String
        let primaryGenre: String?
        let artistLinkUrl: String?
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

    private func mapAlbum(_ b: BackendAlbum) -> Album? {
        Album(
            itunesCollectionId: b.itunesCollectionId,
            name: b.name,
            artistName: b.artistName,
            artistId: b.artistId,
            artworkUrl: b.artworkUrl.flatMap { URL(string: $0) },
            trackCount: b.trackCount,
            releaseDate: nil
        )
    }

    private func mapArtist(_ b: BackendArtist) -> Artist? {
        Artist(
            itunesArtistId: b.itunesArtistId,
            name: b.name,
            primaryGenre: b.primaryGenre,
            artistLinkUrl: b.artistLinkUrl.flatMap { URL(string: $0) }
        )
    }
}
