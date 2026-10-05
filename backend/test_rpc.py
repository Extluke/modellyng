import asyncio
from httpx import AsyncClient
import os
from dotenv import load_dotenv

async def main():
    load_dotenv('d:/Koding/modeling by github/backend/.env')
    supabase_url = os.environ.get('MODELLYNG_SUPABASE_URL')
    supabase_key = os.environ.get('MODELLYNG_SUPABASE_SERVICE_ROLE_KEY')
    headers = {'apikey': supabase_key, 'Authorization': f'Bearer {supabase_key}'}
    async with AsyncClient() as client:
        # Get project id
        res = await client.get(f'{supabase_url}/rest/v1/projects?select=id', headers=headers)
        if not res.json(): return
        project_id = res.json()[0]['id']
        
        # Test get_project_comparisons directly
        res2 = await client.post(
            f'{supabase_url}/rest/v1/rpc/get_project_comparisons',
            json={'p_project_id': project_id},
            headers=headers
        )
        print('Comparisons result:', res2.text)
        
        # Manually invoke comparison_paper_source
        res3 = await client.get(f'{supabase_url}/rest/v1/papers?select=id,title', headers=headers)
        for p in res3.json():
            pid = p['id']
            res4 = await client.post(f'{supabase_url}/rest/v1/rpc/comparison_paper_source', json={'p_paper_id': pid}, headers=headers)
            print(f"Source for {p['title']}: {res4.text[:100]}")
            
asyncio.run(main())
