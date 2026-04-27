import Foundation
import YouTubeKit

/// On-device YouTube stream-URL resolver.
///
/// Takes a `videoId` and returns a directly-playable `*.googlevideo.com/videoplayback` URL.
///
/// Why this lives on the phone: YouTube IP-gates its stream endpoint for
/// datacenter IPs (Oracle Cloud, AWS, GCP, Azure). From a residential/mobile
/// IP the same request succeeds because YouTube's anti-bot heuristics treat
/// the mobile client as a real viewer.
///
/// Cache: 300 entries, 5-hour TTL (googlevideo URLs are signed for ~6h).
/// Persisted to UserDefaults so entries survive app restarts — the most
/// expensive operation (YouTubeKit extraction) is only needed once per song
/// per ~5h window.
actor StreamResolver {
    static let shared = StreamResolver()

    struct Entry {
        let url: URL
        let resolvedAt: Date
    }

    enum ResolveError: Error {
        case noAudioStream
        case underlying(Error)
    }

    private var cache: [String: Entry] = [:]
    private let cacheTTL: TimeInterval = 5 * 60 * 60   // 5 hours
    private let cacheLimit = 300
    private let udKey = "streamResolverCache.v1"

    private init() {
        loadFromDisk()
    }

    // MARK: - Public API

    func resolveURL(videoId: String, bypassCache: Bool = false) async throws -> URL {
        if !bypassCache, let entry = cache[videoId],
           Date().timeIntervalSince(entry.resolvedAt) < cacheTTL {
            return entry.url
        }

        let yt = YouTube(videoID: videoId)
        do {
            let streams = try await yt.streams
            // AVPlayer only decodes AAC/m4a natively — filter out Opus/webm streams
            // that would crash mediaserverd (err=-12860).
            let playable = streams.filterAudioOnly().filter { $0.isNativelyPlayable }
            guard let audio = playable.highestAudioBitrateStream() else {
                throw ResolveError.noAudioStream
            }
            let url = audio.url
            cache[videoId] = Entry(url: url, resolvedAt: Date())
            evictIfNeeded()
            persistToDisk()
            return url
        } catch let err as ResolveError {
            throw err
        } catch {
            throw ResolveError.underlying(error)
        }
    }

    func invalidate(videoId: String) {
        cache.removeValue(forKey: videoId)
        persistToDisk()
    }

    // MARK: - Test support

#if DEBUG
    func injectCacheEntry(videoId: String, url: URL, resolvedAt: Date = Date()) {
        cache[videoId] = Entry(url: url, resolvedAt: resolvedAt)
        evictIfNeeded()
    }

    func clearCache() {
        cache.removeAll()
        UserDefaults.standard.removeObject(forKey: udKey)
    }
#endif

    // MARK: - Private

    private func evictIfNeeded() {
        guard cache.count > cacheLimit else { return }
        let sorted = cache.sorted { $0.value.resolvedAt < $1.value.resolvedAt }
        let dropCount = cache.count - cacheLimit
        for (k, _) in sorted.prefix(dropCount) {
            cache.removeValue(forKey: k)
        }
    }

    // MARK: - Persistence

    private struct CodableEntry: Codable {
        let videoId: String
        let urlString: String
        let resolvedAt: Date
    }

    private func persistToDisk() {
        let entries = cache.map { (videoId, entry) in
            CodableEntry(videoId: videoId, urlString: entry.url.absoluteString, resolvedAt: entry.resolvedAt)
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: udKey)
        }
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: udKey),
              let entries = try? JSONDecoder().decode([CodableEntry].self, from: data) else { return }
        let now = Date()
        for e in entries {
            // Skip expired entries — don't bother loading URLs that will just be
            // evicted on first access anyway.
            guard now.timeIntervalSince(e.resolvedAt) < cacheTTL,
                  let url = URL(string: e.urlString) else { continue }
            cache[e.videoId] = Entry(url: url, resolvedAt: e.resolvedAt)
        }
    }
}
