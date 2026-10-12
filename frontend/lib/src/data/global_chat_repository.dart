import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

class GlobalChatMessage {
  const GlobalChatMessage({
    required this.role,
    required this.content,
    this.timestamp,
  });

  final String role;
  final String content;
  final DateTime? timestamp;

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
  };

  Map<String, dynamic> toApiJson() => {'role': role, 'content': content};

  factory GlobalChatMessage.fromJson(Map<String, dynamic> json) =>
      GlobalChatMessage(
        role: json['role'] as String? ?? 'user',
        content: json['content'] as String? ?? '',
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'].toString())
            : null,
      );
}

class GlobalChatResponse {
  const GlobalChatResponse({required this.answer, required this.modelName});

  final String answer;
  final String modelName;

  factory GlobalChatResponse.fromJson(Map<String, dynamic> json) {
    return GlobalChatResponse(
      answer: json['answer'] as String,
      modelName: json['model_name'] as String,
    );
  }
}

class GlobalChatRepository {
  const GlobalChatRepository(this._client);
  final Dio _client;

  Future<GlobalChatResponse> sendQuestion(
    String question,
    List<GlobalChatMessage> history,
  ) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/v1/assistant/chat',
      data: {
        'question': question,
        'history': history.map((e) => e.toApiJson()).toList(),
      },
    );
    return GlobalChatResponse.fromJson(response.data!);
  }
}

final globalChatRepositoryProvider = Provider<GlobalChatRepository>((ref) {
  final client = ref.watch(dioProvider);
  return GlobalChatRepository(client);
});
