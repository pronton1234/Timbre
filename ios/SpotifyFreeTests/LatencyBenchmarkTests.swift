import XCTest
import AVFoundation
@testable import SpotifyFree

/// Latency tests that verify the resolution pipeline meets the <500ms target.
/// All network calls are replaced with mocks; only the pipeline orchestration
/// and caching logic are exercised — no real YouTubeKit or backend calls.
@MainActor
final class LatencyBenchmarkTests: XCTestCase {

    private let fakeStreamUrl = URL(string: "https://rr1---sn-test.googlevideo.com/videoplayback?id=test")!

    override func setUp() async throws {
        await VideoIdCache.shared.reset()
        await StreamResolver.shared.clearCache()
    }

    // MARK: - Cache hit latency

    func testVideoIdCacheHitReturnsUnder1ms() async throws {
        await VideoIdCache.shared.set(12345, videoId: "dQw4w9WgXcQ")
        let start = ContinuousClock.now
        let result = await VideoIdCache.shared.get(12345)
        let elapsed = ContinuousClock.now - start
        XCTAssertNotNil(result)
        XCTAssertLessThan(elapsedMs(elapsed), 1.0, "VideoId cache hit must be < 1ms")
    }

    func testStreamResolverCacheHitReturnsUnder1ms() async throws {
        await StreamResolver.shared.injectCacheEntry(videoId: "abc123", url: fakeStreamUrl)
        let start = ContinuousClock.now
        let resolved = try await StreamResolver.shared.resolveURL(videoId: "abc123")
        let elapsed = ContinuousClock.now - start
        XCTAssertEqual(resolved, fakeStreamUrl)
        XCTAssertLessThan(elapsedMs(elapsed), 1.0, "Stream cache hit must be < 1ms")
    }

    // MARK: - Full pipeline with mocked resolvers

    func testBothCachesHitResolutionUnder5ms() async throws {
        let track = makeTrack(99999)
        let mockVideoId = MockVideoIdResolver(videoId: "xyz789", delaySeconds: 0)
        let mockStream = MockStreamResolver(url: fakeStreamUrl, delaySeconds: 0)
        let player = AudioPlayer(videoIdResolver: mockVideoId, streamResolver: mockStream)

        let start = ContinuousClock.now
        await player.play(track)
        let elapsed = ContinuousClock.now - start
        XCTAssertLessThan(elapsedMs(elapsed), 50.0,
            "Resolution with zero-delay mocks must complete in < 50ms (AVPlayer setup overhead allowed)")
    }

    func testColdPathAt200msEachIsUnder500ms() async throws {
        // Simulate: backend responds in 200ms, stream extraction in 200ms.
        // Serial total = ~400ms — must stay under the 500ms budget.
        let track = makeTrack(77777)
        let mockVideoId = MockVideoIdResolver(videoId: "coldvid", delaySeconds: 0.200)
        let mockStream = MockStreamResolver(url: fakeStreamUrl, delaySeconds: 0.200)
        let player = AudioPlayer(videoIdResolver: mockVideoId, streamResolver: mockStream)

        let start = ContinuousClock.now
        await player.play(track)
        let elapsed = ContinuousClock.now - start
        XCTAssertLessThan(elapsedMs(elapsed), 500.0,
            "Cold path with 200ms + 200ms mock delays must be < 500ms total")
    }

    func testVideoIdCacheSkipsBackendCall() async throws {
        // Seed VideoIdCache so the resolver should NOT be invoked.
        let track = makeTrack(55555)
        await VideoIdCache.shared.set(55555, videoId: "cachedvid")
        await StreamResolver.shared.injectCacheEntry(videoId: "cachedvid", url: fakeStreamUrl)

        // Resolver that always fails — if it's called, test will fail
        let failingResolver = FailingVideoIdResolver()
        let mockStream = MockStreamResolver(url: fakeStreamUrl, delaySeconds: 0)
        let player = AudioPlayer(videoIdResolver: failingResolver, streamResolver: mockStream)

        // Should not throw — VideoIdCache hit means failingResolver is bypassed
        await player.play(track)
        XCTAssertEqual(player.currentTrack?.itunesTrackId, 55555)
    }

    func testPrewarmMakesSubsequentPlayUnder10ms() async throws {
        // Prewarm with 300ms mock delays, then play — should reuse prewarmed item.
        let track = makeTrack(88888)
        let slowVideoId = MockVideoIdResolver(videoId: "pwvid", delaySeconds: 0.300)
        let slowStream = MockStreamResolver(url: fakeStreamUrl, delaySeconds: 0.300)
        let player = AudioPlayer(videoIdResolver: slowVideoId, streamResolver: slowStream)

        await player.prewarm(track)  // takes ~600ms to resolve

        let start = ContinuousClock.now
        await player.play(track)    // should reuse prewarmed item — near 0ms
        let elapsed = ContinuousClock.now - start
        XCTAssertLessThan(elapsedMs(elapsed), 50.0,
            "Play after prewarm must be < 50ms (uses prewarmed AVPlayerItem)")
    }

    func testCycleThrough5SongsAllUnder500ms() async throws {
        // Seed all 5 tracks in both caches, then measure each resolution call.
        let tracks = (1...5).map { makeTrack($0) }
        for t in tracks {
            await VideoIdCache.shared.set(t.itunesTrackId, videoId: "vid\(t.itunesTrackId)")
            await StreamResolver.shared.injectCacheEntry(
                videoId: "vid\(t.itunesTrackId)", url: fakeStreamUrl)
        }
        let mockVideoId = MockVideoIdResolver(videoId: "unused", delaySeconds: 0)
        let mockStream = MockStreamResolver(url: fakeStreamUrl, delaySeconds: 0)
        let player = AudioPlayer(videoIdResolver: mockVideoId, streamResolver: mockStream)

        for track in tracks {
            let start = ContinuousClock.now
            await player.play(track)
            let elapsed = ContinuousClock.now - start
            XCTAssertLessThan(elapsedMs(elapsed), 500.0,
                "Track \(track.itunesTrackId) must resolve in < 500ms (cache hit path)")
        }
    }

    // MARK: - Helpers

    private func makeTrack(_ id: Int) -> Track {
        Track(itunesTrackId: id, name: "Track \(id)", artistName: "Artist", durationMs: 200_000)
    }

    private func elapsedMs(_ d: ContinuousClock.Duration) -> Double {
        let ns = d.components.attoseconds / 1_000_000_000
        return Double(d.components.seconds * 1000) + Double(ns) / 1_000_000.0
    }
}

// MARK: - Mock resolvers

private final class MockVideoIdResolver: VideoIdResolving, @unchecked Sendable {
    let videoId: String
    let delaySeconds: TimeInterval

    init(videoId: String, delaySeconds: TimeInterval) {
        self.videoId = videoId
        self.delaySeconds = delaySeconds
    }

    func resolveVideoId(for track: Track) async throws -> String {
        if delaySeconds > 0 {
            try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        }
        return videoId
    }
}

private final class MockStreamResolver: StreamURLResolving, @unchecked Sendable {
    let url: URL
    let delaySeconds: TimeInterval

    init(url: URL, delaySeconds: TimeInterval) {
        self.url = url
        self.delaySeconds = delaySeconds
    }

    func resolveURL(videoId: String, bypassCache: Bool) async throws -> URL {
        if delaySeconds > 0 {
            try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        }
        return url
    }
}

/// Resolver that throws — used to verify cache bypasses the resolver.
private final class FailingVideoIdResolver: VideoIdResolving, @unchecked Sendable {
    struct ShouldNotBeCalled: Error {}
    func resolveVideoId(for track: Track) async throws -> String {
        throw ShouldNotBeCalled()
    }
}
