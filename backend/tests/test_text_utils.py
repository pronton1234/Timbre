"""Pure unit tests for normalization helpers (no network)."""
from app.text_utils import norm_key, parse_duration, parse_video_id


def test_norm_key_strips_feat_and_brackets():
    assert norm_key("BNYX", "Fallen (feat. X)") == "bnyx|fallen"
    assert norm_key("Drake", "Hotline Bling [Official Video]") == "drake|hotline bling"
    assert norm_key("A$AP Rocky", "Praise the Lord (Da Shine) ft. Skepta") == "a ap rocky|praise the lord"


def test_norm_key_collapses_punct_and_spaces():
    assert norm_key("  The   Weeknd ", "Blinding   Lights!!!") == "the weeknd|blinding lights"
    assert norm_key("Beyoncé", "Déjà Vu") == norm_key("Beyoncé", "Déjà Vu")  # stable


def test_parse_video_id_watch_url():
    assert parse_video_id("https://www.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ"
    assert parse_video_id("https://youtube.com/watch?v=dQw4w9WgXcQ&t=10s") == "dQw4w9WgXcQ"
    assert parse_video_id("https://music.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ"


def test_parse_video_id_short_and_embed():
    assert parse_video_id("https://youtu.be/dQw4w9WgXcQ") == "dQw4w9WgXcQ"
    assert parse_video_id("https://youtu.be/dQw4w9WgXcQ?si=abc") == "dQw4w9WgXcQ"
    assert parse_video_id("https://www.youtube.com/embed/dQw4w9WgXcQ") == "dQw4w9WgXcQ"
    assert parse_video_id("https://www.youtube.com/shorts/dQw4w9WgXcQ") == "dQw4w9WgXcQ"
    assert parse_video_id("dQw4w9WgXcQ") == "dQw4w9WgXcQ"


def test_parse_video_id_malformed():
    assert parse_video_id("") is None
    assert parse_video_id("https://example.com/watch?v=dQw4w9WgXcQ") is None
    assert parse_video_id("https://www.youtube.com/watch?v=tooShort") is None
    assert parse_video_id("not a url at all") is None
    assert parse_video_id("https://youtube.com/playlist?list=PL123") is None


def test_parse_duration_formats():
    assert parse_duration("3:40") == 220
    assert parse_duration("1:02:03") == 3723
    assert parse_duration(245) == 245
    assert parse_duration(245.7) == 245
    assert parse_duration("245") == 245
    assert parse_duration(None) is None
    assert parse_duration("") is None
    assert parse_duration("not-a-duration") is None
