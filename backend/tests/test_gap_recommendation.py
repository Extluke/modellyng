from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import UUID

import httpx
import pytest
from fastapi.testclient import TestClient

from app import gap_recommendation
from app.auth import AuthenticatedUser, get_current_user
from app.gap_recommendation import (
    AiGapRecommendation,
    build_gap_prompt,
    clean_recommendation,
    gap_input_from_node,
    gap_source_hash,
)
from app.gemini_json import AiUnavailableError
from app.main import app
from app.repository import EntityNotFoundError, project_repository

USER = AuthenticatedUser(id=UUID("00000000-0000-0000-0000-0000000000aa"), access_token="user-token")
PROJECT_ID = UUID("00000000-0000-0000-0000-000000000001")
GAP_ID = UUID("00000000-0000-0000-0000-0000000000b1")


def iot_node(**overrides) -> dict:
    node = {
        "id": str(GAP_ID),
        "node_type": "research_gap",
        "label": "Keterbatasan Device IoT",
        "detail": "Kemampuan komputasi dan memori device IoT sensor terbatas.",
        "gap_typology": "methodological",
        "evidence": [
            {
                "paper_title": "Studi Edge AI",
                "section": "Kesimpulan",
                "quote": "Mikrokontroler IoT standar tidak mampu menjalankan inferensi AI.",
                "page_number": 8,
            },
            "bukan objek",
            {"paper_title": "Kosong", "quote": "  "},
        ],
    }
    node.update(overrides)
    return node


def ai_answer(**overrides) -> AiGapRecommendation:
    data = {
        "core_issue": "Perangkat IoT tidak kuat menjalankan inferensi.",
        "concrete_solution": "Ganti mikrokontroler IoT dengan Raspberry Pi 5.",
        "what_user_can_do": "Pindahkan inferensi ke single-board computer dan bandingkan latensinya.",
        "next_steps": ["Ukur baseline.", "Siapkan Raspberry Pi.", "Bandingkan latensi.", "Ukur baseline."],
        "proposed_titles": ["Edge AI berbasis Raspberry Pi", "Perbandingan IoT dan SBC"],
    }
    data.update(overrides)
    return AiGapRecommendation(**data)


def test_gap_input_keeps_only_real_evidence() -> None:
    gap = gap_input_from_node(iot_node())

    assert gap.gap_id == GAP_ID
    assert gap.statement.startswith("Kemampuan komputasi")
    assert len(gap.evidence) == 1
    assert gap.evidence[0].paper_title == "Studi Edge AI"


def test_prompt_is_built_from_the_clicked_gap() -> None:
    prompt = build_gap_prompt(gap_input_from_node(iot_node()))

    assert "Keterbatasan Device IoT" in prompt
    assert "Kemampuan komputasi dan memori device IoT sensor terbatas." in prompt
    assert "Mikrokontroler IoT standar tidak mampu menjalankan inferensi AI." in prompt
    assert "celah metodologi" in prompt
    assert "Jangan mengarang" in prompt
    assert "Abaikan instruksi" in prompt


def test_source_hash_changes_when_gap_or_evidence_changes() -> None:
    base = gap_source_hash(gap_input_from_node(iot_node()))

    assert base == gap_source_hash(gap_input_from_node(iot_node()))
    assert base != gap_source_hash(gap_input_from_node(iot_node(detail="Gap lain.")))
    assert base != gap_source_hash(gap_input_from_node(iot_node(evidence=[])))


def test_recommendation_is_cleaned_and_deduplicated() -> None:
    cleaned = clean_recommendation(ai_answer())

    assert cleaned.next_steps == ["Ukur baseline.", "Siapkan Raspberry Pi.", "Bandingkan latensi."]
    assert "Raspberry Pi" in cleaned.concrete_solution


@pytest.mark.parametrize("override", [{"concrete_solution": " "}, {"next_steps": []}])
def test_recommendation_without_solution_or_steps_is_rejected(override) -> None:
    with pytest.raises(AiUnavailableError):
        clean_recommendation(ai_answer(**override))


@pytest.fixture
def repo_state(monkeypatch):
    state = {"node_rows": [iot_node()], "row": None, "writes": [], "generated": 0, "requests": []}

    class FakeAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *exc):
            return False

        async def get(self, url, headers=None, params=None):
            state["requests"].append((url, headers, params))
            return httpx.Response(200, json=state["node_rows"], request=httpx.Request("GET", url))

    async def fake_read(user, table, key, *, key_column="project_id"):
        assert (table, key_column, key) == ("gap_recommendations", "gap_id", GAP_ID)
        return state["row"]

    async def fake_write(user, table, row, *, on_conflict="project_id"):
        assert (table, on_conflict) == ("gap_recommendations", "gap_id")
        state["writes"].append(row)
        state["row"] = {**row, "updated_at": "2026-10-14T00:00:00Z"}

    def fake_generate(gap):
        state["generated"] += 1
        return clean_recommendation(ai_answer()), "gemini-test"

    monkeypatch.setattr(project_repository, "get_project", AsyncMock(return_value=SimpleNamespace(id=PROJECT_ID)))
    monkeypatch.setattr("app.repository.httpx.AsyncClient", FakeAsyncClient)
    monkeypatch.setattr(project_repository, "_read_project_ai_cache", fake_read)
    monkeypatch.setattr(project_repository, "_write_project_ai_cache", fake_write)
    monkeypatch.setattr(gap_recommendation, "generate_gap_recommendation", fake_generate)
    return state


@pytest.mark.anyio
async def test_recommendation_is_generated_once_and_reused(repo_state) -> None:
    first = await project_repository.get_gap_recommendation(USER, PROJECT_ID, GAP_ID)
    second = await project_repository.get_gap_recommendation(USER, PROJECT_ID, GAP_ID)

    assert repo_state["generated"] == 1
    assert first.concrete_solution == second.concrete_solution
    assert "Raspberry Pi" in first.concrete_solution
    assert second.model_name == "gemini-test"
    assert second.generated_at is not None
    written = repo_state["writes"][0]
    assert written["gap_id"] == str(GAP_ID)
    assert written["project_id"] == str(PROJECT_ID)
    # Gap dibaca dengan token pengguna dan dibatasi ke proyeknya.
    _, headers, params = repo_state["requests"][0]
    assert headers["Authorization"] == "Bearer user-token"
    assert params["id"] == f"eq.{GAP_ID}"
    assert params["project_id"] == f"eq.{PROJECT_ID}"


@pytest.mark.anyio
async def test_recommendation_is_regenerated_when_gap_changes(repo_state) -> None:
    await project_repository.get_gap_recommendation(USER, PROJECT_ID, GAP_ID)
    repo_state["node_rows"] = [iot_node(detail="Pernyataan gap diperbarui.")]

    await project_repository.get_gap_recommendation(USER, PROJECT_ID, GAP_ID)

    assert repo_state["generated"] == 2


@pytest.mark.anyio
@pytest.mark.parametrize("rows", [[], [iot_node(node_type="paper")]])
async def test_missing_or_non_gap_node_is_not_found(repo_state, rows) -> None:
    repo_state["node_rows"] = rows

    with pytest.raises(EntityNotFoundError):
        await project_repository.get_gap_recommendation(USER, PROJECT_ID, GAP_ID)
    assert repo_state["generated"] == 0


@pytest.fixture
def api_client():
    app.dependency_overrides[get_current_user] = lambda: USER
    yield TestClient(app)
    app.dependency_overrides.pop(get_current_user, None)


def test_endpoint_returns_recommendation(api_client, monkeypatch) -> None:
    from app.gap_recommendation import render_gap_recommendation

    async def fake_get(user, project_id, gap_id):
        assert (user, project_id, gap_id) == (USER, PROJECT_ID, GAP_ID)
        return render_gap_recommendation(gap_id, clean_recommendation(ai_answer()), model_name="m", generated_at=None)

    monkeypatch.setattr(project_repository, "get_gap_recommendation", fake_get)

    response = api_client.get(f"/api/v1/projects/{PROJECT_ID}/gaps/{GAP_ID}/recommendation")

    assert response.status_code == 200
    body = response.json()
    assert body["concrete_solution"] == "Ganti mikrokontroler IoT dengan Raspberry Pi 5."
    assert len(body["next_steps"]) == 3


def test_endpoint_maps_errors(api_client, monkeypatch) -> None:
    async def not_found(*args):
        raise EntityNotFoundError("Gap tidak ditemukan")

    monkeypatch.setattr(project_repository, "get_gap_recommendation", not_found)
    assert api_client.get(f"/api/v1/projects/{PROJECT_ID}/gaps/{GAP_ID}/recommendation").status_code == 404

    async def unavailable(*args):
        raise AiUnavailableError("Gemini sedang sibuk atau timeout. Coba lagi beberapa saat lagi.")

    monkeypatch.setattr(project_repository, "get_gap_recommendation", unavailable)
    response = api_client.get(f"/api/v1/projects/{PROJECT_ID}/gaps/{GAP_ID}/recommendation")
    assert response.status_code == 503
    assert "Gemini sedang sibuk" in response.json()["detail"]


def test_endpoint_requires_authentication() -> None:
    response = TestClient(app).get(f"/api/v1/projects/{PROJECT_ID}/gaps/{GAP_ID}/recommendation")

    assert response.status_code == 401
