import Foundation

/// Row in the playback queue. The instance id lets the same track appear
/// multiple times (e.g. user added it twice) without Hashable collisions.
struct QueueItem: Identifiable, Hashable, Codable {
    let id: UUID
    let track: Track

    init(_ track: Track, id: UUID = UUID()) {
        self.id = id
        self.track = track
    }
}

enum RepeatMode: String, Codable, CaseIterable {
    case off
    case all
    case one
}
