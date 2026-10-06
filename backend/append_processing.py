import sys

code = '''
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
'''

with open('app/processing_repository.py', 'a', encoding='utf-8') as f:
    f.write(code)

print("Appended save_knowledge_graph to processing_repository.py")
