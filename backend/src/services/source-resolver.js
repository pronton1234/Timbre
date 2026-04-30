// Orchestrates the audio source priority chain for a given track:
//
//   1. audio_sources cache (Audius hit from a prior request)
//   2. Audius live search (if title + artist provided)
//   3. stream_urls cache (YouTube URL from a prior request or the pre-extraction worker)
//   4. Live YouTube extraction (slowest path — on-device fallback exists if this fails)
//
// Returns { url, source, extractor } where `source` is "audius" | "youtube" and
// `extractor` identifies the YouTube extractor used (ytdlp | piped | cobalt | innertube).
// Throws only if ALL paths fail.
import { findStreamUrl as audiusFindStreamUrl } from './audius-client.js'
import * as defaultExtractor from './extractor/index.js'

export function createSourceResolver(cache, deps = {}) {
  const findAudiusStreamUrl = deps.findAudiusStreamUrl ?? audiusFindStreamUrl
  const extractStream = deps.extractStream ?? defaultExtractor.extractStream

  // Resolve the best stream URL for a track. opts carries optional track metadata.
  async function resolveBestSource(videoId, { itunesTrackId, title, artist, isrc } = {}) {
    // 1. Audius cache hit (iTunes track ID keyed)
    if (itunesTrackId) {
      const cached = cache.getAudioSource(itunesTrackId)
      if (cached) {
        return { url: cached.streamUrl, source: cached.source, extractor: cached.source, fromCache: true }
      }
    }

    // 2. Audius live search (if we have enough metadata)
    if (title && artist) {
      try {
        const result = await findAudiusStreamUrl({ title, artist, isrc })
        if (result?.url) {
          if (itunesTrackId) {
            cache.setAudioSource(itunesTrackId, {
              source: 'audius',
              sourceTrackId: result.audiusTrackId,
              streamUrl: result.url,
            })
          }
          return { url: result.url, source: 'audius', extractor: 'audius', fromCache: false }
        }
      } catch { /* fall through to YouTube */ }
    }

    // 3. YouTube stream URL cache (warmed by the pre-extraction worker or prior /play calls)
    if (videoId) {
      const cached = cache.getStreamUrl(videoId)
      if (cached) {
        return { url: cached.url, source: 'youtube', extractor: cached.extractor, fromCache: true }
      }
    }

    // 4. Live YouTube extraction
    if (!videoId) throw new Error('no_video_id_and_audius_miss')
    const result = await extractStream(videoId)
    cache.setStreamUrl(videoId, result.url, result.extractor)
    return { url: result.url, source: 'youtube', extractor: result.extractor, fromCache: false }
  }

  return { resolveBestSource }
}
