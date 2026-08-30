"""Authenticated local smoke test for the visual research workflow.

Run only against the local stack. Credentials are read interactively and are
never persisted or printed.
"""

from __future__ import annotations

import getpass
import json
from pathlib import Path

import httpx

from app.config import get_settings


API_URL = "http://127.0.0.1:8000/api/v1"


def main() -> None:
    settings = get_settings()
    email = input("Email akun QA: ").strip()
    password = getpass.getpass("Password akun QA: ")
    with httpx.Client(timeout=120.0) as client:
        auth = client.post(
            f"{settings.supabase_url}/auth/v1/token",
            params={"grant_type": "password"},
            headers={"apikey": settings.supabase_anon_key},
            json={"email": email, "password": password},
        )
        if not auth.is_success:
            raise RuntimeError(f"Login QA gagal ({auth.status_code})")
        token = auth.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        projects = _json(client.get(f"{API_URL}/projects", headers=headers))
        if not projects:
            raise RuntimeError("Akun QA belum memiliki proyek")

        selected = None
        selected_papers = None
        for project in projects:
            papers = _json(
                client.get(
                    f"{API_URL}/projects/{project['id']}/papers", headers=headers
                )
            )
            ready = [paper for paper in papers if paper["status"] == "ready"]
            if len(ready) >= 2:
                selected = project
                selected_papers = ready
                break
        if selected is None or selected_papers is None:
            raise RuntimeError("Tidak ada proyek dengan minimal dua paper ready")

        project_id = selected["id"]
        paper = selected_papers[0]
        paper_id = paper["id"]
        result = _json(
            client.get(
                f"{API_URL}/projects/{project_id}/papers/{paper_id}/result",
                headers=headers,
            )
        )
        structured = result["structured_tables"]
        assert structured["research_questions"], "Tabel pertanyaan kosong"
        assert structured["methodology"], "Tabel metodologi kosong"
        assert set(structured["methodology"][0]) == {
            "content",
            "form",
            "main_activity",
            "activity_direction",
            "final_goal",
        }

        matrix = _json(
            client.get(
                f"{API_URL}/projects/{project_id}/comparative-matrix",
                headers=headers,
            )
        )
        assert len(matrix["papers"]) >= 2
        cells = [cell for row in matrix["rows"] for cell in row["cells"]]
        assert cells
        assert {cell["status"] for cell in cells} <= {"verified", "edited"}
        pairs = [
            (row["parameter"], cell["paper_id"])
            for row in matrix["rows"]
            for cell in row["cells"]
        ]
        assert len(pairs) == len(set(pairs)), "Matrix memuat versi komponen ganda"

        gap_map = _json(
            client.get(
                f"{API_URL}/projects/{project_id}/research-gap-map",
                headers=headers,
            )
        )
        gaps = [node for node in gap_map["nodes"] if node["kind"] == "gap"]
        assert gaps, "Tidak ada kandidat gap terverifikasi untuk smoke test"
        gap = gaps[0]
        decision_url = (
            f"{API_URL}/projects/{project_id}/research-gaps/"
            f"{gap['paper_id']}/{gap['parameter']}/decision"
        )
        rejected = _json(
            client.put(
                decision_url, headers=headers, json={"decision": "rejected"}
            )
        )
        assert rejected["decision"] == "rejected"
        accepted = _json(
            client.put(
                decision_url, headers=headers, json={"decision": "accepted"}
            )
        )
        assert accepted["decision"] == "accepted"
        decisions = _json(
            client.get(
                f"{API_URL}/projects/{project_id}/research-gap-decisions",
                headers=headers,
            )
        )
        assert any(
            item["paper_id"] == gap["paper_id"]
            and item["parameter"] == gap["parameter"]
            and item["decision"] == "accepted"
            for item in decisions
        )

        pdf = client.get(
            f"{API_URL}/projects/{project_id}/papers/{paper_id}/structured-tables.pdf",
            headers=headers,
        )
        pdf.raise_for_status()
        assert pdf.headers["content-type"].startswith("application/pdf")
        assert pdf.content.startswith(b"%PDF")
        output = (
            Path(__file__).resolve().parents[2]
            / "output"
            / "pdf"
            / "modellyng-structured-paper-live.pdf"
        )
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(pdf.content)

        chat = _json(
            client.post(
                f"{API_URL}/projects/{project_id}/chat",
                headers=headers,
                json={
                    "question": "Apa perbedaan metodologi paper dalam proyek ini?",
                    "history": [],
                },
            )
        )
        assert chat["answer"].strip()
        assert "review_notice" in chat

    print(
        json.dumps(
            {
                "login": "passed",
                "project": selected["title"],
                "ready_papers": len(selected_papers),
                "structured_question_rows": len(
                    structured["research_questions"]
                ),
                "methodology_rows": len(structured["methodology"]),
                "matrix_cells": len(cells),
                "matrix_statuses": sorted({cell["status"] for cell in cells}),
                "gap_candidates": len(gaps),
                "gap_decision_branches": ["rejected", "accepted"],
                "chat_sources": len(chat["sources"]),
                "pdf_bytes": len(pdf.content),
                "pdf_path": str(output),
            },
            indent=2,
        )
    )


def _json(response: httpx.Response):
    if not response.is_success:
        detail = response.json().get("detail", "request failed")
        raise RuntimeError(f"API QA gagal ({response.status_code}): {detail}")
    return response.json()


if __name__ == "__main__":
    main()
