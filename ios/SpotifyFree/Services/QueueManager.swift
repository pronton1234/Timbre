import Foundation
import Combine

// MARK: - PlaybackContext

struct PlaybackContext {
    enum Kind {
        case album(Album)
        case playlist(id: UUID, name: String)
        case artistTopTracks(Artist)
        case search
    }

    let kind: Kind
    let originalOrder: [Track]    // immutable; restored on un-shuffle
    var shuffleOrder: [Int]?      // nil = no shuffle; [i] = originalOrder index for position i
    var cursor: Int               // current position in active order

    var activeTracks: [Track] {
        if let order = shuffleOrder {
            return order.map { originalOrder[$0] }
        }
        return originalOrder
    }

    var currentTrack: Track? {
        let t = activeTracks
        guard t.indices.contains(cursor) else { return nil }
        return t[cursor]
    }

    var hasMore: Bool { cursor + 1 < activeTracks.count }

    var remainingTracks: [Track] {
        let t = activeTracks
        guard cursor + 1 < t.count else { return [] }
        return Array(t[(cursor + 1)...])
    }

    var contextLabel: String {
        switch kind {
        case .album(let a):            return a.name
        case .playlist(_, let name):  return name
        case .artistTopTracks(let a): return a.name
        case .search:                  return "Search"
        }
    }
}

// MARK: - QueueManager

@MainActor
final class QueueManager: ObservableObject {
    static let shared = QueueManager()

    @Published private(set) var context: PlaybackContext?
    @Published var userQueue: [QueueItem] = []
    @Published private(set) var autoplayQueue: [QueueItem] = []
    @Published private(set) var currentTrack: Track?
    @Published var repeatMode: RepeatMode = .off

    var shuffleOn: Bool { context?.shuffleOrder != nil }

    private var history: [Track] = []
    private let maxHistory = 100
    private let radioTargetSize = 25
    private var radioRefillTask: Task<Void, Never>?
    private let persistenceKey = "queueManager.state.v2"

    private init() {
        restoreFromDisk()
    }

    // MARK: - Start playback

    func playNow(_ tracks: [Track], startAt: Int = 0, kind: PlaybackContext.Kind = .search) async {
        guard !tracks.isEmpty else { print("[QM.playNow] empty tracks"); return }
        print("[QM.playNow] tracks=\(tracks.count) startAt=\(startAt) kind=\(kind)")
        userQueue = []
        history = []
        autoplayQueue = []
        radioRefillTask?.cancel()
        let cursor = max(0, min(startAt, tracks.count - 1))
        context = PlaybackContext(kind: kind, originalOrder: tracks, shuffleOrder: nil, cursor: cursor)
        await startCurrent()
    }

    // MARK: - Queue mutations

    func addToQueue(_ track: Track) {
        let item = QueueItem(track)
        if currentTrack == nil {
            // Nothing playing — seed a one-track context and start
            context = PlaybackContext(kind: .search, originalOrder: [track], shuffleOrder: nil, cursor: 0)
            persist()
            Task { await startCurrent() }
            return
        }
        userQueue.append(item)
        persist()
        schedulePrewarm()
    }

    func move(from source: IndexSet, to destination: Int) {
        userQueue.move(fromOffsets: source, toOffset: destination)
        persist()
        schedulePrewarm()
    }

    func remove(atOffsets offsets: IndexSet) {
        userQueue.remove(atOffsets: offsets)
        persist()
        schedulePrewarm()
    }

    // MARK: - Transport

    func advance(manual: Bool = false) async {
        guard currentTrack != nil else { return }

        if repeatMode == .one && !manual {
            AudioPlayer.shared.restart()
            return
        }

        let prev = currentTrack

        // 1. User queue wins
        if !userQueue.isEmpty {
            let next = userQueue.removeFirst()
            if let prev { appendHistory(prev) }
            currentTrack = next.track
            await AudioPlayer.shared.play(next.track)
            persist()
            schedulePrewarm()
            return
        }

        // 2. Advance context
        if var ctx = context {
            let nextCursor = ctx.cursor + 1
            if nextCursor < ctx.activeTracks.count {
                ctx.cursor = nextCursor
                context = ctx
                if let prev { appendHistory(prev) }
                await startCurrent()
                return
            }
            // End of context
            if repeatMode == .all {
                ctx.cursor = 0
                context = ctx
                if let prev { appendHistory(prev) }
                await startCurrent()
                return
            }
        }

        // 3. Autoplay queue (radio)
        if !autoplayQueue.isEmpty {
            let next = autoplayQueue.removeFirst()
            if let prev { appendHistory(prev) }
            currentTrack = next.track
            await AudioPlayer.shared.play(next.track)
            persist()
            schedulePrewarm()
            scheduleRadioRefill()   // top up the buffer after consuming one
            return
        }

        persist()
    }

    func previous() async {
        let pos = AudioPlayer.shared.position
        if pos > 3 {
            AudioPlayer.shared.seek(to: 0)
            return
        }
        if let last = history.popLast() {
            if let cur = currentTrack {
                userQueue.insert(QueueItem(cur), at: 0)
            }
            currentTrack = last
            await AudioPlayer.shared.play(last)
            persist()
            schedulePrewarm()
        } else {
            AudioPlayer.shared.seek(to: 0)
        }
    }

    /// Jump to a specific cursor position within the context.
    func jumpContext(to cursor: Int) async {
        guard var ctx = context, ctx.activeTracks.indices.contains(cursor) else { return }
        if let cur = currentTrack { appendHistory(cur) }
        ctx.cursor = cursor
        context = ctx
        await startCurrent()
    }

    // MARK: - Shuffle / Repeat

    func toggleShuffle() {
        guard var ctx = context, !ctx.originalOrder.isEmpty else { return }
        if ctx.shuffleOrder != nil {
            // Toggle off: restore original order
            let currentOriginalIdx = ctx.shuffleOrder![ctx.cursor]
            ctx.shuffleOrder = nil
            ctx.cursor = currentOriginalIdx
        } else {
            // Toggle on: pin current track at position 0
            let currentOriginalIdx = ctx.cursor
            var others = Array(0..<ctx.originalOrder.count).filter { $0 != currentOriginalIdx }
            others.shuffle()
            ctx.shuffleOrder = [currentOriginalIdx] + others
            ctx.cursor = 0
        }
        context = ctx
        persist()
        schedulePrewarm()
    }

    func cycleRepeatMode() {
        repeatMode = switch repeatMode {
        case .off: .all
        case .all: .one
        case .one: .off
        }
        persist()
    }

    // MARK: - Internals

    private func startCurrent() async {
        guard let track = context?.currentTrack else {
            print("[QM.startCurrent] no current track in context")
            return
        }
        print("[QM.startCurrent] starting \"\(track.name)\"")
        currentTrack = track
        await AudioPlayer.shared.play(track)
        persist()
        schedulePrewarm()
        scheduleRadioRefill()
    }

    private func appendHistory(_ track: Track) {
        history.append(track)
        if history.count > maxHistory { history.removeFirst(history.count - maxHistory) }
    }

    private func schedulePrewarm() {
        let upcoming = upcomingTracks(limit: 5)
        let upcomingIds = Set(upcoming.map(\.itunesTrackId))
        AudioPlayer.shared.evictPrewarm(retaining: upcomingIds)
        Task {
            for track in upcoming {
                await AudioPlayer.shared.prewarm(track)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    /// Top up `autoplayQueue` to `radioTargetSize` in the background.
    /// Cancels any in-flight refill before starting a new one.
    private func scheduleRadioRefill() {
        guard autoplayQueue.count < radioTargetSize, let seed = currentTrack else { return }
        radioRefillTask?.cancel()
        let want = radioTargetSize - autoplayQueue.count
        let excludeIds = excludedRadioIds()
        radioRefillTask = Task {
            let candidates = await RadioService.shared.candidates(forArtist: seed.artistName, excluding: excludeIds, want: want)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                for track in candidates {
                    guard !self.excludedRadioIds().contains(track.itunesTrackId) else { continue }
                    self.autoplayQueue.append(QueueItem(track))
                }
                self.persist()
            }
        }
    }

    private func excludedRadioIds() -> Set<Int> {
        var ids = Set(history.map(\.itunesTrackId))
        ids.formUnion(autoplayQueue.map(\.track.itunesTrackId))
        ids.formUnion(userQueue.map(\.track.itunesTrackId))
        if let id = currentTrack?.itunesTrackId { ids.insert(id) }
        return ids
    }

    private func upcomingTracks(limit: Int) -> [Track] {
        var result: [Track] = []
        for item in userQueue.prefix(limit) {
            result.append(item.track)
            if result.count >= limit { return result }
        }
        if let ctx = context {
            for t in ctx.remainingTracks.prefix(limit - result.count) {
                result.append(t)
                if result.count >= limit { return result }
            }
        }
        return result
    }

    // MARK: - Persistence

    private struct ContextSnapshot: Codable {
        enum KindTag: String, Codable {
            case album, playlistLite, artistTopTracks, search
        }
        let kindTag: KindTag
        let album: Album?
        let artist: Artist?
        let playlistId: UUID?
        let playlistName: String?
        let originalOrder: [Track]
        let shuffleOrder: [Int]?
        let cursor: Int
    }

    private struct Snapshot: Codable {
        let context: ContextSnapshot?
        let userQueue: [QueueItem]
        let repeatMode: RepeatMode
    }

    private func persist() {
        let ctxSnap: ContextSnapshot?
        if let ctx = context {
            let tag: ContextSnapshot.KindTag
            var album: Album? = nil
            var artist: Artist? = nil
            var pid: UUID? = nil
            var pname: String? = nil
            switch ctx.kind {
            case .album(let a):               tag = .album;             album = a
            case .artistTopTracks(let ar):    tag = .artistTopTracks;   artist = ar
            case .playlist(let id, let name): tag = .playlistLite;      pid = id; pname = name
            case .search:                     tag = .search
            }
            ctxSnap = ContextSnapshot(kindTag: tag, album: album, artist: artist,
                                       playlistId: pid, playlistName: pname,
                                       originalOrder: ctx.originalOrder,
                                       shuffleOrder: ctx.shuffleOrder,
                                       cursor: ctx.cursor)
        } else {
            ctxSnap = nil
        }
        let snap = Snapshot(context: ctxSnap, userQueue: userQueue, repeatMode: repeatMode)
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }

    private func restoreFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        userQueue = snap.userQueue
        repeatMode = snap.repeatMode
        if let cs = snap.context {
            let kind: PlaybackContext.Kind
            switch cs.kindTag {
            case .album:
                kind = cs.album.map { .album($0) } ?? .search
            case .artistTopTracks:
                kind = cs.artist.map { .artistTopTracks($0) } ?? .search
            case .playlistLite:
                if let id = cs.playlistId, let name = cs.playlistName {
                    kind = .playlist(id: id, name: name)
                } else { kind = .search }
            case .search:
                kind = .search
            }
            let ctx = PlaybackContext(kind: kind, originalOrder: cs.originalOrder,
                                      shuffleOrder: cs.shuffleOrder, cursor: cs.cursor)
            context = ctx
            currentTrack = ctx.currentTrack
        }
    }
}
