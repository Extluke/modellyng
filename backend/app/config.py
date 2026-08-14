from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


ENV_FILE = Path(__file__).resolve().parents[1] / ".env"


class Settings(BaseSettings):
    app_name: str = "Modellyng API"
    environment: str = "development"
    api_prefix: str = "/api/v1"
    allowed_origins: list[str] = [
        "http://localhost:8080",
        "http://127.0.0.1:8080",
        "http://localhost:8081",
        "http://127.0.0.1:8081",
        "http://localhost:8082",
        "http://127.0.0.1:8082",
    ]

    redis_url: str = "redis://localhost:6380/0"
    enqueue_jobs: bool = True

    supabase_url: str = "http://127.0.0.1:54321"
    supabase_anon_key: str = ""
    supabase_service_role_key: str = ""
    object_storage_bucket: str = "private-papers"
    gemini_api_key: str = Field(default="", validation_alias="GEMINI_API_KEY")
    gemini_model: str = "gemini-flash-latest"
    gemini_max_input_chars: int = 400_000

    model_config = SettingsConfigDict(
        env_file=ENV_FILE,
        env_prefix="MODELLYNG_",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
