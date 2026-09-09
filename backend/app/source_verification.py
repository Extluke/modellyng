"""Bibliographic registry checks, separate from human approval and PDF authenticity.

Only a DOI is sent to fixed public registry endpoints. Never send PDF text,
credentials, user IDs, or follow publisher/DOI redirects.
"""
from __future__ import annotations

import asyncio
import re
import unicodedata
from datetime import datetime
from typing import Literal
from urllib.parse import quote
from uuid import UUID

import httpx
from pydantic import BaseModel, Field, field_validator


class BibliographicMetadata(BaseModel):
    title: str | None = Field(default=None, max_length=1000)
    authors: list[str] = Field(default_factory=list, max_length=100)
    publication_year: int | None = Field(default=None, ge=1500, le=2200)
    journal: str | None = Field(default=None, max_length=1000)
    doi: str | None = Field(default=None, max_length=255)
    publisher: str | None = Field(default=None, max_length=1000)
    volume: str | None = Field(default=None, max_length=100)
    issue: str | None = Field(default=None, max_length=100)
    pages: str | None = Field(default=None, max_length=100)
    publication_status: str | None = Field(default=None, max_length=255)


class VerificationRequest(BaseModel):
    doi: str | None = Field(default=None, max_length=255)


class MetadataCheck(BaseModel):
    field: str
    local_value: str | None
    source_value: str | None
    status: Literal["match", "mismatch", "missing_local", "missing_source", "unverifiable"]


class RegistryAttempt(BaseModel):
    provider: Literal["Crossref", "DataCite"]
    url: str
    status: Literal["found", "not_found", "unavailable"]


class VerificationReport(BaseModel):
    status: Literal["matched", "mismatch", "incomplete", "unverifiable"]
    requested_doi: str | None
    doi: str | None
    local_metadata: BibliographicMetadata
    source_metadata: BibliographicMetadata | None = None
    checks: list[MetadataCheck]
    sources: list[RegistryAttempt] = Field(default_factory=list)
    warnings: list[str]


class SourceReviewCreate(BaseModel):
    decision: Literal["accept", "reject"]
    note: str = Field(min_length=1, max_length=2000)

    @field_validator("note")
    @classmethod
    def meaningful_note(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Catatan review wajib diisi")
        return value.strip()


class SourceReviewRead(SourceReviewCreate):
    id: UUID
    reviewer_id: UUID
    created_at: datetime


class SourceVerificationRead(BaseModel):
    id: UUID
    paper_id: UUID
    report: VerificationReport
    created_at: datetime
    reviews: list[SourceReviewRead] = Field(default_factory=list)


def normalize_doi(value: str | None) -> str | None:
    candidate = re.sub(r"^(?:https?://(?:dx\.)?doi\.org/|doi:\s*)", "", (value or "").strip(), flags=re.I)
    # Encode the suffix as one path segment; never interpret user input as a URL.
    if not re.fullmatch(r"10\.\d{4,9}/[^\s\x00-\x1f?#]+", candidate, flags=re.I):
        return None
    if any(part in {".", ".."} for part in candidate.split("/")):
        return None
    return candidate.lower()


def _text(value: object) -> str | None:
    if value is None or value == []:
        return None
    if isinstance(value, list):
        value = "; ".join(str(item) for item in value)
    return " ".join(str(value).split()) or None


def _normalized(value: str) -> str:
    return " ".join(re.findall(r"\w+", unicodedata.normalize("NFKC", value).casefold()))


def _crossref(record: dict) -> BibliographicMetadata:
    date = record.get("published") or record.get("issued") or {}
    parts = date.get("date-parts") or [[]]
    # A registered journal article is not proof that no later retraction exists.
    publication_status = "preprint" if record.get("subtype") == "preprint" else None
    return BibliographicMetadata(
        title=_text((record.get("title") or [None])[0]),
        authors=[_text(author.get("name") or " ".join(filter(None, [author.get("given"), author.get("family")])))
                 for author in record.get("author", []) if author.get("name") or author.get("family")],
        publication_year=parts[0][0] if parts and parts[0] else None,
        journal=_text((record.get("container-title") or [None])[0]),
        doi=normalize_doi(record.get("DOI")), publisher=_text(record.get("publisher")),
        volume=_text(record.get("volume")), issue=_text(record.get("issue")),
        pages=_text(record.get("page")), publication_status=publication_status,
    )


def _datacite(record: dict) -> BibliographicMetadata:
    publisher = record.get("publisher")
    container = record.get("container") or {}
    return BibliographicMetadata(
        title=_text((record.get("titles") or [{}])[0].get("title")),
        authors=[_text(" ".join(filter(None, [author.get("givenName"), author.get("familyName")])) or author.get("name"))
                 for author in record.get("creators", []) if author.get("name") or author.get("familyName")],
        publication_year=record.get("publicationYear"),
        journal=_text(container.get("title")), doi=normalize_doi(record.get("doi")),
        publisher=_text(publisher.get("name") if isinstance(publisher, dict) else publisher),
        volume=_text(container.get("volume")), issue=_text(container.get("issue")),
        pages=_text("-".join(str(container[k]) for k in ("firstPage", "lastPage") if container.get(k))),
        # DataCite's findable state is registry visibility, not publication status.
    )


async def verify_source(local: BibliographicMetadata, requested_doi: str | None = None) -> VerificationReport:
    requested = requested_doi if requested_doi is not None else local.doi
    doi = normalize_doi(requested)
    sources: list[RegistryAttempt] = []
    remote = None
    warnings = [
        "Pencocokan metadata registri bukan bukti keaslian isi PDF atau kualitas jurnal. Review manusia tetap wajib.",
        "Status publikasi/retraksi tidak dapat dipastikan hanya dari keberadaan DOI; periksa laman penerbit.",
    ]
    if doi:
        async with httpx.AsyncClient(
            timeout=6.0,
            follow_redirects=False,
            headers={
                "User-Agent": "Modellyng/0.1 (bibliographic verification)",
                "Accept": "application/json",
            },
        ) as client:
            for provider, base, parser in (
                ("Crossref", "https://api.crossref.org/works/", _crossref),
                ("DataCite", "https://api.datacite.org/dois/", _datacite),
            ):
                url = base + quote(doi, safe="")
                status = "unavailable"
                try:
                    response = await asyncio.wait_for(client.get(url), timeout=8)
                    if response.status_code == 404:
                        status = "not_found"
                    elif response.is_success:
                        payload = response.json()
                        record = payload["message"] if provider == "Crossref" else payload["data"]["attributes"]
                        candidate = parser(record)
                        if candidate.doi == doi:
                            remote, status = candidate, "found"
                except (httpx.HTTPError, TimeoutError, ValueError, KeyError, TypeError, AttributeError, IndexError):
                    pass
                sources.append(RegistryAttempt(provider=provider, url=url, status=status))
                if remote:
                    break
    else:
        warnings.append("DOI belum tersedia atau formatnya tidak valid. Sumber belum dapat diverifikasi.")
    checks = []
    for field in BibliographicMetadata.model_fields:
        local_value = _text(getattr(local, field))
        remote_value = _text(getattr(remote, field)) if remote else None
        if remote is None:
            status = "unverifiable"
        elif not remote_value:
            status = "missing_source"
        elif not local_value:
            status = "missing_local"
        else:
            status = "mismatch"
        if local_value and remote_value:
            # Conservative comparison: punctuation/case only; no fuzzy acceptance.
            left = normalize_doi(local_value) if field == "doi" else _normalized(local_value)
            right = normalize_doi(remote_value) if field == "doi" else _normalized(remote_value)
            status = "match" if left == right else "mismatch"
        checks.append(MetadataCheck(field=field, local_value=local_value, source_value=remote_value, status=status))
    if remote is None:
        overall = "unverifiable"
    elif any(check.status == "mismatch" for check in checks):
        overall = "mismatch"
    elif any(check.status != "match" for check in checks):
        overall = "incomplete"
    else:
        overall = "matched"
    if remote is None and doi:
        warnings.append("Tidak ditemukan pada registri yang diperiksa atau layanan tidak tersedia; ini tidak membuktikan paper palsu.")
    return VerificationReport(
        status=overall, requested_doi=requested, doi=doi,
        local_metadata=local, source_metadata=remote,
        checks=checks, sources=sources, warnings=warnings,
    )
