from io import BytesIO
from uuid import UUID
from zipfile import ZipFile

import pytest
from fastapi.testclient import TestClient

from app.export_service import ExportUnavailableError, build_project_export
from app.auth import AuthenticatedUser
from app.main import app
from app.repository import EntityNotFoundError, SupabaseProjectRepository
from app.schemas import ComparativeMatrixRead


client = TestClient(app)


def _matrix() -> ComparativeMatrixRead:
    return ComparativeMatrixRead.model_validate(
        {
            "project_id": "00000000-0000-0000-0000-000000000010",
            "project_title": "Query Optimization",
            "papers": [
                {
                    "id": "00000000-0000-0000-0000-000000000020",
                    "title": "Optimizing SQL Queries",
                    "original_filename": "query.pdf",
                }
            ],
            "rows": [
                {
                    "parameter": "methodology",
                    "cells": [
                        {
                            "paper_id": "00000000-0000-0000-0000-000000000020",
                            "ai_value": "AI baseline",
                            "final_value": "Human-reviewed method",
                            "status": "edited",
                            "confidence": 0.91,
                            "evidence": [
                                {
                                    "quote": "The optimizer evaluates alternative plans.",
                                    "page_number": 4,
                                    "section": "Methods",
                                    "subsection": None,
                                    "block_id": "private-block-4",
                                    "bounding_box": None,
                                }
                            ],
                        }
                    ],
                }
            ],
        }
    )


@pytest.mark.parametrize("export_format", ["docx", "xlsx", "csv", "pptx"])
def test_export_route_requires_authentication(export_format: str) -> None:
    response = client.get(
        "/api/v1/projects/00000000-0000-0000-0000-000000000010/"
        f"export/{export_format}"
    )
    assert response.status_code == 401


def test_csv_export_preserves_reviewed_value_and_evidence_chain() -> None:
    artifact = build_project_export(_matrix(), "csv")
    content = artifact.content.decode("utf-8-sig")
    assert artifact.filename == "modellyng-query-optimization.csv"
    assert "Human-reviewed method" in content
    assert "AI baseline" in content
    assert "Page 4" in content
    assert "private-block-4" in content
    assert "00000000-0000-0000-0000-000000000020" in content


@pytest.mark.parametrize(
    ("export_format", "required_member"),
    [
        ("docx", "word/document.xml"),
        ("xlsx", "xl/workbook.xml"),
        ("pptx", "ppt/presentation.xml"),
    ],
)
def test_office_exports_are_valid_packages_with_traceable_content(
    export_format: str, required_member: str
) -> None:
    artifact = build_project_export(_matrix(), export_format)
    assert artifact.content.startswith(b"PK")
    with ZipFile(BytesIO(artifact.content)) as package:
        assert required_member in package.namelist()
        combined_xml = b"".join(
            package.read(name)
            for name in package.namelist()
            if name.endswith(".xml")
        )
    assert b"Human-reviewed method" in combined_xml
    assert b"private-block-4" in combined_xml


def test_export_rejects_project_without_ready_papers() -> None:
    empty = ComparativeMatrixRead.model_validate(
        {
            "project_id": "00000000-0000-0000-0000-000000000010",
            "project_title": "Empty",
            "papers": [],
            "rows": [],
        }
    )
    with pytest.raises(ExportUnavailableError, match="Belum ada paper siap"):
        build_project_export(empty, "docx")


@pytest.mark.anyio
async def test_export_data_lookup_stops_when_project_owner_check_fails(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = SupabaseProjectRepository()
    user = AuthenticatedUser(
        id=UUID("00000000-0000-0000-0000-000000000001"),
        access_token="account-b",
    )

    async def deny_owner_lookup(*args, **kwargs):
        raise EntityNotFoundError("Project was not found")

    monkeypatch.setattr(repository, "get_project", deny_owner_lookup)
    with pytest.raises(EntityNotFoundError, match="Project was not found"):
        await repository.get_comparative_matrix(
            user,
            UUID("00000000-0000-0000-0000-000000000010"),
        )
