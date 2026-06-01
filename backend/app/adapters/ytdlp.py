"""yt-dlp ytsearch fallback — widens recall beyond the YT Music catalog.

In extract_flat mode `duration` may be None; the ranker tolerates missing fields.
Keep yt-dlp updated (`pip install -U yt-dlp`) — YouTube changes extraction often.
"""
import yt_dlp

_OPTS = {"quiet": True, "skip_download": True, "extract_flat": True, "noplaylist": True}


def search(query: str, n: int = 15) -> list[dict]:
    """ytsearch fallback. Normalized candidate dicts (same shape as ytmusic)."""
    out: list[dict] = []
    with yt_dlp.YoutubeDL(_OPTS) as ydl:
        info = ydl.extract_info(f"ytsearch{n}:{query}", download=False) or {}
    for entry in info.get("entries") or []:
        if not entry:
            continue
        video_id = entry.get("id")
        if not video_id:
            continue
        channel = entry.get("channel") or entry.get("uploader") or ""
        out.append(
            {
                "video_id": video_id,
                "title": entry.get("title") or "",
                "artist": None,
                "album": None,
                "duration_sec": entry.get("duration"),
                "channel": channel,
                "view_count": entry.get("view_count"),
                "source_hint": "topic" if channel.endswith(" - Topic") else "other",
            }
        )
    return out
