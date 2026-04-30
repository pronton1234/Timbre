import { test, describe, after } from 'node:test'
import assert from 'node:assert/strict'
import { request } from 'undici'
import express from 'express'
import { createSearchRouter } from '../../src/routes/search.js'

function makeItunesTrack(overrides = {}) {
  return {
    itunesTrackId: 123456,
    name: 'Rodeo',
    artistName: 'Travis Scott',
    albumName: 'Rodeo',
    artistId: 111,
    durationMs: 234000,
    artworkUrl: 'https://cdn.example.com/art.jpg',
    isrc: 'USXXX1234567',
    previewUrl: null,
    ...overrides,
  }
}

function makeYtmVideo(overrides = {}) {
  return { id: 'abc123def456', title: 'Cancun (Leak)', duration: 210, channel: 'Playboi Carti - Topic', ...overrides }
}

async function listen(app) {
  return new Promise(resolve => {
    const server = app.listen(0, '127.0.0.1', () => {
      resolve({ server, baseUrl: `http://127.0.0.1:${server.address().port}` })
    })
  })
}

async function makeServer({ itunesTracks = [], itunesAlbums = [], itunesArtists = [], ytmVideos = [] } = {}) {
  const router = createSearchRouter({
    searchTracks: async () => itunesTracks,
    searchAlbums: async () => itunesAlbums,
    searchArtists: async () => itunesArtists,
    searchYtm: async () => ytmVideos,
  })
  const app = express()
  app.use(router)
  return listen(app)
}

describe('GET /search', () => {
  test('returns empty arrays for blank query', async () => {
    const { server, baseUrl } = await makeServer()
    try {
      const res = await request(`${baseUrl}/search?q=`)
      const body = await res.body.json()
      assert.equal(res.statusCode, 200)
      assert.deepEqual(body, { tracks: [], albums: [], artists: [] })
    } finally { server.close() }
  })

  test('returns iTunes tracks with source=itunes', async () => {
    const { server, baseUrl } = await makeServer({ itunesTracks: [makeItunesTrack()] })
    try {
      const res = await request(`${baseUrl}/search?q=rodeo`)
      const body = await res.body.json()
      assert.equal(body.tracks.length, 1)
      assert.equal(body.tracks[0].source, 'itunes')
      assert.equal(body.tracks[0].itunesTrackId, 123456)
    } finally { server.close() }
  })

  test('appends non-overlapping YTM tracks with source=yt and videoId set', async () => {
    const { server, baseUrl } = await makeServer({
      itunesTracks: [makeItunesTrack({ name: 'Rodeo', artistName: 'Travis Scott' })],
      ytmVideos: [makeYtmVideo({ title: 'Cancun (Leak)', channel: 'Playboi Carti - Topic' })],
    })
    try {
      const res = await request(`${baseUrl}/search?q=carti`)
      const body = await res.body.json()
      const tracks = body.tracks
      assert.equal(tracks.length, 2)
      const ytTrack = tracks.find(t => t.source === 'yt')
      assert.ok(ytTrack, 'YTM track should be present')
      assert.equal(ytTrack.videoId, 'abc123def456')
      assert.ok(ytTrack.itunesTrackId < 0, 'YTM pseudo-id should be negative')
    } finally { server.close() }
  })

  test('deduplicates YTM tracks that overlap with iTunes results', async () => {
    const { server, baseUrl } = await makeServer({
      itunesTracks: [makeItunesTrack({ name: 'Rodeo', artistName: 'Travis Scott' })],
      ytmVideos: [makeYtmVideo({ title: 'Rodeo', channel: 'Travis Scott - Topic' })],
    })
    try {
      const res = await request(`${baseUrl}/search?q=rodeo`)
      const body = await res.body.json()
      // Should only have 1 track: YTM "Rodeo" deduped against iTunes "Rodeo"
      assert.equal(body.tracks.length, 1)
      assert.equal(body.tracks[0].source, 'itunes')
    } finally { server.close() }
  })

  test('returns albums and artists from iTunes', async () => {
    const { server, baseUrl } = await makeServer({
      itunesAlbums: [{ itunesCollectionId: 1, name: 'Rodeo', artistName: 'Travis Scott', artworkUrl: null, trackCount: 16, releaseDate: null }],
      itunesArtists: [{ itunesArtistId: 2, name: 'Travis Scott', primaryGenre: 'Hip-Hop/Rap' }],
    })
    try {
      const res = await request(`${baseUrl}/search?q=travis`)
      const body = await res.body.json()
      assert.equal(body.albums.length, 1)
      assert.equal(body.artists.length, 1)
    } finally { server.close() }
  })
})
