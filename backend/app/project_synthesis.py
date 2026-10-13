"""Sintesis AI global per project untuk menu Matriks & Sintesis.

Semua paper ready di project yang punya hasil review verified/edited ikut
disintesis sekaligus. Gemini merumuskan poin dan paragraf; kode di sini:

* memvalidasi rujukan paper pada setiap poin (poin tanpa rujukan dibuang),
* memastikan setiap paper mendapat "posisi" di dalam sintesis,
* mengubah penanda [P1] dari AI menjadi sitasi penulis-tahun berdasarkan
  metadata paper. AI tidak pernah diminta menulis nama penulis atau tahun.

Hasil disimpan per project bersama sidik jari data sumber (source_hash) agar
tidak memanggil Gemini ulang selama hasil review tidak berubah.
"""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from uuid import UUID

from pydantic import BaseModel, Field

from .ai_text import clean_text, first_sentence, is_placeholder, normalize_paper_key
from .ai_text import shorten, unique_paper_keys
from .config import get_settings
from .gemini_json import AiInputError, AiUnavailableError, generate_structured
from .schemas import (
    ComparativeMatrixRead,
    ExtractionParameter,
    MatrixPaperRead,
    ProjectSynthesisRead,
    SynthesisIdeaRead,
    SynthesisPaperPositionRead,
    SynthesisPaperRead,
    SynthesisPointRead,
    SynthesisSectionRead,
)

# Ubah versi ini setiap kali prompt atau aturan berubah agar hasil lama
# ditandai perlu diperbarui.
SYNTHESIS_PROMPT_VERSION = "project-synthesis-v1"
MIN_PAPERS = 2
MAX_POINTS = 5
MAX_IDEAS = 3
MAX_VALUE_CHARS = 1_500


@dataclass(frozen=True)
class SectionSpec:
    key: str
    title: str
    academic_title: str
    min_papers: int


SECTIONS: tuple[SectionSpec, ...] = (
    SectionSpec("similarities", "Persamaan", "Persamaan", 2),
    SectionSpec("differences", "Perbedaan", "Perbedaan", 2),
    SectionSpec("research_patterns", "Pola Penelitian", "Pola Penelitian", 2),
    SectionSpec("approach_differences", "Perbedaan Pendekatan", "Perbedaan Pendekatan", 2),
    SectionSpec("gaps", "Celah & Peluang Penelitian", "Celah dan Peluang Penelitian", 1),
)

_PARAMETER_LABELS: dict[ExtractionParameter, str] = {
    ExtractionParameter.RESEARCH_PROBLEM: "Masalah penelitian",
    ExtractionParameter.RESEARCH_OBJECTIVE: "Tujuan penelitian",
    ExtractionParameter.RESEARCH_QUESTION: "Pertanyaan penelitian",
    ExtractionParameter.METHODOLOGY: "Metodologi",
    ExtractionParameter.DATASET_SAMPLE: "Data dan sampel",
    ExtractionParameter.VARIABLES_CONCEPTS: "Variabel dan konsep",
    ExtractionParameter.RESULTS_FINDINGS: "Hasil dan temuan",
    ExtractionParameter.CONTRIBUTION: "Kontribusi",
    ExtractionParameter.LIMITATIONS: "Keterbatasan",
    ExtractionParameter.FUTURE_WORK: "Penelitian lanjutan",
    ExtractionParameter.KEY_CLAIMS: "Simpulan inti",
}

# Peringatan ekstraksi untuk file yang bukan paper ilmiah bukan isi penelitian.
_NOT_A_PAPER_PREFIX = "file yang diunggah tidak terdeteksi"


class NotEnoughPapersError(AiInputError):
    """Project belum punya cukup paper terreview untuk disintesis."""


# --- Input ----------------------------------------------------------------


@dataclass(frozen=True)
class SynthesisPaperInput:
    key: str
    number: int
    paper: MatrixPaperRead
    values: dict[str, str] = field(default_factory=dict)

    @property
    def paper_id(self) -> UUID:
        return self.paper.id

    @property
    def title(self) -> str:
        return clean_text(self.paper.title) or clean_text(self.paper.original_filename) or (
            f"Paper {self.number}"
        )

    def value(self, parameter: ExtractionParameter) -> str:
        return self.values.get(parameter.value, "")


def collect_synthesis_inputs(matrix: ComparativeMatrixRead) -> list[SynthesisPaperInput]:
    """Semua paper matriks (urut seperti matriks) beserta nilai terreviewnya."""
    values: dict[str, dict[str, str]] = {str(paper.id): {} for paper in matrix.papers}
    for row in matrix.rows:
        if row.parameter not in _PARAMETER_LABELS:
            continue
        for cell in row.cells:
            bucket = values.get(str(cell.paper_id))
            if bucket is None:
                continue
            text = clean_text(cell.final_value) or clean_text(cell.ai_value)
            if is_placeholder(text) or text.lower().startswith(_NOT_A_PAPER_PREFIX):
                continue
            bucket[row.parameter.value] = text[:MAX_VALUE_CHARS]
    return [
        SynthesisPaperInput(
            key=f"P{number}", number=number, paper=paper, values=values[str(paper.id)]
        )
        for number, paper in enumerate(matrix.papers, start=1)
    ]


def included_inputs(inputs: list[SynthesisPaperInput]) -> list[SynthesisPaperInput]:
    """Hanya paper yang punya minimal satu nilai review yang bisa disintesis."""
    return [item for item in inputs if item.values]


def synthesis_source_hash(inputs: list[SynthesisPaperInput]) -> str:
    """Sidik jari data sumber; berubah bila hasil review atau prompt berubah."""
    payload = {
        "version": SYNTHESIS_PROMPT_VERSION,
        "papers": [
            {
                "id": str(item.paper_id),
                "title": item.title,
                "year": item.paper.publication_year,
                "values": item.values,
            }
            for item in included_inputs(inputs)
        ],
    }
    encoded = json.dumps(payload, sort_keys=True, ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


# --- Skema jawaban Gemini -------------------------------------------------


class AiSynthesisPoint(BaseModel):
    text: str = Field(description="Satu kalimat ringkas, maksimal 30 kata.")
    paper_keys: list[str] = Field(description="Kode paper pendukung, misal [\"P1\", \"P3\"].")


class AiResearchIdea(BaseModel):
    title: str = Field(description="Judul ide penelitian lanjutan, maksimal 15 kata.")
    rationale: str = Field(description="Alasan dan arah penelitian, 1-2 kalimat.")
    paper_keys: list[str] = Field(description="Kode paper yang menjadi dasar ide ini.")


class AiPaperPosition(BaseModel):
    paper_key: str = Field(description="Kode paper, misal P1.")
    position: str = Field(
        description="Posisi atau ciri khas paper ini dibanding paper lain, maksimal 35 kata."
    )


class AiSynthesisParagraphs(BaseModel):
    similarities: str = Field(description="Paragraf akademik bagian Persamaan.")
    differences: str = Field(description="Paragraf akademik bagian Perbedaan.")
    research_patterns: str = Field(description="Paragraf akademik bagian Pola Penelitian.")
    approach_differences: str = Field(description="Paragraf akademik bagian Perbedaan Pendekatan.")
    gaps: str = Field(description="Paragraf akademik bagian Celah dan Peluang Penelitian.")


class AiProjectSynthesis(BaseModel):
    similarities: list[AiSynthesisPoint]
    differences: list[AiSynthesisPoint]
    research_patterns: list[AiSynthesisPoint]
    approach_differences: list[AiSynthesisPoint]
    gaps: list[AiSynthesisPoint]
    research_ideas: list[AiResearchIdea]
    paper_positions: list[AiPaperPosition]
    paragraphs: AiSynthesisParagraphs


# --- Isi yang disimpan ----------------------------------------------------
# Rujukan disimpan sebagai paper_id dan penanda sitasi {{p:id;id}} (dalam
# kurung) atau {{n:id}} (naratif). Sitasi baru dirender saat dibaca, sehingga
# perubahan metadata penulis/tahun langsung terlihat tanpa memanggil AI.


class StoredPoint(BaseModel):
    text: str
    paper_ids: list[UUID]


class StoredIdea(BaseModel):
    title: str
    rationale: str
    paper_ids: list[UUID]


class StoredPosition(BaseModel):
    paper_id: UUID
    text: str


class SynthesisContent(BaseModel):
    version: str = SYNTHESIS_PROMPT_VERSION
    paper_ids: list[UUID]
    sections: dict[str, list[StoredPoint]]
    paragraphs: dict[str, str]
    research_ideas: list[StoredIdea] = Field(default_factory=list)
    paper_positions: list[StoredPosition] = Field(default_factory=list)
    model_name: str | None = None
    generated_at: datetime


# --- Prompt ---------------------------------------------------------------

_PROMPT_INSTRUCTIONS = """Anda adalah asisten peneliti yang menyusun SINTESIS LITERATUR lintas paper untuk satu proyek riset.
Gunakan HANYA data ekstraksi terverifikasi di bawah. Jangan menambah fakta, angka, nama penulis, atau tahun yang tidak ada di data.
Tulis dalam Bahasa Indonesia akademik yang jelas dan ringkas.
Setiap paper diberi kode seperti P1, P2, dan seterusnya. Sebut paper HANYA dengan kode tersebut.

Isi setiap bagian di bawah. Setiap poin berupa satu kalimat ringkas (maksimal 30 kata) dengan kode paper pendukung di paper_keys.
1. similarities (Persamaan): 3-5 poin hal yang sama antar paper, misalnya topik, tujuan, objek, metode, atau temuan. Setiap poin minimal 2 paper.
2. differences (Perbedaan): 3-5 poin perbedaan penting, misalnya fokus, konteks, data, atau hasil. Setiap poin menyebut minimal 2 paper yang dibandingkan.
3. research_patterns (Pola Penelitian): 2-4 poin pola yang muncul, misalnya metode yang dominan, jenis data, atau arah perkembangan dari tahun ke tahun. Setiap poin minimal 2 paper.
4. approach_differences (Perbedaan Pendekatan): 2-4 poin perbedaan pendekatan atau metodologi. Setiap poin minimal 2 paper.
5. gaps (Celah & Peluang Penelitian): 3-5 poin celah yang terlihat dari perbandingan, misalnya keterbatasan yang sama, hal yang belum diuji, atau kombinasi yang belum dicoba. Setiap poin minimal 1 paper.
6. research_ideas: 2-3 ide penelitian lanjutan yang konkret dan berangkat dari celah di atas. Isi title, rationale, dan paper_keys.
7. paper_positions: untuk SETIAP paper, satu kalimat tentang posisi atau ciri khas paper itu dibanding paper lain.
8. paragraphs: untuk bagian 1 sampai 5, tulis satu paragraf akademik (4-7 kalimat) yang siap dipakai di tinjauan pustaka.
   Cantumkan sitasi dengan penanda [P1] atau [P1, P3] tepat setelah klaim terkait.
   JANGAN menulis nama penulis atau tahun; penanda akan diganti menjadi sitasi oleh sistem.

Jika paper sedikit, sesuaikan jumlah poin seperlunya, tetapi jangan mengarang perbandingan yang tidak didukung data.

DATA PAPER:
"""


def build_synthesis_prompt(inputs: list[SynthesisPaperInput], *, max_chars: int) -> str:
    separator = "\n\n"
    budget = max(
        max_chars - len(_PROMPT_INSTRUCTIONS) - len(separator) * max(len(inputs) - 1, 0),
        0,
    )
    per_paper = budget // max(len(inputs), 1)
    blocks: list[str] = []
    for item in inputs:
        lines = [f"[{item.key}] Judul: {item.title}"]
        if item.paper.publication_year:
            lines.append(f"Tahun terbit: {item.paper.publication_year}")
        for parameter, label in _PARAMETER_LABELS.items():
            text = item.value(parameter)
            if text:
                lines.append(f"- {label}: {text}")
        blocks.append("\n".join(lines)[:per_paper])
    return _PROMPT_INSTRUCTIONS + separator.join(blocks)


# --- Validasi jawaban AI (deterministik) ---------------------------------

_POINT_LIMIT = 320
_IDEA_TITLE_LIMIT = 160
_IDEA_RATIONALE_LIMIT = 500
_POSITION_LIMIT = 320

# Penanda dari AI: [P1], [P1, P3], (P2 dan P4), [P1, P2, dan P3], atau
# "P1"/"Paper 1" sebagai subjek kalimat (sitasi naratif).
_KEY_TOKEN = r"P(?:aper)?\s*\d{1,3}"
_KEY_SEPARATOR = r"(?:\s*[,;&/]\s*(?:(?:dan|and)\s+)?|\s+(?:dan|and)\s+)"
_GROUP_MARKER = re.compile(
    rf"[\[(]\s*({_KEY_TOKEN}(?:{_KEY_SEPARATOR}{_KEY_TOKEN})*)\s*[\])]", re.IGNORECASE
)
_BARE_MARKER = re.compile(r"\b(?:P|Paper\s+)(\d{1,3})\b")
_STORED_MARKER = re.compile(r"\{\{([pn]):([0-9a-fA-F;-]*)\}\}")
_ADJACENT_GROUPS = re.compile(r"(\{\{p:[0-9a-fA-F;-]*)\}\}\s*\{\{p:")


def build_synthesis_content(
    inputs: list[SynthesisPaperInput],
    ai: AiProjectSynthesis,
    *,
    model_name: str | None = None,
    generated_at: datetime | None = None,
) -> SynthesisContent:
    """Terapkan aturan rujukan pada jawaban AI. [inputs] = paper yang disertakan."""
    by_key = {item.key: item for item in inputs}

    def refs(raw_keys: list[str]) -> list[UUID]:
        keys = [key for key in unique_paper_keys(raw_keys) if key in by_key]
        keys.sort(key=lambda key: by_key[key].number)
        return [by_key[key].paper_id for key in keys]

    def readable(text: str, limit: int) -> str:
        return shorten(readable_paper_keys(text, by_key), limit)

    sections: dict[str, list[StoredPoint]] = {}
    for spec in SECTIONS:
        points: list[StoredPoint] = []
        seen: set[str] = set()
        for point in getattr(ai, spec.key):
            text = readable(point.text, _POINT_LIMIT)
            paper_ids = refs(point.paper_keys)
            if not text or len(paper_ids) < spec.min_papers or text.lower() in seen:
                continue
            seen.add(text.lower())
            points.append(StoredPoint(text=text, paper_ids=paper_ids))
            if len(points) == MAX_POINTS:
                break
        sections[spec.key] = points

    if not any(sections.values()):
        raise AiUnavailableError(
            "Jawaban AI belum memuat poin sintesis yang merujuk paper. Coba lagi."
        )

    paragraphs: dict[str, str] = {}
    for spec in SECTIONS:
        paragraph = encode_citations(getattr(ai.paragraphs, spec.key), by_key)
        if not _has_words(paragraph):
            paragraph = _paragraph_from_points(sections[spec.key])
        paragraphs[spec.key] = paragraph

    ideas: list[StoredIdea] = []
    for idea in ai.research_ideas:
        title = readable(idea.title, _IDEA_TITLE_LIMIT)
        paper_ids = refs(idea.paper_keys)
        if not title or not paper_ids:
            continue
        ideas.append(
            StoredIdea(
                title=title,
                rationale=readable(idea.rationale, _IDEA_RATIONALE_LIMIT),
                paper_ids=paper_ids,
            )
        )
        if len(ideas) == MAX_IDEAS:
            break

    positions_by_key: dict[str, str] = {}
    for position in ai.paper_positions:
        key = normalize_paper_key(position.paper_key)
        text = readable(position.position, _POSITION_LIMIT)
        if key in by_key and text and key not in positions_by_key:
            positions_by_key[key] = text
    positions = [
        StoredPosition(
            paper_id=item.paper_id,
            text=positions_by_key.get(item.key) or _fallback_position(item),
        )
        for item in inputs
    ]

    return SynthesisContent(
        paper_ids=[item.paper_id for item in inputs],
        sections=sections,
        paragraphs=paragraphs,
        research_ideas=ideas,
        paper_positions=positions,
        model_name=model_name,
        generated_at=generated_at or datetime.now(timezone.utc),
    )


def encode_citations(text: str, by_key: dict[str, SynthesisPaperInput]) -> str:
    """Ganti [P1, P3] menjadi {{p:id;id}} dan P1 naratif menjadi {{n:id}}."""

    def group(match: re.Match[str]) -> str:
        keys = unique_paper_keys(re.findall(_KEY_TOKEN, match.group(1), re.IGNORECASE))
        keys = sorted((key for key in keys if key in by_key), key=lambda k: by_key[k].number)
        ids = [str(by_key[key].paper_id) for key in keys]
        return "{{p:" + ";".join(ids) + "}}" if ids else ""

    def bare(match: re.Match[str]) -> str:
        item = by_key.get(f"P{int(match.group(1))}")
        return "{{n:" + str(item.paper_id) + "}}" if item else match.group(0)

    encoded = _GROUP_MARKER.sub(group, clean_text(text))
    encoded = _BARE_MARKER.sub(bare, encoded)
    # [P1][P2] berurutan menjadi satu sitasi (A; B).
    while True:
        merged = _ADJACENT_GROUPS.sub(r"\1;", encoded)
        if merged == encoded:
            break
        encoded = merged
    return _tidy(encoded)


def readable_paper_keys(text: str, by_key: dict[str, SynthesisPaperInput]) -> str:
    """Untuk teks poin: [P1, P2] dibuang (rujukan ada di paper_ids), P3 jadi "Paper 3"."""

    def bare(match: re.Match[str]) -> str:
        item = by_key.get(f"P{int(match.group(1))}")
        return f"Paper {item.number}" if item else match.group(0)

    return _tidy(_BARE_MARKER.sub(bare, _GROUP_MARKER.sub("", clean_text(text))))


def _paragraph_from_points(points: list[StoredPoint]) -> str:
    sentences = [
        f"{point.text.rstrip('.')} {{{{p:{';'.join(str(pid) for pid in point.paper_ids)}}}}}."
        for point in points
    ]
    return " ".join(sentences)


def _fallback_position(item: SynthesisPaperInput) -> str:
    for parameter in (
        ExtractionParameter.CONTRIBUTION,
        ExtractionParameter.RESEARCH_OBJECTIVE,
        ExtractionParameter.RESULTS_FINDINGS,
        ExtractionParameter.RESEARCH_PROBLEM,
    ):
        sentence = first_sentence(item.value(parameter))
        if sentence:
            return shorten(sentence, _POSITION_LIMIT)
    return "Belum ada ringkasan posisi untuk paper ini."


def _has_words(text: str) -> bool:
    return bool(re.search(r"[A-Za-zÀ-ÿ]{3,}", _STORED_MARKER.sub(" ", text)))


def _tidy(text: str) -> str:
    text = re.sub(r"\(\s*\)|\[\s*\]", "", text)
    text = re.sub(r"\s+([.,;:!?])", r"\1", text)
    text = re.sub(r"\s{2,}", " ", text)
    return text.strip()


# --- Sitasi ---------------------------------------------------------------

_NAME_SUFFIXES = {"jr", "jr.", "sr", "sr.", "ii", "iii", "iv"}


def _name_parts(author: str) -> tuple[str, list[str]]:
    """(nama belakang, nama depan). Gelar/akhiran di ujung nama dilewati."""
    tokens = [token.strip(",;") for token in str(author).split() if token.strip(",;")]
    all_caps = str(author).isupper()
    while len(tokens) > 1:
        last = tokens[-1]
        is_suffix = last.lower() in _NAME_SUFFIXES
        is_degree = "." in last and len(last) <= 6
        is_initials = len(last) <= 2 and last.isupper() and not all_caps
        if not (is_suffix or is_degree or is_initials):
            break
        tokens.pop()
    if not tokens:
        return "", []
    surname = tokens[-1].strip(".")
    if surname.isupper() and len(surname) > 1:
        surname = surname.title()
    return surname, tokens[:-1]


def author_surname(author: str) -> str:
    """Nama belakang untuk sitasi, misal "HAMEED AL-QAHERI" menjadi "Al-Qaheri"."""
    return _name_parts(author)[0]


def _apa_author(author: str) -> str:
    surname, given = _name_parts(author)
    initials = " ".join(f"{name[0].upper()}." for name in given if name[:1].isalpha())
    return f"{surname}, {initials}" if surname and initials else surname


_MISSING_METADATA = {"", "-", "null", "none", "n/a", "na", "unknown"}


def _meta(value: object) -> str:
    """Nilai metadata bibliografi; teks pengganti seperti "null" dianggap kosong."""
    text = clean_text(value)
    return "" if text.lower() in _MISSING_METADATA else text


def apa_reference(paper: MatrixPaperRead, year_label: str) -> str:
    """Entri daftar pustaka APA 7 dari metadata paper, tanpa menambah data."""
    title = clean_text(paper.title) or clean_text(paper.original_filename) or "Tanpa judul"
    title = title.rstrip(".") + "."
    authors = [name for name in (_apa_author(a) for a in paper.authors) if name]
    if len(authors) > 20:
        author_text = ", ".join(authors[:19]) + ", . . . " + authors[-1]
    elif len(authors) > 1:
        author_text = ", ".join(authors[:-1]) + ", & " + authors[-1]
    else:
        author_text = authors[0] if authors else ""

    venue = _meta(paper.journal) or _meta(paper.publisher)
    volume, issue, pages = _meta(paper.volume), _meta(paper.issue), _meta(paper.pages)
    if venue:
        if volume:
            venue += f", {volume}" + (f"({issue})" if issue else "")
        elif issue:
            venue += f", ({issue})"
        if pages:
            venue += f", {pages}"
        venue = venue.rstrip(".") + "."
    doi = re.sub(r"^(https?://)?(dx\.)?doi\.org/", "", _meta(paper.doi), flags=re.I)

    if author_text:
        parts = [f"{author_text.rstrip('.')}. ({year_label}).", title]
    else:
        parts = [title, f"({year_label})."]
    if venue:
        parts.append(venue)
    if doi:
        parts.append(f"https://doi.org/{doi}")
    return " ".join(parts)


@dataclass(frozen=True)
class Citation:
    parenthetical: str  # dipakai di dalam kurung: "Al-Qaheri dkk., 2010"
    narrative: str  # dipakai sebagai subjek kalimat: "Al-Qaheri dkk. (2010)"
    year_label: str  # tahun untuk daftar pustaka, termasuk akhiran a/b


def build_citations(papers: list[MatrixPaperRead]) -> dict[UUID, Citation]:
    """Sitasi penulis-tahun; paper dengan penulis dan tahun sama diberi a, b."""
    bases: list[tuple[MatrixPaperRead, str, str, str]] = []
    for paper in papers:
        surnames = [name for name in (author_surname(a) for a in paper.authors) if name]
        if not surnames:
            title = clean_text(paper.title) or clean_text(paper.original_filename) or "Tanpa judul"
            words = title.split()
            short = " ".join(words[:4]) + ("…" if len(words) > 4 else "")
            paren = narrative = f"“{short}”"
        elif len(surnames) == 1:
            paren = narrative = surnames[0]
        elif len(surnames) == 2:
            paren = f"{surnames[0]} & {surnames[1]}"
            narrative = f"{surnames[0]} dan {surnames[1]}"
        else:
            paren = narrative = f"{surnames[0]} dkk."
        year = str(paper.publication_year) if paper.publication_year else "n.d."
        bases.append((paper, paren, narrative, year))

    groups: dict[tuple[str, str], list[MatrixPaperRead]] = {}
    for paper, paren, _, year in bases:
        groups.setdefault((paren.casefold(), year), []).append(paper)

    citations: dict[UUID, Citation] = {}
    for paper, paren, narrative, year in bases:
        same = groups[(paren.casefold(), year)]
        label = year
        if len(same) > 1:
            letter = "abcdefghijklmnopqrstuvwxyz"[same.index(paper) % 26]
            label = f"{year}-{letter}" if year == "n.d." else f"{year}{letter}"
        citations[paper.id] = Citation(
            parenthetical=f"{paren}, {label}",
            narrative=f"{narrative} ({label})",
            year_label=label,
        )
    return citations


_SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+")
_NARRATIVE_MARKER = re.compile(r"\{\{n:([0-9a-fA-F-]+)\}\}")
_GROUP_STORED = re.compile(r"\{\{p:([0-9a-fA-F;-]*)\}\}")


def _drop_repeated_citations(text: str) -> str:
    """Paper yang sudah disebut naratif tidak diulang dalam kurung di kalimat yang sama."""
    sentences: list[str] = []
    for sentence in _SENTENCE_SPLIT.split(text):
        named = {value.lower() for value in _NARRATIVE_MARKER.findall(sentence)}
        if named:

            def prune(match: re.Match[str]) -> str:
                ids = [i for i in match.group(1).split(";") if i and i.lower() not in named]
                return "{{p:" + ";".join(ids) + "}}" if ids else ""

            sentence = _GROUP_STORED.sub(prune, sentence)
        sentences.append(sentence)
    return " ".join(sentences)


def render_citations(text: str, citations: dict[UUID, Citation]) -> tuple[str, set[UUID]]:
    """Ganti penanda tersimpan dengan sitasi; kembalikan juga paper yang disitasi."""
    cited: set[UUID] = set()
    text = _drop_repeated_citations(text)

    def replace(match: re.Match[str]) -> str:
        ids: list[UUID] = []
        for raw in match.group(2).split(";"):
            try:
                paper_id = UUID(raw)
            except ValueError:
                continue
            if paper_id in citations and paper_id not in ids:
                ids.append(paper_id)
        if not ids:
            return ""
        cited.update(ids)
        if match.group(1) == "n":
            return citations[ids[0]].narrative
        parts = sorted((citations[pid].parenthetical for pid in ids), key=str.casefold)
        return "(" + "; ".join(parts) + ")"

    return _tidy(_STORED_MARKER.sub(replace, text)), cited


# --- Render untuk API -----------------------------------------------------


def render_project_synthesis(
    matrix: ComparativeMatrixRead,
    content: SynthesisContent,
    *,
    stale: bool,
) -> ProjectSynthesisRead:
    papers = list(matrix.papers)
    known = {paper.id for paper in papers}
    included = set(content.paper_ids)
    citations = build_citations(papers)

    def keep(paper_ids: list[UUID]) -> list[UUID]:
        return [pid for pid in paper_ids if pid in known]

    sections: list[SynthesisSectionRead] = []
    cited: set[UUID] = set()
    for spec in SECTIONS:
        points = [
            SynthesisPointRead(text=point.text, paper_ids=keep(point.paper_ids))
            for point in content.sections.get(spec.key, [])
            if keep(point.paper_ids)
        ]
        paragraph, cited_here = render_citations(content.paragraphs.get(spec.key, ""), citations)
        cited |= cited_here
        if points or _has_words(paragraph):
            sections.append(
                SynthesisSectionRead(
                    key=spec.key, title=spec.title, points=points, paragraph=paragraph
                )
            )

    ideas = [
        SynthesisIdeaRead(title=idea.title, rationale=idea.rationale, paper_ids=keep(idea.paper_ids))
        for idea in content.research_ideas
        if keep(idea.paper_ids)
    ]
    number_of = {paper.id: number for number, paper in enumerate(papers, start=1)}
    positions = [
        SynthesisPaperPositionRead(
            paper_id=position.paper_id,
            text=_without_self_reference(position.text, number_of[position.paper_id]),
        )
        for position in content.paper_positions
        if position.paper_id in known
    ]

    return ProjectSynthesisRead(
        project_id=matrix.project_id,
        papers=[
            SynthesisPaperRead(
                paper_id=paper.id,
                number=number,
                title=clean_text(paper.title) or clean_text(paper.original_filename) or f"Paper {number}",
                citation=f"({citations[paper.id].parenthetical})",
                included=paper.id in included,
            )
            for number, paper in enumerate(papers, start=1)
        ],
        sections=sections,
        research_ideas=ideas,
        paper_positions=positions,
        academic_text=_academic_text(sections, papers, citations, cited or (included & known)),
        model_name=content.model_name,
        generated_at=content.generated_at,
        stale=stale,
    )


def _without_self_reference(text: str, number: int) -> str:
    """Posisi sudah diberi label "Paper N" di tampilan; hindari "Paper 1 Paper 1 ..."."""
    trimmed = re.sub(rf"^(?:Paper\s+{number}|P{number})\b[\s,:\-–]*", "", text, flags=re.I)
    if not trimmed or trimmed == text:
        return text
    return trimmed[0].upper() + trimmed[1:]


def _academic_text(
    sections: list[SynthesisSectionRead],
    papers: list[MatrixPaperRead],
    citations: dict[UUID, Citation],
    cited: set[UUID],
) -> str:
    titles = {spec.key: spec.academic_title for spec in SECTIONS}
    blocks = [
        f"{titles[section.key]}\n{section.paragraph}"
        for section in sections
        if _has_words(section.paragraph)
    ]
    references = sorted(
        (
            apa_reference(paper, citations[paper.id].year_label)
            for paper in papers
            if paper.id in cited
        ),
        key=str.casefold,
    )
    if references:
        blocks.append("Daftar Pustaka\n" + "\n".join(references))
    return "\n\n".join(blocks)


# --- Pemanggilan Gemini ---------------------------------------------------


def generate_synthesis_content(inputs: list[SynthesisPaperInput]) -> SynthesisContent:
    """[inputs] = paper yang disertakan (sudah difilter included_inputs)."""
    if len(inputs) < MIN_PAPERS:
        raise NotEnoughPapersError(
            "Sintesis membutuhkan minimal 2 paper dengan hasil review terverifikasi."
        )
    prompt = build_synthesis_prompt(inputs, max_chars=get_settings().gemini_max_input_chars)
    ai, model = generate_structured(
        prompt,
        AiProjectSynthesis,
        purpose="Project synthesis",
        failure_message="Sintesis AI belum dapat disusun. Coba lagi.",
        timeout_ms=100_000,
    )
    return build_synthesis_content(
        inputs, ai, model_name=model, generated_at=datetime.now(timezone.utc)
    )
