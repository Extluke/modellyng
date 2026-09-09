import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'paper_result_repository.dart';

const comparisonAspects = [
  'concept',
  'variables',
  'data_object',
  'method',
  'research_problem',
];
String aspectLabel(String aspect) => switch (aspect) {
  'concept' => 'Konsep utama',
  'variables' => 'Variabel',
  'data_object' => 'Data / objek penelitian',
  'method' => 'Metode',
  'research_problem' => 'Permasalahan',
  _ => aspect,
};
String decisionLabel(String decision) => switch (decision) {
  'yes' => 'Yes · Sesuai',
  'no' => 'No · Berbeda',
  'insufficient' => 'Evidence belum cukup',
  _ => 'Tidak dilanjutkan',
};
String outcomeLabel(String? outcome) => switch (outcome) {
  'candidate_gap' => 'Kandidat research gap',
  'unrelated' => 'Konsep tidak cukup berhubungan',
  'insufficient_evidence' => 'Perlu evidence tambahan',
  'no_gap' => 'Tidak ada perbedaan pada lima aspek',
  _ => 'Menunggu analisis',
};

class PairEvidence {
  PairEvidence.fromJson(Map<String, dynamic> json)
    : paperId = json['paper_id'] as String,
      componentId = json['component_id'] as String,
      ref = json['ref'] as String,
      source = ResultEvidence.fromJson(json);
  final String paperId, componentId, ref;
  final ResultEvidence source;
}

class PairStep {
  PairStep.fromJson(Map<String, dynamic> json)
    : aspect = json['aspect'] as String,
      decision = json['decision'] as String,
      reason = json['reason'] as String,
      leftEvidence = _evidence(json['left_evidence']),
      rightEvidence = _evidence(json['right_evidence']);
  final String aspect, decision, reason;
  final List<PairEvidence> leftEvidence, rightEvidence;
  static List<PairEvidence> _evidence(dynamic value) => (value as List? ?? [])
      .map((e) => PairEvidence.fromJson(e as Map<String, dynamic>))
      .toList();
}

class PairReview {
  PairReview.fromJson(Map<String, dynamic> json)
    : decision = json['decision'] as String,
      note = json['note'] as String,
      createdAt = DateTime.parse(json['created_at'] as String);
  final String decision, note;
  final DateTime createdAt;
}

class PaperPair {
  PaperPair.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      leftId = json['left_paper_id'] as String,
      rightId = json['right_paper_id'] as String,
      leftTitle = (json['left_source'] as Map)['title'] as String,
      rightTitle = (json['right_source'] as Map)['title'] as String,
      status = json['status'] as String,
      error = json['error_message'] as String?,
      outcome = (json['result'] as Map?)?['outcome'] as String?,
      stopAspect = (json['result'] as Map?)?['stop_aspect'] as String?,
      candidate =
          (json['result'] as Map?)?['candidate'] as Map<String, dynamic>?,
      steps = ((json['result'] as Map?)?['steps'] as List? ?? [])
          .map((e) => PairStep.fromJson(e as Map<String, dynamic>))
          .toList(),
      reviews = (json['reviews'] as List? ?? [])
          .map((e) => PairReview.fromJson(e as Map<String, dynamic>))
          .toList();
  final String id, leftId, rightId, leftTitle, rightTitle, status;
  final String? error, outcome, stopAspect;
  final Map<String, dynamic>? candidate;
  final List<PairStep> steps;
  final List<PairReview> reviews;
  String get label => '$leftTitle ↔ $rightTitle';
  bool get pending => status == 'queued' || status == 'processing';
  String get statusLabel => switch (status) {
    'processing' => 'Sedang dianalisis',
    'queued' => 'Dalam antrean',
    'failed' => 'Analisis gagal',
    _ => outcomeLabel(outcome),
  };
}

class PairComparisonOverview {
  PairComparisonOverview.fromJson(Map<String, dynamic> json)
    : readyPapers = json['ready_papers'] as int,
      totalPapers = json['total_papers'] as int,
      expectedPairs = json['expected_pairs'] as int,
      warning = json['dispatch_warning'] as String?,
      pairs = (json['pairs'] as List)
          .map((e) => PaperPair.fromJson(e as Map<String, dynamic>))
          .toList();
  final int readyPapers, totalPapers, expectedPairs;
  final String? warning;
  final List<PaperPair> pairs;
  int get completed => pairs.where((p) => p.status == 'completed').length;
  int get candidates => pairs.where((p) => p.outcome == 'candidate_gap').length;
  bool get pending => pairs.any((p) => p.pending);
}

final paperComparisonRepositoryProvider = Provider<PaperComparisonRepository>(
  (ref) => PaperComparisonRepository(ref.watch(dioProvider)),
);
final paperComparisonsProvider = FutureProvider.autoDispose
    .family<PairComparisonOverview, String>((ref, projectId) async {
      Timer? refresh;
      ref.onDispose(() => refresh?.cancel());
      final result = await ref
          .watch(paperComparisonRepositoryProvider)
          .get(projectId);
      if (ref.mounted && result.pending) {
        refresh = Timer(const Duration(seconds: 5), ref.invalidateSelf);
      }
      return result;
    });

class PaperComparisonRepository {
  const PaperComparisonRepository(this._dio);
  final Dio _dio;
  Future<PairComparisonOverview> get(String projectId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/projects/$projectId/comparisons',
    );
    return PairComparisonOverview.fromJson(response.data!);
  }

  Future<PairComparisonOverview> start(String projectId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/projects/$projectId/comparisons',
    );
    return PairComparisonOverview.fromJson(response.data!);
  }

  Future<void> review(
    String projectId,
    String pairId,
    String decision,
    String note,
  ) async {
    await _dio.post<Map<String, dynamic>>(
      '/api/v1/projects/$projectId/comparisons/$pairId/reviews',
      data: {'decision': decision, 'note': note},
    );
  }
}
