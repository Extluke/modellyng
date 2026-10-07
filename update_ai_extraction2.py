import sys
import os

target = os.path.join("backend", "app", "ai_extraction.py")
with open(target, "r", encoding="utf-8") as f:
    content = f.read()

# Replace the prompt instructions to include research_areas and objects
content = content.replace(
    "1. Ekstrak 'variables', 'methods', dan 'results' utama dari teks karya ilmiah.",
    "1. Ekstrak 'variables', 'methods', 'results', 'research_areas', dan 'objects' utama dari teks karya ilmiah."
)

content = content.replace(
    'Jawab HANYA dalam format JSON dengan skema berikut:\n{\n    "variables": ["var1", "var2"],\n    "methods": ["method1"],\n    "results": ["result1"],',
    'Jawab HANYA dalam format JSON dengan skema berikut:\n{\n    "variables": ["var1", "var2"],\n    "methods": ["method1"],\n    "results": ["result1"],\n    "research_areas": ["area1"],\n    "objects": ["object1"],'
)

# Also update the parse_entities_v2
content = content.replace(
    '"methods": data.get("methods", []),\n            "results": data.get("results", [])\n        }',
    '"methods": data.get("methods", []),\n            "results": data.get("results", []),\n            "research_areas": data.get("research_areas", []),\n            "objects": data.get("objects", [])\n        }'
)

content = content.replace(
    'return {"variables": [], "methods": [], "results": []}',
    'return {"variables": [], "methods": [], "results": [], "research_areas": [], "objects": []}'
)

with open(target, "w", encoding="utf-8") as f:
    f.write(content)
print("Updated ai_extraction.py to include research_areas and objects")
