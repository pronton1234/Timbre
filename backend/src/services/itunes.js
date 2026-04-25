// iTunes Search API client. No auth required.
// Docs: https://performance-partners.apple.com/search-api
import { request } from 'undici'

const BASE = 'https://itunes.apple.com'

function upscaleArtwork(url) {
  if (!url) return null
  return url.replace(/\/\d+x\d+bb\.(jpg|png)$/, '/600x600bb.$1')
}

function mapTrack(raw) {
  return {
    itunesTrackId: raw.trackId,
    isrc: raw.isrc ?? null,
    name: raw.trackName,
    artistName: raw.artistName,
    albumName: raw.collectionName,
    durationMs: raw.trackTimeMillis,
    artworkUrl: upscaleArtwork(raw.artworkUrl100),
    previewUrl: raw.previewUrl,
    releaseDate: raw.releaseDate,
  }
}

function mapAlbum(raw) {
  return {
    itunesCollectionId: raw.collectionId,
    name: raw.collectionName,
    artistName: raw.artistName,
    artworkUrl: upscaleArtwork(raw.artworkUrl100),
    trackCount: raw.trackCount,
    releaseDate: raw.releaseDate,
  }
}

function mapArtist(raw) {
  return {
    itunesArtistId: raw.artistId,
    name: raw.artistName,
    primaryGenre: raw.primaryGenreName,
  }
}

async function fetchJson(url, { retries = 2, timeoutMs = 5000 } = {}) {
  let lastErr
  for (let attempt = 0; attempt <= retries; attempt++) {
    const ctrl = new AbortController()
    const t = setTimeout(() => ctrl.abort(), timeoutMs)
    try {
      const res = await request(url, { signal: ctrl.signal })
      clearTimeout(t)
      if (res.statusCode === 429) {
        const wait = 300 * Math.pow(2, attempt) + Math.random() * 200
        await new Promise(r => setTimeout(r, wait))
        continue
      }
      if (res.statusCode >= 500) throw new Error(`iTunes ${res.statusCode}`)
      return await res.body.json()
    } catch (e) {
      clearTimeout(t)
      lastErr = e
      if (attempt === retries) throw lastErr
      await new Promise(r => setTimeout(r, 200 * (attempt + 1)))
    }
  }
  throw lastErr
}

export async function searchTracks(term, limit = 25) {
  const url = `${BASE}/search?term=${encodeURIComponent(term)}&entity=song&limit=${limit}`
  const json = await fetchJson(url)
  return (json.results ?? []).map(mapTrack)
}

export async function searchAlbums(term, limit = 25) {
  const url = `${BASE}/search?term=${encodeURIComponent(term)}&entity=album&limit=${limit}`
  const json = await fetchJson(url)
  return (json.results ?? []).map(mapAlbum)
}

export async function searchArtists(term, limit = 25) {
  const url = `${BASE}/search?term=${encodeURIComponent(term)}&entity=musicArtist&limit=${limit}`
  const json = await fetchJson(url)
  return (json.results ?? []).map(mapArtist)
}

export async function lookupTrack(itunesTrackId) {
  const url = `${BASE}/lookup?id=${itunesTrackId}&entity=song`
  const json = await fetchJson(url)
  const hit = (json.results ?? []).find(r => r.wrapperType === 'track')
  return hit ? mapTrack(hit) : null
}

export async function albumsByArtist(itunesArtistId, limit = 25) {
  const url = `${BASE}/lookup?id=${itunesArtistId}&entity=album&limit=${limit}`
  const json = await fetchJson(url)
  return (json.results ?? []).filter(r => r.wrapperType === 'collection').map(mapAlbum)
}

export async function tracksByAlbum(itunesCollectionId) {
  const url = `${BASE}/lookup?id=${itunesCollectionId}&entity=song`
  const json = await fetchJson(url)
  return (json.results ?? []).filter(r => r.wrapperType === 'track').map(mapTrack)
}

// Exposed for tests
export const _internal = { upscaleArtwork, mapTrack, mapAlbum, mapArtist }
