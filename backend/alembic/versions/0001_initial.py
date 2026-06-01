"""initial schema: pgvector extension + tracks, track_sources, track_embeddings

Revision ID: 0001_initial
Revises:
Create Date: 2026-05-31
"""
from alembic import op
import sqlalchemy as sa
from pgvector.sqlalchemy import Vector
from sqlalchemy.dialects.postgresql import UUID

from app.config import settings

revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # The vector type must exist before any table references it.
    op.execute("CREATE EXTENSION IF NOT EXISTS vector;")

    op.create_table(
        "tracks",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("artist", sa.Text(), nullable=False),
        sa.Column("album", sa.Text(), nullable=True),
        sa.Column("duration_sec", sa.Integer(), nullable=True),
        sa.Column("isrc", sa.Text(), nullable=True),
        sa.Column("norm_key", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_tracks_norm_key", "tracks", ["norm_key"])

    op.create_table(
        "track_sources",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("track_id", UUID(as_uuid=True), sa.ForeignKey("tracks.id"), nullable=False),
        sa.Column("video_id", sa.Text(), nullable=False, unique=True),
        sa.Column("source_kind", sa.Text(), nullable=False),
        sa.Column("confidence", sa.Float(), nullable=False),
        sa.Column("last_verified", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("is_dead", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.create_index("ix_track_sources_track_id", "track_sources", ["track_id"])

    op.create_table(
        "track_embeddings",
        sa.Column("track_id", UUID(as_uuid=True), sa.ForeignKey("tracks.id"), primary_key=True),
        sa.Column("embedding", Vector(settings.EMBEDDING_DIM)),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )


def downgrade() -> None:
    op.drop_table("track_embeddings")
    op.drop_index("ix_track_sources_track_id", table_name="track_sources")
    op.drop_table("track_sources")
    op.drop_index("ix_tracks_norm_key", table_name="tracks")
    op.drop_table("tracks")
