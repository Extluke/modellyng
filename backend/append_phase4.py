import sys

# 1. Update schemas.py
schemas_code = '''
class GraphNodeSynthesisRequest(BaseModel):
    node_ids: list[str] = Field(description="Daftar ID node (terutama Gap dan konteksnya) untuk disintesis.")
'''
with open('app/schemas.py', 'a', encoding='utf-8') as f:
    f.write(schemas_code)

# 2. Update synthesis_service.py
synthesis_code = '''
async def synthesize_graph_nodes(user: AuthenticatedUser, project_id: UUID, node_ids: list[str]) -> AiResearchSynthesis:
    # 1. Fetch the nodes from the knowledge graph
    with httpx.Client(timeout=15.0) as client:
        nodes_resp = client.get(
            f"{project_repository._rest_url}/knowledge_graph_nodes",
            headers=project_repository._headers(user),
            params={"project_id": f"eq.{project_id}"}
        )
        project_repository._raise_for_error(nodes_resp)
        all_nodes = nodes_resp.json()
        
    selected_nodes = [n for n in all_nodes if n["id"] in node_ids]
    if not selected_nodes:
        raise ValueError("Node yang dipilih tidak ditemukan di dalam proyek.")
        
    # Kumpulkan teks gap dan konsep dari node
    node_texts = []
    for n in selected_nodes:
        kind = str(n.get("node_type") or "concept").upper()
        label = n.get("label") or "Tanpa Label"
        detail = n.get("detail") or "Tanpa Detail"
        node_texts.append(f"- [{kind}] {label}: {detail}")
        
    compiled_nodes = "\\n".join(node_texts)
    
    # 2. Panggil Gemini
    settings = get_settings()
    client = genai.Client(api_key=settings.gemini_api_key)
    
    prompt = f"""
Berdasarkan kumpulan entitas Knowledge Graph (seperti celah/gap, metodologi, dan variabel) berikut, posisikan diri Anda sebagai dosen pembimbing tesis yang ahli.

KUMPULAN ENTITAS GRAPH TERPILIH:
{compiled_nodes}

Tugas Anda:
1. Rumuskan 3 usulan judul baru yang kuat dan menarik untuk penelitian tesis yang akan datang.
2. Rumuskan 2-3 pertanyaan penelitian (Research Questions) yang spesifik dan langsung memecahkan gap yang dipilih.
3. Buat satu paragraf narasi (pernyataan novelty) yang menjelaskan letak kebaruan penelitian ini.
4. Buat narasi penjelasan mengapa usulan ini sangat relevan.

Gunakan bahasa Indonesia yang akademis dan profesional. Output WAJIB dalam format JSON.
"""
    
    response = client.models.generate_content(
        model=settings.gemini_model,
        contents=prompt,
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
            response_schema=AiResearchSynthesis,
            temperature=0.7,
        ),
    )
    
    return AiResearchSynthesis.model_validate_json(response.text)
'''
with open('app/synthesis_service.py', 'a', encoding='utf-8') as f:
    f.write(synthesis_code)

# 3. Update main.py
with open('app/main.py', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace(
    "GraphNodeSynthesisRequest", 
    ""  # Avoid double adding if script is rerun
)
content = content.replace(
    "AiResearchSynthesis,",
    "AiResearchSynthesis,\n    GraphNodeSynthesisRequest,"
)

main_endpoint_code = '''
@api.post(
    "/projects/{project_id}/synthesize-graph-nodes",
    response_model=AiResearchSynthesis,
    tags=["projects"],
)
async def synthesize_graph_nodes_endpoint(
    project_id: UUID, payload: GraphNodeSynthesisRequest, current_user: CurrentUser
) -> AiResearchSynthesis:
    from .synthesis_service import synthesize_graph_nodes
    return await synthesize_graph_nodes(current_user, project_id, payload.node_ids)
'''

target = '''@api.get(
    "/projects/{project_id}/intelligence-report",'''

content = content.replace(target, main_endpoint_code + "\\n" + target)

with open('app/main.py', 'w', encoding='utf-8') as f:
    f.write(content)

print("Added synthesis phase 4 implementation")
