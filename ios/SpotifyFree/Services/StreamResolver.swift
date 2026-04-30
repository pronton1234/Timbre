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
            print("[SR.resolveURL] memory cache hit videoId=\(videoId)")
            return entry.url
        }

        // Race the backend (which has its own URL cache + parallel extractor pool)
        // against on-device InnertubeClient. First valid result wins; the loser is
        // cancelled. This gives us the best of both:
        //  - Backend cache hit (~80ms RTT) for songs anyone played in the last 5h
        //  - Backend racing extractor (~500–800ms) for cold songs when youtubei is healthy
        //  - Local InnertubeClient (~500–900ms) when the backend is unreachable
        //  - Whichever path wins, we still cache locally so subsequent taps skip the race
        if !bypassCache {
            let raceStart = Date()
            if let url = await raceResolution(videoId: videoId) {
                print("[SR.resolveURL] raced winner in \(Int(Date().timeIntervalSince(raceStart)*1000))ms videoId=\(videoId)")
                cache[videoId] = Entry(url: url, resolvedAt: Date())
                evictIfNeeded()
                persistToDisk()
                return url
            }
            print("[SR.resolveURL] race failed; falling back to YouTubeKit videoId=\(videoId)")
        }

        // Last-resort fallback: YouTubeKit. Slow (2–5s) but resilient if both
        // backend and InnertubeClient have failed (e.g. PoToken regression).
        let tYTK = Date()
        let yt = YouTube(videoID: videoId)
        do {
            let streams = try await yt.streams
            let playable = streams.filterAudioOnly().filter { $0.isNativelyPlayable }
            print("[SR.resolveURL] YouTubeKit \(streams.count)/\(playable.count) playable in \(Int(Date().timeIntervalSince(tYTK)*1000))ms")
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
            print("[SR.resolveURL] YouTubeKit threw: \(error)")
            throw ResolveError.underlying(error)
        }
    }

    /// Race backend `/stream-url` against on-device `InnertubeClient`.
    /// Returns the first successful URL or nil if both fail.
    private func raceResolution(videoId: String) async -> URL? {
        await withTaskGroup(of: (String, URL?).self) { group in
            // Backend: cache hit (~80ms) or fresh racing extraction (~500–800ms).
            // 1.5s timeout matches the worst case where backend has to extract from
            // scratch with both youtubei and ytdlp racing.
            group.addTask {
                do {
                    let resp = try await BackendClient.shared.fetchStreamURL(
                        videoId: videoId, timeoutSeconds: 1.5
                    )
                    return ("backend(\(resp.source ?? "?"))", URL(string: resp.url))
                } catch {
                    return ("backend", nil)
                }
            }
            // Local: focused IOS Innertube call (~500–900ms). Independent of backend.
            group.addTask {
                let url = try? await InnertubeClient.shared.fetchAudioStreamURL(videoId: videoId)
                return ("innertube", url)
            }
            for await (source, url) in group {
                if let url = url {
                    print("[SR.race] winner=\(source)")
                    group.cancelAll()
                    return url
                }
                print("[SR.race] \(source) failed/empty")
            }
            return nil
        }
    }

    private func fetchFromBackend(videoId: String) async throws -> URL {
        let resp = try await BackendClient.shared.fetchStreamURL(videoId: videoId, timeoutSeconds: 0.2)
        guard let url = URL(string: resp.url) else {
            throw ResolveError.noAudioStream
        }
        return url
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
