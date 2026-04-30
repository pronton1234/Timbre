// Innertube extraction pool: persistent HTTP/2 connections + parallel client racing.
//
// Three Innertube instances (IOS, ANDROID, TV_EMBEDDED) share one undici Agent.
// The Agent maintains per-origin connection pools with keepalive, so:
//   - cold-connection cost (DNS + TLS) is paid once per origin, not per extraction
//   - warm extractions save ~100–200ms vs a fresh connection every call
//
// extract(videoId) fires all three clients in parallel and returns whichever
// responds first with a valid audio URL. Stragglers are abandoned.
import { Innertube, UniversalCache, ClientType } from 'youtubei.js'
import { Agent, fetch as undiciFetch } from 'undici'

// One Agent manages a pool of connections per origin. 10 sockets per origin is
// more than enough for sequential extractions; we never parallelize more than ~3.
const sharedAgent = new Agent({
  connections: 10,
  keepAliveTimeout: 60_000,
  keepAliveMaxTimeout: 300_000,
})

function makePooledFetch() {
  return (url, opts = {}) => undiciFetch(url, { ...opts, dispatcher: sharedAgent })
}

// Client types to race. IOS and ANDROID use different cipher paths and are
// less aggressively rate-limited from datacenter IPs than the web client.
const RACE_CLIENTS = [ClientType.IOS, ClientType.ANDROID, ClientType.TV_EMBEDDED]

export { RACE_CLIENTS }

const _pool = new Map()  // ClientType enum value → Innertube instance

export async function getClient(clientType = ClientType.IOS) {
  if (_pool.has(clientType)) return _pool.get(clientType)
  const client = await Innertube.create({
    cache: new UniversalCache(false),
    generate_session_locally: true,
    client_type: clientType,
    fetch: makePooledFetch(),
  })
  _pool.set(clientType, client)
  return client
}

export async function init() {
  await Promise.allSettled(RACE_CLIENTS.map(ct => getClient(ct)))
}

// Race all three clients. First valid response wins; all-fail → throws.
export async function extract(videoId, { clients = RACE_CLIENTS } = {}) {
  const settled = await Promise.allSettled(clients.map(ct => getClient(ct)))
  const ready = settled.flatMap((r, i) =>
    r.status === 'fulfilled' ? [{ client: r.value, type: clients[i] }] : []
  )
  if (ready.length === 0) throw new Error('no innertube clients available')

  return new Promise((resolve, reject) => {
    let remaining = ready.length
    let resolved = false
    let lastErr

    for (const { client, type } of ready) {
      client.getInfo(videoId)
        .then(info => {
          const format = info.chooseFormat({ type: 'audio', quality: 'best' })
          if (!format) throw new Error(`no audio format for ${videoId} via client ${type}`)
          return format.decipher(client.session.player)
        })
        .then(url => {
          if (!resolved) { resolved = true; resolve({ url, clientType: type }) }
        })
        .catch(err => {
          lastErr = err
          remaining--
          if (!resolved && remaining === 0) reject(lastErr)
        })
    }
  })
}

export async function search(query, n = 5) {
  const client = await getClient(ClientType.IOS)
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

export const _internal = {
  pool: _pool,
  RACE_CLIENTS,
  reset() { _pool.clear() },
}
