"""YouTube Music catalog search via InnerTube (ytmusicapi).

The unauthenticated client is sufficient for search — no oauth.json needed.
Instantiated once at module load and reused (don't hammer it; the orchestrator's
fan-out is only a handful of calls).
"""
from ytmusicapi import YTMusic

from app.text_utils import parse_duration

_yt = YTMusic()


def _first_artist(raw: dict) -> str:
    artists = raw.get("artists") or []
    names = [a.get("name") for a in artists if a.get("name")]
    return ", ".join(names) if names else ""


def search_songs(query: str, limit: int = 15) -> list[dict]:
    """Return normalized candidate dicts:
    {video_id, title, artist, album, duration_sec, channel, source_hint}.

    'songs' results are auto-generated '- Topic' uploads -> source_hint='topic'.
    """
    raw_results = _yt.search(query, filter="songs", limit=limit) or []
    out: list[dict] = []
    for r in raw_results:
        video_id = r.get("videoId")
        if not video_id:
            continue
        artist = _first_artist(r)
        album = (r.get("album") or {}).get("name") if isinstance(r.get("album"), dict) else None
        duration_sec = r.get("duration_seconds") or parse_duration(r.get("duration"))
        out.append(
            {
                "video_id": video_id,
                "title": r.get("title") or "",
                "artist": artist,
                "album": album,
                "duration_sec": duration_sec,
                "channel": artist,
                "source_hint": "topic",
            }
        )
    return out
