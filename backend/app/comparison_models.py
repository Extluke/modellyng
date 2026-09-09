"""Shared, explicit contracts for evidence-grounded, ordered paper comparisons."""
from datetime import datetime
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, Field, field_validator

from .schemas import EvidenceSpan


class Aspect(StrEnum):
    CONCEPT = "concept"
    VARIABLES = "variables"
    DATA = "data_object"
    METHOD = "method"
    PROBLEM = "research_problem"


ASPECTS = tuple(Aspect)
ASPECT_PARAMETERS = {
    Aspect.CONCEPT: {"variables_concepts", "research_problem", "research_objective", "research_question"},
    Aspect.VARIABLES: {"variables_concepts"},
    Aspect.DATA: {"dataset_sample"},
    Aspect.METHOD: {"methodology"},
    Aspect.PROBLEM: {"research_problem"},
}
PROMPT_VERSION = "cross-paper-v1"


class Decision(StrEnum):
    YES = "yes"
    NO = "no"
    INSUFFICIENT = "insufficient"
    NOT_COMPARED = "not_compared"


class Outcome(StrEnum):
    CANDIDATE = "candidate_gap"
    UNRELATED = "unrelated"
    INSUFFICIENT = "insufficient_evidence"
    NO_GAP = "no_gap"


class ComparisonEvidence(EvidenceSpan):
    ref: UUID
    component_id: UUID
    paper_id: UUID
    parameter: str


class ComparisonComponent(BaseModel):
    id: UUID
    parameter: str
    value: str
    evidence: list[ComparisonEvidence] = Field(default_factory=list)


class ComparisonPaper(BaseModel):
    id: UUID
    title: str
    components: list[ComparisonComponent] = Field(default_factory=list)


class ComparisonStep(BaseModel):
    aspect: Aspect
    decision: Decision
    reason: str
    left_evidence: list[ComparisonEvidence] = Field(default_factory=list)
    right_evidence: list[ComparisonEvidence] = Field(default_factory=list)


class GapCandidate(BaseModel):
    kind: str
    summary: str
    validation_question: str


class ComparisonResult(BaseModel):
    steps: list[ComparisonStep] = Field(min_length=5, max_length=5)
    outcome: Outcome
    stop_aspect: Aspect | None = None
    candidate: GapCandidate | None = None
    model_name: str
    prompt_version: str = PROMPT_VERSION


class ComparisonReviewCreate(BaseModel):
    decision: str = Field(pattern=r"^(accepted|rejected)$")
    note: str = Field(min_length=1, max_length=2000)

    @field_validator("note")
    @classmethod
    def meaningful_note(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Alasan review harus diisi")
        return value.strip()


class ComparisonReviewRead(ComparisonReviewCreate):
    id: UUID
    pair_id: UUID
    reviewer_id: UUID
    created_at: datetime


class ComparisonPairRead(BaseModel):
    id: UUID
    project_id: UUID
    left_paper_id: UUID
    right_paper_id: UUID
    left_source: ComparisonPaper
    right_source: ComparisonPaper
    status: str = Field(pattern=r"^(queued|processing|completed|failed)$")
    result: ComparisonResult | None = None
    error_message: str | None = None
    updated_at: datetime
    reviews: list[ComparisonReviewRead] = Field(default_factory=list)


class ComparisonOverview(BaseModel):
    project_id: UUID
    total_papers: int = Field(ge=0)
    ready_papers: int = Field(ge=0)
    expected_pairs: int = Field(ge=0)
    pairs: list[ComparisonPairRead] = Field(default_factory=list)
    dispatch_warning: str | None = None
