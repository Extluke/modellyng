import asyncio
from uuid import UUID

import httpx

from .auth import AuthenticatedUser
from .gemini_json import AiInputError, generate_structured
from .repository import EntityNotFoundError, project_repository
from .schemas import AiResearchSynthesis, GapDecisionValue

_FAILURE_MESSAGE = "Sintesis riset belum dapat disusun. Coba lagi."


async def synthesize_gaps(user: AuthenticatedUser, project_id: UUID) -> AiResearchSynthesis:
    # 1. Ambil daftar keputusan gap yang di-accept oleh pengguna ini
    decisions = await project_repository.list_research_gap_decisions(user, project_id)
    accepted_decisions = [d for d in decisions if d.decision == GapDecisionValue.ACCEPTED]

    if not accepted_decisions:
        raise AiInputError("Belum ada kandidat gap yang Anda terima (accept) untuk disintesis.")

    # 2. Ambil isi teks gap dari matriks terreview
    matrix = await project_repository.get_comparative_matrix(user, project_id)
    gap_texts = []
    for decision in accepted_decisions:
        row = next((r for r in matrix.rows if r.parameter == decision.parameter), None)
        if not row:
            continue
        cell = next((c for c in row.cells if c.paper_id == decision.paper_id), None)
        value = (cell.final_value or cell.ai_value or "").strip() if cell else ""
        if value:
            gap_texts.append(
                f"- Sumber Paper ID ({decision.paper_id}), Parameter: {decision.parameter}\n"
                f"  Isi/Teks Keterbatasan: {value}"
            )

    if not gap_texts:
        raise AiInputError("Gagal menemukan isi teks dari gap yang diterima.")

    compiled_gaps = "\n".join(gap_texts)
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
    return await _generate(prompt, "Gap synthesis")


async def synthesize_graph_nodes(
    user: AuthenticatedUser, project_id: UUID, node_ids: list[str]
) -> AiResearchSynthesis:
    # 1. Ambil node knowledge graph milik project (RLS pemilik project)
    async with httpx.AsyncClient(timeout=15.0) as client:
        nodes_resp = await client.get(
            f"{project_repository._rest_url}/knowledge_graph_nodes",
            headers=project_repository._headers(user),
            params={"project_id": f"eq.{project_id}"},
        )
    project_repository._raise_for_repository_error(nodes_resp)
    selected_nodes = [n for n in nodes_resp.json() if n["id"] in node_ids]
    if not selected_nodes:
        raise EntityNotFoundError("Node yang dipilih tidak ditemukan di dalam proyek.")

    node_texts = []
    for n in selected_nodes:
        kind = str(n.get("node_type") or "concept").upper()
        label = n.get("label") or "Tanpa Label"
        detail = n.get("detail") or "Tanpa Detail"
        node_texts.append(f"- [{kind}] {label}: {detail}")

    compiled_nodes = "\n".join(node_texts)
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
    return await _generate(prompt, "Graph node synthesis")


async def _generate(prompt: str, purpose: str) -> AiResearchSynthesis:
    """Gemini dijalankan di thread agar tidak menahan event loop server."""
    result, _ = await asyncio.to_thread(
        generate_structured,
        prompt,
        AiResearchSynthesis,
        purpose=purpose,
        failure_message=_FAILURE_MESSAGE,
        temperature=0.7,
    )
    return result
