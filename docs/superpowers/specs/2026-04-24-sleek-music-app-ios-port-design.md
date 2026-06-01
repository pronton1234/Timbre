# Claude Code Dispatch — Phase 0 + Phase 1 (Backend)

**Project:** personal YouTube-backed music discovery app. This dispatch covers the backend only:
the resolver (Phase 0) and the search orchestrator (Phase 1). The iOS app and playback (YouTube
IFrame in a WebView) are separate work — the backend's contract with the client is simply: **given a
query, return ranked tracks each carrying a `videoId` the IFrame can play.** No audio-stream
resolution is needed here.

Build Phase 0 first and get its tests green before starting Phase 1. Phase 1 reuses Phase 0's
resolver.

---

## Environment

- Target host: Oracle Cloud ARM64 (aarch64) Ubuntu VM. Keep dependencies ARM-friendly (see note on
  `fastembed` vs `torch` below).
- Python 3.11+.
- Postgres 15+ with the `pgvector` extension installed (`CREATE EXTENSION vector;`).
- Redis 7+.
- Develop locally if you like, but assume final deploy is the ARM VM.

---

## Tech stack & dependencies

```
fastapi
uvicorn[standard]
sqlalchemy>=2.0
alembic
psycopg[binary]          # psycopg3, has aarch64 wheels
pgvector                 # SQLAlchemy Vector type
redis
pydantic-settings
ytmusicapi               # primary catalog search (InnerTube), no auth needed for search
yt-dlp                   # fallback search recall
exa-py                   # semantic long-tail search
anthropic                # query-understanding LLM
fastembed                # ONNX embeddings + reranker — NO torch, light on ARM (preferred)
pytest
pytest-asyncio
httpx                    # test client
```

**Embeddings/reranker library choice (important for ARM):** use `fastembed`, not
`sentence-transformers`. `fastembed` is ONNX-based and avoids pulling `torch`, which is heavy and
sometimes painful on aarch64. It provides `BAAI/bge-small-en-v1.5` (384-dim embeddings) and a
cross-encoder reranker. If you later need a model `fastembed` doesn't have, `sentence-transformers`
is the fallback, but default to `fastembed`.

---

## Project layout

```
backend/
  app/
    main.py              # FastAPI app + router registration
    config.py            # pydantic-settings (env vars)
    db.py                # engine, SessionLocal, get_db dependency
    models.py            # SQLAlchemy models
    schemas.py           # pydantic request/response models
    cache.py             # Redis helpers
    text_utils.py        # normalization helpers (norm_key, videoId parsing)
    resolver.py          # PHASE 0: canonicalize a video result into a track
    routers/
      resolve.py         # POST /resolve, GET /tracks/{id}, GET /health
      search.py          # POST /search   (Phase 1)
    search/
      orchestrator.py    # PHASE 1: full pipeline
      understanding.py   # LLM query parse + variant generation
      recall.py          # fan-out across the three adapters, dedupe
      ranking.py         # scoring function (the domain heart)
      embeddings.py      # embed + pgvector store/lookup
    adapters/
      ytmusic.py
      ytdlp.py
      exa.py
  alembic/               # migrations
  tests/
    test_text_utils.py
    test_ranking.py
    test_resolve.py
    test_search_eval.py
  .env.example
  requirements.txt
```

---

## Configuration (`.env.example`)

```
DATABASE_URL=postgresql+psycopg://user:pass@localhost:5432/musicapp
REDIS_URL=redis://localhost:6379/0
EXA_API_KEY=
ANTHROPIC_API_KEY=
QUERY_LLM_MODEL=claude-haiku-4-5-20251001
EMBEDDING_MODEL=BAAI/bge-small-en-v1.5
EMBEDDING_DIM=384
RERANKER_MODEL=Xenova/ms-marco-MiniLM-L-6-v2   # a fastembed-supported cross-encoder
STREAM_CACHE_TTL=3600
```

`config.py` loads these via `pydantic_settings.BaseSettings`.

---

## Data model (`models.py`)

Use SQLAlchemy 2.0 declarative. The initial Alembic migration must `CREATE EXTENSION IF NOT EXISTS
vector;` before creating tables.

```python
# tracks — the canonical spine. Everything else references tracks.id.
tracks:
    id            UUID  pk  default uuid4
    title         Text  not null
    artist        Text  not null
    album         Text  null
    duration_sec  Integer null
    isrc          Text  null
    norm_key      Text  not null  index   # normalized "artist|title" for dedup (see text_utils)
    created_at    timestamptz default now()

# track_sources — a track can map to several YouTube videos over its lifetime.
track_sources:
    id            UUID  pk  default uuid4
    track_id      UUID  fk -> tracks.id  (index)
    video_id      Text  not null  unique
    source_kind   Text  not null   # 'topic' | 'artist_verified' | 'user_upload' | 'other'
    confidence    Float not null   # ranker score when this source was chosen
    last_verified timestamptz default now()
    is_dead       Boolean default false

# track_embeddings — TEXT embeddings only, for semantic search + the growing private index.
# NOTE: audio (Marengo) embeddings are a DIFFERENT vector space/dimension — when added later they
# get their OWN table, not this column. Do not mix them here.
track_embeddings:
    track_id      UUID  pk  fk -> tracks.id
    embedding     Vector(EMBEDDING_DIM)
    created_at    timestamptz default now()
```

(The `lyrics`, `playlists`, and `playlist_items` tables come in their own later phases — do not
create them now.)

---

## Shared helpers (`text_utils.py`)

```python
def norm_key(artist: str, title: str) -> str:
    """Normalized dedup key. Lowercase, strip feat./brackets/punct, collapse spaces.
    e.g. ('BNYX', 'Fallen (feat. X)') -> 'bnyx|fallen'"""

def parse_video_id(url: str) -> str | None:
    """Extract the YouTube videoId from a watch URL or youtu.be URL. Return None if not a YT video."""

def parse_duration(s) -> int | None:
    """Accept '3:40' or seconds-int or None; return seconds or None."""
```

Write `test_text_utils.py` covering: feat./bracket stripping, `watch?v=`, `youtu.be/`, malformed
URLs, both duration formats.

---

# PHASE 0 — Backend skeleton + resolver

**Goal:** a running FastAPI service with the data layer migrated and a resolver that turns a
(artist, title) into a canonical `track_id` carrying a playable `videoId`.

## Adapter: `adapters/ytmusic.py`

```python
from ytmusicapi import YTMusic

# Unauthenticated client is sufficient for search (no oauth.json needed).
# Instantiate once at module load and reuse.
_yt = YTMusic()

def search_songs(query: str, limit: int = 10) -> list[dict]:
    """Return normalized candidate dicts:
       {video_id, title, artist, album, duration_sec, channel, source_hint}
    Use _yt.search(query, filter='songs', limit=limit).
    Each raw result has: videoId, title, artists[].name, album.name, duration_seconds.
    'songs' results are auto-generated '- Topic' uploads -> source_hint='topic'."""
```

## Resolver: `resolver.py`

```python
def resolve_track(db, artist: str, title: str, duration_sec: int | None) -> Track:
    """
    1. Compute norm_key(artist, title).
    2. Look up an existing track by norm_key (and duration within ±3s if both known).
       If found, return it.
    3. Otherwise call ytmusic.search_songs("{artist} {title}").
       Pick the best candidate using ranking.score_candidates (Phase 1's function — for Phase 0 a
       simpler best-match by norm_key + duration closeness is acceptable; wire in the full ranker
       once Phase 1 exists).
    4. Create a Track + a TrackSource (video_id, source_kind, confidence). Commit. Return.
    """
```

> Phase 0 can ship with a simple "closest title+duration match" selection and be upgraded to call
> the Phase 1 ranker later. Keep the selection logic behind one function so the swap is a one-liner.

## Endpoints: `routers/resolve.py`

- `GET /health` → `{status:"ok"}`. Also ping DB and Redis; report degraded if either is down.
- `POST /resolve`
  - Request: `{ "artist": str, "title": str, "duration_sec": int | null }`
  - Response: `{ "track_id": uuid, "title", "artist", "album", "duration_sec",
                 "video_id", "source_kind" }`
  - Calls `resolve_track`, returns the track plus its current best (non-dead) source.
- `GET /tracks/{track_id}`
  - Response: same shape as `/resolve`. This is what the client calls to get the `videoId` to load
    in the IFrame. If the chosen source `is_dead`, re-resolve (re-run search) and update.

## Phase 0 acceptance tests (`test_resolve.py`)

- Resolve 20 known songs (hard-code a small list of artist/title pairs). Assert each returns a
  non-empty `video_id` and a `track_id`.
- Resolving the same song twice returns the **same** `track_id` (dedup via norm_key works).
- `GET /tracks/{id}` returns the stored video_id.
- `GET /health` returns ok with DB + Redis up.

(These tests hit the live ytmusicapi, so they need network. Mark them with a `@pytest.mark.network`
marker so they can be skipped in CI but run on the VM.)

---

# PHASE 1 — Search orchestrator

**Goal:** `POST /search` that takes a natural-language query and returns ranked tracks, each with a
`video_id`. Most queries are specific songs; the pipeline must nail those and degrade gracefully on
obscure ones.

## Step 1 — Query understanding: `search/understanding.py`

```python
import anthropic, json
client = anthropic.Anthropic()

SYSTEM = """You parse a music search query. Return ONLY minified JSON, no prose, no markdown:
{"artist": str|null, "title": str|null, "is_obscure": bool, "variants": [str, ...]}
- artist/title: your best extraction, or null if unclear.
- is_obscure: true if this looks like a leak/snippet/unreleased track rather than a catalog song.
- variants: 2-4 alternative search phrasings (include the raw query). Keep them short."""

def understand(query: str) -> dict:
    msg = client.messages.create(
        model=settings.QUERY_LLM_MODEL, max_tokens=300,
        system=SYSTEM, messages=[{"role":"user","content":query}],
    )
    text = "".join(b.text for b in msg.content if b.type == "text")
    return json.loads(text.strip())   # wrap in try/except; on failure fall back to {"variants":[query]}
```

## Step 2 — Recall fan-out: `adapters/ytdlp.py`, `adapters/exa.py`, `search/recall.py`

`adapters/ytdlp.py`:
```python
import yt_dlp
_OPTS = {"quiet": True, "skip_download": True, "extract_flat": True, "noplaylist": True}

def search(query: str, n: int = 10) -> list[dict]:
    """ytsearch fallback. Return normalized candidate dicts (same shape as ytmusic adapter).
    Use ydl.extract_info(f'ytsearch{n}:{query}', download=False)['entries'].
    Each entry: id (videoId), title, duration (sec, may be None in flat mode), channel, view_count.
    source_hint: 'topic' if channel endswith ' - Topic', else 'other'."""
```

`adapters/exa.py`:
```python
from exa_py import Exa
_exa = Exa(api_key=settings.EXA_API_KEY)

def search(query: str, n: int = 10) -> list[dict]:
    """Semantic long-tail. _exa.search(query, include_domains=['youtube.com'], num_results=n).
    For each result: parse_video_id(result.url); skip if None. title=result.title.
    Exa won't give duration/channel reliably — leave those None; ranking handles missing fields.
    source_hint='other'."""
```

`search/recall.py`:
```python
async def fan_out(variants: list[str]) -> list[dict]:
    """Run ytmusic + ytdlp + exa across all variants concurrently (asyncio.gather; wrap the
    sync adapters with asyncio.to_thread). Merge all candidates, dedupe by video_id (keep the
    richest record — prefer one that has duration/channel/source_hint set). Return the pool
    (target 50-100 candidates)."""
```

## Step 3 — Ranking: `search/ranking.py` (the domain heart — get this right)

This is where you beat YouTube's native search. Score every candidate, return sorted desc.

```python
import math

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
    JUNK = ["reaction", "cover", "live", "sped up", "slowed", "8d", "1 hour",
            "loop", "remix", "instrumental", "karaoke", "lyrics video"]
    score -= 0.8 * sum(1 for j in JUNK if j in title)

    # 5. View count as a weak tiebreaker only
    v = c.get("view_count")
    if v:
        score += 0.1 * math.log10(v + 10)

    return score
```

Notes:
- `query_sim` comes from Step 4. For candidates missing structured fields (Exa results), the
  semantic term still works off title text, and the heuristics just don't fire — that's intended.
- These weights are a starting point. The eval test below is how you tune them.

## Step 4 — Embeddings + pgvector cache: `search/embeddings.py`

```python
from fastembed import TextEmbedding
_embedder = TextEmbedding(model_name=settings.EMBEDDING_MODEL)

def embed(texts: list[str]) -> list[list[float]]:
    return [list(v) for v in _embedder.embed(texts)]

def candidate_text(c: dict) -> str:
    # what we embed for similarity
    return f"{c.get('artist') or ''} {c.get('title') or ''}".strip()

def store_track_embedding(db, track_id, vector): ...   # upsert into track_embeddings
def cosine(a, b) -> float: ...                          # or use numpy
```

Cross-encoder reranking is an **optional upgrade**, not required for v1: embed-cosine + the
heuristics above handle specific-song queries well. If you add it, use `fastembed`'s
`TextCrossEncoder` on the top ~20 candidates and feed its normalized score in place of `query_sim`.
Leave a clean seam for it but don't block Phase 1 on it.

## Step 5 — Orchestrator: `search/orchestrator.py`

```python
async def run_search(db, query: str, top_k: int = 10) -> list[dict]:
    parsed = understand(query)
    variants = parsed.get("variants") or [query]
    pool = await fan_out(variants)                      # 50-100 candidates

    q_vec = embed([query])[0]
    cand_vecs = embed([candidate_text(c) for c in pool])
    for c, cv in zip(pool, cand_vecs):
        c["_sim"] = cosine(q_vec, cv)

    ranked = sorted(pool, key=lambda c: score_candidate(c, parsed, c["_sim"]), reverse=True)

    # Canonicalize ONLY the top_k (don't write DB rows for the whole pool).
    results = []
    for c in ranked[:top_k]:
        track = resolve_track(db, c.get("artist") or parsed.get("artist") or "",
                              c.get("title") or query, c.get("duration_sec"))
        store_track_embedding(db, track.id, embed([candidate_text(c)])[0])
        results.append({...track + video_id...})

    cache_query(query, results[0]["track_id"])          # Redis: norm(query) -> track_id
    return results
```

## Endpoint: `routers/search.py`

- `POST /search`
  - Request: `{ "query": str, "top_k": int = 10 }`
  - Before running the pipeline, check the Redis `norm(query) -> track_id` cache; on hit, return that
    track immediately (still allow a `?fresh=true` to bypass).
  - Response: `{ "results": [ {track_id, title, artist, album, duration_sec, video_id, source_kind,
                  score}, ... ] }`

## Phase 1 acceptance tests

`test_ranking.py` (pure unit, no network — most important for correctness):
- A "1 hour loop" candidate (dur=3600) ranks **below** the real 3-minute track for the same query.
- A "- Topic" channel candidate ranks above an identical-title random-user upload.
- A "reaction"/"cover" title ranks below the clean title.
- Missing-field (Exa-style) candidates still get a sane score from `_sim` alone.

`test_search_eval.py` (`@pytest.mark.network`):
- A 50-query eval set: 40 specific songs (artist + title), 10 vaguer/obscure. Each row:
  `(query, expected_norm_key)`. Assert top-1 `norm_key` match rate ≥ a threshold you set (start at
  0.85 for the specific-song subset). Print the misses so you can tune ranking weights.

---

## What NOT to build in this dispatch

- No playback / stream-URL resolution (IFrame plays the `video_id` client-side).
- No lyrics, playlists, or voice search (later phases; don't create those tables).
- No cross-encoder requirement (optional seam only).
- No auth/users (single-user personal app).
- No audio embeddings (text only; audio gets its own table later).

## Domain gotchas to remember

- `ytmusicapi`: unauthenticated `YTMusic()` is fine for `search`; instantiate once and reuse.
  Behaving like a human matters — don't hammer it; the orchestrator's fan-out is a few calls, fine.
- `yt-dlp`: keep it updated (`pip install -U yt-dlp`) — YouTube changes extraction periodically.
  In `extract_flat` mode `duration` may be `None`; handle missing fields everywhere.
- `Exa`: `include_domains=["youtube.com"]` scopes it; results give URL + title but not reliable
  duration/channel — parse the `video_id` from the URL and let ranking cope with the missing fields.
- Dedupe the candidate pool by `video_id` before ranking, and canonicalize only the returned top_k
  to avoid writing junk tracks for every fan-out result.
- The canonical `track_id` is the spine: never let a `video_id` become the identity a playlist or
  cache points at.