"""Application configuration loaded from the environment (.env in dev)."""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    DATABASE_URL: str = "postgresql+psycopg://user:pass@localhost:5432/musicapp"
    REDIS_URL: str = "redis://localhost:6379/0"

    EXA_API_KEY: str = ""
    ANTHROPIC_API_KEY: str = ""

    QUERY_LLM_MODEL: str = "claude-haiku-4-5-20251001"
    EMBEDDING_MODEL: str = "BAAI/bge-small-en-v1.5"
    EMBEDDING_DIM: int = 384
    RERANKER_MODEL: str = "Xenova/ms-marco-MiniLM-L-6-v2"

    STREAM_CACHE_TTL: int = 3600

    # Search latency bounds (1-core VM; iOS client times out at 12s).
    SEARCH_MAX_VARIANTS: int = 2   # query paraphrases fanned out to adapters
    SEARCH_MAX_POOL: int = 60      # candidates embedded/ranked per search


settings = Settings()
