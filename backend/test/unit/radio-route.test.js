import { test, describe } from 'node:test'
import assert from 'node:assert/strict'
import { request } from 'undici'
import express from 'express'
import { createRadioRouter, _resetPool } from '../../src/routes/radio.js'

function makeItunesTrack(overrides = {}) {
  return {
    itunesTrackId: 123456,
    name: 'Antidote',
    artistName: 'Travis Scott',
    albumName: 'Rodeo',
    artistId: 111,
    durationMs: 210000,
    artworkUrl: 'https://cdn.example.com/art.jpg',
    isrc: 'USXXX1234567',
    previewUrl: null,
    ...overrides,
  }
}

async function listen(app) {
  return new Promise(resolve => {
    const server = app.listen(0, '127.0.0.1', () => {
      resolve({ server, baseUrl: `http://127.0.0.1:${server.address().port}` })
    })
  })
}

async function makeServer({ similarArtists = [], tracksByArtist = {} } = {}) {
  const router = createRadioRouter({
    getSimilarArtists: async () => similarArtists,
    searchTracks: async (q) => {
      const name = q.trim()
      return tracksByArtist[name] ?? [makeItunesTrack({ artistName: name })]
    },
  })
  const app = express()
  app.use(router)
  return listen(app)
}

describe('GET /radio', { concurrency: false }, () => {
  test('returns empty array for missing artist', async () => {
    _resetPool()
    const { server, baseUrl } = await makeServer()
    try {
      const res = await request(`${baseUrl}/radio?artist=`)
      const body = await res.body.json()
      assert.equal(res.statusCode, 200)
      assert.deepEqual(body, { tracks: [] })
    } finally { server.close() }
  })

  test('returns tracks for seed artist', async () => {
    _resetPool()
    const { server, baseUrl } = await makeServer()
    try {
      const res = await request(`${baseUrl}/radio?artist=Travis+Scott&limit=5`)
      const body = await res.body.json()
      assert.equal(res.statusCode, 200)
      assert.ok(body.tracks.length > 0)
      assert.equal(body.tracks[0].source, 'itunes')
    } finally { server.close() }
  })

  test('includes tracks from similar artists', async () => {
    // Use a unique artist name to avoid pool collision with other tests.
    const { server, baseUrl } = await makeServer({
      similarArtists: [{ name: 'Playboi Carti', match: 0.9 }],
      tracksByArtist: {
        'Kendrick Lamar': [makeItunesTrack({ name: 'Alright', itunesTrackId: 11, artistName: 'Kendrick Lamar' })],
        'Playboi Carti': [makeItunesTrack({ name: 'Magnolia', itunesTrackId: 22, artistName: 'Playboi Carti' })],
      },
    })
    try {
      const res = await request(`${baseUrl}/radio?artist=Kendrick+Lamar&limit=25`)
      const body = await res.body.json()
      const names = body.tracks.map(t => t.artistName)
      assert.ok(names.includes('Kendrick Lamar'), 'seed artist tracks present')
      assert.ok(names.includes('Playboi Carti'), 'similar artist tracks present')
    } finally { server.close() }
  })

  test('deduplicates tracks by itunesTrackId', async () => {
    _resetPool()
    const dupe = makeItunesTrack({ itunesTrackId: 999 })
    const { server, baseUrl } = await makeServer({
      tracksByArtist: { 'Travis Scott': [dupe, dupe] },
    })
    try {
      const res = await request(`${baseUrl}/radio?artist=Travis+Scott`)
      const body = await res.body.json()
      const ids = body.tracks.map(t => t.itunesTrackId)
      const unique = new Set(ids)
      assert.equal(ids.length, unique.size, 'no duplicates')
    } finally { server.close() }
  })

  test('respects limit parameter', async () => {
    _resetPool()
    const many = Array.from({ length: 30 }, (_, i) => makeItunesTrack({ itunesTrackId: i + 1, name: `Track ${i}` }))
    const { server, baseUrl } = await makeServer({ tracksByArtist: { 'Travis Scott': many } })
    try {
      const res = await request(`${baseUrl}/radio?artist=Travis+Scott&limit=5`)
      const body = await res.body.json()
      assert.ok(body.tracks.length <= 5)
    } finally { server.close() }
  })
})
