import { test } from 'node:test'
import assert from 'node:assert/strict'
import { Readable } from 'node:stream'
import { searchTrack, resolveStreamUrl, findStreamUrl, _resetHostCache } from '../../src/services/audius-client.js'

function makeJsonBody(obj) {
  const readable = Readable.from([Buffer.from(JSON.stringify(obj))])
  // Mimic undici body: .json() decodes, .dump() drains silently.
  readable.json = async () => obj
  readable.dump = async () => {}
  return readable
}

function makeEmptyBody() {
  const readable = Readable.from([])
  readable.json = async () => null
  readable.dump = async () => {}
  return readable
}

function makeFetch(responses) {
  let i = 0
  return async (_url, _opts) => {
    if (i >= responses.length) throw new Error(`unexpected fetch call #${i + 1}`)
    const r = responses[i++]
    if (r instanceof Error) throw r
    const body = r.body != null ? makeJsonBody(r.body) : makeEmptyBody()
    return { statusCode: r.status ?? 200, headers: r.headers ?? {}, body }
  }
}

// Reset cached host before each test so host discovery runs fresh.
function withFreshHostCache(fn) {
  return async () => {
    _resetHostCache()
    await fn()
  }
}

test('searchTrack returns null when title and artist are both missing', withFreshHostCache(async () => {
  const result = await searchTrack({}, { fetchFn: async () => { throw new Error('should not call') } })
  assert.equal(result, null)
}))

test('searchTrack returns null when host discovery fails', withFreshHostCache(async () => {
  const result = await searchTrack({ title: 'Rodeo', artist: 'Travis Scott' }, {
    fetchFn: async () => { throw new Error('network error') },
  })
  assert.equal(result, null)
}))

test('searchTrack returns first result on title+artist query', withFreshHostCache(async () => {
  const fakeTrack = { id: 'abc123', title: 'Rodeo', isrc: null }
  const fetch = makeFetch([
    { body: { data: ['https://discovery.audius.co'] } },  // host discovery
    { body: { data: [fakeTrack] } },                       // search
  ])
  const result = await searchTrack({ title: 'Rodeo', artist: 'Travis Scott' }, { fetchFn: fetch })
  assert.deepEqual(result, fakeTrack)
}))

test('searchTrack prefers ISRC-matched result over first result', withFreshHostCache(async () => {
  const wrong = { id: 'wrong', title: 'Rodeo (remix)', isrc: 'USUG11500960' }
  const right = { id: 'right', title: 'Rodeo', isrc: 'USUG11500956' }
  const fetch = makeFetch([
    { body: { data: ['https://discovery.audius.co'] } },
    { body: { data: [wrong, right] } },
  ])
  const result = await searchTrack({ title: 'Rodeo', artist: 'Travis Scott', isrc: 'USUG11500956' }, { fetchFn: fetch })
  assert.equal(result?.id, 'right')
}))

test('searchTrack falls back to first result when no ISRC match', withFreshHostCache(async () => {
  const first = { id: 'first', title: 'Rodeo', isrc: null }
  const second = { id: 'second', title: 'Rodeo (live)', isrc: null }
  const fetch = makeFetch([
    { body: { data: ['https://discovery.audius.co'] } },
    { body: { data: [first, second] } },
  ])
  const result = await searchTrack({ title: 'Rodeo', artist: 'Travis Scott', isrc: 'XXXXXX' }, { fetchFn: fetch })
  assert.equal(result?.id, 'first')
}))

test('resolveStreamUrl follows 302 redirect and returns final CDN URL', withFreshHostCache(async () => {
  const cdnUrl = 'https://cdn.audius.co/tracks/abc123.m4a'
  let calls = 0
  const emptyBody = () => ({ dump: async () => {}, json: async () => null })
  const fetchFn = async (url) => {
    calls++
    if (calls === 1) {
      // host discovery
      return { statusCode: 200, headers: {}, body: makeJsonBody({ data: ['https://discovery.audius.co'] }) }
    }
    if (calls === 2) {
      // /stream returns 302 → cdnUrl
      return { statusCode: 302, headers: { location: cdnUrl }, body: emptyBody() }
    }
    if (calls === 3) {
      // CDN returns 200 directly
      return { statusCode: 200, headers: {}, body: emptyBody() }
    }
    throw new Error(`unexpected call #${calls}`)
  }
  const result = await resolveStreamUrl('abc123', { fetchFn })
  assert.equal(result, cdnUrl)
}))

test('resolveStreamUrl returns null on non-redirect non-200 status', withFreshHostCache(async () => {
  let calls = 0
  const fetchFn = async () => {
    calls++
    if (calls === 1) return { statusCode: 200, headers: {}, body: makeJsonBody({ data: ['https://discovery.audius.co'] }) }
    return { statusCode: 404, headers: {}, body: { dump: async () => {}, json: async () => null } }
  }
  const result = await resolveStreamUrl('notfound', { fetchFn })
  assert.equal(result, null)
}))

test('findStreamUrl returns null when searchTrack returns nothing', withFreshHostCache(async () => {
  let calls = 0
  const fetchFn = async () => {
    calls++
    if (calls === 1) return { statusCode: 200, headers: {}, body: makeJsonBody({ data: ['https://discovery.audius.co'] }) }
    return { statusCode: 200, headers: {}, body: makeJsonBody({ data: [] }) }
  }
  const result = await findStreamUrl({ title: 'Ghost', artist: 'NoAudiusArtist' }, { fetchFn })
  assert.equal(result, null)
}))
