import { test } from 'node:test'
import assert from 'node:assert/strict'
import { openDb, createCache } from '../../src/db/cache.js'
import { createUrlRefresher } from '../../src/workers/url-refresher.js'

const silentLogger = { log() {}, error() {} }

function freshCache() { return createCache(openDb(':memory:')) }

test('refreshOnce: no candidates returns zeros', async () => {
  const cache = freshCache()
  const refresher = createUrlRefresher(cache, {
    extractStream: async () => { throw new Error('should not be called') },
    logger: silentLogger,
  })
  const stats = await refresher.refreshOnce()
  assert.equal(stats.scanned, 0)
  assert.equal(stats.refreshed, 0)
  assert.equal(stats.failed, 0)
})

test('refreshOnce: skips entries with plenty of TTL remaining', async () => {
  const cache = freshCache()
  // 4h TTL — outside the 2h refresh window
  cache.setStreamUrl('safe', 'https://cdn/safe', 'ytdlp', 4 * 60 * 60 * 1000)
  let calls = 0
  const refresher = createUrlRefresher(cache, {
    extractStream: async () => { calls++; return { url: 'https://cdn/new', extractor: 'ytdlp' } },
    logger: silentLogger,
    perCallDelayMs: 0,
  })
  await refresher.refreshOnce()
  assert.equal(calls, 0, 'extractor should not be called for entries with TTL > threshold')
})

test('refreshOnce: refreshes entries inside the threshold window', async () => {
  const cache = freshCache()
  // 30min TTL — inside the 2h refresh window
  cache.setStreamUrl('soon', 'https://cdn/old', 'ytdlp', 30 * 60 * 1000)
  let extractCalls = []
  const refresher = createUrlRefresher(cache, {
    extractStream: async (videoId) => {
      extractCalls.push(videoId)
      return { url: `https://cdn/new-${videoId}`, extractor: 'piped' }
    },
    logger: silentLogger,
    perCallDelayMs: 0,
  })
  const stats = await refresher.refreshOnce()
  assert.equal(stats.refreshed, 1)
  assert.deepEqual(extractCalls, ['soon'])
  const updated = cache.getStreamUrl('soon')
  assert.equal(updated.url, 'https://cdn/new-soon')
  assert.equal(updated.extractor, 'piped')
  // The new entry should have a far-future expiry (5h default)
  assert.ok(updated.expiresAt > Date.now() + 4 * 60 * 60 * 1000)
})

test('refreshOnce: caps work at maxPerCycle', async () => {
  const cache = freshCache()
  for (let i = 0; i < 10; i++) {
    cache.setStreamUrl(`v${i}`, `https://cdn/${i}`, 'ytdlp', 30 * 60 * 1000)
  }
  let calls = 0
  const refresher = createUrlRefresher(cache, {
    extractStream: async () => { calls++; return { url: 'https://cdn/new', extractor: 'ytdlp' } },
    logger: silentLogger,
    perCallDelayMs: 0,
    maxPerCycle: 3,
  })
  const stats = await refresher.refreshOnce()
  assert.equal(stats.scanned, 3)
  assert.equal(calls, 3)
})

test('refreshOnce: failed extraction invalidates the soon-to-expire entry', async () => {
  const cache = freshCache()
  cache.setStreamUrl('willFail', 'https://cdn/old', 'ytdlp', 30 * 60 * 1000)
  const refresher = createUrlRefresher(cache, {
    extractStream: async () => { throw new Error('extractor down') },
    logger: silentLogger,
    perCallDelayMs: 0,
  })
  const stats = await refresher.refreshOnce()
  assert.equal(stats.refreshed, 0)
  assert.equal(stats.failed, 1)
  // Entry was invalidated so the next /stream-url call re-extracts fresh
  assert.equal(cache.getStreamUrl('willFail'), null)
})

test('refreshOnce: purges already-expired entries', async () => {
  const cache = freshCache()
  cache.setStreamUrl('expired', 'https://cdn/old', 'ytdlp', 1)  // 1ms TTL
  const start = Date.now()
  while (Date.now() - start < 5) { /* spin */ }
  const refresher = createUrlRefresher(cache, {
    extractStream: async () => { throw new Error('should not be called') },
    logger: silentLogger,
    perCallDelayMs: 0,
  })
  const stats = await refresher.refreshOnce()
  assert.equal(stats.purged, 1)
  // The expired entry was outside the (now, now+threshold) window so it's not
  // counted as scanned/refreshed/failed — it goes through the purge path.
  assert.equal(stats.scanned, 0)
})

test('start/stop is idempotent and does not throw', () => {
  const cache = freshCache()
  const refresher = createUrlRefresher(cache, {
    extractStream: async () => ({ url: 'x', extractor: 'y' }),
    logger: silentLogger,
    intervalMs: 60_000,
  })
  refresher.start()
  refresher.start()  // double-start
  refresher.stop()
  refresher.stop()  // double-stop
})
