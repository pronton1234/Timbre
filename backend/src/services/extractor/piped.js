// Fallback extractor #1: Piped public instance.
// Docs: https://docs.piped.video/
import { request } from 'undici'

const BASE = process.env.PIPED_BASE_URL || 'https://pipedapi.kavin.rocks'

export async function getStreamUrl(videoId) {
  const res = await request(`${BASE}/streams/${encodeURIComponent(videoId)}`)
  if (res.statusCode >= 400) throw new Error(`piped ${res.statusCode}`)
  const json = await res.body.json()
  const streams = json.audioStreams ?? []
  if (!streams.length) throw new Error('piped: no audioStreams')
  // Prefer highest-bitrate m4a, fall back to highest-bitrate anything
  const byBitrate = [...streams].sort((a, b) => (b.bitrate ?? 0) - (a.bitrate ?? 0))
  const m4a = byBitrate.find(s => (s.format ?? '').toLowerCase().includes('m4a'))
  const picked = m4a ?? byBitrate[0]
  if (!picked?.url) throw new Error('piped: no url on chosen stream')
  return picked.url
}
