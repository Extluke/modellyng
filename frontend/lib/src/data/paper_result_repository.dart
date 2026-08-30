import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/research_models.dart';
import 'api_client.dart';

final paperResultRepositoryProvider = Provider<PaperResultRepository>((ref) {
  return PaperResultRepository(ref.watch(dioProvider));
});

typedef PaperResultQuery = ({String projectId, String paperId});
typedef EvidencePreviewQuery = ({
  String projectId,
  String paperId,
  String blockId,
});

final paperResultProvider = FutureProvider.autoDispose
    .family<PaperResult, PaperResultQuery>((ref, query) {
      return ref
          .watch(paperResultRepositoryProvider)
          .getResult(query.projectId, query.paperId);
    });

final paperPdfProvider = FutureProvider.autoDispose
    .family<Uint8List, PaperResultQuery>((ref, query) {
      // Evidence links are commonly opened repeatedly during one discussion.
      // Retain private bytes briefly in memory; ownership is still enforced by
      // the authenticated API request that initially fills this cache.
      final cacheLink = ref.keepAlive();
      final expiry = Timer(const Duration(minutes: 10), cacheLink.close);
      ref.onDispose(expiry.cancel);
      return ref
          .watch(paperResultRepositoryProvider)
          .getPdf(query.projectId, query.paperId);
    });

final evidencePreviewProvider = FutureProvider.autoDispose
    .family<Uint8List, EvidencePreviewQuery>((ref, query) {
      final cacheLink = ref.keepAlive();
      final expiry = Timer(const Duration(minutes: 10), cacheLink.close);
      ref.onDispose(expiry.cancel);
      return ref
          .watch(paperResultRepositoryProvider)
          .getEvidencePreview(query.projectId, query.paperId, query.blockId);
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

class ResearchQuestionTableRow {
  const ResearchQuestionTableRow({
    required this.number,
    required this.question,
    required this.relatedObject,
    required this.discussionDirection,
    required this.evidencePage,
    required this.evidenceQuote,
  });

  final int number;
  final String question;
  final String relatedObject;
  final String discussionDirection;
  final int? evidencePage;
  final String? evidenceQuote;

  factory ResearchQuestionTableRow.fromJson(Map<String, dynamic> json) =>
      ResearchQuestionTableRow(
        number: (json['number'] as num?)?.toInt() ?? 1,
        question: json['question']?.toString() ?? '',
        relatedObject: json['related_object']?.toString() ?? '',
        discussionDirection: json['discussion_direction']?.toString() ?? '',
        evidencePage: (json['evidence_page'] as num?)?.toInt(),
        evidenceQuote: json['evidence_quote']?.toString(),
      );
}

class MethodologyTableRow {
  const MethodologyTableRow({
    required this.content,
    required this.form,
    required this.mainActivity,
    required this.activityDirection,
    required this.finalGoal,
  });

  final String content;
  final String form;
  final String mainActivity;
  final String activityDirection;
  final String finalGoal;

  factory MethodologyTableRow.fromJson(Map<String, dynamic> json) =>
      MethodologyTableRow(
        content: json['content']?.toString() ?? '',
        form: json['form']?.toString() ?? '',
        mainActivity: json['main_activity']?.toString() ?? '',
        activityDirection: json['activity_direction']?.toString() ?? '',
        finalGoal: json['final_goal']?.toString() ?? '',
      );
}

class StructuredPaperTables {
  const StructuredPaperTables({
    required this.researchQuestions,
    required this.methodology,
  });

  final List<ResearchQuestionTableRow> researchQuestions;
  final List<MethodologyTableRow> methodology;

  factory StructuredPaperTables.fromJson(Map<String, dynamic>? json) {
    final value = json ?? const <String, dynamic>{};
    return StructuredPaperTables(
      researchQuestions:
          (value['research_questions'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>()
              .map(ResearchQuestionTableRow.fromJson)
              .toList(growable: false),
      methodology: (value['methodology'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(MethodologyTableRow.fromJson)
          .toList(growable: false),
    );
  }
}

class StructuredPdfDownload {
  const StructuredPdfDownload({required this.bytes, required this.filename});
  final Uint8List bytes;
  final String filename;
}

class PaperResult {
  const PaperResult({
    required this.paper,
    required this.components,
    required this.structuredTables,
  });
  final ProjectPaper paper;
  final List<PaperComponentResult> components;
  final StructuredPaperTables structuredTables;

  factory PaperResult.fromJson(Map<String, dynamic> json) => PaperResult(
    paper: ProjectPaper.fromJson(json['paper'] as Map<String, dynamic>),
    components: (json['components'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(PaperComponentResult.fromJson)
        .toList(growable: false),
    structuredTables: StructuredPaperTables.fromJson(
      json['structured_tables'] as Map<String, dynamic>?,
    ),
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

  Future<Uint8List> getEvidencePreview(
    String projectId,
    String paperId,
    String blockId,
  ) async {
    final response = await _dio.get<List<int>>(
      '/api/v1/projects/$projectId/papers/$paperId/evidence/$blockId/preview.png',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }

  Future<StructuredPdfDownload> downloadStructuredTables(
    String projectId,
    String paperId,
  ) async {
    final response = await _dio.get<List<int>>(
      '/api/v1/projects/$projectId/papers/$paperId/structured-tables.pdf',
      options: Options(responseType: ResponseType.bytes),
    );
    final disposition = response.headers.value('content-disposition') ?? '';
    final filename = RegExp(
      r'filename="?([^";]+)',
    ).firstMatch(disposition)?.group(1);
    return StructuredPdfDownload(
      bytes: Uint8List.fromList(response.data ?? const []),
      filename: filename ?? 'modellyng-structured-paper-$paperId.pdf',
    );
  }
}
