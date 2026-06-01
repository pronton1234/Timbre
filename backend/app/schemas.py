"""Pydantic request/response models for the API."""
import uuid

from pydantic import BaseModel


class ResolveRequest(BaseModel):
    artist: str
    title: str
    duration_sec: int | None = None


class TrackOut(BaseModel):
    track_id: uuid.UUID
    title: str
    artist: str
    album: str | None = None
    duration_sec: int | None = None
    video_id: str
    source_kind: str


class SearchRequest(BaseModel):
    query: str
    top_k: int = 10


class SearchResult(TrackOut):
    score: float | None = None


class SearchResponse(BaseModel):
    results: list[SearchResult]


class HealthResponse(BaseModel):
    status: str
    db: str
    redis: str
