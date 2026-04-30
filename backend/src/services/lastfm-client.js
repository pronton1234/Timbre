// Last.fm API client — free, no per-request auth, just an API key.
// LASTFM_API_KEY env var (get one at https://www.last.fm/api/account/create).
// All results are cached in-memory for the given TTL to avoid hammering the API.
import { request } from 'undici'

const BASE = 'https://ws.audioscrobbler.com/2.0'
const API_KEY = process.env.LASTFM_API_KEY ?? ''

// In-memory cache: key → { data, expiresAt }
const cache = new Map()

async function callApi(params, ttlMs = 24 * 60 * 60 * 1000) {
  if (!API_KEY) return null
  const qs = new URLSearchParams({ ...params, api_key: API_KEY, format: 'json' })
  const key = qs.toString()
  const now = Date.now()
  const cached = cache.get(key)
  if (cached && cached.expiresAt > now) return cached.data

  const url = `${BASE}/?${key}`
  try {
    const ctrl = new AbortController()
    const timeout = setTimeout(() => ctrl.abort(), 8000)
    const res = await request(url, { signal: ctrl.signal })
    clearTimeout(timeout)
    if (res.statusCode !== 200) { await res.body.dump(); return null }
    const json = await res.body.json()
    if (json.error) return null
    cache.set(key, { data: json, expiresAt: now + ttlMs })
    return json
  } catch {
    return null
  }
}

/**
 * Fetch the top N tracks for an artist by name.
 * Returns [{ name, playcount, mbid, url }], sorted by playcount desc.
 */
export async function getArtistTopTracks(artist, { limit = 20 } = {}) {
  const json = await callApi({ method: 'artist.getTopTracks', artist, limit: String(limit) })
  if (!json?.toptracks?.track) return []
  const tracks = Array.isArray(json.toptracks.track) ? json.toptracks.track : [json.toptracks.track]
  return tracks.map(t => ({
    name: t.name,
    playcount: Number(t.playcount ?? 0),
    mbid: t.mbid || null,
    url: t.url,
  }))
}

/**
 * Fetch similar artists for `artist`. Returns [{ name, match }] (match 0–1).
 */
export async function getSimilarArtists(artist, { limit = 10 } = {}) {
  const json = await callApi({ method: 'artist.getSimilar', artist, limit: String(limit) }, 6 * 60 * 60 * 1000)
  if (!json?.similarartists?.artist) return []
  const artists = Array.isArray(json.similarartists.artist) ? json.similarartists.artist : [json.similarartists.artist]
  return artists.map(a => ({ name: a.name, match: parseFloat(a.match ?? 0) }))
}

/** Clear the in-memory cache (tests only). */
export function _resetCache() { cache.clear() }
