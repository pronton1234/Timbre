"""Phase 0 acceptance tests. Hit live ytmusicapi + DB + Redis — marked network.

Run on the VM with infra up:  pytest -m network tests/test_resolve.py
"""
import pytest
from fastapi.testclient import TestClient

from app.main import app

pytestmark = pytest.mark.network

client = TestClient(app)

KNOWN_SONGS = [
    ("Daft Punk", "Get Lucky"),
    ("The Weeknd", "Blinding Lights"),
    ("Adele", "Hello"),
    ("Drake", "Hotline Bling"),
    ("Billie Eilish", "bad guy"),
    ("Kendrick Lamar", "HUMBLE."),
    ("Tame Impala", "The Less I Know The Better"),
    ("Dua Lipa", "Levitating"),
    ("Harry Styles", "As It Was"),
    ("Travis Scott", "SICKO MODE"),
    ("Frank Ocean", "Thinkin Bout You"),
    ("SZA", "Kill Bill"),
    ("Bad Bunny", "Tití Me Preguntó"),
    ("Doja Cat", "Say So"),
    ("Post Malone", "Circles"),
    ("Lana Del Rey", "Summertime Sadness"),
    ("Arctic Monkeys", "Do I Wanna Know?"),
    ("Childish Gambino", "Redbone"),
    ("Tyler, The Creator", "EARFQUAKE"),
    ("Steve Lacy", "Bad Habit"),
]


def test_health_ok():
    r = client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok", body
    assert body["db"] == "up"
    assert body["redis"] == "up"


@pytest.mark.parametrize("artist,title", KNOWN_SONGS)
def test_resolve_returns_video_and_track(artist, title):
    r = client.post("/resolve", json={"artist": artist, "title": title, "duration_sec": None})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["video_id"], body
    assert body["track_id"], body


def test_resolve_is_idempotent_via_norm_key():
    payload = {"artist": "Daft Punk", "title": "Get Lucky", "duration_sec": None}
    first = client.post("/resolve", json=payload).json()
    second = client.post("/resolve", json={**payload, "title": "Get Lucky (feat. Pharrell)"}).json()
    assert first["track_id"] == second["track_id"]


def test_get_track_returns_stored_video_id():
    resolved = client.post(
        "/resolve", json={"artist": "Adele", "title": "Hello", "duration_sec": None}
    ).json()
    fetched = client.get(f"/tracks/{resolved['track_id']}").json()
    assert fetched["track_id"] == resolved["track_id"]
    assert fetched["video_id"] == resolved["video_id"]
