import Foundation
import YouTubeKit

/// On-device YouTube stream-URL resolver.
///
/// Takes a `videoId` (produced by the backend's iTunes→YouTube match step) and
/// returns a directly-playable `*.googlevideo.com/videoplayback` URL.
///
/// Why this lives on the phone: YouTube IP-gates its stream endpoint for
/// datacenter IPs (Oracle Cloud, AWS, GCP, Azure). Major-label US tracks return
/// `Sign in to confirm you're not a bot` when extraction runs on our VM. From a
/// residential/mobile IP (the user's phone), the same request succeeds because
/// YouTube's anti-bot heuristics treat the mobile client as a real viewer.
///
/// Caches resolved URLs in a small in-process LRU so repeated plays of the same
/// track within a session don't re-hit YouTube. URLs are tied to
/// googlevideo's ~6h signature lifetime, so we treat the cache as a 30-min TTL
/// (conservative — well below the expiry).
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
    private let cacheTTL: TimeInterval = 30 * 60  // 30 minutes
    private let cacheLimit = 32

    private init() {}

    /// Resolve a video ID to a playable stream URL.
    /// - Parameters:
    ///   - videoId: YouTube video identifier.
    ///   - bypassCache: force a fresh extraction (used after mid-stream URL expiry).
    func resolveURL(videoId: String, bypassCache: Bool = false) async throws -> URL {
        if !bypassCache, let entry = cache[videoId], Date().timeIntervalSince(entry.resolvedAt) < cacheTTL {
            return entry.url
        }

        let yt = YouTube(videoID: videoId)
        do {
            let streams = try await yt.streams
            // AVPlayer only decodes AAC/m4a natively — filter out Opus/webm streams
            // that would crash mediaserverd (err=-12860). `isNativelyPlayable` checks
            // both audio+video codecs against AVPlayer's supported set.
            let playable = streams.filterAudioOnly().filter { $0.isNativelyPlayable }
            guard let audio = playable.highestAudioBitrateStream() else {
                throw ResolveError.noAudioStream
            }
            let url = audio.url
            cache[videoId] = Entry(url: url, resolvedAt: Date())
            evictIfNeeded()
            return url
        } catch let err as ResolveError {
            throw err
        } catch {
            throw ResolveError.underlying(error)
        }
    }

    /// Drop a single entry, e.g. after the current stream URL hits a 403.
    func invalidate(videoId: String) {
        cache.removeValue(forKey: videoId)
    }

    private func evictIfNeeded() {
        guard cache.count > cacheLimit else { return }
        // Evict oldest entries
        let sorted = cache.sorted { $0.value.resolvedAt < $1.value.resolvedAt }
        let dropCount = cache.count - cacheLimit
        for (k, _) in sorted.prefix(dropCount) {
            cache.removeValue(forKey: k)
        }
    }
}
