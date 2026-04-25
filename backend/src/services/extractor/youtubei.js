// Primary extractor. Uses LuanRT/YouTube.js (npm: youtubei.js) in-process.
// No subprocess, no Python.
import { Innertube, UniversalCache } from 'youtubei.js'

let yt = null
let initPromise = null

async function getClient() {
  if (yt) return yt
  if (!initPromise) {
    initPromise = Innertube.create({ cache: new UniversalCache(false), generate_session_locally: true })
  }
  yt = await initPromise
  return yt
}

export async function init() { await getClient() }

export async function search(query, n = 5) {
  const client = await getClient()
  const res = await client.search(query, { type: 'video' })
  const videos = res.videos ?? res.results ?? []
  const mapped = []
  for (const v of videos) {
    if (mapped.length >= n) break
    const id = v.id ?? v.video_id
    if (!id) continue
    mapped.push({
      id,
      title: v.title?.text ?? v.title ?? '',
      duration: v.duration?.seconds ?? v.length_seconds ?? 0,
      channel: v.author?.name ?? v.channel?.name ?? '',
    })
  }
  return mapped
}

export async function getStreamUrl(videoId) {
  const client = await getClient()
  const info = await client.getInfo(videoId)
  const format = info.chooseFormat({ type: 'audio', quality: 'best' })
  if (!format) throw new Error(`no audio format for ${videoId}`)
  return format.decipher(client.session.player)
}

export const _internal = {
  reset() { yt = null; initPromise = null },
  _setClient(mock) { yt = mock },
}
