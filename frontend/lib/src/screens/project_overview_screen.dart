import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../data/paper_comparison_repository.dart';
import '../data/paper_repository.dart';
import '../data/paper_result_repository.dart';
import '../data/project_repository.dart';
import '../data/review_repository.dart';
import '../models/research_models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'export_results_screen.dart';
import 'paper_result_screen.dart';

class ProjectOverviewScreen extends ConsumerStatefulWidget {
  const ProjectOverviewScreen({required this.project, super.key});

  final ResearchProject project;

  @override
  ConsumerState<ProjectOverviewScreen> createState() =>
      _ProjectOverviewScreenState();
}

class _ProjectOverviewScreenState extends ConsumerState<ProjectOverviewScreen> {
  bool _uploading = false;
  bool _acceptingAll = false;
  double _uploadProgress = 0;
  Timer? _pollingTimer;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _uploading) return;
      final userId = ref.read(authRepositoryProvider).currentUser?.id;
      if (userId == null) return;
      final query = (userId: userId, projectId: widget.project.id);
      final current = ref.read(projectPapersProvider(query)).value;
      if (current?.any((paper) => paper.isProcessing) ?? false) {
        ref.invalidate(projectPapersProvider(query));
        ref.invalidate(projectsProvider(userId));
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _uploadPdf() async {
    if (_uploading) return;
    setState(() {
      _uploading = true;
      _uploadProgress = 0;
    });

    if (_scrollController.hasClients) {
      unawaited(
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        ),
      );
    }
    try {
      final userId = ref.read(authRepositoryProvider).currentUser?.id;
      if (userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sesi login telah berakhir. Silakan masuk kembali.'),
            backgroundColor: AppColors.red,
          ),
        );
        return;
      }
      final query = (userId: userId, projectId: widget.project.id);
      final existingPapers = ref.read(projectPapersProvider(query)).value ?? [];

      final papers = await ref
          .read(paperRepositoryProvider)
          .pickAndUploadPdf(
            widget.project,
            existingPapers: existingPapers,
            onProgress: (progress) {
              if (mounted) setState(() => _uploadProgress = progress);
            },
          );
      if (!mounted) return;
      if (papers != null && papers.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${papers.length} PDF berhasil diunggah.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(PaperRepository.readableError(error)),
          backgroundColor: AppColors.red,
        ),
      );
    } finally {
      final userId = ref.read(authRepositoryProvider).currentUser?.id;
      if (userId != null) {
        ref.invalidate(
          projectPapersProvider((userId: userId, projectId: widget.project.id)),
        );
        ref.invalidate(projectsProvider(userId));
      }
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _processPaper(ProjectPaper paper) async {
    try {
      await ref
          .read(paperRepositoryProvider)
          .processPaper(projectId: widget.project.id, paperId: paper.id);
      if (!mounted) return;
      final userId = ref.read(authRepositoryProvider).currentUser?.id;
      if (userId != null) {
        ref.invalidate(
          projectPapersProvider((userId: userId, projectId: widget.project.id)),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF masuk ke antrean pemrosesan.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(PaperRepository.readableError(error)),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  Future<void> _deletePaper(ProjectPaper paper) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hapus Paper?'),
          content: Text(
            'Apakah Anda yakin ingin menghapus PDF "${paper.originalFilename}"? '
            'Semua data hasil analisis dan riwayat review untuk paper ini akan hilang permanen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.delete_forever),
              label: const Text('Hapus'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await ref
          .read(projectRepositoryProvider)
          .deletePaper(widget.project.id, paper.id);

      if (!mounted) return;

      final userId = ref.read(authRepositoryProvider).currentUser?.id;
      if (userId != null) {
        ref.invalidate(
          projectPapersProvider((userId: userId, projectId: widget.project.id)),
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Paper "${paper.originalFilename}" telah dihapus.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ProjectRepository.readableError(error)),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  /// Pending analyses the project shortcut may accept: active review-queue
  /// components of this project whose paper awaits review. Papers that are
  /// being (re)processed are skipped, so components about to be replaced are
  /// not finalized and the paper is not marked ready in the middle of a job.
  List<ReviewQueueItem> _acceptableAnalyses(
    List<ProjectPaper>? papers,
    List<ReviewQueueItem>? queue,
  ) {
    if (papers == null || queue == null) return const [];
    final awaitingReview = {
      for (final paper in papers)
        if (paper.status == PaperStatus.needsReview && !paper.isProcessing)
          paper.id,
    };
    return queue
        .where(
          (item) =>
              item.projectId == widget.project.id &&
              awaitingReview.contains(item.paperId),
        )
        .toList(growable: false);
  }

  /// Changes whenever a paper changes the review queue: a finished job adds
  /// components, a completed review or deletion removes them.
  static String _reviewStateSignature(List<ProjectPaper> papers) => [
    for (final paper in papers)
      '${paper.id}:${paper.status.name}:${paper.jobStatus?.name}',
  ].join('|');

  Future<void> _acceptAllAnalyses(
    List<ReviewQueueItem> items, {
    required String userId,
    required int processingPaperCount,
  }) async {
    if (items.isEmpty || _acceptingAll) return;
    final projectId = widget.project.id;
    final total = items.length;
    final paperCount = items.map((item) => item.paperId).toSet().length;
    final batches = planBulkAcceptBatches(items);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Terima semua $total hasil analisis?'),
        content: Text(
          [
            'Semua $total hasil analisis dari $paperCount paper di proyek '
                '"${widget.project.title}" akan dijadikan final tanpa diperiksa '
                'satu per satu. Sitasi dan riwayat keputusan tetap tersimpan '
                'untuk audit.',
            if (processingPaperCount > 0)
              '$processingPaperCount paper yang masih diproses tidak termasuk.',
            if (batches.length > 1)
              'Hasil dikirim bertahap dalam ${batches.length} kelompok per '
                  'paper. Jika satu kelompok gagal, kelompok lain tetap '
                  'diproses dan hasilnya dilaporkan.',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            key: const Key('confirm-accept-all-project-analyses'),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.done_all_rounded),
            label: const Text('Ya, terima semua'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _acceptingAll = true);
    // Captured before the requests so caches still refresh and the outcome is
    // still reported if the user leaves this page while they run.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(reviewRepositoryProvider);
    var accepted = 0;
    var failed = 0;
    // Each request is its own owner-scoped transaction. A failed batch leaves
    // its papers pending, so continue with the rest and report what happened.
    for (final batch in batches) {
      try {
        accepted += await repository.acceptAll(batch);
      } catch (_) {
        failed += batch.length;
      }
    }

    container
      ..invalidate(reviewQueueProvider(userId))
      ..invalidate(reviewHistoryProvider(userId))
      ..invalidate(projectsProvider(userId))
      ..invalidate(projectPapersProvider((userId: userId, projectId: projectId)))
      ..invalidate(paperComparisonsProvider)
      ..invalidate(paperResultProvider);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? '$accepted hasil analisis berhasil diterima.'
              : accepted == 0
              ? 'Terima semua analisis gagal. Tidak ada hasil yang diterima.'
              : '$accepted dari $total hasil analisis diterima. $failed hasil '
                    'lainnya gagal diterima, silakan coba lagi.',
        ),
        backgroundColor: failed == 0 ? null : AppColors.red,
      ),
    );
    if (mounted) setState(() => _acceptingAll = false);
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final userId = ref.watch(authRepositoryProvider).currentUser?.id;
    final papers = userId == null
        ? const AsyncValue<List<ProjectPaper>>.data([])
        : ref.watch(
            projectPapersProvider((userId: userId, projectId: project.id)),
          );
    final paperCount = papers.value?.length ?? project.paperCount;
    final reviewCount =
        papers.value
            ?.where((paper) => paper.status == PaperStatus.needsReview)
            .length ??
        project.reviewCount;
    if (userId != null) {
      // Keep the shortcut's count in step with paper status changes that the
      // polling above picks up.
      ref.listen<AsyncValue<List<ProjectPaper>>>(
        projectPapersProvider((userId: userId, projectId: project.id)),
        (previous, next) {
          final before = previous?.value;
          final after = next.value;
          if (before == null || after == null) return;
          if (_reviewStateSignature(before) != _reviewStateSignature(after)) {
            ref.invalidate(reviewQueueProvider(userId));
          }
        },
      );
    }
    final pendingAnalyses = userId == null
        ? const <ReviewQueueItem>[]
        : _acceptableAnalyses(
            papers.value,
            ref.watch(reviewQueueProvider(userId)).value,
          );
    final processingPaperCount =
        papers.value
            ?.where(
              (paper) =>
                  paper.isProcessing || paper.status == PaperStatus.processing,
            )
            .length ??
        0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const BrandLockup(),
        actions: [
          TextButton.icon(
            key: const Key('open-export-button'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => ExportResultsScreen(project: project),
              ),
            ),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Ekspor'),
          ),
          const SizedBox(width: 10),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_uploading ? 4 : 1),
          child: _uploading
              ? LinearProgressIndicator(
                  key: const Key('appbar-upload-progress'),
                  value: _uploadProgress > 0 ? _uploadProgress : null,
                  minHeight: 4,
                  backgroundColor: AppColors.primarySoft,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.primary,
                  ),
                )
              : const Divider(height: 1),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;
          final spacing = isNarrow ? 16.0 : 24.0;
          return SingleChildScrollView(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
              isNarrow ? 16 : 24,
              isNarrow ? 18 : 30,
              isNarrow ? 16 : 24,
              isNarrow ? 24 : 40,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PageHeading(
                      title: project.title,
                      subtitle: project.description.isEmpty
                          ? 'Workspace riset tanpa deskripsi.'
                          : project.description,
                      action: FilledButton.icon(
                        key: const Key('upload-pdf-button'),
                        onPressed: _uploading ? null : _uploadPdf,
                        icon: _uploading
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.upload_file_rounded),
                        label: Text(
                          _uploading
                              ? '${(_uploadProgress * 100).round()}% Mengunggah...'
                              : 'Unggah PDF',
                        ),
                      ),
                    ),
                    SizedBox(height: spacing),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: MetricCard(
                              icon: Icons.description_outlined,
                              label: 'Paper',
                              value: '$paperCount',
                              color: AppColors.blue,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: MetricCard(
                              icon: Icons.fact_check_outlined,
                              label: 'Menunggu review',
                              value: '$reviewCount',
                              color: AppColors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: spacing),
                    _UploadGuidance(
                      uploading: _uploading,
                      progress: _uploadProgress,
                    ),
                    SizedBox(height: spacing),
                    _PaperSectionHeading(
                      compact: isNarrow,
                      pendingCount: pendingAnalyses.length,
                      accepting: _acceptingAll,
                      onAcceptAll: () => _acceptAllAnalyses(
                        pendingAnalyses,
                        userId: userId!,
                        processingPaperCount: processingPaperCount,
                      ),
                    ),
                    const SizedBox(height: 14),
                    papers.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(36),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (error, _) => Card(
                        child: EmptyState(
                          icon: Icons.cloud_off_outlined,
                          title: 'Daftar paper belum dapat dimuat',
                          message:
                              'Pastikan FastAPI dan Supabase lokal sedang berjalan.',
                          action: FilledButton.icon(
                            onPressed: userId == null
                                ? null
                                : () => ref.invalidate(
                                    projectPapersProvider((
                                      userId: userId,
                                      projectId: project.id,
                                    )),
                                  ),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Coba lagi'),
                          ),
                        ),
                      ),
                      data: (items) => items.isEmpty
                          ? Card(
                              child: EmptyState(
                                icon: _uploading
                                    ? Icons.cloud_upload_outlined
                                    : Icons.upload_file_outlined,
                                title: _uploading
                                    ? 'Sedang mengunggah PDF...'
                                    : 'Belum ada paper dalam proyek ini',
                                message: _uploading
                                    ? 'PDF sedang dikirim ke penyimpanan privat (${(_uploadProgress * 100).round()}%). Mohon jangan tutup halaman ini.'
                                    : 'Unggah PDF pertama. Ukuran maksimal 50 MB dan file harus memiliki isi PDF yang valid.',
                                action: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_uploading) ...[
                                      SizedBox(
                                        width: 240,
                                        child: LinearProgressIndicator(
                                          key: const Key(
                                            'empty-state-upload-progress',
                                          ),
                                          value: _uploadProgress > 0
                                              ? _uploadProgress
                                              : null,
                                          minHeight: 6,
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                          backgroundColor:
                                              AppColors.primarySoft,
                                          valueColor:
                                              const AlwaysStoppedAnimation<
                                                Color
                                              >(AppColors.primary),
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                    ],
                                    FilledButton.icon(
                                      key: const Key(
                                        'empty-state-upload-button',
                                      ),
                                      onPressed: _uploading ? null : _uploadPdf,
                                      icon: _uploading
                                          ? const SizedBox(
                                              width: 17,
                                              height: 17,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.upload_file_rounded,
                                            ),
                                      label: Text(
                                        _uploading
                                            ? 'Mengunggah (${(_uploadProgress * 100).round()}%)...'
                                            : 'Pilih PDF',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Column(
                              children: [
                                for (final paper in items) ...[
                                  _PaperTile(
                                    paper: paper,
                                    onOpenResult: () async {
                                      await Navigator.of(context).push<void>(
                                        MaterialPageRoute(
                                          builder: (_) => PaperResultScreen(
                                            projectId: project.id,
                                            paperId: paper.id,
                                          ),
                                        ),
                                      );
                                      if (userId != null) {
                                        ref.invalidate(
                                          projectPapersProvider((
                                            userId: userId,
                                            projectId: project.id,
                                          )),
                                        );
                                        ref.invalidate(
                                          projectsProvider(userId),
                                        );
                                      }
                                    },
                                    onProcess: paper.canStartProcessing
                                        ? () => _processPaper(paper)
                                        : null,
                                    onDelete: () => _deletePaper(paper),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// "Paper dalam proyek" heading with the project's accept-all shortcut on the
/// same row. The shortcut is hidden while nothing in the project awaits review.
class _PaperSectionHeading extends StatelessWidget {
  const _PaperSectionHeading({
    required this.compact,
    required this.pendingCount,
    required this.accepting,
    required this.onAcceptAll,
  });

  final bool compact;
  final int pendingCount;
  final bool accepting;
  final VoidCallback onAcceptAll;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Expanded(
                child: Text('Paper dalam proyek', style: textTheme.titleLarge),
              ),
              if (pendingCount > 0) ...[
                const SizedBox(width: 12),
                ConstrainedBox(
                  // Leaves room for the title when large text widens the label.
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.6,
                  ),
                  child: Tooltip(
                    message:
                        'Terima semua hasil analisis yang menunggu review di proyek ini',
                    child: FilledButton.icon(
                      key: const Key('accept-all-project-analyses'),
                      onPressed: accepting ? null : onAcceptAll,
                      style: compact
                          ? FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            )
                          : null,
                      icon: accepting
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.done_all_rounded, size: 18),
                      label: Text(
                        compact
                            ? 'Terima semua ($pendingCount)'
                            : 'Terima semua analisis ($pendingCount)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'File tersimpan privat dan hanya dapat diakses oleh pemilik proyek.',
          style: textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _UploadGuidance extends StatelessWidget {
  const _UploadGuidance({required this.uploading, required this.progress});

  final bool uploading;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                uploading ? Icons.cloud_upload_outlined : Icons.lock_outline,
                color: AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  uploading
                      ? 'PDF sedang dikirim ke penyimpanan privat. Jangan tutup halaman ini.'
                      : 'PDF maksimal 50 MB. File diperiksa di perangkat dan server sebelum dicatat sebagai paper.',
                ),
              ),
              if (uploading) ...[
                const SizedBox(width: 12),
                Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
          if (uploading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              key: const Key('guidance-upload-progress'),
              value: progress > 0 ? progress : null,
              minHeight: 6,
              borderRadius: BorderRadius.circular(99),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaperTile extends StatelessWidget {
  const _PaperTile({
    required this.paper,
    required this.onOpenResult,
    this.onProcess,
    this.onDelete,
  });

  final ProjectPaper paper;
  final VoidCallback onOpenResult;
  final VoidCallback? onProcess;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.redSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.picture_as_pdf_outlined,
                color: AppColors.red,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    paper.originalFilename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 5),
                  if (paper.title?.trim().isNotEmpty == true) ...[
                    Text(
                      paper.title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                  ],
                  Text(
                    [
                      paper.formattedSize,
                      if (paper.pageCount != null) '${paper.pageCount} halaman',
                      if (paper.languageCode != null) paper.languageLabel,
                      'PDF privat',
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                  if (paper.isProcessing) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: paper.processingProgress > 0
                                ? paper.processingProgress
                                : null,
                            minHeight: 5,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${(paper.processingProgress * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      paper.processingStageLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                  if (paper.processingError?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      paper.processingError!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusBadge.paper(paper.status),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onOpenResult,
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Lihat hasil'),
                ),
                if (onProcess != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onProcess,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(
                      paper.jobStatus == PaperJobStatus.failed
                          ? 'Proses ulang'
                          : paper.needsGeminiAnalysis
                          ? 'Analisis AI'
                          : 'Proses',
                    ),
                  ),
                ],
                if (onDelete != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: AppColors.red,
                    ),
                    label: const Text(
                      'Hapus',
                      style: TextStyle(color: AppColors.red),
                    ),
                    style: TextButton.styleFrom(foregroundColor: AppColors.red),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
