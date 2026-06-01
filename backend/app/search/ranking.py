"""Ranking — the domain heart. Score every candidate; the orchestrator sorts
desc. This is where we beat YouTube's native search.

Weights are a starting point tuned against tests/test_search_eval.py.
"""
import math

from app.text_utils import _normalize

# Stylistic junk the user usually doesn't want (penalized only by presence in title).
JUNK = ["reaction", "cover", "live", "sped up", "slowed", "8d", "1 hour",
        "loop", "remix", "instrumental", "karaoke", "lyrics video"]

# Markers that a candidate is NOT the canonical original (a tribute/karaoke/lullaby
# re-recording). Scanned in the raw artist+title. Only applied when the user named
# an artist — a vague query may legitimately want one of these.
COVER_MARKERS = [
    "tribute", "made popular", "made famous", "originally performed",
    "in the style of", "various artists", "vocal version", "karaoke",
    "lullaby", "rockabye", "8 bit", "8-bit", "8bit",
]


def _tokens(s: str) -> set[str]:
    return set(_normalize(s).split())


def _identity_tokens(c: dict) -> set[str]:
    """Who the candidate is: its artist field plus channel (minus a '- Topic' suffix)."""
    artist = c.get("artist") or ""
    channel = (c.get("channel") or "")
    if channel.lower().endswith(" - topic"):
        channel = channel[: -len(" - Topic")]
    return _tokens(f"{artist} {channel}")


def score_candidate(c: dict, parsed: dict, query_sim: float) -> float:
    """
    c: candidate {video_id, title, artist?, album?, duration_sec?, channel?, view_count?, source_hint?}
    parsed: output of understand() — has artist/title/is_obscure
    query_sim: cosine similarity (0..1) of query embedding vs candidate-text embedding
    """
    score = 0.0
    title = (c.get("title") or "").lower()

    # 1. Semantic relevance (dominant signal)
    score += 3.0 * query_sim

    # 2. Channel trust
    ch = (c.get("channel") or "").lower()
    if c.get("source_hint") == "topic" or ch.endswith(" - topic") or "vevo" in ch:
        score += 1.5
    elif c.get("source_hint") == "artist_verified":
        score += 1.0

    # 3. Duration sanity — reject mixes/loops/compilations when a normal track is expected
    dur = c.get("duration_sec")
    if dur is not None and not parsed.get("is_obscure"):
        if dur > 900:            # > 15 min: almost certainly a mix/compilation/loop
            score -= 3.0
        elif 90 <= dur <= 420:   # 1.5-7 min: typical song
            score += 1.0

    # 4. Title-junk penalties (don't penalize if the user asked for these)
    score -= 0.8 * sum(1 for j in JUNK if j in title)

    # 5. View count as a weak tiebreaker only
    v = c.get("view_count")
    if v:
        score += 0.1 * math.log10(v + 10)

    # 6. Intent match. The product surfaces a SPECIFIC named song — released or
    # leaked — so the TITLE is the dominant signal. A different track by the same
    # artist (even an official "- Topic"/VEVO upload) is the wrong result and must
    # not ride artist/official signals above the named song, which often lives on a
    # fan/leak channel with no artist or trust signal at all.
    want_title = _tokens(parsed.get("title") or "")
    if want_title and want_title <= _tokens(c.get("title") or ""):
        score += 2.5

    # Artist match is a secondary refinement; demote re-recordings (tribute/karaoke).
    want_artist = _tokens(parsed.get("artist") or "")
    if want_artist:
        if want_artist <= _identity_tokens(c):
            score += 1.0
        haystack = f"{title} {(c.get('artist') or '').lower()}"
        score -= 1.5 * sum(1 for m in COVER_MARKERS if m in haystack)

    return score


def canonical_label(c: dict, parsed: dict, fallback_title: str) -> tuple[str, str]:
    """Choose the (artist, title) to store for a chosen candidate.

    When the query named an artist+title and this candidate is that artist's
    recording (artist/channel matches the named artist and the title contains the
    named title), use the LLM's clean extraction — so the same song from different
    adapters dedups onto one norm_key and the phone shows "Drake / Hotline Bling"
    rather than "Drake - Hotline Bling". Otherwise keep the candidate's own fields.
    """
    p_artist = (parsed.get("artist") or "").strip()
    p_title = (parsed.get("title") or "").strip()
    if p_artist and p_title and _tokens(p_title) <= _tokens(c.get("title") or ""):
        artist_matches = _tokens(p_artist) <= _identity_tokens(c)
        haystack = f"{(c.get('title') or '').lower()} {(c.get('artist') or '').lower()}"
        is_cover = any(m in haystack for m in COVER_MARKERS)
        # Use the named artist for the title-matched track (incl. leaks on fan
        # channels), but never relabel a genuine cover onto the real artist.
        if artist_matches or not is_cover:
            return p_artist, p_title
    artist = c.get("artist") or p_artist or ""
    title = c.get("title") or p_title or fallback_title
    return artist, title
