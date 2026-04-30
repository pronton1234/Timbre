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
    CREATE TABLE IF NOT EXISTS stream_urls (
      video_id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      extractor TEXT,
      resolved_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_stream_urls_expires_at ON stream_urls(expires_at);
    CREATE TABLE IF NOT EXISTS audio_sources (
      itunes_track_id INTEGER PRIMARY KEY,
      source TEXT NOT NULL,
      source_track_id TEXT,
      stream_url TEXT NOT NULL,
      resolved_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_audio_sources_expires_at ON audio_sources(expires_at);
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

  // Stream URL cache: in-memory LRU (hot path, sub-ms) backed by SQLite (warm path, ~1-2ms,
  // survives restart). googlevideo URLs are signed for ~6h; we use 5h as safety margin.
  const URL_TTL_MS = 5 * 60 * 60 * 1000   // 5h
  const URL_MAX_MEM_ENTRIES = 1000
  const memUrlCache = new Map()

  const getUrlStmt = db.prepare('SELECT url, extractor, expires_at FROM stream_urls WHERE video_id = ?')
  const putUrlStmt = db.prepare(`
    INSERT INTO stream_urls (video_id, url, extractor, resolved_at, expires_at)
    VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(video_id) DO UPDATE SET
      url = excluded.url,
      extractor = excluded.extractor,
      resolved_at = excluded.resolved_at,
      expires_at = excluded.expires_at
  `)
  const deleteUrlStmt = db.prepare('DELETE FROM stream_urls WHERE video_id = ?')
  const purgeExpiredStmt = db.prepare('DELETE FROM stream_urls WHERE expires_at < ?')

  function urlGet(videoId) {
    const now = Date.now()
    const memEntry = memUrlCache.get(videoId)
    if (memEntry) {
      if (memEntry.expiresAt > now) {
        memUrlCache.delete(videoId); memUrlCache.set(videoId, memEntry)  // touch for LRU
        return { url: memEntry.url, extractor: memEntry.extractor, expiresAt: memEntry.expiresAt }
      }
      memUrlCache.delete(videoId)
    }
    const dbEntry = getUrlStmt.get(videoId)
    if (!dbEntry) return null
    if (dbEntry.expires_at <= now) {
      deleteUrlStmt.run(videoId)
      return null
    }
    const result = { url: dbEntry.url, extractor: dbEntry.extractor, expiresAt: dbEntry.expires_at }
    memUrlCache.set(videoId, result)
    if (memUrlCache.size > URL_MAX_MEM_ENTRIES) {
      const oldestKey = memUrlCache.keys().next().value
      if (oldestKey !== undefined) memUrlCache.delete(oldestKey)
    }
    return result
  }

  function urlPut(videoId, url, extractor = null, ttlMs = URL_TTL_MS) {
    const now = Date.now()
    const expiresAt = now + ttlMs
    putUrlStmt.run(videoId, url, extractor, now, expiresAt)
    if (memUrlCache.size >= URL_MAX_MEM_ENTRIES) {
      const oldestKey = memUrlCache.keys().next().value
      if (oldestKey !== undefined) memUrlCache.delete(oldestKey)
    }
    memUrlCache.set(videoId, { url, extractor, expiresAt })
  }

  function urlInvalidate(videoId) {
    memUrlCache.delete(videoId)
    deleteUrlStmt.run(videoId)
  }

  function urlPurgeExpired() {
    return purgeExpiredStmt.run(Date.now()).changes
  }

  // audio_sources cache — keyed by iTunes track ID, holds the best resolved stream URL
  // (Audius CDN, or any other non-YouTube source). TTL: 24h for Audius (stable CDN URLs).
  const AUDIO_SOURCE_TTL_MS = 24 * 60 * 60 * 1000  // 24h
  const getAudioSourceStmt = db.prepare(
    'SELECT source, source_track_id, stream_url, expires_at FROM audio_sources WHERE itunes_track_id = ?'
  )
  const putAudioSourceStmt = db.prepare(`
    INSERT INTO audio_sources (itunes_track_id, source, source_track_id, stream_url, resolved_at, expires_at)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(itunes_track_id) DO UPDATE SET
      source = excluded.source,
      source_track_id = excluded.source_track_id,
      stream_url = excluded.stream_url,
      resolved_at = excluded.resolved_at,
      expires_at = excluded.expires_at
  `)
  const deleteAudioSourceStmt = db.prepare('DELETE FROM audio_sources WHERE itunes_track_id = ?')
  const purgeExpiredAudioSourcesStmt = db.prepare('DELETE FROM audio_sources WHERE expires_at < ?')

  function audioSourceGet(itunesTrackId) {
    if (!itunesTrackId) return null
    const now = Date.now()
    const row = getAudioSourceStmt.get(itunesTrackId)
    if (!row) return null
    if (row.expires_at <= now) { deleteAudioSourceStmt.run(itunesTrackId); return null }
    return { source: row.source, sourceTrackId: row.source_track_id, streamUrl: row.stream_url, expiresAt: row.expires_at }
  }

  function audioSourcePut(itunesTrackId, { source, sourceTrackId, streamUrl }, ttlMs = AUDIO_SOURCE_TTL_MS) {
    const now = Date.now()
    putAudioSourceStmt.run(itunesTrackId, source, sourceTrackId ?? null, streamUrl, now, now + ttlMs)
  }

  function audioSourceInvalidate(itunesTrackId) {
    deleteAudioSourceStmt.run(itunesTrackId)
  }

  function audioSourcePurgeExpired() {
    return purgeExpiredAudioSourcesStmt.run(Date.now()).changes
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
    invalidateStreamUrl: urlInvalidate,
    purgeExpiredStreamUrls: urlPurgeExpired,
    _urlCacheSize() { return memUrlCache.size },
    getAudioSource: audioSourceGet,
    setAudioSource: audioSourcePut,
    invalidateAudioSource: audioSourceInvalidate,
    purgeExpiredAudioSources: audioSourcePurgeExpired,
  }
}
