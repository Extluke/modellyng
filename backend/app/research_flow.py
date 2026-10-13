"""Peta alur riset untuk kanvas menu Maps (GAP).

Mengikuti konsep Figma reviewer, dibaca dari kiri ke kanan:

    topik (per paper) -> isi (kesamaan topik) -> masalah (per paper)
    -> solusi (digabung bila sama) -> fungsi + kesimpulan -> poin kesimpulan

Gemini hanya merumuskan frasa singkat dan mengusulkan pengelompokan dari
data matriks yang sudah direview. Aturan yang menentukan warna dan titik
"end" diterapkan di sini oleh kode, bukan oleh AI:

* isi (tema) butuh minimal dua paper. Paper yang topiknya tidak punya
  kesamaan dengan paper lain langsung berakhir setelah topiknya (end).
* solusi yang dipakai minimal dua paper berarti sering diteliti (hijau) dan
  alurnya berlanjut ke fungsi dan kesimpulan. Solusi yang hanya dipakai satu
  paper berarti jarang diteliti (merah) dan alurnya berhenti (end).
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from datetime import datetime, timezone
from uuid import UUID

from pydantic import BaseModel, Field

from .ai_text import PLACEHOLDER_VALUES as _EMPTY_VALUES
from .ai_text import clean_text as _clean
from .ai_text import first_sentence as _first_sentence
from .ai_text import shorten
from .ai_text import unique_paper_keys as _keys
from .ai_text import normalize_paper_key as _normalize_key
from .config import get_settings
from .gemini_json import generate_structured
from .schemas import (
    ComparativeMatrixRead,
    ExtractionParameter,
    ResearchFlowItemRead,
    ResearchFlowPaperRead,
    ResearchFlowRead,
    ResearchFlowSolutionRead,
    ResearchFlowThemeRead,
    ResearchFlowUnrelatedRead,
)

# Ubah versi ini setiap kali prompt atau aturan berubah agar cache lama
# otomatis dibuat ulang.
FLOW_PROMPT_VERSION = "research-flow-v2"

SOURCE_PARAMETERS: tuple[ExtractionParameter, ...] = (
    ExtractionParameter.RESEARCH_PROBLEM,
    ExtractionParameter.RESEARCH_OBJECTIVE,
    ExtractionParameter.RESEARCH_QUESTION,
    ExtractionParameter.METHODOLOGY,
    ExtractionParameter.RESULTS_FINDINGS,
    ExtractionParameter.CONTRIBUTION,
    ExtractionParameter.KEY_CLAIMS,
)

_PARAMETER_LABELS = {
    ExtractionParameter.RESEARCH_PROBLEM: "Masalah penelitian",
    ExtractionParameter.RESEARCH_OBJECTIVE: "Tujuan penelitian",
    ExtractionParameter.RESEARCH_QUESTION: "Pertanyaan penelitian",
    ExtractionParameter.METHODOLOGY: "Metodologi",
    ExtractionParameter.RESULTS_FINDINGS: "Hasil/temuan",
    ExtractionParameter.CONTRIBUTION: "Kontribusi",
    ExtractionParameter.KEY_CLAIMS: "Simpulan inti",
}

MAX_VALUE_CHARS = 1_200
MAX_FUNCTIONS = 4
MAX_CONCLUSIONS = 3
_LIMITS = {
    "topic": 90,
    "problem": 110,
    "solution": 80,
    "theme": 60,
    "function": 140,
    "conclusion": 160,
}


@dataclass(frozen=True)
class FlowPaperInput:
    key: str
    paper_id: UUID
    number: int
    title: str
    values: dict[str, str] = field(default_factory=dict)

    def value(self, parameter: ExtractionParameter) -> str:
        return self.values.get(parameter.value, "")


# --- Skema jawaban Gemini -------------------------------------------------


class AiFlowPaper(BaseModel):
    key: str = Field(description="Kode paper persis seperti di data, misal P1.")
    topic: str = Field(description="Topik penelitian, maksimal 8 kata.")
    problem: str = Field(description="Masalah spesifik yang diteliti, maksimal 10 kata.")
    solution: str = Field(
        description="Solusi, pendekatan, atau produk yang diusulkan, maksimal 6 kata."
    )


class AiFlowTheme(BaseModel):
    label: str = Field(description="Isi atau tema bersama, maksimal 5 kata.")
    paper_keys: list[str] = Field(
        description="Kode paper yang topiknya memiliki kesamaan isi, minimal 2."
    )


class AiFlowSolutionGroup(BaseModel):
    label: str = Field(description="Nama solusi bersama, maksimal 6 kata.")
    paper_keys: list[str] = Field(description="Kode paper dengan solusi yang sama atau sejenis.")
    functions: list[str] = Field(
        default_factory=list,
        description="2-4 fungsi utama solusi, hanya jika paper_keys berisi minimal 2.",
    )
    conclusions: list[str] = Field(
        default_factory=list,
        description="2-3 poin kesimpulan gabungan, hanya jika paper_keys berisi minimal 2.",
    )


class AiResearchFlow(BaseModel):
    papers: list[AiFlowPaper] = Field(default_factory=list)
    themes: list[AiFlowTheme] = Field(default_factory=list)
    solution_groups: list[AiFlowSolutionGroup] = Field(default_factory=list)


# --- Input dan cache ------------------------------------------------------


def collect_flow_inputs(matrix: ComparativeMatrixRead) -> list[FlowPaperInput]:
    """Ambil nilai matriks terverifikasi per paper, berurutan seperti matriks."""
    values: dict[str, dict[str, str]] = {str(paper.id): {} for paper in matrix.papers}
    for row in matrix.rows:
        if row.parameter not in SOURCE_PARAMETERS:
            continue
        for cell in row.cells:
            bucket = values.get(str(cell.paper_id))
            if bucket is None:
                continue
            text = _clean(cell.final_value) or _clean(cell.ai_value)
            if text.lower() in _EMPTY_VALUES:
                continue
            bucket[row.parameter.value] = text[:MAX_VALUE_CHARS]
    return [
        FlowPaperInput(
            key=f"P{number}",
            paper_id=paper.id,
            number=number,
            title=_clean(paper.title) or _clean(paper.original_filename) or f"Paper {number}",
            values=values[str(paper.id)],
        )
        for number, paper in enumerate(matrix.papers, start=1)
    ]


def flow_source_hash(inputs: list[FlowPaperInput]) -> str:
    """Sidik jari data sumber; berubah bila nilai review atau prompt berubah."""
    payload = {
        "version": FLOW_PROMPT_VERSION,
        "papers": [
            {"id": str(item.paper_id), "title": item.title, "values": item.values}
            for item in inputs
        ],
    }
    encoded = json.dumps(payload, sort_keys=True, ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


# --- Prompt ---------------------------------------------------------------

_PROMPT_INSTRUCTIONS = """Anda menyusun PETA ALUR RISET untuk aplikasi Modellyng dari beberapa paper.
Gunakan HANYA data ekstraksi terverifikasi di bawah. Jangan menambah fakta yang tidak ada di data.
Tulis semua teks dalam Bahasa Indonesia yang singkat dan jelas.

Peta dibaca dari kiri ke kanan:
topik paper -> isi (kesamaan topik) -> masalah paper -> solusi -> fungsi solusi dan kesimpulan.

TUGAS:
1. papers: untuk SETIAP paper (pakai kode paper persis, misal "P1"), isi:
   - topic: topik penelitian, frasa maksimal 8 kata.
   - problem: masalah spesifik yang diselesaikan paper, frasa maksimal 10 kata.
   - solution: solusi, pendekatan, atau produk yang diusulkan, frasa maksimal 6 kata
     (misal "aplikasi mobile", "sistem berbasis web", "steganografi pada tag HTML").
2. themes: kelompokkan paper yang topiknya memiliki KESAMAAN ISI, yaitu membahas objek atau
   fenomena utama yang sama walaupun fokus, penyebab, atau sub-topiknya berbeda.
   Contoh: "banjir akibat curah hujan", "banjir akibat sungai", dan "banjir akibat longsor"
   masuk satu tema "banjir", sedangkan "cara menyetrika baju" tidak masuk tema tersebut.
   - label: isi bersama, maksimal 5 kata.
   - paper_keys: minimal 2 paper. Satu paper hanya boleh masuk satu tema.
   - Paper yang objek atau fenomena utamanya berbeda dari semua paper lain JANGAN dimasukkan
     ke tema mana pun.
3. solution_groups: di dalam setiap tema, kelompokkan paper yang SOLUSINYA SAMA atau sejenis.
   - Setiap paper yang masuk tema harus masuk tepat satu kelompok solusi. Kelompok boleh berisi 1 paper.
   - Jangan menggabungkan paper dari tema berbeda dalam satu kelompok solusi.
   - label: nama solusi bersama, maksimal 6 kata.
   - Khusus kelompok berisi minimal 2 paper, isi juga:
     - functions: 2-4 fungsi atau fitur utama solusi menurut paper, masing-masing maksimal 12 kata.
     - conclusions: 2-3 poin kesimpulan gabungan dari paper tersebut, masing-masing maksimal 15 kata.
   - Untuk kelompok berisi 1 paper, biarkan functions dan conclusions kosong.

DATA PAPER:
"""


def build_flow_prompt(inputs: list[FlowPaperInput], *, max_chars: int) -> str:
    separator = "\n\n"
    budget = max(
        max_chars - len(_PROMPT_INSTRUCTIONS) - len(separator) * max(len(inputs) - 1, 0),
        0,
    )
    # Bagi anggaran karakter rata agar setiap paper tetap ikut terkirim.
    per_paper = budget // max(len(inputs), 1)
    blocks: list[str] = []
    for item in inputs:
        lines = [f"[{item.key}] Judul: {item.title}"]
        for parameter in SOURCE_PARAMETERS:
            text = item.value(parameter)
            if text:
                lines.append(f"- {_PARAMETER_LABELS[parameter]}: {text}")
        blocks.append("\n".join(lines)[:per_paper])
    return _PROMPT_INSTRUCTIONS + separator.join(blocks)


# --- Aturan alur (deterministik) -----------------------------------------


@dataclass
class _SolutionGroup:
    theme: int
    keys: list[str]
    label: str
    functions: list[str]
    conclusions: list[str]


def build_research_flow(
    project_id: UUID,
    inputs: list[FlowPaperInput],
    ai: AiResearchFlow,
    *,
    model_name: str | None = None,
    generated_at: datetime | None = None,
) -> ResearchFlowRead:
    """Terapkan aturan kesamaan pada usulan AI dan bentuk peta alur final."""
    by_key = {item.key: item for item in inputs}

    def number(key: str) -> int:
        return by_key[key].number

    phrased: dict[str, AiFlowPaper] = {}
    for paper in ai.papers:
        key = _normalize_key(paper.key)
        if key in by_key and key not in phrased:
            phrased[key] = paper

    def topic(key: str) -> str:
        text = _short(phrased[key].topic, "topic") if key in phrased else ""
        return text or _fallback_topic(by_key[key])

    def problem(key: str) -> str:
        text = _short(phrased[key].problem, "problem") if key in phrased else ""
        return text or _fallback_problem(by_key[key])

    def solution(key: str) -> str:
        text = _short(phrased[key].solution, "solution") if key in phrased else ""
        return text or _fallback_solution(by_key[key])

    # 1. Isi (tema): hanya kelompok yang punya minimal dua paper.
    theme_of: dict[str, int] = {}
    themes: list[tuple[str, list[str]]] = []
    for theme in ai.themes:
        keys = [k for k in _keys(theme.paper_keys) if k in by_key and k not in theme_of]
        if len(keys) < 2:
            continue
        for key in keys:
            theme_of[key] = len(themes)
        themes.append((_short(theme.label, "theme") or "Isi bersama", keys))

    # 2. Solusi di dalam tema. Kelompok yang melintasi tema dipecah per tema.
    groups: list[_SolutionGroup] = []
    solution_of: dict[str, int] = {}
    for group in ai.solution_groups:
        keys = [k for k in _keys(group.paper_keys) if k in theme_of and k not in solution_of]
        per_theme: dict[int, list[str]] = {}
        for key in keys:
            per_theme.setdefault(theme_of[key], []).append(key)
        for theme_index, members in per_theme.items():
            for key in members:
                solution_of[key] = len(groups)
            groups.append(
                _SolutionGroup(
                    theme=theme_index,
                    keys=members,
                    label=_short(group.label, "solution"),
                    functions=list(group.functions),
                    conclusions=list(group.conclusions),
                )
            )
    for theme_index, (_, keys) in enumerate(themes):
        for key in keys:
            if key not in solution_of:
                solution_of[key] = len(groups)
                groups.append(_SolutionGroup(theme_index, [key], "", [], []))

    # 3. Bentuk keluaran dengan urutan stabil (berdasarkan nomor paper).
    theme_reads: list[tuple[int, ResearchFlowThemeRead]] = []
    for theme_index, (label, _) in enumerate(themes):
        theme_groups = sorted(
            (g for g in groups if g.theme == theme_index),
            key=lambda g: min(number(k) for k in g.keys),
        )
        items: list[ResearchFlowItemRead] = []
        solutions: list[ResearchFlowSolutionRead] = []
        for group in theme_groups:
            members = sorted(group.keys, key=number)
            shared = len(members) >= 2
            items.extend(
                ResearchFlowItemRead(
                    paper_id=by_key[key].paper_id, topic=topic(key), problem=problem(key)
                )
                for key in members
            )
            functions: list[str] = []
            conclusions: list[str] = []
            if shared:
                functions = _points(group.functions, "function", MAX_FUNCTIONS) or _points(
                    [_fallback_function(by_key[key]) for key in members],
                    "function",
                    MAX_FUNCTIONS,
                )
                conclusions = _points(group.conclusions, "conclusion", MAX_CONCLUSIONS) or _points(
                    [_fallback_conclusion(by_key[key]) for key in members],
                    "conclusion",
                    MAX_CONCLUSIONS,
                )
            solutions.append(
                ResearchFlowSolutionRead(
                    label=group.label or solution(members[0]),
                    paper_ids=[by_key[key].paper_id for key in members],
                    shared=shared,
                    functions=functions,
                    conclusions=conclusions,
                )
            )
        first_number = min(number(k) for g in theme_groups for k in g.keys)
        theme_reads.append(
            (first_number, ResearchFlowThemeRead(label=label, items=items, solutions=solutions))
        )
    theme_reads.sort(key=lambda entry: entry[0])

    unrelated = [
        ResearchFlowUnrelatedRead(paper_id=item.paper_id, topic=topic(item.key))
        for item in inputs
        if item.key not in theme_of
    ]

    return ResearchFlowRead(
        project_id=project_id,
        papers=[
            ResearchFlowPaperRead(paper_id=item.paper_id, number=item.number, title=item.title)
            for item in inputs
        ],
        themes=[theme for _, theme in theme_reads],
        unrelated=unrelated,
        model_name=model_name,
        generated_at=generated_at,
    )


# --- Pemanggilan Gemini ---------------------------------------------------


def generate_research_flow(project_id: UUID, inputs: list[FlowPaperInput]) -> ResearchFlowRead:
    prompt = build_flow_prompt(inputs, max_chars=get_settings().gemini_max_input_chars)
    ai, model = generate_structured(
        prompt,
        AiResearchFlow,
        purpose="Research flow",
        failure_message="Peta alur riset belum dapat disusun. Coba lagi.",
    )
    return build_research_flow(
        project_id,
        inputs,
        ai,
        model_name=model,
        generated_at=datetime.now(timezone.utc),
    )


# --- Utilitas teks --------------------------------------------------------


def _short(text: str | None, kind: str) -> str:
    return shorten(text, _LIMITS[kind])


def _points(raw: list[str], kind: str, limit: int) -> list[str]:
    points: list[str] = []
    seen: set[str] = set()
    for item in raw:
        value = _short(item, kind)
        if value and value.lower() not in seen:
            seen.add(value.lower())
            points.append(value)
        if len(points) == limit:
            break
    return points


def _first_of(item: FlowPaperInput, *parameters: ExtractionParameter) -> str:
    for parameter in parameters:
        sentence = _first_sentence(item.value(parameter))
        if sentence:
            return sentence
    return ""


def _fallback_topic(item: FlowPaperInput) -> str:
    return _short(
        _first_of(item, ExtractionParameter.RESEARCH_OBJECTIVE) or item.title, "topic"
    )


def _fallback_problem(item: FlowPaperInput) -> str:
    return _short(_first_of(item, ExtractionParameter.RESEARCH_PROBLEM), "problem") or (
        "Masalah belum tercantum"
    )


def _fallback_solution(item: FlowPaperInput) -> str:
    text = _first_of(
        item,
        ExtractionParameter.CONTRIBUTION,
        ExtractionParameter.RESULTS_FINDINGS,
        ExtractionParameter.METHODOLOGY,
    )
    return _short(text, "solution") or "Solusi belum tercantum"


def _fallback_function(item: FlowPaperInput) -> str:
    return _first_of(item, ExtractionParameter.CONTRIBUTION, ExtractionParameter.RESULTS_FINDINGS)


def _fallback_conclusion(item: FlowPaperInput) -> str:
    return _first_of(item, ExtractionParameter.KEY_CLAIMS, ExtractionParameter.RESULTS_FINDINGS)
