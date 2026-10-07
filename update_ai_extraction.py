import sys
import os

target = os.path.join("backend", "app", "ai_extraction.py")
with open(target, "r", encoding="utf-8") as f:
    content = f.read()

# We want to replace everything from `class EntityExtractionV2(BaseModel):` to the end of the file.
start_idx = content.find("class EntityExtractionV2(BaseModel):")
if start_idx == -1:
    print("Cannot find EntityExtractionV2")
    sys.exit(1)

new_code = '''class EntityExtractionV2(BaseModel):
    variables: list[str] = Field(default_factory=list)
    methods: list[str] = Field(default_factory=list)
    results: list[str] = Field(default_factory=list)

def extract_entities_and_gaps_v2(paper_text: str) -> str:
    """Extract variables, methods, results, and research gaps in a single prompt with retry loop."""
    settings = get_settings()
    if not settings.gemini_api_key:
        raise GeminiExtractionError("Gemini API key belum dikonfigurasi")
    
    prompt = f"""Anda adalah asisten AI akademik yang ahli dalam mengekstrak pengetahuan dari karya ilmiah.

TUGAS ANDA:
1. Ekstrak 'variables', 'methods', dan 'results' utama dari teks karya ilmiah.
2. Temukan SEMUA research gap yang disebutkan secara eksplisit oleh penulis.

Untuk setiap gap, berikan:
- "statement": Deskripsi gap dalam bahasa Indonesia.
- "gap_type": JENIS GAP WAJIB SATU DARI INI (DILARANG MENGGUNAKAN NILAI LAIN): unexplored_concept, missing_relation, methodological, population_gap, dataset_gap, empirical_gap.
- "confidence_score": 0-100 (angka).
- "evidence": Objek berisi {{ "section": "nama bab", "quote": "kutipan asli verbatim", "page_number": angka_halaman }}.

Jawab HANYA dalam format JSON dengan skema berikut:
{{
    "variables": ["var1", "var2"],
    "methods": ["method1"],
    "results": ["result1"],
    "gaps": [
        {{
            "statement": "Penelitian ini belum mengukur...",
            "gap_type": "empirical_gap",
            "confidence_score": 90,
            "evidence": {{
                "section": "Conclusion",
                "quote": "Future studies should investigate...",
                "page_number": 12
            }}
        }}
    ]
}}
Jangan tambahkan teks apapun selain JSON.

Teks:
{paper_text[:settings.gemini_max_input_chars]}
"""
    client = genai.Client(api_key=settings.gemini_api_key, http_options=types.HttpOptions(timeout=120_000))
    models = [settings.gemini_model]
    if settings.gemini_fallback_model:
        models.append(settings.gemini_fallback_model)
        
    last_exc = None
    
    # Forensic 1: Retry Loop Implementation
    for attempt in range(3):
        for model in models:
            try:
                response = client.models.generate_content(
                    model=model,
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        response_mime_type="application/json",
                    ),
                )
                return response.text or "{}"
            except Exception as exc:
                last_exc = exc
                import time
                time.sleep(2 ** attempt)  # Exponential backoff
                
    raise GeminiExtractionError(f"Gagal ekstrak Entities & Gaps V2 setelah 3 percobaan: {last_exc}")

def parse_entities_v2(raw: str) -> dict:
    import json
    if not raw:
        return {"variables": [], "methods": [], "results": []}
    raw = raw.strip()
    if raw.startswith("```json"):
        raw = raw[7:]
    elif raw.startswith("```"):
        raw = raw[3:]
    if raw.endswith("```"):
        raw = raw[:-3]
    raw = raw.strip()
    try:
        data = json.loads(raw)
        return {
            "variables": data.get("variables", []),
            "methods": data.get("methods", []),
            "results": data.get("results", [])
        }
    except Exception:
        return {"variables": [], "methods": [], "results": []}

def normalize_gap_type(value: str | None) -> str | None:
    from .constants_graph import GapType
    import logging
    import re
    if not isinstance(value, str) or not value.strip():
        return None
    
    val = value.strip().lower()
    val = re.sub(r'[\\s\\-]+', '_', val)
    
    for gt in GapType:
        if val == gt.value:
            return gt.value
            
    if "methodological" in val or "method" in val:
        return GapType.METHODOLOGICAL.value
    if "dataset" in val or "data" in val:
        return GapType.DATASET_GAP.value
    if "population" in val or "sample" in val:
        return GapType.POPULATION_GAP.value
    if "empirical" in val or "eval" in val:
        return GapType.EMPIRICAL_GAP.value
    if "missing_relation" in val or "relation" in val:
        return GapType.MISSING_RELATION.value
    if "unexplored_concept" in val or "concept" in val or "theory" in val:
        return GapType.UNEXPLORED_CONCEPT.value
        
    logging.warning(f"Unrecognized gap type: {value}")
    return None

def validate_evidence(text: str, quote: str | None, page_number: int | str | None) -> bool:
    import re
    from rapidfuzz import fuzz
    
    if not quote or not str(quote).strip():
        return False
    if not page_number:
        return False
        
    norm_text = re.sub(r'\\s+', ' ', text).lower()
    norm_quote = re.sub(r'\\s+', ' ', str(quote)).lower()
    
    # Forensic 4: Fuzzy Matcher to handle hyphenation and slight PDF artifacts
    if norm_quote in norm_text:
        return True
        
    similarity = fuzz.partial_ratio(norm_quote, norm_text)
    if similarity > 85:
        return True
        
    return False

def parse_and_validate_gaps_v2(raw_json: str, paper_text: str) -> list[dict]:
    import json
    if not raw_json:
        return []
    raw_json = raw_json.strip()
    if raw_json.startswith("```json"):
        raw_json = raw_json[7:]
    elif raw_json.startswith("```"):
        raw_json = raw_json[3:]
    if raw_json.endswith("```"):
        raw_json = raw_json[:-3]
    raw_json = raw_json.strip()
    
    try:
        data = json.loads(raw_json)
        gaps = data.get("gaps", [])
        valid_gaps = []
        for g in gaps:
            evidence = g.get("evidence", {})
            quote = evidence.get("quote")
            page_num = evidence.get("page_number")
            
            if not validate_evidence(paper_text, quote, page_num):
                continue
                
            gap_type = normalize_gap_type(g.get("gap_type"))
            if not gap_type:
                continue
                
            conf = g.get("confidence_score", 50)
            try:
                conf = int(conf)
            except:
                conf = 50
            conf = max(0, min(100, conf))
            
            valid_gaps.append({
                "statement": g.get("statement", ""),
                "gap_type": gap_type,
                "confidence_score": conf,
                "evidence": {
                    "section": evidence.get("section", ""),
                    "quote": quote,
                    "page_number": page_num
                }
            })
        return valid_gaps
    except Exception:
        return []
'''

with open(target, "w", encoding="utf-8") as f:
    f.write(content[:start_idx] + new_code)

print("Replaced successfully!")
