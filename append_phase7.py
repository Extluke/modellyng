import sys
import os

target = os.path.join("backend", "app", "ai_extraction.py")
with open(target, "a", encoding="utf-8") as f:
    f.write('''
# --- Phase 7: Edge Extraction V2 ---
def extract_edges_v2(paper_text: str, entities: list[str]) -> str:
    """Extract relationships between specific entities in a paper."""
    from .config import get_settings
    from google import genai
    from google.genai import types
    
    settings = get_settings()
    if not settings.gemini_api_key:
        raise GeminiExtractionError("Gemini API key belum dikonfigurasi")
        
    entities_str = "\\n".join(f"- {e}" for e in entities)
    
    prompt = f"""Anda adalah asisten AI yang fokus mencari hubungan (edges) antar entitas di dalam karya ilmiah.

TUGAS:
1. Temukan hubungan HANYA di antara entitas-entitas berikut (jangan membuat entitas baru):
{entities_str}

2. Untuk setiap hubungan yang ditemukan, berikan:
   - "source": Nama entitas asal (harus persis sama dengan salah satu di atas)
   - "target": Nama entitas tujuan (harus persis sama dengan salah satu di atas)
   - "edge_type": JENIS RELASI WAJIB SATU DARI INI (DILARANG MENGGUNAKAN NILAI LAIN): uses, produces, reveals, relates_to, supports
   - "quote_basis": Kutipan verbatim singkat dari teks yang membuktikan hubungan ini

FORMAT OUTPUT WAJIB JSON:
{{
    "edges": [
        {{
            "source": "entitas A",
            "target": "entitas B",
            "edge_type": "uses",
            "quote_basis": "We used entitas A to measure entitas B..."
        }}
    ]
}}

TEKS PAPER:
{paper_text[:settings.gemini_max_input_chars]}
"""
    client = genai.Client(api_key=settings.gemini_api_key, http_options=types.HttpOptions(timeout=120_000))
    models = [settings.gemini_model]
    if settings.gemini_fallback_model:
        models.append(settings.gemini_fallback_model)
        
    last_exc = None
    
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
                time.sleep(2 ** attempt)
                
    raise GeminiExtractionError(f"Gagal ekstrak Edges V2: {last_exc}")

def parse_and_validate_edges_v2(raw_json: str, paper_text: str, valid_entities: list[str]) -> list[dict]:
    import json
    import re
    from .constants_graph import EdgeType
    
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
        edges = data.get("edges", [])
        valid_edges = []
        
        # normalize valid entities for case-insensitive comparison
        valid_map = {e.strip().lower(): e.strip() for e in valid_entities}
        allowed_types = {EdgeType.USES.value, EdgeType.PRODUCES.value, EdgeType.REVEALS.value, EdgeType.RELATES_TO.value, EdgeType.SUPPORTS.value}
        
        for e in edges:
            source = e.get("source", "").strip().lower()
            target = e.get("target", "").strip().lower()
            edge_type = e.get("edge_type", "").strip().lower()
            quote_basis = e.get("quote_basis", "").strip()
            
            # 7.B Validator
            if source not in valid_map or target not in valid_map:
                continue
            if edge_type not in allowed_types:
                continue
            if source == target: # self-loop
                continue
            if not quote_basis:
                continue
                
            valid_edges.append({
                "source": valid_map[source],
                "target": valid_map[target],
                "edge_type": edge_type,
                "quote_basis": quote_basis
            })
            
        return valid_edges
    except Exception:
        return []
''')
print("Appended Phase 7 to ai_extraction.py")
