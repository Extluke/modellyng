import 'package:flutter/material.dart';

enum ProjectStatus { ready, processing, needsReview }

enum PaperStatus { validating, ready, processing, needsReview, failed }

enum PaperJobStatus { queued, processing, completed, failed, cancelled }

enum VerificationStatus { verified, needsReview, edited, unsupported, rejected }

class ResearchProject {
  const ResearchProject({
    required this.id,
    required this.title,
    required this.description,
    required this.paperCount,
    required this.reviewCount,
    this.knowledgeNodeCount = 0,
    required this.progress,
    required this.status,
    required this.updatedLabel,
    required this.accent,
  });

  final String id;
  final String title;
  final String description;
  final int paperCount;
  final int reviewCount;
  final int knowledgeNodeCount;
  final double progress;
  final ProjectStatus status;
  final String updatedLabel;
  final Color accent;

  factory ResearchProject.fromJson(Map<String, dynamic> json) {
    final status = switch (json['status']) {
      'processing' => ProjectStatus.processing,
      'needs_review' => ProjectStatus.needsReview,
      _ => ProjectStatus.ready,
    };
    final updatedAt = DateTime.tryParse(json['updated_at']?.toString() ?? '');

    return ResearchProject(
      id: json['id'].toString(),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      paperCount: (json['paper_count'] as num?)?.toInt() ?? 0,
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      knowledgeNodeCount: (json['knowledge_node_count'] as num?)?.toInt() ?? 0,
      progress: switch (status) {
        ProjectStatus.ready => 1,
        ProjectStatus.processing => 0.5,
        ProjectStatus.needsReview => 0.85,
      },
      status: status,
      updatedLabel: _updatedLabel(updatedAt),
      accent: const Color(0xFF5747E8),
    );
  }

  static String _updatedLabel(DateTime? value) {
    if (value == null) return 'Baru diperbarui';
    final difference = DateTime.now().difference(value.toLocal());
    if (difference.inMinutes < 1) return 'Baru saja';
    if (difference.inHours < 1) return '${difference.inMinutes} menit lalu';
    if (difference.inDays < 1) return '${difference.inHours} jam lalu';
    if (difference.inDays == 1) return 'Kemarin';
    return '${difference.inDays} hari lalu';
  }
}

class PaperRecord {
  const PaperRecord({
    required this.id,
    required this.title,
    required this.authors,
    required this.year,
    required this.journal,
    required this.doi,
    required this.status,
    required this.progress,
  });

  final String id;
  final String title;
  final String authors;
  final int year;
  final String journal;
  final String doi;
  final PaperStatus status;
  final double progress;
}

class ProjectPaper {
  const ProjectPaper({
    required this.id,
    required this.projectId,
    required this.originalFilename,
    required this.storageKey,
    required this.fileSizeBytes,
    required this.status,
    required this.pageCount,
    required this.languageCode,
    required this.title,
    required this.authors,
    required this.jobStatus,
    required this.processingStage,
    required this.processingProgress,
    required this.processingError,
    required this.createdAt,
  });

  final String id;
  final String projectId;
  final String originalFilename;
  final String storageKey;
  final int fileSizeBytes;
  final PaperStatus status;
  final int? pageCount;
  final String? languageCode;
  final String? title;
  final List<String> authors;
  final PaperJobStatus? jobStatus;
  final String? processingStage;
  final double processingProgress;
  final String? processingError;
  final DateTime? createdAt;

  factory ProjectPaper.fromJson(Map<String, dynamic> json) {
    final rawJob = json['analysis_job'];
    final job = rawJob is Map<String, dynamic> ? rawJob : null;
    return ProjectPaper(
      id: json['id'].toString(),
      projectId: json['project_id'].toString(),
      originalFilename:
          json['original_filename']?.toString() ?? 'paper-tanpa-nama.pdf',
      storageKey: json['storage_key']?.toString() ?? '',
      fileSizeBytes: (json['file_size_bytes'] as num?)?.toInt() ?? 0,
      status: switch (json['status']) {
        'ready' => PaperStatus.ready,
        'processing' => PaperStatus.processing,
        'needs_review' => PaperStatus.needsReview,
        'failed' => PaperStatus.failed,
        _ => PaperStatus.validating,
      },
      pageCount: (json['page_count'] as num?)?.toInt(),
      languageCode: json['language_code']?.toString(),
      title: json['title']?.toString(),
      authors: (json['authors'] as List<dynamic>? ?? const [])
          .map((author) => author.toString())
          .toList(growable: false),
      jobStatus: switch (job?['status']) {
        'queued' => PaperJobStatus.queued,
        'processing' => PaperJobStatus.processing,
        'completed' => PaperJobStatus.completed,
        'failed' => PaperJobStatus.failed,
        'cancelled' => PaperJobStatus.cancelled,
        _ => null,
      },
      processingStage: job?['stage']?.toString(),
      processingProgress: ((job?['progress'] as num?)?.toDouble() ?? 0).clamp(
        0,
        1,
      ),
      processingError: job?['error_message']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  bool get isProcessing =>
      jobStatus == PaperJobStatus.queued ||
      jobStatus == PaperJobStatus.processing;

  bool get canStartProcessing =>
      !isProcessing &&
      (jobStatus == null ||
          jobStatus == PaperJobStatus.failed ||
          jobStatus == PaperJobStatus.cancelled ||
          (jobStatus == PaperJobStatus.completed &&
              processingStage == 'local_extraction_complete'));

  bool get needsGeminiAnalysis =>
      jobStatus == PaperJobStatus.completed &&
      processingStage == 'local_extraction_complete';

  String get languageLabel => switch (languageCode) {
    'id' => 'Bahasa Indonesia',
    'en' => 'Bahasa Inggris',
    _ => 'Bahasa belum dikenali',
  };

  String get processingStageLabel => switch (processingStage) {
    'queued' => 'Menunggu worker',
    'downloading' => 'Mengambil PDF privat',
    'extracting_text' => 'Membaca teks per halaman',
    'saving_blocks' => 'Menyimpan hasil ekstraksi',
    'gemini_extraction' => 'Menganalisis komponen dengan Gemini',
    'retrying_gemini' => 'Gemini sibuk, mencoba lagi otomatis',
    'saving_ai_results' => 'Menyimpan hasil dan bukti AI',
    'ai_extraction_complete' => 'Ekstraksi AI selesai',
    'queue_failed' => 'Antrean gagal dimulai',
    'failed' => 'Pemrosesan gagal',
    _ => 'Menyiapkan pemrosesan',
  };

  String get formattedSize {
    if (fileSizeBytes >= 1024 * 1024) {
      return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
  }
}

class ExtractedComponent {
  const ExtractedComponent({
    required this.label,
    required this.value,
    required this.evidence,
    required this.location,
    required this.status,
  });

  final String label;
  final String value;
  final String evidence;
  final String location;
  final VerificationStatus status;
}

class ResearchGap {
  const ResearchGap({
    required this.title,
    required this.description,
    required this.supportingPapers,
    required this.confidence,
    required this.type,
  });

  final String title;
  final String description;
  final int supportingPapers;
  final double confidence;
  final String type;
}
