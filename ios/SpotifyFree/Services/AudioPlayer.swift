import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit

// MARK: - Resolver protocols (used for dependency injection in tests)

protocol VideoIdResolving: Sendable {
    /// Fetch a YouTube videoId for the given track via network (no caching at this layer).
    func resolveVideoId(for track: Track) async throws -> String
}

protocol StreamURLResolving: Sendable {
    func resolveURL(videoId: String, bypassCache: Bool) async throws -> URL
}

// MARK: - Default implementations

/// Calls the backend directly. VideoIdCache is checked upstream in AudioPlayer.
private struct DefaultVideoIdResolver: VideoIdResolving {
    func resolveVideoId(for track: Track) async throws -> String {
        let matched = try await BackendClient.shared.matchVideoId(track: track)
        return matched.videoId
    }
}

/// Thin wrapper so StreamResolver (actor) conforms to StreamURLResolving.
private struct DefaultStreamResolver: StreamURLResolving {
    func resolveURL(videoId: String, bypassCache: Bool) async throws -> URL {
        try await StreamResolver.shared.resolveURL(videoId: videoId, bypassCache: bypassCache)
    }
}

// MARK: - AudioPlayer

/// Single long-lived `AVQueuePlayer` — using the queue variant lets us
/// preroll the next track's `AVPlayerItem` ahead of time for ~0ms skip latency.
@MainActor
final class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()

    // MARK: - Published state

    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isBuffering: Bool = false

    // MARK: - Internals

    private let player = AVQueuePlayer()
    private var currentVideoId: String?
    private var periodicObserver: Any?
    private var statusObs: AnyCancellable?
    private var endObs: AnyCancellable?
    private var stallObs: AnyCancellable?
    private var bufferEmptyObs: AnyCancellable?
    private var bufferReadyObs: AnyCancellable?
    private struct PrewarmedItem {
        let trackId: Int
        let videoId: String
        let item: AVPlayerItem
    }
    /// FIFO prewarm cache, capacity 5. Oldest entry evicted when full.
    private var prewarmCache: [Int: PrewarmedItem] = [:]
    private var prewarmOrder: [Int] = []
    private let maxPrewarmedItems = 5

    private var trackDurationSeconds: TimeInterval = 0
    /// Loaders we've attached to AVURLAssets via custom URL scheme. Keyed by
    /// videoId; we keep a strong reference so they live as long as their asset.
    private var loaders: [String: HybridStreamLoader] = [:]
    private let loaderQueue = DispatchQueue(label: "com.spotifyfree.HybridStreamLoader")

    // MARK: - Position persistence (1.5)
    private let positionKey = "audioPlayer.savedPosition.v1"
    private struct SavedPosition: Codable {
        let trackId: Int
        let seconds: TimeInterval
    }

    private let videoIdResolver: VideoIdResolving
    private let streamResolver: StreamURLResolving

    // MARK: - Init

    private convenience init() {
        self.init(videoIdResolver: DefaultVideoIdResolver(), streamResolver: DefaultStreamResolver())
    }

    init(videoIdResolver: VideoIdResolving, streamResolver: StreamURLResolving) {
        self.videoIdResolver = videoIdResolver
        self.streamResolver = streamResolver
        player.automaticallyWaitsToMinimizeStalling = false
        registerRemoteCommands()
        observePlayer()
    }

    // MARK: - Public API

    func play(_ track: Track, context: PlaybackContext? = nil) async {
        let t0 = Date()
        print("[AP.play] ▶︎ track=\"\(track.name)\" by \"\(track.artistName)\" id=\(track.itunesTrackId) videoId=\(track.videoId ?? "nil")")
        RecentPlaysStore.shared.recordPlay(track, context: context ?? QueueManager.shared.context)
        clearSavedPosition()

        // Hot path: use pre-warmed AVPlayerItem from the 5-slot cache.
        if let pw = prewarmCache[track.itunesTrackId] {
            print("[AP.play] cache hit prewarm trackId=\(track.itunesTrackId)")
            if let current = player.currentItem, current === pw.item {
                currentTrack = track
                currentVideoId = pw.videoId
                removeFromPrewarmCache(trackId: track.itunesTrackId)
                trackDurationSeconds = TimeInterval(track.durationMs) / 1000.0
                duration = trackDurationSeconds
                observeCurrentItem()
                if player.timeControlStatus != .playing { player.play() }
                updateNowPlayingInfo()
                PersistenceController.shared.recordPlayed(track)
                return
            }
            player.removeAllItems()
            player.insert(pw.item, after: nil)
            currentTrack = track
            currentVideoId = pw.videoId
            removeFromPrewarmCache(trackId: track.itunesTrackId)
            trackDurationSeconds = TimeInterval(track.durationMs) / 1000.0
            duration = trackDurationSeconds
            observeCurrentItem()
            player.play()
            updateNowPlayingInfo()
            PersistenceController.shared.recordPlayed(track)
            return
        }

        do {
            let videoId = try await resolveVideoId(for: track)
            print("[AP.play] resolved videoId=\(videoId) in \(Int(Date().timeIntervalSince(t0)*1000))ms")
            let url = try await streamResolver.resolveURL(videoId: videoId, bypassCache: false)
            print("[AP.play] resolved streamURL host=\(url.host ?? "?") in \(Int(Date().timeIntervalSince(t0)*1000))ms total")
            let item = makeDirectPlayerItem(url: url)
            player.removeAllItems()
            player.insert(item, after: nil)
            currentTrack = track
            currentVideoId = videoId
            trackDurationSeconds = TimeInterval(track.durationMs) / 1000.0
            duration = trackDurationSeconds
            observeCurrentItem()
            player.play()
            print("[AP.play] player.play() called; status=\(player.timeControlStatus.rawValue) item.status=\(item.status.rawValue)")
            updateNowPlayingInfo()
            PersistenceController.shared.recordPlayed(track)
        } catch {
            print("[AP.play] FAILED: \(error)")
        }
    }

    func prewarm(_ track: Track) async {
        if prewarmCache[track.itunesTrackId] != nil { return }
        do {
            let videoId = try await resolveVideoId(for: track)
            let url = try await streamResolver.resolveURL(videoId: videoId, bypassCache: false)
            let item = makeDirectPlayerItem(url: url)
            addToPrewarmCache(PrewarmedItem(trackId: track.itunesTrackId, videoId: videoId, item: item))
            if player.canInsert(item, after: nil) {
                player.insert(item, after: nil)
            }
            print("[AP.prewarm] cached track=\"\(track.name)\" videoId=\(videoId)")
        } catch {
            print("[AP.prewarm] FAILED for \"\(track.name)\": \(error)")
        }
    }

    /// Direct AVURLAsset for a googlevideo URL. AVPlayer handles HTTP range
    /// streaming natively — no custom resource loader required.
    private func makeDirectPlayerItem(url: URL) -> AVPlayerItem {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 1.5
        return item
    }

    /// Remove cache entries whose trackIds are not in `keepIds`, and pull their
    /// items out of AVQueuePlayer. Called by QueueManager on queue mutations.
    func evictPrewarm(retaining keepIds: Set<Int>) {
        let stale = prewarmOrder.filter { !keepIds.contains($0) }
        for id in stale {
            if let pw = prewarmCache[id] { player.remove(pw.item) }
            prewarmCache.removeValue(forKey: id)
        }
        prewarmOrder = prewarmOrder.filter { keepIds.contains($0) }
    }

    // MARK: - Prewarm cache internals

    private func addToPrewarmCache(_ pw: PrewarmedItem) {
        if prewarmCache[pw.trackId] != nil { return }  // already cached
        if prewarmCache.count >= maxPrewarmedItems, let oldest = prewarmOrder.first {
            if let old = prewarmCache[oldest] { player.remove(old.item) }
            prewarmCache.removeValue(forKey: oldest)
            prewarmOrder.removeFirst()
        }
        prewarmCache[pw.trackId] = pw
        prewarmOrder.append(pw.trackId)
    }

    private func removeFromPrewarmCache(trackId: Int) {
        prewarmCache.removeValue(forKey: trackId)
        prewarmOrder.removeAll { $0 == trackId }
    }

    /// Build an `AVPlayerItem` whose asset routes through HybridStreamLoader.
    /// AVPlayer never sees the googlevideo URL directly — first chunk goes
    /// through backend `/play`, subsequent chunks go to googlevideo via the
    /// loader. See `HybridStreamLoader` for the full handoff design.
    private func makeHybridPlayerItem(videoId: String, track: Track? = nil) -> AVPlayerItem {
        let backend = backendBaseURL()
        let resolver = self.streamResolver
        let meta: HybridStreamLoader.TrackMeta? = track.map {
            HybridStreamLoader.TrackMeta(
                itunesTrackId: $0.itunesTrackId,
                title: $0.name,
                artist: $0.artistName,
                isrc: $0.isrc
            )
        }
        let (asset, loader) = HybridStreamLoader.makeAsset(
            videoId: videoId,
            backendBaseURL: backend,
            delegateQueue: loaderQueue,
            trackMeta: meta,
            onDeviceFallback: { videoId in
                try await resolver.resolveURL(videoId: videoId, bypassCache: false)
            }
        )
        loaders[videoId] = loader
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 1.5
        return item
    }

    private func backendBaseURL() -> URL {
        let fromPlist = Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_FREE_BACKEND_URL") as? String
        let raw = (fromPlist?.isEmpty == false ? fromPlist! : "http://localhost:3000")
        return URL(string: raw) ?? URL(string: "http://localhost:3000")!
    }

    func resume() { player.play(); isPlaying = true; updateNowPlayingInfo() }
    func pause() { player.pause(); isPlaying = false; updateNowPlayingInfo() }
    func togglePlayPause() { isPlaying ? pause() : resume() }

    // MARK: - Position persistence (1.5)

    /// Persist current (trackId, position) so the next launch can restore it.
    func savePositionNow() {
        guard let track = currentTrack else { return }
        let saved = SavedPosition(trackId: track.itunesTrackId, seconds: position)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: positionKey)
        }
    }

    private func clearSavedPosition() {
        UserDefaults.standard.removeObject(forKey: positionKey)
    }

    /// Restore saved playback position after queue is loaded. Player stays paused.
    func restorePosition() {
        guard
            let data = UserDefaults.standard.data(forKey: positionKey),
            let saved = try? JSONDecoder().decode(SavedPosition.self, from: data),
            let track = currentTrack,
            track.itunesTrackId == saved.trackId,
            saved.seconds > 0
        else { return }
        let target = CMTime(seconds: saved.seconds, preferredTimescale: 1000)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in }
        clearSavedPosition()
    }

    func restart() {
        position = 0
        let zero = CMTime.zero
        player.seek(to: zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.player.play()
                self?.isPlaying = true
                self?.updateNowPlayingInfo()
            }
        }
    }

    func seek(to seconds: TimeInterval) {
        let clamped = max(0, min(seconds, max(duration, 0)))
        position = clamped
        let target = CMTime(seconds: clamped, preferredTimescale: 1000)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.updateNowPlayingInfo() }
        }
    }

    // MARK: - Resolution (VideoIdCache → resolver → cache write)

    /// Return the videoId for a track: known > cached > resolved.
    /// If `track.videoId` is already set (YouTube Music search result), it's used
    /// directly and also stored in the cache for future prewarms.
    private func resolveVideoId(for track: Track) async throws -> String {
        if let knownId = track.videoId {
            print("[AP.resolveVideoId] using known videoId=\(knownId) (from track)")
            await VideoIdCache.shared.set(track.itunesTrackId, videoId: knownId)
            return knownId
        }
        if let cached = await VideoIdCache.shared.get(track.itunesTrackId) {
            print("[AP.resolveVideoId] cache hit videoId=\(cached)")
            return cached
        }
        print("[AP.resolveVideoId] cache miss → backend resolve for trackId=\(track.itunesTrackId)")
        let t0 = Date()
        let videoId = try await videoIdResolver.resolveVideoId(for: track)
        print("[AP.resolveVideoId] backend returned videoId=\(videoId) in \(Int(Date().timeIntervalSince(t0)*1000))ms")
        await VideoIdCache.shared.set(track.itunesTrackId, videoId: videoId)
        return videoId
    }

    // MARK: - Observers

    private var positionSaveCounter = 0

    private func observePlayer() {
        periodicObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 1000), queue: .main
        ) { [weak self] t in
            Task { @MainActor in
                guard let self else { return }
                self.position = t.seconds
                if self.trackDurationSeconds > 0 {
                    self.duration = self.trackDurationSeconds
                } else if let item = self.player.currentItem {
                    let d = item.duration.seconds
                    self.duration = (d.isFinite && d > 0) ? d : 0
                }
                // Save position every 5s (10 × 0.5s ticks) while playing.
                self.positionSaveCounter += 1
                if self.positionSaveCounter >= 10 {
                    self.positionSaveCounter = 0
                    if self.isPlaying { self.savePositionNow() }
                }
            }
        }

        stallObs = NotificationCenter.default
            .publisher(for: AVPlayerItem.playbackStalledNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.isBuffering = true
                self?.handlePossibleStreamExpiry()
            }

        NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handlePossibleStreamExpiry() }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    private func observeCurrentItem() {
        guard let item = player.currentItem else { return }
        bufferEmptyObs = item.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: RunLoop.main)
            .sink { [weak self] empty in
                self?.isBuffering = empty
                if empty { print("[AP.item] bufferEmpty=true") }
            }
        bufferReadyObs = item.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: RunLoop.main)
            .sink { [weak self] ready in
                if ready {
                    self?.isBuffering = false
                    print("[AP.item] likelyToKeepUp=true")
                }
            }
        statusObs = item.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { status in
                print("[AP.item] status=\(status.rawValue) (0=unknown,1=ready,2=failed) error=\(item.error?.localizedDescription ?? "nil")")
            }
        endObs = NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                print("[AP.item] didPlayToEndTime")
                Task { await QueueManager.shared.advance() }
                self?.updateNowPlayingInfo()
            }
    }

    private func handlePossibleStreamExpiry() {
        guard let videoId = currentVideoId, let item = player.currentItem else { return }
        if let err = item.error as NSError? {
            let refreshableCodes: Set<Int> = [-11828, -11829, -1001, -1009]
            if !refreshableCodes.contains(err.code) { return }
            print("[AP.expiry] refreshing stream for videoId=\(videoId) err=\(err.code)")
        } else {
            print("[AP.expiry] stall detected, refreshing stream for videoId=\(videoId)")
        }
        let offset = player.currentTime().seconds
        Task { [weak self] in
            guard let self else { return }
            await StreamResolver.shared.invalidate(videoId: videoId)
            self.loaders.removeValue(forKey: videoId)
            do {
                let url = try await self.streamResolver.resolveURL(videoId: videoId, bypassCache: true)
                let new = self.makeDirectPlayerItem(url: url)
                self.player.removeAllItems()
                self.player.insert(new, after: nil)
                self.observeCurrentItem()
                self.player.seek(to: CMTime(seconds: offset, preferredTimescale: 1000)) { _ in }
                self.player.play()
            } catch {
                print("[AP.expiry] FAILED to refresh: \(error)")
            }
        }
    }

    // MARK: - Now Playing / remote controls

    private func registerRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlayPause(); return .success }
        c.nextTrackCommand.addTarget { _ in
            Task { await QueueManager.shared.advance(manual: true) }
            return .success
        }
        c.previousTrackCommand.addTarget { _ in
            Task { await QueueManager.shared.previous() }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: e.positionTime)
            return .success
        }
        c.skipForwardCommand.preferredIntervals = [15]
        c.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.seek(to: self.position + 15); return .success
        }
        c.skipBackwardCommand.preferredIntervals = [15]
        c.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.seek(to: max(0, self.position - 15)); return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: track.name,
            MPMediaItemPropertyArtist: track.artistName,
            MPMediaItemPropertyAlbumTitle: track.albumName ?? "",
            MPMediaItemPropertyPlaybackDuration: TimeInterval(track.durationMs) / 1000.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let art = track.artworkUrl {
            Task.detached {
                if let data = try? Data(contentsOf: art),
                   let img = UIImage(data: data) {
                    let artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                    await MainActor.run {
                        var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                        updated[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
                    }
                }
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        isPlaying = player.timeControlStatus == .playing
    }
}
