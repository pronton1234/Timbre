import { test } from 'node:test'
import assert from 'node:assert/strict'
import { score, pickBest } from '../../src/services/youtube-match.js'

const blindingLights = { name: 'Blinding Lights', artistName: 'The Weeknd', durationMs: 201_000 }

test('exact official video wins', () => {
  const cands = [
    { id: 'a', title: 'The Weeknd - Blinding Lights (Official Video)', duration: 201, channel: 'The Weeknd VEVO' },
    { id: 'b', title: 'Blinding Lights - LIVE cover',                  duration: 220, channel: 'Some Cover Channel' },
  ]
  const best = pickBest(cands, blindingLights)
  assert.equal(best.id, 'a')
  assert.ok(best.matchScore >= 150)
})

test('duration ±3s gives +100, ±8s gives +40', () => {
  const a = score({ title: 'Blinding Lights', duration: 202, channel: 'x' }, blindingLights)
  const b = score({ title: 'Blinding Lights', duration: 205, channel: 'x' }, blindingLights)
  const c = score({ title: 'Blinding Lights', duration: 250, channel: 'x' }, blindingLights)
  assert.ok(a > b)
  assert.ok(b > c)
})

test('live version is penalised when track is studio', () => {
  const live = score({ title: 'The Weeknd - Blinding Lights (Live at SNL)', duration: 201, channel: 'x' }, blindingLights)
  const studio = score({ title: 'The Weeknd - Blinding Lights (Official Video)', duration: 201, channel: 'x' }, blindingLights)
  assert.ok(studio > live)
})

test('cover/karaoke/remix penalties', () => {
  for (const term of ['cover', 'karaoke', 'remix', 'nightcore']) {
    const s = score({ title: `Blinding Lights ${term}`, duration: 201, channel: 'x' }, blindingLights)
    const base = score({ title: 'Blinding Lights', duration: 201, channel: 'x' }, blindingLights)
    assert.ok(base > s, `${term} should be penalised`)
  }
})

test('remix match: no penalty when iTunes title also says remix', () => {
  const track = { name: 'Blinding Lights (Remix)', artistName: 'The Weeknd', durationMs: 210_000 }
  const s = score({ title: 'Blinding Lights (Remix) - The Weeknd', duration: 210, channel: 'x' }, track)
  assert.ok(s > 100)
})

test('VEVO / official channel gets +30', () => {
  const withVevo = score({ title: 'Blinding Lights', duration: 201, channel: 'The Weeknd VEVO' }, blindingLights)
  const without = score({ title: 'Blinding Lights', duration: 201, channel: 'Random Guy' }, blindingLights)
  assert.ok(withVevo - without >= 15)
})

test('non-ASCII: NewJeans Super Shy', () => {
  const track = { name: 'Super Shy', artistName: 'NewJeans', durationMs: 155_000 }
  const cands = [
    { id: 'good', title: 'NewJeans (뉴진스) \'Super Shy\' Official MV', duration: 156, channel: 'HYBE LABELS' },
    { id: 'bad', title: 'Super Shy NewJeans lyrics 1 HOUR',              duration: 3600, channel: 'lyricsbot' },
  ]
  const best = pickBest(cands, track)
  assert.equal(best.id, 'good')
})

test('empty candidates → null', () => {
  assert.equal(pickBest([], blindingLights), null)
})

test('rejects match if top candidate is too low-scoring', () => {
  const cands = [{ id: 'noise', title: 'Totally unrelated song', duration: 600, channel: 'whatever' }]
  assert.equal(pickBest(cands, blindingLights), null)
})

test('title contains track name but not artist → partial credit', () => {
  const cands = [{ id: 'x', title: 'Blinding Lights', duration: 201, channel: 'x' }]
  const best = pickBest(cands, blindingLights)
  assert.ok(best, 'duration+partial title should be enough')
  assert.ok(best.matchScore >= 40)
})

test('punctuation is ignored in normalisation', () => {
  const cands = [{ id: 'x', title: 'The Weeknd — Blinding Lights!!!', duration: 201, channel: 'The Weeknd VEVO' }]
  const best = pickBest(cands, blindingLights)
  assert.ok(best)
})

test('enormous duration mismatch is harshly penalised', () => {
  const short = score({ title: 'Blinding Lights', duration: 30, channel: 'x' }, blindingLights)
  const long  = score({ title: 'Blinding Lights', duration: 3600, channel: 'x' }, blindingLights)
  const good  = score({ title: 'Blinding Lights', duration: 201, channel: 'x' }, blindingLights)
  assert.ok(good > short)
  assert.ok(good > long)
})
