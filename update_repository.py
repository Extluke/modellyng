import sys
import os

target = os.path.join("backend", "app", "processing_repository.py")
with open(target, "r", encoding="utf-8") as f:
    content = f.read()

start_idx = content.find("def save_entities_v2(")
if start_idx == -1:
    print("Cannot find save_entities_v2")
    sys.exit(1)

new_code = '''def save_entities_v2(
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
'''

with open(target, "w", encoding="utf-8") as f:
    f.write(content[:start_idx] + new_code)

print("Updated processing_repository successfully!")
