import XCTest
@testable import SpotifyFree

/// These tests exercise `QueueManager` in isolation — no real network or AVPlayer.
/// `QueueManager.shared` calls `AudioPlayer.shared.play`, which in turn hits
/// `BackendClient.resolve` — for these tests we only assert state before the
/// `Task { await startCurrent() }` network actually completes.
@MainActor
final class QueueManagerTests: XCTestCase {

    private func makeTrack(_ id: Int) -> Track {
        Track(itunesTrackId: id, name: "T\(id)", artistName: "A", durationMs: 180_000)
    }

    override func setUp() async throws {
        // Clean previously-persisted queue state between tests
        UserDefaults.standard.removeObject(forKey: "queueManager.state.v1")
        QueueManager.shared.queue = []
        QueueManager.shared.currentIndex = -1
        QueueManager.shared.shuffleOn = false
        QueueManager.shared.repeatMode = .off
    }

    func testPlayNextInsertsAfterCurrent() {
        let m = QueueManager.shared
        m.queue = [QueueItem(makeTrack(1)), QueueItem(makeTrack(2))]
        m.currentIndex = 0
        m.playNext(makeTrack(3))
        XCTAssertEqual(m.queue.map(\.track.itunesTrackId), [1, 3, 2])
    }

    func testAddToQueueAppends() {
        let m = QueueManager.shared
        m.queue = [QueueItem(makeTrack(1))]
        m.currentIndex = 0
        m.addToQueue(makeTrack(2))
        XCTAssertEqual(m.queue.map(\.track.itunesTrackId), [1, 2])
    }

    func testMovePreservesCurrentlyPlaying() {
        let m = QueueManager.shared
        m.queue = [QueueItem(makeTrack(1)), QueueItem(makeTrack(2)), QueueItem(makeTrack(3))]
        m.currentIndex = 1
        m.move(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(m.queue.map(\.track.itunesTrackId), [3, 1, 2])
        XCTAssertEqual(m.currentIndex, 2, "current index should still refer to original track (now at position 2)")
    }

    func testRemoveFixesCurrentIndex() {
        let m = QueueManager.shared
        m.queue = [QueueItem(makeTrack(1)), QueueItem(makeTrack(2)), QueueItem(makeTrack(3))]
        m.currentIndex = 2
        m.remove(atOffsets: IndexSet(integer: 0))
        XCTAssertEqual(m.currentIndex, 1)
    }

    func testAdvanceWrapsWhenRepeatAll() async {
        let m = QueueManager.shared
        m.queue = [QueueItem(makeTrack(1)), QueueItem(makeTrack(2))]
        m.currentIndex = 1
        m.repeatMode = .all
        await m.advance()
        XCTAssertEqual(m.currentIndex, 0)
    }

    func testAdvanceStopsWhenRepeatOff() async {
        let m = QueueManager.shared
        m.queue = [QueueItem(makeTrack(1)), QueueItem(makeTrack(2))]
        m.currentIndex = 1
        m.repeatMode = .off
        await m.advance()
        XCTAssertEqual(m.currentIndex, 1)
    }

    func testShufflePreservesCurrent() {
        let m = QueueManager.shared
        m.queue = (1...20).map { QueueItem(makeTrack($0)) }
        m.currentIndex = 7
        let currentTrackId = m.queue[m.currentIndex].track.itunesTrackId
        m.toggleShuffle()
        XCTAssertEqual(m.queue[m.currentIndex].track.itunesTrackId, currentTrackId)
        XCTAssertEqual(m.currentIndex, 0)
    }
}
