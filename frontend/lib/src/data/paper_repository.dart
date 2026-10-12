import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide MultipartFile;

import '../models/research_models.dart';
import 'api_client.dart';
import 'auth_repository.dart';
import 'project_repository.dart';

const maxPdfSizeBytes = 50 * 1024 * 1024;
final paperRepositoryProvider = Provider<PaperRepository>((ref) {
  return PaperRepository(
    dio: ref.watch(dioProvider),
    supabase: ref.watch(supabaseClientProvider),
  );
});

typedef ProjectPapersQuery = ({String userId, String projectId});

final projectPapersProvider = FutureProvider.autoDispose
    .family<List<ProjectPaper>, ProjectPapersQuery>((ref, query) async {
      final session = ref.watch(authSessionProvider).value;
      if (session?.user.id != query.userId) return const [];

      final papers = await ref
          .watch(paperRepositoryProvider)
          .listPapers(query.projectId);
      if (ref.read(authRepositoryProvider).currentUser?.id != query.userId) {
        return const [];
      }
      return papers;
    });

class PaperUploadException implements Exception {
  const PaperUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PaperRepository {
  const PaperRepository({required Dio dio, required SupabaseClient supabase})
    : _dio = dio,
      _supabase = supabase;

  final Dio _dio;
  final SupabaseClient _supabase;

  Future<List<ProjectPaper>> listPapers(String projectId) async {
    final response = await _dio.get<List<dynamic>>(
      '/api/v1/projects/$projectId/papers',
    );
    return (response.data ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ProjectPaper.fromJson)
        .toList(growable: false);
  }

  Future<ProjectPaper> processPaper({
    required String projectId,
    required String paperId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/projects/$projectId/papers/$paperId/process',
    );
    return ProjectPaper.fromJson(response.data!);
  }

  Future<List<ProjectPaper>?> pickAndUploadPdf(
    ResearchProject project, {
    List<ProjectPaper> existingPapers = const [],
    void Function(double progress)? onProgress,
  }) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Pilih paper PDF',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: true,
      withData: kIsWeb,
    );
    if (result == null) return null;

    if (result.files.length > 15) {
      throw const PaperUploadException(
        'Maksimal 15 PDF dalam satu kali unggah.',
      );
    }

    List<ProjectPaper> currentPapers = existingPapers;
    if (currentPapers.isEmpty) {
      try {
        currentPapers = await listPapers(project.id);
      } catch (_) {}
    }

    validateDuplicateFilenames(
      result.files.map((file) => file.name),
      currentPapers.map((paper) => paper.originalFilename),
    );

    final List<ProjectPaper> uploadedPapers = [];
    final totalFiles = result.files.length;
    int completedFiles = 0;
    final List<String> failures = [];

    for (final selected in result.files) {
      Uint8List? fileBytes = selected.bytes;
      if (fileBytes == null && selected.path != null) {
        try {
          final f = File(selected.path!);
          if (await f.exists()) {
            fileBytes = await f.readAsBytes();
          }
        } catch (_) {}
      }

      if (fileBytes == null && selected.path == null) {
        failures.add(
          'File "${selected.name}" tidak dapat dibaca dari penyimpanan perangkat.',
        );
        continue;
      }

      try {
        final paper = await uploadPdf(
          project: project,
          originalFilename: selected.name,
          bytes: fileBytes,
          path: selected.path,
          size: selected.size,
          onProgress: (progress) {
            final overallProgress = (completedFiles + progress) / totalFiles;
            onProgress?.call(overallProgress);
          },
        );
        uploadedPapers.add(paper);
        completedFiles++;
      } catch (error) {
        failures.add('${selected.name}: ${readableError(error)}');
      }
    }

    if (failures.isNotEmpty) {
      if (uploadedPapers.isEmpty) {
        throw PaperUploadException(failures.join('\n'));
      }
      throw PaperUploadException(
        '${uploadedPapers.length} dari $totalFiles PDF berhasil diunggah. Gagal:\n${failures.join('\n')}',
      );
    }

    return uploadedPapers;
  }

  Future<ProjectPaper> uploadPdf({
    required ResearchProject project,
    required String originalFilename,
    Uint8List? bytes,
    String? path,
    int? size,
    void Function(double progress)? onProgress,
  }) async {
    final validatedBytes = await _validatePdf(
      originalFilename,
      size,
      bytes: bytes,
      path: path,
    );

    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const PaperUploadException(
        'Sesi login telah berakhir. Silakan masuk kembali.',
      );
    }

    try {
      onProgress?.call(0.05);

      final multipartFile = MultipartFile.fromBytes(
        validatedBytes,
        filename: originalFilename,
      );

      final formData = FormData.fromMap({'file': multipartFile});
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/projects/${project.id}/papers/upload',
        data: formData,
        options: Options(
          connectTimeout: const Duration(minutes: 1),
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
        ),
        onSendProgress: (sent, total) {
          if (total > 0) {
            final ratio = (sent / total).clamp(0.0, 1.0);
            onProgress?.call(0.05 + (ratio * 0.9));
          } else if (sent > 0) {
            onProgress?.call(0.5);
          }
        },
      );
      onProgress?.call(1.0);
      return ProjectPaper.fromJson(response.data!);
    } catch (error) {
      throw PaperUploadException(readableError(error));
    }
  }

  @visibleForTesting
  static void validateDuplicateFilenames(
    Iterable<String> incomingNames,
    Iterable<String> existingNames,
  ) {
    final seen = existingNames
        .map((name) => name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();

    for (final name in incomingNames) {
      final nameLower = name.trim().toLowerCase();
      if (seen.contains(nameLower)) {
        throw PaperUploadException(
          'Paper "$name" sudah pernah diunggah atau duplikat dalam pilihan.',
        );
      }
      seen.add(nameLower);
    }
  }

  @visibleForTesting
  static Future<Uint8List> validatePdf(
    String name,
    int? size, {
    Uint8List? bytes,
    String? path,
  }) => _validatePdf(name, size, bytes: bytes, path: path);

  static Future<Uint8List> _validatePdf(
    String name,
    int? size, {
    Uint8List? bytes,
    String? path,
  }) async {
    if (!name.toLowerCase().endsWith('.pdf')) {
      throw const PaperUploadException('Hanya file PDF yang dapat diunggah.');
    }

    Uint8List effectiveBytes;
    if (bytes != null) {
      effectiveBytes = bytes;
    } else if (path != null) {
      try {
        final file = File(path);
        if (!await file.exists()) {
          throw PaperUploadException(
            'File "$name" tidak ditemukan di perangkat. Silakan pilih kembali.',
          );
        }
        effectiveBytes = await file.readAsBytes();
      } on FileSystemException catch (e) {
        throw PaperUploadException(
          'Gagal membaca file "$name" dari perangkat: ${e.message}',
        );
      }
    } else {
      throw PaperUploadException(
        'File "$name" tidak dapat dibaca dari penyimpanan perangkat.',
      );
    }

    if (effectiveBytes.isEmpty) {
      throw const PaperUploadException(
        'File PDF kosong (0 byte) dan tidak dapat diproses.',
      );
    }
    if (effectiveBytes.length > maxPdfSizeBytes) {
      throw const PaperUploadException(
        'Ukuran PDF melebihi batas 50 MB per file.',
      );
    }

    const signature = [0x25, 0x50, 0x44, 0x46, 0x2D];
    if (effectiveBytes.length < 5 ||
        !List.generate(
          5,
          (index) => effectiveBytes[index] == signature[index],
        ).every((matches) => matches)) {
      throw const PaperUploadException(
        'Isi file tidak dikenali sebagai dokumen PDF yang valid.',
      );
    }
    return effectiveBytes;
  }

  static String readableError(Object error) {
    if (error is PaperUploadException) return error.message;
    if (error is FileSystemException) {
      return 'Gagal membaca file dari penyimpanan perangkat: ${error.message}';
    }
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic> && data['detail'] != null) {
        return data['detail'].toString();
      }
      if (data is Map<String, dynamic> && data['message'] != null) {
        return data['message'].toString();
      }
      if (error.response?.statusCode == 413) {
        return 'Ukuran PDF melebihi batas 50 MB per file.';
      }
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout) {
        return 'FastAPI belum dapat dihubungi. Pastikan server lokal berjalan dan koneksi stabil.';
      }
      if (error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return 'Waktu unggah habis. Pastikan koneksi jaringan stabil lalu coba kembali.';
      }
      return ProjectRepository.readableError(error);
    }
    return 'PDF belum dapat diunggah. Silakan coba kembali.';
  }
}
