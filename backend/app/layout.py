import uuid
from typing import Any
import httpx
import networkx as nx
from .config import get_settings
import logging

logger = logging.getLogger(__name__)

# Zone configurations (X-axis bounds)
# Y-axis can span 0 to 2000
ZONE_BOUNDS = {
    "none": (0, 400),
    "low": (500, 900),
    "medium": (1000, 1400),
    "high": (1500, 1900),
}
Y_BOUNDS = (0, 2000)

def compute_layout(nodes: list[dict], edges: list[dict]) -> dict[str, tuple[float, float]]:
    """
    Computes X and Y coordinates for nodes based on their saturation_status.
    Separates graph into subgraphs by saturation_status, runs spring_layout for each,
    and scales them into their respective spatial zones.
    """
    if not nodes:
        return {}

    # Build the main graph
    G = nx.Graph()
    for n in nodes:
        # Default to 'none' if empty or invalid
        status = (n.get("saturation_status") or "none").lower()
        if status not in ZONE_BOUNDS:
            status = "none"
        G.add_node(n["id"], status=status)
        
    # Map node to its index for quick edge lookup
    node_ids = set(G.nodes)

    for e in edges:
        u = e["source"]
        v = e["target"]
        if u in node_ids and v in node_ids:
            G.add_edge(u, v)

    layout_result = {}
    
    # Process each zone independently
    for status, (min_x, max_x) in ZONE_BOUNDS.items():
        # Get nodes that belong to this zone
        zone_nodes = [n for n, attr in G.nodes(data=True) if attr["status"] == status]
        if not zone_nodes:
            continue
            
        # Create subgraph (includes edges between nodes in the same zone)
        H = G.subgraph(zone_nodes)
        
        # Calculate spring layout
        # NetworkX layouts require numpy. If numpy is not installed, fallback to pure Python
        try:
            pos = nx.spring_layout(H, seed=42)
        except ImportError:
            # Pure Python fallback random layout
            import random
            rng = random.Random(42)
            pos = {node: (rng.random() * 2 - 1, rng.random() * 2 - 1) for node in H.nodes}
        except Exception as e:
            logger.error(f"Error in spring_layout for zone {status}: {e}")
            import random
            rng = random.Random(42)
            pos = {node: (rng.random() * 2 - 1, rng.random() * 2 - 1) for node in H.nodes}
            
        if not pos:
            continue
            
        # Rescale the points to fit inside the zone bounds
        # min_x to max_x for X, Y_BOUNDS for Y
        xs = [p[0] for p in pos.values()]
        ys = [p[1] for p in pos.values()]
        
        min_p_x, max_p_x = min(xs), max(xs)
        min_p_y, max_p_y = min(ys), max(ys)
        
        range_p_x = max_p_x - min_p_x
        range_p_y = max_p_y - min_p_y
        
        width_zone = max_x - min_x
        height_zone = Y_BOUNDS[1] - Y_BOUNDS[0]
        
        for node_id, (px, py) in pos.items():
            if range_p_x == 0:
                # If only 1 node or all X are the same
                final_x = min_x + (width_zone / 2.0)
            else:
                # Normalize to 0-1, then scale and shift
                final_x = min_x + ((px - min_p_x) / range_p_x) * width_zone
                
            if range_p_y == 0:
                final_y = Y_BOUNDS[0] + (height_zone / 2.0)
            else:
                final_y = Y_BOUNDS[0] + ((py - min_p_y) / range_p_y) * height_zone
                
            layout_result[node_id] = (final_x, final_y)
            
    # Fallback to ensure no two nodes have identical coordinates if they somehow end up overlapping
    # Add minor jitter to duplicates
    seen_coords = set()
    for node_id, (x, y) in layout_result.items():
        while (x, y) in seen_coords:
            x += 0.1
            y += 0.1
        layout_result[node_id] = (x, y)
        seen_coords.add((x, y))

    return layout_result


def update_layout_for_project(project_id: uuid.UUID) -> None:
    """Fetches nodes and edges, computes their layout, and patches the database."""
    settings = get_settings()
    headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}"
    }
    
    with httpx.Client(timeout=60.0) as client:
        resp_nodes = client.get(
            f"{settings.supabase_url}/rest/v1/knowledge_graph_nodes",
            headers=headers,
            params={
                "project_id": f"eq.{project_id}",
                "select": "id,saturation_status"
            }
        )
        resp_nodes.raise_for_status()
        nodes = resp_nodes.json()
        
        resp_edges = client.get(
            f"{settings.supabase_url}/rest/v1/knowledge_graph_edges",
            headers=headers,
            params={
                "project_id": f"eq.{project_id}",
                "select": "source,target"
            }
        )
        resp_edges.raise_for_status()
        edges = resp_edges.json()
        
    if not nodes:
        return
        
    layout_mapping = compute_layout(nodes, edges)
    
    # Batch update coordinates in chunks of 50
    node_ids = list(layout_mapping.keys())
    with httpx.Client(timeout=60.0) as client:
        # Supabase doesn't support bulk dynamic patching natively out of the box with varying bodies 
        # for different rows easily without a function. 
        # So we iterate and patch individually or grouped by coords if needed.
        # But patching individually for 1000s of nodes could be slow.
        # However, for Python scripts, let's just use asyncio or batch as best as possible.
        # The easiest approach for arbitrary X,Y is to update them one by one.
        for node_id, (x, y) in layout_mapping.items():
            resp = client.patch(
                f"{settings.supabase_url}/rest/v1/knowledge_graph_nodes",
                headers=headers,
                params={"id": f"eq.{node_id}"},
                json={"x": x, "y": y}
            )
            resp.raise_for_status()


def compute_zones(nodes: list[dict]) -> list[dict]:
    """
    Computes bounding boxes for each saturation_status zone based on final node coordinates.
    Returns: [{'saturation_status': 'high', 'min_x': 0.0, ...}]
    Ignores empty zones.
    """
    zones_map = {}
    
    for n in nodes:
        status = (n.get("saturation_status") or "none").lower()
        x = n.get("x")
        y = n.get("y")
        
        if x is None or y is None:
            continue
            
        if status not in zones_map:
            zones_map[status] = {
                "saturation_status": status,
                "min_x": x,
                "max_x": x,
                "min_y": y,
                "max_y": y,
            }
        else:
            z = zones_map[status]
            z["min_x"] = min(z["min_x"], x)
            z["max_x"] = max(z["max_x"], x)
            z["min_y"] = min(z["min_y"], y)
            z["max_y"] = max(z["max_y"], y)
            
    # Add some padding to bounding boxes so nodes aren't on the exact edge
    PADDING = 20.0
    result = []
    for z in zones_map.values():
        z["min_x"] -= PADDING
        z["max_x"] += PADDING
        z["min_y"] -= PADDING
        z["max_y"] += PADDING
        result.append(z)
        
    return result

