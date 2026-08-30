import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

final projectChatRepositoryProvider = Provider<ProjectChatRepository>((ref) {
  return ProjectChatRepository(ref.watch(dioProvider));
});

class ChatHistoryMessage {
  const ChatHistoryMessage({required this.role, required this.content});
  final String role;
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class ProjectChatSource {
  const ProjectChatSource({
    required this.sourceId,
    required this.paperId,
    required this.paperTitle,
    required this.parameter,
    required this.quote,
    required this.pageNumber,
    required this.blockId,
  });
  final String sourceId;
  final String paperId;
  final String paperTitle;
  final String parameter;
  final String? quote;
  final int? pageNumber;
  final String? blockId;

  factory ProjectChatSource.fromJson(Map<String, dynamic> json) =>
      ProjectChatSource(
        sourceId: json['source_id']?.toString() ?? '',
        paperId: json['paper_id']?.toString() ?? '',
        paperTitle: json['paper_title']?.toString() ?? 'Paper',
        parameter: json['parameter']?.toString() ?? '',
        quote: json['quote']?.toString(),
        pageNumber: (json['page_number'] as num?)?.toInt(),
        blockId: json['block_id']?.toString(),
      );
}

class ProjectChatAnswer {
  const ProjectChatAnswer({
    required this.answer,
    required this.sources,
    required this.modelName,
    required this.reviewNotice,
  });
  final String answer;
  final List<ProjectChatSource> sources;
  final String modelName;
  final String reviewNotice;

  factory ProjectChatAnswer.fromJson(Map<String, dynamic> json) =>
      ProjectChatAnswer(
        answer: json['answer']?.toString() ?? '',
        sources: (json['sources'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ProjectChatSource.fromJson)
            .toList(growable: false),
        modelName: json['model_name']?.toString() ?? '',
        reviewNotice: json['review_notice']?.toString() ?? '',
      );
}

class StoredProjectChatMessage {
  const StoredProjectChatMessage({
    required this.role,
    required this.content,
    required this.sources,
    required this.reviewNotice,
  });

  final String role;
  final String content;
  final List<ProjectChatSource> sources;
  final String? reviewNotice;

  factory StoredProjectChatMessage.fromJson(Map<String, dynamic> json) =>
      StoredProjectChatMessage(
        role: json['role']?.toString() ?? 'assistant',
        content: json['content']?.toString() ?? '',
        sources: (json['sources'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ProjectChatSource.fromJson)
            .toList(growable: false),
        reviewNotice: json['review_notice']?.toString(),
      );
}

class ProjectChatRepository {
  const ProjectChatRepository(this._dio);
  final Dio _dio;

  Future<List<StoredProjectChatMessage>> getHistory(String projectId) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/v1/projects/$projectId/chat/messages',
    );
    return (response.data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(StoredProjectChatMessage.fromJson)
        .toList(growable: false);
  }

  Future<ProjectChatAnswer> ask({
    required String projectId,
    required String question,
    required List<ChatHistoryMessage> history,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/projects/$projectId/chat',
      data: {
        'question': question,
        'history': history.map((message) => message.toJson()).toList(),
      },
    );
    return ProjectChatAnswer.fromJson(response.data!);
  }

  static String readableError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic> && data['detail'] != null) {
        return data['detail'].toString();
      }
    }
    return 'Chatbot belum dapat menjawab. Silakan coba lagi.';
  }
}
