"""LLM query understanding — parse a raw search query into structured intent
plus alternate phrasings to widen recall.
"""
import json
import re

import anthropic

from app import cache
from app.config import settings

_client = anthropic.Anthropic(api_key=settings.ANTHROPIC_API_KEY) if settings.ANTHROPIC_API_KEY else anthropic.Anthropic()

SYSTEM = """You parse a music search query. Return ONLY minified JSON, no prose, no markdown:
{"artist": str|null, "title": str|null, "is_obscure": bool, "variants": [str, ...]}
- artist/title: your best extraction, or null if unclear.
- is_obscure: true if this looks like a leak/snippet/unreleased track rather than a catalog song.
- variants: 2-4 alternative search phrasings (include the raw query). Keep them short."""

# Models often wrap JSON in ```json ... ``` despite instructions; strip the fence.
_FENCE = re.compile(r"^\s*```(?:json)?\s*(.*?)\s*```\s*$", re.DOTALL | re.IGNORECASE)


def parse_understanding(text: str) -> dict:
    """Parse the model's reply into the understanding dict. Tolerates a markdown
    code fence around the JSON. Raises on genuinely non-JSON output."""
    text = (text or "").strip()
    m = _FENCE.match(text)
    if m:
        text = m.group(1).strip()
    parsed = json.loads(text)
    if not parsed.get("variants"):
        parsed["variants"] = []
    return parsed


def understand(query: str) -> dict:
    """Parse a query via the LLM. Cached per-query for determinism; on failure,
    degrade to {"variants": [query]} (the degraded result is never cached)."""
    cached = cache.get_cached_understanding(query)
    if cached is not None:
        variants = cached.get("variants") or []
        if query not in variants:
            cached["variants"] = [query] + variants
        return cached
    try:
        # Prefill the assistant turn with "{" so the model emits pure JSON (no
        # markdown fence, no prose) — the most reliable shape to parse.
        msg = _client.with_options(timeout=4.0).messages.create(
            model=settings.QUERY_LLM_MODEL,
            max_tokens=300,
            system=SYSTEM,
            messages=[
                {"role": "user", "content": query},
                {"role": "assistant", "content": "{"},
            ],
        )
        text = "{" + "".join(b.text for b in msg.content if b.type == "text")
        parsed = parse_understanding(text)
        # Always include the raw query so recall never narrows below the literal search.
        if query not in parsed["variants"]:
            parsed["variants"] = [query] + parsed["variants"]
        cache.cache_understanding(query, parsed)
        return parsed
    except Exception:
        return {"artist": None, "title": None, "is_obscure": False, "variants": [query]}
