"""Unreleased/leak eval (network) — the product's actual purpose: surface the
SPECIFIC named song even when it's a leak on a fan channel, not a different
released track by the same artist.

Asserts the top-1 result's title contains the named song's title tokens. Leak
uploads are volatile (YouTube takedowns), so we hold a rate threshold and print
misses rather than requiring every single one.

Run on the VM:  pytest -m network tests/test_unreleased_eval.py -s
"""
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.text_utils import _normalize

pytestmark = pytest.mark.network

client = TestClient(app)
THRESHOLD = 0.66

# (query, expected title — its tokens must all appear in the top result's title)
LEAKS = [
    ("cancun sega playboi carti", "cancun"),
    ("molly playboi carti", "molly"),
    ("kid cudi playboi carti", "kid cudi"),
    ("pissy pamper playboi carti", "pissy pamper"),
    ("a man travis scott", "a man"),
    ("green and purple travis scott", "green purple"),
    ("hellboy travis scott", "hellboy"),
    ("lost files juice wrld", "lost files"),
]


def _top_title_tokens(query: str):
    r = client.post("/search", json={"query": query, "top_k": 5}, params={"fresh": "true"})
    assert r.status_code == 200, r.text
    results = r.json()["results"]
    if not results:
        return None, None
    top = results[0]
    return set(_normalize(top["title"]).split()), f'{top["artist"]} - {top["title"]}'


def test_named_unreleased_song_surfaces_top1():
    hits, misses = 0, []
    for query, want_title in LEAKS:
        want = set(_normalize(want_title).split())
        got, label = _top_title_tokens(query)
        if got is not None and want <= got:
            hits += 1
        else:
            misses.append((query, want_title, label))
    rate = hits / len(LEAKS)
    print(f"\nunreleased top-1 title-match rate: {rate:.2%} ({hits}/{len(LEAKS)})")
    for q, want, label in misses:
        print(f"  MISS  query={q!r}  wanted title~{want!r}  got={label!r}")
    assert rate >= THRESHOLD, f"{rate:.2%} < {THRESHOLD:.0%}"
