import express from 'express'
import { openDb, createCache } from './db/cache.js'
import * as extractor from './services/extractor/index.js'
import { createResolveRouter } from './routes/resolve.js'

const PORT = Number(process.env.PORT || 3000)
const CACHE_PATH = process.env.CACHE_PATH || './cache.db'

async function main() {
  const db = openDb(CACHE_PATH)
  const cache = createCache(db)

  // Warm up the primary extractor (Innertube session)
  extractor.init().catch(err => console.error('extractor.init failed:', err))

  const app = express()
  app.set('logger', console)
  app.disable('x-powered-by')

  app.get('/health', (_req, res) => {
    res.json({ ok: true, extractors: extractor.health(), urlCacheSize: cache._urlCacheSize() })
  })

  app.use(createResolveRouter(cache))
  // /stream removed (Apr 2026): on-device extraction via YouTubeKit replaced it.

  app.use((err, _req, res, _next) => {
    console.error('unhandled error', err)
    res.status(500).json({ error: 'internal_error' })
  })

  app.listen(PORT, () => {
    console.log(`spotify-free backend listening on :${PORT}`)
  })
}

main().catch(err => { console.error(err); process.exit(1) })
