import { test } from 'node:test'
import assert from 'node:assert/strict'
import express from 'express'
import { request } from 'undici'
import { openDb, createCache } from '../../src/db/cache.js'
import { createStreamUrlRouter } from '../../src/routes/streamUrl.js'

function makeApp({ extractStream }) {
  const cache = createCache(openDb(':memory:'))
  const app = express()
  app.use(createStreamUrlRouter(cache, { extractStream }))
  return { app, cache }
}

async function listen(app) {
  return new Promise((resolve) => {
    const server = app.listen(0, '127.0.0.1', () => {
      const port = server.address().port
      resolve({ server, baseUrl: `http://127.0.0.1:${port}` })
    })
  })
}

test('GET /stream-url without videoId returns 400', async () => {
  const { app } = makeApp({ extractStream: async () => { throw new Error('should not be called') } })
  const { server, baseUrl } = await listen(app)
  try {
    const res = await request(`${baseUrl}/stream-url`)
    assert.equal(res.statusCode, 400)
    const body = await res.body.json()
    assert.equal(body.error, 'no_video_id')
  } finally { server.close() }
})

test('GET /stream-url cache miss invokes extractor and writes back', async () => {
  let calls = 0
  const fakeUrl = 'https://rr1.googlevideo.com/videoplayback?id=test'
  const { app, cache } = makeApp({
    extractStream: async (videoId) => {
      calls++
      assert.equal(videoId, 'abc123')
      return { url: fakeUrl, extractor: 'ytdlp' }
    },
  })
  const { server, baseUrl } = await listen(app)
  try {
    const res = await request(`${baseUrl}/stream-url?videoId=abc123`)
    assert.equal(res.statusCode, 200)
    const body = await res.body.json()
    assert.equal(body.videoId, 'abc123')
    assert.equal(body.url, fakeUrl)
    assert.equal(body.extractor, 'ytdlp')
    assert.equal(body.source, 'fresh')
    assert.ok(body.expiresAt > Date.now())
    assert.equal(calls, 1)
    // Cache should now have it
    assert.equal(cache.getStreamUrl('abc123').url, fakeUrl)
  } finally { server.close() }
})

test('GET /stream-url cache hit returns immediately without extractor', async () => {
  const fakeUrl = 'https://rr1.googlevideo.com/videoplayback?id=cached'
  const { app, cache } = makeApp({
    extractStream: async () => { throw new Error('extractor must not be called on cache hit') },
  })
  cache.setStreamUrl('cachedVid', fakeUrl, 'piped')
  const { server, baseUrl } = await listen(app)
  try {
    const res = await request(`${baseUrl}/stream-url?videoId=cachedVid`)
    assert.equal(res.statusCode, 200)
    const body = await res.body.json()
    assert.equal(body.url, fakeUrl)
    assert.equal(body.extractor, 'piped')
    assert.equal(body.source, 'cache')
  } finally { server.close() }
})

test('GET /stream-url returns 503 when all extractors fail', async () => {
  const { app } = makeApp({
    extractStream: async () => { throw new Error('all extractors failed') },
  })
  const { server, baseUrl } = await listen(app)
  try {
    const res = await request(`${baseUrl}/stream-url?videoId=brokenVid`)
    assert.equal(res.statusCode, 503)
    const body = await res.body.json()
    assert.equal(body.error, 'extraction_failed')
    assert.match(body.detail, /all extractors failed/)
  } finally { server.close() }
})

test('GET /stream-url two sequential calls hit extractor exactly once', async () => {
  let calls = 0
  const fakeUrl = 'https://rr1.googlevideo.com/videoplayback?id=once'
  const { app } = makeApp({
    extractStream: async () => {
      calls++
      return { url: fakeUrl, extractor: 'ytdlp' }
    },
  })
  const { server, baseUrl } = await listen(app)
  try {
    const r1 = await request(`${baseUrl}/stream-url?videoId=once`)
    const b1 = await r1.body.json()
    const r2 = await request(`${baseUrl}/stream-url?videoId=once`)
    const b2 = await r2.body.json()
    assert.equal(b1.source, 'fresh')
    assert.equal(b2.source, 'cache')
    assert.equal(calls, 1)
  } finally { server.close() }
})
