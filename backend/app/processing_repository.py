from __future__ import annotations

from urllib.parse import quote
from uuid import UUID

import httpx

from .ai_extraction import VerifiedPaperExtraction
from .config import get_settings
from .pdf_processing import ExtractedPdf


class ProcessingRepositoryError(RuntimeError):
    pass


class PdfProcessingRepository:
    """Service-role data adapter used only by the trusted Celery worker."""

    def __init__(self) -> None:
        settings = get_settings()
        self._rest_url = f"{settings.supabase_url}/rest/v1"
        self._storage_url = f"{settings.supabase_url}/storage/v1"
        self._service_key = settings.supabase_service_role_key
        self._storage_bucket = settings.object_storage_bucket
        if not self._service_key.strip():
            raise ProcessingRepositoryError(
                "MODELLYNG_SUPABASE_SERVICE_ROLE_KEY wajib diisi untuk worker"
            )

    @property
    def _headers(self) -> dict[str, str]:
        return {
            "apikey": self._service_key,
            "Authorization": f"Bearer {self._service_key}",
        }

    def get_paper(self, paper_id: UUID) -> dict[str, object]:
        with httpx.Client(timeout=15.0) as client:
            response = client.get(
                f"{self._rest_url}/papers",
                headers=self._headers,
                params={
                    "select": (
                        "id,project_id,storage_key,original_filename,status,"
                        "projects(owner_id)"
                    ),
                    "id": f"eq.{paper_id}",
                    "limit": "1",
                },
            )
        self._raise_for_error(response)
        rows = response.json()
        if not rows:
            raise ProcessingRepositoryError("Paper tidak ditemukan")

        paper = rows[0]
        project = paper.get("projects") or {}
        owner_id = str(project.get("owner_id") or "")
        expected_prefix = f"{owner_id}/{paper['project_id']}/"
        storage_key = str(paper.get("storage_key") or "")
        if not owner_id or not storage_key.startswith(expected_prefix):
            raise ProcessingRepositoryError(
                "Lokasi penyimpanan PDF tidak sesuai dengan pemilik proyek"
            )
        return paper

    def download_pdf(self, storage_key: str) -> bytes:
        encoded_path = quote(storage_key, safe="/")
        with httpx.Client(timeout=60.0) as client:
            response = client.get(
                f"{self._storage_url}/object/authenticated/"
                f"{self._storage_bucket}/{encoded_path}",
                headers=self._headers,
            )
        self._raise_for_error(response)
        return response.content

    def update_job(
        self,
        job_id: UUID,
        *,
        status: str,
        stage: str,
        progress: float,
        error_message: str | None = None,
    ) -> None:
        with httpx.Client(timeout=15.0) as client:
            response = client.patch(
                f"{self._rest_url}/analysis_jobs",
                headers={**self._headers, "Prefer": "return=minimal"},
                params={"id": f"eq.{job_id}"},
                json={
                    "status": status,
                    "stage": stage,
                    "progress": progress,
                    "error_message": error_message,
                },
            )
        self._raise_for_error(response)

    def update_paper_status(self, paper_id: UUID, status: str) -> None:
        self._patch("papers", paper_id, {"status": status})

    def update_project_status(self, project_id: UUID, status: str) -> None:
        self._patch("projects", project_id, {"status": status})

    def save_extraction(self, paper_id: UUID, extraction: ExtractedPdf) -> None:
        blocks: list[dict[str, object]] = []
        block_index = 0
        for page in extraction.pages:
            for text_chunk in self._split_text(page.text):
                blocks.append(
                    {
                        "paper_id": str(paper_id),
                        "block_index": block_index,
                        "page_number": page.page_number,
                        "content": text_chunk,
                    }
                )
                block_index += 1

        with httpx.Client(timeout=60.0) as client:
            for start in range(0, len(blocks), 100):
                response = client.post(
                    f"{self._rest_url}/paper_blocks",
                    headers={
                        **self._headers,
                        "Prefer": "resolution=merge-duplicates,return=minimal",
                    },
                    params={"on_conflict": "paper_id,block_index"},
                    json=blocks[start : start + 100],
                )
                self._raise_for_error(response)

        paper_update: dict[str, object] = {
            "page_count": extraction.page_count,
            "language_code": extraction.language_code,
            "status": "processing",
        }
        if extraction.title:
            paper_update["title"] = extraction.title
        if extraction.authors:
            paper_update["authors"] = list(extraction.authors)
        self._patch("papers", paper_id, paper_update)

    def get_blocks(self, paper_id: UUID) -> list[dict[str, object]]:
        with httpx.Client(timeout=30.0) as client:
            response = client.get(
                f"{self._rest_url}/paper_blocks",
                headers=self._headers,
                params={
                    "select": "id,block_index,page_number,section,subsection,content",
                    "paper_id": f"eq.{paper_id}",
                    "order": "block_index.asc",
                },
            )
        self._raise_for_error(response)
        return response.json()

    def save_ai_extraction(
        self,
        *,
        job_id: UUID,
        paper_id: UUID,
        extraction: VerifiedPaperExtraction,
    ) -> None:
        if extraction.metadata.title:
            paper_update = {
                "title": extraction.metadata.title,
                "authors": extraction.metadata.authors,
                "publication_year": extraction.metadata.publication_year,
                "journal": extraction.metadata.journal,
                "doi": extraction.metadata.doi,
            }
            # Remove None values
            paper_update = {k: v for k, v in paper_update.items() if v is not None}
            if paper_update:
                self._patch("papers", paper_id, paper_update)

        component_rows = [
            {
                "paper_id": str(paper_id),
                "analysis_job_id": str(job_id),
                "parameter": component.parameter.value,
                "ai_value": component.value,
                "status": "needs_review",
                "confidence": component.confidence,
                "model_name": extraction.model_name,
                "prompt_version": extraction.prompt_version,
                "is_active": False,
            }
            for component in extraction.components
        ]
        with httpx.Client(timeout=60.0) as client:
            response = client.post(
                f"{self._rest_url}/extracted_components",
                headers={
                    **self._headers,
                    "Prefer": "resolution=merge-duplicates,return=representation",
                },
                params={"on_conflict": "analysis_job_id,paper_id,parameter"},
                json=component_rows,
            )
        self._raise_for_error(response)
        saved_components = response.json()
        component_ids = {
            row["parameter"]: row["id"] for row in saved_components
        }

        evidence_rows: list[dict[str, object]] = []
        for component in extraction.components:
            component_id = component_ids.get(component.parameter.value)
            if not component_id:
                continue
            for evidence in component.evidence:
                evidence_rows.append(
                    {
                        "component_id": component_id,
                        "paper_block_id": str(evidence.paper_block_id),
                        "quote": evidence.quote,
                        "page_number": evidence.page_number,
                        "evidence_kind": evidence.evidence_kind.value,
                        "source_label": evidence.source_label,
                        "section": evidence.section,
                        "subsection": evidence.subsection,
                    }
                )
        if evidence_rows:
            with httpx.Client(timeout=60.0) as client:
                response = client.post(
                    f"{self._rest_url}/evidence_spans",
                    headers={**self._headers, "Prefer": "return=minimal"},
                    json=evidence_rows,
                )
            self._raise_for_error(response)

        structure_rows: list[dict[str, object]] = []
        for part in extraction.structure:
            structure_rows.append({
                "paper_id": str(paper_id),
                "analysis_job_id": str(job_id),
                "part_name": part.section_name,
                "is_present": part.is_present,
                "page_number": part.page_number,
                "status": "needs_review",
            })
        if structure_rows:
            with httpx.Client(timeout=60.0) as client:
                response = client.post(
                    f"{self._rest_url}/paper_structures",
                    headers={**self._headers, "Prefer": "resolution=merge-duplicates,return=minimal"},
                    params={"on_conflict": "paper_id,part_name"},
                    json=structure_rows,
                )
            self._raise_for_error(response)
            
        gap_rows: list[dict[str, object]] = []
        for gap in extraction.research_gaps:
            evidence = gap.evidence[0] if gap.evidence else None
            gap_rows.append({
                "paper_id": str(paper_id),
                "analysis_job_id": str(job_id),
                "gap_statement": gap.gap_statement,
                "gap_type": gap.gap_type,
                "supporting_section": gap.supporting_section,
                "confidence": gap.confidence,
                "is_explicit": gap.is_explicit,
                "is_active": False,
                "paper_block_id": str(evidence.paper_block_id) if evidence else None,
                "evidence_quote": evidence.quote if evidence else None,
                "page_number": evidence.page_number if evidence else None,
            })
        if gap_rows:
            with httpx.Client(timeout=60.0) as client:
                response = client.post(
                    f"{self._rest_url}/research_gaps",
                    headers={**self._headers, "Prefer": "return=minimal"},
                    json=gap_rows,
                )
            self._raise_for_error(response)

        # Activate the complete new result only after both components and
        # evidence have been persisted. The database function switches the
        # version atomically while retaining older rows for audit history.
        with httpx.Client(timeout=30.0) as client:
            response = client.post(
                f"{self._rest_url}/rpc/activate_analysis_components",
                headers={**self._headers, "Prefer": "return=minimal"},
                json={"p_job_id": str(job_id), "p_paper_id": str(paper_id)},
            )
        self._raise_for_error(response)

        metadata = extraction.metadata
        paper_update: dict[str, object] = {"status": "needs_review"}
        if metadata.title:
            paper_update["title"] = metadata.title
        if metadata.authors:
            paper_update["authors"] = metadata.authors
        if metadata.publication_year:
            paper_update["publication_year"] = metadata.publication_year
        if metadata.journal:
            paper_update["journal"] = metadata.journal
        if metadata.doi:
            paper_update["doi"] = metadata.doi
        for field in ("publisher", "volume", "issue", "pages", "publication_status"):
            # New analysis may honestly find no value; never retain stale metadata.
            paper_update[field] = getattr(metadata, field)
        paper_update["metadata_verified"] = False
        self._patch("papers", paper_id, paper_update)

    def mark_failure(
        self,
        *,
        job_id: UUID,
        paper_id: UUID,
        project_id: UUID | None,
        message: str,
    ) -> None:
        safe_message = " ".join(message.split())[:1_000]
        try:
            self.update_job(
                job_id,
                status="failed",
                stage="failed",
                progress=1,
                error_message=safe_message,
            )
            self.update_paper_status(paper_id, "failed")
            if project_id:
                self.update_project_status(project_id, "needs_review")
        except Exception:
            # Failure persistence is best-effort. Never replace the original
            # pipeline exception with a secondary status-update exception.
            pass

    def _patch(self, table: str, record_id: UUID, payload: dict[str, object]) -> None:
        with httpx.Client(timeout=15.0) as client:
            response = client.patch(
                f"{self._rest_url}/{table}",
                headers={**self._headers, "Prefer": "return=minimal"},
                params={"id": f"eq.{record_id}"},
                json=payload,
            )
        self._raise_for_error(response)

    @staticmethod
    def _split_text(text: str, limit: int = 8_000) -> list[str]:
        if len(text) <= limit:
            return [text]
        chunks: list[str] = []
        remaining = text
        while remaining:
            split_at = min(limit, len(remaining))
            if split_at < len(remaining):
                paragraph_break = remaining.rfind("\n", 0, split_at)
                if paragraph_break > limit // 2:
                    split_at = paragraph_break
            chunk = remaining[:split_at].strip()
            if chunk:
                chunks.append(chunk)
            remaining = remaining[split_at:].lstrip()
        return chunks

    @staticmethod
    def _raise_for_error(response: httpx.Response) -> None:
        if response.is_success:
            return
        try:
            payload = response.json()
            detail = (
                payload.get("message")
                or payload.get("error")
                or payload.get("details")
                or response.text
            )
        except (ValueError, AttributeError):
            detail = response.text
        raise ProcessingRepositoryError(f"Supabase worker request gagal: {detail}")

    def save_knowledge_graph(
        self,
        *,
        project_id: UUID,
        extraction: object,
    ) -> None:
        """Save Knowledge Graph entities."""
        node_rows = [
            {
                "project_id": str(project_id),
                "node_type": node.node_type,
                "label": node.label,
                "detail": node.detail,
                "gap_typology": node.gap_typology,
                "confidence_score": node.confidence_score,
                "evidence": [{"quote": node.evidence_quote}] if node.evidence_quote else [],
                "status": "pending"
            }
            for node in extraction.nodes
        ]
        
        node_id_map = {}
        if node_rows:
            import httpx
            with httpx.Client(timeout=60.0) as client:
                response = client.post(
                    f"{self._rest_url}/knowledge_graph_nodes",
                    headers={**self._headers, "Prefer": "return=representation"},
                    json=node_rows,
                )
            self._raise_for_error(response)
            saved_nodes = response.json()
            for row in saved_nodes:
                node_id_map[row["label"]] = row["id"]

        edge_rows = []
        for edge in extraction.edges:
            source_id = node_id_map.get(edge.source_label)
            target_id = node_id_map.get(edge.target_label)
            if source_id and target_id:
                edge_rows.append({
                    "project_id": str(project_id),
                    "source_id": source_id,
                    "target_id": target_id,
                    "relation": edge.relation,
                    "detail": edge.detail
                })

        if edge_rows:
            import httpx
            with httpx.Client(timeout=60.0) as client:
                response = client.post(
                    f"{self._rest_url}/knowledge_graph_edges",
                    headers={**self._headers, "Prefer": "return=minimal"},
                    json=edge_rows,
                )
            self._raise_for_error(response)

    def save_entities_v2(
        self,
        *,
        project_id: UUID,
        paper_id: UUID,
        parsed_entities: dict,
        paper_title: str | None = None
    ) -> None:
        """Save AI extracted entities (v2) safely using upsert to avoid race conditions."""
        import httpx
        
        # Determine paper node
        with httpx.Client(timeout=60.0) as client:
            resp = client.get(
                f"{self._rest_url}/knowledge_graph_nodes",
                headers=self._headers,
                params={
                    "project_id": f"eq.{project_id}",
                    "node_type": "eq.paper",
                    "detail": f"eq.{paper_id}",
                }
            )
        self._raise_for_error(resp)
        paper_nodes = resp.json()
        
        if paper_nodes:
            paper_node_id = paper_nodes[0]["id"]
        else:
            # Create paper node
            title = paper_title or f"Paper {paper_id}"
            with httpx.Client(timeout=60.0) as client:
                resp = client.post(
                    f"{self._rest_url}/knowledge_graph_nodes",
                    headers={**self._headers, "Prefer": "return=representation, resolution=ignore-duplicates"},
                    params={"on_conflict": "project_id,node_type,label"},
                    json={
                        "project_id": str(project_id),
                        "node_type": "paper",
                        "label": title[:100],
                        "detail": str(paper_id),
                        "status": "accepted"
                    }
                )
            self._raise_for_error(resp)
            paper_nodes_inserted = resp.json()
            if paper_nodes_inserted:
                paper_node_id = paper_nodes_inserted[0]["id"]
            else:
                # it was ignored, fetch it again
                with httpx.Client(timeout=60.0) as client:
                    resp = client.get(
                        f"{self._rest_url}/knowledge_graph_nodes",
                        headers=self._headers,
                        params={"project_id": f"eq.{project_id}", "node_type": "eq.paper", "detail": f"eq.{paper_id}"}
                    )
                self._raise_for_error(resp)
                paper_node_id = resp.json()[0]["id"]

        # Forensic 6: Upsert nodes to prevent race conditions
        node_rows_to_upsert = []
        for key, n_type in [("variables", "variable"), ("methods", "method"), ("results", "result")]:
            for label in parsed_entities.get(key, []):
                if not isinstance(label, str) or not label.strip():
                    continue
                node_rows_to_upsert.append({
                    "project_id": str(project_id),
                    "node_type": n_type,
                    "label": label.strip()[:100],
                    "status": "accepted"
                })
        
        entity_map = {}
        if node_rows_to_upsert:
            with httpx.Client(timeout=60.0) as client:
                resp = client.post(
                    f"{self._rest_url}/knowledge_graph_nodes",
                    headers={**self._headers, "Prefer": "return=representation, resolution=merge-duplicates"},
                    params={"on_conflict": "project_id,node_type,label"},
                    json=node_rows_to_upsert,
                )
            self._raise_for_error(resp)
            for row in resp.json():
                entity_map[row["label"].strip().lower()] = row["id"]
                
        # Now create edges: entity -> paper
        if not entity_map:
            return
            
        # check existing edges to avoid duplicate edges
        with httpx.Client(timeout=60.0) as client:
            resp = client.get(
                f"{self._rest_url}/knowledge_graph_edges",
                headers=self._headers,
                params={
                    "project_id": f"eq.{project_id}",
                    "target_id": f"eq.{paper_node_id}",
                    "relation": "eq.mentioned_in",
                }
            )
        self._raise_for_error(resp)
        existing_edges = set(e["source_id"] for e in resp.json())
        
        edge_rows_to_insert = []
        for key in ["variables", "methods", "results"]:
            for label in parsed_entities.get(key, []):
                if not isinstance(label, str) or not label.strip():
                    continue
                lower_label = label.strip().lower()
                entity_id = entity_map.get(lower_label)
                if entity_id and entity_id not in existing_edges:
                    edge_rows_to_insert.append({
                        "project_id": str(project_id),
                        "source_id": entity_id,
                        "target_id": paper_node_id,
                        "relation": "mentioned_in",
                        "detail": None
                    })
                    existing_edges.add(entity_id)
                    
        if edge_rows_to_insert:
            with httpx.Client(timeout=60.0) as client:
                resp = client.post(
                    f"{self._rest_url}/knowledge_graph_edges",
                    headers={**self._headers, "Prefer": "return=minimal"},
                    json=edge_rows_to_insert,
                )
            self._raise_for_error(resp)

    def save_gaps_v2(
        self,
        *,
        project_id: UUID,
        paper_id: UUID,
        valid_gaps: list[dict],
        paper_title: str | None = None
    ) -> None:
        """Save AI extracted gaps (v2), link them, and insert into gap_evidence."""
        if not valid_gaps:
            return
            
        import httpx
        
        # Determine paper node
        with httpx.Client(timeout=60.0) as client:
            resp = client.get(
                f"{self._rest_url}/knowledge_graph_nodes",
                headers=self._headers,
                params={
                    "project_id": f"eq.{project_id}",
                    "node_type": "eq.paper",
                    "detail": f"eq.{paper_id}",
                }
            )
        self._raise_for_error(resp)
        paper_nodes = resp.json()
        
        if paper_nodes:
            paper_node_id = paper_nodes[0]["id"]
        else:
            title = paper_title or f"Paper {paper_id}"
            with httpx.Client(timeout=60.0) as client:
                resp = client.post(
                    f"{self._rest_url}/knowledge_graph_nodes",
                    headers={**self._headers, "Prefer": "return=representation, resolution=ignore-duplicates"},
                    params={"on_conflict": "project_id,node_type,label"},
                    json={
                        "project_id": str(project_id),
                        "node_type": "paper",
                        "label": title[:100],
                        "detail": str(paper_id),
                        "status": "accepted"
                    }
                )
            self._raise_for_error(resp)
            paper_nodes_inserted = resp.json()
            if paper_nodes_inserted:
                paper_node_id = paper_nodes_inserted[0]["id"]
            else:
                with httpx.Client(timeout=60.0) as client:
                    resp = client.get(
                        f"{self._rest_url}/knowledge_graph_nodes",
                        headers=self._headers,
                        params={"project_id": f"eq.{project_id}", "node_type": "eq.paper", "detail": f"eq.{paper_id}"}
                    )
                self._raise_for_error(resp)
                paper_node_id = resp.json()[0]["id"]

        # Forensic 6: Upsert nodes to prevent race conditions
        node_rows_to_upsert = []
        for g in valid_gaps:
            node_rows_to_upsert.append({
                "project_id": str(project_id),
                "node_type": "research_gap",
                "label": g["statement"][:200],
                "detail": g["statement"],
                "gap_typology": g["gap_type"],
                "confidence_score": g["confidence_score"],
                "evidence": [g["evidence"]],
                "status": "accepted"
            })
            
        if node_rows_to_upsert:
            with httpx.Client(timeout=60.0) as client:
                resp = client.post(
                    f"{self._rest_url}/knowledge_graph_nodes",
                    headers={**self._headers, "Prefer": "return=representation, resolution=merge-duplicates"},
                    params={"on_conflict": "project_id,node_type,label"},
                    json=node_rows_to_upsert,
                )
            self._raise_for_error(resp)
            inserted_nodes = resp.json()
            
            edge_rows_to_insert = []
            gap_evidence_rows = []
            
            # Create a lookup for evidence based on label
            gap_map = {n["label"].strip().lower(): n["id"] for n in inserted_nodes}
            
            # Forensic 2: Insert into gap_evidence table
            for g in valid_gaps:
                gap_id = gap_map.get(g["statement"][:200].strip().lower())
                if not gap_id:
                    continue
                
                # Check edges
                edge_rows_to_insert.append({
                    "project_id": str(project_id),
                    "source_id": gap_id,
                    "target_id": paper_node_id,
                    "relation": "mentioned_in",
                    "detail": None
                })
                
                ev = g["evidence"]
                gap_evidence_rows.append({
                    "project_id": str(project_id),
                    "gap_node_id": gap_id,
                    "paper_id": str(paper_id),
                    "section": ev.get("section", ""),
                    "quote": ev.get("quote", ""),
                    "page_number": ev.get("page_number", 1)
                })
                
            if edge_rows_to_insert:
                with httpx.Client(timeout=60.0) as client:
                    resp = client.post(
                        f"{self._rest_url}/knowledge_graph_edges",
                        headers={**self._headers, "Prefer": "return=minimal"},
                        json=edge_rows_to_insert,
                    )
                self._raise_for_error(resp)
                
            if gap_evidence_rows:
                with httpx.Client(timeout=60.0) as client:
                    resp = client.post(
                        f"{self._rest_url}/gap_evidence",
                        headers={**self._headers, "Prefer": "return=minimal"},
                        json=gap_evidence_rows,
                    )
                self._raise_for_error(resp)

    def save_edges_v2(
        self,
        *,
        project_id: UUID,
        valid_edges: list[dict]
    ) -> None:
        """Save AI extracted entity-to-entity edges (v2)."""
        if not valid_edges:
            return
            
        import httpx
        
        # We need to map the string labels back to UUIDs in knowledge_graph_nodes
        # since valid_edges has "source": "label A", "target": "label B"
        labels_to_fetch = set()
        for e in valid_edges:
            labels_to_fetch.add(e["source"])
            labels_to_fetch.add(e["target"])
            
        if not labels_to_fetch:
            return
            
        # Get all nodes in project to map labels to IDs
        with httpx.Client(timeout=60.0) as client:
            resp = client.get(
                f"{self._rest_url}/knowledge_graph_nodes",
                headers=self._headers,
                params={
                    "project_id": f"eq.{project_id}",
                    "select": "id,label"
                }
            )
        self._raise_for_error(resp)
        nodes = resp.json()
        
        label_to_id = {n["label"].strip().lower(): n["id"] for n in nodes}
        
        edge_rows_to_insert = []
        for e in valid_edges:
            source_id = label_to_id.get(e["source"].strip().lower())
            target_id = label_to_id.get(e["target"].strip().lower())
            
            if source_id and target_id:
                edge_rows_to_insert.append({
                    "project_id": str(project_id),
                    "source_id": source_id,
                    "target_id": target_id,
                    "relation": e["edge_type"],
                    "detail": e["quote_basis"]
                })
                
        if edge_rows_to_insert:
            with httpx.Client(timeout=60.0) as client:
                resp = client.post(
                    f"{self._rest_url}/knowledge_graph_edges",
                    headers={**self._headers, "Prefer": "return=minimal"},
                    json=edge_rows_to_insert,
                )
            self._raise_for_error(resp)
