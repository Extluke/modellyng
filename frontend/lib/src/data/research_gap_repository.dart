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

final researchGapDecisionsProvider = FutureProvider.autoDispose
    .family<List<ResearchGapDecision>, String>((ref, projectId) {
      return ref.watch(researchGapRepositoryProvider).getDecisions(projectId);
    });

enum GapDecision { accepted, rejected }

class ResearchGapDecision {
  const ResearchGapDecision({
    required this.id,
    required this.projectId,
    required this.paperId,
    required this.parameter,
    required this.decision,
    required this.note,
  });

  final String id;
  final String projectId;
  final String paperId;
  final String parameter;
  final GapDecision decision;
  final String? note;

  String get candidateKey => '$paperId:$parameter';

  factory ResearchGapDecision.fromJson(Map<String, dynamic> json) =>
      ResearchGapDecision(
        id: json['id'].toString(),
        projectId: json['project_id'].toString(),
        paperId: json['paper_id'].toString(),
        parameter: json['parameter']?.toString() ?? '',
        decision: json['decision'] == 'accepted'
            ? GapDecision.accepted
            : GapDecision.rejected,
        note: json['note']?.toString(),
      );
}

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

  Future<List<ResearchGapDecision>> getDecisions(String projectId) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/v1/projects/$projectId/research-gap-decisions',
    );
    return (response.data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ResearchGapDecision.fromJson)
        .toList(growable: false);
  }

  Future<ResearchGapDecision> saveDecision({
    required String projectId,
    required String paperId,
    required String parameter,
    required GapDecision decision,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/v1/projects/$projectId/research-gaps/$paperId/$parameter/decision',
      data: {'decision': decision.name},
    );
    return ResearchGapDecision.fromJson(response.data!);
  }
}
