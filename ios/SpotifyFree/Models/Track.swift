import Foundation

/// Immutable value type representing a track returned from the iTunes Search API.
/// The app's runtime identity for a song is the iTunes trackId (stable, non-paid).
/// `isrc` is preferred for backend resolution when present.
struct Track: Identifiable, Hashable, Codable {
    let itunesTrackId: Int
    let isrc: String?
    let name: String
    let artistName: String
    let artistId: Int?
    let albumName: String?
    let albumId: Int?
    let durationMs: Int
    let artworkUrl: URL?
    let previewUrl: URL?
    /// Known YouTube videoId — set for YouTube Music results so the resolve step can be skipped.
    let videoId: String?

    var id: Int { itunesTrackId }

    init(
        itunesTrackId: Int,
        isrc: String? = nil,
        name: String,
        artistName: String,
        artistId: Int? = nil,
        albumName: String? = nil,
        albumId: Int? = nil,
        durationMs: Int,
        artworkUrl: URL? = nil,
        previewUrl: URL? = nil,
        videoId: String? = nil
    ) {
        self.itunesTrackId = itunesTrackId
        self.isrc = isrc
        self.name = name
        self.artistName = artistName
        self.artistId = artistId
        self.albumName = albumName
        self.albumId = albumId
        self.durationMs = durationMs
        self.artworkUrl = artworkUrl
        self.previewUrl = previewUrl
        self.videoId = videoId
    }
}
