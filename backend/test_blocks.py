import httpx
import os
from dotenv import load_dotenv
import json

load_dotenv()
supabase_url = os.environ["MODELLYNG_SUPABASE_URL"]
supabase_key = os.environ["MODELLYNG_SUPABASE_SERVICE_ROLE_KEY"]

headers = {
    "apikey": supabase_key,
    "Authorization": f"Bearer {supabase_key}",
    "Content-Type": "application/json"
}

client = httpx.Client(base_url=f"{supabase_url}/rest/v1", headers=headers)

r = client.get("/papers", params={"order": "created_at.desc", "limit": "1"})
paper_id = r.json()[0]['id']

blocks = client.get('/paper_blocks', params={'paper_id': f'eq.{paper_id}', 'order': 'block_index.asc', 'limit': 10}).json()
for idx, b in enumerate(blocks):
    print(f"--- Block {idx} ---")
    print(b['content'])
