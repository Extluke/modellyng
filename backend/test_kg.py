import asyncio
import uuid
import httpx
import json
from app.config import get_settings
from app.processing_repository import PdfProcessingRepository
from app.ai_extraction import extract_knowledge_graph_from_results

settings = get_settings()

repository = PdfProcessingRepository()

papers = [
    uuid.UUID('e76ffa50-4aa9-4c19-aa33-ea2647b57da4'), 
    uuid.UUID('a7482b5f-90b7-4f88-97a8-36ba7b77ea8d'), 
    uuid.UUID('afc8ec51-2fa9-4a47-88f4-3eb113b0caca')
]

for paper_id in papers:
    paper = repository.get_paper(paper_id)
    project_id = uuid.UUID(str(paper['project_id']))

    with httpx.Client(timeout=15.0) as client:
        response = client.get(
            f'{settings.supabase_url}/rest/v1/extracted_components',
            headers={
                'apikey': settings.supabase_service_role_key,
                'Authorization': f'Bearer {settings.supabase_service_role_key}'
            },
            params={'paper_id': f'eq.{paper_id}', 'is_active': 'eq.true'}
        )
    components = response.json()

    with httpx.Client(timeout=15.0) as client:
        gap_response = client.get(
            f'{settings.supabase_url}/rest/v1/research_gaps',
            headers={
                'apikey': settings.supabase_service_role_key,
                'Authorization': f'Bearer {settings.supabase_service_role_key}'
            },
            params={'paper_id': f'eq.{paper_id}', 'is_active': 'eq.true'}
        )

    if gap_response.is_success:
        for gap in gap_response.json():
            components.append({
                'parameter': 'research_gap',
                'ai_value': f"Tipe: {gap.get('gap_type')}, Pernyataan: {gap.get('gap_statement')}"
            })

    structured_data = json.dumps([{
        'parameter': c['parameter'],
        'value': c['ai_value']
    } for c in components])

    try:
        print(f'Extracting KG for {paper_id}...')
        kg_extraction = extract_knowledge_graph_from_results(structured_data)
        print(f'Nodes extracted: {len(kg_extraction.nodes)}')
        for n in kg_extraction.nodes:
            if n.node_type == 'gap':
                print('  FOUND GAP NODE:', n.gap_typology, '->', n.label)
        print('Saving to DB...')
        repository.save_knowledge_graph(project_id=project_id, extraction=kg_extraction)
        print(f'Success for {paper_id}!')
    except Exception as e:
        import traceback
        traceback.print_exc()
