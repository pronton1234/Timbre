// Self-hosted Cobalt v11 extractor.
//
// Why self-hosted: the public Cobalt v7 API at co.wuk.sh / api.cobalt.tools was
// shut down on Nov 11 2024. Cobalt v11 is a new API (different shape, different
// port, tunnel-by-default for YouTube) and upstream does not run a shared
// public instance anymore — every operator runs their own Docker container.
//
// We run ghcr.io/imputnet/cobalt:11 on the same Oracle ARM VM as this backend,
// bound to 127.0.0.1:9000. The Node process talks to it over the loopback.
//
// v11 API shape (see https://github.com/imputnet/cobalt/blob/main/docs/api.md):
//   POST / with JSON body:
//     { "url": "<youtube watch/shorts URL>",
//       "downloadMode": "audio",
//       "audioFormat": "best" }
//   Response: { status: "tunnel" | "redirect" | "error" | "picker", url?, error? }
//
// For YouTube audio the happy path is "tunnel": Cobalt returns a URL pointing
// back at its own tunnel endpoint; the audio bytes stream through Cobalt
// (and therefore through our VM via the nginx /cobalt/ subpath) to AVPlayer.
// Tunnel URLs are time-limited (~few minutes); caller is expected to treat
// them like the stream URLs from ytdlp and refresh on AVPlayer -11828/-11829.

import { request } from 'undici'

const BASE = process.env.COBALT_BASE_URL || 'http://127.0.0.1:9000'

export async function getStreamUrl(videoId) {
  const res = await request(BASE, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'accept': 'application/json',
    },
    body: JSON.stringify({
      url: `https://youtu.be/${videoId}`,
      downloadMode: 'audio',
      audioFormat: 'best',
    }),
  })
  // Cobalt returns 4xx with a JSON error body. Parse body first so we surface
  // the actual error code (e.g. error.api.youtube.login) rather than a bare
  // HTTP status.
  let json
  try { json = await res.body.json() }
  catch (_) { throw new Error(`cobalt http ${res.statusCode} (non-JSON body)`) }
  if (json.status === 'error') {
    const code = json.error?.code ?? 'unknown'
    throw new Error(`cobalt error: ${code}`)
  }
  if (res.statusCode >= 400) throw new Error(`cobalt http ${res.statusCode}`)
  if (json.status !== 'tunnel' && json.status !== 'redirect') {
    throw new Error(`cobalt unexpected status: ${json.status}`)
  }
  if (!json.url) throw new Error('cobalt: no url in response')
  return json.url
}
