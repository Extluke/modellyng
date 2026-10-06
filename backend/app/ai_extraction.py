from __future__ import annotations

import re
import httpx
from dataclasses import dataclass
from uuid import UUID
from rapidfuzz import fuzz

from google import genai
from google.genai import types
from pydantic import BaseModel, Field, model_validator

from .config import get_settings
from .schemas import ExtractionParameter, EvidenceKind
from .source_verification import BibliographicMetadata
from .source_location import classify_evidence, locate_headings


PROMPT_VERSION = "academic-components-v3-routing-fuzzy"


class AiStructurePart(BaseModel):
    section_name: str = Field(description="Nama bab, misal: Introduction, Method, Result, Discussion, Conclusion")
    is_present: bool = Field(description="Apakah bab ini ada secara eksplisit di dalam teks?")
    page_number: int | None = Field(default=None, description="Halaman di mana bab ini dimulai")


class AiComponent(BaseModel):
    parameter: ExtractionParameter
    evidence_quote: str | None = Field(
        description="Kutipan verbatim (persis sama) dari teks asli. HARUS diisi sebelum membuat ringkasan. Jika tidak ada, isi null."
    )
    page_number: int | None = Field(default=None, ge=1)
    summary_indonesian: str = Field(
        description="Rangkuman dalam Bahasa Indonesia berdasarkan evidence_quote di atas.",
        min_length=1, max_length=4_000
    )
    ai_confidence: int = Field(
        default=95,
        ge=0,
        le=100,
        description="Tingkat keyakinan Anda (0-100) terhadap akurasi rangkuman ini. Jika informasi tidak ditemukan, berikan 100 karena Anda yakin informasi itu tidak ada."
    )


class AiResearchGap(BaseModel):
    evidence_quote: str = Field(description="Kutipan asli yang mengindikasikan adanya research gap.")
    page_number: int = Field(ge=1)
    gap_statement: str = Field(description="Deskripsi research gap dalam Bahasa Indonesia.")
    gap_type: str = Field(description="Jenis gap penelitian (misal: population, methodological, dll.)")
    supporting_section: str = Field(description="Bagian tempat gap ini ditemukan (misal: Future Work, Conclusion, Discussion).")
    ai_confidence: int = Field(
        default=95,
        ge=0,
        le=100,
        description="Tingkat keyakinan Anda (0-100) terhadap penemuan celah penelitian ini."
    )


class AiMethodologyDetail(BaseModel):
    evidence_quote: str | None = Field(
        description="Kutipan verbatim (persis sama) dari teks asli. HARUS diisi sebelum membuat ringkasan. Jika tidak ada, isi null."
    )
    page_number: int | None = Field(default=None, ge=1)
    
    jenis_metodologi: str = Field(description="Format metodologi (Kuantitatif/Kualitatif/Mixed)")
    desain_riset: str = Field(description="Desain riset (misal: Eksperimental / Survei / Studi Kasus)")
    
    # -- Kuantitatif (opsional) --
    variabel: str | None = Field(default=None, description="Hanya untuk Kuantitatif. Misal: X = [...], Y = [...]")
    hipotesis: str | None = Field(default=None, description="Hanya untuk Kuantitatif. Hipotesis penelitian.")
    ukuran_sampel: str | None = Field(default=None, description="Hanya untuk Kuantitatif. Jumlah responden/sampel.")
    teknik_sampling: str | None = Field(default=None, description="Hanya untuk Kuantitatif. Nama teknik sampling.")
    
    # -- Kualitatif (opsional) --
    fokus_riset: str | None = Field(default=None, description="Hanya untuk Kualitatif. Pertanyaan/tujuan eksplorasi.")
    subjek_informan: str | None = Field(default=None, description="Hanya untuk Kualitatif. Jumlah dan deskripsi subjek.")
    teknik_pemilihan: str | None = Field(default=None, description="Hanya untuk Kualitatif. Teknik pemilihan subjek.")
    
    # -- Mixed (opsional) --
    tahap_kuantitatif: str | None = Field(default=None, description="Hanya untuk Mixed Methods. Ringkasan tahap kuantitatif.")
    tahap_kualitatif: str | None = Field(default=None, description="Hanya untuk Mixed Methods. Ringkasan tahap kualitatif.")
    integrasi_analisis: str | None = Field(default=None, description="Hanya untuk Mixed Methods. Cara penggabungan data.")
    
    # -- Overlapping --
    instrumen: str | None = Field(default=None, description="Instrumen pengumpulan data.")
    teknik_analisis: str | None = Field(default=None, description="Teknik analisis data.")
    
    arah_kegiatan: str = Field(description="Membahas narasi isi metodologi, output, dan arah pengembangannya.")
    ai_confidence: int = Field(default=95, ge=0, le=100)

class AiFutureWorkRecommendation(BaseModel):
    rank: int = Field(description="Peringkat prioritas rekomendasi (1, 2, atau 3).")
    judul_rekomendasi: str = Field(description="Judul singkat.")
    alasan_konteks: str = Field(description="Alasan rekomendasi.")
    metode: str = Field(description="Metode yang disarankan.")
    dampak: str = Field(description="Dampak yang diharapkan.")

class AiFutureWorkDetail(BaseModel):
    evidence_quote: str | None = Field(
        description="Kutipan verbatim (persis sama) dari teks asli. HARUS diisi sebelum membuat ringkasan. Jika tidak ada, isi null."
    )
    page_number: int | None = Field(default=None, ge=1)
    arah_pengembangan: str = Field(
        description="Ke arah mana penelitian ini bisa dikembangkan? (potensi aplikasi atau pengembangan lanjutan)"
    )
    recommendations: list[AiFutureWorkRecommendation] = Field(
        description="3 rekomendasi ide penelitian selanjutnya."
    )
    ai_confidence: int = Field(default=95, ge=0, le=100)

class AiPaperMetadata(BibliographicMetadata):
    pass


class AiExtractionRouteResponse(BaseModel):
    components: list[AiComponent] = Field(default_factory=list)
    research_gaps: list[AiResearchGap] = Field(default_factory=list)

class AiPaperExtraction(BaseModel):
    metadata: AiPaperMetadata = Field(default_factory=AiPaperMetadata)
    structure: list[AiStructurePart] = Field(default_factory=list)
    components: list[AiComponent] = Field(default_factory=list)
    methodology: AiMethodologyDetail | None = None
    future_work: AiFutureWorkDetail | None = None
    research_gaps: list[AiResearchGap] = Field(default_factory=list)

    @model_validator(mode="after")
    def parameters_must_be_unique(self) -> "AiPaperExtraction":
        parameters = [component.parameter for component in self.components]
        if len(parameters) != len(set(parameters)):
            raise ValueError("Each academic parameter may appear only once")
        return self


@dataclass(frozen=True)
class VerifiedEvidence:
    paper_block_id: UUID
    quote: str
    page_number: int
    evidence_kind: EvidenceKind = EvidenceKind.TEXT
    source_label: str | None = None
    section: str | None = None
    subsection: str | None = None


@dataclass(frozen=True)
class VerifiedComponent:
    parameter: ExtractionParameter
    value: str
    confidence: float
    is_explicit: bool
    evidence: tuple[VerifiedEvidence, ...]


@dataclass(frozen=True)
class VerifiedStructurePart:
    section_name: str
    is_present: bool
    page_number: int | None

@dataclass(frozen=True)
class VerifiedResearchGap:
    gap_statement: str
    gap_type: str
    supporting_section: str
    confidence: float
    is_explicit: bool
    evidence: tuple[VerifiedEvidence, ...]

@dataclass(frozen=True)
class VerifiedPaperExtraction:
    metadata: AiPaperMetadata
    structure: tuple[VerifiedStructurePart, ...]
    components: tuple[VerifiedComponent, ...]
    research_gaps: tuple[VerifiedResearchGap, ...]
    model_name: str
    prompt_version: str = PROMPT_VERSION


class GeminiExtractionError(RuntimeError):
    def __init__(self, message: str, *, transient: bool = False) -> None:
        super().__init__(message)
        self.transient = transient


def gemini_response_schema() -> dict:
    """Keep the provider grammar small; validate all bounds locally afterwards.

    Combining bounded optional bibliography strings, 100 authors, 11 components
    and evidence arrays can exceed Gemini's structured-output grammar limits.
    Dropping bounds here does not relax AiPaperExtraction or evidence validation.
    """
    omitted = {'title', 'default', 'minLength', 'maxLength', 'minItems', 'maxItems',
               'minimum', 'maximum'}

    def simplify(value):
        if isinstance(value, dict):
            return {
                key: ({name: simplify(schema) for name, schema in item.items()}
                      if key in ('properties', '$defs') else simplify(item))
                for key, item in value.items() if key not in omitted
            }
        if isinstance(value, list):
            return [simplify(item) for item in value]
        return value

    return simplify(AiPaperExtraction.model_json_schema())


def extract_academic_components(
    blocks: list[dict[str, object]],
    route: str = "intro",
) -> VerifiedPaperExtraction:
    settings = get_settings()
    if not settings.gemini_api_key:
        raise GeminiExtractionError("Gemini API key belum dikonfigurasi")
    if not blocks:
        raise GeminiExtractionError("Teks halaman belum tersedia untuk dianalisis")

    prompt = build_prompt(blocks, route, max_chars=settings.gemini_max_input_chars)
    client = genai.Client(api_key=settings.gemini_api_key,
                         http_options=types.HttpOptions(timeout=120_000))
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
                    response_json_schema=gemini_response_schema(),
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
            transient = isinstance(exc, (httpx.TimeoutException, httpx.ConnectError)) or any(
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
        if isinstance(exc, (httpx.TimeoutException, httpx.ConnectError)):
            raise GeminiExtractionError(
                'Koneksi Gemini terputus. Modellyng akan mencoba lagi otomatis.',
                transient=True,
            ) from exc
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


def build_prompt(blocks: list[dict[str, object]], route: str, *, max_chars: int) -> str:
    if route == "intro":
        components = "research_problem, research_objective, research_question"
    elif route == "method":
        components = "methodology, dataset_sample, variables_concepts"
    else:
        components = "results_findings, contribution, limitations, future_work, key_claims"

    instructions = f"""
Anda adalah Asisten Peneliti Akademik (RAG) untuk aplikasi Modellyng.
Tugas Anda mengekstrak informasi spesifik dari teks Bab PDF berikut.

ATURAN EKSTRAKSI (QUOTE-FIRST):
1. Anda WAJIB menarik KUTIPAN VERBATIM (persis sama) dari teks dan menaruhnya di field `evidence_quote`.
2. Setelah mendapat bukti, buat rangkuman di field `summary_indonesian`.
3. Jika poin informasi tidak ditemukan dalam teks yang diberikan, kembalikan null pada quote dan tulis "Informasi tidak ditemukan" pada rangkuman.

TUGAS KOMPONEN:
Fokus hanya mengekstrak komponen ini dari teks berikut:
{components}

Untuk setiap komponen:
- Rangkuman harus ringkas dan faktual.
- WAJIB IKUTI ATURAN FORMAT VALUE:
  1) variables_concepts: WAJIB gunakan format poin-poin ringkas (bullet points dengan awal karakter '- ') untuk setiap objek/konsep.
  2) dataset_sample: JIKA teks berisi dataset/sampel, WAJIB tuliskan 3 baris ini:
      Populasi data dari paper ini adalah: [ISI_DI_SINI]
      Tahap pengumpulan data penelitian ini adalah: [ISI_DI_SINI]
      Teknik analisis data penelitian ini adalah: [ISI_DI_SINI]
     JIKA teks bukan merupakan paper penelitian ilmiah (tidak memiliki sampel/dataset/metode penelitian), tuliskan teks peringatan berikut (tanpa tambahan lain):
      "File yang diunggah tidak terdeteksi sebagai paper penelitian. Silakan unggah file lain yang merupakan jurnal atau paper ilmiah."
  3) methodology: HANYA ISI OBJEK JSON `methodology`. Isi `jenis_metodologi`, `desain_riset`, dan HANYA isi field opsional yang sesuai dengan jenis metodologinya. Isi `arah_kegiatan` dengan narasi isi metodologi.
  4) results_findings: WAJIB fokus menjawab "Output dari penelitian ini apa? (hasil konkret yang dihasilkan)".
  5) future_work: HANYA ISI OBJEK JSON `future_work`. Isi `arah_pengembangan` dengan deskripsi potensi pengembangan. Isi `recommendations` dengan daftar 3 ide penelitian.
  6) research_question: Khusus untuk pertanyaan penelitian, JIKA tidak ditulis secara eksplisit, Anda WAJIB merumuskan (inferensi) pertanyaan penelitian berdasarkan masalah dan tujuan penelitian. JANGAN gunakan "Informasi tidak ditemukan" kecuali sama sekali tidak bisa dirumuskan.
  7) key_claims: Ekstrak argumen atau klaim utama dari penulis yang menjadi simpulan inti paper ini.

Dokumen:
"""
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
    import json
    
    # Process methodology separately and append to components
    if extraction.methodology:
        def get_val(val):
            return val if val and str(val).strip() != "None" else "-"
            
        parts = ["--- BENTUK METODOLOGI ---"]
        
        desain_text = str(extraction.methodology.jenis_metodologi)
        if extraction.methodology.desain_riset and str(extraction.methodology.desain_riset).strip() != "None":
            desain_text += f" ({extraction.methodology.desain_riset})"
            
        jenis_lower = str(extraction.methodology.jenis_metodologi).lower()
        
        if "kuantitatif" in jenis_lower and "mixed" not in jenis_lower:
            parts.append(f"{'Desain Riset'.ljust(18)}: {desain_text}")
            parts.append(f"{'Variabel'.ljust(18)}: {get_val(extraction.methodology.variabel)}")
            parts.append(f"{'Hipotesis'.ljust(18)}: {get_val(extraction.methodology.hipotesis)}")
            parts.append(f"{'Ukuran Sampel'.ljust(18)}: {get_val(extraction.methodology.ukuran_sampel)}")
            parts.append(f"{'Teknik Sampling'.ljust(18)}: {get_val(extraction.methodology.teknik_sampling)}")
            parts.append(f"{'Instrumen'.ljust(18)}: {get_val(extraction.methodology.instrumen)}")
            parts.append(f"{'Teknik Analisis'.ljust(18)}: {get_val(extraction.methodology.teknik_analisis)}")
        elif "kualitatif" in jenis_lower and "mixed" not in jenis_lower:
            parts.append(f"{'Desain Riset'.ljust(18)}: {desain_text}")
            parts.append(f"{'Fokus Riset'.ljust(18)}: {get_val(extraction.methodology.fokus_riset)}")
            parts.append(f"{'Subjek/Informan'.ljust(18)}: {get_val(extraction.methodology.subjek_informan)}")
            parts.append(f"{'Teknik Pemilihan'.ljust(18)}: {get_val(extraction.methodology.teknik_pemilihan)}")
            parts.append(f"{'Instrumen'.ljust(18)}: {get_val(extraction.methodology.instrumen)}")
            parts.append(f"{'Teknik Analisis'.ljust(18)}: {get_val(extraction.methodology.teknik_analisis)}")
        else:
            parts.append(f"{'Desain Riset'.ljust(18)}: {desain_text}")
            parts.append(f"{'Tahap Kuantitatif'.ljust(18)}: {get_val(extraction.methodology.tahap_kuantitatif)}")
            parts.append(f"{'Tahap Kualitatif'.ljust(18)}: {get_val(extraction.methodology.tahap_kualitatif)}")
            parts.append(f"{'Integrasi Analisis'.ljust(18)}: {get_val(extraction.methodology.integrasi_analisis)}")
                
        parts.append("\n--- ARAH KEGIATAN ---")
        parts.append(extraction.methodology.arah_kegiatan)
        
        val = "\n".join(parts)
        
        extraction.components.append(AiComponent(
            parameter=ExtractionParameter.METHODOLOGY,
            evidence_quote=extraction.methodology.evidence_quote,
            page_number=extraction.methodology.page_number,
            summary_indonesian=val,
            ai_confidence=extraction.methodology.ai_confidence
        ))
        
    # Process future_work separately and append to components
    if extraction.future_work:
        val = json.dumps({
            "pengembangan": extraction.future_work.arah_pengembangan,
            "recommendations": [
                {
                    "rank": r.rank,
                    "judul": r.judul_rekomendasi,
                    "alasan": r.alasan_konteks,
                    "metode": r.metode,
                    "dampak": r.dampak
                } for r in extraction.future_work.recommendations
            ]
        }, ensure_ascii=False)
        extraction.components.append(AiComponent(
            parameter=ExtractionParameter.FUTURE_WORK,
            evidence_quote=extraction.future_work.evidence_quote,
            page_number=extraction.future_work.page_number,
            summary_indonesian=val,
            ai_confidence=extraction.future_work.ai_confidence
        ))

    blocks_by_page: dict[int, list[dict[str, object]]] = {}
    for block in blocks:
        blocks_by_page.setdefault(int(block["page_number"]), []).append(block)

    verified_components: list[VerifiedComponent] = []
    for component in extraction.components:
        verified_evidence: list[VerifiedEvidence] = []
        is_explicit = False
        best_score = 0
        best_block = None
        
        if component.evidence_quote:
            # Cari best match dengan RapidFuzz di seluruh atau spesifik blok
            
            # Jika page_number diberikan, prioritaskan halaman tersebut
            search_blocks = blocks_by_page.get(component.page_number, []) if component.page_number else blocks
            if not search_blocks:
                search_blocks = blocks
                
            for block in search_blocks:
                content = str(block["content"])
                score = fuzz.partial_ratio(component.evidence_quote.lower(), content.lower())
                if score > best_score:
                    best_score = score
                    best_block = block
                    
        confidence = float(best_score) / 100.0 if best_score > 0 else 0.5
        
        if best_block and best_score > 85:
                is_explicit = True
                exact_quote = _find_exact_source_quote(str(best_block["content"]), component.evidence_quote) or component.evidence_quote
                section, subsection = locate_headings(blocks, str(best_block["id"]), exact_quote)
                
                verified_evidence.append(
                    VerifiedEvidence(
                        paper_block_id=UUID(str(best_block["id"])),
                        quote=exact_quote,
                        page_number=int(best_block["page_number"]),
                        evidence_kind=EvidenceKind.TEXT,
                        source_label=None,
                        section=section,
                        subsection=subsection,
                    )
                )

        import re
        verified_components.append(
            VerifiedComponent(
                parameter=component.parameter,
                value=re.sub(r'[ \t]+', ' ', component.summary_indonesian).strip(),
                confidence=confidence,
                is_explicit=is_explicit,
                evidence=tuple(verified_evidence),
            )
        )
        
    verified_gaps: list[VerifiedResearchGap] = []
    for gap in extraction.research_gaps:
        verified_evidence_gap: list[VerifiedEvidence] = []
        is_explicit = False
        best_score = 0
        best_block = None
        
        if gap.evidence_quote:
            search_blocks = blocks_by_page.get(gap.page_number, []) if gap.page_number else blocks
            if not search_blocks:
                search_blocks = blocks
                
            for block in search_blocks:
                content = str(block["content"])
                score = fuzz.partial_ratio(gap.evidence_quote.lower(), content.lower())
                if score > best_score:
                    best_score = score
                    best_block = block
                    
        confidence = float(best_score) / 100.0 if best_score > 0 else 0.5
        
        if best_block and best_score > 85:
                is_explicit = True
                exact_quote = _find_exact_source_quote(str(best_block["content"]), gap.evidence_quote) or gap.evidence_quote
                section, subsection = locate_headings(blocks, str(best_block["id"]), exact_quote)
                
                verified_evidence_gap.append(
                    VerifiedEvidence(
                        paper_block_id=UUID(str(best_block["id"])),
                        quote=exact_quote,
                        page_number=int(best_block["page_number"]),
                        evidence_kind=EvidenceKind.TEXT,
                        source_label=None,
                        section=section,
                        subsection=subsection,
                    )
                )
                
        verified_gaps.append(
            VerifiedResearchGap(
                gap_statement=re.sub(r'[ \t]+', ' ', gap.gap_statement).strip(),
                gap_type=gap.gap_type,
                supporting_section=gap.supporting_section,
                confidence=confidence,
                is_explicit=is_explicit,
                evidence=tuple(verified_evidence_gap),
            )
        )

    verified_structure = [
        VerifiedStructurePart(
            section_name=part.section_name,
            is_present=part.is_present,
            page_number=part.page_number
        ) for part in extraction.structure
    ]

    return VerifiedPaperExtraction(
        metadata=extraction.metadata,
        structure=tuple(verified_structure),
        components=tuple(verified_components),
        research_gaps=tuple(verified_gaps),
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
    match = re.search(pattern, content, re.IGNORECASE)
    return match.group(0) if match else None


# --- Phase 2: Knowledge Graph Extraction ---

class AiKnowledgeGraphNode(BaseModel):
    node_type: str = Field(description="Tipe entitas: 'variable', 'method', 'result', 'research_area', 'gap', atau 'concept'.")
    label: str = Field(description="Label/judul node.")
    detail: str = Field(description="Penjelasan.")
    parent_label: str | None = Field(default=None, description="Jika ini sub-konsep, tulis label node induknya (Konsep Payung).")
    gap_typology: str | None = Field(default=None, description="Tipe celah jika node ini adalah 'gap'. (unexplored_concept, missing_relation, dll)")
    confidence_score: int = Field(default=95, ge=0, le=100, description="Tingkat keyakinan (0-100).")
    evidence_quote: str | None = Field(default=None, description="Kutipan terkait dari input JSON.")

class AiKnowledgeGraphEdge(BaseModel):
    source_label: str = Field(description="Label dari node sumber")
    target_label: str = Field(description="Label dari node target")
    relation: str = Field(description="Relasi, misal 'menyebabkan', 'digunakan_untuk', 'menghasilkan'")
    detail: str | None = Field(default=None, description="Penjelasan detail relasi")

class AiKnowledgeGraphExtraction(BaseModel):
    nodes: list[AiKnowledgeGraphNode] = Field(default_factory=list)
    edges: list[AiKnowledgeGraphEdge] = Field(default_factory=list)

def extract_knowledge_graph_from_results(extracted_data_json: str) -> AiKnowledgeGraphExtraction:
    settings = get_settings()
    if not settings.gemini_api_key:
        raise GeminiExtractionError("Gemini API key belum dikonfigurasi")
    
    prompt = f"""Anda adalah sistem ekstraksi Knowledge Graph.
Diberikan hasil ekstraksi penelitian tahap 1 dalam format JSON, tugas Anda adalah mengidentifikasi entitas (nodes) dan relasinya (edges) untuk membentuk jaring laba-laba yang utuh.

ATURAN (Phase 2):
1. Ekstrak entitas penting dari hasil penelitian sebagai Node (tipe: variable, method, result, research_area, gap, concept).
2. Temukan hubungan antar entitas tersebut (misal Method A -> Result B -> Gap C) dan buat sebagai Edges. Pastikan saling terhubung.
3. Tentukan `parent_label` jika sebuah node merupakan sub-bagian dari node lain.
4. Jika node adalah gap, berikan `gap_typology` secara spesifik.
5. Anda WAJIB memberikan format JSON sesuai schema. Anda membaca dari data hasil ekstraksi tahap 1 di bawah ini:

--- DATA TAHAP 1 ---
{extracted_data_json}
"""
    client = genai.Client(api_key=settings.gemini_api_key, http_options=types.HttpOptions(timeout=120_000))
    models = [settings.gemini_model]
    if settings.gemini_fallback_model:
        models.append(settings.gemini_fallback_model)
        
    last_exc = None
    for model in models:
        try:
            response = client.models.generate_content(
                model=model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_json_schema=AiKnowledgeGraphExtraction.model_json_schema(),
                ),
            )
            parsed = response.parsed
            if isinstance(parsed, AiKnowledgeGraphExtraction):
                return parsed
            return AiKnowledgeGraphExtraction.model_validate_json(response.text or "")
        except Exception as exc:
            last_exc = exc
            
    raise GeminiExtractionError(f"Gagal ekstrak Knowledge Graph: {last_exc}")

import json

class EntityExtractionV2(BaseModel):
    variables: list[str] = Field(default_factory=list)
    methods: list[str] = Field(default_factory=list)
    results: list[str] = Field(default_factory=list)

def extract_entities_v2(paper_text: str) -> str:
    """Extract variables, methods, and results as raw JSON string."""
    settings = get_settings()
    if not settings.gemini_api_key:
        raise GeminiExtractionError("Gemini API key belum dikonfigurasi")
    
    prompt = f"""Anda adalah asisten AI akademik. Ekstrak 'variables', 'methods', dan 'results' utama dari teks karya ilmiah berikut.
Jawab HANYA dalam format JSON dengan kunci: "variables", "methods", "results", di mana masing-masing adalah array of strings.
Jangan tambahkan teks apapun selain JSON.

Teks:
{paper_text}
"""
    client = genai.Client(api_key=settings.gemini_api_key, http_options=types.HttpOptions(timeout=120_000))
    models = [settings.gemini_model]
    if settings.gemini_fallback_model:
        models.append(settings.gemini_fallback_model)
        
    last_exc = None
    for model in models:
        try:
            response = client.models.generate_content(
                model=model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_json_schema=EntityExtractionV2.model_json_schema(),
                ),
            )
            return response.text or "{}"
        except Exception as exc:
            last_exc = exc
            
    raise GeminiExtractionError(f"Gagal ekstrak Entities V2: {last_exc}")

def parse_entities_v2(raw: str) -> dict:
    if not raw:
        return {"variables": [], "methods": [], "results": []}
    raw = raw.strip()
    if raw.startswith("```json"):
        raw = raw[7:]
    elif raw.startswith("```"):
        raw = raw[3:]
    if raw.endswith("```"):
        raw = raw[:-3]
    raw = raw.strip()
    try:
        data = json.loads(raw)
        return {
            "variables": data.get("variables", []),
            "methods": data.get("methods", []),
            "results": data.get("results", [])
        }
    except Exception:
        return {"variables": [], "methods": [], "results": []}
