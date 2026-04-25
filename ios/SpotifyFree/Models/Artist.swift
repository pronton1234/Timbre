import Foundation

struct Artist: Identifiable, Hashable, Codable {
    let itunesArtistId: Int
    let name: String
    let primaryGenre: String?
    let artistLinkUrl: URL?

    var id: Int { itunesArtistId }
}
