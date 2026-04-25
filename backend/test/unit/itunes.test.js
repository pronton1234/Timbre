import { test } from 'node:test'
import assert from 'node:assert/strict'
import { _internal } from '../../src/services/itunes.js'

test('upscaleArtwork rewrites 100x100 → 600x600', () => {
  assert.equal(
    _internal.upscaleArtwork('https://is1.mzstatic.com/image/thumb/abc/100x100bb.jpg'),
    'https://is1.mzstatic.com/image/thumb/abc/600x600bb.jpg',
  )
  assert.equal(
    _internal.upscaleArtwork('https://is1.mzstatic.com/image/thumb/abc/60x60bb.png'),
    'https://is1.mzstatic.com/image/thumb/abc/600x600bb.png',
  )
})

test('upscaleArtwork handles null/undefined', () => {
  assert.equal(_internal.upscaleArtwork(null), null)
  assert.equal(_internal.upscaleArtwork(undefined), null)
})

test('mapTrack maps all expected fields', () => {
  const raw = {
    trackId: 1, isrc: 'US1234', trackName: 'x', artistName: 'y',
    collectionName: 'z', trackTimeMillis: 200_000,
    artworkUrl100: 'https://x/100x100bb.jpg',
    previewUrl: 'https://preview',
    releaseDate: '2019-01-01',
  }
  const m = _internal.mapTrack(raw)
  assert.equal(m.itunesTrackId, 1)
  assert.equal(m.isrc, 'US1234')
  assert.equal(m.artworkUrl, 'https://x/600x600bb.jpg')
  assert.equal(m.durationMs, 200_000)
})

test('mapAlbum / mapArtist shape', () => {
  const a = _internal.mapAlbum({ collectionId: 5, collectionName: 'Album', artistName: 'x', artworkUrl100: null, trackCount: 12, releaseDate: '2020' })
  assert.equal(a.itunesCollectionId, 5)
  assert.equal(a.trackCount, 12)
  const ar = _internal.mapArtist({ artistId: 9, artistName: 'X', primaryGenreName: 'Pop' })
  assert.equal(ar.itunesArtistId, 9)
  assert.equal(ar.primaryGenre, 'Pop')
})
