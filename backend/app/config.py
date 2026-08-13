from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "Modellyng API"
    environment: str = "development"
    api_prefix: str = "/api/v1"
    allowed_origins: list[str] = ["http://localhost:8081"]
    database_url: str = "postgresql://modellyng:modellyng@localhost:5432/modellyng"
    redis_url: str = "redis://localhost:6379/0"
    object_storage_bucket: str = "private-papers"
    enqueue_jobs: bool = False

    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="MODELLYNG_",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
