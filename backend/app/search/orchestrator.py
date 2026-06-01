"""Phase 1 orchestrator: query -> understanding -> recall -> rank -> canonicalize.

Only the returned top_k are canonicalized into DB rows (resolve_track) — we do
NOT write a Track for every fan-out candidate.
"""
from sqlalchemy.orm import Session

from app import cache
from app.config import settings
from app.resolver import canonicalize_candidate, track_to_out
from app.search import embeddings
from app.search.ranking import canonical_label, score_candidate
from app.search.recall import fan_out
from app.search.understanding import understand


async def run_search(db: Session, query: str, top_k: int = 10) -> list[dict]:
    parsed = understand(query)
    # Raw query first (best recall + the yt-dlp call keys off variants[0]), then a
    # bounded number of paraphrases — fan-out cost is what blew the client timeout.
    raw = [query] + [v for v in (parsed.get("variants") or []) if v != query]
    variants = raw[: settings.SEARCH_MAX_VARIANTS]
    pool = await fan_out(variants)

    if not pool:
        return []

    q_vec = embeddings.embed([query])[0]
    cand_vecs = embeddings.embed([embeddings.candidate_text(c) for c in pool])
    for c, cv in zip(pool, cand_vecs):
        c["_sim"] = embeddings.cosine(q_vec, cv)
        c["_vec"] = cv  # reused below — don't re-embed per result

    ranked = sorted(pool, key=lambda c: score_candidate(c, parsed, c["_sim"]), reverse=True)

    # Walk the ranked pool canonicalizing until we have top_k *distinct* tracks.
    # Different pool candidates (e.g. a YT Music "- Topic" upload and a yt-dlp
    # result for the same song) can collapse onto one canonical track_id, so we
    # dedupe by track_id here — keeping the highest-ranked occurrence. Bounded so
    # a dupe-heavy pool can't fan out into unbounded resolve_track calls.
    results: list[dict] = []
    seen_track_ids: set = set()
    max_canonicalize = top_k * 3
    for c in ranked[:max_canonicalize]:
        if len(results) >= top_k:
            break
        # Prefer the LLM's clean artist/title when this candidate is the named
        # artist's recording — dedups variants and gives the phone a clean label.
        artist, title = canonical_label(c, parsed, query)
        labeled = {**c, "artist": artist, "title": title}
        try:
            # No network: canonicalize from the candidate's own ranked video_id.
            track = canonicalize_candidate(db, labeled, artist, title)
        except ValueError:
            continue
        if track.id in seen_track_ids:
            continue
        seen_track_ids.add(track.id)
        embeddings.store_track_embedding(db, track.id, labeled["_vec"])
        out = track_to_out(track)
        out["score"] = score_candidate(labeled, parsed, labeled["_sim"])
        results.append(out)

    if results:
        cache.cache_query(query, results[0]["track_id"])
    return results
