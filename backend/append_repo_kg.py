import sys

code = '''
    async def get_knowledge_graph(
        self, user: AuthenticatedUser, project_id: UUID
    ) -> 'KnowledgeGraphMapRead':
        project = await self.get_project(user, project_id)

        # 1. Fetch nodes and edges from Supabase
        with httpx.Client(timeout=15.0) as client:
            nodes_resp = client.get(
                f"{self._rest_url}/knowledge_graph_nodes",
                headers=self._headers(user),
                params={"project_id": f"eq.{project_id}"}
            )
            self._raise_for_error(nodes_resp)
            edges_resp = client.get(
                f"{self._rest_url}/knowledge_graph_edges",
                headers=self._headers(user),
                params={"project_id": f"eq.{project_id}"}
            )
            self._raise_for_error(edges_resp)
            
        nodes_data = nodes_resp.json()
        edges_data = edges_resp.json()

        # 2. Calculate Saturation
        from .intelligence_service import calculate_node_saturation
        calculate_node_saturation(nodes_data)

        # 3. NetworkX Layouting
        import networkx as nx
        
        G = nx.DiGraph()
        
        # Mapping partitions for zone_category
        # 0: research_area / concept -> Zone: Dasar
        # 1: variable / method -> Zone: Metodologi
        # 2: result -> Zone: Temuan
        # 3: gap -> Zone: Peluang (Celah)
        
        def get_partition(node_type: str) -> tuple[int, str]:
            nt = (node_type or "").lower()
            if nt in ("gap",):
                return 3, "Peluang (Celah)"
            elif nt in ("result",):
                return 2, "Temuan"
            elif nt in ("variable", "method"):
                return 1, "Metodologi"
            else:
                return 0, "Dasar Konsep"

        for node in nodes_data:
            partition_idx, zone_name = get_partition(node.get("node_type"))
            node["zone_category"] = zone_name
            G.add_node(node["id"], partition=partition_idx)

        for edge in edges_data:
            G.add_edge(edge["source_id"], edge["target_id"])

        # Layout computation
        try:
            pos = nx.multipartite_layout(G, subset_key="partition", align="vertical", scale=1000)
            for node in nodes_data:
                coords = pos.get(node["id"])
                if coords is not None:
                    node["x"] = float(coords[0])
                    node["y"] = float(coords[1])
        except Exception as e:
            # Fallback spring layout
            try:
                pos = nx.spring_layout(G, scale=1000)
                for node in nodes_data:
                    coords = pos.get(node["id"])
                    if coords is not None:
                        node["x"] = float(coords[0])
                        node["y"] = float(coords[1])
            except Exception:
                pass
                
        # 4. Map back to edges format expected by schema
        edges_formatted = []
        for e in edges_data:
            edges_formatted.append({
                "source": e["source_id"],
                "target": e["target_id"],
                "relation": e["relation"],
                "detail": e.get("detail")
            })

        # 5. Format nodes to match schemas
        nodes_formatted = []
        for n in nodes_data:
            nodes_formatted.append({
                "id": n["id"],
                "kind": n["node_type"],
                "label": n["label"],
                "detail": n.get("detail", ""),
                "parent_id": n.get("parent_id"),
                "gap_typology": n.get("gap_typology"),
                "saturation_status": n.get("saturation_status"),
                "confidence_score": float(n["confidence_score"]) if n.get("confidence_score") else None,
                "zone_category": n.get("zone_category"),
                "x": n.get("x"),
                "y": n.get("y"),
                "evidence": n.get("evidence", []),
                "status": n.get("status")
            })

        from .schemas import KnowledgeGraphMapRead
        return KnowledgeGraphMapRead(
            project_id=project.id,
            project_title=project.title,
            nodes=nodes_formatted,
            edges=edges_formatted
        )
'''

with open('app/repository.py', 'a', encoding='utf-8') as f:
    f.write(code)

print("Appended get_knowledge_graph to repository.py")
