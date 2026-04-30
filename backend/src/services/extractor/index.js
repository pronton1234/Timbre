// Extractor chain: yt-dlp → Piped → Cobalt → youtubei.js.
// yt-dlp is primary because it is the only client that reliably returns a
// playable stream URL from a datacenter IP (requires cookies + bgutil PO-token
// sidecar + deno JS runtime). The others stay as pure-HTTP fallbacks.
// Each extractor has a circuit breaker. If one throws 3× in a row, it's skipped
// for 60s and the chain moves to the next. Callers only see a single interface.

import * as ytdlp from './ytdlp.js'
import * as youtubei from './youtubei.js'
import * as piped from './piped.js'
import * as cobalt from './cobalt.js'

const FAIL_THRESHOLD = 3
const OPEN_MS = 60_000

function makeBreaker(name) {
  let consecutiveFailures = 0
  let openedAt = 0
  return {
    name,
    isOpen() {
      if (openedAt === 0) return false
      if (Date.now() - openedAt < OPEN_MS) return true
      // half-open: let one probe through
      openedAt = 0
      consecutiveFailures = 0
      return false
    },
    recordSuccess() { consecutiveFailures = 0; openedAt = 0 },
    recordFailure() {
      consecutiveFailures++
      if (consecutiveFailures >= FAIL_THRESHOLD) openedAt = Date.now()
    },
    status() {
      return { name, open: this.isOpen(), consecutiveFailures, openedAt }
    },
  }
}

// Order matters: extractStream walks this list top-down. youtubei is FIRST
// because the persistent HTTP/2 pool + parallel client racing in youtube-pool.js
// gives it ~300–600ms warm latency — an order of magnitude faster than the
// subprocess-based extractors. ytdlp/piped/cobalt are reliable fallbacks if
// the IOS Innertube clients get blocked from a particular IP.
//
// Per-extractor timeouts reflect their speed envelope: blow past it → kick
// to the next. Total chain budget on cold-cold is ~3s before all options
// have been tried.
const registry = [
  { name: 'youtubei', impl: youtubei, breaker: makeBreaker('youtubei'), timeoutMs: 2_500 },
  { name: 'ytdlp',    impl: ytdlp,    breaker: makeBreaker('ytdlp'),    timeoutMs: 12_000 },
  { name: 'piped',    impl: piped,    breaker: makeBreaker('piped'),    timeoutMs: 5_000 },
  { name: 'cobalt',   impl: cobalt,   breaker: makeBreaker('cobalt'),   timeoutMs: 5_000 },
]

function withTimeout(promise, ms) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error(`timeout after ${ms}ms`)), ms)
    promise.then(v => { clearTimeout(t); resolve(v) }, e => { clearTimeout(t); reject(e) })
  })
}

export async function init() {
  // Pre-warm the primary (yt-dlp: downloads EJS scripts, caches sigfuncs) and
  // the youtubei Innertube session used for search. Both best-effort; any
  // failure surfaces on the first real call.
  try { await ytdlp.init?.() } catch (_) { /* swallow */ }
  try { await youtubei.init?.() } catch (_) { /* swallow */ }
}

export async function search(query, n = 5) {
  // Search only uses the primary. If it fails, surface to caller — secondary
  // extractors don't all expose search reliably.
  return youtubei.search(query, n)
}

export async function extractStream(videoId) {
  let lastErr
  const t0 = Date.now()
  for (const ex of registry) {
    if (ex.breaker.isOpen()) {
      console.error(`[extractor:${ex.name}] skipped (circuit open) videoId=${videoId}`)
      continue
    }
    const tEx = Date.now()
    try {
      const url = await withTimeout(ex.impl.getStreamUrl(videoId), ex.timeoutMs)
      ex.breaker.recordSuccess()
      console.log(`[extractor:${ex.name}] OK videoId=${videoId} ${Date.now() - tEx}ms (chain ${Date.now() - t0}ms)`)
      return { url, extractor: ex.name }
    } catch (e) {
      ex.breaker.recordFailure()
      console.error(`[extractor:${ex.name}] failed videoId=${videoId} after ${Date.now() - tEx}ms: ${e.message}`)
      lastErr = e
    }
  }
  throw lastErr ?? new Error('all extractors failed')
}

/// Race-extract: fire youtubei AND a slower-but-reliable fallback in parallel.
/// First valid response wins; the other is abandoned. Used when latency matters
/// more than minimizing upstream load (i.e. the live /stream-url path).
///
/// Why this is safer than just using extractStream sequentially: if youtubei is
/// going to fail (e.g. PoToken regression on Oracle datacenter IPs), we don't
/// pay the 2.5s timeout before falling to ytdlp — they raced from the start.
export async function extractStreamRaced(videoId) {
  const t0 = Date.now()
  const candidates = []
  for (const ex of registry) {
    if (ex.breaker.isOpen()) continue
    candidates.push(ex)
    // Race only first two by default — youtubei (fast) + ytdlp (reliable).
    // piped/cobalt remain available as last-resort fallbacks via extractStream.
    if (candidates.length >= 2) break
  }
  if (candidates.length === 0) return extractStream(videoId)

  return new Promise((resolve, reject) => {
    let resolved = false
    let pending = candidates.length
    let lastErr

    for (const ex of candidates) {
      const tEx = Date.now()
      withTimeout(ex.impl.getStreamUrl(videoId), ex.timeoutMs)
        .then(url => {
          ex.breaker.recordSuccess()
          if (resolved) return
          resolved = true
          console.log(`[extractor:race ${ex.name}] WON videoId=${videoId} ${Date.now() - tEx}ms (race ${Date.now() - t0}ms)`)
          resolve({ url, extractor: ex.name })
        })
        .catch(err => {
          ex.breaker.recordFailure()
          lastErr = err
          pending--
          console.error(`[extractor:race ${ex.name}] failed ${Date.now() - tEx}ms: ${err.message}`)
          if (resolved) return
          if (pending === 0) {
            // Both raced extractors failed — fall back to remaining chain.
            extractStream(videoId).then(resolve).catch(() => reject(lastErr))
          }
        })
    }
  })
}

export function health() {
  return registry.map(r => r.breaker.status())
}

// Exposed for tests to reset state between cases
export const _internal = { registry, makeBreaker, withTimeout, FAIL_THRESHOLD, OPEN_MS }
