import sys
import os

target = os.path.join("app", "ai_extraction.py")
with open(target, "a", encoding="utf-8") as f:
    f.write('''
# --- Phase 6: GAP Extraction V2 ---
def extract_gaps_v2(paper_text: str) -> str:
    """Extract strictly gap categories and evidences."""
    settings = get_settings()
    if not settings.gemini_api_key:
        raise GeminiExtractionError("Gemini API key belum dikonfigurasi")
    
    prompt = f"""Anda adalah asisten AI yang fokus HANYA mencari celah penelitian (Research Gap) dari teks paper akademik berikut.
    
TUGAS:
1. Temukan SEMUA research gap yang disebutkan secara eksplisit oleh penulis (biasanya di bagian conclusion, discussion, atau future work).
2. Untuk setiap gap, berikan:
   - "statement": Deskripsi gap dalam bahasa Indonesia.
   - "gap_type": JENIS GAP WAJIB SATU DARI INI (DILARANG MENGGUNAKAN NILAI LAIN): unexplored_concept, missing_relation, methodological, population_gap, dataset_gap, empirical_gap.
   - "confidence_score": 0-100 (angka).
   - "evidence": Objek berisi {{ "section": "nama bab", "quote": "kutipan asli verbatim bahasa asli", "page_number": angka_halaman }}.

FORMAT OUTPUT WAJIB BERUPA JSON VALID. Contoh:
{{
    "gaps": [
        {{
            "statement": "Penelitian ini belum mengukur dampak jangka panjang dari model.",
            "gap_type": "empirical_gap",
            "confidence_score": 90,
            "evidence": {{
                "section": "Conclusion",
                "quote": "Future studies should investigate the long-term impacts...",
                "page_number": 12
            }}
        }}
    ]
}}

TEKS PAPER:
{paper_text[:settings.gemini_max_input_chars]}
"""
    
    client = genai.Client(api_key=settings.gemini_api_key, http_options=types.HttpOptions(timeout=120_000))
    response = client.models.generate_content(
        model=settings.gemini_model,
        contents=prompt,
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
        ),
    )
    return response.text or ""

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
    if not quote or not str(quote).strip():
        return False
    if not page_number:
        return False
        
    norm_text = re.sub(r'\\s+', ' ', text).lower()
    norm_quote = re.sub(r'\\s+', ' ', str(quote)).lower()
    
    if norm_quote not in norm_text:
        return False
        
    return True

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
''')
print("Appended!")
