from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.ai_extraction import (
    AiComponent,
    AiPaperExtraction,
    GeminiExtractionError,
    build_prompt,
    verify_extraction,
    gemini_response_schema,
)
from app.schemas import ExtractionParameter


def test_provider_schema_keeps_types_and_local_validation_keeps_bounds():
    import json
    schema = gemini_response_schema()
    serialized = json.dumps(schema)
    assert 'maxLength' not in serialized
    assert 'maxItems' not in serialized
    assert set(schema['$defs']['ExtractionParameter']['enum']) == {p.value for p in ExtractionParameter}
    assert 'metadata' in schema['properties']
    assert 'title' in schema['$defs']['AiPaperMetadata']['properties']
    with pytest.raises(ValidationError):
        AiComponent(parameter=ExtractionParameter.RESEARCH_PROBLEM, summary_indonesian="short", evidence_quote='x', page_number=0)

def _complete_extraction(*, quote: str = None) -> AiPaperExtraction:
    return AiPaperExtraction(
        components=[
            AiComponent(
                parameter=parameter,
                summary_indonesian=f"Nilai {parameter.value}",
                evidence_quote=quote if index == 0 else None,
                page_number=1 if index == 0 and quote else None,
            )
            for index, parameter in enumerate(ExtractionParameter)
        ],
        structure=[],
        research_gaps=[],
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
        "intro",
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
    extraction = _complete_extraction(quote="Tujuan penelitian adalah mengukur literasi digital mahasiswa.")

    verified = verify_extraction(extraction, blocks, "test-model")

    first = verified.components[0]
    assert len(first.evidence) == 1
    assert first.evidence[0].paper_block_id == block_id
    assert first.confidence > 0.8
    assert verified.components[1].confidence == 0.5





def test_transient_gemini_error_is_explicitly_retryable() -> None:
    error = GeminiExtractionError("Gemini sibuk", transient=True)
    assert error.transient is True
