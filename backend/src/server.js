import express from 'express'
import { openDb, createCache } from './db/cache.js'
import * as extractor from './services/extractor/index.js'
import { createResolveRouter } from './routes/resolve.js'
import { createStreamUrlRouter } from './routes/streamUrl.js'
import { createPlayRouter } from './routes/play.js'
import { createPrefetchRouter } from './routes/prefetch.js'
import { createSearchRouter } from './routes/search.js'
import { createArtistTopTracksRouter } from './routes/artist-top-tracks.js'
import { createRadioRouter } from './routes/radio.js'
import { createUrlRefresher } from './workers/url-refresher.js'

const PORT = Number(process.env.PORT || 3000)
const CACHE_PATH = process.env.CACHE_PATH || './cache.db'

async function main() {
  const db = openDb(CACHE_PATH)
  const cache = createCache(db)

  // Warm up the primary extractor (Innertube session)
  extractor.init().catch(err => console.error('extractor.init failed:', err))

  // Start the URL refresher: every hour, refresh URLs expiring within 2h so
  // popular tracks stay hot in the cache. Disabled in test/dev by setting
  // SPOTIFY_DISABLE_URL_REFRESHER=1.
  const urlRefresher = createUrlRefresher(cache)
  if (process.env.SPOTIFY_DISABLE_URL_REFRESHER !== '1') {
    urlRefresher.start()
  }

  const app = express()
  app.set('logger', console)
  app.disable('x-powered-by')

  app.get('/health', (_req, res) => {
    res.json({
      ok: true,
      extractors: extractor.health(),
      urlCacheSize: cache._urlCacheSize(),
      urlRefresher: urlRefresher.stats(),
    })
  })

  app.use(createResolveRouter(cache))
  app.use(createStreamUrlRouter(cache))
  app.use(createPlayRouter(cache))
  app.use(createPrefetchRouter(cache))
  app.use(createSearchRouter())
  app.use(createArtistTopTracksRouter())
  app.use(createRadioRouter())
  // /stream removed (Apr 2026): on-device extraction via YouTubeKit was the
  // sole path. /stream-url restored (Phase 1.1, 2026-04-29): returns a cached
  // or freshly-extracted URL — iOS still has on-device fallback for 503.

  app.use((err, _req, res, _next) => {
    console.error('unhandled error', err)
    res.status(500).json({ error: 'internal_error' })
  })

  app.listen(PORT, () => {
    console.log(`spotify-free backend listening on :${PORT}`)
  })
}

main().catch(err => { console.error(err); process.exit(1) })
