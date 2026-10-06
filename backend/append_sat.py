import sys

code = '''
def calculate_node_saturation(project_nodes: list[dict[str, Any]]) -> None:
    """
    Menghitung agregasi saturasi riset.
    Mutasi in-place list dict project_nodes untuk menambahkan 'saturation_status'.
    Kriteria (sementara):
    - > 5 paper: HIGH (Banyak diteliti / Hijau)
    - 3 - 5 paper: MEDIUM (Cukup / Kuning)
    - 1 - 2 paper: LOW (Jarang / Oranye)
    - 0 paper (hanya muncul sbg ide/gap): NONE (Belum diteliti / Merah)
    """
    from collections import defaultdict
    
    label_counts = defaultdict(set)
    # Asumsikan tiap node memiliki 'paper_id' jika ia berasal dari suatu paper
    for node in project_nodes:
        label = str(node.get("label") or "").strip().lower()
        if not label:
            continue
        # Jika node terafiliasi dengan paper tertentu, tambahkan
        paper_id = node.get("paper_id")
        if paper_id:
            label_counts[label].add(paper_id)
            
    for node in project_nodes:
        if node.get("node_type") == "gap":
            node["saturation_status"] = "none"
        else:
            label = str(node.get("label") or "").strip().lower()
            count = len(label_counts[label])
            if count > 5:
                node["saturation_status"] = "high"
            elif count >= 3:
                node["saturation_status"] = "medium"
            else:
                node["saturation_status"] = "low"
'''

with open('app/intelligence_service.py', 'a', encoding='utf-8') as f:
    f.write(code)

print("Appended calculate_node_saturation to intelligence_service.py")
