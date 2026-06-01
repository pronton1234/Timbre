"""Redis helpers — the query->track_id result cache and a health ping.

The cache key is a normalized form of the raw query so 'BNYX fallen' and
'bnyx  Fallen' hit the same entry.
"""
import json
import re

import redis

from app.config import settings

_redis = redis.from_url(settings.REDIS_URL, decode_responses=True)

_SPACES = re.compile(r"\s+")
_PUNCT = re.compile(r"[^\w\s]")


def _norm_query(query: str) -> str:
    q = (query or "").lower()
    q = _PUNCT.sub(" ", q)
    return _SPACES.sub(" ", q).strip()


def _key(query: str) -> str:
    return f"q:{_norm_query(query)}"


def cache_query(query: str, track_id) -> None:
    """Map norm(query) -> track_id for STREAM_CACHE_TTL seconds."""
    _redis.set(_key(query), str(track_id), ex=settings.STREAM_CACHE_TTL)


def get_cached_track_id(query: str) -> str | None:
    return _redis.get(_key(query))


def ping() -> bool:
    try:
        return bool(_redis.ping())
    except Exception:
        return False


def _u_key(query: str) -> str:
    return f"u:{_norm_query(query)}"


def cache_understanding(query: str, parsed: dict) -> None:
    """Cache the parsed query-understanding so repeat queries are deterministic
    and a later LLM hiccup can't silently drop intent. TTL matches the result cache."""
    try:
        _redis.set(_u_key(query), json.dumps(parsed), ex=settings.STREAM_CACHE_TTL)
    except Exception:
        pass


def get_cached_understanding(query: str) -> dict | None:
    try:
        raw = _redis.get(_u_key(query))
        return json.loads(raw) if raw else None
    except Exception:
        return None
