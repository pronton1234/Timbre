// Unit tests for the self-hosted Cobalt v11 extractor.
// Spins a disposable HTTP server on 127.0.0.1 to stand in for the Cobalt
// container. The wrapper is pointed at it via COBALT_BASE_URL.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createServer } from 'node:http'

function startFakeCobalt(handler) {
  return new Promise((resolve) => {
    const server = createServer((req, res) => {
      let body = ''
      req.on('data', (c) => { body += c })
      req.on('end', () => handler(req, res, body))
    })
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address()
      resolve({ server, url: `http://127.0.0.1:${port}` })
    })
  })
}

async function loadMod(baseUrl) {
  process.env.COBALT_BASE_URL = baseUrl
  return import(`../../src/services/extractor/cobalt.js?cachebust=${Math.random()}`)
}

test('getStreamUrl returns tunnel URL on status=tunnel', async () => {
  const tunnel = 'http://127.0.0.1:9000/tunnel?id=abc123'
  const { server, url } = await startFakeCobalt((req, res, body) => {
    const json = JSON.parse(body)
    assert.equal(req.method, 'POST')
    assert.equal(req.headers['content-type'], 'application/json')
    assert.equal(json.url, 'https://youtu.be/dQw4w9WgXcQ')
    assert.equal(json.downloadMode, 'audio')
    assert.equal(json.audioFormat, 'best')
    res.writeHead(200, { 'content-type': 'application/json' })
    res.end(JSON.stringify({ status: 'tunnel', url: tunnel }))
  })
  try {
    const mod = await loadMod(url)
    const out = await mod.getStreamUrl('dQw4w9WgXcQ')
    assert.equal(out, tunnel)
  } finally {
    server.close()
  }
})

test('getStreamUrl accepts status=redirect as a valid success', async () => {
  const direct = 'https://rr4.googlevideo.com/videoplayback?x=1'
  const { server, url } = await startFakeCobalt((_req, res) => {
    res.writeHead(200, { 'content-type': 'application/json' })
    res.end(JSON.stringify({ status: 'redirect', url: direct }))
  })
  try {
    const mod = await loadMod(url)
    const out = await mod.getStreamUrl('abc')
    assert.equal(out, direct)
  } finally {
    server.close()
  }
})

test('getStreamUrl throws on status=error with code', async () => {
  const { server, url } = await startFakeCobalt((_req, res) => {
    res.writeHead(200, { 'content-type': 'application/json' })
    res.end(JSON.stringify({ status: 'error', error: { code: 'youtube.no_matching_format' } }))
  })
  try {
    const mod = await loadMod(url)
    await assert.rejects(mod.getStreamUrl('abc'), /youtube\.no_matching_format/)
  } finally {
    server.close()
  }
})

test('getStreamUrl throws on unexpected status', async () => {
  const { server, url } = await startFakeCobalt((_req, res) => {
    res.writeHead(200, { 'content-type': 'application/json' })
    res.end(JSON.stringify({ status: 'picker', items: [] }))
  })
  try {
    const mod = await loadMod(url)
    await assert.rejects(mod.getStreamUrl('abc'), /unexpected status: picker/)
  } finally {
    server.close()
  }
})

test('getStreamUrl throws when HTTP status is 5xx', async () => {
  const { server, url } = await startFakeCobalt((_req, res) => {
    res.writeHead(502)
    res.end('Bad Gateway')
  })
  try {
    const mod = await loadMod(url)
    await assert.rejects(mod.getStreamUrl('abc'), /cobalt http 502/)
  } finally {
    server.close()
  }
})

test('getStreamUrl throws when tunnel response is missing url', async () => {
  const { server, url } = await startFakeCobalt((_req, res) => {
    res.writeHead(200, { 'content-type': 'application/json' })
    res.end(JSON.stringify({ status: 'tunnel' }))
  })
  try {
    const mod = await loadMod(url)
    await assert.rejects(mod.getStreamUrl('abc'), /no url in response/)
  } finally {
    server.close()
  }
})
