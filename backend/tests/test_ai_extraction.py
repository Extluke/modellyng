from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.ai_extraction import (
    AiComponent,
    AiEvidence,
    AiPaperExtraction,
    GeminiExtractionError,
    build_prompt,
    verify_extraction,
)
from app.schemas import ExtractionParameter


def _complete_extraction(*, evidence: list[AiEvidence]) -> AiPaperExtraction:
    return AiPaperExtraction(
        components=[
            AiComponent(
                parameter=parameter,
                value=f"Nilai {parameter.value}",
                confidence=0.9,
                evidence=evidence if index == 0 else [],
            )
            for index, parameter in enumerate(ExtractionParameter)
        ]
    )


def test_build_prompt_keeps_page_markers_and_respects_limit() -> None:
    prompt = build_prompt(
        [
            {
                "id": uuid4(),
                "block_index": 0,
                "page_number": 1,
                "content": "Metode penelitian menggunakan survei.",
            }
        ],
        max_chars=10_000,
    )

    assert "PAGE 1 / BLOCK 0" in prompt
    assert "Metode penelitian menggunakan survei." in prompt


def test_verify_extraction_keeps_only_quotes_present_on_the_claimed_page() -> None:
    block_id = uuid4()
    blocks = [
        {
            "id": block_id,
            "block_index": 0,
            "page_number": 1,
            "content": "Tujuan penelitian adalah mengukur literasi digital mahasiswa.",
        }
    ]
    extraction = _complete_extraction(
        evidence=[
            AiEvidence(
                quote="Tujuan penelitian adalah mengukur literasi digital mahasiswa.",
                page_number=1,
            ),
            AiEvidence(quote="Kutipan yang tidak ada di PDF", page_number=1),
        ]
    )

    verified = verify_extraction(extraction, blocks, "test-model")

    first = verified.components[0]
    assert len(first.evidence) == 1
    assert first.evidence[0].paper_block_id == block_id
    assert first.confidence == 0.9
    assert verified.components[1].confidence == 0.35


def test_ai_schema_requires_all_academic_parameters() -> None:
    with pytest.raises(ValidationError, match="Missing academic parameters"):
        AiPaperExtraction(
            components=[
                AiComponent(
                    parameter=ExtractionParameter.METHODOLOGY,
                    value="Survei",
                    confidence=0.8,
                )
            ]
        )


def test_transient_gemini_error_is_explicitly_retryable() -> None:
    error = GeminiExtractionError("Gemini sibuk", transient=True)
    assert error.transient is True
