"""The display (artist,title) of a track must always normalize to its norm_key.
A stale/poisoned row (clean key, verbose or wrong display) must self-heal when
re-canonicalized with the clean label. (network: real DB)"""
import pytest

from app.db import SessionLocal
from app.models import Track, TrackEmbedding, TrackSource
from app.resolver import canonicalize_candidate
from app.text_utils import norm_key

pytestmark = pytest.mark.network

_KEY = "zzheal artist|zzheal song"
_VID = "ZZheal12345"


def _purge(db):
    ids = [t.id for t in db.query(Track).filter(Track.norm_key == _KEY).all()]
    if ids:
        db.query(TrackSource).filter(TrackSource.track_id.in_(ids)).delete(synchronize_session=False)
        db.query(TrackEmbedding).filter(TrackEmbedding.track_id.in_(ids)).delete(synchronize_session=False)
        db.query(Track).filter(Track.id.in_(ids)).delete(synchronize_session=False)
        db.commit()
    db.query(TrackSource).filter(TrackSource.video_id == _VID).delete(synchronize_session=False)
    db.commit()


def test_canonicalize_heals_inconsistent_display():
    db = SessionLocal()
    try:
        _purge(db)
        bad = Track(title="Verbose Song (feat. Someone)", artist="ZZheal Artist, Featured Guy",
                    norm_key=_KEY)
        db.add(bad)
        db.commit()
        bad_id = bad.id

        cand = {"video_id": _VID, "title": "ZZheal Song", "artist": "ZZheal Artist",
                "duration_sec": 200, "source_hint": "topic"}
        track = canonicalize_candidate(db, cand, "ZZheal Artist", "ZZheal Song")

        assert track.id == bad_id, "should dedupe onto the existing row by norm_key"
        db.refresh(track)
        assert norm_key(track.artist, track.title) == track.norm_key == _KEY
        assert track.artist == "ZZheal Artist"
        assert track.title == "ZZheal Song"
    finally:
        _purge(db)
        db.close()
