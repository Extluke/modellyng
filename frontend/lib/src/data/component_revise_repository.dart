import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'global_chat_repository.dart'; // Re-use GlobalChatMessage

class ComponentReviseResponse {
  const ComponentReviseResponse({
    required this.revisedContent,
    required this.modelName,
  });

  final String revisedContent;
  final String modelName;

  factory ComponentReviseResponse.fromJson(Map<String, dynamic> json) {
    return ComponentReviseResponse(
      revisedContent: json['revised_content'] as String,
      modelName: json['model_name'] as String,
    );
  }
}

class ComponentReviseRepository {
  const ComponentReviseRepository(this._client);
  final Dio _client;

  Future<ComponentReviseResponse> reviseComponent(
    String projectId,
    String componentId,
    String parameter,
    String originalValue,
    List<String> evidenceQuotes,
    String prompt,
    List<GlobalChatMessage> history,
  ) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/v1/projects/$projectId/components/$componentId/revise',
      data: {
        'parameter': parameter,
        'original_value': originalValue,
        'evidence_quotes': evidenceQuotes,
        'prompt': prompt,
        'history': history.map((e) => e.toJson()).toList(),
      },
    );
    return ComponentReviseResponse.fromJson(response.data!);
  }
}

final componentReviseRepositoryProvider = Provider<ComponentReviseRepository>((ref) {
  final client = ref.watch(dioProvider);
  return ComponentReviseRepository(client);
});
