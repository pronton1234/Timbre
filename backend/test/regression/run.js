// Regression harness: for each track in corpus.json, resolve iTunes metadata,
// search YouTube via the primary extractor, pick a match, then call
// getStreamUrl on EACH extractor independently (matrix mode). We want to see
// which specific extractors break before the chain's fallback masks it.
//
// Exit code:
//   0  if every extractor's pass rate >= THRESHOLD (default 90%)
//   1  otherwise
//
// Designed for nightly cron. Output is human-readable + ends with a JSON
// summary line prefixed `RESULT:` for log scraping.
import fs from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { request } from 'undici'
import * as itunes from '../../src/services/itunes.js'
import { pickBest } from '../../src/services/youtube-match.js'
import * as youtubei from '../../src/services/extractor/youtubei.js'
import * as piped from '../../src/services/extractor/piped.js'
import * as cobalt from '../../src/services/extractor/cobalt.js'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const CORPUS_PATH = path.join(__dirname, 'corpus.json')
const THRESHOLD = Number(process.env.REGRESSION_THRESHOLD ?? 0.9)
const TIMEOUT_MS = Number(process.env.REGRESSION_TIMEOUT_MS ?? 15_000)
const EXTRACTORS = [
  { name: 'youtubei', impl: youtubei },
  { name: 'piped', impl: piped },
  { name: 'cobalt', impl: cobalt },
]

function withTimeout(promise, ms, label) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error(`${label} timeout after ${ms}ms`)), ms)
    promise.then(
      v => { clearTimeout(t); resolve(v) },
      e => { clearTimeout(t); reject(e) },
    )
  })
}

// Look up iTunes metadata for a fixture entry.
// Prefer ISRC lookup when the fixture provides one (deterministic, no drift).
async function resolveItunes(entry) {
  if (entry.isrc) {
    const res = await itunes.searchTracks(`${entry.artist} ${entry.title}`, 25)
    const hit = res.find(t => t.isrc && t.isrc.toUpperCase() === entry.isrc.toUpperCase())
    if (hit) return hit
  }
  const res = await itunes.searchTracks(`${entry.artist} ${entry.title}`, 5)
  return res[0] ?? null
}

// HEAD the stream URL to confirm YouTube's CDN actually serves it.
// googlevideo sometimes rejects HEAD; fall back to a zero-byte range GET.
async function isPlayable(url) {
  try {
    const head = await withTimeout(request(url, { method: 'HEAD' }), 8_000, 'HEAD')
    if (head.statusCode >= 200 && head.statusCode < 400) return true
  } catch (_) { /* fall through */ }
  try {
    const r = await withTimeout(request(url, { method: 'GET', headers: { range: 'bytes=0-0' } }), 8_000, 'GET')
    // Consume & discard
    for await (const _ of r.body) { break }
    return r.statusCode >= 200 && r.statusCode < 400
  } catch (_) {
    return false
  }
}

async function runOne(entry) {
  const row = {
    fixture: `${entry.artist} — ${entry.title}`,
    itunes: false,
    videoId: null,
    matchScore: null,
    extractors: Object.fromEntries(EXTRACTORS.map(e => [e.name, { ok: false, error: null, playable: false }])),
  }

  let track
  try {
    track = await withTimeout(resolveItunes(entry), TIMEOUT_MS, 'itunes')
  } catch (e) {
    row.itunesError = String(e.message ?? e)
    return row
  }
  if (!track) {
    row.itunesError = 'no itunes hit'
    return row
  }
  row.itunes = true

  let candidates
  try {
    candidates = await withTimeout(youtubei.search(`${track.artistName} ${track.name}`, 8), TIMEOUT_MS, 'yt-search')
  } catch (e) {
    row.searchError = String(e.message ?? e)
    return row
  }
  const picked = pickBest(candidates, track)
  if (!picked) { row.searchError = 'no candidate passed match threshold'; return row }
  row.videoId = picked.id
  row.matchScore = picked.matchScore

  // Run every extractor INDEPENDENTLY on the same videoId
  for (const ex of EXTRACTORS) {
    const r = row.extractors[ex.name]
    try {
      const url = await withTimeout(ex.impl.getStreamUrl(picked.id), TIMEOUT_MS, `${ex.name}-extract`)
      r.ok = Boolean(url)
      if (url) r.playable = await isPlayable(url)
    } catch (e) {
      r.error = String(e.message ?? e).slice(0, 200)
    }
  }
  return row
}

async function main() {
  const raw = await fs.readFile(CORPUS_PATH, 'utf8')
  const corpus = JSON.parse(raw)
  const started = Date.now()
  console.log(`regression: ${corpus.length} fixtures; threshold ${(THRESHOLD * 100).toFixed(0)}%`)
  console.log(`extractors: ${EXTRACTORS.map(e => e.name).join(', ')}`)
  console.log('-'.repeat(80))

  await youtubei.init?.().catch(() => {})

  const rows = []
  for (let i = 0; i < corpus.length; i++) {
    const entry = corpus[i]
    const row = await runOne(entry)
    rows.push(row)
    const flags = EXTRACTORS.map(e => {
      const r = row.extractors[e.name]
      return r.playable ? 'P' : r.ok ? 'U' : '.'
    }).join('')
    console.log(`[${String(i + 1).padStart(2)}/${corpus.length}] ${flags}  ${row.fixture}${row.videoId ? `  (${row.videoId})` : ''}`)
    if (row.itunesError) console.log(`        itunes: ${row.itunesError}`)
    if (row.searchError) console.log(`        search: ${row.searchError}`)
    for (const ex of EXTRACTORS) {
      const r = row.extractors[ex.name]
      if (r.error) console.log(`        ${ex.name}: ${r.error}`)
    }
  }

  console.log('-'.repeat(80))
  const summary = { total: rows.length, extractors: {} }
  let failed = false
  for (const ex of EXTRACTORS) {
    const playable = rows.filter(r => r.extractors[ex.name].playable).length
    const extracted = rows.filter(r => r.extractors[ex.name].ok).length
    const rate = playable / rows.length
    summary.extractors[ex.name] = { extracted, playable, total: rows.length, rate }
    const status = rate >= THRESHOLD ? 'OK' : 'FAIL'
    if (rate < THRESHOLD) failed = true
    console.log(`${status}  ${ex.name.padEnd(10)} playable=${playable}/${rows.length}  extracted=${extracted}/${rows.length}  rate=${(rate * 100).toFixed(1)}%`)
  }
  summary.durationMs = Date.now() - started
  summary.passed = !failed
  console.log('-'.repeat(80))
  console.log(`RESULT: ${JSON.stringify(summary)}`)

  process.exit(failed ? 1 : 0)
}

main().catch(e => {
  console.error('regression harness crashed:', e)
  process.exit(2)
})
