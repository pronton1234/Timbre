// GET /stream-url?videoId=xxx
//
// Returns a directly-playable googlevideo.com URL for a YouTube videoId.
// On cache hit, this is a single SQLite read (~1-2ms backend-side).
// On cache miss, runs the full extractor chain (yt-dlp → Piped → Cobalt → youtubei.js)
// and writes the result back to cache for the next ~5h (googlevideo URLs are signed
// for ~6h; we use 5h as a safety margin).
//
// Why this exists alongside on-device extraction in iOS:
// the cache hit path is shared across all users. Once any one user (or the
// pre-extraction worker) has resolved a song's URL, every subsequent user gets
// it in 1 RTT instead of 2-5s of YouTubeKit/Innertube parsing.
//
// Response shapes:
//   200 { videoId, url, extractor, expiresAt, source: 'cache'|'fresh' }
//   404 { error: 'no_video_id' }            — missing query param
//   503 { error: 'extraction_failed' }      — all extractors failed (datacenter IP block, etc.)
//                                             iOS falls back to on-device extraction.
import express from 'express'
import { request as undiciRequest } from 'undici'
import * as defaultExtractor from '../services/extractor/index.js'

export function createStreamUrlRouter(cache, deps = {}) {
  // Default to the racing extractor — youtubei + ytdlp in parallel, first wins.
  // p50 cold extraction drops from ~5s (sequential ytdlp-first) to ~500–800ms.
  const extract = deps.extractStream ?? defaultExtractor.extractStreamRaced ?? defaultExtractor.extractStream
  const router = express.Router()

  router.get('/stream-url', async (req, res) => {
    const videoId = String(req.query.videoId ?? '').trim()
    if (!videoId) {
      return res.status(400).json({ error: 'no_video_id' })
    }

    const cached = cache.getStreamUrl(videoId)
    if (cached) {
      return res.json({
        videoId,
        url: cached.url,
        extractor: cached.extractor,
        expiresAt: cached.expiresAt,
        source: 'cache',
      })
    }

    try {
      const { url, extractor: extractorName } = await extract(videoId)
      cache.setStreamUrl(videoId, url, extractorName)
      const stored = cache.getStreamUrl(videoId)
      // Pipelined CDN warmup: fire-and-forget HEAD/range to googlevideo so the
      // CDN edge node serving this region is warm by the time iOS asks for
      // bytes. Saves ~50–100ms on the AVPlayer first-byte path.
      warmCDN(url)
      return res.json({
        videoId,
        url,
        extractor: extractorName,
        expiresAt: stored?.expiresAt ?? null,
        source: 'fresh',
      })
    } catch (e) {
      req.app.get('logger')?.error?.('/stream-url failed', { videoId, error: String(e?.message ?? e) })
      return res.status(503).json({ error: 'extraction_failed', detail: String(e?.message ?? e) })
    }
  })

  return router
}

function warmCDN(url) {
  // Don't await; don't block response on this. Best-effort CDN warmup.
  // bytes=0-262143 is ~256KB — enough to populate edge cache without consuming
  // server bandwidth to download the full file. We discard the body.
  Promise.resolve().then(async () => {
    try {
      const ac = new AbortController()
      // Self-cancel after 2s so a slow CDN response doesn't hold a socket open.
      const t = setTimeout(() => ac.abort(), 2_000)
      const resp = await undiciRequest(url, {
        method: 'GET',
        headers: { Range: 'bytes=0-262143' },
        signal: ac.signal,
      })
      // Drain so undici releases the socket back to the pool.
      await resp.body.dump?.()
      clearTimeout(t)
    } catch (_) { /* swallow — warmup is best-effort */ }
  })
}
