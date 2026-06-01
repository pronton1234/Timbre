"""FastAPI application entrypoint."""
from fastapi import FastAPI

from app.routers import resolve, search

app = FastAPI(title="Music Discovery Backend")

app.include_router(resolve.router)
app.include_router(search.router)
