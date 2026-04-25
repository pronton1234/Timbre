// Pick the best YouTube candidate for a given iTunes track.
// Scoring is deterministic so it's testable from fixtures.

const STUDIO_HINTS = /vevo|official|records|music$/i
const PENALTY_TERMS = /\b(live|cover|karaoke|remix|instrumental|sped[- ]?up|slowed|reverb|nightcore|8d|mashup)\b/i
const NORMALIZE = s => (s ?? '').toLowerCase().replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim()

export function score(candidate, track) {
  let s = 0
  const cand = {
    title: NORMALIZE(candidate.title),
    channel: NORMALIZE(candidate.channel),
    duration: candidate.duration, // seconds
  }
  const tr = {
    name: NORMALIZE(track.name),
    artist: NORMALIZE(track.artistName),
    durationSec: Math.round((track.durationMs ?? 0) / 1000),
  }

  // Duration: within 3s → +100, within 8s → +40, else 0 / huge penalty if >30s off
  if (tr.durationSec > 0 && cand.duration > 0) {
    const diff = Math.abs(cand.duration - tr.durationSec)
    if (diff <= 3) s += 100
    else if (diff <= 8) s += 40
    else if (diff > 30) s -= 80
  }

  // Title contains artist + track name
  if (cand.title.includes(tr.artist) && cand.title.includes(tr.name)) s += 50
  else if (cand.title.includes(tr.name)) s += 20

  // Channel heuristics
  if (STUDIO_HINTS.test(candidate.channel ?? '')) s += 30
  if (cand.channel.includes(tr.artist)) s += 15

  // Live/cover/karaoke penalties (unless the track itself is that)
  const titleIsLive = PENALTY_TERMS.test(candidate.title ?? '')
  const trackIsLive = PENALTY_TERMS.test(track.name ?? '')
  if (titleIsLive && !trackIsLive) s -= 40

  return s
}

export function pickBest(candidates, track) {
  if (!candidates?.length) return null
  const scored = candidates
    .map(c => ({ candidate: c, score: score(c, track) }))
    .sort((a, b) => b.score - a.score)
  const best = scored[0]
  // Require a plausible match — reject all if top score is too low
  if (best.score < 40) return null
  return { ...best.candidate, matchScore: best.score }
}

export const _internal = { NORMALIZE, STUDIO_HINTS, PENALTY_TERMS }
