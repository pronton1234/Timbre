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

const registry = [
  { name: 'ytdlp', impl: ytdlp, breaker: makeBreaker('ytdlp') },
  { name: 'piped', impl: piped, breaker: makeBreaker('piped') },
  { name: 'cobalt', impl: cobalt, breaker: makeBreaker('cobalt') },
  { name: 'youtubei', impl: youtubei, breaker: makeBreaker('youtubei') },
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
  for (const ex of registry) {
    if (ex.breaker.isOpen()) {
      console.error(`[extractor:${ex.name}] skipped (circuit open) videoId=${videoId}`)
      continue
    }
    try {
      const url = await withTimeout(ex.impl.getStreamUrl(videoId), 15_000)
      ex.breaker.recordSuccess()
      return { url, extractor: ex.name }
    } catch (e) {
      ex.breaker.recordFailure()
      console.error(`[extractor:${ex.name}] failed videoId=${videoId}: ${e.message}`)
      lastErr = e
    }
  }
  throw lastErr ?? new Error('all extractors failed')
}

export function health() {
  return registry.map(r => r.breaker.status())
}

// Exposed for tests to reset state between cases
export const _internal = { registry, makeBreaker, withTimeout, FAIL_THRESHOLD, OPEN_MS }
