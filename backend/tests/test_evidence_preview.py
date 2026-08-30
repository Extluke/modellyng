import pymupdf
import pytest

from app.evidence_preview import build_evidence_page_preview


def _sample_pdf() -> bytes:
    document = pymupdf.open()
    page = document.new_page(width=400, height=500)
    page.insert_textbox(
        pymupdf.Rect(40, 40, 360, 180),
        "The supporting evidence states that the survey covered five cities "
        "and included two hundred participants in the final sample.",
        fontsize=12,
    )
    content = document.tobytes()
    document.close()
    return content


def test_evidence_preview_renders_only_requested_page_as_png() -> None:
    png = build_evidence_page_preview(
        _sample_pdf(),
        1,
        "the survey covered five cities and included two hundred participants",
    )
    assert png.startswith(b"\x89PNG\r\n\x1a\n")
    image = pymupdf.open(stream=png, filetype="png")
    assert image.page_count == 1
    image.close()


def test_evidence_preview_rejects_page_outside_document() -> None:
    with pytest.raises(ValueError, match="Halaman evidence"):
        build_evidence_page_preview(_sample_pdf(), 2, "supporting evidence")
