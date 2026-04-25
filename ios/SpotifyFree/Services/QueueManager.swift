import Foundation
import Combine

/// Owns the playback queue and implements next-track pre-resolve.
/// When the user starts a track, we immediately tell `AudioPlayer` to prewarm
/// the *next* track in the queue so skipping is effectively instant.
@MainActor
final class QueueManager: ObservableObject {
    static let shared = QueueManager()

    @Published var queue: [QueueItem] = []
    @Published var currentIndex: Int = -1
    @Published var shuffleOn: Bool = false
    @Published var repeatMode: RepeatMode = .off

    private let persistenceKey = "queueManager.state.v1"

    private init() {
        restoreFromDisk()
    }

    // MARK: - Queue mutations

    /// Replace queue with `tracks`, start playback at index 0.
    func playNow(_ tracks: [Track], startAt: Int = 0) async {
        queue = tracks.map { QueueItem($0) }
        currentIndex = max(0, min(startAt, queue.count - 1))
        await startCurrent()
    }

    /// Insert a track to play next — right after the current one.
    /// If nothing is playing yet, seed the queue and start at index 0 so the
    /// track begins playing immediately.
    func addToQueue(_ track: Track) {
        let item = QueueItem(track)
        if queue.isEmpty {
            queue = [item]
            currentIndex = 0
            persist()
            Task { await startCurrent() }
            return
        }
        let idx = max(0, currentIndex) + 1
        if idx >= queue.count { queue.append(item) }
        else { queue.insert(item, at: idx) }
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        let current = currentIndex >= 0 ? queue[currentIndex].id : nil
        queue.move(fromOffsets: source, toOffset: destination)
        if let id = current, let newIdx = queue.firstIndex(where: { $0.id == id }) {
            currentIndex = newIdx
        }
        persist()
    }

    func remove(atOffsets offsets: IndexSet) {
        let currentId = currentIndex >= 0 ? queue[currentIndex].id : nil
        queue.remove(atOffsets: offsets)
        if let id = currentId, let newIdx = queue.firstIndex(where: { $0.id == id }) {
            currentIndex = newIdx
        } else {
            currentIndex = min(currentIndex, queue.count - 1)
        }
        persist()
    }

    // MARK: - Transport

    func advance(manual: Bool = false) async {
        guard !queue.isEmpty else { return }
        // Repeat-one (non-manual end-of-track): just rewind the current
        // AVPlayerItem. Avoids re-resolving the stream or colliding with the
        // prewarmed-item buffer.
        if repeatMode == .one && !manual {
            AudioPlayer.shared.restart()
            return
        }
        let next = currentIndex + 1
        if next >= queue.count {
            if repeatMode == .all { currentIndex = 0 }
            else { return }
        } else {
            currentIndex = next
        }
        await startCurrent()
    }

    func previous() async {
        guard !queue.isEmpty else { return }
        // Match Spotify: if >3s into track, restart it; else go back
        let pos = AudioPlayer.shared.position
        if pos > 3 { AudioPlayer.shared.seek(to: 0); return }
        if currentIndex > 0 { currentIndex -= 1 }
        await startCurrent()
    }

    func jump(to index: Int) async {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        await startCurrent()
    }

    // MARK: - Shuffle / repeat

    func toggleShuffle() {
        shuffleOn.toggle()
        guard shuffleOn, !queue.isEmpty, currentIndex >= 0 else { persist(); return }
        // Keep currently-playing track in place; shuffle the rest
        let currentItem = queue[currentIndex]
        var rest = queue
        rest.remove(at: currentIndex)
        rest.shuffle()
        queue = [currentItem] + rest
        currentIndex = 0
        persist()
    }

    func cycleRepeatMode() {
        repeatMode = {
            switch repeatMode {
            case .off: return .all
            case .all: return .one
            case .one: return .off
            }
        }()
        persist()
    }

    // MARK: - Internals

    private func startCurrent() async {
        guard queue.indices.contains(currentIndex) else { return }
        let track = queue[currentIndex].track
        await AudioPlayer.shared.play(track)
        persist()
        // Kick off next-track pre-resolve + AVPlayer pre-warm
        let nextIdx = currentIndex + 1
        if queue.indices.contains(nextIdx) {
            let nextTrack = queue[nextIdx].track
            Task { await AudioPlayer.shared.prewarm(nextTrack) }
        }
    }

    // MARK: - Persistence (UserDefaults)

    private struct Snapshot: Codable {
        let queue: [QueueItem]
        let currentIndex: Int
        let shuffleOn: Bool
        let repeatMode: RepeatMode
    }

    private func persist() {
        let snap = Snapshot(queue: queue, currentIndex: currentIndex, shuffleOn: shuffleOn, repeatMode: repeatMode)
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }

    private func restoreFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        queue = snap.queue
        currentIndex = snap.currentIndex
        shuffleOn = snap.shuffleOn
        repeatMode = snap.repeatMode
    }
}
