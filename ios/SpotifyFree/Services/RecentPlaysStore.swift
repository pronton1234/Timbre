import Foundation
import Combine

// MARK: - RecentContext

/// A recently-played context tile: the album, playlist, artist, or search session
/// from which a track was started. Home shows these tiles, not raw tracks.
struct RecentContext: Identifiable, Codable {
    let id: UUID
    let kind: Kind
    let playedAt: Date

    enum Kind: Codable {
        case album(Album)
        case playlist(id: UUID, name: String, artworkURL: URL?)
        case artistTopTracks(Artist)
        case search(Track)   // single track played from search — show the track

        // MARK: Custom Codable

        private enum Tag: String, Codable { case album, playlist, artistTopTracks, search }

        private enum CodingKeys: String, CodingKey {
            case tag, album, artist, playlistId, playlistName, playlistArtworkURL, track
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .album(let a):
                try c.encode(Tag.album, forKey: .tag)
                try c.encode(a, forKey: .album)
            case .playlist(let id, let name, let url):
                try c.encode(Tag.playlist, forKey: .tag)
                try c.encode(id, forKey: .playlistId)
                try c.encode(name, forKey: .playlistName)
                try c.encodeIfPresent(url, forKey: .playlistArtworkURL)
            case .artistTopTracks(let ar):
                try c.encode(Tag.artistTopTracks, forKey: .tag)
                try c.encode(ar, forKey: .artist)
            case .search(let t):
                try c.encode(Tag.search, forKey: .tag)
                try c.encode(t, forKey: .track)
            }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let tag = try c.decode(Tag.self, forKey: .tag)
            switch tag {
            case .album:
                self = .album(try c.decode(Album.self, forKey: .album))
            case .playlist:
                let id = try c.decode(UUID.self, forKey: .playlistId)
                let name = try c.decode(String.self, forKey: .playlistName)
                let url = try c.decodeIfPresent(URL.self, forKey: .playlistArtworkURL)
                self = .playlist(id: id, name: name, artworkURL: url)
            case .artistTopTracks:
                self = .artistTopTracks(try c.decode(Artist.self, forKey: .artist))
            case .search:
                self = .search(try c.decode(Track.self, forKey: .track))
            }
        }
    }

    var title: String {
        switch kind {
        case .album(let a):             return a.name
        case .playlist(_, let n, _):   return n
        case .artistTopTracks(let ar): return ar.name
        case .search(let t):           return t.name
        }
    }

    var subtitle: String {
        switch kind {
        case .album(let a):             return a.artistName
        case .playlist:                return "Playlist"
        case .artistTopTracks(let ar): return ar.primaryGenre ?? "Artist"
        case .search(let t):           return t.artistName
        }
    }

    var artworkURL: URL? {
        switch kind {
        case .album(let a):            return a.artworkUrl
        case .playlist(_, _, let u):  return u
        case .artistTopTracks:         return nil
        case .search(let t):           return t.artworkUrl
        }
    }
}

// MARK: - RecentPlaysStore

/// Tracks the last 20 played contexts (push-to-front, dedupe by context identity).
/// Persisted to UserDefaults as JSON. Home view reads `contexts` to populate tiles.
@MainActor
final class RecentPlaysStore: ObservableObject {
    static let shared = RecentPlaysStore()

    @Published private(set) var contexts: [RecentContext] = []

    private let key = "recentPlaysStore.v2"
    private let capacity = 20

    private init() {
        restore()
    }

    func recordPlay(_ track: Track, context: PlaybackContext?) {
        let kind: RecentContext.Kind
        if let ctx = context {
            switch ctx.kind {
            case .album(let a):               kind = .album(a)
            case .playlist(let id, let name): kind = .playlist(id: id, name: name, artworkURL: ctx.originalOrder.first?.artworkUrl)
            case .artistTopTracks(let ar):    kind = .artistTopTracks(ar)
            case .search:                     kind = .search(track)
            }
        } else {
            kind = .search(track)
        }
        let entry = RecentContext(id: UUID(), kind: kind, playedAt: Date())
        // Deduplicate by context identity (not play instance id)
        contexts.removeAll { existing in
            switch (existing.kind, entry.kind) {
            case (.album(let a1), .album(let a2)):                      return a1.id == a2.id
            case (.playlist(let i1, _, _), .playlist(let i2, _, _)):   return i1 == i2
            case (.artistTopTracks(let a1), .artistTopTracks(let a2)): return a1.id == a2.id
            case (.search(let t1), .search(let t2)):                   return t1.id == t2.id
            default:                                                    return false
            }
        }
        contexts.insert(entry, at: 0)
        if contexts.count > capacity { contexts = Array(contexts.prefix(capacity)) }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(contexts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([RecentContext].self, from: data)
        else { return }
        contexts = decoded
    }
}
