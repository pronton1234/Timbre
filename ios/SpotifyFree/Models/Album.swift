import Foundation

struct Album: Identifiable, Hashable, Codable {
    let itunesCollectionId: Int
    let name: String
    let artistName: String
    let artistId: Int?
    let artworkUrl: URL?
    let trackCount: Int?
    let releaseDate: Date?

    var id: Int { itunesCollectionId }
}
