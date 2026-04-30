// LRClib lyrics client — https://lrclib.net
// Free, open, no authentication, returns time-synced LRC lyrics.
import Foundation

struct LyricsLine: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval   // seconds from track start
    let text: String
}

struct TrackLyrics {
    let lines: [LyricsLine]       // sorted ascending by timestamp
    let plainText: String         // fallback when no timestamps available

    var hasSyncedLines: Bool { !lines.isEmpty }
}

actor LyricsClient {
    static let shared = LyricsClient()

    private var cache: [Int: TrackLyrics?] = [:]  // itunesTrackId → lyrics (nil = confirmed miss)

    func fetchLyrics(for track: Track) async -> TrackLyrics? {
        if let cached = cache[track.itunesTrackId] { return cached }

        let result = await _fetch(title: track.name, artist: track.artistName, album: track.albumName, durationSec: track.durationMs / 1000)
        cache[track.itunesTrackId] = result
        return result
    }

    private func _fetch(title: String, artist: String, album: String?, durationSec: Int) async -> TrackLyrics? {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if let album { items.append(URLQueryItem(name: "album_name", value: album)) }
        if durationSec > 0 { items.append(URLQueryItem(name: "duration", value: String(durationSec))) }
        comps.queryItems = items
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Timbre/1.0 (iOS; lrclib.net)", forHTTPHeaderField: "Lrclib-Client")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONDecoder().decode(LrclibResponse.self, from: data)
        else { return nil }

        if let synced = json.syncedLyrics, !synced.isEmpty {
            let lines = parseLRC(synced)
            if !lines.isEmpty { return TrackLyrics(lines: lines, plainText: json.plainLyrics ?? "") }
        }
        if let plain = json.plainLyrics, !plain.isEmpty {
            return TrackLyrics(lines: [], plainText: plain)
        }
        return nil
    }

    private func parseLRC(_ lrc: String) -> [LyricsLine] {
        var lines: [LyricsLine] = []
        for raw in lrc.components(separatedBy: "\n") {
            guard raw.hasPrefix("[") else { continue }
            if let close = raw.firstIndex(of: "]") {
                let tag = String(raw[raw.index(after: raw.startIndex)..<close])
                let text = String(raw[raw.index(after: close)...]).trimmingCharacters(in: .whitespaces)
                if let ts = parseTimestamp(tag) {
                    lines.append(LyricsLine(timestamp: ts, text: text))
                }
            }
        }
        return lines.sorted { $0.timestamp < $1.timestamp }
    }

    private func parseTimestamp(_ tag: String) -> TimeInterval? {
        // Format: MM:SS.xx or MM:SS
        let parts = tag.split(separator: ":")
        guard parts.count == 2,
              let min = Double(parts[0]),
              let sec = Double(parts[1])
        else { return nil }
        return min * 60 + sec
    }

    private struct LrclibResponse: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }
}
