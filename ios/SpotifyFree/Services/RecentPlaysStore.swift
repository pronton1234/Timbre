import Foundation
import Combine

/// Tracks the last N played tracks (push-to-front, dedupe by id, cap 20).
/// Persisted to UserDefaults as JSON. Home view reads `items` to populate
/// its "Recently Played" carousel.
@MainActor
final class RecentPlaysStore: ObservableObject {
    static let shared = RecentPlaysStore()

    @Published private(set) var items: [Track] = []

    private let key = "recentPlaysStore.v1"
    private let capacity = 20

    private init() {
        restore()
    }

    func recordPlay(_ track: Track) {
        items.removeAll { $0.id == track.id }
        items.insert(track, at: 0)
        if items.count > capacity { items = Array(items.prefix(capacity)) }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Track].self, from: data)
        else { return }
        items = decoded
    }
}
