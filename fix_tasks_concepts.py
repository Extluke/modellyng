import sys
import os

target = os.path.join("backend", "app", "tasks.py")
with open(target, "r", encoding="utf-8") as f:
    content = f.read()

replacement = """
                        # Forensic 5: Fetch concepts for this paper
                        try:
                            with httpx.Client(timeout=10.0) as client:
                                resp = client.get(
                                    f"{settings.supabase_url}/rest/v1/knowledge_graph_nodes",
                                    headers={
                                        "apikey": settings.supabase_service_role_key,
                                        "Authorization": f"Bearer {settings.supabase_service_role_key}"
                                    },
                                    params={
                                        "project_id": f"eq.{project_id}",
                                        "node_type": "eq.concept",
                                        "select": "label"
                                    }
                                )
                                if resp.is_success:
                                    for node in resp.json():
                                        extracted_valid_entities_for_edge.append(node["label"])
                        except Exception:
                            pass
"""

content = content.replace("""                        # Forensic 5: Fetch concepts for this paper
                        try:
                            blocks = repository.get_blocks(parsed_paper_id)
                            # Wait, the concepts were saved by Phase 1. 
                            # We can just query knowledge_graph_nodes directly?
                            # Not worth complicating here if we don't have a direct repo method. Let's write the query in a simple way or skip passing concept if too hard.
                            pass
                        except Exception:
                            pass""", replacement)

with open(target, "w", encoding="utf-8") as f:
    f.write(content)
print("Updated tasks.py to fetch concept nodes")
