import json
from uuid import UUID
from typing import Any
import httpx
from google import genai
from google.genai import types
from .config import get_settings

def cluster_nodes_llm(names: list[str], k: int) -> dict[str, dict[str, Any]]:
    """
    Mengelompokkan entitas menggunakan LLM dengan JSON output terstruktur.
    Validator bawaan memastikan tidak crash dan mitigasi halusinasi.
    """
    if not names:
        return {}
        
    k = min(k, len(names))
    if len(names) < 3:
        # Terlalu sedikit untuk diklaster, masukkan semua ke klaster 0
        return {name: {"cluster_id": 0, "label": "Cluster 0: General"} for name in names}

    settings = get_settings()
    client = genai.Client(api_key=settings.gemini_api_key, http_options=types.HttpOptions(timeout=120_000))
    
    prompt = f"""Kelompokkan {len(names)} konsep berikut ke dalam maksimal {k} klaster berdasarkan kemiripan makna/konteks ilmiahnya.

ATURAN WAJIB:
1. Output WAJIB dalam format JSON yang berisi array 'clusters'.
2. Setiap objek klaster wajib memiliki 'cluster_id' (angka 0 sampai {k-1}), 'label' (maksimal 3 kata yang merangkum isi klaster), dan 'members' (array string berisi nama entitas yang persis sama dengan input).
3. SEMUA item dari input wajib dimasukkan ke salah satu klaster. Jangan ada yang terlewat.
4. JANGAN menambah item yang tidak ada di input.

Input Entitas:
{json.dumps(names)}

Contoh Output JSON:
{{
  "clusters": [
    {{
      "cluster_id": 0,
      "label": "Machine Learning",
      "members": ["Deep Learning", "CNN"]
    }},
    {{
      "cluster_id": 1,
      "label": "Data Processing",
      "members": ["Data Cleansing", "Normalization"]
    }}
  ]
}}
"""
    try:
        response = client.models.generate_content(
            model=settings.gemini_model,
            contents=prompt,
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                temperature=0.1 # Rendah agar tidak halusinasi
            )
        )
        raw_text = response.text
        if raw_text.startswith("```json"):
            raw_text = raw_text[7:]
        if raw_text.endswith("```"):
            raw_text = raw_text[:-3]
            
        data = json.loads(raw_text.strip())
        
        # Pemetaan hasil
        mapping = {}
        for cluster in data.get("clusters", []):
            cid = cluster.get("cluster_id", 0)
            if not isinstance(cid, int) or cid < 0 or cid >= k:
                cid = 0
            
            label_text = str(cluster.get("label", "General")).strip()
            label = f"Cluster {cid}: {label_text}"
            
            for member in cluster.get("members", []):
                mapping[member] = {"cluster_id": cid, "label": label}
                
        # Validator Lapis 2: Jika ada nama yang terlewat, paksa ke klaster 0
        for name in names:
            if name not in mapping:
                mapping[name] = {"cluster_id": 0, "label": "Cluster 0: Unclassified"}
                
        return mapping
    except Exception as e:
        import logging
        logging.error(f"Clustering LLM Error: {e}")
        # Mitigasi Crash: Jika hancur/timeout, fallback ke klaster 0
        return {name: {"cluster_id": 0, "label": "Cluster 0: Fallback"} for name in names}


def update_clusters_for_project(project_id: UUID) -> None:
    settings = get_settings()
    headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}"
    }
    
    with httpx.Client(timeout=60.0) as client:
        resp = client.get(
            f"{settings.supabase_url}/rest/v1/knowledge_graph_nodes",
            headers=headers,
            params={
                "project_id": f"eq.{project_id}",
                "node_type": "in.(method,concept,variable,research_area,object)",
                "select": "id,node_type,label"
            }
        )
        resp.raise_for_status()
        nodes = resp.json()
        
    if not nodes:
        return
        
    method_nodes = [n for n in nodes if n["node_type"] == "method"]
    object_nodes = [n for n in nodes if n["node_type"] in ("concept", "variable", "research_area", "object")]
    
    method_names = list({n["label"] for n in method_nodes})
    object_names = list({n["label"] for n in object_nodes})
    
    updates = []
    
    # 1. Cluster Methods (k=4)
    if method_names:
        method_mapping = cluster_nodes_llm(method_names, k=4)
        for n in method_nodes:
            lbl = n["label"]
            cluster_info = method_mapping.get(lbl, {"label": "Cluster 0: Unclassified"})
            updates.append({
                "id": n["id"],
                "method_cluster": cluster_info["label"]
            })
            
    # 2. Cluster Objects (k=5)
    if object_names:
        object_mapping = cluster_nodes_llm(object_names, k=5)
        for n in object_nodes:
            lbl = n["label"]
            cluster_info = object_mapping.get(lbl, {"label": "Cluster 0: Unclassified"})
            updates.append({
                "id": n["id"],
                "object_cluster": cluster_info["label"],
                "zone_category": cluster_info["label"]
            })
            
    # Batch update
    if updates:
        from collections import defaultdict
        
        # For methods
        method_groups = defaultdict(list)
        for u in updates:
            if "method_cluster" in u:
                method_groups[u["method_cluster"]].append(u["id"])
                
        # For objects
        object_groups = defaultdict(list)
        for u in updates:
            if "object_cluster" in u:
                object_groups[u["object_cluster"]].append(u["id"])
                
        with httpx.Client(timeout=60.0) as client:
            for cluster_label, ids in method_groups.items():
                for i in range(0, len(ids), 50):
                    chunk = ids[i:i+50]
                    resp = client.patch(
                        f"{settings.supabase_url}/rest/v1/knowledge_graph_nodes",
                        headers=headers,
                        params={"id": f"in.({','.join(chunk)})"},
                        json={"method_cluster": cluster_label}
                    )
                    resp.raise_for_status()
                    
            for cluster_label, ids in object_groups.items():
                for i in range(0, len(ids), 50):
                    chunk = ids[i:i+50]
                    resp = client.patch(
                        f"{settings.supabase_url}/rest/v1/knowledge_graph_nodes",
                        headers=headers,
                        params={"id": f"in.({','.join(chunk)})"},
                        json={
                            "object_cluster": cluster_label,
                            "zone_category": cluster_label
                        }
                    )
                    resp.raise_for_status()
