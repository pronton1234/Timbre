// Audius public API client.
// Audius returns direct CDN stream URLs — no extraction step needed.
// API docs: https://audiusproject.github.io/api-docs/
import { request as undiciRequest } from 'undici'

const DISCOVERY_ENDPOINT = 'https://api.audius.co'
const APP_NAME = 'timbre'
const SEARCH_TIMEOUT_MS = 3000
const HOST_CACHE_TTL_MS = 10 * 60 * 1000  // re-pick node every 10 min

let _cachedHost = null
let _hostCachedAt = 0

// Pick the first healthy Audius discovery node. Cached for 10 min.
async function getHost(fetchFn) {
  if (_cachedHost && Date.now() - _hostCachedAt < HOST_CACHE_TTL_MS) return _cachedHost
  try {
    const { statusCode, body } = await fetchFn(DISCOVERY_ENDPOINT, {
      method: 'GET',
      headersTimeout: 2000,
      bodyTimeout: 2000,
    })
    if (statusCode !== 200) { await body.dump?.(); return null }
    const json = await body.json()
    // Response: { "data": ["https://discoveryprovider.audius.co", ...] }
    const hosts = json?.data
    if (Array.isArray(hosts) && hosts.length > 0) {
      _cachedHost = hosts[0].replace(/\/$/, '')
      _hostCachedAt = Date.now()
      return _cachedHost
    }
  } catch { /* fall through */ }
  return null
}

// Exported only for tests — resets the cached host so getHost() re-fetches.
export function _resetHostCache() { _cachedHost = null; _hostCachedAt = 0 }

// Search Audius for a track by title + artist (and optionally ISRC).
// Returns the best matching Audius track object or null on miss/error.
export async function searchTrack({ title, artist, isrc } = {}, { fetchFn = undiciRequest } = {}) {
  if (!title && !artist) return null
  const host = await getHost(fetchFn)
  if (!host) return null

  const query = encodeURIComponent([title, artist].filter(Boolean).join(' '))
  const url = `${host}/v1/tracks/search?query=${query}&limit=5&app_name=${APP_NAME}`
  try {
    const { statusCode, body } = await fetchFn(url, {
      method: 'GET',
      headersTimeout: SEARCH_TIMEOUT_MS,
      bodyTimeout: SEARCH_TIMEOUT_MS,
    })
    if (statusCode !== 200) { await body.dump?.(); return null }
    const json = await body.json()
    const tracks = json?.data
    if (!Array.isArray(tracks) || tracks.length === 0) return null

    // Prefer ISRC-matched result when provided
    if (isrc) {
      const exact = tracks.find(t =>
        t.isrc && t.isrc.replace(/-/g, '').toLowerCase() === isrc.replace(/-/g, '').toLowerCase()
      )
      if (exact) return exact
    }

    return tracks[0]
  } catch { return null }
}

// Resolve the direct CDN stream URL for an Audius track ID by following the
// /stream redirect. Returns the final CDN URL or null on failure.
export async function resolveStreamUrl(audiusTrackId, { fetchFn = undiciRequest } = {}) {
  const host = await getHost(fetchFn)
  if (!host) return null

  let currentUrl = `${host}/v1/tracks/${audiusTrackId}/stream?app_name=${APP_NAME}`

  for (let hop = 0; hop < 4; hop++) {
    let statusCode, headers, body
    try {
      ;({ statusCode, headers, body } = await fetchFn(currentUrl, {
        method: 'GET',
        maxRedirections: 0,
        headersTimeout: 2000,
        bodyTimeout: 1000,
      }))
    } catch { return null }

    if (statusCode === 301 || statusCode === 302 || statusCode === 307 || statusCode === 308) {
      const loc = headers?.location
      if (!loc) { await body.dump?.(); return null }
      await body.dump?.()
      currentUrl = loc.startsWith('http') ? loc : `${host}${loc}`
      continue
    }

    if (statusCode === 200 || statusCode === 206) {
      // Body is the stream — dump it; we only need the URL
      await body.dump?.()
      return currentUrl
    }

    await body.dump?.()
    return null
  }

  return null
}

// High-level helper: search + resolve in one call.
// Returns { url, audiusTrackId, title } or null.
export async function findStreamUrl({ title, artist, isrc } = {}, { fetchFn = undiciRequest } = {}) {
  const track = await searchTrack({ title, artist, isrc }, { fetchFn })
  if (!track?.id) return null
  const url = await resolveStreamUrl(track.id, { fetchFn })
  if (!url) return null
  return { url, audiusTrackId: track.id, title: track.title }
}
