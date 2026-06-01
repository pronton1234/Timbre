"""SQLAlchemy 2.0 declarative models.

The `tracks` table is the canonical spine — playlists and caches must point at
`tracks.id`, never at a raw `video_id`. A track maps to one or more
`track_sources` (YouTube videos) over its lifetime. `track_embeddings` holds
TEXT embeddings only; audio (Marengo) embeddings get their own table later.
"""
import uuid
from datetime import datetime

from pgvector.sqlalchemy import Vector
from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.config import settings
from app.db import Base


class Track(Base):
    __tablename__ = "tracks"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    artist: Mapped[str] = mapped_column(Text, nullable=False)
    album: Mapped[str | None] = mapped_column(Text, nullable=True)
    duration_sec: Mapped[int | None] = mapped_column(Integer, nullable=True)
    isrc: Mapped[str | None] = mapped_column(Text, nullable=True)
    norm_key: Mapped[str] = mapped_column(Text, nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    sources: Mapped[list["TrackSource"]] = relationship(
        back_populates="track", cascade="all, delete-orphan"
    )


class TrackSource(Base):
    __tablename__ = "track_sources"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    track_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tracks.id"), nullable=False, index=True
    )
    video_id: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    source_kind: Mapped[str] = mapped_column(Text, nullable=False)  # topic|artist_verified|user_upload|other
    confidence: Mapped[float] = mapped_column(Float, nullable=False)
    last_verified: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    is_dead: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    track: Mapped["Track"] = relationship(back_populates="sources")


class TrackEmbedding(Base):
    __tablename__ = "track_embeddings"

    track_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tracks.id"), primary_key=True
    )
    embedding: Mapped[list[float]] = mapped_column(Vector(settings.EMBEDDING_DIM))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
