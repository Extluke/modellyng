import sys
import logging
from uuid import uuid4

# Set up logging to stdout
logging.basicConfig(level=logging.DEBUG, stream=sys.stdout)

from app.ai_extraction import extract_academic_components

blocks = [
    {
        "id": str(uuid4()),
        "block_index": 0,
        "page_number": 1,
        "content": "This paper investigates the research problem of AI hallucination. The research objective is to mitigate it."
    }
]

try:
    print("Calling Gemini...")
    result = extract_academic_components(blocks, route="intro")
    print("SUCCESS!")
    print(result)
except Exception as e:
    import traceback
    print("FAILED!")
    traceback.print_exc()
    # also print the __cause__ if any
    if e.__cause__:
        print("CAUSE:")
        traceback.print_exception(type(e.__cause__), e.__cause__, e.__cause__.__traceback__)
