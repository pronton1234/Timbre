import { test } from 'node:test'
import assert from 'node:assert/strict'
import express from 'express'
import { request } from 'undici'
import { openDb, createCache } from '../../src/db/cache.js'
import { createPrefetchRouter } from '../../src/routes/prefetch.js'

function makeApp(deps = {}) {
  const cache = createCache(openDb(':memory:'))
  const app = express()
  app.use(createPrefetchRouter(cache, deps))
  return { app, cache }
}

async function listen(app) {
  return new Promise(resolve => {
    const server = app.listen(0, '127.0.0.1', () => {
      resolve({ server, baseUrl: `http://127.0.0.1:${server.address().port}` })
    })
  })
}

// Wait until the audio_sources or stream_urls cache is populated (background resolve).
async function waitForCache(cache, checkFn, timeoutMs = 2000) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    if (checkFn(cache)) return true
    await new Promise(r => setTimeout(r, 50))
  }
  return false
}

test('POST /prefetch returns 400 when tracks array missing', async () => {
  const { app } = makeApp()
  const { server, baseUrl } = await listen(app)
  try {
    const res = await request(`${baseUrl}/prefetch`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({}),
    })
    assert.equal(res.statusCode, 400)
  } finally { server.close() }
})

test('POST /prefetch returns 202 immediately and resolves in background', async () => {
  let resolveCalls = 0
  const { app, cache } = makeApp({
    findAudiusStreamUrl: async () => null,
    extractStream: async (videoId) => {
      resolveCalls++
      return { url: `https://googlevideo.com/${videoId}`, extractor: 'ytdlp' }
    },
  })
  const { server, baseUrl } = await listen(app)
  try {
    const res = await request(`${baseUrl}/prefetch`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ tracks: [{ videoId: 'vid1' }, { videoId: 'vid2' }] }),
    })
    assert.equal(res.statusCode, 202)
    const body = await res.body.json()
    assert.equal(body.queued, 2)
    // Background resolve should populate stream_urls
    const populated = await waitForCache(cache, c => c.getStreamUrl('vid1') !== null && c.getStreamUrl('vid2') !== null)
    assert.ok(populated, 'stream_urls should be populated within 2s')
    assert.equal(cache.getStreamUrl('vid1').url, 'https://googlevideo.com/vid1')
    assert.equal(cache.getStreamUrl('vid2').url, 'https://googlevideo.com/vid2')
  } finally { server.close() }
})

test('POST /prefetch caps at 20 tracks', async () => {
  let resolveCalls = 0
  const { app } = makeApp({
    findAudiusStreamUrl: async () => null,
    extractStream: async () => { resolveCalls++; return { url: 'https://x', extractor: 'ytdlp' } },
  })
  const { server, baseUrl } = await listen(app)
  try {
    const tracks = Array.from({ length: 30 }, (_, i) => ({ videoId: `vid${i}` }))
    const res = await request(`${baseUrl}/prefetch`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ tracks }),
    })
    const body = await res.body.json()
    assert.equal(body.queued, 20)
    // Wait for background to finish
    await new Promise(r => setTimeout(r, 2500))
    assert.equal(resolveCalls, 20)
  } finally { server.close() }
})

test('POST /prefetch with Audius metadata warms audio_sources cache', async () => {
  const { app, cache } = makeApp({
    findAudiusStreamUrl: async ({ title, artist }) => {
      if (title === 'Goosebumps' && artist === 'Travis Scott') {
        return { url: 'https://cdn.audius.co/goosebumps.m4a', audiusTrackId: 'aud_gb', title: 'Goosebumps' }
      }
      return null
    },
    extractStream: async () => { throw new Error('should not call') },
  })
  const { server, baseUrl } = await listen(app)
  try {
    await request(`${baseUrl}/prefetch`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        tracks: [{ videoId: 'yt_gb', itunesTrackId: 77777, title: 'Goosebumps', artist: 'Travis Scott' }],
      }),
    })
    const populated = await waitForCache(cache, c => c.getAudioSource(77777) !== null)
    assert.ok(populated, 'audio_sources should be populated within 2s')
    assert.equal(cache.getAudioSource(77777)?.streamUrl, 'https://cdn.audius.co/goosebumps.m4a')
  } finally { server.close() }
})
