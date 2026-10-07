from app.config import get_settings
from supabase import create_client, Client
import json

settings = get_settings()
supabase: Client = create_client(settings.supabase_url, settings.supabase_service_role_key)

proj_res = supabase.table('projects').select('id, title').eq('title', 'log').execute()
if proj_res.data:
    pid = proj_res.data[0]['id']
    nodes = supabase.table('knowledge_graph_nodes').select('id, node_type, gap_typology, label, saturation_status').eq('project_id', pid).execute()
    print('Nodes count:', len(nodes.data))
    for n in nodes.data:
        print(f"{n['node_type']} -> {n['label']} | Saturation: {n['saturation_status']}")
