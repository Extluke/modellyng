import sys
import os

target = os.path.join("backend", "app", "processing_repository.py")
with open(target, "a", encoding="utf-8") as f:
    f.write('''
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
''')
print("Appended Phase 7 to processing_repository.py")
