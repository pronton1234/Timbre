// Tests for youtube-pool: racing logic, first-win semantics, all-fail error propagation.
// We never call real YouTube APIs — each test injects mock Innertube-like clients directly.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { ClientType } from 'youtubei.js'
import { extract, _internal } from '../../src/services/youtube-pool.js'

function makeClient({ url, delayMs = 0, fail = false }) {
  return {
    getInfo: async (_videoId) => {
      if (delayMs) await new Promise(r => setTimeout(r, delayMs))
      if (fail) throw new Error('client failed')
      return {
        chooseFormat: () => ({
          decipher: () => url,
        }),
      }
    },
    session: { player: null },
  }
}

function withClients(clientMap, fn) {
  return async () => {
    _internal.reset()
    for (const [type, client] of Object.entries(clientMap)) {
      _internal.pool.set(ClientType[type], client)
    }
    try { await fn() }
    finally { _internal.reset() }
  }
}

test('extract returns URL from fastest responding client', withClients({
  IOS: makeClient({ url: 'https://googlevideo.com/ios', delayMs: 50 }),
  ANDROID: makeClient({ url: 'https://googlevideo.com/android', delayMs: 100 }),
  TV_EMBEDDED: makeClient({ url: 'https://googlevideo.com/tv', delayMs: 150 }),
}, async () => {
  const result = await extract('vid1', { clients: [ClientType.IOS, ClientType.ANDROID, ClientType.TV_EMBEDDED] })
  assert.equal(result.url, 'https://googlevideo.com/ios')
  assert.equal(result.clientType, ClientType.IOS)
}))

test('extract falls back to slower client when fastest fails', withClients({
  IOS: makeClient({ fail: true }),
  ANDROID: makeClient({ url: 'https://googlevideo.com/android', delayMs: 20 }),
  TV_EMBEDDED: makeClient({ url: 'https://googlevideo.com/tv', delayMs: 100 }),
}, async () => {
  const result = await extract('vid2', { clients: [ClientType.IOS, ClientType.ANDROID, ClientType.TV_EMBEDDED] })
  assert.equal(result.url, 'https://googlevideo.com/android')
}))

test('extract throws when all clients fail', withClients({
  IOS: makeClient({ fail: true }),
  ANDROID: makeClient({ fail: true }),
  TV_EMBEDDED: makeClient({ fail: true }),
}, async () => {
  await assert.rejects(
    () => extract('vid3', { clients: [ClientType.IOS, ClientType.ANDROID, ClientType.TV_EMBEDDED] }),
    /client failed/
  )
}))

test('extract with single client type still works', withClients({
  IOS: makeClient({ url: 'https://googlevideo.com/single' }),
}, async () => {
  const result = await extract('vid4', { clients: [ClientType.IOS] })
  assert.equal(result.url, 'https://googlevideo.com/single')
}))

test('extract resolves quickly even when some clients are slow', withClients({
  IOS: makeClient({ url: 'https://googlevideo.com/fast', delayMs: 10 }),
  ANDROID: makeClient({ url: 'https://googlevideo.com/slow', delayMs: 500 }),
  TV_EMBEDDED: makeClient({ url: 'https://googlevideo.com/slower', delayMs: 1000 }),
}, async () => {
  const start = Date.now()
  const result = await extract('vid5', { clients: [ClientType.IOS, ClientType.ANDROID, ClientType.TV_EMBEDDED] })
  const elapsed = Date.now() - start
  assert.equal(result.url, 'https://googlevideo.com/fast')
  assert.ok(elapsed < 200, `should resolve in <200ms but took ${elapsed}ms`)
}))

test('extract throws when no clients are available in pool', async () => {
  _internal.reset()
  await assert.rejects(
    () => extract('vid6', { clients: [] }),
    /no innertube clients available/
  )
})
