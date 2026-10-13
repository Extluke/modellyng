import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/research_models.dart';
import 'api_client.dart';

final comparativeMatrixRepositoryProvider =
    Provider<ComparativeMatrixRepository>((ref) {
      return ComparativeMatrixRepository(ref.watch(dioProvider));
    });

final comparativeMatrixProvider = FutureProvider.autoDispose
    .family<ComparativeMatrix, String>((ref, projectId) {
      return ref
          .watch(comparativeMatrixRepositoryProvider)
          .getMatrix(projectId);
    });

class MatrixPaper {
  const MatrixPaper({
    required this.id,
    required this.title,
    required this.originalFilename,
  });
  final String id;
  final String title;
  final String originalFilename;
  factory MatrixPaper.fromJson(Map<String, dynamic> json) => MatrixPaper(
    id: json['id'].toString(),
    title: json['title']?.toString() ?? 'Paper',
    originalFilename: json['original_filename']?.toString() ?? 'paper.pdf',
  );
}

class MatrixEvidence {
  const MatrixEvidence({required this.quote, required this.pageNumber});
  final String quote;
  final int pageNumber;
  factory MatrixEvidence.fromJson(Map<String, dynamic> json) => MatrixEvidence(
    quote: json['quote']?.toString() ?? '',
    pageNumber: (json['page_number'] as num?)?.toInt() ?? 1,
  );
}

class MatrixCell {
  const MatrixCell({
    required this.paperId,
    required this.aiValue,
    required this.finalValue,
    required this.status,
    required this.confidence,
    required this.evidence,
  });
  final String paperId;
  final String aiValue;
  final String? finalValue;
  final VerificationStatus status;
  final double? confidence;
  final List<MatrixEvidence> evidence;
  String get displayValue =>
      finalValue?.trim().isNotEmpty == true ? finalValue! : aiValue;

  factory MatrixCell.fromJson(Map<String, dynamic> json) => MatrixCell(
    paperId: json['paper_id'].toString(),
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
        .map(MatrixEvidence.fromJson)
        .toList(growable: false),
  );
}

class MatrixRow {
  const MatrixRow({required this.parameter, required this.cells});
  final String parameter;
  final List<MatrixCell> cells;
  MatrixCell? cellFor(String paperId) {
    for (final cell in cells) {
      if (cell.paperId == paperId) return cell;
    }
    return null;
  }

  factory MatrixRow.fromJson(Map<String, dynamic> json) => MatrixRow(
    parameter: json['parameter']?.toString() ?? '',
    cells: (json['cells'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(MatrixCell.fromJson)
        .toList(growable: false),
  );
}

class ComparativeMatrix {
  const ComparativeMatrix({
    required this.projectId,
    required this.projectTitle,
    required this.papers,
    required this.rows,
  });
  final String projectId;
  final String projectTitle;
  final List<MatrixPaper> papers;
  final List<MatrixRow> rows;
  factory ComparativeMatrix.fromJson(Map<String, dynamic> json) =>
      ComparativeMatrix(
        projectId: json['project_id'].toString(),
        projectTitle: json['project_title']?.toString() ?? 'Proyek',
        papers: (json['papers'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(MatrixPaper.fromJson)
            .toList(growable: false),
        rows: (json['rows'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(MatrixRow.fromJson)
            .toList(growable: false),
      );
}

class ComparativeMatrixRepository {
  const ComparativeMatrixRepository(this._dio);
  final Dio _dio;
  Future<ComparativeMatrix> getMatrix(String projectId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/projects/$projectId/comparative-matrix',
    );
    return ComparativeMatrix.fromJson(response.data!);
  }
}
