"""Round-trip test for the understanding cache (real Redis).

Uses a sentinel query namespaced so it can never collide with a real search
query's normalized cache key (a past version of this test poisoned the prod key
for 'daft punk get lucky')."""
import pytest

from app import cache

pytestmark = pytest.mark.network  # touches Redis

_SENTINEL = "zzunittestcacheunderstanding sentinel query 9f3a"


def test_understanding_cache_round_trip():
    parsed = {"artist": "Sentinel", "title": "Probe", "is_obscure": False, "variants": [_SENTINEL]}
    cache.cache_understanding(_SENTINEL, parsed)
    # Punctuation/whitespace-insensitive hit on the same normalized key.
    assert cache.get_cached_understanding(f"  {_SENTINEL.upper()}!!  ") == parsed


def test_understanding_cache_miss_returns_none():
    assert cache.get_cached_understanding("zz no such query 12345 nonexistent zzz") is None
