from uuid import UUID

import httpx

from app.ai_extraction import (
    AiPaperMetadata,
    VerifiedComponent,
    VerifiedPaperExtraction,
)
from app.processing_repository import PdfProcessingRepository
from app.schemas import ExtractionParameter


def test_worker_activates_new_version_only_after_result_is_saved(monkeypatch) -> None:
    repository = PdfProcessingRepository.__new__(PdfProcessingRepository)
    repository._rest_url = "http://supabase.test/rest/v1"
    repository._storage_url = "http://supabase.test/storage/v1"
    repository._service_key = "service-key"
    repository._storage_bucket = "private-papers"
    job_id = UUID("00000000-0000-0000-0000-000000000010")
    paper_id = UUID("00000000-0000-0000-0000-000000000020")
    calls: list[tuple[str, str, dict]] = []

    class FakeClient:
        def __init__(self, *args, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def post(self, url, **kwargs):
            calls.append(("post", url, kwargs))
            if url.endswith("/extracted_components"):
                return httpx.Response(
                    201,
                    json=[
                        {
                            "id": "00000000-0000-0000-0000-000000000030",
                            "parameter": "methodology",
                        }
                    ],
                    request=httpx.Request("POST", url),
                )
            return httpx.Response(204, request=httpx.Request("POST", url))

        def patch(self, url, **kwargs):
            calls.append(("patch", url, kwargs))
            return httpx.Response(204, request=httpx.Request("PATCH", url))

    monkeypatch.setattr("app.processing_repository.httpx.Client", FakeClient)
    extraction = VerifiedPaperExtraction(
        metadata=AiPaperMetadata(),
        components=(
            VerifiedComponent(
                parameter=ExtractionParameter.METHODOLOGY,
                value="Experiment",
                confidence=0.9,
                evidence=(),
            ),
        ),
        model_name="gemini-test",
    )

    repository.save_ai_extraction(
        job_id=job_id,
        paper_id=paper_id,
        extraction=extraction,
    )

    component_call = calls[0]
    assert component_call[2]["json"][0]["is_active"] is False
    assert calls[1][1].endswith("/rpc/activate_analysis_components")
    assert calls[1][2]["json"] == {
        "p_job_id": str(job_id),
        "p_paper_id": str(paper_id),
    }
    assert calls[2][0] == "patch"
