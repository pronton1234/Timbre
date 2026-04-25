// Persistent match cache backed by SQLite (better-sqlite3, synchronous).
// Plus an in-memory LRU for short-lived stream URLs (YouTube CDN URLs expire ~6h).
import Database from 'better-sqlite3'
import { createHash } from 'node:crypto'

export function queryHash(artist, title) {
  return createHash('sha1').update(`${(artist ?? '').toLowerCase()}|${(title ?? '').toLowerCase()}`).digest('hex')
}

export function openDb(path) {
  const db = new Database(path)
  db.pragma('journal_mode = WAL')
  db.pragma('synchronous = NORMAL')
  db.exec(`
    CREATE TABLE IF NOT EXISTS matches (
      isrc TEXT PRIMARY KEY,
      itunes_track_id INTEGER,
      youtube_video_id TEXT NOT NULL,
      duration_ms INTEGER,
      match_score INTEGER,
      resolved_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS matches_by_query (
      query_hash TEXT PRIMARY KEY,
      youtube_video_id TEXT NOT NULL,
      resolved_at INTEGER NOT NULL
    );
  `)
  return db
}

export function createCache(db) {
  const getByIsrc = db.prepare('SELECT * FROM matches WHERE isrc = ?')
  const getByQuery = db.prepare('SELECT * FROM matches_by_query WHERE query_hash = ?')
  const putIsrc = db.prepare(`
    INSERT INTO matches (isrc, itunes_track_id, youtube_video_id, duration_ms, match_score, resolved_at)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(isrc) DO UPDATE SET
      youtube_video_id = excluded.youtube_video_id,
      duration_ms = excluded.duration_ms,
      match_score = excluded.match_score,
      resolved_at = excluded.resolved_at
  `)
  const putQuery = db.prepare(`
    INSERT INTO matches_by_query (query_hash, youtube_video_id, resolved_at)
    VALUES (?, ?, ?)
    ON CONFLICT(query_hash) DO UPDATE SET
      youtube_video_id = excluded.youtube_video_id,
      resolved_at = excluded.resolved_at
  `)

  // In-memory stream URL LRU (TTL 10 min)
  const TTL_MS = 10 * 60 * 1000
  const MAX_ENTRIES = 500
  const urlCache = new Map()

  function urlGet(videoId) {
    const entry = urlCache.get(videoId)
    if (!entry) return null
    if (Date.now() - entry.at > TTL_MS) { urlCache.delete(videoId); return null }
    // touch for LRU
    urlCache.delete(videoId); urlCache.set(videoId, entry)
    return entry.url
  }
  function urlPut(videoId, url) {
    if (urlCache.size >= MAX_ENTRIES) {
      const oldestKey = urlCache.keys().next().value
      if (oldestKey !== undefined) urlCache.delete(oldestKey)
    }
    urlCache.set(videoId, { url, at: Date.now() })
  }

  return {
    db,
    getMatchByIsrc(isrc) { return isrc ? getByIsrc.get(isrc) : null },
    getMatchByQuery(artist, title) {
      return getByQuery.get(queryHash(artist, title))
    },
    recordMatch({ isrc, itunesTrackId, videoId, durationMs, matchScore, artist, title }) {
      const now = Date.now()
      const tx = db.transaction(() => {
        if (isrc) putIsrc.run(isrc, itunesTrackId ?? null, videoId, durationMs ?? null, matchScore ?? null, now)
        putQuery.run(queryHash(artist, title), videoId, now)
      })
      tx()
    },
    getStreamUrl: urlGet,
    setStreamUrl: urlPut,
    _urlCacheSize() { return urlCache.size },
  }
}
