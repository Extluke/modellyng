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

/// Jumlah pesan terakhir yang dikirim sebagai konteks percakapan. Backend hanya
/// membaca 6 pesan terakhir dan menolak daftar yang lebih panjang dari 15.
const chatHistoryMessageLimit = 6;

/// Backend menolak isi riwayat di atas 4.000 karakter; jawaban AI bisa lebih
/// panjang, jadi dipotong agar permintaan tidak gagal.
const chatHistoryMessageMaxChars = 1500;

/// Menyusun konteks percakapan yang dikirim bersama pertanyaan baru.
///
/// [messages] adalah percakapan sebelum pertanyaan ini. Hasilnya memuat pesan
/// pengguna dan jawaban AI (agar pertanyaan lanjutan nyambung), tanpa sapaan
/// awal lokal yang tampil sebelum pengguna bertanya, paling banyak [limit]
/// pesan terakhir.
List<GlobalChatMessage> buildChatHistory(
  Iterable<GlobalChatMessage> messages, {
  int limit = chatHistoryMessageLimit,
  int maxChars = chatHistoryMessageMaxChars,
}) {
  final all = messages.toList(growable: false);
  final firstUser = all.indexWhere((message) => message.role == 'user');
  if (firstUser < 0) return const [];
  final recent = all.sublist(firstUser);
  final window = recent.length > limit
      ? recent.sublist(recent.length - limit)
      : recent;
  return [
    for (final message in window)
      GlobalChatMessage(
        role: message.role,
        content: _truncateChatText(message.content, maxChars),
      ),
  ];
}

String _truncateChatText(String text, int maxChars) {
  if (text.length <= maxChars) return text;
  var end = maxChars;
  // Jangan memotong di tengah pasangan surrogate (emoji dan sejenisnya).
  final unit = text.codeUnitAt(end - 1);
  if (unit >= 0xD800 && unit <= 0xDBFF) end -= 1;
  return '${text.substring(0, end)}…';
}

/// Pesan yang ramah untuk kegagalan mengirim pertanyaan ke asisten.
///
/// Memakai `detail` dari backend bila ada (misalnya "Gemini sedang sibuk…")
/// dan menghindari teks mentah `DioException` yang tidak berguna bagi pengguna.
String chatErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    final detail = data is Map<String, dynamic> ? data['detail'] : null;
    if (detail is String && detail.trim().isNotEmpty) return detail.trim();

    final status = error.response?.statusCode;
    if (status == 422) {
      return 'Pesan terlalu panjang atau tidak valid. Persingkat pesan lalu coba lagi.';
    }
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return 'Server belum dapat dihubungi. Periksa koneksi lalu coba lagi.';
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Asisten terlalu lama menjawab. Coba lagi sebentar lagi.';
      default:
        break;
    }
    if (status != null && status >= 500) {
      return 'Asisten sedang tidak tersedia. Coba lagi beberapa saat.';
    }
  }
  return 'Pesan belum dapat dikirim. Silakan coba lagi.';
}
