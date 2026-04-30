import { test } from 'node:test'
import assert from 'node:assert/strict'
import { openDb, createCache } from '../../src/db/cache.js'
import { createSourceResolver } from '../../src/services/source-resolver.js'

function makeCache() {
  return createCache(openDb(':memory:'))
}

test('resolves from audio_sources cache without calling Audius or extractor', async () => {
  const cache = makeCache()
  cache.setAudioSource(12345, { source: 'audius', sourceTrackId: 'aud_abc', streamUrl: 'https://cdn.audius.co/x.m4a' })
  let audiusCalls = 0, extractCalls = 0
  const resolver = createSourceResolver(cache, {
    findAudiusStreamUrl: async () => { audiusCalls++; return null },
    extractStream: async () => { extractCalls++; throw new Error('should not call') },
  })
  const result = await resolver.resolveBestSource('yt_vid', { itunesTrackId: 12345 })
  assert.equal(result.url, 'https://cdn.audius.co/x.m4a')
  assert.equal(result.source, 'audius')
  assert.equal(result.fromCache, true)
  assert.equal(audiusCalls, 0)
  assert.equal(extractCalls, 0)
})

test('resolves via Audius live search on cache miss, writes audio_sources', async () => {
  const cache = makeCache()
  let extractCalls = 0
  const resolver = createSourceResolver(cache, {
    findAudiusStreamUrl: async ({ title, artist }) => {
      assert.equal(title, 'Sicko Mode')
      assert.equal(artist, 'Travis Scott')
      return { url: 'https://cdn.audius.co/sicko.m4a', audiusTrackId: 'aud_sicko', title: 'Sicko Mode' }
    },
    extractStream: async () => { extractCalls++; throw new Error('should not call') },
  })
  const result = await resolver.resolveBestSource('yt_vid', {
    itunesTrackId: 99999,
    title: 'Sicko Mode',
    artist: 'Travis Scott',
  })
  assert.equal(result.url, 'https://cdn.audius.co/sicko.m4a')
  assert.equal(result.source, 'audius')
  assert.equal(result.fromCache, false)
  assert.equal(extractCalls, 0)
  // Cache should now have the entry
  const cached = cache.getAudioSource(99999)
  assert.equal(cached?.streamUrl, 'https://cdn.audius.co/sicko.m4a')
})

test('falls through to stream_urls cache when Audius has no result', async () => {
  const cache = makeCache()
  cache.setStreamUrl('yt123', 'https://googlevideo.com/x', 'ytdlp')
  let extractCalls = 0
  const resolver = createSourceResolver(cache, {
    findAudiusStreamUrl: async () => null,
    extractStream: async () => { extractCalls++; throw new Error('should not call') },
  })
  const result = await resolver.resolveBestSource('yt123', { title: 'X', artist: 'Y' })
  assert.equal(result.url, 'https://googlevideo.com/x')
  assert.equal(result.source, 'youtube')
  assert.equal(result.fromCache, true)
  assert.equal(extractCalls, 0)
})

test('falls through to live extraction when all caches miss and Audius returns nothing', async () => {
  const cache = makeCache()
  const resolver = createSourceResolver(cache, {
    findAudiusStreamUrl: async () => null,
    extractStream: async (videoId) => {
      assert.equal(videoId, 'cold_vid')
      return { url: 'https://googlevideo.com/fresh', extractor: 'piped' }
    },
  })
  const result = await resolver.resolveBestSource('cold_vid', { title: 'Unknown', artist: 'Artist' })
  assert.equal(result.url, 'https://googlevideo.com/fresh')
  assert.equal(result.source, 'youtube')
  assert.equal(result.extractor, 'piped')
  assert.equal(result.fromCache, false)
  // Extracted URL should be cached in stream_urls
  assert.equal(cache.getStreamUrl('cold_vid')?.url, 'https://googlevideo.com/fresh')
})

test('throws when no videoId and Audius fails', async () => {
  const cache = makeCache()
  const resolver = createSourceResolver(cache, {
    findAudiusStreamUrl: async () => null,
    extractStream: async () => { throw new Error('should not reach') },
  })
  await assert.rejects(
    () => resolver.resolveBestSource(null, { itunesTrackId: 1, title: 'X', artist: 'Y' }),
    /no_video_id/
  )
})

test('skips Audius live search when title or artist missing', async () => {
  const cache = makeCache()
  cache.setStreamUrl('vid_no_meta', 'https://googlevideo.com/nometa', 'cobalt')
  let audiusCalls = 0
  const resolver = createSourceResolver(cache, {
    findAudiusStreamUrl: async () => { audiusCalls++; return null },
    extractStream: async () => { throw new Error('should not call') },
  })
  // Only videoId, no title/artist — should go straight to stream_urls
  const result = await resolver.resolveBestSource('vid_no_meta')
  assert.equal(result.source, 'youtube')
  assert.equal(audiusCalls, 0)
})
