from __future__ import annotations

import re

import pymupdf


def build_evidence_page_preview(
    pdf_bytes: bytes,
    page_number: int,
    evidence_text: str,
) -> bytes:
    """Render one evidence page as a highlighted PNG without opening a full viewer."""
    document = pymupdf.open(stream=pdf_bytes, filetype="pdf")
    try:
        if page_number < 1 or page_number > document.page_count:
            raise ValueError("Halaman evidence tidak tersedia di PDF")
        page = document.load_page(page_number - 1)
        for rectangle in _find_evidence_rectangles(page, evidence_text):
            annotation = page.add_highlight_annot(rectangle)
            annotation.set_colors(stroke=(1.0, 0.72, 0.0))
            annotation.update(opacity=0.5)
        pixmap = page.get_pixmap(matrix=pymupdf.Matrix(1.6, 1.6), alpha=False)
        return pixmap.tobytes("png")
    finally:
        document.close()


def _find_evidence_rectangles(
    page: pymupdf.Page, evidence_text: str
) -> list[pymupdf.Rect]:
    words = re.findall(r"\S+", evidence_text)
    # Extracted blocks can differ slightly from PDF text spacing. Search several
    # overlapping phrases; this also highlights a paragraph across multiple lines.
    for phrase_size in (18, 12, 8, 5):
        if len(words) < phrase_size:
            continue
        rectangles: list[pymupdf.Rect] = []
        step = max(1, phrase_size // 2)
        for start in range(0, len(words) - phrase_size + 1, step):
            phrase = " ".join(words[start : start + phrase_size])
            rectangles.extend(page.search_for(phrase))
        if rectangles:
            return rectangles
    return page.search_for(" ".join(words)) if words else []
