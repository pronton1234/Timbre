// Unified search: fans out to iTunes + YouTube Music, merges and deduplicates.
// Response shape:
//   { tracks: [...], albums: [...], artists: [...] }
//
// Track shape:
//   { itunesTrackId, name, artistName, albumName, artistId, durationMs,
//     artworkUrl, isrc, previewUrl, videoId, source }
//
// For YouTube Music-only results (source='yt'), itunesTrackId is a stable
// negative hash of the videoId — negative so it never collides with real iTunes IDs.

import { Router } from 'express'
import * as itunes from '../services/itunes.js'
import * as extractor from '../services/extractor/index.js'

// Stable negative int ID from a YouTube videoId string.
function ytPseudoId(videoId) {
  let h = 5381
  for (let i = 0; i < videoId.length; i++) {
    h = ((h * 33) ^ videoId.charCodeAt(i)) & 0x7fffffff
  }
  return -(h || 1)
}

// Normalise a track name/artist for deduplication comparison.
function normalise(s) {
  return (s ?? '').toLowerCase().replace(/[^a-z0-9 ]/g, '').replace(/\s+/g, ' ').trim()
}

// Rough overlap check — true if two tracks are likely the same recording.
function overlaps(a, b) {
  const aN = normalise(a.name); const bN = normalise(b.name)
  const aArt = normalise(a.artistName); const bArt = normalise(b.artistName)
  // Same normalised title + artist shares first word match
  if (aN === bN && aArt.split(' ')[0] === bArt.split(' ')[0]) return true
  // ISRC match (most reliable)
  if (a.isrc && b.isrc && a.isrc === b.isrc) return true
  return false
}

export function createSearchRouter({
  searchTracks = itunes.searchTracks,
  searchAlbums = itunes.searchAlbums,
  searchArtists = itunes.searchArtists,
  searchYtm = (q, n) => extractor.search(q, n),
} = {}) {
  const router = Router()

  router.get('/search', async (req, res, next) => {
    try {
      const q = (req.query.q ?? '').trim()
      if (!q) return res.json({ tracks: [], albums: [], artists: [] })

      const limit = Math.min(Number(req.query.limit ?? 25), 50)

      // Fan out in parallel: iTunes (tracks + albums + artists) + YTM (tracks only)
      const [itunesTracks, itunesAlbums, itunesArtists, ytmVideos] = await Promise.allSettled([
        searchTracks(q, limit),
        searchAlbums(q, limit),
        searchArtists(q, limit),
        searchYtm(q, 15),
      ]).then(rs => rs.map(r => r.status === 'fulfilled' ? r.value : []))

      // Merge tracks: iTunes first (have full metadata), then YTM supplements
      const merged = [...itunesTracks]
      for (const v of ytmVideos) {
        if (!v.id || !v.title) continue
        const candidate = { name: v.title, artistName: v.channel, isrc: null }
        const alreadyPresent = merged.some(t => overlaps(t, candidate))
        if (alreadyPresent) continue
        merged.push({
          itunesTrackId: ytPseudoId(v.id),
          name: v.title,
          artistName: v.channel,
          albumName: null,
          artistId: null,
          durationMs: (v.duration ?? 0) * 1000,
          artworkUrl: null,
          isrc: null,
          previewUrl: null,
          videoId: v.id,
          source: 'yt',
        })
      }

      // Add source field to iTunes tracks
      const tracks = merged.map(t => ({
        itunesTrackId: t.itunesTrackId,
        name: t.name,
        artistName: t.artistName,
        albumName: t.albumName ?? null,
        artistId: t.artistId ?? null,
        durationMs: t.durationMs ?? 0,
        artworkUrl: t.artworkUrl ?? null,
        isrc: t.isrc ?? null,
        previewUrl: t.previewUrl ?? null,
        videoId: t.videoId ?? null,
        source: t.source ?? 'itunes',
      }))

      res.json({ tracks, albums: itunesAlbums, artists: itunesArtists })
    } catch (err) {
      next(err)
    }
  })

  return router
}
