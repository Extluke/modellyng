import asyncio
from app.dependencies import get_db_pool
from app.repository import Repository

async def fetch():
    pool = await get_db_pool()
    repo = Repository(pool)
    paper = await pool.fetchrow("SELECT id, title FROM papers WHERE title ILIKE '%Resource block allocation%'")
    if not paper:
        print('Paper not found')
        return
    print('Paper ID:', paper['id'])
    
    components = await pool.fetch("SELECT parameter, value, evidence_quote FROM extracted_components WHERE paper_id = $1", paper['id'])
    for c in components:
        print(f"\n[{c['parameter'].upper()}]")
        print(f"Value: {c['value']}")
        print(f"Quote: {c['evidence_quote']}")
        
    gaps = await pool.fetch("SELECT gap_statement, gap_type, evidence_quote FROM research_gaps WHERE paper_id = $1", paper['id'])
    for g in gaps:
        print(f"\n[GAP - {g['gap_type']}]")
        print(f"Statement: {g['gap_statement']}")
        print(f"Quote: {g['evidence_quote']}")

asyncio.run(fetch())
