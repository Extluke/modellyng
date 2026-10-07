import asyncio
import httpx
from app.config import get_settings

async def main():
    settings = get_settings()
    rest_url = f"{settings.supabase_url}/rest/v1"
    headers = {
        "apikey": settings.supabase_anon_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
    }
    
    async with httpx.AsyncClient(base_url=rest_url, headers=headers) as client:
        res = await client.get("/analysis_jobs?select=*&order=created_at.desc&limit=1")
        print("Response jobs:", res.status_code)
        import json
        print(json.dumps(res.json(), indent=2))

asyncio.run(main())
