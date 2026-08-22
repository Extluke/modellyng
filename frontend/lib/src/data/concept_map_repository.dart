import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

final conceptMapRepositoryProvider = Provider<ConceptMapRepository>((ref) {
  return ConceptMapRepository(ref.watch(dioProvider));
});

final conceptMapProvider = FutureProvider.autoDispose
    .family<ConceptEvidenceMap, String>((ref, projectId) {
      return ref.watch(conceptMapRepositoryProvider).getMap(projectId);
    });

class ConceptMapNode {
  const ConceptMapNode({
    required this.id,
    required this.kind,
    required this.label,
    required this.detail,
    required this.paperId,
    required this.parameter,
    required this.pageNumber,
  });
  final String id;
  final String kind;
  final String label;
  final String detail;
  final String paperId;
  final String? parameter;
  final int? pageNumber;
  factory ConceptMapNode.fromJson(Map<String, dynamic> json) => ConceptMapNode(
    id: json['id'].toString(),
    kind: json['kind']?.toString() ?? '',
    label: json['label']?.toString() ?? '',
    detail: json['detail']?.toString() ?? '',
    paperId: json['paper_id'].toString(),
    parameter: json['parameter']?.toString(),
    pageNumber: (json['page_number'] as num?)?.toInt(),
  );
}

class ConceptMapEdge {
  const ConceptMapEdge({
    required this.source,
    required this.target,
    required this.relation,
  });
  final String source;
  final String target;
  final String relation;
  factory ConceptMapEdge.fromJson(Map<String, dynamic> json) => ConceptMapEdge(
    source: json['source'].toString(),
    target: json['target'].toString(),
    relation: json['relation']?.toString() ?? '',
  );
}

class ConceptEvidenceMap {
  const ConceptEvidenceMap({
    required this.projectId,
    required this.projectTitle,
    required this.nodes,
    required this.edges,
  });
  final String projectId;
  final String projectTitle;
  final List<ConceptMapNode> nodes;
  final List<ConceptMapEdge> edges;
  factory ConceptEvidenceMap.fromJson(Map<String, dynamic> json) =>
      ConceptEvidenceMap(
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
      );
}

class ConceptMapRepository {
  const ConceptMapRepository(this._dio);
  final Dio _dio;
  Future<ConceptEvidenceMap> getMap(String projectId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/projects/$projectId/concept-evidence-map',
    );
    return ConceptEvidenceMap.fromJson(response.data!);
  }
}
