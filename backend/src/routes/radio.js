// GET /radio?artist=<name>&limit=<n>
// Returns a shuffled pool of tracks for radio seeding.
// Strategy: seed artist + top-3 Last.fm similar artists → iTunes search per artist → pool + shuffle.
// All candidates are iTunes-enriched so iOS gets itunesTrackId, artworkUrl, etc.
// Response: { tracks: [...] }  (same Track shape as /search, source='itunes')

import { Router } from 'express'
import * as lastfm from '../services/lastfm-client.js'
import * as itunes from '../services/itunes.js'

const TTL = 6 * 60 * 60 * 1000

// Kept for backwards-compat with existing tests; no-op when pool is per-instance.
export function _resetPool() {}

export function createRadioRouter({
  getSimilarArtists = lastfm.getSimilarArtists,
  searchTracks = itunes.searchTracks,
} = {}) {
  // Per-instance pool: production uses one router (one pool); tests get isolated pools.
  const pool = new Map()
  const router = Router()

  router.get('/radio', async (req, res, next) => {
    try {
      const artist = (req.query.artist ?? '').trim()
      if (!artist) return res.json({ tracks: [] })

      const limit = Math.min(Number(req.query.limit ?? 25), 50)
      const cacheKey = artist.toLowerCase()
      const now = Date.now()
      const cached = pool.get(cacheKey)
      if (cached && cached.expiresAt > now && cached.data.length >= limit) {
        return res.json({ tracks: cached.data.slice(0, limit) })
      }

      // 1. Get similar artists (Last.fm, 3 closest)
      const similar = await getSimilarArtists(artist, { limit: 3 })
      const artists = [artist, ...similar.map(s => s.name)]

      // 2. Fan out: iTunes search per artist (parallel)
      const trackSets = await Promise.allSettled(
        artists.map(a => searchTracks(`${a}`, 15).catch(() => []))
      )
      const combined = trackSets.flatMap(r => r.status === 'fulfilled' ? r.value : [])

      // 3. Deduplicate by itunesTrackId, shuffle
      const seen = new Set()
      const deduped = combined.filter(t => {
        if (seen.has(t.itunesTrackId)) return false
        seen.add(t.itunesTrackId)
        return true
      })
      // Fisher-Yates shuffle
      for (let i = deduped.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1))
        ;[deduped[i], deduped[j]] = [deduped[j], deduped[i]]
      }

      const tracks = deduped.map(t => ({ ...t, source: 'itunes', videoId: null }))
      pool.set(cacheKey, { data: tracks, expiresAt: now + TTL })
      res.json({ tracks: tracks.slice(0, limit) })
    } catch (err) {
      next(err)
    }
  })

  return router
}
