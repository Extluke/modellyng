from __future__ import annotations

import re

from .schemas import (
    ExtractedComponentRead,
    MethodologyTableRow,
    ResearchQuestionTableRow,
    StructuredPaperTablesRead,
)


def build_structured_tables(
    components: list[ExtractedComponentRead],
) -> StructuredPaperTablesRead:
    """Build readable tables from the active, human-reviewable component set.

    The transformation is deterministic. It never adds scientific claims; it
    only aligns reviewed values that already exist in the same paper result.
    """

    by_parameter = {component.parameter.value: component for component in components}
    questions_component = by_parameter.get("research_question")
    questions = _split_items(_display_value(questions_component))
    objects = _split_items(_display_value(by_parameter.get("variables_concepts")))
    directions = _split_items(_display_value(by_parameter.get("research_objective")))

    research_questions: list[ResearchQuestionTableRow] = []
    for index, question in enumerate(questions):
        evidence = (
            questions_component.evidence[min(index, len(questions_component.evidence) - 1)]
            if questions_component and questions_component.evidence
            else None
        )
        research_questions.append(
            ResearchQuestionTableRow(
                number=index + 1,
                question=question,
                related_object=_aligned_value(objects, index, "Belum dinyatakan"),
                discussion_direction=_aligned_value(
                    directions, index, "Belum dinyatakan"
                ),
                evidence_page=evidence.page_number if evidence else None,
                evidence_quote=evidence.quote if evidence else None,
            )
        )

    methodology_text = _display_value(by_parameter.get("methodology"))
    methodology = []
    if methodology_text:
        methodology.append(
            MethodologyTableRow(
                content=methodology_text,
                form=_infer_method_form(methodology_text),
                main_activity=_display_value(by_parameter.get("dataset_sample"))
                or "Belum dinyatakan",
                activity_direction=_display_value(
                    by_parameter.get("variables_concepts")
                )
                or "Belum dinyatakan",
                final_goal=_display_value(by_parameter.get("research_objective"))
                or "Belum dinyatakan",
            )
        )

    return StructuredPaperTablesRead(
        research_questions=research_questions,
        methodology=methodology,
    )


def _display_value(component: ExtractedComponentRead | None) -> str:
    if component is None:
        return ""
    return " ".join((component.final_value or component.ai_value).split()).strip()


def _split_items(value: str) -> list[str]:
    if not value:
        return []
    normalized = re.sub(r"\s*[•●▪]\s*", "\n", value)
    normalized = re.sub(r"(?:^|\n)\s*\d+[.)]\s*", "\n", normalized)
    if "?" in normalized:
        raw_items = re.split(r"(?<=\?)\s+|\n+", normalized)
    else:
        raw_items = re.split(r"\n+|\s*;\s*", normalized)
    items = [" ".join(item.strip(" -\t").split()) for item in raw_items]
    return [item for item in items if item]


def _aligned_value(values: list[str], index: int, fallback: str) -> str:
    if not values:
        return fallback
    return values[min(index, len(values) - 1)]


def _infer_method_form(methodology: str) -> str:
    lowered = methodology.lower()
    patterns = (
        (("systematic review", "systematic literature", "slr"), "Systematic review"),
        (("literature review", "tinjauan pustaka"), "Literature review"),
        (("case study", "studi kasus"), "Studi kasus"),
        (("experiment", "eksperimen", "experimental"), "Eksperimen"),
        (("survey", "survei", "questionnaire", "kuesioner"), "Survei"),
        (("qualitative", "kualitatif", "interview", "wawancara"), "Kualitatif"),
        (("quantitative", "kuantitatif", "regression", "statistical"), "Kuantitatif"),
        (("simulation", "simulasi"), "Simulasi"),
    )
    matches = [label for keywords, label in patterns if any(k in lowered for k in keywords)]
    return " / ".join(dict.fromkeys(matches)) if matches else "Metode dijelaskan naratif"
