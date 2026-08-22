import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/research_models.dart';
import 'api_client.dart';

final paperResultRepositoryProvider = Provider<PaperResultRepository>((ref) {
  return PaperResultRepository(ref.watch(dioProvider));
});

typedef PaperResultQuery = ({String projectId, String paperId});

final paperResultProvider = FutureProvider.autoDispose
    .family<PaperResult, PaperResultQuery>((ref, query) {
      return ref
          .watch(paperResultRepositoryProvider)
          .getResult(query.projectId, query.paperId);
    });

final paperPdfProvider = FutureProvider.autoDispose
    .family<Uint8List, PaperResultQuery>((ref, query) {
      return ref
          .watch(paperResultRepositoryProvider)
          .getPdf(query.projectId, query.paperId);
    });

class ResultEvidence {
  const ResultEvidence({required this.quote, required this.pageNumber});
  final String quote;
  final int pageNumber;

  factory ResultEvidence.fromJson(Map<String, dynamic> json) => ResultEvidence(
    quote: json['quote']?.toString() ?? '',
    pageNumber: (json['page_number'] as num?)?.toInt() ?? 1,
  );
}

class PaperComponentResult {
  const PaperComponentResult({
    required this.parameter,
    required this.aiValue,
    required this.finalValue,
    required this.status,
    required this.confidence,
    required this.evidence,
  });
  final String parameter;
  final String aiValue;
  final String? finalValue;
  final VerificationStatus status;
  final double? confidence;
  final List<ResultEvidence> evidence;

  factory PaperComponentResult.fromJson(Map<String, dynamic> json) =>
      PaperComponentResult(
        parameter: json['parameter']?.toString() ?? '',
        aiValue: json['ai_value']?.toString() ?? '',
        finalValue: json['final_value']?.toString(),
        status: switch (json['status']) {
          'verified' => VerificationStatus.verified,
          'edited' => VerificationStatus.edited,
          'unsupported' => VerificationStatus.unsupported,
          'rejected' => VerificationStatus.rejected,
          _ => VerificationStatus.needsReview,
        },
        confidence: (json['confidence'] as num?)?.toDouble(),
        evidence: (json['evidence'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ResultEvidence.fromJson)
            .toList(growable: false),
      );
}

class PaperResult {
  const PaperResult({required this.paper, required this.components});
  final ProjectPaper paper;
  final List<PaperComponentResult> components;

  factory PaperResult.fromJson(Map<String, dynamic> json) => PaperResult(
    paper: ProjectPaper.fromJson(json['paper'] as Map<String, dynamic>),
    components: (json['components'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(PaperComponentResult.fromJson)
        .toList(growable: false),
  );
}

class PaperResultRepository {
  const PaperResultRepository(this._dio);
  final Dio _dio;

  Future<PaperResult> getResult(String projectId, String paperId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/projects/$projectId/papers/$paperId/result',
    );
    return PaperResult.fromJson(response.data!);
  }

  Future<Uint8List> getPdf(String projectId, String paperId) async {
    final response = await _dio.get<List<int>>(
      '/api/v1/projects/$projectId/papers/$paperId/pdf',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }
}
