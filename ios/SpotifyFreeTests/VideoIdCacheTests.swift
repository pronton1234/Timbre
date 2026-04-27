import XCTest
@testable import SpotifyFree

final class VideoIdCacheTests: XCTestCase {

    override func setUp() async throws {
        await VideoIdCache.shared.reset()
    }

    // MARK: - Basic correctness

    func testGetReturnsNilForUnknownId() async {
        let result = await VideoIdCache.shared.get(99999)
        XCTAssertNil(result)
    }

    func testSetAndGetRoundTrip() async {
        await VideoIdCache.shared.set(1234, videoId: "dQw4w9WgXcQ")
        let result = await VideoIdCache.shared.get(1234)
        XCTAssertEqual(result, "dQw4w9WgXcQ")
    }

    func testUpdateExistingEntryDoesNotDuplicate() async {
        await VideoIdCache.shared.set(1, videoId: "aaa")
        await VideoIdCache.shared.set(2, videoId: "bbb")
        await VideoIdCache.shared.set(1, videoId: "ccc")
        let val1 = await VideoIdCache.shared.get(1)
        let val2 = await VideoIdCache.shared.get(2)
        XCTAssertEqual(val1, "ccc")
        XCTAssertEqual(val2, "bbb")
    }

    // MARK: - Capacity & eviction

    func testCapacityEvictsOldestEntry() async {
        for i in 0..<2001 {
            await VideoIdCache.shared.set(i, videoId: "vid\(i)")
        }
        let evicted = await VideoIdCache.shared.get(0)
        let newest = await VideoIdCache.shared.get(2000)
        XCTAssertNil(evicted, "Oldest entry must be evicted when capacity exceeded")
        XCTAssertEqual(newest, "vid2000")
    }

    func testCapacityIsEnforcedAfterEviction() async {
        for i in 0..<2010 {
            await VideoIdCache.shared.set(i, videoId: "v\(i)")
        }
        for i in 0..<10 {
            let val = await VideoIdCache.shared.get(i)
            XCTAssertNil(val, "Entry \(i) should have been evicted")
        }
        for i in 10..<2010 {
            let val = await VideoIdCache.shared.get(i)
            XCTAssertNotNil(val, "Entry \(i) should still be present")
        }
    }

    // MARK: - Persistence

    func testPersistenceAcrossResets() async {
        await VideoIdCache.shared.set(555, videoId: "persistedVid")
        let before = await VideoIdCache.shared.get(555)
        XCTAssertEqual(before, "persistedVid")

        await VideoIdCache.shared.reset()
        let after = await VideoIdCache.shared.get(555)
        XCTAssertNil(after, "Reset must clear disk too")
    }

    func testEmptyDiskLoadDoesNotCrash() async {
        let result = await VideoIdCache.shared.get(1)
        XCTAssertNil(result)
    }

    // MARK: - Performance

    func testHundredGetsCompleteUnder10ms() async throws {
        for i in 0..<100 {
            await VideoIdCache.shared.set(i, videoId: "vid\(i)")
        }
        let start = ContinuousClock.now
        for i in 0..<100 {
            _ = await VideoIdCache.shared.get(i)
        }
        let elapsed = ContinuousClock.now - start
        let ns = elapsed.components.attoseconds / 1_000_000_000
        let totalMs = Double(elapsed.components.seconds * 1000) + Double(ns) / 1_000_000.0
        XCTAssertLessThan(totalMs, 10.0, "100 cache gets must complete in under 10ms")
    }
}
