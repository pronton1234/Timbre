import { test } from 'node:test'
import assert from 'node:assert/strict'
import express from 'express'
import { request } from 'undici'
import { Readable } from 'node:stream'
import { openDb, createCache } from '../../src/db/cache.js'
import { createPlayRouter } from '../../src/routes/play.js'

function makeApp({ extractStream, fetchUpstream, findAudiusStreamUrl } = {}) {
  const cache = createCache(openDb(':memory:'))
  const app = express()
  app.use(createPlayRouter(cache, { extractStream, fetchUpstream, findAudiusStreamUrl }))
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

function fakeUpstreamResponse({ statusCode = 206, headers = {}, body = 'AUDIO_BYTES' } = {}) {
  return async (_url, _opts) => ({
    statusCode,
    headers: { 'content-type': 'audio/mp4', 'accept-ranges': 'bytes', ...headers },
    body: Readable.from([Buffer.from(body)]),
  })
}

test('GET /play without videoId returns 400', async () => {
  const { app } = makeApp({
    extractStream: async () => { throw new Error('should not be called') },
    fetchUpstream: async () => { throw new Error('should not be called') },
  })
  const { server, baseUrl } = await listen(app)
  try {
    const res = await request(`${baseUrl}/play`)
    assert.equal(res.statusCode, 400)
  } finally { server.close() }
})

test('GET /play cache miss → extraction → byte stream + X-Direct-URL header', async () => {
  let extractCalls = 0
  let fetchCalls = []
  const fakeUrl = 'https://rr1.googlevideo.com/videoplayback?id=cold'
  const { app, cache } = makeApp({
    extractStream: async (videoId) => {
      extractCalls++
      assert.equal(videoId, 'cold')
      return { url: fakeUrl, extractor: 'ytdlp' }
    },
    fetchUpstream: async (url, opts) => {
      fetchCalls.push({ url, headers: opts.headers })
      return {
        statusCode: 206,
        headers: {
          'content-type': 'audio/mp4',
          'accept-ranges': 'bytes',
          'content-range': 'bytes 0-9/100',
        },
        body: Readable.from([Buffer.from('FIRSTBYTES')]),
      }
    },
  })
  const { server, baseUrl } = await listen(app)
  try {
    const res = await request(`${baseUrl}/play?videoId=cold`, {
      headers: { range: 'bytes=0-9' },
    })
    assert.equal(res.statusCode, 206)
    assert.equal(res.headers['x-direct-url'], fakeUrl)
    assert.equal(res.headers['x-extractor'], 'ytdlp')
    assert.equal(res.headers['content-type'], 'audio/mp4')
    assert.equal(res.headers['accept-ranges'], 'bytes')
    assert.equal(res.headers['content-range'], 'bytes 0-9/100')
    const body = await res.body.text()
    assert.equal(body, 'FIRSTBYTES')
    assert.equal(extractCalls, 1)
    assert.equal(fetchCalls.length, 1)
    assert.equal(fetchCalls[0].url, fakeUrl)
    assert.equal(fetchCalls[0].headers.range, 'bytes=0-9')
    // Cache populated for next call
    assert.equal(cache.getStreamUrl('cold').url, fakeUrl)
  } finally { server.close() }
})

test('GET /play cache hit → no extraction, direct upstream fetch', async () => {
  const fakeUrl = 'https://rr1.googlevideo.com/videoplayback?id=warm'
  const { app, cache } = makeApp({
    extractStream: async () => { throw new Error('extractor must not be called on cache hit') },
    fetchUpstream: fakeUpstreamResponse(),
  })
  cache.setStreamUrl('warm', fakeUrl, 'piped')
  const { server, baseUrl } = await listen(app)
  try {
    const res = await request(`${baseUrl}/play?videoId=warm`)
    assert.equal(res.statusCode, 206)
    assert.equal(res.headers['x-direct-url'], fakeUrl)
    assert.equal(res.headers['x-extractor'], 'piped')
  } finally { server.close() }
})

test('GET /play returns 503 when extractor chain fails', async () => {
  const { app } = makeApp({
    extractStream: async () => { throw new Error('all extractors failed') },
    fetchUpstream: async () => { throw new Error('should not be called') },
  })
  const { server, baseUrl } = await listen(app)
  try {
    const res = await request(`${baseUrl}/play?videoId=brokenVid`)
    assert.equal(res.statusCode, 503)
    const body = await res.body.json()
    assert.equal(body.error, 'extraction_failed')
  } finally { server.close() }
})

test('GET /play invalidates cache on upstream 403 (expired URL)', async () => {
  const expiredUrl = 'https://rr1.googlevideo.com/videoplayback?id=expired'
  const { app, cache } = makeApp({
    extractStream: async () => { throw new Error('should not be called') },
    fetchUpstream: fakeUpstreamResponse({ statusCode: 403, body: 'forbidden' }),
  })
  cache.setStreamUrl('expired', expiredUrl, 'ytdlp')
  const { server, baseUrl } = await listen(app)
  try {
    const res = await request(`${baseUrl}/play?videoId=expired`)
    assert.equal(res.statusCode, 503)
    // The cache entry should have been invalidated so the NEXT call re-extracts
    assert.equal(cache.getStreamUrl('expired'), null)
  } finally { server.close() }
})

test('GET /play forwards Range header to upstream', async () => {
  let capturedRange = null
  const { app, cache } = makeApp({
    extractStream: async () => ({ url: 'https://cdn/x', extractor: 'ytdlp' }),
    fetchUpstream: async (_url, opts) => {
      capturedRange = opts.headers.range
      return {
        statusCode: 206,
        headers: { 'content-type': 'audio/mp4', 'accept-ranges': 'bytes' },
        body: Readable.from([Buffer.from('chunk')]),
      }
    },
  })
  cache.setStreamUrl('rangeVid', 'https://cdn/x', 'ytdlp')
  const { server, baseUrl } = await listen(app)
  try {
    await request(`${baseUrl}/play?videoId=rangeVid`, {
      headers: { range: 'bytes=512000-1024000' },
    })
    assert.equal(capturedRange, 'bytes=512000-1024000')
  } finally { server.close() }
})

test('GET /play uses Audius URL when title+artist provided and Audius hit', async () => {
  const audiusUrl = 'https://cdn.audius.co/sicko.m4a'
  let audiusCalls = 0
  let fetchCalls = []
  const { app } = makeApp({
    findAudiusStreamUrl: async ({ title, artist }) => {
      audiusCalls++
      assert.equal(title, 'Sicko Mode')
      assert.equal(artist, 'Travis Scott')
      return { url: audiusUrl, audiusTrackId: 'aud_sm', title: 'Sicko Mode' }
    },
    extractStream: async () => { throw new Error('should not call YouTube extractor') },
    fetchUpstream: async (url, opts) => {
      fetchCalls.push({ url })
      return {
        statusCode: 206,
        headers: { 'content-type': 'audio/mp4', 'accept-ranges': 'bytes', 'content-range': 'bytes 0-9/999999' },
        body: Readable.from([Buffer.from('AUDIUSBYTES')]),
      }
    },
  })
  const { server, baseUrl } = await listen(app)
  try {
    const res = await request(`${baseUrl}/play?videoId=yt_sm&itunesTrackId=55555&title=Sicko+Mode&artist=Travis+Scott`, {
      headers: { range: 'bytes=0-9' },
    })
    assert.equal(res.statusCode, 206)
    assert.equal(res.headers['x-direct-url'], audiusUrl)
    assert.equal(res.headers['x-source'], 'audius')
    const body = await res.body.text()
    assert.equal(body, 'AUDIUSBYTES')
    assert.equal(audiusCalls, 1)
    assert.equal(fetchCalls[0].url, audiusUrl)
  } finally { server.close() }
})

test('GET /play returns 400 when videoId and itunesTrackId both absent', async () => {
  const { app } = makeApp({
    extractStream: async () => { throw new Error('should not call') },
    fetchUpstream: async () => { throw new Error('should not call') },
  })
  const { server, baseUrl } = await listen(app)
  try {
    const res = await request(`${baseUrl}/play?title=Foo&artist=Bar`)
    assert.equal(res.statusCode, 400)
  } finally { server.close() }
})
