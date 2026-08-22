import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../data/paper_repository.dart';
import '../data/project_repository.dart';
import '../models/research_models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
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
  double _uploadProgress = 0;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
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
    super.dispose();
  }

  Future<void> _uploadPdf() async {
    setState(() {
      _uploading = true;
      _uploadProgress = 0;
    });
    try {
      final paper = await ref
          .read(paperRepositoryProvider)
          .pickAndUploadPdf(
            widget.project,
            onProgress: (progress) {
              if (mounted) setState(() => _uploadProgress = progress);
            },
          );
      if (!mounted) return;
      if (paper != null) {
        final userId = ref.read(authRepositoryProvider).currentUser?.id;
        if (userId != null) {
          ref.invalidate(
            projectPapersProvider((
              userId: userId,
              projectId: widget.project.id,
            )),
          );
          ref.invalidate(projectsProvider(userId));
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${paper.originalFilename} berhasil diunggah.'),
          ),
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const BrandLockup(),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 40),
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
                    label: Text(_uploading ? 'Mengunggah...' : 'Unggah PDF'),
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 210,
                      child: MetricCard(
                        icon: Icons.description_outlined,
                        label: 'Paper',
                        value: '$paperCount',
                        color: AppColors.blue,
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: MetricCard(
                        icon: Icons.fact_check_outlined,
                        label: 'Menunggu review',
                        value: '$reviewCount',
                        color: AppColors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _UploadGuidance(
                  uploading: _uploading,
                  progress: _uploadProgress,
                ),
                const SizedBox(height: 24),
                const SectionHeading(
                  title: 'Paper dalam proyek',
                  subtitle:
                      'File tersimpan privat dan hanya dapat diakses oleh pemilik proyek.',
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
                            icon: Icons.upload_file_outlined,
                            title: 'Belum ada paper dalam proyek ini',
                            message:
                                'Unggah PDF pertama. Ukuran maksimal 50 MB dan file harus memiliki isi PDF yang valid.',
                            action: FilledButton.icon(
                              onPressed: _uploading ? null : _uploadPdf,
                              icon: const Icon(Icons.upload_file_rounded),
                              label: const Text('Pilih PDF'),
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            for (final paper in items) ...[
                              _PaperTile(
                                paper: paper,
                                onOpenResult: () =>
                                    Navigator.of(context).push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => PaperResultScreen(
                                          projectId: project.id,
                                          paperId: paper.id,
                                        ),
                                      ),
                                    ),
                                onProcess: paper.canStartProcessing
                                    ? () => _processPaper(paper)
                                    : null,
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
      ),
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
  });

  final ProjectPaper paper;
  final VoidCallback onOpenResult;
  final VoidCallback? onProcess;

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
              ],
            ),
          ],
        ),
      ),
    );
  }
}
