import asyncio
from urllib.parse import quote
from uuid import UUID, uuid4

import httpx

from .auth import AuthenticatedUser
from .config import get_settings
from .schemas import (
    PaperCreate,
    PaperProcessingRead,
    PaperRead,
    PaperSource,
    ProjectCreate,
    ProjectRead,
    ReviewQueueItemRead,
    PaperResultRead,
    ExtractedComponentRead,
    ExtractionParameter,
    ComparativeMatrixRead,
    ConceptEvidenceMapRead,
    ResearchGapMapRead,
    ResearchGapDecisionCreate,
    ResearchGapDecisionRead,
    ReviewHistoryItemRead,
    ReviewRecordCreate,
    ReviewRecordRead,
    ReviewerAction,
    ProjectChatMessageRead,
    ProjectChatRequest,
    ProjectChatResponse,
    BulkReviewAcceptRequest,
    BulkReviewAcceptResponse,
)
from .structured_results import build_structured_tables
from .chat_service import ProjectChatBlock, ProjectChatContext, ProjectChatDocument


class EntityNotFoundError(LookupError):
    pass


class RepositoryError(RuntimeError):
    pass


class InvalidUploadError(ValueError):
    pass


class InvalidReviewError(ValueError):
    pass


class SupabaseProjectRepository:
    def __init__(self) -> None:
        settings = get_settings()
        self._rest_url = f"{settings.supabase_url}/rest/v1"
        self._storage_url = f"{settings.supabase_url}/storage/v1"
        self._anon_key = settings.supabase_anon_key
        self._worker_service_key = settings.supabase_service_role_key
        self._storage_bucket = settings.object_storage_bucket

    def _headers(
        self,
        user: AuthenticatedUser,
        *,
        return_representation: bool = False,
    ) -> dict[str, str]:
        headers = {
            "apikey": self._anon_key,
            "Authorization": f"Bearer {user.access_token}",
        }
        if return_representation:
            headers["Prefer"] = "return=representation"
        return headers

    @staticmethod
    def _to_project(row: dict[str, object]) -> ProjectRead:
        payload = {**row}
        paper_relation = payload.pop("papers", [])
        paper_count = 0
        review_count = 0
        knowledge_node_count = 0
        if isinstance(paper_relation, list):
            paper_count = len(paper_relation)
            review_count = sum(
                1 for paper in paper_relation if paper.get("status") == "needs_review"
            )
            knowledge_node_count = sum(
                1
                for paper in paper_relation
                for component in paper.get("extracted_components", [])
                if component.get("is_active", True)
                if component.get("status") in {"verified", "edited"}
            )
        return ProjectRead.model_validate(
            {
                **payload,
                "paper_count": paper_count,
                "review_count": review_count,
                "knowledge_node_count": knowledge_node_count,
            }
        )

    @staticmethod
    def _to_paper(row: dict[str, object]) -> PaperRead:
        payload = {**row}
        raw_jobs = payload.pop("analysis_jobs", [])
        analysis_job = None
        if isinstance(raw_jobs, list) and raw_jobs:
            newest_job = max(
                raw_jobs,
                key=lambda job: str(job.get("created_at", "")),
            )
            analysis_job = PaperProcessingRead.model_validate(newest_job)
        source = PaperSource.UPLOAD if row.get("storage_key") else PaperSource.DOI
        return PaperRead.model_validate(
            {**payload, "source": source, "analysis_job": analysis_job}
        )

    @staticmethod
    def _paper_select() -> str:
        return (
            "id,project_id,storage_key,original_filename,mime_type,"
            "file_size_bytes,page_count,language_code,doi,status,title,authors,"
            "publication_year,journal,created_at,updated_at,"
            "analysis_jobs(id,status,stage,progress,error_message,created_at,updated_at)"
        )

    @staticmethod
    def _project_select() -> str:
        return (
            "id,title,description,status,created_at,updated_at,"
            "papers(id,status,extracted_components(id,status,is_active))"
        )

    async def create_project(
        self,
        user: AuthenticatedUser,
        payload: ProjectCreate,
    ) -> ProjectRead:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(
                f"{self._rest_url}/projects",
                headers=self._headers(user, return_representation=True),
                json={"owner_id": str(user.id), **payload.model_dump()},
            )
        self._raise_for_repository_error(response)
        return self._to_project(response.json()[0])

    async def list_projects(
        self,
        user: AuthenticatedUser,
    ) -> list[ProjectRead]:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(
                f"{self._rest_url}/projects",
                headers=self._headers(user),
                params={
                    "select": self._project_select(),
                    "order": "updated_at.desc",
                },
            )
        self._raise_for_repository_error(response)
        return [self._to_project(row) for row in response.json()]

    async def get_project(
        self,
        user: AuthenticatedUser,
        project_id: UUID,
    ) -> ProjectRead:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(
                f"{self._rest_url}/projects",
                headers=self._headers(user),
                params={
                    "select": self._project_select(),
                    "id": f"eq.{project_id}",
                    "limit": "1",
                },
            )
        self._raise_for_repository_error(response)
        rows = response.json()
        if not rows:
            raise EntityNotFoundError(f"Project {project_id} was not found")
        return self._to_project(rows[0])

    async def create_paper(
        self,
        user: AuthenticatedUser,
        project_id: UUID,
        payload: PaperCreate,
    ) -> PaperRead:
        await self.get_project(user, project_id)

        if payload.source == PaperSource.UPLOAD:
            self._validate_storage_key(user, project_id, payload)
            await self._verify_uploaded_pdf(user, payload)

        database_payload = payload.model_dump(exclude={"source"})
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.post(
                f"{self._rest_url}/papers",
                headers=self._headers(user, return_representation=True),
                json={"project_id": str(project_id), **database_payload},
            )
        self._raise_for_repository_error(response)
        return self._to_paper(response.json()[0])

    async def upload_pdf(
        self,
        user: AuthenticatedUser,
        project_id: UUID,
        *,
        original_filename: str,
        content: bytes,
    ) -> PaperRead:
        """Store a validated PDF and create its private paper record."""
        await self.get_project(user, project_id)
        self._validate_pdf_content(original_filename, content)

        storage_key = f"{user.id}/{project_id}/{uuid4()}.pdf"
        encoded_path = quote(storage_key, safe="/")
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(
                f"{self._storage_url}/object/"
                f"{self._storage_bucket}/{encoded_path}",
                headers={
                    **self._headers(user),
                    "Content-Type": "application/pdf",
                    "x-upsert": "false",
                },
                content=content,
            )
        self._raise_for_repository_error(response)

        payload = PaperCreate(
            source=PaperSource.UPLOAD,
            original_filename=original_filename,
            storage_key=storage_key,
            mime_type="application/pdf",
            file_size_bytes=len(content),
        )
        try:
            paper = await self.create_paper(user, project_id, payload)
            await self.start_pdf_processing(user, project_id, paper.id)
            return await self.get_paper(user, project_id, paper.id)
        except Exception:
            if "paper" not in locals():
                await self._remove_storage_object(user, storage_key)
            raise

    async def get_paper(
        self,
        user: AuthenticatedUser,
        project_id: UUID,
        paper_id: UUID,
    ) -> PaperRead:
        await self.get_project(user, project_id)
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(
                f"{self._rest_url}/papers",
                headers=self._headers(user),
                params={
                    "select": self._paper_select(),
                    "project_id": f"eq.{project_id}",
                    "id": f"eq.{paper_id}",
                    "limit": "1",
                },
            )
        self._raise_for_repository_error(response)
        rows = response.json()
        if not rows:
            raise EntityNotFoundError(f"Paper {paper_id} was not found")
        return self._to_paper(rows[0])

    async def start_pdf_processing(
        self,
        user: AuthenticatedUser,
        project_id: UUID,
        paper_id: UUID,
    ) -> PaperRead:
        if not self._worker_service_key.strip():
            raise RepositoryError(
                "Worker belum dikonfigurasi: MODELLYNG_SUPABASE_SERVICE_ROLE_KEY kosong"
            )
        paper = await self.get_paper(user, project_id, paper_id)
        if not paper.storage_key:
            raise InvalidUploadError("Paper DOI belum memiliki PDF untuk diproses")
        if paper.analysis_job and paper.analysis_job.status.value in {
            "queued",
            "processing",
        }:
            return paper

        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.post(
                f"{self._rest_url}/analysis_jobs",
                headers=self._headers(user, return_representation=True),
                json={
                    "project_id": str(project_id),
                    "paper_id": str(paper_id),
                    "status": "queued",
                    "stage": "queued",
                    "progress": 0,
                    "parameters": {"pipeline": "gemini_academic_extraction_v1"},
                },
            )
        self._raise_for_repository_error(response)
        job_id = response.json()[0]["id"]

        async with httpx.AsyncClient(timeout=15.0) as client:
            paper_response = await client.patch(
                f"{self._rest_url}/papers",
                headers=self._headers(user),
                params={"id": f"eq.{paper_id}"},
                json={"status": "processing"},
            )
            project_response = await client.patch(
                f"{self._rest_url}/projects",
                headers=self._headers(user),
                params={"id": f"eq.{project_id}"},
                json={"status": "processing"},
            )
        self._raise_for_repository_error(paper_response)
        self._raise_for_repository_error(project_response)

        try:
            from .celery_app import celery_app

            celery_app.send_task(
                "modellyng.process_pdf",
                args=[job_id, str(paper_id)],
                task_id=job_id,
            )
        except Exception as exc:
            await self._mark_enqueue_failure(
                user, project_id, paper_id, UUID(job_id), str(exc)
            )
            return await self.get_paper(user, project_id, paper_id)

        return await self.get_paper(user, project_id, paper_id)

    async def _mark_enqueue_failure(
        self,
        user: AuthenticatedUser,
        project_id: UUID,
        paper_id: UUID,
        job_id: UUID,
        detail: str,
    ) -> None:
        async with httpx.AsyncClient(timeout=10.0) as client:
            await client.patch(
                f"{self._rest_url}/analysis_jobs",
                headers=self._headers(user),
                params={"id": f"eq.{job_id}"},
                json={
                    "status": "failed",
                    "stage": "queue_failed",
                    "progress": 1,
                    "error_message": f"Redis/Celery tidak tersedia: {detail}"[:1000],
                },
            )
            await client.patch(
                f"{self._rest_url}/papers",
                headers=self._headers(user),
                params={"id": f"eq.{paper_id}"},
                json={"status": "failed"},
            )
            await client.patch(
                f"{self._rest_url}/projects",
                headers=self._headers(user),
                params={"id": f"eq.{project_id}"},
                json={"status": "needs_review"},
            )

    async def list_papers(
        self,
        user: AuthenticatedUser,
        project_id: UUID,
    ) -> list[PaperRead]:
        await self.get_project(user, project_id)
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(
                f"{self._rest_url}/papers",
                headers=self._headers(user),
                params={
                    "select": self._paper_select(),
                    "project_id": f"eq.{project_id}",
                    "order": "created_at.desc",
                },
            )
        self._raise_for_repository_error(response)
        return [self._to_paper(row) for row in response.json()]

    async def list_review_queue(
        self,
        user: AuthenticatedUser,
    ) -> list[ReviewQueueItemRead]:
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.get(
                f"{self._rest_url}/extracted_components",
                headers=self._headers(user),
                params={
                    "select": (
                        "id,paper_id,parameter,ai_value,final_value,status,confidence,"
                        "model_name,prompt_version,created_at,is_active,"
                        "papers(id,project_id,title,original_filename,"
                        "projects(id,title)),"
                        "evidence_spans(quote,page_number,section,subsection,"
                        "paper_blocks(id,bounding_box))"
                    ),
                    "status": "eq.needs_review",
                    "is_active": "eq.true",
                    "order": "created_at.desc",
                },
            )
        self._raise_for_repository_error(response)
        items: list[ReviewQueueItemRead] = []
        for row in response.json():
            paper = row.get("papers") or {}
            project = paper.get("projects") or {}
            evidence = []
            for span in row.get("evidence_spans") or []:
                block = span.get("paper_blocks") or {}
                evidence.append(
                    {
                        "quote": span["quote"],
                        "page_number": span["page_number"],
                        "section": span.get("section"),
                        "subsection": span.get("subsection"),
                        "block_id": str(block.get("id") or ""),
                        "bounding_box": block.get("bounding_box"),
                    }
                )
            items.append(
                ReviewQueueItemRead.model_validate(
                    {
                        "component_id": row["id"],
                        "paper_id": row["paper_id"],
                        "project_id": paper["project_id"],
                        "project_title": project.get("title") or "Proyek",
                        "paper_title": paper.get("title")
                        or paper.get("original_filename")
                        or "Paper",
                        "original_filename": paper.get("original_filename")
                        or "paper.pdf",
                        "parameter": row["parameter"],
                        "ai_value": row["ai_value"],
                        "final_value": row.get("final_value"),
                        "status": row["status"],
                        "confidence": row.get("confidence"),
                        "evidence": evidence,
                        "model_name": row["model_name"],
                        "prompt_version": row["prompt_version"],
                        "created_at": row["created_at"],
                    }
                )
            )
        return items

    async def get_paper_result(
        self, user: AuthenticatedUser, project_id: UUID, paper_id: UUID
    ) -> PaperResultRead:
        paper = await self.get_paper(user, project_id, paper_id)
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.get(
                f"{self._rest_url}/extracted_components",
                headers=self._headers(user),
                params={
                    "select": (
                        "id,paper_id,parameter,ai_value,final_value,status,confidence,"
                        "model_name,prompt_version,created_at,is_active,"
                        "evidence_spans(quote,page_number,section,subsection,"
                        "paper_blocks(id,bounding_box))"
                    ),
                    "paper_id": f"eq.{paper_id}",
                    "is_active": "eq.true",
                    "order": "created_at.desc",
                },
            )
        self._raise_for_repository_error(response)
        components: list[ExtractedComponentRead] = []
        seen: set[str] = set()
        for row in response.json():
            parameter = str(row["parameter"])
            if parameter in seen:
                continue
            seen.add(parameter)
            evidence = []
            for span in row.get("evidence_spans") or []:
                block = span.get("paper_blocks") or {}
                evidence.append({
                    "quote": span["quote"],
                    "page_number": span["page_number"],
                    "section": span.get("section"),
                    "subsection": span.get("subsection"),
                    "block_id": str(block.get("id") or ""),
                    "bounding_box": block.get("bounding_box"),
                })
            components.append(ExtractedComponentRead.model_validate({**row, "evidence": evidence}))
        return PaperResultRead(
            paper=paper,
            components=components,
            structured_tables=build_structured_tables(components),
        )

    async def get_comparative_matrix(
        self, user: AuthenticatedUser, project_id: UUID
    ) -> ComparativeMatrixRead:
        project = await self.get_project(user, project_id)
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.get(
                f"{self._rest_url}/papers",
                headers=self._headers(user),
                params={
                    "select": (
                        "id,title,original_filename,created_at,"
                        "extracted_components(id,parameter,ai_value,final_value,status,"
                        "confidence,created_at,is_active,evidence_spans(quote,page_number,section,"
                        "subsection,paper_blocks(id,bounding_box)))"
                    ),
                    "project_id": f"eq.{project_id}",
                    "status": "eq.ready",
                    "order": "created_at.asc",
                },
            )
        self._raise_for_repository_error(response)
        paper_rows = response.json()
        papers = [
            {
                "id": row["id"],
                "title": row.get("title") or row.get("original_filename") or "Paper",
                "original_filename": row.get("original_filename") or "paper.pdf",
            }
            for row in paper_rows
        ]
        parameters = [parameter.value for parameter in ExtractionParameter]
        row_cells: dict[str, list[dict[str, object]]] = {
            parameter: [] for parameter in parameters
        }
        for paper in paper_rows:
            latest: dict[str, dict[str, object]] = {}
            components = sorted(
                paper.get("extracted_components") or [],
                key=lambda item: str(item.get("created_at") or ""),
                reverse=True,
            )
            for component in components:
                parameter = str(component.get("parameter") or "")
                if not component.get("is_active", True):
                    continue
                if component.get("status") not in {"verified", "edited"}:
                    continue
                if parameter in latest or parameter not in row_cells:
                    continue
                latest[parameter] = component
            for parameter, component in latest.items():
                evidence = []
                for span in component.get("evidence_spans") or []:
                    block = span.get("paper_blocks") or {}
                    evidence.append({
                        "quote": span["quote"],
                        "page_number": span["page_number"],
                        "section": span.get("section"),
                        "subsection": span.get("subsection"),
                        "block_id": str(block.get("id") or ""),
                        "bounding_box": block.get("bounding_box"),
                    })
                row_cells[parameter].append({
                    "paper_id": paper["id"],
                    "ai_value": component["ai_value"],
                    "final_value": component.get("final_value"),
                    "status": component["status"],
                    "confidence": component.get("confidence"),
                    "evidence": evidence,
                })
        return ComparativeMatrixRead.model_validate({
            "project_id": project.id,
            "project_title": project.title,
            "papers": papers,
            "rows": [
                {"parameter": parameter, "cells": row_cells[parameter]}
                for parameter in parameters
            ],
        })

    async def get_concept_evidence_map(
        self, user: AuthenticatedUser, project_id: UUID
    ) -> ConceptEvidenceMapRead:
        matrix = await self.get_comparative_matrix(user, project_id)
        nodes: list[dict[str, object]] = []
        edges: list[dict[str, str]] = []
        for paper in matrix.papers:
            nodes.append({
                "id": f"paper:{paper.id}",
                "kind": "paper",
                "label": paper.title,
                "detail": paper.original_filename,
                "paper_id": paper.id,
            })
        for row in matrix.rows:
            for cell in row.cells:
                paper_id = str(cell.paper_id)
                concept_id = f"concept:{paper_id}:{row.parameter.value}"
                nodes.append({
                    "id": concept_id,
                    "kind": "concept",
                    "label": row.parameter.value,
                    "detail": cell.final_value or cell.ai_value,
                    "paper_id": cell.paper_id,
                    "parameter": row.parameter.value,
                    "status": cell.status.value,
                })
                edges.append({
                    "source": f"paper:{paper_id}",
                    "target": concept_id,
                    "relation": "contains",
                })
                for index, evidence in enumerate(cell.evidence):
                    evidence_id = f"evidence:{paper_id}:{row.parameter.value}:{index}"
                    nodes.append({
                        "id": evidence_id,
                        "kind": "evidence",
                        "label": f"Halaman {evidence.page_number}",
                        "detail": evidence.quote,
                        "paper_id": cell.paper_id,
                        "parameter": row.parameter.value,
                        "page_number": evidence.page_number,
                    })
                    edges.append({
                        "source": concept_id,
                        "target": evidence_id,
                        "relation": "supported_by",
                    })
        return ConceptEvidenceMapRead.model_validate({
            "project_id": matrix.project_id,
            "project_title": matrix.project_title,
            "nodes": nodes,
            "edges": edges,
        })

    async def get_research_gap_map(
        self, user: AuthenticatedUser, project_id: UUID
    ) -> ResearchGapMapRead:
        """Build reviewable gap candidates without inventing new claims.

        A limitation or future-work value is exposed verbatim as a candidate,
        with its verified source evidence. It is deliberately not promoted to
        a final research gap automatically.
        """
        matrix = await self.get_comparative_matrix(user, project_id)
        paper_by_id = {str(paper.id): paper for paper in matrix.papers}
        nodes: list[dict[str, object]] = []
        edges: list[dict[str, str]] = []
        candidate_count = 0
        gap_parameters = {
            ExtractionParameter.LIMITATIONS,
            ExtractionParameter.FUTURE_WORK,
        }
        for row in matrix.rows:
            if row.parameter not in gap_parameters:
                continue
            for cell in row.cells:
                paper_id = str(cell.paper_id)
                paper = paper_by_id.get(paper_id)
                if paper is None:
                    continue
                paper_node_id = f"paper:{paper_id}"
                if not any(node["id"] == paper_node_id for node in nodes):
                    nodes.append({
                        "id": paper_node_id,
                        "kind": "paper",
                        "label": paper.title,
                        "detail": paper.original_filename,
                        "paper_id": cell.paper_id,
                    })
                gap_id = f"gap:{paper_id}:{row.parameter.value}"
                candidate_count += 1
                nodes.append({
                    "id": gap_id,
                    "kind": "gap",
                    "label": row.parameter.value,
                    "detail": cell.final_value or cell.ai_value,
                    "paper_id": cell.paper_id,
                    "parameter": row.parameter.value,
                    "status": cell.status.value,
                })
                edges.append({
                    "source": paper_node_id,
                    "target": gap_id,
                    "relation": "suggests_candidate",
                })
                for index, evidence in enumerate(cell.evidence):
                    evidence_id = f"gap-evidence:{paper_id}:{row.parameter.value}:{index}"
                    nodes.append({
                        "id": evidence_id,
                        "kind": "evidence",
                        "label": f"Halaman {evidence.page_number}",
                        "detail": evidence.quote,
                        "paper_id": cell.paper_id,
                        "parameter": row.parameter.value,
                        "page_number": evidence.page_number,
                    })
                    edges.append({
                        "source": gap_id,
                        "target": evidence_id,
                        "relation": "supported_by",
                    })
        return ResearchGapMapRead.model_validate({
            "project_id": matrix.project_id,
            "project_title": matrix.project_title,
            "nodes": nodes,
            "edges": edges,
            "candidate_count": candidate_count,
        })

    async def get_project_chat_context(
        self, user: AuthenticatedUser, project_id: UUID
    ) -> ProjectChatContext:
        """Load searchable PDF text through the caller's RLS-scoped token."""
        project = await self.get_project(user, project_id)
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.get(
                f"{self._rest_url}/papers",
                headers=self._headers(user),
                params={
                    "select": (
                        "id,title,original_filename,status,"
                        "paper_blocks(id,block_index,page_number,section,subsection,content)"
                    ),
                    "project_id": f"eq.{project_id}",
                    "order": "created_at.asc",
                    "paper_blocks.order": "block_index.asc",
                },
            )
        self._raise_for_repository_error(response)
        documents: list[ProjectChatDocument] = []
        for row in response.json():
            blocks = tuple(
                ProjectChatBlock(
                    id=str(block["id"]),
                    page_number=int(block["page_number"]),
                    content=str(block["content"]),
                    section=str(block["section"]) if block.get("section") else None,
                    subsection=(
                        str(block["subsection"])
                        if block.get("subsection")
                        else None
                    ),
                )
                for block in row.get("paper_blocks") or []
                if str(block.get("content") or "").strip()
            )
            documents.append(
                ProjectChatDocument(
                    id=UUID(str(row["id"])),
                    title=str(
                        row.get("title")
                        or row.get("original_filename")
                        or "Paper"
                    ),
                    original_filename=str(row.get("original_filename") or "paper.pdf"),
                    status=str(row.get("status") or "uploaded"),
                    blocks=blocks,
                )
            )
        return ProjectChatContext(
            project_id=project.id,
            project_title=project.title,
            documents=tuple(documents),
        )

    async def list_project_chat_messages(
        self, user: AuthenticatedUser, project_id: UUID
    ) -> list[ProjectChatMessageRead]:
        await self.get_project(user, project_id)
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.get(
                f"{self._rest_url}/project_chat_messages",
                headers=self._headers(user),
                params={
                    "select": (
                        "id,turn_id,role,content,sources,model_name,"
                        "review_notice,created_at,position"
                    ),
                    "project_id": f"eq.{project_id}",
                    "owner_id": f"eq.{user.id}",
                    "order": "created_at.desc,position.desc",
                    "limit": "200",
                },
            )
        self._raise_for_repository_error(response)
        rows = response.json()
        return [ProjectChatMessageRead.model_validate(row) for row in reversed(rows)]

    async def save_project_chat_exchange(
        self,
        user: AuthenticatedUser,
        project_id: UUID,
        request: ProjectChatRequest,
        answer: ProjectChatResponse,
    ) -> None:
        await self.get_project(user, project_id)
        turn_id = uuid4()
        rows = [
            {
                "owner_id": str(user.id),
                "project_id": str(project_id),
                "turn_id": str(turn_id),
                "position": 0,
                "role": "user",
                "content": request.question,
                "sources": [],
                "model_name": None,
                "review_notice": None,
            },
            {
                "owner_id": str(user.id),
                "project_id": str(project_id),
                "turn_id": str(turn_id),
                "position": 1,
                "role": "assistant",
                "content": answer.answer,
                "sources": [
                    source.model_dump(mode="json") for source in answer.sources
                ],
                "model_name": answer.model_name,
                "review_notice": answer.review_notice,
            },
        ]
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.post(
                f"{self._rest_url}/project_chat_messages",
                headers=self._headers(user),
                json=rows,
            )
        self._raise_for_repository_error(response)

    async def list_research_gap_decisions(
        self, user: AuthenticatedUser, project_id: UUID
    ) -> list[ResearchGapDecisionRead]:
        await self.get_project(user, project_id)
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.get(
                f"{self._rest_url}/research_gap_decisions",
                headers=self._headers(user),
                params={
                    "select": (
                        "id,project_id,paper_id,parameter,decision,note,reviewer_id,"
                        "created_at,updated_at"
                    ),
                    "project_id": f"eq.{project_id}",
                    "reviewer_id": f"eq.{user.id}",
                    "order": "updated_at.desc",
                },
            )
        self._raise_for_repository_error(response)
        return [ResearchGapDecisionRead.model_validate(row) for row in response.json()]

    async def save_research_gap_decision(
        self,
        user: AuthenticatedUser,
        project_id: UUID,
        paper_id: UUID,
        parameter: ExtractionParameter,
        payload: ResearchGapDecisionCreate,
    ) -> ResearchGapDecisionRead:
        if parameter not in {
            ExtractionParameter.LIMITATIONS,
            ExtractionParameter.FUTURE_WORK,
        }:
            raise InvalidReviewError(
                "Keputusan gap hanya berlaku untuk keterbatasan atau future work"
            )
        await self.get_paper(user, project_id, paper_id)
        matrix = await self.get_comparative_matrix(user, project_id)
        has_candidate = any(
            row.parameter == parameter
            and any(cell.paper_id == paper_id for cell in row.cells)
            for row in matrix.rows
        )
        if not has_candidate:
            raise InvalidReviewError(
                "Kandidat gap aktif dan terverifikasi tidak ditemukan"
            )
        row = {
            "project_id": str(project_id),
            "paper_id": str(paper_id),
            "parameter": parameter.value,
            "decision": payload.decision.value,
            "note": payload.note,
            "reviewer_id": str(user.id),
        }
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.post(
                f"{self._rest_url}/research_gap_decisions",
                headers={
                    **self._headers(user, return_representation=True),
                    "Prefer": "resolution=merge-duplicates,return=representation",
                },
                params={
                    "on_conflict": "project_id,paper_id,parameter,reviewer_id"
                },
                json=row,
            )
        self._raise_for_repository_error(response)
        return ResearchGapDecisionRead.model_validate(response.json()[0])

    async def download_private_pdf(
        self, user: AuthenticatedUser, project_id: UUID, paper_id: UUID
    ) -> tuple[bytes, str]:
        paper = await self.get_paper(user, project_id, paper_id)
        if not paper.storage_key:
            raise EntityNotFoundError("Paper ini tidak memiliki PDF")
        encoded_path = quote(paper.storage_key, safe="/")
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.get(
                f"{self._storage_url}/object/authenticated/{self._storage_bucket}/{encoded_path}",
                headers=self._headers(user),
            )
        self._raise_for_repository_error(response)
        return response.content, paper.original_filename or "paper.pdf"

    async def get_evidence_preview_data(
        self,
        user: AuthenticatedUser,
        project_id: UUID,
        paper_id: UUID,
        block_id: UUID,
    ) -> tuple[bytes, int, str]:
        # Authorize once, then fetch the private object and its RLS-scoped block
        # concurrently to keep the evidence click path near one network round trip.
        paper = await self.get_paper(user, project_id, paper_id)
        if not paper.storage_key:
            raise EntityNotFoundError("Paper ini tidak memiliki PDF")
        encoded_path = quote(paper.storage_key, safe="/")
        async with httpx.AsyncClient(timeout=15.0) as client:
            block_response, pdf_response = await asyncio.gather(
                client.get(
                    f"{self._rest_url}/paper_blocks",
                    headers=self._headers(user),
                    params={
                        "select": "id,paper_id,page_number,content",
                        "id": f"eq.{block_id}",
                        "paper_id": f"eq.{paper_id}",
                        "limit": "1",
                    },
                ),
                client.get(
                    f"{self._storage_url}/object/authenticated/"
                    f"{self._storage_bucket}/{encoded_path}",
                    headers=self._headers(user),
                ),
            )
        self._raise_for_repository_error(block_response)
        self._raise_for_repository_error(pdf_response)
        rows = block_response.json()
        if not rows:
            raise EntityNotFoundError("Evidence tidak ditemukan")
        return (
            pdf_response.content,
            int(rows[0]["page_number"]),
            str(rows[0]["content"]),
        )

    async def list_review_history(
        self, user: AuthenticatedUser
    ) -> list[ReviewHistoryItemRead]:
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.get(
                f"{self._rest_url}/review_actions",
                headers=self._headers(user),
                params={
                    "select": (
                        "id,component_id,reviewer_id,action,corrected_value,note,created_at,"
                        "extracted_components(parameter,paper_id,papers(title,original_filename))"
                    ),
                    "order": "created_at.desc",
                    "limit": "100",
                },
            )
        self._raise_for_repository_error(response)
        result = []
        for row in response.json():
            component = row.pop("extracted_components") or {}
            paper = component.get("papers") or {}
            result.append(ReviewHistoryItemRead.model_validate({
                **row,
                "parameter": component["parameter"],
                "paper_id": component["paper_id"],
                "paper_title": paper.get("title") or paper.get("original_filename") or "Paper",
            }))
        return result

    async def review_component(
        self,
        user: AuthenticatedUser,
        component_id: UUID,
        payload: ReviewRecordCreate,
    ) -> ReviewRecordRead:
        async with httpx.AsyncClient(timeout=15.0) as client:
            component_response = await client.get(
                f"{self._rest_url}/extracted_components",
                headers=self._headers(user),
                params={
                    "select": "id,paper_id,ai_value,status,is_active,papers(project_id)",
                    "id": f"eq.{component_id}",
                    "limit": "1",
                },
            )
        self._raise_for_repository_error(component_response)
        rows = component_response.json()
        if not rows:
            raise EntityNotFoundError(f"Component {component_id} was not found")
        component = rows[0]
        if component["status"] != "needs_review":
            raise InvalidReviewError("Komponen ini sudah selesai ditinjau")
        if not component.get("is_active", True):
            raise InvalidReviewError("Komponen ini berasal dari versi analisis lama")

        component_status = {
            ReviewerAction.ACCEPT: "verified",
            ReviewerAction.EDIT: "edited",
            ReviewerAction.REJECT: "rejected",
            ReviewerAction.REQUEST_REANALYSIS: "unsupported",
        }[payload.action]
        final_value = (
            payload.corrected_value
            if payload.action == ReviewerAction.EDIT
            else component["ai_value"]
            if payload.action == ReviewerAction.ACCEPT
            else None
        )

        async with httpx.AsyncClient(timeout=20.0) as client:
            action_response = await client.post(
                f"{self._rest_url}/review_actions",
                headers=self._headers(user, return_representation=True),
                json={
                    "component_id": str(component_id),
                    "reviewer_id": str(user.id),
                    "action": payload.action.value,
                    "original_ai_value": component["ai_value"],
                    "corrected_value": payload.corrected_value,
                    "note": payload.note,
                },
            )
            self._raise_for_repository_error(action_response)
            update_response = await client.patch(
                f"{self._rest_url}/extracted_components",
                headers=self._headers(user),
                params={"id": f"eq.{component_id}"},
                json={"status": component_status, "final_value": final_value},
            )
        self._raise_for_repository_error(update_response)
        await self._refresh_review_status(
            user,
            paper_id=UUID(component["paper_id"]),
            project_id=UUID(component["papers"]["project_id"]),
        )
        if payload.action == ReviewerAction.REQUEST_REANALYSIS:
            await self.start_pdf_processing(
                user,
                UUID(component["papers"]["project_id"]),
                UUID(component["paper_id"]),
            )
        action = action_response.json()[0]
        return ReviewRecordRead.model_validate(
            {
                "id": action["id"],
                "component_id": action["component_id"],
                "reviewer_id": action["reviewer_id"],
                "action": action["action"],
                "corrected_value": action.get("corrected_value"),
                "note": action.get("note"),
                "created_at": action["created_at"],
            }
        )

    async def accept_review_components(
        self,
        user: AuthenticatedUser,
        payload: BulkReviewAcceptRequest,
    ) -> BulkReviewAcceptResponse:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                f"{self._rest_url}/rpc/accept_review_components",
                headers=self._headers(user),
                json={
                    "p_component_ids": [
                        str(component_id) for component_id in payload.component_ids
                    ]
                },
            )
        self._raise_for_repository_error(response)
        rows = response.json()
        if not rows:
            raise RepositoryError("Aksi terima semua tidak mengembalikan hasil")
        return BulkReviewAcceptResponse.model_validate(rows[0])

    async def _refresh_review_status(
        self,
        user: AuthenticatedUser,
        *,
        paper_id: UUID,
        project_id: UUID,
    ) -> None:
        """Mark a paper/project ready only after its review queue is empty."""
        async with httpx.AsyncClient(timeout=15.0) as client:
            pending_components = await client.get(
                f"{self._rest_url}/extracted_components",
                headers=self._headers(user),
                params={
                    "select": "id",
                    "paper_id": f"eq.{paper_id}",
                    "status": "eq.needs_review",
                    "is_active": "eq.true",
                    "limit": "1",
                },
            )
            self._raise_for_repository_error(pending_components)
            if pending_components.json():
                return

            paper_update = await client.patch(
                f"{self._rest_url}/papers",
                headers=self._headers(user),
                params={"id": f"eq.{paper_id}"},
                json={"status": "ready"},
            )
            self._raise_for_repository_error(paper_update)

            pending_papers = await client.get(
                f"{self._rest_url}/papers",
                headers=self._headers(user),
                params={
                    "select": "id",
                    "project_id": f"eq.{project_id}",
                    "status": "neq.ready",
                    "limit": "1",
                },
            )
            self._raise_for_repository_error(pending_papers)
            if pending_papers.json():
                return

            project_update = await client.patch(
                f"{self._rest_url}/projects",
                headers=self._headers(user),
                params={"id": f"eq.{project_id}"},
                json={"status": "ready"},
            )
            self._raise_for_repository_error(project_update)

    @staticmethod
    def _validate_storage_key(
        user: AuthenticatedUser,
        project_id: UUID,
        payload: PaperCreate,
    ) -> None:
        storage_key = payload.storage_key or ""
        expected_prefix = f"{user.id}/{project_id}/"
        if not storage_key.startswith(expected_prefix):
            raise InvalidUploadError(
                "The uploaded file path does not belong to this user and project"
            )
        if ".." in storage_key.split("/") or not storage_key.lower().endswith(".pdf"):
            raise InvalidUploadError("The uploaded file path must point to a PDF")
        if not (payload.original_filename or "").lower().endswith(".pdf"):
            raise InvalidUploadError("The original file must use the .pdf extension")

    @staticmethod
    def _validate_pdf_content(original_filename: str, content: bytes) -> None:
        if len(original_filename) > 255:
            raise InvalidUploadError("Nama file PDF terlalu panjang (maksimal 255 karakter)")
        if not original_filename.lower().endswith(".pdf"):
            raise InvalidUploadError("Hanya file dengan ekstensi .pdf yang dapat diunggah")
        if not content:
            raise InvalidUploadError("File PDF kosong dan tidak dapat diproses")
        if len(content) > 52_428_800:
            raise InvalidUploadError("Ukuran PDF melebihi batas 50 MB per file")
        if not content.startswith(b"%PDF-"):
            raise InvalidUploadError(
                "Isi file tidak dikenali sebagai dokumen PDF yang valid"
            )

    async def _remove_storage_object(
        self,
        user: AuthenticatedUser,
        storage_key: str,
    ) -> None:
        """Best-effort rollback when database registration fails."""
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                await client.request(
                    "DELETE",
                    f"{self._storage_url}/object/{self._storage_bucket}",
                    headers={
                        **self._headers(user),
                        "Content-Type": "application/json",
                    },
                    json={"prefixes": [storage_key]},
                )
        except httpx.HTTPError:
            # Preserve the original registration error for the API client.
            pass

    async def _verify_uploaded_pdf(
        self,
        user: AuthenticatedUser,
        payload: PaperCreate,
    ) -> None:
        encoded_path = quote(payload.storage_key or "", safe="/")
        headers = self._headers(user)
        async with httpx.AsyncClient(timeout=15.0) as client:
            info_response = await client.get(
                f"{self._storage_url}/object/info/"
                f"{self._storage_bucket}/{encoded_path}",
                headers=headers,
            )
            if info_response.status_code == 404:
                raise InvalidUploadError(
                    "The uploaded PDF was not found in private storage"
                )
            self._raise_for_repository_error(info_response)

            content_response = await client.get(
                f"{self._storage_url}/object/authenticated/"
                f"{self._storage_bucket}/{encoded_path}",
                headers={**headers, "Range": "bytes=0-4"},
            )
        self._raise_for_repository_error(content_response)
        if not content_response.content.startswith(b"%PDF-"):
            raise InvalidUploadError("The uploaded file is not a valid PDF document")

        metadata = info_response.json().get("metadata") or {}
        stored_size = metadata.get("size") or info_response.json().get("size")
        if stored_size is not None and int(stored_size) != payload.file_size_bytes:
            raise InvalidUploadError(
                "The uploaded file size does not match its metadata"
            )

    @staticmethod
    def _raise_for_repository_error(response: httpx.Response) -> None:
        if response.is_success:
            return
        try:
            payload = response.json()
            if isinstance(payload, dict):
                detail = (
                    payload.get("message")
                    or payload.get("error")
                    or payload.get("statusCode")
                    or response.text
                )
            else:
                detail = response.text
        except ValueError:
            detail = response.text
        raise RepositoryError(f"Supabase request failed: {detail}")


project_repository = SupabaseProjectRepository()
