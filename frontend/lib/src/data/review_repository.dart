import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'auth_repository.dart';

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  return ReviewRepository(ref.watch(dioProvider));
});

final reviewQueueProvider = FutureProvider.autoDispose
    .family<List<ReviewQueueItem>, String>((ref, userId) async {
      final session = ref.watch(authSessionProvider).value;
      if (session?.user.id != userId) return const [];
      final items = await ref.watch(reviewRepositoryProvider).listQueue();
      if (ref.read(authRepositoryProvider).currentUser?.id != userId) {
        return const [];
      }
      return items;
    });

enum ReviewDecision { accept, edit, reject }

class ReviewEvidence {
  const ReviewEvidence({required this.quote, required this.pageNumber});

  final String quote;
  final int pageNumber;

  factory ReviewEvidence.fromJson(Map<String, dynamic> json) {
    return ReviewEvidence(
      quote: json['quote']?.toString() ?? '',
      pageNumber: (json['page_number'] as num?)?.toInt() ?? 1,
    );
  }
}

class ReviewQueueItem {
  const ReviewQueueItem({
    required this.componentId,
    required this.paperId,
    required this.projectId,
    required this.projectTitle,
    required this.paperTitle,
    required this.originalFilename,
    required this.parameter,
    required this.aiValue,
    required this.confidence,
    required this.evidence,
    required this.modelName,
  });

  final String componentId;
  final String paperId;
  final String projectId;
  final String projectTitle;
  final String paperTitle;
  final String originalFilename;
  final String parameter;
  final String aiValue;
  final double? confidence;
  final List<ReviewEvidence> evidence;
  final String modelName;

  factory ReviewQueueItem.fromJson(Map<String, dynamic> json) {
    return ReviewQueueItem(
      componentId: json['component_id'].toString(),
      paperId: json['paper_id'].toString(),
      projectId: json['project_id'].toString(),
      projectTitle: json['project_title']?.toString() ?? 'Proyek',
      paperTitle: json['paper_title']?.toString() ?? 'Paper',
      originalFilename: json['original_filename']?.toString() ?? 'paper.pdf',
      parameter: json['parameter']?.toString() ?? '',
      aiValue: json['ai_value']?.toString() ?? '',
      confidence: (json['confidence'] as num?)?.toDouble(),
      evidence: (json['evidence'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ReviewEvidence.fromJson)
          .toList(growable: false),
      modelName: json['model_name']?.toString() ?? 'Gemini',
    );
  }

  String get parameterLabel => switch (parameter) {
    'research_problem' => 'Masalah penelitian',
    'research_objective' => 'Tujuan penelitian',
    'research_question' => 'Pertanyaan penelitian',
    'methodology' => 'Metodologi',
    'dataset_sample' => 'Dataset atau sampel',
    'variables_concepts' => 'Variabel dan konsep',
    'results_findings' => 'Hasil dan temuan',
    'contribution' => 'Kontribusi',
    'limitations' => 'Keterbatasan',
    'future_work' => 'Penelitian berikutnya',
    'key_claims' => 'Klaim utama',
    _ => parameter,
  };
}

class ReviewRepository {
  const ReviewRepository(this._dio);

  final Dio _dio;

  Future<List<ReviewQueueItem>> listQueue() async {
    final response = await _dio.get<List<dynamic>>('/api/v1/reviews');
    return (response.data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ReviewQueueItem.fromJson)
        .toList(growable: false);
  }

  Future<void> submitDecision({
    required String componentId,
    required ReviewDecision decision,
    String? correctedValue,
    String? note,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/api/v1/reviews/$componentId',
      data: {
        'action': decision.name,
        if (correctedValue != null) 'corrected_value': correctedValue,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
  }
}
