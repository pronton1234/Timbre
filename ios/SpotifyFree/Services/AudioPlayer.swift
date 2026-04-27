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
    private var prewarmed: (trackId: Int, item: AVPlayerItem, videoId: String)?
    private var trackDurationSeconds: TimeInterval = 0

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

    func play(_ track: Track) async {
        RecentPlaysStore.shared.recordPlay(track)
        // Hot path: use pre-warmed AVPlayerItem
        if let pw = prewarmed, pw.trackId == track.itunesTrackId {
            if let current = player.currentItem, current === pw.item {
                currentTrack = track
                currentVideoId = pw.videoId
                prewarmed = nil
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
            prewarmed = nil
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
            let streamUrl = try await streamResolver.resolveURL(videoId: videoId, bypassCache: false)
            let item = AVPlayerItem(asset: AVURLAsset(url: streamUrl))
            item.preferredForwardBufferDuration = 5
            player.removeAllItems()
            player.insert(item, after: nil)
            currentTrack = track
            currentVideoId = videoId
            trackDurationSeconds = TimeInterval(track.durationMs) / 1000.0
            duration = trackDurationSeconds
            observeCurrentItem()
            player.play()
            updateNowPlayingInfo()
            PersistenceController.shared.recordPlayed(track)
        } catch {
            print("AudioPlayer.play failed: \(error)")
        }
    }

    func prewarm(_ track: Track) async {
        if prewarmed?.trackId == track.itunesTrackId { return }
        do {
            let videoId = try await resolveVideoId(for: track)
            let streamUrl = try await streamResolver.resolveURL(videoId: videoId, bypassCache: false)
            let item = AVPlayerItem(asset: AVURLAsset(url: streamUrl))
            item.preferredForwardBufferDuration = 5
            prewarmed = (track.itunesTrackId, item, videoId)
            if player.canInsert(item, after: nil) {
                player.insert(item, after: nil)
            }
        } catch {
            print("AudioPlayer.prewarm failed: \(error)")
        }
    }

    func resume() { player.play(); isPlaying = true; updateNowPlayingInfo() }
    func pause() { player.pause(); isPlaying = false; updateNowPlayingInfo() }
    func togglePlayPause() { isPlaying ? pause() : resume() }

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

    /// Check on-device VideoIdCache first; only call the injected resolver on a miss.
    /// This ensures the resolver is bypassed for repeat plays — and in tests,
    /// seeding VideoIdCache will prevent mock/real resolvers from being called.
    private func resolveVideoId(for track: Track) async throws -> String {
        if let cached = await VideoIdCache.shared.get(track.itunesTrackId) {
            return cached
        }
        let videoId = try await videoIdResolver.resolveVideoId(for: track)
        await VideoIdCache.shared.set(track.itunesTrackId, videoId: videoId)
        return videoId
    }

    // MARK: - Observers

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
            .sink { [weak self] empty in self?.isBuffering = empty }
        bufferReadyObs = item.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: RunLoop.main)
            .sink { [weak self] ready in if ready { self?.isBuffering = false } }
        endObs = NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { await QueueManager.shared.advance() }
                self?.updateNowPlayingInfo()
            }
    }

    private func handlePossibleStreamExpiry() {
        guard let videoId = currentVideoId, let item = player.currentItem else { return }
        if let err = item.error as NSError? {
            let refreshableCodes: Set<Int> = [-11828, -11829, -1001, -1009]
            if !refreshableCodes.contains(err.code) { return }
        }
        let offset = player.currentTime().seconds
        Task { [weak self] in
            guard let self else { return }
            do {
                let fresh = try await self.streamResolver.resolveURL(videoId: videoId, bypassCache: true)
                let new = AVPlayerItem(asset: AVURLAsset(url: fresh))
                new.preferredForwardBufferDuration = 5
                self.player.removeAllItems()
                self.player.insert(new, after: nil)
                self.observeCurrentItem()
                self.player.seek(to: CMTime(seconds: offset, preferredTimescale: 1000)) { _ in }
                self.player.play()
            } catch {
                print("Stream refresh failed: \(error)")
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
