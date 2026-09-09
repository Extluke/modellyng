from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import uuid4

import httpx
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.auth import AuthenticatedUser, get_current_user
from app.comparison_models import ASPECTS, ASPECT_PARAMETERS, ComparisonPaper, ComparisonReviewCreate
from app.comparison_repository import ComparisonRepository
from app.comparison_service import ProposedComparison, ProposedStep, compare_papers, validate_comparison
from app.main import app
from app.repository import EntityNotFoundError, InvalidReviewError


def paper(title="Paper A"):
    paper_id = uuid4()
    components = []
    for parameter in sorted(set.union(*ASPECT_PARAMETERS.values())):
        component_id = uuid4()
        components.append({"id": component_id, "parameter": parameter, "value": f"Reviewed {parameter}",
                           "evidence": [{"ref": uuid4(), "component_id": component_id,
                                         "paper_id": paper_id, "parameter": parameter,
                                         "quote": f"Original evidence for {parameter}.", "page_number": 3,
                                         "block_id": str(uuid4()), "section": "Methods"}]})
    return ComparisonPaper(id=paper_id, title=title, components=components)


def proposal(left, right, *, stop=None, decision="no"):
    steps = []
    for aspect in ASPECTS:
        parameter = sorted(ASPECT_PARAMETERS[aspect])[0]
        refs = [[str(e.ref) for c in p.components if c.parameter == parameter for e in c.evidence]
                for p in (left, right)]
        steps.append(ProposedStep(aspect=aspect, decision=decision if aspect == stop else "yes",
                                  reason="Cakupan rumah tangga umum berbeda dengan rumah tangga pemilah sampah.",
                                  left_refs=refs[0], right_refs=refs[1]))
    return ProposedComparison(steps=steps)


def test_household_example_stops_at_data_and_keeps_both_evidence_chains():
    left, right = paper(), paper("Paper B")
    result = validate_comparison(proposal(left, right, stop="data_object"), left, right, model_name="test")
    assert [s.decision for s in result.steps] == ["yes", "yes", "no", "not_compared", "not_compared"]
    assert result.outcome == "candidate_gap"
    assert result.candidate.kind == "population_context"
    assert result.stop_aspect == "data_object"
    step = result.steps[2]
    assert step.left_evidence[0].paper_id == left.id
    assert step.right_evidence[0].paper_id == right.id
    assert step.left_evidence[0].page_number == 3
    assert step.left_evidence[0].quote == "Original evidence for dataset_sample."
    assert all(not s.left_evidence and not s.right_evidence for s in result.steps[3:])


@pytest.mark.parametrize("stop,outcome,kind", [
    ("concept", "unrelated", None), ("variables", "candidate_gap", "variable"),
    ("method", "candidate_gap", "methodological"),
    ("research_problem", "candidate_gap", "problem_scope"), (None, "no_gap", None),
])
def test_first_terminal_controls_outcome(stop, outcome, kind):
    left, right = paper(), paper()
    result = validate_comparison(proposal(left, right, stop=stop), left, right, model_name="test")
    assert result.outcome == outcome
    assert result.stop_aspect == stop
    assert (result.candidate.kind if result.candidate else None) == kind


@pytest.mark.parametrize("failure", ["missing", "foreign_paper", "wrong_aspect", "reordered", "omitted", "insufficient"])
def test_unknown_or_invalid_evidence_never_produces_a_gap(failure):
    left, right = paper(), paper()
    value = proposal(left, right, stop="variables")
    if failure == "missing":
        value.steps[1].right_refs = []
    elif failure == "foreign_paper":
        value.steps[1].right_refs = value.steps[1].left_refs
    elif failure == "wrong_aspect":
        value.steps[1].right_refs = value.steps[2].right_refs
    elif failure == "reordered":
        value.steps[1], value.steps[2] = value.steps[2], value.steps[1]
    elif failure == "omitted":
        value.steps = value.steps[:1]
    else:
        value.steps[1].decision = "insufficient"
    result = validate_comparison(value, left, right, model_name="test")
    assert result.outcome == "insufficient_evidence"
    assert result.stop_aspect == "variables"
    assert result.candidate is None
    assert all(s.decision == "not_compared" for s in result.steps[2:])


def test_pair_stops_independently_of_other_pairs():
    a, b, c = paper(), paper(), paper()
    ab = validate_comparison(proposal(a, b, stop="data_object"), a, b, model_name="test")
    ac = validate_comparison(proposal(a, c, stop="method"), a, c, model_name="test")
    assert ab.steps[3].decision == "not_compared"
    assert ac.steps[3].decision == "no"


def test_no_concept_evidence_does_not_call_model(monkeypatch):
    left, right = paper(), paper()
    left.components = []
    monkeypatch.setattr("app.comparison_service.genai.Client", lambda **kw: pytest.fail("Unexpected model request"))
    result = compare_papers(left, right)
    assert result.outcome == "insufficient_evidence"
    assert result.model_name == "evidence-check"


def test_human_review_requires_an_explanation():
    for note in ("", "  ", "\n"):
        with pytest.raises(ValidationError):
            ComparisonReviewCreate(decision="accepted", note=note)
    with pytest.raises(ValidationError):
        ComparisonReviewCreate(decision="confirmed_novel", note="Unjustified")
    assert ComparisonReviewCreate(decision="accepted", note="  Check population  ").note == "Check population"


@pytest.mark.parametrize("method,path,body", [
    ("get", "", None), ("post", "", None),
    ("post", "/00000000-0000-0000-0000-000000000002/reviews", {"decision": "accepted", "note": "Review"}),
])
def test_comparison_endpoints_require_authentication(method, path, body):
    with TestClient(app) as client:
        response = client.request(method, "/api/v1/projects/00000000-0000-0000-0000-000000000001/comparisons" + path,
                                  **({"json": body} if body else {}))
    assert response.status_code == 401


@pytest.mark.anyio
async def test_repository_uses_user_jwt_and_forwards_only_project_id(monkeypatch):
    project_id = uuid4()
    calls = []

    def handler(request):
        calls.append(request)
        return httpx.Response(200, json={"project_id": str(project_id), "total_papers": 0,
                                        "ready_papers": 0, "expected_pairs": 0, "pairs": []})

    original = httpx.AsyncClient
    monkeypatch.setattr("app.comparison_repository.httpx.AsyncClient", lambda **kw: original(transport=httpx.MockTransport(handler)))
    result = await ComparisonRepository().get(AuthenticatedUser(id=uuid4(), access_token="test-owner-jwt"), project_id)
    assert result.expected_pairs == 0
    assert calls[0].headers["Authorization"] == "Bearer test-owner-jwt"
    assert calls[0].read().decode() == '{"p_project_id":"' + str(project_id) + '"}'


@pytest.mark.anyio
async def test_stale_or_other_project_pair_cannot_be_reviewed(monkeypatch):
    repository = ComparisonRepository()
    overview = SimpleNamespace(pairs=[])
    monkeypatch.setattr(repository, "get", AsyncMock(return_value=overview))
    rpc = AsyncMock()
    monkeypatch.setattr(repository, "_rpc", rpc)
    with pytest.raises(InvalidReviewError):
        await repository.review(AuthenticatedUser(id=uuid4(), access_token="owner"), uuid4(), uuid4(),
                                ComparisonReviewCreate(decision="accepted", note="Needs validation"))
    rpc.assert_not_called()


def test_other_owner_project_returns_404(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=uuid4(), access_token="account-b")
    monkeypatch.setattr("app.comparison_routes.comparison_repository.get", AsyncMock(side_effect=EntityNotFoundError("Not found")))
    try:
        with TestClient(app) as client:
            assert client.get(f"/api/v1/projects/{uuid4()}/comparisons").status_code == 404
    finally:
        app.dependency_overrides.clear()


def test_review_api_schedules_pairs_after_successful_bulk_review(monkeypatch):
    from app.schemas import BulkReviewAcceptResponse
    component_id = uuid4()
    user = AuthenticatedUser(id=uuid4(), access_token="review-owner")
    app.dependency_overrides[get_current_user] = lambda: user
    publish = AsyncMock()
    monkeypatch.setattr("app.main.queue_reviewed_comparisons", publish)
    monkeypatch.setattr("app.main.project_repository.accept_review_components",
                        AsyncMock(return_value=BulkReviewAcceptResponse(accepted_count=1)))
    try:
        with TestClient(app) as client:
            response = client.post("/api/v1/reviews/accept-all", json={"component_ids": [str(component_id)]})
        assert response.status_code == 200
        publish.assert_awaited_once_with(user, [component_id])
    finally:
        app.dependency_overrides.clear()
