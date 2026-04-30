import Foundation
import AVFoundation

/// Custom AVAssetResourceLoaderDelegate that gives AVPlayer a single continuous
/// asset under the URL scheme `timbre://video/{videoId}`, while internally
/// switching between two byte sources:
///
///   1. **Backend `/play`** for the first range request — the backend resolves
///      the googlevideo URL (cache hit ~80ms, miss runs the extractor chain)
///      and pipes bytes back. The response header `X-Direct-URL` carries the
///      resolved URL so subsequent ranges can skip the backend entirely.
///
///   2. **Direct googlevideo URL** for subsequent ranges — once we know the
///      direct URL, we issue HTTP range requests to it ourselves. This avoids
///      sending audio data through the backend after the initial chunk.
///
/// The handoff is invisible to AVPlayer: it always sees `timbre://...` and
/// receives bytes from whichever source we pulled them from.
///
/// On any backend failure (503, timeout), we fall back to resolving the URL
/// on-device via the existing `StreamResolver` and stream directly. Playback
/// is never blocked on the backend being healthy.
final class HybridStreamLoader: NSObject, @unchecked Sendable {

    static let scheme = "timbre"

    private let videoId: String
    private let backendBaseURL: URL
    private let session: URLSession
    private let onDeviceFallback: (String) async throws -> URL

    // Optional track metadata — sent as query params to /play so the backend
    // can try Audius before falling back to YouTube extraction.
    struct TrackMeta {
        let itunesTrackId: Int
        let title: String
        let artist: String
        let isrc: String?
    }
    private let trackMeta: TrackMeta?

    /// Cached direct googlevideo URL, set on the first successful response from
    /// the backend (or via on-device fallback). Reads/writes are guarded by
    /// `lock` because AVAssetResourceLoaderDelegate callbacks come on the
    /// delegate's queue but the dataTask completion may be on a URLSession
    /// internal queue.
    private let lock = NSLock()
    private var directURL: URL?

    private var inFlight: [ObjectIdentifier: URLSessionDataTask] = [:]

    init(
        videoId: String,
        backendBaseURL: URL,
        session: URLSession = .shared,
        trackMeta: TrackMeta? = nil,
        onDeviceFallback: @escaping (String) async throws -> URL
    ) {
        self.videoId = videoId
        self.backendBaseURL = backendBaseURL
        self.session = session
        self.trackMeta = trackMeta
        self.onDeviceFallback = onDeviceFallback
    }

    /// Build an `AVURLAsset` whose resource loader is wired to a fresh loader.
    /// The loader is retained as the asset's delegate; release it by deallocating
    /// the asset.
    static func makeAsset(
        videoId: String,
        backendBaseURL: URL,
        delegateQueue: DispatchQueue,
        trackMeta: TrackMeta? = nil,
        onDeviceFallback: @escaping (String) async throws -> URL
    ) -> (AVURLAsset, HybridStreamLoader) {
        let url = URL(string: "\(scheme)://video/\(videoId)")!
        let asset = AVURLAsset(url: url)
        let loader = HybridStreamLoader(
            videoId: videoId,
            backendBaseURL: backendBaseURL,
            trackMeta: trackMeta,
            onDeviceFallback: onDeviceFallback
        )
        asset.resourceLoader.setDelegate(loader, queue: delegateQueue)
        return (asset, loader)
    }

    // MARK: - Internal

    fileprivate func snapshotDirectURL() -> URL? {
        lock.lock(); defer { lock.unlock() }
        return directURL
    }

    fileprivate func setDirectURLIfNeeded(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        if directURL == nil { directURL = url }
    }

    fileprivate func registerTask(_ task: URLSessionDataTask, for request: AVAssetResourceLoadingRequest) {
        lock.lock(); defer { lock.unlock() }
        inFlight[ObjectIdentifier(request)] = task
    }

    fileprivate func deregisterTask(for request: AVAssetResourceLoadingRequest) {
        lock.lock(); defer { lock.unlock() }
        inFlight.removeValue(forKey: ObjectIdentifier(request))
    }

    fileprivate func cancelAll() {
        lock.lock()
        let tasks = Array(inFlight.values)
        inFlight.removeAll()
        lock.unlock()
        for t in tasks { t.cancel() }
    }
}

// MARK: - AVAssetResourceLoaderDelegate

extension HybridStreamLoader: AVAssetResourceLoaderDelegate {

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        if loadingRequest.dataRequest == nil {
            // Content-information-only request — AVPlayer wants MIME type + content length.
            Task { [weak self] in await self?.handleContentInfo(loadingRequest) }
            return true
        }
        Task { [weak self] in
            guard let dataRequest = loadingRequest.dataRequest else { return }
            await self?.handle(loadingRequest: loadingRequest, dataRequest: dataRequest)
        }
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        deregisterTask(for: loadingRequest)
    }

    private func handle(
        loadingRequest: AVAssetResourceLoadingRequest,
        dataRequest: AVAssetResourceLoadingDataRequest
    ) async {
        // Hot path: we already know the direct googlevideo URL. Skip the backend.
        if let direct = snapshotDirectURL() {
            dispatchDirect(loadingRequest: loadingRequest, dataRequest: dataRequest, url: direct)
            return
        }

        // Cold path: hit backend /play. The response includes audio bytes for
        // the requested range AND an X-Direct-URL header we cache for next time.
        if await dispatchViaBackend(loadingRequest: loadingRequest, dataRequest: dataRequest) {
            return
        }

        // Backend failed entirely (503, timeout, etc.) — fall back to on-device
        // stream resolution and issue the range request directly to googlevideo.
        do {
            let url = try await onDeviceFallback(videoId)
            setDirectURLIfNeeded(url)
            dispatchDirect(loadingRequest: loadingRequest, dataRequest: dataRequest, url: url)
        } catch {
            loadingRequest.finishLoading(with: error)
        }
    }

    // MARK: - Content information (no dataRequest)

    /// Handles AVPlayer's initial probe for content type + length.
    /// Issues a bytes=0-0 range request to whatever source we can reach,
    /// fills the contentInformationRequest, and finishes the load.
    private func handleContentInfo(_ loadingRequest: AVAssetResourceLoadingRequest) async {
        // If we already resolved the direct URL, probe it.
        let probeURL: URL?
        if let direct = snapshotDirectURL() {
            probeURL = direct
        } else {
            // Try resolving on-device so we have a URL to probe.
            probeURL = try? await onDeviceFallback(videoId)
            if let url = probeURL { setDirectURLIfNeeded(url) }
        }

        guard let url = probeURL else {
            // Nothing to probe — fill in sensible defaults so AVPlayer can proceed.
            if let info = loadingRequest.contentInformationRequest {
                info.contentType = "audio/mp4"
                info.isByteRangeAccessSupported = true
            }
            loadingRequest.finishLoading()
            return
        }

        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        do {
            let (_, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse {
                fillContentInformation(loadingRequest: loadingRequest, response: http)
            }
        } catch {
            if let info = loadingRequest.contentInformationRequest {
                info.contentType = "audio/mp4"
                info.isByteRangeAccessSupported = true
            }
        }
        loadingRequest.finishLoading()
    }

    /// Returns true if the backend handled the request (success or failure that
    /// AVPlayer should observe). Returns false to signal the caller to fall back
    /// to on-device resolution.
    private func dispatchViaBackend(
        loadingRequest: AVAssetResourceLoadingRequest,
        dataRequest: AVAssetResourceLoadingDataRequest
    ) async -> Bool {
        var comps = URLComponents(url: backendBaseURL.appendingPathComponent("play"), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "videoId", value: videoId)]
        if let meta = trackMeta {
            queryItems += [
                URLQueryItem(name: "itunesTrackId", value: String(meta.itunesTrackId)),
                URLQueryItem(name: "title", value: meta.title),
                URLQueryItem(name: "artist", value: meta.artist),
            ]
            if let isrc = meta.isrc {
                queryItems.append(URLQueryItem(name: "isrc", value: isrc))
            }
        }
        comps.queryItems = queryItems
        guard let url = comps.url else { return false }
        var req = URLRequest(url: url, timeoutInterval: 8)
        if let rangeHeader = makeRangeHeader(dataRequest) {
            req.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            // Anything outside 2xx → fall back. We never want to feed AVPlayer
            // a JSON error body as if it were audio bytes.
            guard (200..<300).contains(http.statusCode) else { return false }
            // Capture the resolved direct URL for subsequent ranges.
            if let directStr = http.value(forHTTPHeaderField: "X-Direct-URL"),
               let direct = URL(string: directStr) {
                setDirectURLIfNeeded(direct)
            }
            fillContentInformation(loadingRequest: loadingRequest, response: http)
            dataRequest.respond(with: data)
            loadingRequest.finishLoading()
            return true
        } catch {
            return false
        }
    }

    private func dispatchDirect(
        loadingRequest: AVAssetResourceLoadingRequest,
        dataRequest: AVAssetResourceLoadingDataRequest,
        url: URL
    ) {
        var req = URLRequest(url: url, timeoutInterval: 15)
        if let rangeHeader = makeRangeHeader(dataRequest) {
            req.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }
        let task = session.dataTask(with: req) { [weak self] data, response, error in
            self?.deregisterTask(for: loadingRequest)
            if let error = error {
                loadingRequest.finishLoading(with: error)
                return
            }
            guard let data = data, let http = response as? HTTPURLResponse else {
                loadingRequest.finishLoading(with: NSError(
                    domain: "HybridStreamLoader", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "no data"]
                ))
                return
            }
            self?.fillContentInformation(loadingRequest: loadingRequest, response: http)
            dataRequest.respond(with: data)
            loadingRequest.finishLoading()
        }
        registerTask(task, for: loadingRequest)
        task.resume()
    }

    private func makeRangeHeader(_ dataRequest: AVAssetResourceLoadingDataRequest) -> String? {
        // AVPlayer often sets requestsAllDataToEndOfResource — translate that
        // to an open-ended range. Otherwise return a closed range.
        let start = dataRequest.requestedOffset
        let length = Int64(dataRequest.requestedLength)
        if dataRequest.requestsAllDataToEndOfResource {
            return "bytes=\(start)-"
        }
        if length <= 0 { return nil }
        let end = start + length - 1
        return "bytes=\(start)-\(end)"
    }

    private func fillContentInformation(
        loadingRequest: AVAssetResourceLoadingRequest,
        response: HTTPURLResponse
    ) {
        guard let info = loadingRequest.contentInformationRequest else { return }
        if let mime = response.mimeType {
            info.contentType = mime as String
        }
        if let total = totalContentLength(from: response) {
            info.contentLength = total
        }
        info.isByteRangeAccessSupported = (response.value(forHTTPHeaderField: "Accept-Ranges") == "bytes")
            || (response.value(forHTTPHeaderField: "Content-Range")?.hasPrefix("bytes") ?? false)
    }

    private func totalContentLength(from response: HTTPURLResponse) -> Int64? {
        // Prefer Content-Range (e.g. "bytes 0-1023/4567890") over Content-Length
        // because Content-Length on a 206 only describes this chunk, not the file.
        if let cr = response.value(forHTTPHeaderField: "Content-Range") {
            if let slash = cr.lastIndex(of: "/") {
                let total = cr[cr.index(after: slash)...]
                if let n = Int64(total), n > 0 { return n }
            }
        }
        if response.statusCode == 200, response.expectedContentLength > 0 {
            return response.expectedContentLength
        }
        return nil
    }
}
