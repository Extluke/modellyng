import pymupdf
import pytest

from app.pdf_processing import PdfExtractionError, extract_pdf


def build_pdf(*, text: str = "", title: str = "", author: str = "") -> bytes:
    document = pymupdf.open()
    page = document.new_page()
    if text:
        page.insert_text((72, 72), text)
    document.set_metadata({"title": title, "author": author})
    content = document.tobytes()
    document.close()
    return content


def test_extract_pdf_reads_page_metadata_and_language() -> None:
    content = build_pdf(
        text=(
            "Penelitian ini adalah kajian sistem dan hasil penelitian "
            "yang digunakan untuk analisis dalam Bahasa Indonesia."
        ),
        title="  Modellyng   Local Extraction  ",
        author="Budi Santoso; Siti Aminah",
    )

    extracted = extract_pdf(content)

    assert extracted.page_count == 1
    assert len(extracted.pages) == 1
    assert "Penelitian ini" in extracted.pages[0].text
    assert extracted.title == "Modellyng Local Extraction"
    assert extracted.authors == ("Budi Santoso", "Siti Aminah")
    assert extracted.language_code == "id"


def test_extract_pdf_rejects_scanned_or_empty_document() -> None:
    with pytest.raises(PdfExtractionError, match="memerlukan OCR"):
        extract_pdf(build_pdf())
