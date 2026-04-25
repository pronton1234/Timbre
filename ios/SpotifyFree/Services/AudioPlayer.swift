import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit

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
    /// Seconds. Preferred source for UI duration; comes from `Track.durationMs`
    /// (accurate, from iTunes), falling back to `AVPlayerItem.duration` only
    /// when the track-supplied value is missing.
    private var trackDurationSeconds: TimeInterval = 0

    private init() {
        player.automaticallyWaitsToMinimizeStalling = false
        registerRemoteCommands()
        observePlayer()
    }

    // MARK: - Public API

    /// Replace the currently-playing item with a newly-resolved track.
    /// If a pre-warmed item is queued for this trackId, promote it instead of
    /// resolving again — this is the hot path (~0 ms).
    func play(_ track: Track) async {
        RecentPlaysStore.shared.recordPlay(track)
        // Hot path: use pre-warmed AVPlayerItem
        if let pw = prewarmed, pw.trackId == track.itunesTrackId {
            // If the prewarmed item is already the AVQueuePlayer's currentItem
            // (because `prewarm()` inserted it and AVQueuePlayer auto-advanced
            // to it after the previous track ended), don't rebuild the queue —
            // just update bookkeeping and keep playback running.
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
            let matched = try await BackendClient.shared.matchVideoId(track: track)
            let streamUrl = try await StreamResolver.shared.resolveURL(videoId: matched.videoId)
            let item = AVPlayerItem(asset: AVURLAsset(url: streamUrl))
            item.preferredForwardBufferDuration = 5 // start playing ~500ms sooner
            player.removeAllItems()
            player.insert(item, after: nil)
            currentTrack = track
            currentVideoId = matched.videoId
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

    /// Resolve the next track and attach its `AVPlayerItem` to the queue so
    /// `AVPlayer` can start buffering it immediately.
    func prewarm(_ track: Track) async {
        // Skip if already prewarmed for this track
        if prewarmed?.trackId == track.itunesTrackId { return }
        do {
            let matched = try await BackendClient.shared.matchVideoId(track: track)
            let streamUrl = try await StreamResolver.shared.resolveURL(videoId: matched.videoId)
            let item = AVPlayerItem(asset: AVURLAsset(url: streamUrl))
            item.preferredForwardBufferDuration = 5
            prewarmed = (track.itunesTrackId, item, matched.videoId)
            // Attach so AVPlayer pre-buffers proactively
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

    /// Rewind the current AVPlayerItem to 0 and keep playing — the canonical
    /// "repeat one" primitive. Does NOT re-resolve the stream, does NOT touch
    /// the queue, and does NOT fight the prewarmed-item bookkeeping.
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
        // Optimistically update the published position so the slider binding
        // doesn't snap back to the pre-seek value while AVPlayer finishes the
        // seek asynchronously. Use tolerance zero for exact positioning; the
        // periodic observer will pick up forward progress from here.
        let clamped = max(0, min(seconds, max(duration, 0)))
        position = clamped
        let target = CMTime(seconds: clamped, preferredTimescale: 1000)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.updateNowPlayingInfo() }
        }
    }

    // MARK: - Observers

    private func observePlayer() {
        periodicObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 1000), queue: .main) { [weak self] t in
            Task { @MainActor in
                guard let self else { return }
                self.position = t.seconds
                // Prefer the track's iTunes-reported duration (accurate for
                // YouTube-resolved streams, whose AVPlayerItem.duration is
                // often infinite, NaN, or includes ad padding).
                if self.trackDurationSeconds > 0 {
                    self.duration = self.trackDurationSeconds
                } else if let item = self.player.currentItem {
                    let d = item.duration.seconds
                    self.duration = (d.isFinite && d > 0) ? d : 0
                }
            }
        }

        // NOTE: the end-of-track observer is attached per-item in
        // `observeCurrentItem()` so it fires for the actual current item
        // (not the prewarmed pre-buffer).

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
        // Item-scoped end observer — fires only for THIS currentItem, not for
        // the prewarmed pre-buffered next item (which would otherwise trigger
        // a phantom advance and break repeat/autoplay).
        endObs = NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { await QueueManager.shared.advance() }
                self?.updateNowPlayingInfo()
            }
    }

    /// googlevideo stream URLs expire after ~6 hours. If the current item
    /// fails or stalls indefinitely and we have a videoId, refresh and resume.
    private func handlePossibleStreamExpiry() {
        guard let videoId = currentVideoId, let item = player.currentItem else { return }
        // Only attempt refresh if the item has actually failed or its url is unreachable
        if let err = item.error as NSError? {
            let refreshableCodes: Set<Int> = [-11828, -11829, -1001, -1009]
            if !refreshableCodes.contains(err.code) { return }
        }
        let offset = player.currentTime().seconds
        Task { [weak self] in
            guard let self else { return }
            do {
                // Bypass the on-device cache: the cached URL is exactly the one
                // that just failed. This forces YouTubeKit to re-extract.
                let fresh = try await StreamResolver.shared.resolveURL(videoId: videoId, bypassCache: true)
                let new = AVPlayerItem(asset: AVURLAsset(url: fresh))
                new.preferredForwardBufferDuration = 5
                self.player.removeAllItems()
                self.player.insert(new, after: nil)
                self.observeCurrentItem()
                self.player.seek(to: CMTime(seconds: offset, preferredTimescale: 1000), completionHandler: { _ in })
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
        // isPlaying is kept in sync with time control status as a fallback
        isPlaying = player.timeControlStatus == .playing
    }
}
