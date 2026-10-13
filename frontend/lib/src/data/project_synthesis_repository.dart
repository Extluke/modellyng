import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project_synthesis.dart';
import 'api_client.dart';

final projectSynthesisRepositoryProvider = Provider<ProjectSynthesisRepository>(
  (ref) => ProjectSynthesisRepository(ref.watch(dioProvider)),
);

/// Sintesis tersimpan (null bila belum pernah dibuat). Tidak memanggil AI.
/// Retry otomatis dimatikan; pengguna memakai tombol "Coba lagi".
final projectSynthesisProvider = FutureProvider.autoDispose
    .family<ProjectSynthesis?, String>(
      (ref, projectId) =>
          ref.watch(projectSynthesisRepositoryProvider).getSynthesis(projectId),
      retry: (_, _) => null,
    );

class ProjectSynthesisRepository {
  const ProjectSynthesisRepository(this._dio);

  final Dio _dio;

  Future<ProjectSynthesis?> getSynthesis(String projectId) async {
    final response = await _dio.get<Map<String, dynamic>?>(
      '/api/v1/projects/$projectId/synthesis',
    );
    final data = response.data;
    return data == null ? null : ProjectSynthesis.fromJson(data);
  }

  /// Menyusun sintesis untuk semua paper terreview. Hasil tersimpan dipakai
  /// ulang bila datanya belum berubah, kecuali [forceRegenerate].
  Future<ProjectSynthesis> generateSynthesis(
    String projectId, {
    bool forceRegenerate = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/projects/$projectId/synthesis',
      data: {'force_regenerate': forceRegenerate},
      // Gemini bisa butuh hingga satu menit lebih untuk banyak paper.
      options: Options(receiveTimeout: const Duration(minutes: 4)),
    );
    return ProjectSynthesis.fromJson(response.data!);
  }
}
