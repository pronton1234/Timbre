// GET /play?videoId=xxx[&itunesTrackId=NNN&title=...&artist=...&isrc=...]
//
// Streaming byte proxy for HybridStreamLoader on iOS. The endpoint:
//   1. Resolves the best audio source: Audius cache → Audius live → YouTube cache → YouTube extract
//   2. Forwards the client's Range header to the upstream CDN
//   3. Pipes bytes back AND sets `X-Direct-URL` so iOS can issue subsequent range
//      requests directly (backend only proxies the first chunk).
//
// Optional track metadata params (itunesTrackId, title, artist, isrc) let us try
// Audius first — Audius returns direct CDN URLs with no extraction step, so cold
// starts for tracks available on Audius drop from 2–5s to ~300ms.
//
// On any failure (all sources down) we surface 503; HybridStreamLoader falls back
// to on-device extraction.
import express from 'express'
import { request as undiciRequest } from 'undici'
import { createSourceResolver } from '../services/source-resolver.js'

const RANGE_HEADER_PASSTHROUGH = ['range', 'accept', 'accept-encoding', 'user-agent']
const RESPONSE_HEADER_PASSTHROUGH = [
  'content-type',
  'content-length',
  'content-range',
  'accept-ranges',
  'last-modified',
  'etag',
]

export function createPlayRouter(cache, deps = {}) {
  const fetchUpstream = deps.fetchUpstream ?? undiciRequest
  const resolver = createSourceResolver(cache, {
    extractStream: deps.extractStream,
    findAudiusStreamUrl: deps.findAudiusStreamUrl,
  })
  const router = express.Router()

  router.get('/play', async (req, res) => {
    const videoId = String(req.query.videoId ?? '').trim() || null
    const itunesTrackId = Number(req.query.itunesTrackId) || null
    const title = String(req.query.title ?? '').trim() || null
    const artist = String(req.query.artist ?? '').trim() || null
    const isrc = String(req.query.isrc ?? '').trim() || null

    if (!videoId && !itunesTrackId) {
      return res.status(400).json({ error: 'no_video_id' })
    }

    let resolved
    try {
      resolved = await resolver.resolveBestSource(videoId, { itunesTrackId, title, artist, isrc })
    } catch (e) {
      req.app.get('logger')?.error?.('/play source resolution failed', { videoId, error: String(e?.message ?? e) })
      return res.status(503).json({ error: 'extraction_failed', detail: String(e?.message ?? e) })
    }

    const { url: resolvedUrl, extractor: extractorName, source } = resolved

    // Build forwarded headers — only pass through what we need.
    const upstreamHeaders = {}
    for (const h of RANGE_HEADER_PASSTHROUGH) {
      const v = req.headers[h]
      if (v != null) upstreamHeaders[h] = String(v)
    }

    let upstream
    try {
      upstream = await fetchUpstream(resolvedUrl, { method: 'GET', headers: upstreamHeaders })
    } catch (e) {
      // Upstream unreachable — invalidate caches and let iOS fall back.
      if (videoId) cache.invalidateStreamUrl(videoId)
      if (itunesTrackId) cache.invalidateAudioSource(itunesTrackId)
      req.app.get('logger')?.error?.('/play upstream fetch failed', { videoId, source, error: String(e?.message ?? e) })
      return res.status(503).json({ error: 'upstream_unreachable' })
    }

    if (upstream.statusCode === 403 || upstream.statusCode === 410) {
      // Expired URL — invalidate so next call re-extracts.
      if (videoId && source === 'youtube') cache.invalidateStreamUrl(videoId)
      if (itunesTrackId && source === 'audius') cache.invalidateAudioSource(itunesTrackId)
      await upstream.body.dump?.()
      return res.status(503).json({ error: 'upstream_expired' })
    }

    // Set X-Direct-URL FIRST so the iOS loader can capture it before bytes flow back.
    res.setHeader('X-Direct-URL', resolvedUrl)
    res.setHeader('X-Source', source)
    if (extractorName) res.setHeader('X-Extractor', extractorName)

    for (const h of RESPONSE_HEADER_PASSTHROUGH) {
      const v = upstream.headers[h]
      if (v != null) res.setHeader(h, v)
    }
    res.status(upstream.statusCode)

    upstream.body.pipe(res)
    upstream.body.on('error', () => {
      try { res.end() } catch { /* ignore */ }
    })
  })

  return router
}
