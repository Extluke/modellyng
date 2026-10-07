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

  Future<void> deleteProject(String projectId) async {
    await _dio.delete('/api/v1/projects/$projectId');
  }

  Future<void> deletePaper(String projectId, String paperId) async {
    await _dio.delete('/api/v1/projects/$projectId/papers/$paperId');
  }

  static String readableError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic> && data['detail'] != null) {
        return data['detail'].toString();
      }
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout) {
        return 'Server belum dapat dihubungi. Periksa internet atau coba lagi ketika server beta aktif.';
      }
    }
    return 'Proyek belum dapat disimpan. Silakan coba kembali.';
  }

  Future<KnowledgeGraphMap> getKnowledgeGraph(String projectId) async {
    final response = await _dio.get<Map<String, dynamic>>('/api/v1/projects/$projectId/knowledge-graph');
    return KnowledgeGraphMap.fromJson(response.data!);
  }

  Future<AiResearchSynthesis> synthesizeGraphNodes(String projectId, List<String> nodeIds) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/projects/$projectId/synthesize-graph-nodes',
      data: {'node_ids': nodeIds},
    );
    return AiResearchSynthesis.fromJson(response.data!);
  }

  Future<void> updateGapValidation(String projectId, String gapId, String status) async {
    await _dio.patch(
      '/api/v1/projects/$projectId/gaps/$gapId/validation',
      data: {'status': status},
    );
  }
}
