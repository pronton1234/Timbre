// Innertube extractor — delegates to youtube-pool for persistent HTTP/2 connections
// and parallel client racing (IOS, ANDROID, TV_EMBEDDED). First valid response wins.
import { ClientType } from 'youtubei.js'
import * as pool from '../youtube-pool.js'

export async function init() { await pool.init() }

export async function search(query, n = 5) { return pool.search(query, n) }

export async function getStreamUrl(videoId) {
  const { url } = await pool.extract(videoId)
  return url
}

export const _internal = {
  reset() { pool._internal.reset() },
  // Insert a mock client as all racing slots so tests that call getStreamUrl work.
  _setClient(mock) {
    for (const ct of pool._internal.RACE_CLIENTS) {
      pool._internal.pool.set(ct, mock)
    }
  },
}
