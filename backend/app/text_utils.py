"""Normalization helpers shared across the resolver, ranker, and adapters."""
import re
from urllib.parse import parse_qs, urlparse

# Anything in (), [], {} — typically "(feat. X)", "[Official Video]".
_BRACKETS = re.compile(r"[\(\[\{].*?[\)\]\}]")
# Leading "feat./featuring/ft./with" segment that isn't bracketed.
_FEAT = re.compile(r"\b(feat\.?|featuring|ft\.?|with)\b.*$", re.IGNORECASE)
# Any char that isn't a word char or whitespace.
_PUNCT = re.compile(r"[^\w\s]")
_SPACES = re.compile(r"\s+")

_VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")


def normalize(s: str) -> str:
    """Lowercase, strip brackets/feat. segments/punctuation, collapse spaces.
    Shared by the dedup key (`norm_key`) and the ranker's lexical matching."""
    s = (s or "").lower()
    s = _BRACKETS.sub(" ", s)
    s = _FEAT.sub(" ", s)
    s = _PUNCT.sub(" ", s)
    s = _SPACES.sub(" ", s).strip()
    return s


# Back-compat internal alias.
_normalize = normalize


def norm_key(artist: str, title: str) -> str:
    """Normalized dedup key 'artist|title': lowercase, strip feat./brackets/
    punctuation, collapse spaces. e.g. ('BNYX', 'Fallen (feat. X)') -> 'bnyx|fallen'."""
    return f"{_normalize(artist)}|{_normalize(title)}"


def parse_video_id(url: str) -> str | None:
    """Extract the YouTube videoId from a watch or youtu.be URL. None if not a YT video."""
    if not url:
        return None
    # Bare 11-char id passed through.
    if _VIDEO_ID.match(url):
        return url

    parsed = urlparse(url)
    host = (parsed.netloc or "").lower().removeprefix("www.")

    if host in ("youtube.com", "m.youtube.com", "music.youtube.com"):
        if parsed.path == "/watch":
            vid = parse_qs(parsed.query).get("v", [None])[0]
            return vid if vid and _VIDEO_ID.match(vid) else None
        # /embed/<id>, /shorts/<id>, /v/<id>
        m = re.match(r"^/(?:embed|shorts|v)/([A-Za-z0-9_-]{11})", parsed.path)
        return m.group(1) if m else None

    if host == "youtu.be":
        vid = parsed.path.lstrip("/").split("/")[0]
        return vid if _VIDEO_ID.match(vid) else None

    return None


def parse_duration(s) -> int | None:
    """Accept '3:40' / 'H:MM:SS' / seconds-int / None; return seconds or None."""
    if s is None:
        return None
    if isinstance(s, (int, float)):
        return int(s)
    s = str(s).strip()
    if not s:
        return None
    if ":" in s:
        parts = s.split(":")
        try:
            nums = [int(p) for p in parts]
        except ValueError:
            return None
        seconds = 0
        for n in nums:
            seconds = seconds * 60 + n
        return seconds
    try:
        return int(float(s))
    except ValueError:
        return None
