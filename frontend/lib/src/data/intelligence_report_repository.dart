import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

final intelligenceReportRepositoryProvider =
    Provider<IntelligenceReportRepository>((ref) {
      return IntelligenceReportRepository(ref.watch(dioProvider));
    });

final intelligenceReportProvider = FutureProvider.autoDispose
    .family<IntelligenceReport, String>((ref, key) {
      final parts = key.split('|');
      return ref
          .watch(intelligenceReportRepositoryProvider)
          .getReport(
            parts.first,
            citationStyle: parts.length > 1 ? parts[1] : 'apa7',
          );
    });

class IntelligenceReport {
  const IntelligenceReport({
    required this.projectTitle,
    required this.citationStyle,
    required this.references,
    required this.papers,
    required this.relationshipCount,
    required this.clusters,
    required this.unsupportedClaims,
    required this.synthesis,
    required this.candidateGapCount,
    required this.comparisonCount,
    required this.candidateComparisonCount,
    required this.acceptedComparisonCount,
  });

  final String projectTitle;
  final String citationStyle;
  final List<ReferenceEntry> references;
  final List<CompressedPaper> papers;
  final int relationshipCount;
  final List<ResearchCluster> clusters;
  final List<UnsupportedClaim> unsupportedClaims;
  final String synthesis;
  final int candidateGapCount;
  final int comparisonCount;
  final int candidateComparisonCount;
  final int acceptedComparisonCount;

  factory IntelligenceReport.fromJson(Map<String, dynamic> json) =>
      IntelligenceReport(
        projectTitle: json['project_title']?.toString() ?? 'Proyek',
        citationStyle: json['citation_style']?.toString() ?? 'apa7',
        references: (json['references'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ReferenceEntry.fromJson)
            .toList(growable: false),
        papers: (json['papers'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CompressedPaper.fromJson)
            .toList(growable: false),
        relationshipCount: (json['relationship_count'] as num?)?.toInt() ?? 0,
        clusters: (json['clusters'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ResearchCluster.fromJson)
            .toList(growable: false),
        unsupportedClaims:
            (json['unsupported_claims'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(UnsupportedClaim.fromJson)
                .toList(growable: false),
        synthesis: json['synthesis']?.toString() ?? '',
        candidateGapCount: (json['candidate_gap_count'] as num?)?.toInt() ?? 0,
        comparisonCount: (json['comparison_count'] as num?)?.toInt() ?? 0,
        candidateComparisonCount:
            (json['candidate_comparison_count'] as num?)?.toInt() ?? 0,
        acceptedComparisonCount:
            (json['accepted_comparison_count'] as num?)?.toInt() ?? 0,
      );
}

class CompressedPaper {
  const CompressedPaper({required this.title, required this.structure});
  final String title;
  final Map<String, dynamic> structure;
  factory CompressedPaper.fromJson(Map<String, dynamic> json) =>
      CompressedPaper(
        title: json['title']?.toString() ?? 'Paper',
        structure:
            (json['research_structure'] as Map<dynamic, dynamic>? ?? const {})
                .map((key, value) => MapEntry(key.toString(), value)),
      );
}

class ReferenceEntry {
  const ReferenceEntry({
    required this.title,
    required this.citation,
    required this.inTextCitation,
  });
  final String title;
  final String citation;
  final String inTextCitation;
  factory ReferenceEntry.fromJson(Map<String, dynamic> json) => ReferenceEntry(
    title: json['title']?.toString() ?? 'Paper',
    citation: json['citation']?.toString() ?? '',
    inTextCitation: json['in_text_citation']?.toString() ?? '',
  );
}

class ResearchCluster {
  const ResearchCluster({
    required this.kind,
    required this.label,
    required this.sharedTerms,
  });
  final String kind;
  final String label;
  final List<String> sharedTerms;
  factory ResearchCluster.fromJson(Map<String, dynamic> json) =>
      ResearchCluster(
        kind: json['kind']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        sharedTerms: (json['shared_terms'] as List<dynamic>? ?? const [])
            .map((value) => value.toString())
            .toList(growable: false),
      );
}

class UnsupportedClaim {
  const UnsupportedClaim({
    required this.parameter,
    required this.claim,
    required this.reason,
  });
  final String parameter;
  final String claim;
  final String reason;
  factory UnsupportedClaim.fromJson(Map<String, dynamic> json) =>
      UnsupportedClaim(
        parameter: json['parameter']?.toString() ?? '',
        claim: json['claim']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
      );
}

class IntelligenceReportRepository {
  const IntelligenceReportRepository(this._dio);
  final Dio _dio;

  Future<IntelligenceReport> getReport(
    String projectId, {
    String citationStyle = 'apa7',
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/projects/$projectId/intelligence-report',
      queryParameters: {'citation_style': citationStyle},
    );
    return IntelligenceReport.fromJson(response.data!);
  }
}
