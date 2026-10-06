from enum import StrEnum

class NodeType(StrEnum):
    PAPER = "paper"
    CONCEPT = "concept"
    RESEARCH_GAP = "research_gap"
    VARIABLE = "variable"
    METHOD = "method"
    RESULT = "result"

class GapType(StrEnum):
    UNEXPLORED_CONCEPT = "unexplored_concept"
    MISSING_RELATION = "missing_relation"
    METHODOLOGICAL = "methodological"
    POPULATION_GAP = "population_gap"
    DATASET_GAP = "dataset_gap"
    EMPIRICAL_GAP = "empirical_gap"

class SaturationStatus(StrEnum):
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    NONE = "none"

class EdgeType(StrEnum):
    USES = "uses"
    PRODUCES = "produces"
    REVEALS = "reveals"
    RELATES_TO = "relates_to"
    SUPPORTS = "supports"
    MENTIONED_IN = "mentioned_in"
