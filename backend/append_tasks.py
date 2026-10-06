import sys

code = '''
@celery_app.task(name="modellyng.extract_knowledge_graph", bind=True)
def extract_knowledge_graph_task(self, job_id: str, paper_id: str) -> dict[str, object]:
    """Phase 2: Extract Knowledge Graph from structured data."""
    parsed_job_id = UUID(job_id)
    parsed_paper_id = UUID(paper_id)
    repository = None
    
    try:
        repository = PdfProcessingRepository()
        paper = repository.get_paper(parsed_paper_id)
        project_id = UUID(str(paper["project_id"]))
        
        self.update_state(
            state="PROGRESS",
            meta={"job_id": job_id, "stage": "knowledge_graph_extraction", "progress": 0.5},
        )
        
        # 1. Fetch structured components to feed the AI
        import httpx
        from .config import get_settings
        settings = get_settings()
        
        with httpx.Client(timeout=15.0) as client:
            response = client.get(
                f"{settings.supabase_url}/rest/v1/extracted_components",
                headers={
                    "apikey": settings.supabase_service_role_key,
                    "Authorization": f"Bearer {settings.supabase_service_role_key}"
                },
                params={"paper_id": f"eq.{paper_id}", "is_active": "eq.true"}
            )
        
        if not response.is_success:
            raise RuntimeError("Gagal mengambil extracted components untuk fase 2")
            
        components = response.json()
        import json
        structured_data = json.dumps([{
            "parameter": c["parameter"],
            "value": c["ai_value"]
        } for c in components])
        
        # 2. Extract KG
        from .ai_extraction import extract_knowledge_graph_from_results
        kg_extraction = extract_knowledge_graph_from_results(structured_data)
        
        # 3. Save to DB
        repository.save_knowledge_graph(project_id=project_id, extraction=kg_extraction)
        
        self.update_state(
            state="PROGRESS",
            meta={"job_id": job_id, "stage": "knowledge_graph_complete", "progress": 1.0},
        )
        
        return {
            "job_id": job_id,
            "paper_id": paper_id,
            "status": "kg_extracted",
            "nodes": len(kg_extraction.nodes)
        }

    except Exception as exc:
        if repository is not None:
            # Not failing the main job if Phase 2 fails, just log it.
            print(f"Knowledge Graph Extraction failed for {paper_id}: {exc}")
        raise
'''

with open('app/tasks.py', 'a', encoding='utf-8') as f:
    f.write(code)

print("Appended extract_knowledge_graph_task to tasks.py")
