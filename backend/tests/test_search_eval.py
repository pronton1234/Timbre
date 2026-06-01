"""Phase 1 search eval (network). 50 queries: 40 specific songs + 10 vaguer.

Asserts top-1 norm_key match rate >= THRESHOLD on the specific-song subset and
prints the misses so ranking weights can be tuned.

Run on the VM with infra + API keys:  pytest -m network tests/test_search_eval.py -s
"""
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.text_utils import norm_key

pytestmark = pytest.mark.network

client = TestClient(app)

THRESHOLD = 0.85

# (query, artist, title) — expected_norm_key is computed from artist+title.
SPECIFIC = [
    ("daft punk get lucky", "Daft Punk", "Get Lucky"),
    ("blinding lights weeknd", "The Weeknd", "Blinding Lights"),
    ("adele hello", "Adele", "Hello"),
    ("drake hotline bling", "Drake", "Hotline Bling"),
    ("billie eilish bad guy", "Billie Eilish", "bad guy"),
    ("kendrick humble", "Kendrick Lamar", "HUMBLE."),
    ("tame impala the less i know the better", "Tame Impala", "The Less I Know The Better"),
    ("dua lipa levitating", "Dua Lipa", "Levitating"),
    ("harry styles as it was", "Harry Styles", "As It Was"),
    ("travis scott sicko mode", "Travis Scott", "SICKO MODE"),
    ("frank ocean thinkin bout you", "Frank Ocean", "Thinkin Bout You"),
    ("sza kill bill", "SZA", "Kill Bill"),
    ("bad bunny titi me pregunto", "Bad Bunny", "Tití Me Preguntó"),
    ("doja cat say so", "Doja Cat", "Say So"),
    ("post malone circles", "Post Malone", "Circles"),
    ("lana del rey summertime sadness", "Lana Del Rey", "Summertime Sadness"),
    ("arctic monkeys do i wanna know", "Arctic Monkeys", "Do I Wanna Know?"),
    ("childish gambino redbone", "Childish Gambino", "Redbone"),
    ("tyler the creator earfquake", "Tyler, The Creator", "EARFQUAKE"),
    ("steve lacy bad habit", "Steve Lacy", "Bad Habit"),
    ("the killers mr brightside", "The Killers", "Mr. Brightside"),
    ("rihanna umbrella", "Rihanna", "Umbrella"),
    ("eminem lose yourself", "Eminem", "Lose Yourself"),
    ("queen bohemian rhapsody", "Queen", "Bohemian Rhapsody"),
    ("michael jackson billie jean", "Michael Jackson", "Billie Jean"),
    ("nirvana smells like teen spirit", "Nirvana", "Smells Like Teen Spirit"),
    ("the beatles hey jude", "The Beatles", "Hey Jude"),
    ("coldplay yellow", "Coldplay", "Yellow"),
    ("radiohead creep", "Radiohead", "Creep"),
    ("amy winehouse rehab", "Amy Winehouse", "Rehab"),
    ("kanye west stronger", "Kanye West", "Stronger"),
    ("beyonce halo", "Beyoncé", "Halo"),
    ("ed sheeran shape of you", "Ed Sheeran", "Shape of You"),
    ("the chainsmokers closer", "The Chainsmokers", "Closer"),
    ("calvin harris feel so close", "Calvin Harris", "Feel So Close"),
    ("avicii wake me up", "Avicii", "Wake Me Up"),
    ("david bowie heroes", "David Bowie", "Heroes"),
    ("fleetwood mac dreams", "Fleetwood Mac", "Dreams"),
    ("gorillaz feel good inc", "Gorillaz", "Feel Good Inc."),
    ("mac miller good news", "Mac Miller", "Good News"),
]

# Vaguer / obscure — not held to the threshold, just exercised for crashes.
VAGUE = [
    "that song that goes ooh na na",
    "sad lofi piano for studying",
    "upbeat 2010s indie road trip anthem",
    "viral tiktok sped up phonk",
    "dark moody trap beat unreleased leak",
    "80s synthwave driving at night",
    "acoustic cover of a pop hit",
    "best workout hype song",
    "rainy day jazz cafe",
    "summer reggaeton party banger",
]


def _top1_norm_key(query: str) -> str | None:
    r = client.post("/search", json={"query": query, "top_k": 5}, params={"fresh": "true"})
    assert r.status_code == 200, r.text
    results = r.json()["results"]
    if not results:
        return None
    top = results[0]
    return norm_key(top["artist"], top["title"])


def test_specific_song_top1_match_rate():
    hits, misses = 0, []
    for query, artist, title in SPECIFIC:
        expected = norm_key(artist, title)
        got = _top1_norm_key(query)
        if got == expected:
            hits += 1
        else:
            misses.append((query, expected, got))

    rate = hits / len(SPECIFIC)
    print(f"\nspecific-song top-1 match rate: {rate:.2%} ({hits}/{len(SPECIFIC)})")
    for q, exp, got in misses:
        print(f"  MISS  query={q!r}  expected={exp!r}  got={got!r}")
    assert rate >= THRESHOLD, f"{rate:.2%} < {THRESHOLD:.0%}"


@pytest.mark.parametrize("query", VAGUE)
def test_vague_queries_do_not_crash(query):
    r = client.post("/search", json={"query": query, "top_k": 5}, params={"fresh": "true"})
    assert r.status_code == 200, r.text
    for item in r.json()["results"]:
        assert item["video_id"]
