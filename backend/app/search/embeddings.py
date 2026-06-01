"""Text embeddings (fastembed/ONNX — no torch) + pgvector storage helpers.

The embedder is lazy-loaded so importing this module (e.g. in pure unit tests)
doesn't download the ONNX model.

Cross-encoder reranking is an OPTIONAL upgrade, not built here: embed-cosine +
the ranking heuristics handle specific-song queries well. To add it later, run
fastembed's `TextCrossEncoder` on the top ~20 candidates and feed its normalized
score into `score_candidate` in place of `query_sim` — see `rerank()` seam below.
"""
import math

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import settings
from app.models import TrackEmbedding

_embedder = None


def _get_embedder():
    global _embedder
    if _embedder is None:
        from fastembed import TextEmbedding

        _embedder = TextEmbedding(model_name=settings.EMBEDDING_MODEL)
    return _embedder


def embed(texts: list[str]) -> list[list[float]]:
    return [list(v) for v in _get_embedder().embed(texts)]


def candidate_text(c: dict) -> str:
    """What we embed for similarity. Include artist + title + album when present;
    title-only candidates (Exa/yt-dlp) still embed their title gracefully."""
    parts = [c.get("artist"), c.get("title"), c.get("album")]
    return " ".join(p for p in parts if p).strip()


def cosine(a, b) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)


def store_track_embedding(db: Session, track_id, vector) -> None:
    """Upsert a track's text embedding."""
    row = db.scalar(select(TrackEmbedding).where(TrackEmbedding.track_id == track_id))
    if row is None:
        db.add(TrackEmbedding(track_id=track_id, embedding=list(vector)))
    else:
        row.embedding = list(vector)
    db.commit()


def rerank(query: str, candidates: list[dict]) -> list[float] | None:
    """Optional cross-encoder seam. Returns None until a reranker is wired in."""
    return None
