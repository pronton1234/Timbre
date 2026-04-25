// GET /resolve?isrc=&title=&artist=&durationMs=&itunesTrackId=
//
// After the Option C architecture shift (Apr 2026), this endpoint ONLY does the
// iTunes→YouTube videoId match. Stream URL extraction has moved on-device via
// YouTubeKit, because YouTube IP-gates *.googlevideo.com for datacenter IPs
// (~15-25% failure rate for major-label US tracks from our Oracle VM).
//
// Response: { videoId, source: 'cache'|'fresh', matchScore? }
import express from 'express'
import { pickBest } from '../services/youtube-match.js'
import * as extractor from '../services/extractor/index.js'

export function createResolveRouter(cache) {
  const router = express.Router()

  router.get('/resolve', async (req, res) => {
    const { isrc, title, artist, durationMs, itunesTrackId } = req.query
    if (!title || !artist) {
      return res.status(400).json({ error: 'title and artist are required' })
    }

    try {
      // Step 1: look up existing videoId match (ISRC, then artist|title hash)
      let videoId = null
      const byIsrc = cache.getMatchByIsrc(isrc)
      if (byIsrc) videoId = byIsrc.youtube_video_id
      if (!videoId) {
        const byQuery = cache.getMatchByQuery(artist, title)
        if (byQuery) videoId = byQuery.youtube_video_id
      }
      if (videoId) {
        return res.json({ videoId, source: 'cache' })
      }

      // Step 2: search YouTube, pick best match, persist
      const candidates = await extractor.search(`${artist} ${title}`, 5)
      const best = pickBest(candidates, {
        name: title, artistName: artist, durationMs: Number(durationMs) || 0,
      })
      if (!best) return res.status(404).json({ error: 'no acceptable youtube match' })
      videoId = best.id
      cache.recordMatch({
        isrc: isrc || null,
        itunesTrackId: itunesTrackId ? Number(itunesTrackId) : null,
        videoId,
        durationMs: Number(durationMs) || null,
        matchScore: best.matchScore,
        artist, title,
      })
      return res.json({ videoId, source: 'fresh', matchScore: best.matchScore })
    } catch (e) {
      req.app.get('logger')?.error?.('/resolve failed', e)
      return res.status(502).json({ error: 'match_failed', detail: String(e.message ?? e) })
    }
  })

  return router
}
