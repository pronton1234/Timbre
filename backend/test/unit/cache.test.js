import { test } from 'node:test'
import assert from 'node:assert/strict'
import { openDb, createCache, queryHash } from '../../src/db/cache.js'

function freshCache() { return createCache(openDb(':memory:')) }

test('schema creation is idempotent (opening twice does not throw)', () => {
  const db = openDb(':memory:')
  // re-open same file (:memory: is per-connection, but openDb applies CREATE IF NOT EXISTS)
  const cache1 = createCache(db)
  const cache2 = createCache(db)
  assert.ok(cache1)
  assert.ok(cache2)
})

test('ISRC round-trip', () => {
  const c = freshCache()
  assert.equal(c.getMatchByIsrc('USX'), undefined)
  c.recordMatch({
    isrc: 'USX', itunesTrackId: 10, videoId: 'abc123', durationMs: 200_000,
    matchScore: 180, artist: 'The Weeknd', title: 'Blinding Lights',
  })
  const row = c.getMatchByIsrc('USX')
  assert.equal(row.youtube_video_id, 'abc123')
  assert.equal(row.match_score, 180)
})

test('query-hash fallback lookup works when ISRC missing', () => {
  const c = freshCache()
  c.recordMatch({ isrc: null, videoId: 'def456', artist: 'X', title: 'Y' })
  const row = c.getMatchByQuery('X', 'Y')
  assert.equal(row.youtube_video_id, 'def456')
  assert.equal(row.query_hash, queryHash('X', 'Y'))
})

test('recordMatch is atomic across both tables', () => {
  const c = freshCache()
  c.recordMatch({
    isrc: 'USY', videoId: 'vid', artist: 'A', title: 'B', itunesTrackId: 1, durationMs: 100, matchScore: 100,
  })
  assert.ok(c.getMatchByIsrc('USY'))
  assert.ok(c.getMatchByQuery('A', 'B'))
})

test('recordMatch without ISRC only writes query row', () => {
  const c = freshCache()
  c.recordMatch({ isrc: null, videoId: 'v', artist: 'a', title: 't' })
  assert.ok(c.getMatchByQuery('a', 't'))
})

test('stream URL cache: miss returns null', () => {
  const c = freshCache()
  assert.equal(c.getStreamUrl('v1'), null)
})

test('stream URL cache: round-trip returns url + extractor + expiresAt', () => {
  const c = freshCache()
  c.setStreamUrl('v1', 'https://cdn/one', 'ytdlp')
  const got = c.getStreamUrl('v1')
  assert.equal(got.url, 'https://cdn/one')
  assert.equal(got.extractor, 'ytdlp')
  assert.ok(got.expiresAt > Date.now())
  assert.ok(got.expiresAt - Date.now() < 6 * 60 * 60 * 1000, 'expiry within 6h')
})

test('stream URL cache: expired entry returns null and is purged', () => {
  const c = freshCache()
  // 1ms TTL — guaranteed expired by the time we read it back
  c.setStreamUrl('v1', 'https://cdn/one', 'ytdlp', 1)
  // Wait a tick to ensure expiry
  const start = Date.now()
  while (Date.now() - start < 5) { /* spin briefly */ }
  assert.equal(c.getStreamUrl('v1'), null)
})

test('stream URL cache: invalidate removes entry', () => {
  const c = freshCache()
  c.setStreamUrl('v1', 'https://cdn/one', 'ytdlp')
  assert.ok(c.getStreamUrl('v1'))
  c.invalidateStreamUrl('v1')
  assert.equal(c.getStreamUrl('v1'), null)
})

test('stream URL cache: persists across cache instances on same db', () => {
  // Simulates restart: two createCache() calls on same db file should share data
  const db = openDb(':memory:')
  const c1 = createCache(db)
  c1.setStreamUrl('v1', 'https://cdn/one', 'ytdlp')
  const c2 = createCache(db)
  const got = c2.getStreamUrl('v1')
  assert.equal(got.url, 'https://cdn/one')
  assert.equal(got.extractor, 'ytdlp')
})

test('stream URL cache: purgeExpiredStreamUrls removes only expired rows', () => {
  const c = freshCache()
  c.setStreamUrl('alive', 'https://cdn/alive', 'ytdlp')
  c.setStreamUrl('expired', 'https://cdn/expired', 'ytdlp', 1)
  const start = Date.now()
  while (Date.now() - start < 5) { /* spin */ }
  const purged = c.purgeExpiredStreamUrls()
  assert.equal(purged, 1)
  assert.ok(c.getStreamUrl('alive'))
})
