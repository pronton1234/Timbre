import Foundation

/// SwiftUI-friendly value mirror of the CoreData `PlaylistEntity`.
/// The CoreData entity owns canonical identity; this struct is what views consume.
struct Playlist: Identifiable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var coverArtURL: URL?
    var tracks: [Track]
}
