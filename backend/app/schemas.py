from datetime import datetime
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, Field, model_validator


class ProjectStatus(StrEnum):
    READY = "ready"
    PROCESSING = "processing"
    NEEDS_REVIEW = "needs_review"


class PaperSource(StrEnum):
    UPLOAD = "upload"
    DOI = "doi"


class PaperStatus(StrEnum):
    VALIDATING = "validating"
    READY = "ready"
    PROCESSING = "processing"
    NEEDS_REVIEW = "needs_review"
    FAILED = "failed"


class JobStatus(StrEnum):
    QUEUED = "queued"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class VerificationStatus(StrEnum):
    NEEDS_REVIEW = "needs_review"
    VERIFIED = "verified"
    EDITED = "edited"
    UNSUPPORTED = "unsupported"
    REJECTED = "rejected"


class ReviewerAction(StrEnum):
    ACCEPT = "accept"
    EDIT = "edit"
    REJECT = "reject"
    REQUEST_REANALYSIS = "request_reanalysis"


class ExtractionParameter(StrEnum):
    RESEARCH_PROBLEM = "research_problem"
    RESEARCH_OBJECTIVE = "research_objective"
    RESEARCH_QUESTION = "research_question"
    METHODOLOGY = "methodology"
    DATASET_SAMPLE = "dataset_sample"
    VARIABLES_CONCEPTS = "variables_concepts"
    RESULTS_FINDINGS = "results_findings"
    CONTRIBUTION = "contribution"
    LIMITATIONS = "limitations"
    FUTURE_WORK = "future_work"
    KEY_CLAIMS = "key_claims"


class ProjectCreate(BaseModel):
    title: str = Field(min_length=3, max_length=180)
    description: str = Field(default="", max_length=2_000)


class ProjectRead(ProjectCreate):
    id: UUID
    status: ProjectStatus
    paper_count: int = 0
    created_at: datetime
    updated_at: datetime


class PaperCreate(BaseModel):
    source: PaperSource
    original_filename: str | None = Field(default=None, max_length=255)
    storage_key: str | None = Field(default=None, max_length=600)
    doi: str | None = Field(default=None, max_length=255)

    @model_validator(mode="after")
    def validate_source_fields(self) -> "PaperCreate":
        if self.source == PaperSource.UPLOAD and not self.storage_key:
            raise ValueError("storage_key is required for uploaded papers")
        if self.source == PaperSource.DOI and not self.doi:
            raise ValueError("doi is required for DOI papers")
        return self


class PaperRead(PaperCreate):
    id: UUID
    project_id: UUID
    status: PaperStatus
    title: str | None = None
    authors: list[str] = Field(default_factory=list)
    publication_year: int | None = None
    journal: str | None = None
    created_at: datetime


class AnalysisJobCreate(BaseModel):
    paper_ids: list[UUID] = Field(min_length=1, max_length=25)
    parameters: list[ExtractionParameter] = Field(
        default_factory=lambda: [
            ExtractionParameter.RESEARCH_PROBLEM,
            ExtractionParameter.RESEARCH_OBJECTIVE,
            ExtractionParameter.METHODOLOGY,
            ExtractionParameter.RESULTS_FINDINGS,
            ExtractionParameter.LIMITATIONS,
        ],
        min_length=1,
    )


class AnalysisJobRead(AnalysisJobCreate):
    id: UUID
    project_id: UUID
    status: JobStatus
    stage: str
    progress: float = Field(ge=0, le=1)
    error_message: str | None = None
    created_at: datetime
    updated_at: datetime


class EvidenceSpan(BaseModel):
    quote: str = Field(min_length=1)
    page_number: int = Field(ge=1)
    section: str | None = None
    subsection: str | None = None
    block_id: str
    bounding_box: tuple[float, float, float, float] | None = None


class ExtractedComponentRead(BaseModel):
    id: UUID
    paper_id: UUID
    parameter: ExtractionParameter
    ai_value: str
    final_value: str | None = None
    status: VerificationStatus
    confidence: float | None = Field(default=None, ge=0, le=1)
    evidence: list[EvidenceSpan]
    model_name: str
    prompt_version: str
    created_at: datetime


class ReviewRecordCreate(BaseModel):
    component_id: UUID
    action: ReviewerAction
    corrected_value: str | None = None
    note: str | None = Field(default=None, max_length=2_000)

    @model_validator(mode="after")
    def require_correction_for_edit(self) -> "ReviewRecordCreate":
        if self.action == ReviewerAction.EDIT and not self.corrected_value:
            raise ValueError("corrected_value is required for edit actions")
        return self


class ReviewRecordRead(ReviewRecordCreate):
    id: UUID
    reviewer_id: UUID
    created_at: datetime


class HealthRead(BaseModel):
    status: str
    service: str
    version: str
