import sys

code = '''
class KnowledgeGraphMapRead(BaseModel):
    project_id: UUID
    project_title: str
    nodes: list[KnowledgeGraphNodeRead] = Field(default_factory=list)
    edges: list[KnowledgeGraphEdgeRead] = Field(default_factory=list)
'''

with open('app/schemas.py', 'a', encoding='utf-8') as f:
    f.write(code)

print("Appended KnowledgeGraphMapRead to schemas.py")
