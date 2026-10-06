import sys

code = '''
@api.get(
    "/projects/{project_id}/knowledge-graph",
    response_model=KnowledgeGraphMapRead,
    tags=["projects"],
)
async def get_knowledge_graph_map(
    project_id: UUID, current_user: CurrentUser
) -> KnowledgeGraphMapRead:
    return await project_repository.get_knowledge_graph(current_user, project_id)
'''

with open('app/main.py', 'r', encoding='utf-8') as f:
    content = f.read()

# Add KnowledgeGraphMapRead to imports from schemas
content = content.replace(
    "ResearchGapMapRead,",
    "ResearchGapMapRead,\n    KnowledgeGraphMapRead,"
)

# Insert the endpoint before the intelligence-report endpoint
target = '''@api.get(
    "/projects/{project_id}/intelligence-report",'''

content = content.replace(target, code + "\n" + target)

with open('app/main.py', 'w', encoding='utf-8') as f:
    f.write(content)

print("Added get_knowledge_graph_map to main.py")
