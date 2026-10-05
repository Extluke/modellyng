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
paper = r.json()[0]
paper_id = paper['id']

print("PAPER TITLE:", paper['title'])

r = client.get("/extracted_components", params={"paper_id": f"eq.{paper_id}"})
components = r.json()
print("Components Dump:")
print(json.dumps(components, indent=2))

r = client.get("/evidence_spans", params={"paper_id": f"eq.{paper_id}"})
spans = r.json()
print("Evidence Spans:")
print(json.dumps(spans, indent=2))
