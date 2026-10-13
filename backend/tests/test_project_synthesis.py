from datetime import datetime, timezone
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from app import project_synthesis, synthesis_service
from app.auth import AuthenticatedUser, get_current_user
from app.gemini_json import AiInputError, AiUnavailableError
from app.main import app
from app.project_synthesis import (
    AiPaperPosition,
    AiProjectSynthesis,
    AiResearchIdea,
    AiSynthesisParagraphs,
    AiSynthesisPoint,
    NotEnoughPapersError,
    SynthesisContent,
    author_surname,
    build_citations,
    build_synthesis_content,
    build_synthesis_prompt,
    collect_synthesis_inputs,
    generate_synthesis_content,
    included_inputs,
    render_project_synthesis,
    synthesis_source_hash,
)
from app.repository import project_repository
from app.schemas import (
    AiResearchSynthesis,
    ComparativeMatrixRead,
    ExtractionParameter,
    GapDecisionValue,
    MatrixCellRead,
    MatrixPaperRead,
    MatrixRowRead,
    ResearchGapDecisionRead,
    VerificationStatus,
)

PROJECT_ID = UUID("00000000-0000-0000-0000-000000000010")
USER = AuthenticatedUser(id=UUID("00000000-0000-0000-0000-000000000001"), access_token="t")
P = ExtractionParameter


def pid(number: int) -> UUID:
    return UUID(f"00000000-0000-0000-0000-0000000002{number:02d}")


PAPERS = [
    MatrixPaperRead(
        id=pid(1),
        title="Hiding inside Html and Other Source Codes",
        original_filename="p1.pdf",
        authors=["HAMEED AL-QAHERI", "SANDIPAN DEY", "SUGATA SANYAL"],
        publication_year=2010,
    ),
    MatrixPaperRead(
        id=pid(2),
        title="Embedding Secret Data in Html Web Page",
        original_filename="p2.pdf",
        authors=["Sandipan Dey", "Hameed Al-Qaheri"],
        publication_year=2010,
        journal="IJCSI",
    ),
    MatrixPaperRead(
        id=pid(3),
        title="Semantic-Sensitive Web Information Retrieval Model",
        original_filename="p3.pdf",
        authors=["Youssef Bassil"],
        publication_year=2012,
    ),
    MatrixPaperRead(
        id=pid(4),
        title="Development and Maintenance of XML-based Websites",
        original_filename="p4.pdf",
    ),
]

VALUES = {
    1: {P.RESEARCH_PROBLEM: "Menyembunyikan pesan di HTML.", P.CONTRIBUTION: "Teknik huruf kapital tag. Detail lain."},
    2: {P.RESEARCH_PROBLEM: "Data rahasia di halaman web.", P.METHODOLOGY: "Eksperimen algoritmik."},
    3: {P.RESEARCH_PROBLEM: "Temu kembali dokumen HTML.", P.RESULTS_FINDINGS: "Presisi meningkat."},
    4: {},
}


def make_matrix(values=VALUES, papers=PAPERS, finals=None) -> ComparativeMatrixRead:
    finals = finals or {}
    rows = []
    for parameter in ExtractionParameter:
        cells = []
        for number, paper in enumerate(papers, start=1):
            text = values.get(number, {}).get(parameter)
            if text is None:
                continue
            cells.append(
                MatrixCellRead(
                    paper_id=paper.id,
                    ai_value=text,
                    final_value=finals.get((number, parameter)),
                    status=VerificationStatus.VERIFIED,
                    evidence=[],
                )
            )
        rows.append(MatrixRowRead(parameter=parameter, cells=cells))
    return ComparativeMatrixRead(
        project_id=PROJECT_ID, project_title="HTML", papers=papers, rows=rows
    )


def ai_answer(**overrides) -> AiProjectSynthesis:
    data = dict(
        similarities=[
            AiSynthesisPoint(text="Kedua paper menyisipkan data pada tag HTML.", paper_keys=["P2", "P1"]),
            AiSynthesisPoint(text="Hanya satu paper", paper_keys=["P1"]),
            AiSynthesisPoint(text="Rujukan fiktif", paper_keys=["P1", "P9"]),
            AiSynthesisPoint(text="kedua paper menyisipkan data pada tag html", paper_keys=["P1", "P2"]),
        ],
        differences=[AiSynthesisPoint(text="P3 berfokus pada temu kembali.", paper_keys=["P1", "P3"])],
        research_patterns=[AiSynthesisPoint(text="Dominan eksperimen.", paper_keys=["p1", "Paper 2"])],
        approach_differences=[],
        gaps=[AiSynthesisPoint(text="Belum ada uji ketahanan.", paper_keys=["[P3]"])],
        research_ideas=[
            AiResearchIdea(title="Steganografi tahan minifikasi", rationale="Menguji ketahanan.", paper_keys=["P1"]),
            AiResearchIdea(title="Tanpa dasar", rationale="x", paper_keys=[]),
        ],
        paper_positions=[
            AiPaperPosition(paper_key="P1", position="Pelopor teknik huruf kapital."),
            AiPaperPosition(paper_key="P9", position="Tidak ada."),
        ],
        paragraphs=AiSynthesisParagraphs(
            similarities="Kedua penelitian memakai tag HTML [P1, P2]. P3 menunjukkan arah lain [P9].",
            differences="Fokusnya berbeda [P1][P3].",
            research_patterns="Pola eksperimen terlihat (P1 dan P2).",
            approach_differences="",
            gaps="",
        ),
    )
    data.update(overrides)
    return AiProjectSynthesis(**data)


def included(matrix=None):
    return included_inputs(collect_synthesis_inputs(matrix or make_matrix()))


# --- Input dan sidik jari -------------------------------------------------


def test_collect_inputs_skip_placeholders_and_prefer_reviewer_edits():
    values = {
        1: {P.RESEARCH_PROBLEM: "asli AI"},
        2: {P.DATASET_SAMPLE: "File yang diunggah tidak terdeteksi sebagai paper penelitian."},
        3: {P.KEY_CLAIMS: "Informasi tidak ditemukan"},
        4: {P.LIMITATIONS: "-"},
    }
    matrix = make_matrix(values, finals={(1, P.RESEARCH_PROBLEM): "diedit   reviewer"})
    inputs = collect_synthesis_inputs(matrix)

    assert [item.key for item in inputs] == ["P1", "P2", "P3", "P4"]
    assert inputs[0].values == {"research_problem": "diedit reviewer"}
    assert [item.key for item in included_inputs(inputs)] == ["P1"]


def test_source_hash_tracks_reviewed_data_only():
    base = synthesis_source_hash(collect_synthesis_inputs(make_matrix()))
    assert base == synthesis_source_hash(collect_synthesis_inputs(make_matrix()))
    edited = make_matrix(finals={(1, P.RESEARCH_PROBLEM): "baru"})
    assert base != synthesis_source_hash(collect_synthesis_inputs(edited))
    # Paper tanpa hasil review tidak mengubah sidik jari.
    without_p4 = make_matrix(papers=PAPERS[:3])
    assert base == synthesis_source_hash(collect_synthesis_inputs(without_p4))


def test_prompt_uses_paper_codes_not_author_names():
    prompt = build_synthesis_prompt(included(), max_chars=20_000)
    assert "[P1] Judul: Hiding inside Html" in prompt
    assert "Tahun terbit: 2010" in prompt
    assert "- Masalah penelitian: Menyembunyikan pesan di HTML." in prompt
    assert "AL-QAHERI" not in prompt and "Bassil" not in prompt
    assert "[P4]" not in prompt  # belum punya hasil review


# --- Validasi jawaban AI --------------------------------------------------


def test_content_keeps_only_grounded_points():
    content = build_synthesis_content(included(), ai_answer(), model_name="m")

    similarities = content.sections["similarities"]
    # Poin satu paper ditolak untuk persamaan; rujukan fiktif dibuang; duplikat hilang.
    assert [p.text for p in similarities] == ["Kedua paper menyisipkan data pada tag HTML"]
    assert similarities[0].paper_ids == [pid(1), pid(2)]
    # Kode paper di teks poin dibuat terbaca.
    assert content.sections["differences"][0].text == "Paper 3 berfokus pada temu kembali"
    assert content.sections["research_patterns"][0].paper_ids == [pid(1), pid(2)]
    assert content.sections["approach_differences"] == []
    assert content.sections["gaps"][0].paper_ids == [pid(3)]
    assert [idea.title for idea in content.research_ideas] == ["Steganografi tahan minifikasi"]


def test_every_included_paper_gets_a_position():
    content = build_synthesis_content(included(), ai_answer())
    positions = {p.paper_id: p.text for p in content.paper_positions}

    assert list(positions) == [pid(1), pid(2), pid(3)]
    assert positions[pid(1)] == "Pelopor teknik huruf kapital"
    # Saat dirender, "Paper 1 ..." di awal posisi Paper 1 dibuang (label sudah ada).
    echoed = content.model_copy(
        update={
            "paper_positions": [
                project_synthesis.StoredPosition(paper_id=pid(1), text="Paper 1 memelopori teknik")
            ]
        }
    )
    rendered = render_project_synthesis(make_matrix(), echoed, stale=False)
    assert rendered.paper_positions[0].text == "Memelopori teknik"
    # Tanpa jawaban AI: kalimat pertama dari data review.
    assert positions[pid(3)] == "Presisi meningkat"
    assert positions[pid(2)] == "Data rahasia di halaman web"


def test_paragraph_markers_are_encoded_and_unknown_keys_removed():
    content = build_synthesis_content(included(), ai_answer())
    paragraphs = content.paragraphs

    assert paragraphs["similarities"] == (
        f"Kedua penelitian memakai tag HTML {{{{p:{pid(1)};{pid(2)}}}}}. "
        f"{{{{n:{pid(3)}}}}} menunjukkan arah lain."
    )
    assert paragraphs["differences"] == f"Fokusnya berbeda {{{{p:{pid(1)};{pid(3)}}}}}."
    assert paragraphs["research_patterns"] == (
        f"Pola eksperimen terlihat {{{{p:{pid(1)};{pid(2)}}}}}."
    )
    # Paragraf kosong dibangun dari poin; bagian tanpa poin tetap kosong.
    assert paragraphs["gaps"] == f"Belum ada uji ketahanan {{{{p:{pid(3)}}}}}."
    assert paragraphs["approach_differences"] == ""


def test_answer_without_grounded_points_is_rejected():
    empty = ai_answer(
        similarities=[AiSynthesisPoint(text="x y z", paper_keys=["P1"])],
        differences=[],
        research_patterns=[],
        gaps=[AiSynthesisPoint(text="Tanpa rujukan", paper_keys=[])],
    )
    with pytest.raises(AiUnavailableError):
        build_synthesis_content(included(), empty)


# --- Sitasi ---------------------------------------------------------------


@pytest.mark.parametrize(
    ("author", "surname"),
    [
        ("HAMEED AL-QAHERI", "Al-Qaheri"),
        ("Bayong Tjasyono HK", "Tjasyono"),
        ("Muh. Syafaat S. Kuba", "Kuba"),
        ("Budi Santoso, S.T.", "Santoso"),
        ("Ernawati", "Ernawati"),
        ("Martin Luther King Jr.", "King"),
    ],
)
def test_author_surname(author, surname):
    assert author_surname(author) == surname


def test_citations_follow_author_count_and_disambiguate_duplicates():
    duplicate = PAPERS[2].model_copy(update={"id": pid(5)})
    citations = build_citations(PAPERS + [duplicate])

    assert citations[pid(1)].parenthetical == "Al-Qaheri dkk., 2010"
    assert citations[pid(2)].parenthetical == "Dey & Al-Qaheri, 2010"
    assert citations[pid(2)].narrative == "Dey dan Al-Qaheri (2010)"
    assert citations[pid(3)].parenthetical == "Bassil, 2012a"
    assert citations[pid(5)].narrative == "Bassil (2012b)"
    assert citations[pid(4)].parenthetical == "“Development and Maintenance of…”, n.d."


def test_render_builds_citations_and_academic_text():
    content = build_synthesis_content(included(), ai_answer(), model_name="gemini-x")
    result = render_project_synthesis(make_matrix(), content, stale=False)

    assert [s.key for s in result.sections] == [
        "similarities",
        "differences",
        "research_patterns",
        "gaps",
    ]
    similarities = result.sections[0]
    assert similarities.title == "Persamaan"
    assert similarities.paragraph == (
        "Kedua penelitian memakai tag HTML (Al-Qaheri dkk., 2010; Dey & Al-Qaheri, 2010). "
        "Bassil (2012) menunjukkan arah lain."
    )
    assert [p.citation for p in result.papers] == [
        "(Al-Qaheri dkk., 2010)",
        "(Dey & Al-Qaheri, 2010)",
        "(Bassil, 2012)",
        "(“Development and Maintenance of…”, n.d.)",
    ]
    assert [p.included for p in result.papers] == [True, True, True, False]
    assert result.model_name == "gemini-x"

    text = result.academic_text
    assert text.startswith("Persamaan\nKedua penelitian memakai tag HTML")
    assert "\n\nCelah dan Peluang Penelitian\nBelum ada uji ketahanan (Bassil, 2012)." in text
    references = text.split("Daftar Pustaka\n", 1)[1].splitlines()
    assert references == [
        "Al-Qaheri, H., Dey, S., & Sanyal, S. (2010). Hiding inside Html and Other Source Codes.",
        "Bassil, Y. (2012). Semantic-Sensitive Web Information Retrieval Model.",
        "Dey, S., & Al-Qaheri, H. (2010). Embedding Secret Data in Html Web Page. IJCSI.",
    ]  # hanya paper yang disitasi, urut abjad


def test_narrative_citation_is_not_repeated_in_parentheses():
    by_key = {item.key: item for item in included()}
    encoded = project_synthesis.encode_citations("P1 dan P2 sama [P1, P2, P3]. Lalu [P1].", by_key)
    rendered, cited = project_synthesis.render_citations(
        encoded, build_citations(PAPERS)
    )

    assert rendered == (
        "Al-Qaheri dkk. (2010) dan Dey dan Al-Qaheri (2010) sama (Bassil, 2012). "
        "Lalu (Al-Qaheri dkk., 2010)."
    )
    assert cited == {pid(1), pid(2), pid(3)}


def test_apa_reference_formats_available_metadata_only():
    full = PAPERS[1].model_copy(
        update={"volume": "7", "issue": "2", "pages": "1-9", "doi": "https://doi.org/10.1/abc"}
    )
    assert project_synthesis.apa_reference(full, "2010") == (
        "Dey, S., & Al-Qaheri, H. (2010). Embedding Secret Data in Html Web Page. "
        "IJCSI, 7(2), 1-9. https://doi.org/10.1/abc"
    )
    single = PAPERS[2].model_copy(
        update={"authors": ["Ernawati"], "publisher": "Penerbit X", "pages": "null", "doi": "None"}
    )
    assert project_synthesis.apa_reference(single, "2012b") == (
        "Ernawati. (2012b). Semantic-Sensitive Web Information Retrieval Model. Penerbit X."
    )
    assert project_synthesis.apa_reference(PAPERS[3], "n.d.") == (
        "Development and Maintenance of XML-based Websites. (n.d.)."
    )


def test_render_drops_references_to_deleted_papers():
    content = build_synthesis_content(included(), ai_answer())
    without_p3 = make_matrix(papers=PAPERS[:2] + [PAPERS[3]])
    result = render_project_synthesis(without_p3, content, stale=True)

    assert result.stale is True
    gaps = next(s for s in result.sections if s.key == "gaps")
    assert gaps.points == []
    assert "Bassil" not in result.academic_text
    assert [p.paper_id for p in result.paper_positions] == [pid(1), pid(2)]


# --- Gemini ---------------------------------------------------------------


def test_generation_uses_fallback_model(fake_gemini):
    models = fake_gemini([RuntimeError("503 UNAVAILABLE"), ai_answer().model_dump_json()])
    content = generate_synthesis_content(included())

    assert models.calls == ["primary", "backup"]
    assert content.model_name == "backup"
    assert "[P3]" in models.prompts[0]


def test_generation_needs_two_papers():
    with pytest.raises(NotEnoughPapersError):
        generate_synthesis_content(included()[:1])


def test_invalid_ai_json_reports_friendly_error(fake_gemini):
    fake_gemini(["{}", "not json"])
    with pytest.raises(AiUnavailableError, match="Sintesis AI belum dapat disusun"):
        generate_synthesis_content(included())


# --- Repository -----------------------------------------------------------


@pytest.fixture
def repo_state(monkeypatch):
    state = {"matrix": make_matrix(), "row": None, "writes": [], "generated": 0}

    async def fake_matrix(user, project_id):
        return state["matrix"]

    async def fake_read(user, table, project_id):
        assert table == "project_syntheses"
        return state["row"]

    async def fake_write(user, table, row):
        state["writes"].append(row)
        state["row"] = {**row, "updated_at": "2026-10-13T00:00:00Z"}

    def fake_generate(inputs):
        state["generated"] += 1
        return build_synthesis_content(inputs, ai_answer(), model_name="m")

    monkeypatch.setattr(project_repository, "get_comparative_matrix", fake_matrix)
    monkeypatch.setattr(project_repository, "_read_project_ai_cache", fake_read)
    monkeypatch.setattr(project_repository, "_write_project_ai_cache", fake_write)
    monkeypatch.setattr(project_synthesis, "generate_synthesis_content", fake_generate)
    return state


@pytest.mark.anyio
async def test_repository_reuses_saved_synthesis_until_forced(repo_state):
    assert await project_repository.get_project_synthesis(USER, PROJECT_ID) is None

    first = await project_repository.generate_project_synthesis(USER, PROJECT_ID)
    second = await project_repository.generate_project_synthesis(USER, PROJECT_ID)
    forced = await project_repository.generate_project_synthesis(
        USER, PROJECT_ID, force_regenerate=True
    )

    assert repo_state["generated"] == 2
    assert first == second
    assert forced.sections == first.sections
    saved = repo_state["writes"][0]
    assert saved["project_id"] == str(PROJECT_ID)
    assert saved["source_hash"] == synthesis_source_hash(collect_synthesis_inputs(make_matrix()))
    assert SynthesisContent.model_validate(saved["content"]).paper_ids == [pid(1), pid(2), pid(3)]


@pytest.mark.anyio
async def test_saved_synthesis_is_marked_stale_after_review_changes(repo_state):
    await project_repository.generate_project_synthesis(USER, PROJECT_ID)
    fresh = await project_repository.get_project_synthesis(USER, PROJECT_ID)
    assert fresh is not None and fresh.stale is False

    repo_state["matrix"] = make_matrix(finals={(1, P.RESEARCH_PROBLEM): "direvisi"})
    stale = await project_repository.get_project_synthesis(USER, PROJECT_ID)
    assert stale is not None and stale.stale is True

    # Generate tanpa paksa tetap membuat ulang karena datanya berubah.
    await project_repository.generate_project_synthesis(USER, PROJECT_ID)
    assert repo_state["generated"] == 2


@pytest.mark.anyio
async def test_repository_requires_two_reviewed_papers(repo_state):
    repo_state["matrix"] = make_matrix(values={1: VALUES[1]})
    with pytest.raises(NotEnoughPapersError):
        await project_repository.generate_project_synthesis(USER, PROJECT_ID)
    assert repo_state["generated"] == 0


# --- Endpoint -------------------------------------------------------------


@pytest.fixture
def api_client():
    app.dependency_overrides[get_current_user] = lambda: USER
    yield TestClient(app)
    app.dependency_overrides.pop(get_current_user, None)


def sample_read():
    content = build_synthesis_content(included(), ai_answer(), model_name="m")
    return render_project_synthesis(make_matrix(), content, stale=False)


def test_get_endpoint_returns_null_or_saved(monkeypatch, api_client):
    results = [None, sample_read()]

    async def fake_get(user, project_id):
        return results.pop(0)

    monkeypatch.setattr(project_repository, "get_project_synthesis", fake_get)
    url = f"/api/v1/projects/{PROJECT_ID}/synthesis"

    assert api_client.get(url).json() is None
    body = api_client.get(url).json()
    assert body["sections"][0]["paragraph"].startswith("Kedua penelitian")
    assert body["papers"][0]["citation"] == "(Al-Qaheri dkk., 2010)"


def test_post_endpoint_passes_force_flag(monkeypatch, api_client):
    calls = []

    async def fake_generate(user, project_id, force_regenerate=False):
        calls.append(force_regenerate)
        return sample_read()

    monkeypatch.setattr(project_repository, "generate_project_synthesis", fake_generate)
    url = f"/api/v1/projects/{PROJECT_ID}/synthesis"

    assert api_client.post(url).status_code == 200
    assert api_client.post(url, json={"force_regenerate": True}).status_code == 200
    # Klien lama yang masih mengirim paper_ids tetap diterima.
    assert api_client.post(url, json={"paper_ids": [str(pid(1))]}).status_code == 200
    assert calls == [False, True, False]


@pytest.mark.parametrize(
    ("error", "status"),
    [
        (NotEnoughPapersError("Sintesis membutuhkan minimal 2 paper."), 409),
        (AiUnavailableError("Kuota Gemini sedang habis."), 503),
    ],
)
def test_post_endpoint_maps_errors(monkeypatch, api_client, error, status):
    async def fake_generate(user, project_id, force_regenerate=False):
        raise error

    monkeypatch.setattr(project_repository, "generate_project_synthesis", fake_generate)
    response = api_client.post(f"/api/v1/projects/{PROJECT_ID}/synthesis")

    assert response.status_code == status
    assert response.json()["detail"] == str(error)


# --- Sintesis gap (fitur lama yang memakai helper yang sama) -------------


@pytest.mark.anyio
async def test_gap_synthesis_reads_reviewed_values(monkeypatch):
    decision = ResearchGapDecisionRead(
        id=pid(90),
        project_id=PROJECT_ID,
        paper_id=pid(1),
        parameter=P.LIMITATIONS,
        reviewer_id=USER.id,
        created_at=datetime.now(timezone.utc),
        decision=GapDecisionValue.ACCEPTED,
    )
    prompts = []

    async def fake_decisions(user, project_id):
        return [decision]

    async def fake_matrix(user, project_id):
        return make_matrix(
            values={1: {P.LIMITATIONS: "teks AI"}},
            finals={(1, P.LIMITATIONS): "teks reviewer"},
        )

    def fake_generate(prompt, schema, **kwargs):
        prompts.append(prompt)
        return (
            AiResearchSynthesis(
                usulan_judul=["a"], rumusan_masalah=["b"], pernyataan_novelty="c", alasan_pemilihan="d"
            ),
            "m",
        )

    monkeypatch.setattr(project_repository, "list_research_gap_decisions", fake_decisions)
    monkeypatch.setattr(project_repository, "get_comparative_matrix", fake_matrix)
    monkeypatch.setattr(synthesis_service, "generate_structured", fake_generate)

    result = await synthesis_service.synthesize_gaps(USER, PROJECT_ID)

    assert result.usulan_judul == ["a"]
    assert "teks reviewer" in prompts[0]


@pytest.mark.anyio
async def test_gap_synthesis_without_accepted_gap_is_input_error(monkeypatch):
    async def no_decisions(user, project_id):
        return []

    monkeypatch.setattr(project_repository, "list_research_gap_decisions", no_decisions)
    with pytest.raises(AiInputError):
        await synthesis_service.synthesize_gaps(USER, PROJECT_ID)
