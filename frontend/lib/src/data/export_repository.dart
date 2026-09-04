import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

final exportRepositoryProvider = Provider<ExportRepository>((ref) {
  return ExportRepository(ref.watch(dioProvider));
});

class ExportDownload {
  const ExportDownload({
    required this.bytes,
    required this.filename,
    required this.mediaType,
  });

  final Uint8List bytes;
  final String filename;
  final String mediaType;
}

class ExportRepository {
  const ExportRepository(this._dio);

  final Dio _dio;

  Future<ExportDownload> exportProject({
    required String projectId,
    required String format,
  }) async {
    final response = await _dio.get<List<int>>(
      '/api/v1/projects/$projectId/export/$format',
      options: Options(responseType: ResponseType.bytes),
    );
    final disposition = response.headers.value('content-disposition') ?? '';
    final filenameMatch = RegExp(
      r'filename="?([^";]+)',
    ).firstMatch(disposition);
    return ExportDownload(
      bytes: Uint8List.fromList(response.data ?? const []),
      filename: filenameMatch?.group(1) ?? 'modellyng-export.$format',
      mediaType:
          response.headers.value(Headers.contentTypeHeader) ??
          'application/octet-stream',
    );
  }

  static String readableError(Object error) {
    if (error is DioException) {
      final detail = _responseDetail(error.response?.data);
      if (detail != null) return detail;
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout) {
        return 'FastAPI belum dapat dihubungi. Pastikan server lokal berjalan.';
      }
    }
    return 'File ekspor belum dapat dibuat. Silakan coba kembali.';
  }

  static String? _responseDetail(Object? data) {
    Object? decoded = data;
    if (data is List<int>) {
      try {
        decoded = jsonDecode(utf8.decode(data));
      } on FormatException {
        return null;
      }
    } else if (data is String) {
      try {
        decoded = jsonDecode(data);
      } on FormatException {
        return null;
      }
    }
    if (decoded is! Map) return null;
    final detail = decoded['detail'];
    return detail == null || detail.toString().trim().isEmpty
        ? null
        : detail.toString();
  }
}
