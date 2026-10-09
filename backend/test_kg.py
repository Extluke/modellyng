import asyncio
import os
import uuid
import httpx
from app.config import get_settings
from app.auth import AuthenticatedUser
from app.repository import project_repository

async def main():
    settings = get_settings()
    headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}"
    }
    with httpx.Client(timeout=10.0) as client:
        res = client.get(
            f"{settings.supabase_url}/rest/v1/projects",
            headers=headers
        )
        data = res.json()
        if not data:
            print("No projects found.")
            return
        
        project_id = uuid.UUID(data[0]['id'])
        print(f"Testing for project {project_id}")

        user = AuthenticatedUser(
            id=data[0]['owner_id'], 
            email="test@example.com", 
            role="authenticated",
            access_token=settings.supabase_service_role_key
        )
        
        try:
            kg = await project_repository.get_knowledge_graph(user, project_id)
            print("Success! Nodes:", len(kg.nodes), "Edges:", len(kg.edges))
        except Exception as e:
            import traceback
            traceback.print_exc()

asyncio.run(main())
