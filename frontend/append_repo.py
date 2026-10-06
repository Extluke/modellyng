import sys

dart_code = '''
  Future<KnowledgeGraphMap> getKnowledgeGraph(String projectId) async {
    final response = await _dio.get<Map<String, dynamic>>('/api/v1/projects/$projectId/knowledge-graph');
    return KnowledgeGraphMap.fromJson(response.data!);
  }

  Future<AiResearchSynthesis> synthesizeGraphNodes(String projectId, List<String> nodeIds) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/projects/$projectId/synthesize-graph-nodes',
      data: {'node_ids': nodeIds},
    );
    return AiResearchSynthesis.fromJson(response.data!);
  }
'''

with open('lib/src/data/project_repository.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Insert before the last closing brace
insert_idx = content.rfind('}')
if insert_idx != -1:
    content = content[:insert_idx] + dart_code + "\n" + content[insert_idx:]
    with open('lib/src/data/project_repository.dart', 'w', encoding='utf-8') as f:
        f.write(content)
    print("Appended methods to project_repository.dart")
else:
    print("Failed to find closing brace")
