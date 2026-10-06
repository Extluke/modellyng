from uuid import UUID
import httpx
from pydantic import BaseModel
from google import genai
from google.genai import types

from .auth import AuthenticatedUser
from .config import get_settings
from .repository import project_repository
from .schemas import AiResearchSynthesis, GapDecisionValue


async def synthesize_gaps(user: AuthenticatedUser, project_id: UUID) -> AiResearchSynthesis:
    # 1. Ambil daftar keputusan gap yang di-accept oleh pengguna ini
    decisions = await project_repository.list_research_gap_decisions(user, project_id)
    accepted_decisions = [d for d in decisions if d.decision == GapDecisionValue.ACCEPTED]
    
    if not accepted_decisions:
        raise ValueError("Belum ada kandidat gap yang Anda terima (accept) untuk disintesis.")
        
    # 2. Ambil data asli dari matrix (atau tabel komponen) untuk mendapatkan isi (teks gap)
    matrix = await project_repository.get_comparative_matrix(user, project_id)
    
    # Kumpulkan teks gap
    gap_texts = []
    
    for decision in accepted_decisions:
        # Cari di matriks yang sesuai dengan paper dan parameter
        row = next((r for r in matrix.rows if r.parameter == decision.parameter), None)
        if row:
            cell = next((c for c in row.cells if c.paper_id == decision.paper_id), None)
            if cell and cell.value:
                gap_texts.append(f"- Sumber Paper ID ({decision.paper_id}), Parameter: {decision.parameter}\n  Isi/Teks Keterbatasan: {cell.value}")
    
    if not gap_texts:
        raise ValueError("Gagal menemukan isi teks dari gap yang diterima.")
        
    compiled_gaps = "\n".join(gap_texts)
    
    # 3. Panggil Gemini
    settings = get_settings()
    client = genai.Client(api_key=settings.gemini_api_key)
    
    prompt = f"""
Berdasarkan kumpulan keterbatasan (limitations) dan arahan masa depan (future works) dari berbagai paper berikut, posisikan diri Anda sebagai dosen pembimbing tesis yang ahli.

KUMPULAN RESEARCH GAP TERPILIH:
{compiled_gaps}

Tugas Anda:
1. Rumuskan 3 usulan judul baru yang kuat dan menarik untuk penelitian tesis yang akan datang.
2. Rumuskan 2-3 pertanyaan penelitian (Research Questions) yang spesifik dan langsung menjawab celah dari paper-paper tersebut.
3. Buat satu paragraf narasi (pernyataan novelty) yang menjelaskan letak kebaruan penelitian ini dibandingkan paper terdahulu.
4. Buat narasi penjelasan mengapa usulan ini sangat relevan.

Gunakan bahasa Indonesia yang akademis dan profesional.
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

async def synthesize_graph_nodes(user: AuthenticatedUser, project_id: UUID, node_ids: list[str]) -> AiResearchSynthesis:
    # 1. Fetch the nodes from the knowledge graph
    with httpx.Client(timeout=15.0) as client:
        nodes_resp = client.get(
            f"{project_repository._rest_url}/knowledge_graph_nodes",
            headers=project_repository._headers(user),
            params={"project_id": f"eq.{project_id}"}
        )
        project_repository._raise_for_repository_error(nodes_resp)
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
        
    compiled_nodes = "\n".join(node_texts)
    
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
