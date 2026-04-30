import Foundation

/// Direct Innertube `/player` client. Uses the IOS client params which return
/// unsigned, directly-playable googlevideo URLs — no JS signature decryption.
///
/// This is what makes cold-cold YouTube extraction fast: YouTubeKit and
/// other general-purpose libraries do extra work (metadata, signature
/// decryption, retries) that takes 2–5s. A focused IOS-client call returns
/// in ~400–900ms.
///
/// Reference: the IOS client key is publicly known (extracted from the
/// official iOS YouTube binary by ytdl-org/yt-dlp). YouTube has not gated
/// it behind PoToken as of this writing.
actor InnertubeClient {
    static let shared = InnertubeClient()

    enum Err: Error {
        case http(Int, String)
        case playabilityFailed(String)
        case noPlayableAudio
        case malformedResponse
    }

    private static let apiURL = URL(string: "https://youtubei.googleapis.com/youtubei/v1/player?prettyPrint=false")!
    private static let iosKey = "AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc"
    private static let iosUserAgent = "com.google.ios.youtube/19.09.3 (iPhone16,2; U; CPU iOS 17_1 like Mac OS X;)"

    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 5
        cfg.httpMaximumConnectionsPerHost = 4
        self.session = URLSession(configuration: cfg)
    }

    /// Fetch a directly-playable audio URL for a videoId via the IOS Innertube
    /// client. Returns the highest-bitrate AAC/m4a stream — AVPlayer plays
    /// these natively without transcoding.
    func fetchAudioStreamURL(videoId: String) async throws -> URL {
        let t0 = Date()
        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "IOS",
                    "clientVersion": "19.09.3",
                    "deviceMake": "Apple",
                    "deviceModel": "iPhone16,2",
                    "osName": "iPhone",
                    "osVersion": "17.1.0.21B74",
                    "hl": "en",
                    "gl": "US",
                    "utcOffsetMinutes": 0,
                ],
            ],
            "videoId": videoId,
            "playbackContext": [
                "contentPlaybackContext": ["html5Preference": "HTML5_PREF_WANTS"],
            ],
            "contentCheckOk": true,
            "racyCheckOk": true,
        ]

        var req = URLRequest(url: Self.apiURL.appendingQueryItem(name: "key", value: Self.iosKey))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.iosUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("2", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw Err.malformedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Err.http(http.statusCode, String(data: data.prefix(200), encoding: .utf8) ?? "")
        }
        let url = try parseBestAudioURL(from: data)
        print("[IT.fetch] videoId=\(videoId) → \(Int(Date().timeIntervalSince(t0)*1000))ms host=\(url.host ?? "?")")
        return url
    }

    private func parseBestAudioURL(from data: Data) throws -> URL {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Err.malformedResponse
        }
        // Surface playability problems clearly rather than letting them look like
        // "no streams" — UNPLAYABLE / LOGIN_REQUIRED / AGE_RESTRICTED show up here.
        if let playability = json["playabilityStatus"] as? [String: Any],
           let status = playability["status"] as? String, status != "OK" {
            let reason = (playability["reason"] as? String)
                ?? (playability["errorScreen"] as? [String: Any])?.description
                ?? status
            throw Err.playabilityFailed("\(status): \(reason)")
        }
        guard let streamingData = json["streamingData"] as? [String: Any] else {
            throw Err.noPlayableAudio
        }
        let formats = (streamingData["adaptiveFormats"] as? [[String: Any]]) ?? []
        // Pick highest-bitrate audio/mp4 (AAC) — AVPlayer plays these natively.
        // Skip audio/webm (Opus) which causes mediaserverd crashes (-12860).
        let candidates = formats.compactMap { fmt -> (Int, String)? in
            guard let mime = fmt["mimeType"] as? String, mime.hasPrefix("audio/mp4") else { return nil }
            guard let url = fmt["url"] as? String else { return nil }
            let bitrate = (fmt["bitrate"] as? Int) ?? (fmt["averageBitrate"] as? Int) ?? 0
            return (bitrate, url)
        }
        guard let best = candidates.max(by: { $0.0 < $1.0 }),
              let url = URL(string: best.1) else {
            throw Err.noPlayableAudio
        }
        return url
    }
}

private extension URL {
    func appendingQueryItem(name: String, value: String) -> URL {
        guard var comps = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: name, value: value))
        comps.queryItems = items
        return comps.url ?? self
    }
}
