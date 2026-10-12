import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

class GlobalChatMessage {
  const GlobalChatMessage({
    required this.role,
    required this.content,
    this.timestamp,
    this.referencedProject,
    this.projectId,
    this.referencedPaper,
    this.paperId,
  });

  final String role;
  final String content;
  final DateTime? timestamp;
  final String? referencedProject;
  final String? projectId;
  final String? referencedPaper;
  final String? paperId;

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
    if (referencedProject != null) 'referenced_project': referencedProject,
    if (projectId != null) 'project_id': projectId,
    if (referencedPaper != null) 'referenced_paper': referencedPaper,
    if (paperId != null) 'paper_id': paperId,
  };

  Map<String, dynamic> toApiJson() => {'role': role, 'content': content};

  factory GlobalChatMessage.fromJson(Map<String, dynamic> json) =>
      GlobalChatMessage(
        role: json['role'] as String? ?? 'user',
        content: json['content'] as String? ?? '',
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'].toString())
            : null,
        referencedProject: json['referenced_project'] as String?,
        projectId: json['project_id'] as String?,
        referencedPaper: json['referenced_paper'] as String?,
        paperId: json['paper_id'] as String?,
      );
}

class GlobalChatResponse {
  const GlobalChatResponse({
    required this.answer,
    required this.modelName,
    this.referencedProject,
    this.referencedPaper,
  });

  final String answer;
  final String modelName;
  final String? referencedProject;
  final String? referencedPaper;

  factory GlobalChatResponse.fromJson(Map<String, dynamic> json) {
    return GlobalChatResponse(
      answer: json['answer'] as String,
      modelName: json['model_name'] as String,
      referencedProject: json['referenced_project'] as String?,
      referencedPaper: json['referenced_paper'] as String?,
    );
  }
}

class GlobalChatRepository {
  const GlobalChatRepository(this._client);
  final Dio _client;

  Future<GlobalChatResponse> sendQuestion(
    String question,
    List<GlobalChatMessage> history, {
    String? projectId,
    String? paperId,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/v1/assistant/chat',
      data: {
        'question': question,
        'history': history.map((e) => e.toApiJson()).toList(),
        if (projectId != null) 'project_id': projectId,
        if (paperId != null) 'paper_id': paperId,
      },
    );
    return GlobalChatResponse.fromJson(response.data!);
  }
}

final globalChatRepositoryProvider = Provider<GlobalChatRepository>((ref) {
  final client = ref.watch(dioProvider);
  return GlobalChatRepository(client);
});
