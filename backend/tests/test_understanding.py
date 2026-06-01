"""Unit tests for query-understanding JSON parsing (no network)."""
import pytest

from app.search.understanding import parse_understanding


def test_parses_plain_minified_json():
    out = parse_understanding('{"artist":"Adele","title":"Hello","is_obscure":false,"variants":["hello"]}')
    assert out["artist"] == "Adele"
    assert out["title"] == "Hello"


def test_strips_json_fenced_block():
    # Haiku wraps JSON in ```json ... ``` despite instructions — must still parse.
    raw = '```json\n{"artist":"Daft Punk","title":"Get Lucky","is_obscure":false,"variants":["Get Lucky"]}\n```'
    out = parse_understanding(raw)
    assert out["artist"] == "Daft Punk"
    assert out["title"] == "Get Lucky"
    assert out["variants"] == ["Get Lucky"]


def test_strips_bare_fenced_block():
    raw = '```\n{"artist":"Drake","title":"Hotline Bling","is_obscure":false,"variants":["x"]}\n```'
    out = parse_understanding(raw)
    assert out["artist"] == "Drake"


def test_invalid_json_raises():
    with pytest.raises(Exception):
        parse_understanding("sorry, I cannot help with that")
