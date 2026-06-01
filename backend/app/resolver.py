"""Phase 0 resolver: turn an (artist, title) into a canonical Track carrying a
playable videoId. The candidate-selection logic lives behind one function
(`select_best`) so it can be swapped for the Phase 1 ranker as a one-liner.
"""
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.adapters import ytmusic
from app.models import Track, TrackSource
from app.search.ranking import score_candidate
from app.text_utils import norm_key

_DURATION_TOLERANCE_SEC = 3


def _title_sim(target_title: str, cand_title: str) -> float:
    """Cheap text similarity used as `query_sim` for the resolver's per-candidate
    ranking (the embedding-based sim lives in the search orchestrator)."""
    a = set(norm_key("", target_title).split())
    b = set(norm_key("", cand_title).split())
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def select_best(candidates: list[dict], artist: str, title: str, duration_sec: int | None) -> dict | None:
    """Pick the best ytmusic candidate for a known (artist, title).

    Delegates to the Phase 1 ranker (`score_candidate`). We don't embed here, so
    `query_sim` is an exact-norm_key (1.0) / title-token-overlap proxy; duration
    closeness breaks ties so the right-length upload wins.
    """
    if not candidates:
        return None
    target = norm_key(artist, title)
    parsed = {"artist": artist, "title": title, "is_obscure": False}

    def score(c: dict) -> tuple[float, float]:
        c_key = norm_key(c.get("artist") or artist, c.get("title") or "")
        query_sim = 1.0 if c_key == target else _title_sim(title, c.get("title") or "")
        ranker = score_candidate(c, parsed, query_sim)
        dur = c.get("duration_sec")
        closeness = -abs(dur - duration_sec) if (duration_sec and dur) else 0.0
        return (ranker, closeness)

    return max(candidates, key=score)


def _best_source(track: Track) -> TrackSource | None:
    """Highest-confidence non-dead source, or None."""
    alive = [s for s in track.sources if not s.is_dead]
    if not alive:
        return None
    return max(alive, key=lambda s: s.confidence)


def _heal_display(db: Session, track: Track, artist: str, title: str) -> None:
    """Enforce the invariant that a track's display normalizes to its norm_key.

    A poisoned row (clean key but verbose/wrong artist+title, e.g. from an earlier
    code path) is corrected to the canonical (artist, title) — which by construction
    normalize to the same key, since the row was looked up by norm_key(artist, title).
    """
    if norm_key(track.artist, track.title) != track.norm_key and norm_key(artist, title) == track.norm_key:
        track.artist = artist
        track.title = title
        db.commit()


def _find_existing(db: Session, artist: str, title: str, duration_sec: int | None) -> Track | None:
    key = norm_key(artist, title)
    rows = db.scalars(select(Track).where(Track.norm_key == key)).all()
    if not rows:
        return None
    if duration_sec is not None:
        for t in rows:
            if t.duration_sec is not None and abs(t.duration_sec - duration_sec) <= _DURATION_TOLERANCE_SEC:
                _heal_display(db, t, artist, title)
                return t
        # No duration match — fall through to the first row (norm_key still dedups).
    _heal_display(db, rows[0], artist, title)
    return rows[0]


def _source_kind(candidate: dict) -> str:
    hint = candidate.get("source_hint")
    if hint == "topic":
        return "topic"
    if hint == "artist_verified":
        return "artist_verified"
    if hint == "other":
        return "other"
    return "user_upload"


def _upsert_source(db: Session, track: Track, candidate: dict, artist: str, title: str) -> None:
    """Attach the candidate's video_id to `track`, reviving an existing (UNIQUE)
    source row in place rather than inserting a duplicate."""
    confidence = (
        1.0
        if norm_key(candidate.get("artist") or artist, candidate.get("title") or "") == norm_key(artist, title)
        else 0.5
    )
    existing_src = db.scalar(select(TrackSource).where(TrackSource.video_id == candidate["video_id"]))
    if existing_src is not None:
        existing_src.is_dead = False
        existing_src.confidence = confidence
        existing_src.source_kind = _source_kind(candidate)
        existing_src.track_id = track.id
    else:
        db.add(
            TrackSource(
                track_id=track.id,
                video_id=candidate["video_id"],
                source_kind=_source_kind(candidate),
                confidence=confidence,
            )
        )


def _create_track(db: Session, candidate: dict, artist: str, title: str, duration_sec: int | None) -> Track:
    track = Track(
        title=candidate.get("title") or title,
        artist=candidate.get("artist") or artist,
        album=candidate.get("album"),
        duration_sec=candidate.get("duration_sec") or duration_sec,
        norm_key=norm_key(artist, title),
    )
    db.add(track)
    db.flush()  # assign track.id
    return track


def resolve_track(db: Session, artist: str, title: str, duration_sec: int | None) -> Track:
    """Resolve or create a canonical Track for (artist, title).

    Used by the `/resolve` endpoint, which has only metadata and must hit YT
    Music to find a video. The search orchestrator uses `canonicalize_candidate`
    instead — it already has a ranked `video_id` and must not re-search.
    """
    existing = _find_existing(db, artist, title, duration_sec)
    if existing is not None and _best_source(existing) is not None:
        return existing

    candidates = ytmusic.search_songs(f"{artist} {title}".strip())
    best = select_best(candidates, artist, title, duration_sec)
    if best is None:
        raise ValueError(f"no candidate found for {artist!r} {title!r}")

    track = existing or _create_track(db, best, artist, title, duration_sec)
    _upsert_source(db, track, best, artist, title)
    db.commit()
    db.refresh(track)
    return track


def canonicalize_candidate(db: Session, candidate: dict, artist: str, title: str) -> Track:
    """Create/dedupe a canonical Track from an already-ranked pool candidate that
    carries a `video_id` — NO network call (the latency-critical search path).

    Dedupes by norm_key: if a canonical track with a live source already exists,
    return it as-is; otherwise create the track and/or attach this video_id.
    """
    if not candidate.get("video_id"):
        raise ValueError("candidate has no video_id")
    duration_sec = candidate.get("duration_sec")

    existing = _find_existing(db, artist, title, duration_sec)
    if existing is not None and _best_source(existing) is not None:
        return existing

    track = existing or _create_track(db, candidate, artist, title, duration_sec)
    _upsert_source(db, track, candidate, artist, title)
    db.commit()
    db.refresh(track)
    return track


def track_to_out(track: Track) -> dict:
    """Serialize a Track plus its current best source into the API shape."""
    src = _best_source(track)
    return {
        "track_id": track.id,
        "title": track.title,
        "artist": track.artist,
        "album": track.album,
        "duration_sec": track.duration_sec,
        "video_id": src.video_id if src else "",
        "source_kind": src.source_kind if src else "",
    }


def best_source(track: Track) -> TrackSource | None:
    return _best_source(track)
