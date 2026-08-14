from __future__ import annotations

import re
from dataclasses import dataclass

import pymupdf


class PdfExtractionError(ValueError):
    pass


@dataclass(frozen=True)
class ExtractedPage:
    page_number: int
    text: str


@dataclass(frozen=True)
class ExtractedPdf:
    page_count: int
    pages: tuple[ExtractedPage, ...]
    title: str | None
    authors: tuple[str, ...]
    language_code: str


def extract_pdf(content: bytes) -> ExtractedPdf:
    try:
        document = pymupdf.open(stream=content, filetype="pdf")
    except Exception as exc:
        raise PdfExtractionError("PDF rusak atau tidak dapat dibuka") from exc

    try:
        if document.needs_pass:
            raise PdfExtractionError(
                "PDF dilindungi kata sandi dan belum dapat diproses"
            )
        if document.page_count < 1:
            raise PdfExtractionError("PDF tidak memiliki halaman yang dapat diproses")

        pages: list[ExtractedPage] = []
        combined_text: list[str] = []
        for page_index, page in enumerate(document):
            text = page.get_text("text", sort=True).strip()
            if text:
                pages.append(
                    ExtractedPage(page_number=page_index + 1, text=text)
                )
                combined_text.append(text)

        searchable_text = "\n".join(combined_text)
        if len(searchable_text.strip()) < 20:
            raise PdfExtractionError(
                "PDF tidak memiliki teks yang dapat dibaca. Dokumen kemungkinan "
                "berupa hasil pindai dan memerlukan OCR"
            )

        metadata = document.metadata or {}
        title = _clean_metadata(metadata.get("title"))
        authors = _parse_authors(metadata.get("author"))
        return ExtractedPdf(
            page_count=document.page_count,
            pages=tuple(pages),
            title=title,
            authors=authors,
            language_code=_detect_language(searchable_text),
        )
    finally:
        document.close()


def _clean_metadata(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = " ".join(value.split()).strip()
    return cleaned or None


def _parse_authors(value: str | None) -> tuple[str, ...]:
    cleaned = _clean_metadata(value)
    if not cleaned:
        return ()
    parts = re.split(r"\s*(?:;|\band\b|\n)\s*", cleaned, flags=re.IGNORECASE)
    return tuple(part for part in parts if part)


def _detect_language(text: str) -> str:
    words = re.findall(r"[a-zA-Z]+", text[:50_000].lower())
    if not words:
        return "und"
    word_set = set(words)
    indonesian_markers = {
        "adalah",
        "dan",
        "dengan",
        "dalam",
        "dari",
        "hasil",
        "penelitian",
        "yang",
        "untuk",
    }
    english_markers = {
        "and",
        "are",
        "from",
        "in",
        "of",
        "research",
        "results",
        "the",
        "this",
        "with",
    }
    indonesia_score = len(word_set & indonesian_markers)
    english_score = len(word_set & english_markers)
    if indonesia_score == english_score == 0:
        return "und"
    return "id" if indonesia_score > english_score else "en"
