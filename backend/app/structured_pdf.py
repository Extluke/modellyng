from __future__ import annotations

from io import BytesIO
from pathlib import Path
from uuid import UUID

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

from .schemas import PaperResultRead


def build_structured_tables_pdf(result: PaperResultRead) -> bytes:
    buffer = BytesIO()
    font_name = _register_unicode_font()
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        "ModellyngTitle",
        parent=styles["Title"],
        fontName=font_name,
        fontSize=18,
        leading=22,
        textColor=colors.HexColor("#1D2433"),
        spaceAfter=5 * mm,
    )
    heading_style = ParagraphStyle(
        "ModellyngHeading",
        parent=styles["Heading2"],
        fontName=font_name,
        fontSize=12,
        leading=15,
        textColor=colors.HexColor("#4E3FE3"),
        spaceBefore=2 * mm,
        spaceAfter=3 * mm,
    )
    cell_style = ParagraphStyle(
        "ModellyngCell",
        parent=styles["BodyText"],
        fontName=font_name,
        fontSize=7.4,
        leading=9.2,
        textColor=colors.HexColor("#1D2433"),
    )
    header_style = ParagraphStyle(
        "ModellyngHeader",
        parent=cell_style,
        alignment=TA_CENTER,
        textColor=colors.white,
        fontSize=7.2,
        leading=8.6,
    )
    doc = SimpleDocTemplate(
        buffer,
        pagesize=landscape(A4),
        leftMargin=12 * mm,
        rightMargin=12 * mm,
        topMargin=14 * mm,
        bottomMargin=14 * mm,
        title=f"Modellyng - {result.paper.title or result.paper.original_filename}",
        author="Modellyng",
    )
    story = [
        Paragraph("Modellyng - Structured Paper Result", title_style),
        Paragraph(
            _escape(result.paper.title or result.paper.original_filename), cell_style
        ),
        Spacer(1, 4 * mm),
        Paragraph("Tabel Pertanyaan Penelitian", heading_style),
    ]

    rq_rows = [
        [
            _p("No", header_style),
            _p("Pertanyaan", header_style),
            _p("Objek / konsep terkait", header_style),
            _p("Arah pembahasan", header_style),
            _p("Evidence", header_style),
        ]
    ]
    for row in result.structured_tables.research_questions:
        evidence = (
            f"Hal. {row.evidence_page}: {row.evidence_quote}"
            if row.evidence_page and row.evidence_quote
            else "Belum ada evidence terverifikasi"
        )
        rq_rows.append(
            [
                _p(str(row.number), cell_style),
                _p(row.question, cell_style),
                _p(row.related_object, cell_style),
                _p(row.discussion_direction, cell_style),
                _p(evidence, cell_style),
            ]
        )
    if len(rq_rows) == 1:
        rq_rows.append(
            [
                _p("-", cell_style),
                _p("Pertanyaan penelitian belum tersedia.", cell_style),
                _p("-", cell_style),
                _p("-", cell_style),
                _p("-", cell_style),
            ]
        )
    story.append(
        _table(
            rq_rows,
            [12 * mm, 57 * mm, 55 * mm, 55 * mm, 80 * mm],
            repeat_rows=1,
        )
    )
    story.extend([PageBreak(), Paragraph("Tabel Metodologi", heading_style)])
    method_rows = [
        [
            _p("Isi", header_style),
            _p("Bentuk", header_style),
            _p("Kegiatan utama", header_style),
            _p("Arah kegiatan", header_style),
            _p("Tujuan akhir", header_style),
        ]
    ]
    for row in result.structured_tables.methodology:
        method_rows.append(
            [
                _p(row.content, cell_style),
                _p(row.form, cell_style),
                _p(row.main_activity, cell_style),
                _p(row.activity_direction, cell_style),
                _p(row.final_goal, cell_style),
            ]
        )
    if len(method_rows) == 1:
        method_rows.append([_p("Belum tersedia", cell_style)] * 5)
    story.append(_table(method_rows, [52 * mm] * 5, repeat_rows=1))
    story.append(Spacer(1, 6 * mm))
    story.append(
        Paragraph(
            "Catatan: tabel menyusun ulang hasil ekstraksi aktif. Nilai AI tetap "
            "harus direview dan evidence perlu diperiksa pada PDF privat.",
            cell_style,
        )
    )

    doc.build(story, onFirstPage=_page_footer, onLaterPages=_page_footer)
    return buffer.getvalue()


def structured_pdf_filename(paper_id: UUID) -> str:
    return f"modellyng-structured-paper-{paper_id}.pdf"


def _register_unicode_font() -> str:
    candidates = (
        Path("C:/Windows/Fonts/arial.ttf"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
    )
    for path in candidates:
        if path.exists():
            name = "ModellyngSans"
            if name not in pdfmetrics.getRegisteredFontNames():
                pdfmetrics.registerFont(TTFont(name, str(path)))
            return name
    return "Helvetica"


def _escape(value: str) -> str:
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\n", "<br/>")
    )


def _p(value: str, style: ParagraphStyle) -> Paragraph:
    return Paragraph(_escape(value), style)


def _table(rows: list[list[Paragraph]], widths: list[float], *, repeat_rows: int) -> Table:
    table = Table(rows, colWidths=widths, repeatRows=repeat_rows, hAlign="LEFT")
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#5747E8")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("GRID", (0, 0), (-1, -1), 0.45, colors.HexColor("#D9DCE8")),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F7F7FC")]),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    return table


def _page_footer(canvas, doc) -> None:
    canvas.saveState()
    canvas.setFont("Helvetica", 7)
    canvas.setFillColor(colors.HexColor("#6D7488"))
    canvas.drawString(12 * mm, 7 * mm, "Modellyng - evidence-centered research workspace")
    canvas.drawRightString(285 * mm, 7 * mm, f"Halaman {doc.page}")
    canvas.restoreState()
