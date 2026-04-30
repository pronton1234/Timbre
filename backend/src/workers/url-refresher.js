// Background worker that keeps cached googlevideo URLs warm.
//
// googlevideo URLs are signed for ~6h. We cache them for 5h, so any URL with
// `expires_at` within the next ~2h is a good candidate for refresh — by the
// time the next user actually taps that song, the URL is already fresh and
// the response comes from cache (one RTT) instead of running the extractor
// chain (2-5s).
//
// Sequencing rationale: we don't fan out parallel refreshes — that would
// hammer YouTube and trip rate-limits / bot detection on the shared Oracle
// IP. Refreshes run sequentially with a small delay between calls. Throughput
// of ~1 URL/sec is plenty given the cache is small (<1000 entries) and the
// refresh cycle is hourly.
//
// Top-N pre-warming: NOT implemented yet because the backend doesn't record
// per-track play counts. Deferred until play-stats infrastructure exists.

const REFRESH_INTERVAL_MS = 60 * 60 * 1000        // every 1h
const REFRESH_THRESHOLD_MS = 2 * 60 * 60 * 1000   // refresh URLs expiring within 2h
const PER_CALL_DELAY_MS = 250                     // sequential pacing
const MAX_PER_CYCLE = 200                         // safety: never refresh more than this in one cycle

export function createUrlRefresher(cache, deps = {}) {
  const extractStream = deps.extractStream
    ?? (async (videoId) => {
      const mod = await import('../services/extractor/index.js')
      return mod.extractStream(videoId)
    })
  const logger = deps.logger ?? console
  const intervalMs = deps.intervalMs ?? REFRESH_INTERVAL_MS
  const thresholdMs = deps.thresholdMs ?? REFRESH_THRESHOLD_MS
  const perCallDelayMs = deps.perCallDelayMs ?? PER_CALL_DELAY_MS
  const maxPerCycle = deps.maxPerCycle ?? MAX_PER_CYCLE

  let timer = null
  let stopped = false
  let lastStats = { refreshed: 0, failed: 0, scanned: 0, lastRunAt: 0 }

  const findCandidates = cache.db.prepare(`
    SELECT video_id, expires_at FROM stream_urls
    WHERE expires_at > ? AND expires_at < ?
    ORDER BY expires_at ASC
    LIMIT ?
  `)

  function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms))
  }

  async function refreshOnce() {
    const now = Date.now()
    const cutoff = now + thresholdMs
    const rows = findCandidates.all(now, cutoff, maxPerCycle)
    let refreshed = 0
    let failed = 0
    for (const row of rows) {
      if (stopped) break
      try {
        const { url, extractor: extractorName } = await extractStream(row.video_id)
        cache.setStreamUrl(row.video_id, url, extractorName)
        refreshed++
      } catch (e) {
        failed++
        logger.error?.(`[url-refresher] failed videoId=${row.video_id}: ${e?.message ?? e}`)
        // On failure, drop the soon-to-expire entry so the next user gets a
        // fresh extraction rather than serving an about-to-expire URL.
        cache.invalidateStreamUrl(row.video_id)
      }
      if (perCallDelayMs > 0) await sleep(perCallDelayMs)
    }
    // Drop anything already expired (lazy cleanup).
    const purged = cache.purgeExpiredStreamUrls()
    lastStats = { refreshed, failed, scanned: rows.length, purged, lastRunAt: now }
    logger.log?.(`[url-refresher] cycle complete: scanned=${rows.length} refreshed=${refreshed} failed=${failed} purged=${purged}`)
    return lastStats
  }

  function start() {
    if (timer) return
    stopped = false
    // First refresh runs after one interval — server startup shouldn't pay this cost.
    timer = setInterval(() => {
      refreshOnce().catch((e) => logger.error?.('[url-refresher] uncaught', e))
    }, intervalMs)
    // Don't keep the process alive just for this timer.
    timer.unref?.()
  }

  function stop() {
    stopped = true
    if (timer) clearInterval(timer)
    timer = null
  }

  function stats() { return { ...lastStats, intervalMs, thresholdMs } }

  return { start, stop, refreshOnce, stats }
}
