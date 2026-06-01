"""Recall fan-out: run the three adapters across every query variant
concurrently, then dedupe into a single candidate pool (target 50-100).
"""
import asyncio

from app.config import settings

from app.adapters import exa, ytdlp, ytmusic

# Per-adapter timeouts (seconds). A slow adapter (esp. the yt-dlp subprocess)
# must not stall the whole search — we cap each and take whatever came back.
_TIMEOUTS = {"ytmusic": 5.0, "ytdlp": 6.0, "exa": 5.0}

# Fields whose presence makes a record "richer" — when two candidates share a
# video_id we keep the one with more of these populated.
_RICHNESS_FIELDS = ("duration_sec", "channel", "artist", "album", "source_hint", "view_count")


def _richness(c: dict) -> int:
    return sum(1 for f in _RICHNESS_FIELDS if c.get(f) is not None)


def _merge(into: dict, other: dict) -> dict:
    """Fill missing fields of `into` from `other` (keep `into`'s non-null values)."""
    for f in _RICHNESS_FIELDS:
        if into.get(f) is None and other.get(f) is not None:
            into[f] = other[f]
    return into


async def _run(fn, arg, timeout: float) -> list[dict]:
    """Run a sync adapter off-thread, bounded by `timeout`. Returns [] on
    timeout or error so one slow/failing adapter can't sink the whole fan-out."""
    try:
        return await asyncio.wait_for(asyncio.to_thread(fn, arg), timeout)
    except Exception:
        return []


async def fan_out(variants: list[str]) -> list[dict]:
    """Concurrently search all adapters over all variants; dedupe by video_id."""
    tasks = []
    for i, v in enumerate(variants):
        tasks.append(_run(ytmusic.search_songs, v, _TIMEOUTS["ytmusic"]))
        tasks.append(_run(exa.search, v, _TIMEOUTS["exa"]))
        # yt-dlp spawns a subprocess (the heaviest adapter, and least additive across
        # paraphrases) — run it on the raw query only to bound latency on a 1-core box.
        if i == 0:
            tasks.append(_run(ytdlp.search, v, _TIMEOUTS["ytdlp"]))

    results = await asyncio.gather(*tasks, return_exceptions=True)

    by_id: dict[str, dict] = {}
    for res in results:
        if isinstance(res, Exception):
            continue
        for c in res:
            vid = c.get("video_id")
            if not vid:
                continue
            if vid not in by_id:
                by_id[vid] = dict(c)
            else:
                existing = by_id[vid]
                # Keep the richer record as the base, merge the other's extras in.
                if _richness(c) > _richness(existing):
                    by_id[vid] = _merge(dict(c), existing)
                else:
                    by_id[vid] = _merge(existing, c)
    pool = list(by_id.values())
    return pool[: settings.SEARCH_MAX_POOL]
