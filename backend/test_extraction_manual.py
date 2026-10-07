import asyncio
from app.processing_repository import PdfProcessingRepository
from app.ai_extraction import extract_academic_components
import uuid
import json

def test_extraction():
    repo = PdfProcessingRepository()
    paper_id = uuid.UUID("d133a5a1-c5e0-4c60-a0a1-8bcd27de883f")
    print("Fetching extraction...")
    blocks = repo.get_blocks(paper_id)
    if not blocks:
        print("No extraction blocks found!")
        return

    print(f"Running Gemini on {len(blocks)} blocks...")
    try:
        res = extract_academic_components(blocks)
        print("Success!")
    except Exception as e:
        print("FAILED:", type(e))
        import traceback
        traceback.print_exc()

test_extraction()
