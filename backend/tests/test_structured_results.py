from uuid import UUID

import pymupdf

from app.schemas import ExtractedComponentRead, PaperResultRead
from app.structured_pdf import build_structured_tables_pdf
from app.structured_results import build_structured_tables


def _component(parameter: str, value: str, *, page: int | None = None):
    evidence = []
    if page is not None:
        evidence = [
            {
                "quote": "Which indexing strategy provides the lowest latency?",
                "page_number": page,
                "block_id": "block-1",
            }
        ]
    return ExtractedComponentRead.model_validate(
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "paper_id": "00000000-0000-0000-0000-000000000002",
            "parameter": parameter,
            "ai_value": value,
            "status": "verified",
            "confidence": 0.9,
            "evidence": evidence,
            "model_name": "gemini-test",
            "prompt_version": "test-v1",
            "created_at": "2026-08-25T00:00:00Z",
        }
    )


def test_structured_tables_align_questions_objects_and_methodology() -> None:
    components = [
        _component(
            "research_question",
            "Which index is fastest? Which optimizer uses less memory?",
            page=3,
        ),
        _component("variables_concepts", "B-tree index; query optimizer"),
        _component("research_objective", "Measure latency; Measure memory"),
        _component(
            "methodology",
            "A quantitative experiment compares three query optimizers.",
        ),
        _component("dataset_sample", "TPC-H benchmark with 22 queries"),
    ]

    tables = build_structured_tables(components)

    assert [row.number for row in tables.research_questions] == [1, 2]
    assert tables.research_questions[0].related_object == "B-tree index"
    assert tables.research_questions[1].discussion_direction == "Measure memory"
    assert tables.research_questions[0].evidence_page == 3
    assert tables.methodology[0].form == "Eksperimen / Kuantitatif"
    assert tables.methodology[0].main_activity == "TPC-H benchmark with 22 queries"


def test_structured_pdf_has_two_readable_table_pages() -> None:
    components = [
        _component("research_question", "Which index is fastest?", page=3),
        _component("variables_concepts", "B-tree index"),
        _component("research_objective", "Measure query latency"),
        _component("methodology", "A quantitative experiment."),
        _component("dataset_sample", "TPC-H benchmark"),
    ]
    result = PaperResultRead.model_validate(
        {
            "paper": {
                "id": "00000000-0000-0000-0000-000000000002",
                "project_id": "00000000-0000-0000-0000-000000000003",
                "source": "upload",
                "original_filename": "query-optimization.pdf",
                "storage_key": "owner/project/query-optimization.pdf",
                "mime_type": "application/pdf",
                "file_size_bytes": 2048,
                "status": "ready",
                "authors": [],
                "created_at": "2026-08-25T00:00:00Z",
                "updated_at": "2026-08-25T00:00:00Z",
            },
            "components": [component.model_dump(mode="json") for component in components],
            "structured_tables": build_structured_tables(components).model_dump(
                mode="json"
            ),
        }
    )

    content = build_structured_tables_pdf(result)

    assert content.startswith(b"%PDF")
    document = pymupdf.open(stream=content, filetype="pdf")
    assert document.page_count == 2
    text = "\n".join(page.get_text() for page in document)
    document.close()
    assert "Tabel Pertanyaan Penelitian" in text
    assert "Tabel Metodologi" in text
    assert "B-tree index" in text
