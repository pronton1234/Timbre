// Cloudflare Worker — edge proxy for Timbre backend.
//
// Purpose: terminates the iOS → backend connection at the nearest Cloudflare PoP
// (~200+ global PoPs, free tier) and forwards to the Oracle origin over a persistent
// HTTP/2 connection. This drops device-to-backend RTT from 80–200ms (single-region
// Oracle) to 30–80ms for users not near the Oracle datacenter.
//
// Routes proxied: /play, /stream-url, /prefetch, /resolve, /health, /search (future)
// All other paths return 404 immediately at the edge — no origin hit.
//
// Deployment:
//   1. Install wrangler: npm i -g wrangler
//   2. Set ORIGIN_URL in wrangler.toml (your Oracle backend URL)
//   3. wrangler deploy
//
// Environment variables (set in Cloudflare dashboard or wrangler.toml):
//   ORIGIN_URL  — full URL of the Oracle backend, e.g. https://free-spotify.duckdns.org
//
// Streaming responses (from /play) are forwarded as-is using TransformStream so
// HybridStreamLoader receives bytes as they flow — no buffering at the edge.

const ALLOWED_PATHS = new Set(['/play', '/stream-url', '/prefetch', '/resolve', '/health'])

function isAllowedPath(pathname) {
  return ALLOWED_PATHS.has(pathname) || pathname.startsWith('/search')
}

// Headers to forward from client to origin. Keep this list minimal — we do not
// want to forward cookies, Authorization, or Cloudflare-specific headers.
const CLIENT_HEADERS_TO_FORWARD = [
  'range',
  'accept',
  'accept-encoding',
  'content-type',
  'content-length',
]

// Headers to forward from origin to client.
const ORIGIN_HEADERS_TO_FORWARD = [
  'content-type',
  'content-length',
  'content-range',
  'accept-ranges',
  'last-modified',
  'etag',
  'x-direct-url',
  'x-source',
  'x-extractor',
]

export default {
  async fetch(request, env) {
    const url = new URL(request.url)

    if (!isAllowedPath(url.pathname)) {
      return new Response('not found', { status: 404 })
    }

    const originBase = env.ORIGIN_URL?.replace(/\/$/, '') ?? ''
    if (!originBase) {
      return new Response('ORIGIN_URL not configured', { status: 500 })
    }

    // Build the upstream request to the Oracle origin.
    const originUrl = `${originBase}${url.pathname}${url.search}`
    const forwardHeaders = new Headers()
    for (const name of CLIENT_HEADERS_TO_FORWARD) {
      const val = request.headers.get(name)
      if (val) forwardHeaders.set(name, val)
    }
    // Identify ourselves so server logs can see edge hits vs direct hits.
    forwardHeaders.set('x-forwarded-by', 'timbre-cf-worker')

    let originResponse
    try {
      originResponse = await fetch(originUrl, {
        method: request.method,
        headers: forwardHeaders,
        body: request.method !== 'GET' && request.method !== 'HEAD' ? request.body : undefined,
      })
    } catch (e) {
      return new Response(JSON.stringify({ error: 'origin_unreachable', detail: e.message }), {
        status: 503,
        headers: { 'content-type': 'application/json' },
      })
    }

    // Forward selected headers from the origin response.
    const responseHeaders = new Headers()
    for (const name of ORIGIN_HEADERS_TO_FORWARD) {
      const val = originResponse.headers.get(name)
      if (val) responseHeaders.set(name, val)
    }
    // Allow iOS to read custom headers (CORS for any future web usage).
    responseHeaders.set('access-control-expose-headers', ORIGIN_HEADERS_TO_FORWARD.join(', '))

    // Stream the body through — critical for /play so HybridStreamLoader doesn't
    // have to wait for the full chunk before iOS starts receiving bytes.
    return new Response(originResponse.body, {
      status: originResponse.status,
      headers: responseHeaders,
    })
  },
}
