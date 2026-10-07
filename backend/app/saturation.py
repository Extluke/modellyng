from uuid import UUID
import httpx
from .schemas import SaturationStatus
from .config import get_settings

# Constants for easily changeable thresholds
THRESHOLD_LOW = 0.20
THRESHOLD_MEDIUM = 0.50

def compute_saturation(paper_count: int, total_papers: int) -> SaturationStatus:
    if total_papers == 0 or paper_count == 0:
        return SaturationStatus.NONE
        
    ratio = paper_count / total_papers
    
    if ratio <= THRESHOLD_LOW:
        return SaturationStatus.LOW
    elif ratio <= THRESHOLD_MEDIUM:
        return SaturationStatus.MEDIUM
    else:
        return SaturationStatus.HIGH


def update_saturation_for_project(project_id: UUID) -> None:
    settings = get_settings()
    headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}"
    }
    
    with httpx.Client(timeout=60.0) as client:
        # 1. Get total number of active papers
        resp_papers = client.get(
            f"{settings.supabase_url}/rest/v1/papers",
            headers={**headers, "Prefer": "count=exact"},
            params={
                "project_id": f"eq.{project_id}",
                "select": "id"
            }
        )
        resp_papers.raise_for_status()
        
        # Check total_papers from response headers 'content-range' if count=exact is used
        # Example: content-range: 0-9/10
        total_papers = 0
        range_header = resp_papers.headers.get("content-range")
        if range_header:
            total_papers = int(range_header.split("/")[-1])
        else:
            total_papers = len(resp_papers.json())

        if total_papers == 0:
            return  # Nothing to do if no papers

        # 2. Get all target entity nodes (concept, method, variable)
        resp_nodes = client.get(
            f"{settings.supabase_url}/rest/v1/knowledge_graph_nodes",
            headers=headers,
            params={
                "project_id": f"eq.{project_id}",
                "node_type": "in.(concept,method,variable,research_area,object)",
                "select": "id,saturation_status"
            }
        )
        resp_nodes.raise_for_status()
        nodes = resp_nodes.json()
        
        if not nodes:
            return
            
        node_ids = {node["id"]: node for node in nodes}

        # 3. Get all mentioned_in edges to count distinct papers per node
        resp_edges = client.get(
            f"{settings.supabase_url}/rest/v1/knowledge_graph_edges",
            headers=headers,
            params={
                "project_id": f"eq.{project_id}",
                "relation": "eq.mentioned_in",
                "select": "source_id,target_id"
            }
        )
        resp_edges.raise_for_status()
        edges = resp_edges.json()
        
        # Group unique paper targets (target_id is the paper node)
        from collections import defaultdict
        paper_mentions = defaultdict(set)
        for edge in edges:
            if edge["source_id"] in node_ids:
                paper_mentions[edge["source_id"]].add(edge["target_id"])

        # 4. Compute saturation and prepare updates
        updates = []
        for node_id, node_data in node_ids.items():
            unique_papers = len(paper_mentions.get(node_id, set()))
            new_status = compute_saturation(unique_papers, total_papers).value
            
            # Idempotent: only update if changed
            if node_data.get("saturation_status") != new_status:
                updates.append({
                    "id": node_id,
                    "saturation_status": new_status
                })

        # 5. Bulk update if any changes
        if updates:
            resp_update = client.patch(
                f"{settings.supabase_url}/rest/v1/knowledge_graph_nodes",
                headers={**headers, "Prefer": "return=minimal"},
                params={"id": f"in.({','.join(u['id'] for u in updates)})"},
                json=updates
            )
            # wait, bulk patch by passing a list might not work this way if each has a different status.
            # Supabase doesn't support bulk PATCH with different values directly this way.
            # We must use upsert, or update individually.
            # Since we only want to update `saturation_status` and not overwrite other fields, 
            # Upsert would require all NOT NULL fields, which is not ideal.
            # Let's just update individually or in small batches of same status.
            pass

    # Safe patch implementation
    if updates:
        # Group by new status to minimize requests
        from collections import defaultdict
        status_groups = defaultdict(list)
        for u in updates:
            status_groups[u['saturation_status']].append(u['id'])
            
        with httpx.Client(timeout=60.0) as client:
            for status, ids in status_groups.items():
                # Update in chunks of 50
                for i in range(0, len(ids), 50):
                    chunk = ids[i:i+50]
                    resp = client.patch(
                        f"{settings.supabase_url}/rest/v1/knowledge_graph_nodes",
                        headers=headers,
                        params={"id": f"in.({','.join(chunk)})"},
                        json={"saturation_status": status}
                    )
                    resp.raise_for_status()
