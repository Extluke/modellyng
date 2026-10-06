import asyncio
import os
import httpx
from httpx import Response
from supabase import create_client

from app.config import get_settings
from app.repository import project_repository
from app.ai_extraction import AiKnowledgeGraphExtraction, AiKnowledgeGraphNode, AiKnowledgeGraphEdge
from app.intelligence_service import calculate_node_saturation

async def run_tests():
    print("=== STARTING COMPREHENSIVE INTEGRATION TEST ===")
    settings = get_settings()
    
    # 1. PHASE 1 TEST: Schema & Auth check
    print("\\n[Phase 1] Testing Supabase Table Schema...")
    try:
        sb = create_client(settings.supabase_url, settings.supabase_service_role_key)
        res = sb.table('knowledge_graph_nodes').select('id', count='exact').limit(1).execute()
        print("  [OK] knowledge_graph_nodes is accessible. Count:", res.count)
        res_edges = sb.table('knowledge_graph_edges').select('id', count='exact').limit(1).execute()
        print("  [OK] knowledge_graph_edges is accessible. Count:", res_edges.count)
    except Exception as e:
        print("  [FAIL] Phase 1 Database error:", e)

    # 2. PHASE 2 TEST: Pydantic schemas for Gemini extraction
    print("\\n[Phase 2] Testing Secondary Pipeline Data Contracts...")
    try:
        mock_result = AiKnowledgeGraphExtraction(
            nodes=[
                AiKnowledgeGraphNode(id="n1", node_type="gap", label="AI bias", detail="Bias in ML", evidence_quote="Some quote")
            ],
            edges=[
                AiKnowledgeGraphEdge(source="n1", target="n2", source_label="AI bias", target_label="Issues", relation="causes", detail="AI bias causes issues")
            ]
        )
        print("  [OK] Extraction Result Pydantic Model instantiated successfully.")
    except Exception as e:
        print("  [FAIL] Phase 2 Data Contract Error:", e)

    # 3. PHASE 3 TEST: Spatial Layout (NetworkX) and Saturation logic
    print("\\n[Phase 3] Testing Graph NetworkX & Logic...")
    try:
        nodes = [{"label": "AI", "paper_id": "1"}, {"label": "AI", "paper_id": "2"}, {"label": "AI", "paper_id": "3"}, {"label": "AI", "paper_id": "4"}, {"node_type": "gap"}]
        calculate_node_saturation(nodes)
        print(f"  [OK] Node Saturation Logic executed. Result for first node: {nodes[0].get('saturation_status')}")
    except Exception as e:
        print("  [FAIL] Phase 3 Node Saturation Error:", e)

    try:
        # Test the spatial layout internal logic
        import networkx as nx
        G = nx.DiGraph()
        G.add_node("n1", category="Dasar Konsep")
        G.add_node("n2", category="Temuan")
        G.add_edge("n1", "n2")
        pos = nx.multipartite_layout(G, subset_key="category")
        print("  [OK] NetworkX generated spatial coordinates successfully.")
        print("       Sample pos:", pos)
    except Exception as e:
        print("  [WARN] Phase 3 Spatial Layout Error (Ignored if numpy missing in test env):", e)

    # 4. PHASE 4 TEST: Endpoints & Services availability
    print("\\n[Phase 4] Testing Endpoints Configuration...")
    try:
        from app.main import app
        # Ensure the routes are registered
        paths = []
        for route in app.routes:
            if hasattr(route, 'path'):
                paths.append(route.path)
            if hasattr(route, 'routes'):
                for sub_route in route.routes:
                    if hasattr(sub_route, 'path'):
                        paths.append(sub_route.path)
            if type(route).__name__ == '_IncludedRouter':
                for sub_route in route.original_router.routes:
                    if hasattr(sub_route, 'path'):
                        paths.append(sub_route.path)
        
        has_kg = any("knowledge-graph" in p for p in paths)
        has_synth = any("synthesize-graph-nodes" in p for p in paths)
        
        if has_kg and has_synth:
            print("  [OK] Endpoints registered in FastAPI router.")
        else:
            print("  [FAIL] Endpoints missing in router! Paths found:", paths)
    except Exception as e:
        print("  [FAIL] Phase 4 Endpoint Error:", e)
        
    print("\\n=== BACKEND TESTING COMPLETE ===")

if __name__ == "__main__":
    asyncio.run(run_tests())
