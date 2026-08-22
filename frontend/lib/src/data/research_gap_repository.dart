import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'concept_map_repository.dart';

final researchGapRepositoryProvider = Provider<ResearchGapRepository>((ref) {
  return ResearchGapRepository(ref.watch(dioProvider));
});

final researchGapMapProvider = FutureProvider.autoDispose
    .family<ResearchGapMap, String>((ref, projectId) {
      return ref.watch(researchGapRepositoryProvider).getMap(projectId);
    });

class ResearchGapMap {
  const ResearchGapMap({
    required this.projectId,
    required this.projectTitle,
    required this.nodes,
    required this.edges,
    required this.candidateCount,
  });

  final String projectId;
  final String projectTitle;
  final List<ConceptMapNode> nodes;
  final List<ConceptMapEdge> edges;
  final int candidateCount;

  factory ResearchGapMap.fromJson(Map<String, dynamic> json) => ResearchGapMap(
    projectId: json['project_id'].toString(),
    projectTitle: json['project_title']?.toString() ?? 'Proyek',
    nodes: (json['nodes'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ConceptMapNode.fromJson)
        .toList(growable: false),
    edges: (json['edges'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ConceptMapEdge.fromJson)
        .toList(growable: false),
    candidateCount: (json['candidate_count'] as num?)?.toInt() ?? 0,
  );
}

class ResearchGapRepository {
  const ResearchGapRepository(this._dio);
  final Dio _dio;

  Future<ResearchGapMap> getMap(String projectId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/projects/$projectId/research-gap-map',
    );
    return ResearchGapMap.fromJson(response.data!);
  }
}
