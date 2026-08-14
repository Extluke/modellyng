from fastapi.testclient import TestClient

from app.main import app
from app.repository import SupabaseProjectRepository


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
