// GET /artist-top-tracks?artist=<name>&artistId=<itunesArtistId>
//
// Returns Last.fm top tracks enriched with iTunes metadata (artwork, durationMs,
// itunesTrackId). Falls back to iTunes popularity ranking if Last.fm is unavailable.
//
// Response: { tracks: [...] }  (same Track shape as /search)

import { Router } from 'express'
import * as lastfm from '../services/lastfm-client.js'
import * as itunes from '../services/itunes.js'

// In-memory cache: artist name → { data, expiresAt }  (24h TTL)
const topTracksCache = new Map()
const TTL = 24 * 60 * 60 * 1000

export function createArtistTopTracksRouter() {
  const router = Router()

  router.get('/artist-top-tracks', async (req, res, next) => {
    try {
      const artist = (req.query.artist ?? '').trim()
      if (!artist) return res.json({ tracks: [] })

      const cacheKey = artist.toLowerCase()
      const now = Date.now()
      const cached = topTracksCache.get(cacheKey)
      if (cached && cached.expiresAt > now) return res.json({ tracks: cached.data })

      // 1. Fetch Last.fm top tracks (name + playcount only)
      const lfmTracks = await lastfm.getArtistTopTracks(artist, { limit: 20 })

      let result = []
      if (lfmTracks.length > 0) {
        // 2. Enrich each top-track name with iTunes metadata (artwork, duration, trackId)
        const enriched = await Promise.allSettled(
          lfmTracks.slice(0, 10).map(async lfm => {
            const hits = await itunes.searchTracks(`${lfm.name} ${artist}`, 3).catch(() => [])
            const match = hits.find(h =>
              h.name.toLowerCase().includes(lfm.name.toLowerCase()) ||
              lfm.name.toLowerCase().includes(h.name.toLowerCase())
            ) ?? hits[0]
            if (!match) return null
            return { ...match, source: 'itunes', _playcount: lfm.playcount }
          })
        )
        result = enriched
          .flatMap(r => r.status === 'fulfilled' && r.value ? [r.value] : [])
          .sort((a, b) => (b._playcount ?? 0) - (a._playcount ?? 0))
          .filter((t, i, arr) => arr.findIndex(x => x.itunesTrackId === t.itunesTrackId) === i)
          .map(({ _playcount, ...t }) => t)
      }

      // 3. Fallback: iTunes albumsByArtist → first album tracks if Last.fm returns nothing
      if (result.length === 0 && req.query.artistId) {
        const artistId = Number(req.query.artistId)
        if (!isNaN(artistId)) {
          const albums = await itunes.albumsByArtist(artistId, 3).catch(() => [])
          if (albums.length > 0) {
            const albumTracks = await itunes.tracksByAlbum(albums[0].itunesCollectionId).catch(() => [])
            result = albumTracks.slice(0, 10).map(t => ({ ...t, source: 'itunes' }))
          }
        }
      }

      topTracksCache.set(cacheKey, { data: result, expiresAt: now + TTL })
      res.json({ tracks: result })
    } catch (err) {
      next(err)
    }
  })

  return router
}
