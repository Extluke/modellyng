from __future__ import annotations

from urllib.parse import quote
from uuid import UUID

import httpx

from .ai_extraction import VerifiedPaperExtraction
from .config import get_settings
from .pdf_processing import ExtractedPdf


class ProcessingRepositoryError(RuntimeError):
    pass


class PdfProcessingRepository:
    """Service-role data adapter used only by the trusted Celery worker."""

    def __init__(self) -> None:
        settings = get_settings()
        self._rest_url = f"{settings.supabase_url}/rest/v1"
        self._storage_url = f"{settings.supabase_url}/storage/v1"
        self._service_key = settings.supabase_service_role_key
        self._storage_bucket = settings.object_storage_bucket
        if not self._service_key.strip():
            raise ProcessingRepositoryError(
                "MODELLYNG_SUPABASE_SERVICE_ROLE_KEY wajib diisi untuk worker"
            )

    @property
    def _headers(self) -> dict[str, str]:
        return {
            "apikey": self._service_key,
            "Authorization": f"Bearer {self._service_key}",
        }

    def get_paper(self, paper_id: UUID) -> dict[str, object]:
        with httpx.Client(timeout=15.0) as client:
            response = client.get(
                f"{self._rest_url}/papers",
                headers=self._headers,
                params={
                    "select": (
                        "id,project_id,storage_key,original_filename,status,"
                        "projects(owner_id)"
                    ),
                    "id": f"eq.{paper_id}",
                    "limit": "1",
                },
            )
        self._raise_for_error(response)
        rows = response.json()
        if not rows:
            raise ProcessingRepositoryError("Paper tidak ditemukan")

        paper = rows[0]
        project = paper.get("projects") or {}
        owner_id = str(project.get("owner_id") or "")
        expected_prefix = f"{owner_id}/{paper['project_id']}/"
        storage_key = str(paper.get("storage_key") or "")
        if not owner_id or not storage_key.startswith(expected_prefix):
            raise ProcessingRepositoryError(
                "Lokasi penyimpanan PDF tidak sesuai dengan pemilik proyek"
            )
        return paper

    def download_pdf(self, storage_key: str) -> bytes:
        encoded_path = quote(storage_key, safe="/")
        with httpx.Client(timeout=60.0) as client:
            response = client.get(
                f"{self._storage_url}/object/authenticated/"
                f"{self._storage_bucket}/{encoded_path}",
                headers=self._headers,
            )
        self._raise_for_error(response)
        return response.content

    def update_job(
        self,
        job_id: UUID,
        *,
        status: str,
        stage: str,
        progress: float,
        error_message: str | None = None,
    ) -> None:
        with httpx.Client(timeout=15.0) as client:
            response = client.patch(
                f"{self._rest_url}/analysis_jobs",
                headers={**self._headers, "Prefer": "return=minimal"},
                params={"id": f"eq.{job_id}"},
                json={
                    "status": status,
                    "stage": stage,
                    "progress": progress,
                    "error_message": error_message,
                },
            )
        self._raise_for_error(response)

    def update_paper_status(self, paper_id: UUID, status: str) -> None:
        self._patch("papers", paper_id, {"status": status})

    def update_project_status(self, project_id: UUID, status: str) -> None:
        self._patch("projects", project_id, {"status": status})

    def save_extraction(self, paper_id: UUID, extraction: ExtractedPdf) -> None:
        blocks: list[dict[str, object]] = []
        block_index = 0
        for page in extraction.pages:
            for text_chunk in self._split_text(page.text):
                blocks.append(
                    {
                        "paper_id": str(paper_id),
                        "block_index": block_index,
                        "page_number": page.page_number,
                        "content": text_chunk,
                    }
                )
                block_index += 1

        with httpx.Client(timeout=60.0) as client:
            for start in range(0, len(blocks), 100):
                response = client.post(
                    f"{self._rest_url}/paper_blocks",
                    headers={
                        **self._headers,
                        "Prefer": "resolution=merge-duplicates,return=minimal",
                    },
                    params={"on_conflict": "paper_id,block_index"},
                    json=blocks[start : start + 100],
                )
                self._raise_for_error(response)

        paper_update: dict[str, object] = {
            "page_count": extraction.page_count,
            "language_code": extraction.language_code,
            "status": "processing",
        }
        if extraction.title:
            paper_update["title"] = extraction.title
        if extraction.authors:
            paper_update["authors"] = list(extraction.authors)
        self._patch("papers", paper_id, paper_update)

    def get_blocks(self, paper_id: UUID) -> list[dict[str, object]]:
        with httpx.Client(timeout=30.0) as client:
            response = client.get(
                f"{self._rest_url}/paper_blocks",
                headers=self._headers,
                params={
                    "select": "id,block_index,page_number,section,subsection,content",
                    "paper_id": f"eq.{paper_id}",
                    "order": "block_index.asc",
                },
            )
        self._raise_for_error(response)
        return response.json()

    def save_ai_extraction(
        self,
        *,
        job_id: UUID,
        paper_id: UUID,
        extraction: VerifiedPaperExtraction,
    ) -> None:
        component_rows = [
            {
                "paper_id": str(paper_id),
                "analysis_job_id": str(job_id),
                "parameter": component.parameter.value,
                "ai_value": component.value,
                "status": "needs_review",
                "confidence": component.confidence,
                "model_name": extraction.model_name,
                "prompt_version": extraction.prompt_version,
                "is_active": False,
            }
            for component in extraction.components
        ]
        with httpx.Client(timeout=60.0) as client:
            response = client.post(
                f"{self._rest_url}/extracted_components",
                headers={
                    **self._headers,
                    "Prefer": "resolution=merge-duplicates,return=representation",
                },
                params={"on_conflict": "analysis_job_id,paper_id,parameter"},
                json=component_rows,
            )
        self._raise_for_error(response)
        saved_components = response.json()
        component_ids = {
            row["parameter"]: row["id"] for row in saved_components
        }

        evidence_rows: list[dict[str, object]] = []
        for component in extraction.components:
            component_id = component_ids.get(component.parameter.value)
            if not component_id:
                continue
            for evidence in component.evidence:
                evidence_rows.append(
                    {
                        "component_id": component_id,
                        "paper_block_id": str(evidence.paper_block_id),
                        "quote": evidence.quote,
                        "page_number": evidence.page_number,
                    }
                )
        if evidence_rows:
            with httpx.Client(timeout=60.0) as client:
                response = client.post(
                    f"{self._rest_url}/evidence_spans",
                    headers={**self._headers, "Prefer": "return=minimal"},
                    json=evidence_rows,
                )
            self._raise_for_error(response)

        # Activate the complete new result only after both components and
        # evidence have been persisted. The database function switches the
        # version atomically while retaining older rows for audit history.
        with httpx.Client(timeout=30.0) as client:
            response = client.post(
                f"{self._rest_url}/rpc/activate_analysis_components",
                headers={**self._headers, "Prefer": "return=minimal"},
                json={"p_job_id": str(job_id), "p_paper_id": str(paper_id)},
            )
        self._raise_for_error(response)

        metadata = extraction.metadata
        paper_update: dict[str, object] = {"status": "needs_review"}
        if metadata.title:
            paper_update["title"] = metadata.title
        if metadata.authors:
            paper_update["authors"] = metadata.authors
        if metadata.publication_year:
            paper_update["publication_year"] = metadata.publication_year
        if metadata.journal:
            paper_update["journal"] = metadata.journal
        if metadata.doi:
            paper_update["doi"] = metadata.doi
        self._patch("papers", paper_id, paper_update)

    def mark_failure(
        self,
        *,
        job_id: UUID,
        paper_id: UUID,
        project_id: UUID | None,
        message: str,
    ) -> None:
        safe_message = " ".join(message.split())[:1_000]
        try:
            self.update_job(
                job_id,
                status="failed",
                stage="failed",
                progress=1,
                error_message=safe_message,
            )
            self.update_paper_status(paper_id, "failed")
            if project_id:
                self.update_project_status(project_id, "needs_review")
        except Exception:
            # Failure persistence is best-effort. Never replace the original
            # pipeline exception with a secondary status-update exception.
            pass

    def _patch(self, table: str, record_id: UUID, payload: dict[str, object]) -> None:
        with httpx.Client(timeout=15.0) as client:
            response = client.patch(
                f"{self._rest_url}/{table}",
                headers={**self._headers, "Prefer": "return=minimal"},
                params={"id": f"eq.{record_id}"},
                json=payload,
            )
        self._raise_for_error(response)

    @staticmethod
    def _split_text(text: str, limit: int = 8_000) -> list[str]:
        if len(text) <= limit:
            return [text]
        chunks: list[str] = []
        remaining = text
        while remaining:
            split_at = min(limit, len(remaining))
            if split_at < len(remaining):
                paragraph_break = remaining.rfind("\n", 0, split_at)
                if paragraph_break > limit // 2:
                    split_at = paragraph_break
            chunk = remaining[:split_at].strip()
            if chunk:
                chunks.append(chunk)
            remaining = remaining[split_at:].lstrip()
        return chunks

    @staticmethod
    def _raise_for_error(response: httpx.Response) -> None:
        if response.is_success:
            return
        try:
            payload = response.json()
            detail = (
                payload.get("message")
                or payload.get("error")
                or payload.get("details")
                or response.text
            )
        except (ValueError, AttributeError):
            detail = response.text
        raise ProcessingRepositoryError(f"Supabase worker request gagal: {detail}")
