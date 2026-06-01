"""Resolve + track-fetch + health endpoints."""
import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, text
from sqlalchemy.orm import Session

from app import cache
from app.db import get_db
from app.models import Track
from app.resolver import best_source, resolve_track, track_to_out
from app.schemas import HealthResponse, ResolveRequest, TrackOut

router = APIRouter()


@router.get("/health", response_model=HealthResponse)
def health(db: Session = Depends(get_db)) -> HealthResponse:
    db_ok = True
    try:
        db.execute(text("SELECT 1"))
    except Exception:
        db_ok = False
    redis_ok = cache.ping()
    status = "ok" if (db_ok and redis_ok) else "degraded"
    return HealthResponse(
        status=status,
        db="up" if db_ok else "down",
        redis="up" if redis_ok else "down",
    )


@router.post("/resolve", response_model=TrackOut)
def resolve(req: ResolveRequest, db: Session = Depends(get_db)) -> TrackOut:
    try:
        track = resolve_track(db, req.artist, req.title, req.duration_sec)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    return TrackOut(**track_to_out(track))


@router.get("/tracks/{track_id}", response_model=TrackOut)
def get_track(track_id: uuid.UUID, db: Session = Depends(get_db)) -> TrackOut:
    track = db.scalar(select(Track).where(Track.id == track_id))
    if track is None:
        raise HTTPException(status_code=404, detail="track not found")

    # If the current best source is dead, re-resolve (re-run search) and update.
    if best_source(track) is None:
        try:
            track = resolve_track(db, track.artist, track.title, track.duration_sec)
        except ValueError:
            raise HTTPException(status_code=502, detail="re-resolution failed")
    return TrackOut(**track_to_out(track))
