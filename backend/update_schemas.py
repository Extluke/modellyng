import sys

with open('app/schemas.py', 'r', encoding='utf-8') as f:
    content = f.read()

# Normalize line endings to LF for easier replacement
content = content.replace('\r\n', '\n')

old_gap = """class GapType(StrEnum):
    POPULATION = "population"
    METHODOLOGICAL = "methodological"
    EMPIRICAL = "empirical"
    THEORETICAL = "theoretical"
    CONCEPTUAL = "conceptual"
    OTHER = "other\""""

new_gap = """class GapType(StrEnum):
    POPULATION = "population"
    METHODOLOGICAL = "methodological"
    EMPIRICAL = "empirical"
    THEORETICAL = "theoretical"
    CONCEPTUAL = "conceptual"
    UNEXPLORED_CONCEPT = "unexplored_concept"
    MISSING_RELATION = "missing_relation"
    DATASET = "dataset"
    OTHER = "other\""""

if old_gap in content:
    content = content.replace(old_gap, new_gap)
else:
    print("GapType not found")

old_edge = """class ConceptMapEdgeRead(BaseModel):
    source: str
    target: str
    relation: str"""

new_schemas = """class ConceptMapEdgeRead(BaseModel):
    source: str
    target: str
    relation: str


class SaturationStatus(StrEnum):
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    NONE = "none"


class KnowledgeGraphEvidence(BaseModel):
    paper_title: str
    section: str | None = None
    quote: str
    paper_id: UUID | None = None


class KnowledgeGraphNodeRead(BaseModel):
    id: str
    kind: str
    label: str
    detail: str
    parent_id: str | None = None
    gap_typology: GapType | None = None
    saturation_status: SaturationStatus | None = None
    confidence_score: float | None = Field(default=None, ge=0, le=1)
    zone_category: str | None = None
    x: float | None = None
    y: float | None = None
    evidence: list[KnowledgeGraphEvidence] = Field(default_factory=list)
    status: VerificationStatus | None = None


class KnowledgeGraphEdgeRead(BaseModel):
    source: str
    target: str
    relation: str
    detail: str | None = None"""

if old_edge in content:
    content = content.replace(old_edge, new_schemas)
else:
    print("ConceptMapEdgeRead not found")

with open('app/schemas.py', 'w', encoding='utf-8') as f:
    f.write(content)

print("Schemas updated successfully.")
