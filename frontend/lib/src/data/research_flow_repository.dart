import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/research_flow.dart';
import 'api_client.dart';

final researchFlowRepositoryProvider = Provider<ResearchFlowRepository>((ref) {
  return ResearchFlowRepository(ref.watch(dioProvider));
});

/// Peta alur riset per project. Retry otomatis Riverpod dimatikan karena
/// setiap percobaan ulang bisa memicu panggilan Gemini; pengguna memakai
/// tombol "Coba lagi" bila gagal.
final researchFlowProvider = FutureProvider.autoDispose
    .family<ResearchFlowMap, String>(
      (ref, projectId) =>
          ref.watch(researchFlowRepositoryProvider).getFlow(projectId),
      retry: (_, _) => null,
    );

class ResearchFlowRepository {
  const ResearchFlowRepository(this._dio);

  final Dio _dio;

  Future<ResearchFlowMap> getFlow(String projectId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/projects/$projectId/research-flow',
      // Penyusunan pertama memanggil Gemini dan bisa lebih dari 45 detik.
      options: Options(receiveTimeout: const Duration(seconds: 120)),
    );
    return ResearchFlowMap.fromJson(response.data!);
  }
}
