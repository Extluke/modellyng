import 'dart:io';
import 'dart:typed_data';

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
    
    // Check for duplicates
    final existingTitles = existingPapers.map((p) => p.title?.toLowerCase() ?? '').toSet();
    for (final file in result.files) {
      if (existingTitles.contains(file.name.toLowerCase())) {
        throw PaperUploadException(
          'Paper "${file.name}" sudah pernah diunggah ke proyek ini.',
        );
      }
    }

    final List<ProjectPaper> uploadedPapers = [];
    final totalFiles = result.files.length;
    int completedFiles = 0;

    for (final selected in result.files) {
      if (kIsWeb && selected.bytes == null) {
        throw const PaperUploadException(
          'Salah satu file tidak dapat dibaca. Silakan pilih PDF kembali.',
        );
      }
      if (!kIsWeb && selected.path == null) {
        throw const PaperUploadException(
          'Path file tidak ditemukan. Silakan pilih PDF kembali.',
        );
      }
      
      final paper = await uploadPdf(
        project: project,
        originalFilename: selected.name,
        bytes: selected.bytes,
        path: selected.path,
        size: selected.size,
        onProgress: (progress) {
          final overallProgress = (completedFiles + progress) / totalFiles;
          onProgress?.call(overallProgress);
        },
      );
      uploadedPapers.add(paper);
      completedFiles++;
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
    await _validatePdf(originalFilename, size, bytes: bytes, path: path);

    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const PaperUploadException(
        'Sesi login telah berakhir. Silakan masuk kembali.',
      );
    }

    try {
      onProgress?.call(0.05);
      
      final multipartFile = bytes != null
          ? MultipartFile.fromBytes(bytes, filename: originalFilename)
          : await MultipartFile.fromFile(path!, filename: originalFilename);

      final formData = FormData.fromMap({
        'file': multipartFile,
      });
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/projects/${project.id}/papers/upload',
        data: formData,
        options: Options(
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(minutes: 2),
        ),
        onSendProgress: (sent, total) {
          if (total > 0) {
            onProgress?.call(0.05 + (sent / total * 0.9));
          }
        },
      );
      onProgress?.call(1);
      return ProjectPaper.fromJson(response.data!);
    } catch (error) {
      throw PaperUploadException(readableError(error));
    }
  }

  static Future<void> _validatePdf(String name, int? size, {Uint8List? bytes, String? path}) async {
    if (!name.toLowerCase().endsWith('.pdf')) {
      throw const PaperUploadException('Hanya file PDF yang dapat diunggah.');
    }
    
    int actualSize = size ?? 0;
    List<int> signatureBytes = [];

    if (bytes != null) {
      actualSize = bytes.length;
      if (bytes.length >= 5) {
        signatureBytes = bytes.sublist(0, 5);
      }
    } else if (path != null) {
      final file = File(path);
      actualSize = await file.length();
      final stream = file.openRead(0, 5);
      await for (final chunk in stream) {
        signatureBytes.addAll(chunk);
        if (signatureBytes.length >= 5) break;
      }
    }

    if (actualSize <= 0 || signatureBytes.isEmpty) {
      throw const PaperUploadException(
        'File PDF kosong dan tidak dapat diproses.',
      );
    }
    if (actualSize > maxPdfSizeBytes) {
      throw const PaperUploadException(
        'Ukuran PDF melebihi batas 50 MB per file.',
      );
    }
    
    const signature = [0x25, 0x50, 0x44, 0x46, 0x2D];
    if (signatureBytes.length < 5 ||
        !List.generate(
          5,
          (index) => signatureBytes[index] == signature[index],
        ).every((matches) => matches)) {
      throw const PaperUploadException(
        'Isi file tidak dikenali sebagai dokumen PDF yang valid.',
      );
    }
  }

  static String readableError(Object error) {
    if (error is PaperUploadException) return error.message;
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
        return 'FastAPI belum dapat dihubungi. Pastikan server lokal berjalan.';
      }
      if (error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return 'Waktu unggah habis. Pastikan server tetap berjalan lalu coba kembali.';
      }
      return ProjectRepository.readableError(error);
    }
    return 'PDF belum dapat diunggah. Silakan coba kembali.';
  }
}
