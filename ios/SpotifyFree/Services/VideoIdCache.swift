import Foundation

/// Persistent on-device cache: iTunes trackId → YouTube videoId.
///
/// VideoIds never expire (they are permanent YouTube identifiers), so there is
/// no TTL. The cache holds up to 2000 entries; oldest-inserted entries are
/// evicted first when capacity is exceeded.
///
/// Backed by UserDefaults so it survives app restarts. At ~20 bytes/entry the
/// maximum footprint is ~40KB — well within UserDefaults limits.
actor VideoIdCache {
    static let shared = VideoIdCache()

    private let capacity = 2000
    private let udKey = "videoIdCache.v1"

    // Ordered storage: insertionOrder tracks insertion sequence for eviction.
    private var map: [Int: String] = [:]          // trackId → videoId
    private var insertionOrder: [Int] = []        // oldest first

    private init() {
        loadFromDisk()
    }

    func get(_ itunesTrackId: Int) -> String? {
        map[itunesTrackId]
    }

#if DEBUG
    func reset() {
        map.removeAll()
        insertionOrder.removeAll()
        UserDefaults.standard.removeObject(forKey: udKey)
    }
#endif

    func set(_ itunesTrackId: Int, videoId: String) {
        if map[itunesTrackId] != nil {
            // Already present — update in place, don't change insertion order
            map[itunesTrackId] = videoId
        } else {
            map[itunesTrackId] = videoId
            insertionOrder.append(itunesTrackId)
            evictIfNeeded()
        }
        persistToDisk()
    }

    // MARK: - Private

    private func evictIfNeeded() {
        while map.count > capacity, !insertionOrder.isEmpty {
            let oldest = insertionOrder.removeFirst()
            map.removeValue(forKey: oldest)
        }
    }

    private func persistToDisk() {
        // Encode as [[trackId, videoId]] — simple, compact.
        let pairs: [[String]] = insertionOrder.compactMap { id in
            guard let vid = map[id] else { return nil }
            return ["\(id)", vid]
        }
        if let data = try? JSONEncoder().encode(pairs) {
            UserDefaults.standard.set(data, forKey: udKey)
        }
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: udKey),
              let pairs = try? JSONDecoder().decode([[String]].self, from: data) else { return }
        for pair in pairs where pair.count == 2 {
            guard let id = Int(pair[0]) else { continue }
            map[id] = pair[1]
            insertionOrder.append(id)
        }
    }
}
