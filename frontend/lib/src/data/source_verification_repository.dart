import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import 'auth_repository.dart';
import 'paper_result_repository.dart';

const metadataLabels = <String, String>{
  'title': 'Judul',
  'authors': 'Penulis',
  'publication_year': 'Tahun publikasi',
  'journal': 'Jurnal / conference',
  'doi': 'DOI',
  'publisher': 'Penerbit',
  'volume': 'Volume',
  'issue': 'Issue',
  'pages': 'Halaman publikasi',
  'publication_status': 'Status publikasi',
};

String verificationStatusLabel(String status) => switch (status) {
  'match' || 'matched' => 'Cocok',
  'mismatch' => 'Berbeda',
  'missing_local' => 'Belum ada di paper',
  'missing_source' => 'Registri tidak menyatakan',
  'incomplete' => 'Metadata belum lengkap',
  'found' => 'DOI ditemukan',
  'not_found' => 'Tidak ditemukan',
  'unavailable' => 'Layanan tidak tersedia',
  _ => 'Belum dapat diverifikasi',
};

class MetadataCheck {
  const MetadataCheck(
    this.field,
    this.localValue,
    this.sourceValue,
    this.status,
  );
  final String field;
  final String? localValue;
  final String? sourceValue;
  final String status;
  factory MetadataCheck.fromJson(Map<String, dynamic> j) => MetadataCheck(
    j['field'] as String,
    j['local_value'] as String?,
    j['source_value'] as String?,
    j['status'] as String,
  );
}

class RegistrySource {
  const RegistrySource(this.provider, this.url, this.status);
  final String provider;
  final String url;
  final String status;
  factory RegistrySource.fromJson(Map<String, dynamic> j) => RegistrySource(
    j['provider'] as String,
    j['url'] as String,
    j['status'] as String,
  );
}

class SourceReview {
  const SourceReview(this.decision, this.note, this.createdAt);
  final String decision;
  final String note;
  final DateTime createdAt;
  factory SourceReview.fromJson(Map<String, dynamic> j) => SourceReview(
    j['decision'] as String,
    j['note'] as String,
    DateTime.parse(j['created_at'] as String),
  );
}

class SourceVerification {
  const SourceVerification({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.doi,
    required this.checks,
    required this.sources,
    required this.warnings,
    required this.reviews,
  });
  final String id;
  final String status;
  final DateTime createdAt;
  final String? doi;
  final List<MetadataCheck> checks;
  final List<RegistrySource> sources;
  final List<String> warnings;
  final List<SourceReview> reviews;
  factory SourceVerification.fromJson(Map<String, dynamic> j) {
    final r = j['report'] as Map<String, dynamic>;
    return SourceVerification(
      id: j['id'] as String,
      status: r['status'] as String,
      createdAt: DateTime.parse(j['created_at'] as String),
      doi: r['requested_doi'] as String?,
      checks: (r['checks'] as List)
          .cast<Map<String, dynamic>>()
          .map(MetadataCheck.fromJson)
          .toList(),
      sources: (r['sources'] as List)
          .cast<Map<String, dynamic>>()
          .map(RegistrySource.fromJson)
          .toList(),
      warnings: (r['warnings'] as List).cast<String>(),
      reviews:
          (j['reviews'] as List? ?? [])
              .cast<Map<String, dynamic>>()
              .map(SourceReview.fromJson)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    );
  }
}

final sourceVerificationRepositoryProvider = Provider(
  (ref) => SourceVerificationRepository(ref.watch(dioProvider)),
);
final sourceVerificationsProvider = FutureProvider.autoDispose
    .family<List<SourceVerification>, PaperResultQuery>((ref, query) async {
      final ownerId = ref.watch(authSessionProvider).value?.user.id;
      if (ownerId == null) return const [];
      final reports = await ref
          .watch(sourceVerificationRepositoryProvider)
          .list(query);
      if (!ref.mounted) return const [];
      if (ref.read(authRepositoryProvider).currentUser?.id != ownerId)
        return const [];
      return reports;
    }, retry: (count, error) => null);

class SourceVerificationRepository {
  const SourceVerificationRepository(this.dio);
  final Dio dio;
  String _path(PaperResultQuery q) =>
      '/api/v1/projects/${q.projectId}/papers/${q.paperId}/source-verifications';
  Future<List<SourceVerification>> list(PaperResultQuery q) async {
    final response = await dio.get<List<dynamic>>(_path(q));
    return response.data!
        .cast<Map<String, dynamic>>()
        .map(SourceVerification.fromJson)
        .toList();
  }

  Future<void> verify(PaperResultQuery q, String doi) async {
    await dio.post<Map<String, dynamic>>(
      _path(q),
      data: {'doi': doi.trim().isEmpty ? null : doi.trim()},
    );
  }

  Future<void> review(
    PaperResultQuery q,
    String id,
    String decision,
    String note,
  ) async {
    await dio.post<Map<String, dynamic>>(
      '${_path(q)}/$id/reviews',
      data: {'decision': decision, 'note': note.trim()},
    );
  }
}
