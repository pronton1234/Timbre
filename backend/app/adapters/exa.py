"""Exa semantic search — long-tail recall. Returns URL + title only; duration
and channel are left None for the ranker to cope with.
"""
import logging

from exa_py import Exa

from app.config import settings
from app.text_utils import parse_video_id

logger = logging.getLogger(__name__)

_exa = Exa(api_key=settings.EXA_API_KEY) if settings.EXA_API_KEY else None


def search(query: str, n: int = 15) -> list[dict]:
    """Semantic long-tail search scoped to youtube.com. Skips non-video results."""
    if _exa is None:
        logger.warning("exa: disabled (EXA_API_KEY not set) — skipping long-tail recall")
        return []
    results = _exa.search(query, include_domains=["youtube.com"], num_results=n)
    out: list[dict] = []
    for r in getattr(results, "results", []) or []:
        video_id = parse_video_id(getattr(r, "url", "") or "")
        if not video_id:
            continue
        out.append(
            {
                "video_id": video_id,
                "title": getattr(r, "title", "") or "",
                "artist": None,
                "album": None,
                "duration_sec": None,
                "channel": None,
                "source_hint": "other",
            }
        )
    return out
