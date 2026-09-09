import asyncio
import json
from uuid import uuid4

import httpx
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.ai_extraction import AiComponent, AiEvidence, AiPaperExtraction, verify_extraction
from app.auth import AuthenticatedUser
from app.main import app
from app.repository import EntityNotFoundError, SupabaseProjectRepository
from app.schemas import ExtractionParameter
from app.source_verification import (
    BibliographicMetadata, SourceReviewCreate, VerificationRequest,
    normalize_doi, verify_source,
)


DOI = "10.1234/example"
RECORD = {"DOI": DOI, "title": ["A Study"], "author": [{"given": "Ada", "family": "Lovelace"}],
          "published": {"date-parts": [[2024, 1, 1]]}, "container-title": ["Journal A"],
          "publisher": "Publisher A", "volume": "2", "issue": "1", "page": "10-20", "type": "journal-article"}


def _registry(monkeypatch, handler):
    real_client = httpx.AsyncClient
    monkeypatch.setattr("app.source_verification.httpx.AsyncClient", lambda **kwargs: real_client(transport=httpx.MockTransport(handler), **kwargs))


def test_registry_compares_every_field_without_approving_or_overwriting(monkeypatch):
    calls = []
    def handler(request):
        calls.append(request)
        return httpx.Response(200, json={"message": RECORD})
    _registry(monkeypatch, handler)
    local = BibliographicMetadata(title="An unrelated paper", doi=DOI, authors=["Ada Lovelace"], publication_year=2023)
    result = asyncio.run(verify_source(local))
    checks = {c.field: c for c in result.checks}
    assert result.status == "mismatch"
    assert checks["title"].status == "mismatch"
    assert checks["authors"].status == "match"
    assert checks["publication_year"].status == "mismatch"
    assert checks["publisher"].status == "missing_local"
    assert checks["publication_status"].status == "missing_source"
    assert len(checks) == 10
    assert local.title == "An unrelated paper"
    assert result.local_metadata.title == local.title
    assert result.source_metadata.pages == "10-20"
    assert len(calls) == 1 and calls[0].url.host == "api.crossref.org"
    assert not calls[0].content and "authorization" not in calls[0].headers


@pytest.mark.parametrize("value", [None, "", "http://127.0.0.1/private", "10.1234/a?url=secret", "10.1234/../admin", "10.1234/a\nb"])
def test_invalid_or_missing_doi_never_causes_network_request(monkeypatch, value):
    def forbidden(request):
        pytest.fail("Invalid DOI was sent to the network")
    _registry(monkeypatch, forbidden)
    result = asyncio.run(verify_source(BibliographicMetadata(), value))
    assert result.status == "unverifiable"
    assert result.sources == []


def test_normalize_doi_preserves_legitimate_suffix():
    assert normalize_doi("https://doi.org/10.1002/(SICI)1099-0844") == "10.1002/(sici)1099-0844"
    assert normalize_doi("DOI: 10.1234/ABC") == "10.1234/abc"


@pytest.mark.parametrize("failure", [404, 429, 503, "timeout", "malformed", "wrong_doi", "redirect"])
def test_unavailable_or_unreliable_registries_are_not_proof_of_fraud(monkeypatch, failure):
    calls = []
    def handler(request):
        calls.append(request)
        if failure == "timeout":
            raise httpx.ReadTimeout("timeout", request=request)
        if failure == "malformed":
            return httpx.Response(200, json={"message": []})
        if failure == "wrong_doi":
            return httpx.Response(200, json={"message": {**RECORD, "DOI": "10.1234/wrong"}})
        if failure == "redirect":
            return httpx.Response(302, headers={"location": "http://127.0.0.1/private"})
        return httpx.Response(failure)
    _registry(monkeypatch, handler)
    result = asyncio.run(verify_source(BibliographicMetadata(doi=DOI)))
    assert result.status == "unverifiable"
    assert len(calls) == 2
    assert all(c.url.host in {"api.crossref.org", "api.datacite.org"} for c in calls)
    assert all(c.status == "unverifiable" for c in result.checks)


def test_datacite_fallback_and_visibility_is_not_publication_status(monkeypatch):
    def handler(request):
        if request.url.host == "api.crossref.org":
            return httpx.Response(404)
        return httpx.Response(200, json={"data": {"attributes": {
            "doi": DOI, "titles": [{"title": "A Study"}], "creators": [{"name": "Ada Lovelace"}],
            "publicationYear": 2024, "publisher": {"name": "Repository A"}, "state": "findable",
        }}})
    _registry(monkeypatch, handler)
    report = asyncio.run(verify_source(BibliographicMetadata(doi=DOI, title="A Study")))
    assert [s.status for s in report.sources] == ["not_found", "found"]
    assert report.source_metadata.publisher == "Repository A"
    assert report.source_metadata.publication_status is None
    assert report.status == "incomplete"


def test_posted_content_is_not_assumed_to_be_a_preprint(monkeypatch):
    def handler(request):
        return httpx.Response(200, json={"message": {**RECORD, "type": "posted-content"}})
    _registry(monkeypatch, handler)
    report = asyncio.run(verify_source(BibliographicMetadata(doi=DOI)))
    assert report.source_metadata.publication_status is None


@pytest.mark.parametrize("operation", ["list", "verify", "review"])
def test_owner_check_precedes_registry_and_verification_access(monkeypatch, operation):
    repo = SupabaseProjectRepository()
    user = AuthenticatedUser(id=uuid4(), access_token="account-b")
    async def denied(*args):
        raise EntityNotFoundError("Paper not found")
    async def forbidden(*args):
        pytest.fail("Registry called for another owner's paper")
    monkeypatch.setattr(repo, "get_paper", denied)
    monkeypatch.setattr("app.repository.verify_source", forbidden)
    args = (user, uuid4(), uuid4())
    with pytest.raises(EntityNotFoundError):
        if operation == "list":
            asyncio.run(repo.list_source_verifications(*args))
        elif operation == "verify":
            asyncio.run(repo.create_source_verification(*args, VerificationRequest(doi=DOI)))
        else:
            asyncio.run(repo.review_source_verification(*args, uuid4(), SourceReviewCreate(decision="accept", note="Read source")))


def test_verification_routes_require_authentication():
    client = TestClient(app)
    path = f"/api/v1/projects/{uuid4()}/papers/{uuid4()}/source-verifications"
    assert client.get(path).status_code == 401
    assert client.post(path, json={"doi": DOI}).status_code == 401
    assert client.post(f"{path}/{uuid4()}/reviews", json={"decision": "accept", "note": "Checked"}).status_code == 401


def test_review_rejects_blank_note():
    with pytest.raises(ValidationError):
        SourceReviewCreate(decision="accept", note="   ")


@pytest.mark.parametrize("kind,label,quote", [
    ("table", "Table 2", "Table 2 reports accuracy 91%."),
    ("figure", "Figure 1", "Figure 1 shows the study design."),
    ("equation", "Equation (3)", "Equation (3) is y = ax + b."),
    ("equation", "(3)", "y = ax + b (3)"),
    ("result", None, "The accuracy was 91%."),
])
def test_evidence_kinds_and_source_hierarchy_are_grounded(kind, label, quote):
    block_id = uuid4()
    blocks = [{"id": uuid4(), "page_number": 1, "block_index": 0, "content": "2 Results\n2.1 Evaluation\n"},
              {"id": block_id, "page_number": 2, "block_index": 1, "content": quote}]
    extraction = AiPaperExtraction(components=[AiComponent(
        parameter=p, value="An extracted claim", confidence=.9,
        evidence=[AiEvidence(quote=quote, page_number=2, evidence_kind=kind, source_label=label)] if p == ExtractionParameter.RESULTS_FINDINGS else [],
    ) for p in ExtractionParameter])
    result = verify_extraction(extraction, blocks, "test")
    evidence = next(c for c in result.components if c.parameter == ExtractionParameter.RESULTS_FINDINGS).evidence[0]
    assert evidence.paper_block_id == block_id
    assert evidence.section == "2 Results" and evidence.subsection == "2.1 Evaluation"
    assert evidence.evidence_kind == kind and evidence.source_label == label


def test_fabricated_label_does_not_upgrade_text_and_wrong_page_is_discarded():
    quote = "This study reports an accuracy of 91%."
    extraction = AiPaperExtraction(components=[AiComponent(
        parameter=p, value="An extracted claim", confidence=.9,
        evidence=[AiEvidence(quote=quote, page_number=1, evidence_kind="table", source_label="Table 99"),
                  AiEvidence(quote=quote, page_number=2)],
    ) for p in ExtractionParameter])
    result = verify_extraction(extraction, [{"id": uuid4(), "page_number": 1, "block_index": 0, "content": quote}], "test")
    assert len(result.components[0].evidence) == 1
    assert result.components[0].evidence[0].evidence_kind == "text"
    assert result.components[0].evidence[0].source_label is None


def test_review_is_append_only_and_cannot_use_report_from_another_paper(monkeypatch):
    repo = SupabaseProjectRepository()
    user = AuthenticatedUser(id=uuid4(), access_token="account-a")
    calls = []
    async def owned(*args):
        return None
    monkeypatch.setattr(repo, "get_paper", owned)
    def handler(request):
        calls.append(request)
        return httpx.Response(200, json=[])
    _registry(monkeypatch, handler)
    with pytest.raises(EntityNotFoundError):
        asyncio.run(repo.review_source_verification(user, uuid4(), uuid4(), uuid4(), SourceReviewCreate(decision="reject", note="Mismatch")))
    assert len(calls) == 1 and calls[0].method == "GET"
    assert "paper_id" in calls[0].url.params and "id" in calls[0].url.params


def test_human_review_preserves_registry_report_and_records_authenticated_reviewer(monkeypatch):
    repo = SupabaseProjectRepository()
    user = AuthenticatedUser(id=uuid4(), access_token="account-a")
    report_id = uuid4()
    calls = []
    async def owned(*args):
        return None
    monkeypatch.setattr(repo, "get_paper", owned)
    def handler(request):
        calls.append(request)
        if request.method == "GET":
            return httpx.Response(200, json=[{"id": str(report_id)}])
        payload = json.loads(request.content)
        return httpx.Response(201, json=[{"id": str(uuid4()), "created_at": "2026-09-07T00:00:00Z", **payload}])
    _registry(monkeypatch, handler)
    result = asyncio.run(repo.review_source_verification(user, uuid4(), uuid4(), report_id, SourceReviewCreate(decision="accept", note="Compared to original PDF")))
    assert result.reviewer_id == user.id
    assert [r.method for r in calls] == ["GET", "POST"]
    assert calls[-1].url.path.endswith("/paper_source_reviews")
    assert json.loads(calls[-1].content)["verification_id"] == str(report_id)
    assert calls[-1].headers["authorization"] == "Bearer account-a"


def test_worker_persists_extended_metadata_and_source_locators(monkeypatch):
    from app.ai_extraction import AiPaperMetadata, VerifiedComponent, VerifiedEvidence, VerifiedPaperExtraction
    from app.processing_repository import PdfProcessingRepository
    from app.schemas import EvidenceKind
    repo = PdfProcessingRepository.__new__(PdfProcessingRepository)
    repo._rest_url, repo._service_key = "http://supabase.test/rest/v1", "test-worker-key"
    calls = []
    component_id, block_id = uuid4(), uuid4()
    def handler(request):
        calls.append(request)
        if request.url.path.endswith("/extracted_components"):
            return httpx.Response(201, json=[{"id": str(component_id), "parameter": "results_findings"}])
        return httpx.Response(204)
    original = httpx.Client
    monkeypatch.setattr("app.processing_repository.httpx.Client", lambda **kw: original(transport=httpx.MockTransport(handler), **kw))
    extraction = VerifiedPaperExtraction(metadata=AiPaperMetadata(publisher="Publisher A", volume="2", issue="1", pages="10-20", publication_status="preprint"),
        components=(VerifiedComponent(parameter=ExtractionParameter.RESULTS_FINDINGS, value="Results", confidence=.8,
            evidence=(VerifiedEvidence(paper_block_id=block_id, quote="Table 2 reports 91%.", page_number=3,
                evidence_kind=EvidenceKind.TABLE, source_label="Table 2", section="2 Results", subsection="2.1 Evaluation"),)),), model_name="test")
    repo.save_ai_extraction(job_id=uuid4(), paper_id=uuid4(), extraction=extraction)
    span = json.loads(calls[1].content)[0]
    assert span["paper_block_id"] == str(block_id) and span["source_label"] == "Table 2"
    assert span["evidence_kind"] == "table" and span["subsection"] == "2.1 Evaluation"
    assert calls[2].url.path.endswith("/activate_analysis_components")
    paper_update = json.loads(calls[-1].content)
    assert paper_update["pages"] == "10-20" and paper_update["publication_status"] == "preprint"
    assert paper_update["metadata_verified"] is False
