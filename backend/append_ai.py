import sys

content_to_append = '''

# --- Phase 2: Knowledge Graph Extraction ---

class AiKnowledgeGraphNode(BaseModel):
    node_type: str = Field(description="Tipe entitas: 'variable', 'method', 'result', 'research_area', 'gap', atau 'concept'.")
    label: str = Field(description="Label/judul node.")
    detail: str = Field(description="Penjelasan.")
    parent_label: str | None = Field(default=None, description="Jika ini sub-konsep, tulis label node induknya (Konsep Payung).")
    gap_typology: str | None = Field(default=None, description="Tipe celah jika node ini adalah 'gap'. (unexplored_concept, missing_relation, dll)")
    confidence_score: int = Field(default=95, ge=0, le=100, description="Tingkat keyakinan (0-100).")
    evidence_quote: str | None = Field(default=None, description="Kutipan terkait dari input JSON.")

class AiKnowledgeGraphEdge(BaseModel):
    source_label: str = Field(description="Label dari node sumber")
    target_label: str = Field(description="Label dari node target")
    relation: str = Field(description="Relasi, misal 'menyebabkan', 'digunakan_untuk', 'menghasilkan'")
    detail: str | None = Field(default=None, description="Penjelasan detail relasi")

class AiKnowledgeGraphExtraction(BaseModel):
    nodes: list[AiKnowledgeGraphNode] = Field(default_factory=list)
    edges: list[AiKnowledgeGraphEdge] = Field(default_factory=list)

def extract_knowledge_graph_from_results(extracted_data_json: str) -> AiKnowledgeGraphExtraction:
    settings = get_settings()
    if not settings.gemini_api_key:
        raise GeminiExtractionError("Gemini API key belum dikonfigurasi")
    
    prompt = f"""Anda adalah sistem ekstraksi Knowledge Graph.
Diberikan hasil ekstraksi penelitian tahap 1 dalam format JSON, tugas Anda adalah mengidentifikasi entitas (nodes) dan relasinya (edges) untuk membentuk jaring laba-laba yang utuh.

ATURAN (Phase 2):
1. Ekstrak entitas penting dari hasil penelitian sebagai Node (tipe: variable, method, result, research_area, gap, concept).
2. Temukan hubungan antar entitas tersebut (misal Method A -> Result B -> Gap C) dan buat sebagai Edges. Pastikan saling terhubung.
3. Tentukan `parent_label` jika sebuah node merupakan sub-bagian dari node lain.
4. Jika node adalah gap, berikan `gap_typology` secara spesifik.
5. Anda WAJIB memberikan format JSON sesuai schema. Anda membaca dari data hasil ekstraksi tahap 1 di bawah ini:

--- DATA TAHAP 1 ---
{extracted_data_json}
"""
    client = genai.Client(api_key=settings.gemini_api_key, http_options=types.HttpOptions(timeout=120_000))
    models = [settings.gemini_model]
    if settings.gemini_fallback_model:
        models.append(settings.gemini_fallback_model)
        
    last_exc = None
    for model in models:
        try:
            response = client.models.generate_content(
                model=model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_json_schema=AiKnowledgeGraphExtraction.model_json_schema(),
                ),
            )
            parsed = response.parsed
            if isinstance(parsed, AiKnowledgeGraphExtraction):
                return parsed
            return AiKnowledgeGraphExtraction.model_validate_json(response.text or "")
        except Exception as exc:
            last_exc = exc
            
    raise GeminiExtractionError(f"Gagal ekstrak Knowledge Graph: {last_exc}")
'''

with open('app/ai_extraction.py', 'a', encoding='utf-8') as f:
    f.write(content_to_append)

print("Appended Phase 2 to ai_extraction.py")
