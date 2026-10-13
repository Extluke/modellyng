import json

import pytest

from app.ai_text import readable_component_value
from app.export_service import build_project_export
from app.schemas import ComparativeMatrixRead

FUTURE_WORK = json.dumps(
    {
        "pengembangan": "Perluas uji ke kota pesisir lain.",
        "recommendations": [
            {
                "rank": 1,
                "judul": "Model banjir multi-kota",
                "alasan": "Data hanya satu kota.",
                "metode": "Studi komparatif",
                "dampak": "Generalisasi lebih kuat",
            },
            {"rank": 2, "judul": "Sensor murah", "alasan": None, "metode": "", "dampak": "Biaya turun"},
        ],
    },
    ensure_ascii=False,
)


def _no_json_marks(text: str) -> bool:
    return not any(mark in text for mark in "{}[]\"")


def test_future_work_json_becomes_numbered_text() -> None:
    text = readable_component_value(FUTURE_WORK)

    assert _no_json_marks(text)
    assert text.splitlines()[0] == "Perluas uji ke kota pesisir lain."
    assert "1. Model banjir multi-kota" in text
    assert "   Alasan: Data hanya satu kota." in text
    assert "   Metode: Studi komparatif" in text
    assert "2. Sensor murah" in text
    assert "   Dampak: Biaya turun" in text
    # Nilai kosong atau null tidak dicetak sebagai "None"/"null".
    assert "None" not in text and "null" not in text


def test_plain_text_is_returned_unchanged() -> None:
    assert readable_component_value("Metode survei kepada 200 responden.") == (
        "Metode survei kepada 200 responden."
    )
    assert readable_component_value("") == ""
    assert readable_component_value(None) == ""


def test_markdown_code_fence_is_unwrapped() -> None:
    text = readable_component_value(f"```json\n{FUTURE_WORK}\n```")

    assert _no_json_marks(text)
    assert "1. Model banjir multi-kota" in text


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ('{"title": "Ide A", "idea": "x"}', "Title: Ide A"),
        ('[{"rank": 1, "judul": "A"}, "B"]', "• B"),
        ('{"arah_kegiatan": "Uji", "detail": {"durasi": "3 bulan"}}', "Durasi: 3 bulan"),
    ],
)
def test_other_json_shapes_are_readable(raw: str, expected: str) -> None:
    text = readable_component_value(raw)

    assert _no_json_marks(text)
    assert expected in text


def test_alternative_recommendation_keys_are_understood() -> None:
    raw = json.dumps({"recommendations": [{"title": "Ide pengganti", "rationale": "Alasan", "impact": "Dampak"}]})

    text = readable_component_value(raw)

    assert "1. Ide pengganti" in text
    assert "Alasan: Alasan" in text
    assert "Dampak: Dampak" in text


def test_broken_json_is_still_cleaned_up() -> None:
    broken = '{"pengembangan": "Perluas uji", "recommendations": [{"rank": 1, "judul": "Model'

    text = readable_component_value(broken)

    assert _no_json_marks(text)
    assert "Pengembangan: Perluas uji" in text
    assert "Judul: Model" in text


def test_empty_json_object_becomes_empty_text() -> None:
    assert readable_component_value("{}") == ""


def test_exports_contain_readable_future_work() -> None:
    matrix = ComparativeMatrixRead.model_validate(
        {
            "project_id": "00000000-0000-0000-0000-000000000010",
            "project_title": "Banjir",
            "papers": [
                {"id": "00000000-0000-0000-0000-000000000020", "title": "Paper Banjir", "original_filename": "banjir.pdf"}
            ],
            "rows": [
                {
                    "parameter": "future_work",
                    "cells": [
                        {
                            "paper_id": "00000000-0000-0000-0000-000000000020",
                            "ai_value": FUTURE_WORK,
                            "final_value": None,
                            "status": "verified",
                            "confidence": 0.8,
                            "evidence": [],
                        }
                    ],
                }
            ],
        }
    )

    content = build_project_export(matrix, "csv").content.decode("utf-8-sig")

    assert "1. Model banjir multi-kota" in content
    assert '"recommendations"' not in content
    assert "pengembangan" not in content
