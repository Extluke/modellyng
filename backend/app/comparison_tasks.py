from uuid import UUID, uuid4

import httpx

from .celery_app import celery_app
from .comparison_models import ComparisonPaper
from .comparison_service import compare_papers
from .config import get_settings


@celery_app.task(name="modellyng.analyze_paper_pair", bind=True, max_retries=2,
                 rate_limit="6/m", soft_time_limit=300, time_limit=330)
def analyze_paper_pair(self, pair_id: str) -> dict:
    pair_id = str(UUID(pair_id))
    token = str(uuid4())
    settings = get_settings()
    if not settings.supabase_service_role_key:
        raise RuntimeError("Worker database credentials are not configured")
    headers = {"apikey": settings.supabase_service_role_key,
               "Authorization": f"Bearer {settings.supabase_service_role_key}",
               "Prefer": "return=representation"}
    base = f"{settings.supabase_url.rstrip('/')}/rest/v1"
    with httpx.Client(timeout=30, headers=headers) as client:
        try:
            response = client.post(f"{base}/rpc/claim_paper_comparison", json={"p_pair_id": pair_id, "p_token": token})
            response.raise_for_status()
        except httpx.HTTPError:
            raise self.retry(exc=RuntimeError("Comparison database unavailable"), countdown=30)
        rows = response.json()
        if not rows:
            return {"id": pair_id, "status": "skipped"}
        row = rows[0]
        try:
            result = compare_papers(ComparisonPaper.model_validate(row["left_source"]),
                                    ComparisonPaper.model_validate(row["right_source"]))
            update = {"status": "completed", "result": result.model_dump(mode="json"), "error_message": None}
        except Exception:
            retry = self.request.retries < self.max_retries
            update = {"status": "queued" if retry else "failed", "result": None,
                      "error_message": "Perbandingan gagal. Periksa ketersediaan/kuota Gemini dan worker, lalu coba lagi."}
        try:
            saved = client.patch(f"{base}/paper_comparisons",
                                 params={"id": f"eq.{pair_id}", "claim_token": f"eq.{token}", "status": "eq.processing"},
                                 json=update)
            saved.raise_for_status()
        except httpx.HTTPError:
            # A retry after the lease expires can recover an interrupted write.
            raise self.retry(exc=RuntimeError("Comparison result could not be saved"), countdown=610)
        if update["status"] == "queued":
            raise self.retry(exc=RuntimeError("Comparison model temporarily unavailable"), countdown=30 * (2 ** self.request.retries))
        return {"id": pair_id, "status": update["status"]}
