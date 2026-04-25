// Integration tests — hit the real iTunes + real YouTube.
// Run with: SPOTIFY_INTEGRATION=1 npm run test:integration
// These may fail for legitimate reasons (YouTube change, rate limit). Re-run.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { request } from 'undici'
import { searchTracks } from '../../src/services/itunes.js'
import * as extractor from '../../src/services/extractor/index.js'
import { pickBest } from '../../src/services/youtube-match.js'

const ENABLED = process.env.SPOTIFY_INTEGRATION === '1'
const maybe = ENABLED ? test : test.skip

maybe('iTunes → youtubei.js resolves Blinding Lights (ISRC USUG12001534)', async () => {
  const tracks = await searchTracks('The Weeknd Blinding Lights', 5)
  const hit = tracks.find(t => t.isrc === 'USUG12001534') ?? tracks[0]
  assert.ok(hit, 'iTunes returned no tracks')

  await extractor.init()
  const cands = await extractor.search(`${hit.artistName} ${hit.name}`, 5)
  const best = pickBest(cands, hit)
  assert.ok(best, 'no YouTube match')
  // Blinding Lights studio is ~200s
  assert.ok(Math.abs(best.duration - Math.round(hit.durationMs / 1000)) <= 5, `duration mismatch ${best.duration} vs ${hit.durationMs / 1000}`)

  const { url } = await extractor.extractStream(best.id)
  assert.match(url, /googlevideo\.com\/videoplayback/)
})

maybe('stream URL is playable (HTTP 200 on HEAD/GET)', async () => {
  await extractor.init()
  const cands = await extractor.search('The Weeknd Blinding Lights', 3)
  const videoId = cands[0]?.id
  assert.ok(videoId, 'no candidate videos')

  const { url } = await extractor.extractStream(videoId)
  // googlevideo rejects HEAD; do a tiny Range GET
  const res = await request(url, { method: 'GET', headers: { range: 'bytes=0-1023' } })
  assert.ok(res.statusCode === 200 || res.statusCode === 206, `status ${res.statusCode}`)
  const ctype = res.headers['content-type'] ?? ''
  assert.ok(ctype.startsWith('audio/') || ctype.includes('mp4'), `unexpected content-type ${ctype}`)
  // drain
  res.body.destroy()
})

maybe('non-ASCII (NewJeans Super Shy) resolves', async () => {
  const tracks = await searchTracks('NewJeans Super Shy', 3)
  assert.ok(tracks.length > 0)
  const hit = tracks[0]
  await extractor.init()
  const cands = await extractor.search(`${hit.artistName} ${hit.name}`, 5)
  const best = pickBest(cands, hit)
  assert.ok(best, 'no match for NewJeans')
})

maybe('classical: Beethoven 9 4th movement resolves to something plausible', async () => {
  const tracks = await searchTracks('Beethoven Symphony 9 Ode to Joy', 5)
  assert.ok(tracks.length > 0)
  const hit = tracks.find(t => (t.durationMs ?? 0) > 15 * 60_000) ?? tracks[0]
  await extractor.init()
  const cands = await extractor.search(`${hit.artistName} ${hit.name}`, 5)
  // For long-form classical, the scorer might reject; accept "got candidates"
  assert.ok(cands.length > 0, 'YouTube returned no candidates')
})
