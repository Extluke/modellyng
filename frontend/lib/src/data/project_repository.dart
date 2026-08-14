import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/research_models.dart';
import 'api_client.dart';
import 'auth_repository.dart';

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository(ref.watch(dioProvider));
});

final projectsProvider = FutureProvider.autoDispose
    .family<List<ResearchProject>, String>((ref, userId) async {
      final session = ref.watch(authSessionProvider).value;
      if (session?.user.id != userId) return const [];

      final projects = await ref
          .watch(projectRepositoryProvider)
          .listProjects();
      if (ref.read(authRepositoryProvider).currentUser?.id != userId) {
        return const [];
      }
      return projects;
    });

class ProjectRepository {
  const ProjectRepository(this._dio);

  final Dio _dio;

  Future<List<ResearchProject>> listProjects() async {
    final response = await _dio.get<List<dynamic>>('/api/v1/projects');
    return (response.data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ResearchProject.fromJson)
        .toList(growable: false);
  }

  Future<ResearchProject> createProject({
    required String title,
    required String description,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/projects',
      data: {'title': title, 'description': description},
    );
    return ResearchProject.fromJson(response.data!);
  }

  static String readableError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic> && data['detail'] != null) {
        return data['detail'].toString();
      }
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout) {
        return 'FastAPI belum dapat dihubungi. Pastikan server lokal berjalan.';
      }
    }
    return 'Proyek belum dapat disimpan. Silakan coba kembali.';
  }
}
