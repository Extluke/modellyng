import asyncio
import os
import json
from dotenv import load_dotenv
from uuid import uuid4

load_dotenv()
from app.ai_extraction import extract_academic_components
from app.source_location import partition_blocks_by_route

import httpx

def run_extraction():
    supabase_url = os.environ["MODELLYNG_SUPABASE_URL"]
    supabase_key = os.environ["MODELLYNG_SUPABASE_SERVICE_ROLE_KEY"]

    headers = {
        "apikey": supabase_key,
        "Authorization": f"Bearer {supabase_key}",
        "Content-Type": "application/json"
    }

    client = httpx.Client(base_url=f"{supabase_url}/rest/v1", headers=headers)

    r = client.get("/papers", params={"title": "ilike.*Resource block allocation*", "limit": "1"})
    if not r.json():
        print("Paper not found")
        return
    paper_id = r.json()[0]['id']

    blocks = client.get('/paper_blocks', params={'paper_id': f'eq.{paper_id}', 'order': 'block_index.asc'}).json()
    
    print(f"Loaded {len(blocks)} blocks for paper {paper_id}")
    
    routed_blocks = partition_blocks_by_route(blocks)
    
    for route in ["intro", "method", "discussion"]:
        print(f"\n--- Extracting route: {route} ---")
        route_blocks = routed_blocks.get(route, blocks)
        if not route_blocks:
            route_blocks = blocks
            
        print(f"Using {len(route_blocks)} blocks for {route}")
        
        try:
            result = extract_academic_components(route_blocks, route=route)
            for c in result.components:
                print(f"[{c.parameter.value}]")
                print(f"Value: {c.value}")
                if c.evidence:
                    print(f"Quote: {c.evidence[0].quote[:100]}...")
                else:
                    print(f"Quote: None")
        except Exception as e:
            print(f"Extraction failed: {e}")

if __name__ == "__main__":
    run_extraction()
