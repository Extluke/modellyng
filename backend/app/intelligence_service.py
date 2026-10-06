"""Evidence-preserving project intelligence reports.

The report deliberately uses reviewed component values and keeps every claim
linked to its paper/component.  Similarity and clustering are deterministic
summaries; they are discovery aids and never promoted to a verified finding.
"""

from collections import defaultdict
from datetime import datetime, timezone
import re
from typing import Any
from uuid import UUID

import httpx

from .auth import AuthenticatedUser
from .comparison_repository import comparison_repository
from .comparison_models import Outcome
from .config import get_settings
from .repository import project_repository
from .schemas import (
    CitationStyle,
    ComparativeMatrixRead,
    IntelligenceReportRead,
    ReferenceEntryRead,
    RelationshipRead,
    ResearchClusterRead,
    StructuralPaperRead,
    UnsupportedClaimRead,
)

_STOPWORDS = {
    "and", "the", "of", "in", "on", "for", "with", "to", "a", "an",
    "dan", "yang", "dari", "pada", "untuk", "dengan", "di", "ke", "atau",
    "research", "study", "analysis", "penelitian", "studi", "analisis",
}


def _tokens(value: str) -> set[str]:
    return {
        token for token in re.findall(r"[a-z0-9]{3,}", value.lower())
        if token not in _STOPWORDS
    }


def _author_name(author: str) -> str:
    parts = [part for part in re.split(r"\s+", author.strip()) if part]
    return parts[-1] if parts else ""


def _initials(author: str) -> str:
    parts = [part for part in re.split(r"\s+", author.strip()) if part]
    if not parts:
        return ""
    surname = parts[-1]
    initials = " ".join(f"{part[0]}." for part in parts[:-1] if part)
    return f"{surname}, {initials}".strip(", ")


def format_citation(paper: dict[str, Any], style: CitationStyle, number: int) -> str:
    """Format a conservative bibliography entry without inventing metadata."""
    title = str(paper.get("title") or paper.get("original_filename") or "Untitled paper").strip()
    authors = [str(value).strip() for value in (paper.get("authors") or []) if str(value).strip()]
    year = paper.get("publication_year") or "n.d."
    journal = str(paper.get("journal") or "").strip()
    publisher = str(paper.get("publisher") or "").strip()
    doi = str(paper.get("doi") or "").strip()
    venue = journal or publisher
    doi_text = f" https://doi.org/{doi}" if doi else ""
    if style == CitationStyle.IEEE:
        author_text = ", ".join(_initials(author) for author in authors) or "Unknown author"
        pieces = [f"[{number}] {author_text}, \"{title},\""]
        if venue:
            pieces.append(venue + ",")
        pieces.append(f"{year}.")
        return " ".join(pieces) + (f" doi: {doi}." if doi else "")
    if style == CitationStyle.HARVARD:
        author_text = ", ".join(_author_name(author) for author in authors) or "Unknown author"
        suffix = f" {venue}." if venue else "."
        return f"{author_text} ({year}) ‘{title}’.{suffix}{doi_text}".strip()
    if style == CitationStyle.VANCOUVER:
        author_text = ", ".join(_author_name(author) for author in authors) or "Unknown author"
        suffix = f" {venue}." if venue else "."
        return f"{author_text}. {title}. {year}.{suffix}{doi_text}".strip()
    if style == CitationStyle.CHICAGO:
        author_text = ", ".join(authors) or "Unknown author"
        venue_text = f" {venue}" if venue else ""
        return f"{author_text}. \"{title}.\"{venue_text} ({year}).{doi_text}".strip()
    # APA 7 (default): preserve full author strings supplied by metadata.
    author_text = ", ".join(authors) or "Unknown author"
    venue_text = f" {venue}." if venue else "."
    return f"{author_text} ({year}). {title}.{venue_text}{doi_text}".strip()


def format_in_text_citation(paper: dict[str, Any], style: CitationStyle, number: int) -> str:
    authors = [str(value).strip() for value in (paper.get("authors") or []) if str(value).strip()]
    surname = _author_name(authors[0]) if authors else "Unknown"
    year = paper.get("publication_year") or "n.d."
    if style in {CitationStyle.IEEE, CitationStyle.VANCOUVER}:
        return f"[{number}]"
    if style == CitationStyle.CHICAGO:
        return f"({surname} {year})"
    if len(authors) > 2:
        surname = f"{surname} et al."
    return f"({surname}, {year})"


def _value(cell: Any) -> str:
    return (cell.final_value or cell.ai_value or "").strip()


def build_intelligence_report(
    matrix: ComparativeMatrixRead,
    raw_papers: list[dict[str, Any]],
    *,
    citation_style: CitationStyle,
    comparison_pairs: list[dict[str, Any]] | None = None,
    candidate_gap_count: int = 0,
) -> IntelligenceReportRead:
    raw_by_id = {str(row.get("id")): row for row in raw_papers}
    papers: list[StructuralPaperRead] = []
    references: list[ReferenceEntryRead] = []
    structure_by_paper: dict[str, dict[str, str]] = defaultdict(dict)
    evidence_counts: dict[str, int] = defaultdict(int)
    parameter_by_paper: dict[str, dict[str, Any]] = defaultdict(dict)
    for row in matrix.rows:
        for cell in row.cells:
            value = _value(cell)
            if not value:
                continue
            parameter_by_paper[str(cell.paper_id)][row.parameter.value] = cell
            structure_by_paper[str(cell.paper_id)][row.parameter.value] = value
            evidence_counts[str(cell.paper_id)] += len(cell.evidence)
    for index, paper in enumerate(matrix.papers, start=1):
        row = raw_by_id.get(str(paper.id), {})
        identity = {
            "title": paper.title,
            "authors": paper.authors,
            "publication_year": paper.publication_year,
            "journal": paper.journal,
            "conference_or_journal": paper.journal,
            "doi": paper.doi,
            "publisher": paper.publisher,
            "publication_status": paper.publication_status,
        }
        papers.append(StructuralPaperRead(
            paper_id=paper.id,
            title=paper.title,
            identity=identity,
            research_structure=structure_by_paper.get(str(paper.id), {}),
            evidence_count=evidence_counts.get(str(paper.id), 0),
        ))
        references.append(ReferenceEntryRead(
            paper_id=paper.id,
            citation=format_citation({**row, **identity}, citation_style, index),
            in_text_citation=format_in_text_citation({**row, **identity}, citation_style, index),
            title=paper.title,
            authors=paper.authors,
            publication_year=paper.publication_year,
            journal=paper.journal,
            publisher=paper.publisher,
            doi=paper.doi,
        ))

    relationships: list[RelationshipRead] = []
    for paper in matrix.papers:
        paper_key = str(paper.id)
        for parameter, cell in parameter_by_paper.get(paper_key, {}).items():
            component_id = f"component:{paper_key}:{parameter}"
            relationships.append(RelationshipRead(
                source_id=f"paper:{paper_key}", target_id=component_id,
                relation="contains", detail=parameter, paper_ids=[paper.id],
            ))
            if parameter in {"results_findings", "contribution"}:
                relationships.append(RelationshipRead(
                    source_id=component_id, target_id=f"result:{paper_key}",
                    relation="contributes_to_result", detail=_value(cell), paper_ids=[paper.id],
                ))
            for evidence in cell.evidence:
                relationships.append(RelationshipRead(
                    source_id=component_id,
                    target_id=f"evidence:{paper_key}:{evidence.page_number}:{evidence.block_id}",
                    relation="supported_by", detail=evidence.quote, paper_ids=[paper.id],
                ))

    clusters: list[ResearchClusterRead] = []
    for kind, parameter in (
        ("research_topic", "research_problem"),
        ("concept", "variables_concepts"),
        ("method", "methodology"),
    ):
        entries = []
        for paper in matrix.papers:
            value = structure_by_paper.get(str(paper.id), {}).get(parameter, "")
            terms = _tokens(value)
            if terms:
                entries.append((paper.id, terms))
        for index, (paper_id, terms) in enumerate(entries):
            members = [paper_id]
            shared = set(terms)
            for other_id, other_terms in entries[index + 1:]:
                overlap = terms & other_terms
                if overlap:
                    members.append(other_id)
                    shared &= other_terms
            if len(members) >= 2:
                clusters.append(ResearchClusterRead(
                    id=f"cluster:{kind}:{index}", kind=kind,
                    label=f"{kind.replace('_', ' ').title()} · {parameter}",
                    paper_ids=members, shared_terms=sorted(shared or terms)[:8],
                ))
    for left_index, left in enumerate(matrix.papers):
        left_values = structure_by_paper.get(str(left.id), {})
        for right in matrix.papers[left_index + 1:]:
            right_values = structure_by_paper.get(str(right.id), {})
            shared_parameters = sorted(set(left_values) & set(right_values))
            if shared_parameters:
                relationships.append(RelationshipRead(
                    source_id=f"paper:{left.id}", target_id=f"paper:{right.id}",
                    relation="structurally_related", detail=", ".join(shared_parameters),
                    paper_ids=[left.id, right.id],
                ))

    unsupported: list[UnsupportedClaimRead] = []
    for paper in raw_papers:
        paper_title = str(paper.get("title") or paper.get("original_filename") or "Paper")
        for component in paper.get("extracted_components") or []:
            if not component.get("is_active", True):
                continue
            status = str(component.get("status") or "needs_review")
            evidence_count = len(component.get("evidence_spans") or [])
            if status not in {"unsupported", "rejected"} and evidence_count:
                continue
            reason = "Status ditolak oleh reviewer" if status == "rejected" else (
                "Status unsupported oleh reviewer" if status == "unsupported" else
                "Belum memiliki evidence yang tertaut"
            )
            unsupported.append(UnsupportedClaimRead(
                component_id=UUID(str(component["id"])), paper_id=UUID(str(paper["id"])),
                paper_title=paper_title, parameter=component["parameter"],
                claim=str(component.get("final_value") or component.get("ai_value") or ""),
                status=status, confidence=component.get("confidence"),
                evidence_count=evidence_count, reason=reason,
            ))

    pairs = comparison_pairs or []
    candidates = sum(1 for pair in pairs if (pair.get("result") or {}).get("outcome") == Outcome.CANDIDATE)
    accepted = sum(
        1 for pair in pairs
        if any(review.get("decision") == "accepted" for review in pair.get("reviews") or [])
    )
    if pairs:
        synthesis = (
            f"Perbandingan terstruktur menemukan {len(pairs)} pasangan paper; "
            f"{candidates} pasangan ditandai sebagai kandidat research gap dan "
            f"{accepted} sudah diterima reviewer. Kandidat tetap memerlukan validasi manusia."
        )
    else:
        synthesis = (
            "Belum ada hasil perbandingan pasangan paper yang selesai. "
            "Lengkapi review evidence dan jalankan analisis untuk menghasilkan kandidat gap."
        )
    return IntelligenceReportRead(
        project_id=matrix.project_id, project_title=matrix.project_title,
        citation_style=citation_style, references=references, papers=papers,
        relationships=relationships, relationship_count=len(relationships),
        clusters=clusters, unsupported_claims=unsupported,
        candidate_gap_count=candidate_gap_count, comparison_count=len(pairs),
        candidate_comparison_count=candidates, accepted_comparison_count=accepted,
        synthesis=synthesis, generated_at=datetime.now(timezone.utc),
    )


async def _load_raw_papers(user: AuthenticatedUser, project_id: UUID) -> list[dict[str, Any]]:
    settings = get_settings()
    select = (
        "id,title,original_filename,authors,publication_year,journal,publisher,doi,"
        "publication_status,extracted_components(id,paper_id,parameter,ai_value,final_value,"
        "status,confidence,is_active,evidence_spans(quote,page_number))"
    )
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.get(
            f"{settings.supabase_url.rstrip('/')}/rest/v1/papers",
            headers=project_repository._headers(user),
            params={"select": select, "project_id": f"eq.{project_id}", "order": "created_at.asc"},
        )
    project_repository._raise_for_repository_error(response)
    return response.json()


async def get_project_intelligence_report(
    user: AuthenticatedUser, project_id: UUID, citation_style: CitationStyle,
) -> IntelligenceReportRead:
    matrix = await project_repository.get_comparative_matrix(user, project_id)
    raw_papers = await _load_raw_papers(user, project_id)
    gap_map = await project_repository.get_research_gap_map(user, project_id)
    pairs: list[dict[str, Any]] = []
    try:
        overview = await comparison_repository.get(user, project_id)
        pairs = [pair.model_dump(mode="json") for pair in overview.pairs]
    except Exception:
        # Reports remain useful when the optional comparison migration/worker is offline.
        pairs = []
    return build_intelligence_report(
        matrix, raw_papers, citation_style=citation_style,
        comparison_pairs=pairs, candidate_gap_count=gap_map.candidate_count,
    )

def calculate_node_saturation(project_nodes: list[dict[str, Any]]) -> None:
    """
    Menghitung agregasi saturasi riset.
    Mutasi in-place list dict project_nodes untuk menambahkan 'saturation_status'.
    Kriteria (sementara):
    - > 5 paper: HIGH (Banyak diteliti / Hijau)
    - 3 - 5 paper: MEDIUM (Cukup / Kuning)
    - 1 - 2 paper: LOW (Jarang / Oranye)
    - 0 paper (hanya muncul sbg ide/gap): NONE (Belum diteliti / Merah)
    """
    from collections import defaultdict
    
    label_counts = defaultdict(set)
    # Asumsikan tiap node memiliki 'paper_id' jika ia berasal dari suatu paper
    for node in project_nodes:
        label = str(node.get("label") or "").strip().lower()
        if not label:
            continue
        # Jika node terafiliasi dengan paper tertentu, tambahkan
        paper_id = node.get("paper_id")
        if paper_id:
            label_counts[label].add(paper_id)
            
    for node in project_nodes:
        if node.get("node_type") == "gap":
            node["saturation_status"] = "none"
        else:
            label = str(node.get("label") or "").strip().lower()
            count = len(label_counts[label])
            if count > 5:
                node["saturation_status"] = "high"
            elif count >= 3:
                node["saturation_status"] = "medium"
            else:
                node["saturation_status"] = "low"
