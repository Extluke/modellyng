from uuid import UUID

from .ai_extraction import extract_academic_components
from .celery_app import celery_app
from .pdf_processing import extract_pdf
from .processing_repository import PdfProcessingRepository


@celery_app.task(name="modellyng.process_pdf", bind=True)
def process_pdf(self, job_id: str, paper_id: str) -> dict[str, object]:
    """Download, parse, and persist one private PDF outside the API process."""
    parsed_job_id = UUID(job_id)
    parsed_paper_id = UUID(paper_id)
    repository = PdfProcessingRepository()
    project_id: UUID | None = None

    try:
        self.update_state(
            state="PROGRESS",
            meta={"job_id": job_id, "stage": "downloading", "progress": 0.1},
        )
        repository.update_job(
            parsed_job_id,
            status="processing",
            stage="downloading",
            progress=0.1,
        )
        paper = repository.get_paper(parsed_paper_id)
        project_id = UUID(str(paper["project_id"]))
        repository.update_paper_status(parsed_paper_id, "processing")
        repository.update_project_status(project_id, "processing")

        content = repository.download_pdf(str(paper["storage_key"]))
        self.update_state(
            state="PROGRESS",
            meta={"job_id": job_id, "stage": "extracting_text", "progress": 0.45},
        )
        repository.update_job(
            parsed_job_id,
            status="processing",
            stage="extracting_text",
            progress=0.45,
        )
        extraction = extract_pdf(content)

        self.update_state(
            state="PROGRESS",
            meta={"job_id": job_id, "stage": "saving_blocks", "progress": 0.8},
        )
        repository.update_job(
            parsed_job_id,
            status="processing",
            stage="saving_blocks",
            progress=0.8,
        )
        repository.save_extraction(parsed_paper_id, extraction)

        self.update_state(
            state="PROGRESS",
            meta={"job_id": job_id, "stage": "gemini_extraction", "progress": 0.85},
        )
        repository.update_job(
            parsed_job_id,
            status="processing",
            stage="gemini_extraction",
            progress=0.85,
        )
        blocks = repository.get_blocks(parsed_paper_id)
        ai_extraction = extract_academic_components(blocks)

        self.update_state(
            state="PROGRESS",
            meta={"job_id": job_id, "stage": "saving_ai_results", "progress": 0.95},
        )
        repository.update_job(
            parsed_job_id,
            status="processing",
            stage="saving_ai_results",
            progress=0.95,
        )
        repository.save_ai_extraction(
            job_id=parsed_job_id,
            paper_id=parsed_paper_id,
            extraction=ai_extraction,
        )
        repository.update_project_status(project_id, "needs_review")
        repository.update_job(
            parsed_job_id,
            status="completed",
            stage="ai_extraction_complete",
            progress=1,
        )
        return {
            "job_id": job_id,
            "paper_id": paper_id,
            "status": "needs_review",
            "page_count": extraction.page_count,
            "text_blocks": len(extraction.pages),
            "components": len(ai_extraction.components),
        }
    except Exception as exc:
        repository.mark_failure(
            job_id=parsed_job_id,
            paper_id=parsed_paper_id,
            project_id=project_id,
            message=str(exc) or "Pemrosesan PDF gagal",
        )
        raise
