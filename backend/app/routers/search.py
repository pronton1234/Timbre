"""Search endpoint — natural-language query -> ranked tracks."""
import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import cache
from app.db import get_db
from app.models import Track
from app.resolver import track_to_out
from app.schemas import SearchRequest, SearchResponse, SearchResult
from app.search.orchestrator import run_search

router = APIRouter()


@router.post("/search", response_model=SearchResponse)
async def search(
    req: SearchRequest,
    fresh: bool = Query(False),
    db: Session = Depends(get_db),
) -> SearchResponse:
    # Cache fast-path: norm(query) -> track_id. Bypass with ?fresh=true.
    if not fresh:
        cached_id = cache.get_cached_track_id(req.query)
        if cached_id:
            track = db.scalar(select(Track).where(Track.id == uuid.UUID(cached_id)))
            if track is not None:
                return SearchResponse(results=[SearchResult(**track_to_out(track))])

    results = await run_search(db, req.query, req.top_k)
    return SearchResponse(results=[SearchResult(**r) for r in results])
