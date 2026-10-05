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
    objects_raw = _display_value(by_parameter.get("variables_concepts"))
    directions_raw = _display_value(by_parameter.get("research_objective"))
    directions = _split_items(directions_raw)

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
                related_object=objects_raw or "Belum dinyatakan",
                discussion_direction=_aligned_value(
                    directions, index, "Belum dinyatakan"
                ),
                evidence_page=evidence.page_number if evidence else None,
                evidence_quote=evidence.quote if evidence else None,
            )
        )

    import json
    
    methodology_text = _display_value(by_parameter.get("methodology"))
    content_part = ""
    form_part = ""
    
    clean_text = methodology_text.replace("**", "")
    
    if "--- ARAH KEGIATAN ---" in clean_text:
        parts = clean_text.split("--- ARAH KEGIATAN ---")
        form_part = parts[0].replace("--- BENTUK METODOLOGI ---", "").strip()
        content_part = parts[1].strip() if len(parts) > 1 else ""
    elif methodology_text.strip().startswith('{'):
        try:
            data = json.loads(methodology_text)
            content_part = data.get("arah_kegiatan", "")
            form_part = data.get("bentuk", "")
        except json.JSONDecodeError:
            pass
            
    if not content_part and not form_part:
        methodology_parts = methodology_text.split("|||")
        content_part = methodology_parts[0].strip() if methodology_parts else ""
        form_part = methodology_parts[1].strip() if len(methodology_parts) > 1 else _infer_method_form(methodology_text)

    results_findings = _display_value(by_parameter.get("results_findings"))
    future_work_raw = _display_value(by_parameter.get("future_work"))
    future_work_display = future_work_raw
    future_ideas = []
    
    if future_work_raw.strip().startswith('{'):
        try:
            data = json.loads(future_work_raw)
            future_work_display = data.get("pengembangan", "Belum dinyatakan")
            for rec in data.get("recommendations", []):
                future_ideas.append({
                    "rank": rec.get("rank", 1),
                    "title": rec.get("judul", "Ide Penelitian"),
                    "rationale": rec.get("alasan", "-"),
                    "methodology": rec.get("metode", "-"),
                    "impact": rec.get("dampak", "-"),
                })
        except json.JSONDecodeError:
            pass
            
    if not future_ideas and future_work_raw and "[RANK 1]" in future_work_raw.upper():
        parts = future_work_raw.split("|||")
        future_work_display = parts[0].strip() if parts else "Belum dinyatakan"
        for part in parts:
            part = part.strip()
            if not part:
                continue
            
            rank_match = re.search(r'\[RANK\s*(\d+)\]', part, re.IGNORECASE)
            if not rank_match:
                continue
            rank = int(rank_match.group(1))
            
            part = part.strip().replace('\\n', '\n')
            part = re.sub(r'\*\*', '', part)
            
            title_match = re.search(r'Judul:\s*(.*?)(?=\n\s*Alasan:|\n\s*Metode:|\n\s*Dampak:|$)', part, re.IGNORECASE | re.DOTALL)
            rationale_match = re.search(r'Alasan:\s*(.*?)(?=\n\s*Judul:|\n\s*Metode:|\n\s*Dampak:|$)', part, re.IGNORECASE | re.DOTALL)
            method_match = re.search(r'Metode:\s*(.*?)(?=\n\s*Judul:|\n\s*Alasan:|\n\s*Dampak:|$)', part, re.IGNORECASE | re.DOTALL)
            impact_match = re.search(r'Dampak:\s*(.*?)(?=\n\s*Judul:|\n\s*Alasan:|\n\s*Metode:|$)', part, re.IGNORECASE | re.DOTALL)
            
            future_ideas.append({
                "rank": rank,
                "title": title_match.group(1).strip() if title_match else "Ide Penelitian",
                "rationale": rationale_match.group(1).strip() if rationale_match else "-",
                "methodology": method_match.group(1).strip() if method_match else "-",
                "impact": impact_match.group(1).strip() if impact_match else "-",
            })

    activity_direction_parts = []
    if results_findings:
        activity_direction_parts.append(f"Output penelitian:\n{results_findings}")
    if future_work_display:
        activity_direction_parts.append(f"Arah pengembangan:\n{future_work_display}")
    activity_direction = "\n\n".join(activity_direction_parts) if activity_direction_parts else "Belum dinyatakan"

    def _bulletize(text: str) -> str:
        # Menangani jika Gemini tidak memberikan newline dengan memotong berdasarkan kata kunci
        keywords = [
            "Populasi data dari paper ini adalah:",
            "Tahap pengumpulan data penelitian ini adalah:",
            "Teknik analisis data penelitian ini adalah:",
            "Desain Riset:", "Variabel:", "Hipotesis:", "Ukuran Sampel:",
            "Teknik Sampling:", "Instrumen:", "Teknik Analisis:",
            "Fokus Riset:", "Subjek/Informan:", "Teknik Pemilihan:",
            "Tahap Kuantitatif:", "Tahap Kualitatif:", "Integrasi Analisis:"
        ]
        
        # Buat regex pattern untuk mencari kata kunci (dengan atau tanpa newline sebelumnya)
        # Pisahkan text dan pastikan kata kunci tetap berada di awal baris
        pattern = re.compile(r'(?<!\n)\s*(' + '|'.join(map(re.escape, keywords)) + r')')
        formatted_text = pattern.sub(r'\n\1', text)
        
        lines = [line.strip() for line in formatted_text.split('\n') if line.strip()]
        if len(lines) > 1:
            return "\n\n".join(f"• {line.lstrip('•').strip()}" for line in lines)
        return text

    methodology = []
    if methodology_text:
        methodology.append(
            MethodologyTableRow(
                content=content_part,
                form=_bulletize(form_part),
                main_activity=_bulletize(_display_value(by_parameter.get("dataset_sample")))
                or "Belum dinyatakan",
                activity_direction=activity_direction,
                final_goal=_display_value(by_parameter.get("research_objective"))
                or "Belum dinyatakan",
            )
        )

    return StructuredPaperTablesRead(
        research_questions=research_questions,
        methodology=methodology,
        future_ideas=future_ideas if future_ideas else None,
    )


def _display_value(component: ExtractedComponentRead | None) -> str:
    if component is None:
        return ""
    val = component.final_value or component.ai_value
    val = re.sub(r'[ \t]+', ' ', val)
    return val.strip()


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
