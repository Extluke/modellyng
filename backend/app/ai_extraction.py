from __future__ import annotations

import re
from dataclasses import dataclass
from uuid import UUID

from google import genai
from google.genai import types
from pydantic import BaseModel, Field, model_validator

from .config import get_settings
from .schemas import ExtractionParameter


PROMPT_VERSION = "academic-components-v1"


class AiEvidence(BaseModel):
    quote: str = Field(min_length=5, max_length=1_200)
    page_number: int = Field(ge=1)


class AiComponent(BaseModel):
    parameter: ExtractionParameter
    value: str = Field(min_length=1, max_length=4_000)
    confidence: float = Field(ge=0, le=1)
    evidence: list[AiEvidence] = Field(default_factory=list, max_length=3)


class AiPaperMetadata(BaseModel):
    title: str | None = Field(default=None, max_length=1_000)
    authors: list[str] = Field(default_factory=list, max_length=100)
    publication_year: int | None = Field(default=None, ge=1500, le=2200)
    journal: str | None = Field(default=None, max_length=1_000)
    doi: str | None = Field(default=None, max_length=255)


class AiPaperExtraction(BaseModel):
    metadata: AiPaperMetadata = Field(default_factory=AiPaperMetadata)
    components: list[AiComponent] = Field(min_length=1, max_length=11)

    @model_validator(mode="after")
    def parameters_must_be_unique(self) -> "AiPaperExtraction":
        parameters = [component.parameter for component in self.components]
        if len(parameters) != len(set(parameters)):
            raise ValueError("Each academic parameter may appear only once")
        missing = set(ExtractionParameter) - set(parameters)
        if missing:
            raise ValueError(
                "Missing academic parameters: "
                + ", ".join(sorted(parameter.value for parameter in missing))
            )
        return self


@dataclass(frozen=True)
class VerifiedEvidence:
    paper_block_id: UUID
    quote: str
    page_number: int


@dataclass(frozen=True)
class VerifiedComponent:
    parameter: ExtractionParameter
    value: str
    confidence: float
    evidence: tuple[VerifiedEvidence, ...]


@dataclass(frozen=True)
class VerifiedPaperExtraction:
    metadata: AiPaperMetadata
    components: tuple[VerifiedComponent, ...]
    model_name: str
    prompt_version: str = PROMPT_VERSION


class GeminiExtractionError(RuntimeError):
    def __init__(self, message: str, *, transient: bool = False) -> None:
        super().__init__(message)
        self.transient = transient


def extract_academic_components(
    blocks: list[dict[str, object]],
) -> VerifiedPaperExtraction:
    settings = get_settings()
    if not settings.gemini_api_key:
        raise GeminiExtractionError("Gemini API key belum dikonfigurasi")
    if not blocks:
        raise GeminiExtractionError("Teks halaman belum tersedia untuk dianalisis")

    prompt = build_prompt(blocks, max_chars=settings.gemini_max_input_chars)
    client = genai.Client(api_key=settings.gemini_api_key)
    models = [settings.gemini_model]
    if (
        settings.gemini_fallback_model
        and settings.gemini_fallback_model not in models
    ):
        models.append(settings.gemini_fallback_model)
    extraction: AiPaperExtraction | None = None
    used_model = settings.gemini_model
    last_transient: Exception | None = None
    for index, model in enumerate(models):
        try:
            response = client.models.generate_content(
                model=model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema=AiPaperExtraction,
                ),
            )
            parsed = response.parsed
            extraction = (
                parsed
                if isinstance(parsed, AiPaperExtraction)
                else AiPaperExtraction.model_validate_json(response.text or "")
            )
            used_model = model
            break
        except Exception as exc:
            message = str(exc)
            transient = any(
                marker in message.upper()
                for marker in ("429", "503", "RESOURCE_EXHAUSTED", "UNAVAILABLE")
            )
            if transient and index < len(models) - 1:
                last_transient = exc
                continue
            last_transient = exc
            break

    if extraction is None:
        exc = last_transient or RuntimeError("Gemini tidak mengembalikan hasil")
        message = str(exc)
        if "429" in message or "RESOURCE_EXHAUSTED" in message.upper():
            raise GeminiExtractionError(
                "Kuota Gemini sedang habis. Menunggu sebelum mencoba lagi.",
                transient=True,
            ) from exc
        if "503" in message or "UNAVAILABLE" in message.upper():
            raise GeminiExtractionError(
                "Gemini sedang sibuk. Modellyng akan mencoba lagi otomatis.",
                transient=True,
            ) from exc
        if "API_KEY" in message.upper() or "401" in message or "403" in message:
            raise GeminiExtractionError(
                "Gemini API key ditolak. Perbarui key backend lalu proses ulang."
            ) from exc
        raise GeminiExtractionError(
            "Gemini belum dapat mengekstrak dokumen ini. Silakan proses ulang."
        ) from exc

    return verify_extraction(extraction, blocks, used_model)


def build_prompt(blocks: list[dict[str, object]], *, max_chars: int) -> str:
    instructions = """
Anda adalah pengekstrak paper akademik untuk Modellyng.
Gunakan HANYA isi dokumen di bawah ini. Jangan memakai pengetahuan luar.
Tulis ringkasan komponen dalam Bahasa Indonesia, tetapi pertahankan kutipan
bukti persis seperti bahasa sumber. Kembalikan tepat satu entri untuk setiap
parameter berikut: research_problem, research_objective, research_question,
methodology, dataset_sample, variables_concepts, results_findings,
contribution, limitations, future_work, key_claims.

Untuk setiap komponen:
- value harus ringkas, faktual, dan tidak melebih-lebihkan isi paper.
- evidence berisi 1-3 kutipan verbatim dengan page_number yang benar.
- jika informasi tidak dinyatakan, value harus menjelaskan bahwa informasi
  tidak ditemukan, confidence rendah, dan evidence boleh kosong.
- jangan mengarang kutipan, halaman, penulis, DOI, jurnal, atau tahun.

Dokumen:
""".strip()
    remaining = max_chars - len(instructions)
    if remaining <= 0:
        raise GeminiExtractionError("Batas input Gemini terlalu kecil")

    sections: list[str] = []
    used = 0
    for block in sorted(
        blocks,
        key=lambda item: (int(item["page_number"]), int(item["block_index"])),
    ):
        header = (
            f"\n\n--- PAGE {block['page_number']} / "
            f"BLOCK {block['block_index']} ---\n"
        )
        content = str(block["content"])
        available = remaining - used - len(header)
        if available <= 0:
            break
        section = header + content[:available]
        sections.append(section)
        used += len(section)
        if len(content) > available:
            break
    if not sections:
        raise GeminiExtractionError("Teks PDF tidak cukup untuk dikirim ke Gemini")
    return instructions + "".join(sections)


def verify_extraction(
    extraction: AiPaperExtraction,
    blocks: list[dict[str, object]],
    model_name: str,
) -> VerifiedPaperExtraction:
    blocks_by_page: dict[int, list[dict[str, object]]] = {}
    for block in blocks:
        blocks_by_page.setdefault(int(block["page_number"]), []).append(block)

    verified_components: list[VerifiedComponent] = []
    for component in extraction.components:
        verified_evidence: list[VerifiedEvidence] = []
        for evidence in component.evidence:
            for block in blocks_by_page.get(evidence.page_number, []):
                exact_quote = _find_exact_source_quote(
                    str(block["content"]), evidence.quote
                )
                if exact_quote is not None:
                    verified_evidence.append(
                        VerifiedEvidence(
                            paper_block_id=UUID(str(block["id"])),
                            quote=exact_quote,
                            page_number=evidence.page_number,
                        )
                    )
                    break
        verified_components.append(
            VerifiedComponent(
                parameter=component.parameter,
                value=" ".join(component.value.split()),
                confidence=(
                    component.confidence
                    if verified_evidence
                    else min(component.confidence, 0.35)
                ),
                evidence=tuple(verified_evidence),
            )
        )
    return VerifiedPaperExtraction(
        metadata=extraction.metadata,
        components=tuple(verified_components),
        model_name=model_name,
    )


def _find_exact_source_quote(content: str, requested_quote: str) -> str | None:
    quote = requested_quote.strip()
    if quote in content:
        return quote
    words = re.split(r"\s+", quote)
    if not words:
        return None
    pattern = r"\s+".join(re.escape(word) for word in words)
    match = re.search(pattern, content)
    return match.group(0) if match else None
