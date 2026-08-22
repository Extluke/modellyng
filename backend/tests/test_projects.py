from uuid import UUID

import httpx
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.auth import AuthenticatedUser
from app.main import app
from app.repository import (
    EntityNotFoundError,
    RepositoryError,
    SupabaseProjectRepository,
)
from app.schemas import ComparativeMatrixRead, ReviewRecordCreate


client = TestClient(app)


def test_projects_require_authentication() -> None:
    response = client.get("/api/v1/projects")

    assert response.status_code == 401
    assert response.json() == {"detail": "Authentication is required"}


def test_papers_require_authentication() -> None:
    response = client.get(
        "/api/v1/projects/00000000-0000-0000-0000-000000000000/papers"
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Authentication is required"}


def test_paper_upload_requires_authentication() -> None:
    response = client.post(
        "/api/v1/projects/00000000-0000-0000-0000-000000000000/papers/upload",
        files={"file": ("paper.pdf", b"%PDF-1.4\n", "application/pdf")},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Authentication is required"}


def test_paper_processing_requires_authentication() -> None:
    response = client.post(
        "/api/v1/projects/00000000-0000-0000-0000-000000000000/"
        "papers/00000000-0000-0000-0000-000000000000/process"
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Authentication is required"}


def test_reviews_require_authentication() -> None:
    response = client.get("/api/v1/reviews")

    assert response.status_code == 401
    assert response.json() == {"detail": "Authentication is required"}


def test_review_submission_requires_authentication() -> None:
    response = client.post(
        "/api/v1/reviews/00000000-0000-0000-0000-000000000000",
        json={"action": "accept"},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Authentication is required"}


@pytest.mark.parametrize("suffix", ["result", "pdf"])
def test_private_paper_result_routes_require_authentication(suffix: str) -> None:
    response = client.get(
        "/api/v1/projects/00000000-0000-0000-0000-000000000001/"
        f"papers/00000000-0000-0000-0000-000000000002/{suffix}"
    )
    assert response.status_code == 401


def test_review_history_requires_authentication() -> None:
    assert client.get("/api/v1/reviews/history").status_code == 401


def test_comparative_matrix_requires_authentication() -> None:
    response = client.get(
        "/api/v1/projects/00000000-0000-0000-0000-000000000001/comparative-matrix"
    )
    assert response.status_code == 401


def test_concept_evidence_map_requires_authentication() -> None:
    response = client.get(
        "/api/v1/projects/00000000-0000-0000-0000-000000000001/concept-evidence-map"
    )
    assert response.status_code == 401


def test_research_gap_map_requires_authentication() -> None:
    response = client.get(
        "/api/v1/projects/00000000-0000-0000-0000-000000000001/research-gap-map"
    )
    assert response.status_code == 401


@pytest.mark.anyio
async def test_processing_fails_before_creating_a_job_without_worker_key() -> None:
    repository = SupabaseProjectRepository()
    repository._worker_service_key = ""
    user = AuthenticatedUser(
        id=UUID("00000000-0000-0000-0000-000000000001"),
        access_token="account-a",
    )
    with pytest.raises(RepositoryError, match="SERVICE_ROLE_KEY kosong"):
        await repository.start_pdf_processing(
            user,
            UUID("00000000-0000-0000-0000-000000000010"),
            UUID("00000000-0000-0000-0000-000000000020"),
        )


@pytest.mark.parametrize("action", ["reject", "request_reanalysis"])
def test_reject_and_reanalysis_require_a_reason(action: str) -> None:
    with pytest.raises(ValidationError):
        ReviewRecordCreate.model_validate({"action": action})


@pytest.mark.anyio
@pytest.mark.parametrize("operation", ["result", "pdf"])
async def test_private_paper_reads_stop_when_owner_lookup_fails(
    monkeypatch: pytest.MonkeyPatch, operation: str
) -> None:
    repository = SupabaseProjectRepository()
    user = AuthenticatedUser(
        id="00000000-0000-0000-0000-000000000001", access_token="account-b"
    )

    async def deny_owner_lookup(*args, **kwargs):
        raise EntityNotFoundError("Paper was not found")

    monkeypatch.setattr(repository, "get_paper", deny_owner_lookup)
    method = (
        repository.get_paper_result
        if operation == "result"
        else repository.download_private_pdf
    )
    with pytest.raises(EntityNotFoundError):
        await method(
            user,
            UUID("00000000-0000-0000-0000-000000000010"),
            UUID("00000000-0000-0000-0000-000000000020"),
        )


@pytest.mark.anyio
async def test_reanalysis_preserves_history_and_enqueues_fresh_job(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = SupabaseProjectRepository()
    component_id = UUID("00000000-0000-0000-0000-000000000030")
    paper_id = UUID("00000000-0000-0000-0000-000000000020")
    project_id = UUID("00000000-0000-0000-0000-000000000010")
    user = AuthenticatedUser(
        id=UUID("00000000-0000-0000-0000-000000000001"),
        access_token="account-a",
    )
    responses = [
        [
            {
                "id": str(component_id),
                "paper_id": str(paper_id),
                "ai_value": "Original AI",
                "status": "needs_review",
                "papers": {"project_id": str(project_id)},
            }
        ],
        [
            {
                "id": "00000000-0000-0000-0000-000000000040",
                "component_id": str(component_id),
                "reviewer_id": str(user.id),
                "action": "request_reanalysis",
                "corrected_value": None,
                "note": "Evidence tidak cukup",
                "created_at": "2026-08-22T00:00:00Z",
            }
        ],
    ]
    writes: list[tuple[str, dict]] = []

    class FakeClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            return None

        async def get(self, url, **kwargs):
            return httpx.Response(
                200,
                json=responses.pop(0),
                request=httpx.Request("GET", url),
            )

        async def post(self, url, **kwargs):
            writes.append(("post", kwargs["json"]))
            return httpx.Response(
                201,
                json=responses.pop(0),
                request=httpx.Request("POST", url),
            )

        async def patch(self, url, **kwargs):
            writes.append(("patch", kwargs["json"]))
            return httpx.Response(204, request=httpx.Request("PATCH", url))

    async def no_refresh(*args, **kwargs):
        return None

    enqueued: list[tuple[UUID, UUID]] = []

    async def capture_enqueue(_user, queued_project_id, queued_paper_id):
        enqueued.append((queued_project_id, queued_paper_id))
        return None

    monkeypatch.setattr("app.repository.httpx.AsyncClient", FakeClient)
    monkeypatch.setattr(repository, "_refresh_review_status", no_refresh)
    monkeypatch.setattr(repository, "start_pdf_processing", capture_enqueue)

    record = await repository.review_component(
        user,
        component_id,
        ReviewRecordCreate(
            action="request_reanalysis", note="Evidence tidak cukup"
        ),
    )

    assert record.action.value == "request_reanalysis"
    assert writes[0][1]["original_ai_value"] == "Original AI"
    assert writes[1][1] == {"status": "unsupported", "final_value": None}
    assert enqueued == [(project_id, paper_id)]


@pytest.mark.anyio
async def test_comparative_matrix_uses_latest_reviewed_values_and_evidence(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = SupabaseProjectRepository()
    project_id = UUID("00000000-0000-0000-0000-000000000010")
    paper_id = UUID("00000000-0000-0000-0000-000000000020")
    user = AuthenticatedUser(
        id=UUID("00000000-0000-0000-0000-000000000001"),
        access_token="account-a",
    )
    project = SupabaseProjectRepository._to_project(
        {
            "id": str(project_id),
            "title": "Matrix project",
            "description": "",
            "status": "ready",
            "created_at": "2026-08-22T00:00:00Z",
            "updated_at": "2026-08-22T00:00:00Z",
            "papers": [],
        }
    )

    async def get_project(*args, **kwargs):
        return project

    payload = [
        {
            "id": str(paper_id),
            "title": "Paper A",
            "original_filename": "a.pdf",
            "created_at": "2026-08-22T00:00:00Z",
            "extracted_components": [
                {
                    "id": "new",
                    "parameter": "methodology",
                    "ai_value": "AI method",
                    "final_value": "Human method",
                    "status": "edited",
                    "confidence": 0.8,
                    "created_at": "2026-08-22T02:00:00Z",
                    "evidence_spans": [
                        {
                            "quote": "Verified method quote",
                            "page_number": 4,
                            "section": "Methods",
                            "subsection": None,
                            "paper_blocks": {"id": "block-1", "bounding_box": None},
                        }
                    ],
                },
                {
                    "id": "old",
                    "parameter": "methodology",
                    "ai_value": "Old method",
                    "final_value": "Old final",
                    "status": "verified",
                    "confidence": 0.7,
                    "created_at": "2026-08-22T01:00:00Z",
                    "evidence_spans": [],
                },
            ],
        }
    ]

    class FakeClient:
        def __init__(self, *args, **kwargs): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *args): return None
        async def get(self, url, **kwargs):
            assert kwargs["params"]["status"] == "eq.ready"
            return httpx.Response(200, json=payload, request=httpx.Request("GET", url))

    monkeypatch.setattr(repository, "get_project", get_project)
    monkeypatch.setattr("app.repository.httpx.AsyncClient", FakeClient)
    matrix = await repository.get_comparative_matrix(user, project_id)

    assert len(matrix.rows) == 11
    methodology = next(row for row in matrix.rows if row.parameter.value == "methodology")
    assert methodology.cells[0].final_value == "Human method"
    assert methodology.cells[0].ai_value == "AI method"
    assert methodology.cells[0].evidence[0].page_number == 4


@pytest.mark.anyio
async def test_concept_map_preserves_paper_concept_evidence_chain(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = SupabaseProjectRepository()
    project_id = UUID("00000000-0000-0000-0000-000000000010")
    paper_id = UUID("00000000-0000-0000-0000-000000000020")
    user = AuthenticatedUser(
        id=UUID("00000000-0000-0000-0000-000000000001"), access_token="account-a"
    )
    matrix = ComparativeMatrixRead.model_validate({
        "project_id": str(project_id),
        "project_title": "Map project",
        "papers": [{"id": str(paper_id), "title": "Paper A", "original_filename": "a.pdf"}],
        "rows": [{
            "parameter": "methodology",
            "cells": [{
                "paper_id": str(paper_id), "ai_value": "AI method",
                "final_value": "Reviewed method", "status": "edited", "confidence": 0.9,
                "evidence": [{
                    "quote": "Verified quote", "page_number": 4, "section": "Methods",
                    "subsection": None, "block_id": "block-1", "bounding_box": None,
                }],
            }],
        }],
    })

    async def get_matrix(*args, **kwargs): return matrix
    monkeypatch.setattr(repository, "get_comparative_matrix", get_matrix)
    graph = await repository.get_concept_evidence_map(user, project_id)

    assert [node.kind for node in graph.nodes] == ["paper", "concept", "evidence"]
    assert graph.nodes[1].detail == "Reviewed method"
    assert graph.nodes[2].page_number == 4
    assert [(edge.relation, edge.source, edge.target) for edge in graph.edges] == [
        ("contains", f"paper:{paper_id}", f"concept:{paper_id}:methodology"),
        ("supported_by", f"concept:{paper_id}:methodology", f"evidence:{paper_id}:methodology:0"),
    ]


@pytest.mark.anyio
async def test_research_gap_map_only_uses_reviewed_gap_sources(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = SupabaseProjectRepository()
    project_id = UUID("00000000-0000-0000-0000-000000000010")
    paper_id = UUID("00000000-0000-0000-0000-000000000020")
    user = AuthenticatedUser(
        id=UUID("00000000-0000-0000-0000-000000000001"), access_token="account-a"
    )
    matrix = ComparativeMatrixRead.model_validate({
        "project_id": str(project_id),
        "project_title": "Gap project",
        "papers": [{"id": str(paper_id), "title": "Paper A", "original_filename": "a.pdf"}],
        "rows": [
            {
                "parameter": "limitations",
                "cells": [{
                    "paper_id": str(paper_id), "ai_value": "AI limitation",
                    "final_value": "Reviewed limitation", "status": "edited", "confidence": 0.9,
                    "evidence": [{
                        "quote": "The sample was limited to one city.", "page_number": 9,
                        "section": "Limitations", "subsection": None,
                        "block_id": "block-9", "bounding_box": None,
                    }],
                }],
            },
            {
                "parameter": "methodology",
                "cells": [{
                    "paper_id": str(paper_id), "ai_value": "Survey", "final_value": None,
                    "status": "verified", "confidence": 0.8, "evidence": [],
                }],
            },
        ],
    })

    async def get_matrix(*args, **kwargs): return matrix
    monkeypatch.setattr(repository, "get_comparative_matrix", get_matrix)
    graph = await repository.get_research_gap_map(user, project_id)

    assert graph.candidate_count == 1
    assert [node.kind for node in graph.nodes] == ["paper", "gap", "evidence"]
    assert graph.nodes[1].detail == "Reviewed limitation"
    assert graph.nodes[2].page_number == 9
    assert [edge.relation for edge in graph.edges] == [
        "suggests_candidate", "supported_by"
    ]


def test_project_summary_counts_review_papers_and_verified_nodes() -> None:
    project = SupabaseProjectRepository._to_project(
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "title": "Project test",
            "description": "",
            "status": "needs_review",
            "created_at": "2026-08-14T00:00:00Z",
            "updated_at": "2026-08-14T00:00:00Z",
            "papers": [
                {
                    "id": "00000000-0000-0000-0000-000000000002",
                    "status": "needs_review",
                    "extracted_components": [
                        {"id": "c1", "status": "verified"},
                        {"id": "c2", "status": "edited"},
                        {"id": "c3", "status": "needs_review"},
                    ],
                }
            ],
        }
    )

    assert project.paper_count == 1
    assert project.review_count == 1
    assert project.knowledge_node_count == 2
