from uuid import uuid4

from app.intelligence_service import build_intelligence_report, format_citation
from app.schemas import CitationStyle, ComparativeMatrixRead


def _matrix():
    left, right = uuid4(), uuid4()
    return ComparativeMatrixRead.model_validate({
        "project_id": str(uuid4()), "project_title": "Waste study",
        "papers": [
            {"id": str(left), "title": "Waste behavior", "original_filename": "a.pdf",
             "authors": ["Jane Doe"], "publication_year": 2024, "journal": "Journal A"},
            {"id": str(right), "title": "Sorting behavior", "original_filename": "b.pdf",
             "authors": ["John Roe"], "publication_year": 2023, "journal": "Journal B"},
        ],
        "rows": [{
            "parameter": "variables_concepts",
            "cells": [
                {"paper_id": str(left), "ai_value": "knowledge and attitude", "status": "verified",
                 "confidence": 0.9, "evidence": [{"quote": "knowledge", "page_number": 2, "block_id": "a"}]},
                {"paper_id": str(right), "ai_value": "knowledge and attitude", "status": "verified",
                 "confidence": 0.8, "evidence": [{"quote": "knowledge", "page_number": 3, "block_id": "b"}]},
            ],
        }],
    })


def test_citation_styles_keep_known_metadata_only():
    paper = {"title": "A paper", "authors": ["Jane Doe"], "publication_year": 2024, "journal": "Journal"}
    assert "[1]" in format_citation(paper, CitationStyle.IEEE, 1)
    assert "(2024)" in format_citation(paper, CitationStyle.HARVARD, 1)
    assert "2024" in format_citation(paper, CitationStyle.APA7, 1)


def test_report_contains_clusters_relationships_and_unsupported_claims():
    matrix = _matrix()
    paper_id = str(matrix.papers[0].id)
    report = build_intelligence_report(
        matrix,
        [
            {"id": paper_id, "title": "Waste behavior", "extracted_components": [
                {"id": str(uuid4()), "paper_id": paper_id, "parameter": "key_claims",
                 "ai_value": "unsupported claim", "status": "unsupported", "confidence": 0.2,
                 "is_active": True, "evidence_spans": []},
            ]},
        ],
        citation_style=CitationStyle.APA7,
    )
    assert len(report.references) == 2
    assert report.clusters
    assert any(edge.relation == "structurally_related" for edge in report.relationships)
    assert len(report.unsupported_claims) == 1
