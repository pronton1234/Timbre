# Music Discovery Backend

FastAPI service that, given a query, returns ranked tracks each carrying a
YouTube `videoId` the client can play (the client plays the `videoId` itself —
this service does **no** audio-stream resolution). See
`../docs/superpowers/specs/2026-04-24-sleek-music-app-ios-port-design.md`.

- **Phase 0** — resolver: `(artist, title)` → canonical `track_id` + best `videoId`.
- **Phase 1** — `POST /search`: LLM query understanding → recall fan-out
  (YT Music + yt-dlp + Exa) → ranking → text embeddings (pgvector) → top-k.

## Architecture

```
query ──▶ understanding (Anthropic)         app/search/understanding.py
      ──▶ recall fan-out (3 adapters)        app/search/recall.py + app/adapters/*
      ──▶ embed + cosine sim (fastembed)     app/search/embeddings.py
      ──▶ rank (the domain heart)            app/search/ranking.py
      ──▶ canonicalize top-k                 app/resolver.py  (tracks/track_sources)
      ──▶ cache norm(query)→track_id (Redis) app/cache.py
```

`tracks.id` is the canonical spine — playlists/caches reference it, never a raw
`video_id`. A track has one or more `track_sources`; `/tracks/{id}` re-resolves
when the best source is `is_dead`.

## Prerequisites (the VM already has these)

- Python 3.11+. Deps are ARM64-friendly — embeddings use `fastembed` (ONNX, no torch).
- Postgres 15+ with the `pgvector` extension (the first migration runs
  `CREATE EXTENSION IF NOT EXISTS vector;`).
- Redis 7+.

## Setup

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env        # fill in EXA_API_KEY + ANTHROPIC_API_KEY, point DATABASE_URL/REDIS_URL at the VM
alembic upgrade head        # creates the vector extension + tables
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## Deploy on the VM (24/7)

This Python service runs **alongside** the existing Node backend — two separate dirs,
ports, and systemd units. **Do not deploy this over the Node backend's directory.**

| Service | Dir (example)                  | Port | Unit                         | Serves |
|---------|--------------------------------|------|------------------------------|--------|
| Node    | `/home/ubuntu/spotify-free/backend` | 3000 | `spotify-free-backend.service` | playback: `/resolve` `/play` `/stream-url` `/prefetch` `/artist-top-tracks` |
| Python  | `/home/ubuntu/timbre-search`        | 8000 | `timbre-search.service`        | search: `/search` `/resolve` `/tracks/{id}` `/health` |

```bash
# 1. Put the Python service in its OWN dir, set up venv + .env + migrate (see Setup above).
# 2. Run it 24/7:
sudo cp systemd/timbre-search.service /etc/systemd/system/   # edit paths inside first
sudo systemctl daemon-reload && sudo systemctl enable --now timbre-search
# 3. Expose it to the phone over HTTPS (ATS blocks plaintext http to non-localhost):
#    paste deploy/nginx-search-api.conf into the existing TLS server block, then:
sudo nginx -t && sudo systemctl reload nginx
```

The iOS app's `SEARCH_BACKEND_URL` build setting must match the public path
(`https://free-spotify.duckdns.org/search-api`). uvicorn binds `127.0.0.1:8000`; nginx is
the only public entry. fastembed downloads its model once (~130 MB) into `~/.cache/fastembed`
on the first `/search` — that's why the unit doesn't lock down `$HOME`.

## Endpoints

| Method | Path             | Body / params                          | Returns |
|--------|------------------|----------------------------------------|---------|
| GET    | `/health`        | —                                      | `{status, db, redis}` (degraded if either down) |
| POST   | `/resolve`       | `{artist, title, duration_sec?}`       | track + best source |
| GET    | `/tracks/{id}`   | —                                      | same shape; re-resolves dead sources |
| POST   | `/search`        | `{query, top_k=10}`, `?fresh=true`     | `{results: [...]}` ranked, each with `video_id` + `score` |

`/search` checks a Redis `norm(query)→track_id` cache first; `?fresh=true` bypasses it.

## Tests

```bash
pytest -m "not network"     # pure unit: text_utils + ranking (no DB/keys needed)
pytest -m network -s        # acceptance: resolve (DB+Redis) + search eval (also Exa/Anthropic keys)
```

- `tests/test_text_utils.py`, `tests/test_ranking.py` — pure, run anywhere.
- `tests/test_resolve.py` — 20 known songs resolve, dedup via norm_key, `/tracks/{id}`, `/health`.
- `tests/test_search_eval.py` — 50-query eval; asserts specific-song top-1 norm_key match ≥ 85%, prints misses.

## Notes / seams

- Cross-encoder reranking is an optional upgrade only — see the `rerank()` seam in
  `app/search/embeddings.py`. embed-cosine + the ranking heuristics handle
  specific-song queries on their own.
- Candidate selection in the resolver lives behind `select_best()` in
  `app/resolver.py` and delegates to `score_candidate` (the Phase 1 ranker).
- Keep `yt-dlp` updated (`pip install -U yt-dlp`) — YouTube changes extraction periodically.
