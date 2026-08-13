from .celery_app import celery_app


PIPELINE_STAGES = (
    "validate_file_and_metadata",
    "extract_layout_and_sections",
    "extract_research_components",
    "match_claims_to_evidence",
    "generate_comparative_synthesis",
    "detect_candidate_gaps",
)


@celery_app.task(name="modellyng.run_analysis", bind=True)
def run_analysis(self, job_id: str) -> dict[str, object]:
    """Worker entry point.

    Document parsers and AI providers are deliberately injected in the next
    vertical slice. Keeping one explicit task boundary prevents long-running
    analysis from blocking API requests.
    """

    for index, stage in enumerate(PIPELINE_STAGES, start=1):
        self.update_state(
            state="PROGRESS",
            meta={"job_id": job_id, "stage": stage, "progress": index / 6},
        )
    return {"job_id": job_id, "status": "pipeline_contract_ready"}
