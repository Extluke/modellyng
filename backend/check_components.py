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
        res = await client.get(f'{supabase_url}/rest/v1/projects?select=id', headers=headers)
        if not res.json(): return
        project_id = res.json()[0]['id']
        
        res2 = await client.get(
            f'{supabase_url}/rest/v1/papers',
            params={
                'select': 'id,title,original_filename,extracted_components(id,parameter,status,ai_value,final_value,is_active,evidence_spans(id,quote,page_number))',
                'project_id': f'eq.{project_id}',
                'status': 'eq.ready',
                'extracted_components.is_active': 'eq.true'
            },
            headers=headers
        )
        papers = res2.json()
        print('Total papers fetched:', len(papers))
        for p in papers:
            comps = p.get('extracted_components', [])
            has_gap = any(c['parameter'] in ['limitations', 'future_work'] for c in comps)
            print(f"Paper {p['title']} has {len(comps)} components, has_gap={has_gap}")
        
asyncio.run(main())
