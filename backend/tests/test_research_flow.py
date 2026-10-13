from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from app import research_flow
from app.auth import AuthenticatedUser, get_current_user
from app.gemini_json import AiUnavailableError
from app.main import app
from app.repository import project_repository
from app.research_flow import (
    AiFlowPaper,
    AiFlowSolutionGroup,
    AiFlowTheme,
    AiResearchFlow,
    FlowPaperInput,
    build_flow_prompt,
    build_research_flow,
    collect_flow_inputs,
    flow_source_hash,
    generate_research_flow,
)
from app.schemas import (
    ComparativeMatrixRead,
    ExtractionParameter,
    MatrixCellRead,
    MatrixPaperRead,
    MatrixRowRead,
    ResearchFlowRead,
    VerificationStatus,
)

PROJECT_ID = UUID("00000000-0000-0000-0000-000000000010")
USER = AuthenticatedUser(id=UUID("00000000-0000-0000-0000-000000000001"), access_token="t")


def paper_id(number: int) -> UUID:
    return UUID(f"00000000-0000-0000-0000-0000000001{number:02d}")


def make_input(number: int, **values: str) -> FlowPaperInput:
    return FlowPaperInput(
        key=f"P{number}",
        paper_id=paper_id(number),
        number=number,
        title=f"Judul paper {number}",
        values={key: value for key, value in values.items()},
    )


def figma_inputs() -> list[FlowPaperInput]:
    return [make_input(n, research_problem=f"Masalah {n}.") for n in range(1, 5)]


def figma_ai() -> AiResearchFlow:
    return AiResearchFlow(
        papers=[
            AiFlowPaper(key="P1", topic="banjir akibat curah hujan", problem="curah hujan", solution="apk"),
            AiFlowPaper(key="P2", topic="banjir akibat sungai", problem="sungai", solution="apk"),
            AiFlowPaper(key="P3", topic="banjir akibat longsor", problem="longsor", solution="web"),
            AiFlowPaper(key="P4", topic="cara menyetrika baju", problem="baju kusut", solution="setrika"),
        ],
        themes=[AiFlowTheme(label="banjir", paper_keys=["P1", "P2", "P3"])],
        solution_groups=[
            AiFlowSolutionGroup(
                label="apk",
                paper_keys=["P1", "P2"],
                functions=["peringatan dini banjir", "peta titik rawan"],
                conclusions=["apk mempercepat evakuasi", "data curah hujan real-time"],
            ),
            AiFlowSolutionGroup(
                label="web",
                paper_keys=["P3"],
                functions=["tidak boleh tampil"],
                conclusions=["tidak boleh tampil"],
            ),
        ],
    )


def test_flow_follows_figma_rules():
    flow = build_research_flow(PROJECT_ID, figma_inputs(), figma_ai(), model_name="m")

    assert [p.number for p in flow.papers] == [1, 2, 3, 4]
    assert len(flow.themes) == 1
    theme = flow.themes[0]
    assert theme.label == "banjir"
    assert [item.paper_id for item in theme.items] == [paper_id(1), paper_id(2), paper_id(3)]
    assert [item.topic for item in theme.items] == [
        "banjir akibat curah hujan",
        "banjir akibat sungai",
        "banjir akibat longsor",
    ]
    assert theme.items[0].problem == "curah hujan"

    shared, single = theme.solutions
    assert shared.shared is True
    assert shared.label == "apk"
    assert shared.paper_ids == [paper_id(1), paper_id(2)]
    assert shared.functions == ["peringatan dini banjir", "peta titik rawan"]
    assert shared.conclusions == ["apk mempercepat evakuasi", "data curah hujan real-time"]

    # Solusi tanpa kesamaan berhenti: tidak ada fungsi maupun kesimpulan.
    assert single.shared is False
    assert single.paper_ids == [paper_id(3)]
    assert single.functions == []
    assert single.conclusions == []

    # Topik tanpa kesamaan langsung end.
    assert [(u.paper_id, u.topic) for u in flow.unrelated] == [
        (paper_id(4), "cara menyetrika baju")
    ]


def test_theme_needs_two_known_papers_and_keys_are_normalized():
    ai = AiResearchFlow(
        papers=[AiFlowPaper(key="p1", topic="IoT", problem="daya", solution="sensor")],
        themes=[
            AiFlowTheme(label="hanya satu", paper_keys=["P1", "P9"]),
            AiFlowTheme(label="HTML", paper_keys=["[P2]", "Paper 3", "P2"]),
        ],
    )
    flow = build_research_flow(PROJECT_ID, figma_inputs(), ai)

    assert [t.label for t in flow.themes] == ["HTML"]
    assert [i.paper_id for i in flow.themes[0].items] == [paper_id(2), paper_id(3)]
    assert {u.paper_id for u in flow.unrelated} == {paper_id(1), paper_id(4)}
    assert flow.unrelated[0].topic == "IoT"


def test_cross_theme_solution_is_split_and_missing_papers_become_singletons():
    ai = AiResearchFlow(
        themes=[
            AiFlowTheme(label="A", paper_keys=["P1", "P2"]),
            AiFlowTheme(label="B", paper_keys=["P3", "P4"]),
        ],
        solution_groups=[
            AiFlowSolutionGroup(label="campur", paper_keys=["P1", "P3"], functions=["x"]),
        ],
    )
    flow = build_research_flow(PROJECT_ID, figma_inputs(), ai)

    assert [t.label for t in flow.themes] == ["A", "B"]
    for theme in flow.themes:
        assert all(not s.shared for s in theme.solutions)
        assert all(len(s.paper_ids) == 1 for s in theme.solutions)
        assert {pid for s in theme.solutions for pid in s.paper_ids} == {
            i.paper_id for i in theme.items
        }
    assert flow.unrelated == []


def test_shared_solution_without_points_uses_reviewed_values():
    inputs = [
        make_input(1, contribution="Aplikasi memberi notifikasi banjir. Detail lain.", key_claims="Evakuasi lebih cepat."),
        make_input(2, results_findings="Peta rawan banjir akurat.", key_claims="Warga lebih siap."),
    ]
    ai = AiResearchFlow(
        themes=[AiFlowTheme(label="banjir", paper_keys=["P1", "P2"])],
        solution_groups=[AiFlowSolutionGroup(label="apk", paper_keys=["P1", "P2"])],
    )
    solution = build_research_flow(PROJECT_ID, inputs, ai).themes[0].solutions[0]

    assert solution.shared is True
    assert solution.functions == ["Aplikasi memberi notifikasi banjir", "Peta rawan banjir akurat"]
    assert solution.conclusions == ["Evakuasi lebih cepat", "Warga lebih siap"]


def test_missing_ai_phrases_fall_back_to_matrix_values():
    inputs = [
        make_input(
            1,
            research_objective="Membangun sistem peringatan banjir. Kalimat kedua.",
            research_problem="Warga terlambat mengungsi.",
            methodology="--- BENTUK METODOLOGI --- Desain Riset : Eksperimen --- ARAH KEGIATAN --- Membuat prototipe aplikasi. Lanjut.",
        ),
        make_input(2),
    ]
    ai = AiResearchFlow(themes=[AiFlowTheme(label="banjir", paper_keys=["P1", "P2"])])
    theme = build_research_flow(PROJECT_ID, inputs, ai).themes[0]

    first = theme.items[0]
    assert first.topic == "Membangun sistem peringatan banjir"
    assert first.problem == "Warga terlambat mengungsi"
    assert theme.solutions[0].label == "Membuat prototipe aplikasi"
    assert theme.items[1].topic == "Judul paper 2"
    assert theme.items[1].problem == "Masalah belum tercantum"
    assert theme.solutions[1].label == "Solusi belum tercantum"


def test_long_phrases_are_shortened_on_word_boundary():
    ai = AiResearchFlow(
        papers=[AiFlowPaper(key="P1", topic="kata " * 40, problem="m", solution="s")]
    )
    topic = build_research_flow(PROJECT_ID, figma_inputs(), ai).unrelated[0].topic
    assert len(topic) <= 90
    assert topic.endswith("…")
    assert not topic.endswith(" …")


def _matrix(values: dict[ExtractionParameter, list[tuple[str, str | None]]]) -> ComparativeMatrixRead:
    papers = [
        MatrixPaperRead(id=paper_id(1), title="Paper A", original_filename="a.pdf"),
        MatrixPaperRead(id=paper_id(2), title="  ", original_filename="b.pdf"),
    ]
    rows = []
    for parameter in ExtractionParameter:
        cells = []
        for index, (ai_value, final_value) in enumerate(values.get(parameter, [])):
            cells.append(
                MatrixCellRead(
                    paper_id=paper_id(index + 1),
                    ai_value=ai_value,
                    final_value=final_value,
                    status=VerificationStatus.VERIFIED,
                    evidence=[],
                )
            )
        rows.append(MatrixRowRead(parameter=parameter, cells=cells))
    return ComparativeMatrixRead(project_id=PROJECT_ID, project_title="P", papers=papers, rows=rows)


def test_collect_inputs_prefers_reviewer_edits_and_skips_placeholders():
    matrix = _matrix({
        ExtractionParameter.RESEARCH_PROBLEM: [("ai   masalah", "diedit  reviewer"), ("Informasi tidak ditemukan", None)],
        ExtractionParameter.LIMITATIONS: [("bukan sumber alur", None)],
    })
    first, second = collect_flow_inputs(matrix)

    assert (first.key, first.number, first.title) == ("P1", 1, "Paper A")
    assert first.values == {"research_problem": "diedit reviewer"}
    assert second.title == "b.pdf"
    assert second.values == {}


def test_source_hash_changes_only_when_reviewed_data_changes():
    base = collect_flow_inputs(_matrix({ExtractionParameter.RESEARCH_PROBLEM: [("a", None)]}))
    same = collect_flow_inputs(_matrix({ExtractionParameter.RESEARCH_PROBLEM: [("a", None)]}))
    edited = collect_flow_inputs(_matrix({ExtractionParameter.RESEARCH_PROBLEM: [("a", "b")]}))

    assert flow_source_hash(base) == flow_source_hash(same)
    assert flow_source_hash(base) != flow_source_hash(edited)


def test_prompt_keeps_every_paper_inside_small_budget():
    inputs = [make_input(n, research_problem="x" * 5_000) for n in range(1, 4)]
    prompt = build_flow_prompt(inputs, max_chars=6_000)

    assert len(prompt) <= 6_000
    for key in ("[P1]", "[P2]", "[P3]"):
        assert key in prompt


def test_generation_falls_back_to_second_model(fake_gemini):
    models = fake_gemini([RuntimeError("503 UNAVAILABLE"), figma_ai().model_dump_json()])
    flow = generate_research_flow(PROJECT_ID, figma_inputs())

    assert models.calls == ["primary", "backup"]
    assert flow.model_name == "backup"
    assert flow.generated_at is not None
    assert flow.themes[0].solutions[0].shared is True


def test_generation_reports_quota_errors(fake_gemini):
    fake_gemini([RuntimeError("429 RESOURCE_EXHAUSTED")] * 2)
    with pytest.raises(AiUnavailableError, match="Kuota Gemini"):
        generate_research_flow(PROJECT_ID, figma_inputs())


@pytest.mark.anyio
async def test_repository_uses_cache_until_reviewed_data_changes(monkeypatch):
    matrix = _matrix({ExtractionParameter.RESEARCH_PROBLEM: [("a", None), ("b", None)]})
    generated = build_research_flow(PROJECT_ID, collect_flow_inputs(matrix), figma_ai())
    store: dict[str, object] = {}
    calls = {"generate": 0}

    async def fake_matrix(user, project_id):
        return matrix

    async def fake_read(user, project_id, source_hash):
        return store.get(source_hash)

    async def fake_write(user, project_id, source_hash, flow):
        store[source_hash] = flow

    def fake_generate(project_id, inputs):
        calls["generate"] += 1
        return generated

    monkeypatch.setattr(project_repository, "get_comparative_matrix", fake_matrix)
    monkeypatch.setattr(project_repository, "_read_research_flow_cache", fake_read)
    monkeypatch.setattr(project_repository, "_write_research_flow_cache", fake_write)
    monkeypatch.setattr(research_flow, "generate_research_flow", fake_generate)

    first = await project_repository.get_research_flow(USER, PROJECT_ID)
    second = await project_repository.get_research_flow(USER, PROJECT_ID)

    assert first == generated == second
    assert calls["generate"] == 1
    assert list(store) == [flow_source_hash(collect_flow_inputs(matrix))]


@pytest.mark.anyio
async def test_repository_returns_empty_flow_without_calling_gemini(monkeypatch):
    empty = ComparativeMatrixRead(project_id=PROJECT_ID, project_title="P", papers=[], rows=[])

    async def fake_matrix(user, project_id):
        return empty

    def fail_generate(project_id, inputs):
        raise AssertionError("Gemini must not be called without papers")

    monkeypatch.setattr(project_repository, "get_comparative_matrix", fake_matrix)
    monkeypatch.setattr(research_flow, "generate_research_flow", fail_generate)

    flow = await project_repository.get_research_flow(USER, PROJECT_ID)
    assert flow == ResearchFlowRead(project_id=PROJECT_ID)


@pytest.fixture
def api_client():
    app.dependency_overrides[get_current_user] = lambda: USER
    yield TestClient(app)
    app.dependency_overrides.pop(get_current_user, None)


def test_endpoint_returns_flow(monkeypatch, api_client):
    flow = build_research_flow(PROJECT_ID, figma_inputs(), figma_ai(), model_name="m")

    async def fake_get(user, project_id):
        assert project_id == PROJECT_ID
        return flow

    monkeypatch.setattr(project_repository, "get_research_flow", fake_get)
    response = api_client.get(f"/api/v1/projects/{PROJECT_ID}/research-flow")

    assert response.status_code == 200
    body = response.json()
    assert body["themes"][0]["solutions"][0]["shared"] is True
    assert body["unrelated"][0]["topic"] == "cara menyetrika baju"


def test_endpoint_maps_gemini_failure_to_503(monkeypatch, api_client):
    async def fake_get(user, project_id):
        raise AiUnavailableError("Kuota Gemini sedang habis. Coba lagi beberapa saat lagi.")

    monkeypatch.setattr(project_repository, "get_research_flow", fake_get)
    response = api_client.get(f"/api/v1/projects/{PROJECT_ID}/research-flow")

    assert response.status_code == 503
    assert response.json()["detail"].startswith("Kuota Gemini")
