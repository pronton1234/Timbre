// POST /prefetch
// Body: { tracks: [ { videoId, itunesTrackId, title, artist, isrc }, ... ] }
//
// Warms the audio source cache for up to 20 tracks in the background.
// iOS calls this after search results render so tracks are cached before the user taps.
// The endpoint responds immediately with 202; resolution runs asynchronously.
import express from 'express'
import { createSourceResolver } from '../services/source-resolver.js'

const MAX_TRACKS = 20
const INTER_TRACK_DELAY_MS = 100  // avoid hammering Audius/YouTube in bursts

export function createPrefetchRouter(cache, deps = {}) {
  const resolver = createSourceResolver(cache, {
    extractStream: deps.extractStream,
    findAudiusStreamUrl: deps.findAudiusStreamUrl,
  })
  const router = express.Router()

  router.post('/prefetch', express.json({ limit: '16kb' }), (req, res) => {
    const raw = req.body?.tracks
    if (!Array.isArray(raw) || raw.length === 0) {
      return res.status(400).json({ error: 'no_tracks' })
    }
    const tracks = raw.slice(0, MAX_TRACKS)

    // Respond immediately — resolution is fire-and-forget.
    res.status(202).json({ queued: tracks.length })

    // Staggered sequential resolution so we don't spike outbound connections.
    ;(async () => {
      for (const t of tracks) {
        const videoId = t.videoId ? String(t.videoId).trim() : null
        const itunesTrackId = Number(t.itunesTrackId) || null
        const title = t.title ? String(t.title).trim() : null
        const artist = t.artist ? String(t.artist).trim() : null
        const isrc = t.isrc ? String(t.isrc).trim() : null
        if (!videoId && !itunesTrackId) continue
        try {
          await resolver.resolveBestSource(videoId, { itunesTrackId, title, artist, isrc })
        } catch { /* ignore — this is best-effort */ }
        await new Promise(r => setTimeout(r, INTER_TRACK_DELAY_MS))
      }
    })()
  })

  return router
}
