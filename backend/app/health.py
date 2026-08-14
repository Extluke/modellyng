import asyncio

import httpx
from redis.asyncio import Redis

from .config import get_settings
from .schemas import DependencyHealthRead, DependencyStatus


async def check_redis() -> DependencyStatus:
    settings = get_settings()
    client = Redis.from_url(settings.redis_url, decode_responses=True)
    try:
        is_available = await client.ping()
        return DependencyStatus(
            status="ok" if is_available else "error",
            detail="Redis responded to PING" if is_available else "Redis did not respond",
        )
    except Exception as exc:
        return DependencyStatus(status="error", detail=type(exc).__name__)
    finally:
        await client.aclose()


async def check_supabase() -> DependencyStatus:
    settings = get_settings()
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            response = await client.get(
                f"{settings.supabase_url}/auth/v1/health",
                headers={"apikey": settings.supabase_anon_key},
            )
        response.raise_for_status()
        return DependencyStatus(status="ok", detail="Supabase Auth is healthy")
    except Exception as exc:
        return DependencyStatus(status="error", detail=type(exc).__name__)


async def dependency_health() -> DependencyHealthRead:
    redis_status, supabase_status = await asyncio.gather(
        check_redis(),
        check_supabase(),
    )
    overall_status = (
        "ok"
        if redis_status.status == "ok" and supabase_status.status == "ok"
        else "degraded"
    )
    return DependencyHealthRead(
        status=overall_status,
        redis=redis_status,
        supabase=supabase_status,
    )
