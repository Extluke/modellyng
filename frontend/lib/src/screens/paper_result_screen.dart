import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/paper_result_repository.dart';
import '../models/research_models.dart';
import '../theme/app_theme.dart';

class PaperResultScreen extends ConsumerStatefulWidget {
  const PaperResultScreen({
    required this.projectId,
    required this.paperId,
    this.initialPage = 1,
    super.key,
  });
  final String projectId;
  final String paperId;
  final int initialPage;

  @override
  ConsumerState<PaperResultScreen> createState() => _PaperResultScreenState();
}

class _PaperResultScreenState extends ConsumerState<PaperResultScreen>
    with SingleTickerProviderStateMixin {
  final _pdfController = PdfViewerController();
  late final TabController _tabController;
  late int _targetPage;

  @override
  void initState() {
    super.initState();
    _targetPage = widget.initialPage;
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  PaperResultQuery get _query =>
      (projectId: widget.projectId, paperId: widget.paperId);

  void _showPage(int page) {
    setState(() => _targetPage = page);
    _tabController.animateTo(1);
    if (_pdfController.isReady) {
      _pdfController.goToPage(pageNumber: page);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(paperResultProvider(_query));
    return Scaffold(
      appBar: AppBar(title: const Text('Hasil paper dan evidence')),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Failure(
          onRetry: () => ref.invalidate(paperResultProvider(_query)),
        ),
        data: (value) {
          if (value.paper.isProcessing) {
            return const _Message(
              icon: Icons.hourglass_top_rounded,
              title: 'Paper masih diproses',
              message: 'Hasil terstruktur tersedia setelah ekstraksi selesai.',
            );
          }
          if (value.paper.status == PaperStatus.failed) {
            return _Message(
              icon: Icons.error_outline_rounded,
              title: 'Analisis paper gagal',
              message:
                  value.paper.processingError ?? 'Silakan proses ulang paper.',
            );
          }
          final resultPane = _ResultPane(result: value, onEvidence: _showPage);
          final pdfPane = _PdfPane(
            query: _query,
            controller: _pdfController,
            initialPage: _targetPage,
          );
          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 1050) {
                return Row(
                  children: [
                    Expanded(child: resultPane),
                    Expanded(child: pdfPane),
                  ],
                );
              }
              return DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      controller: _tabController,
                      tabs: const [
                        Tab(text: 'Hasil'),
                        Tab(text: 'PDF evidence'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [resultPane, pdfPane],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ResultPane extends StatelessWidget {
  const _ResultPane({required this.result, required this.onEvidence});
  final PaperResult result;
  final ValueChanged<int> onEvidence;

  static const parameters = <String, String>{
    'research_problem': 'Masalah penelitian',
    'research_objective': 'Tujuan penelitian',
    'research_question': 'Pertanyaan penelitian',
    'methodology': 'Metodologi',
    'dataset_sample': 'Dataset atau sampel',
    'variables_concepts': 'Variabel dan konsep',
    'results_findings': 'Hasil dan temuan',
    'contribution': 'Kontribusi',
    'limitations': 'Keterbatasan',
    'future_work': 'Penelitian berikutnya',
    'key_claims': 'Klaim utama',
  };

  @override
  Widget build(BuildContext context) {
    final byParameter = {
      for (final item in result.components) item.parameter: item,
    };
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          result.paper.title ?? result.paper.originalFilename,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          '${result.components.length}/11 komponen tersedia',
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 20),
        for (final entry in parameters.entries)
          _ComponentCard(
            label: entry.value,
            component: byParameter[entry.key],
            onEvidence: onEvidence,
          ),
      ],
    );
  }
}

class _ComponentCard extends StatelessWidget {
  const _ComponentCard({
    required this.label,
    required this.component,
    required this.onEvidence,
  });
  final String label;
  final PaperComponentResult? component;
  final ValueChanged<int> onEvidence;

  @override
  Widget build(BuildContext context) {
    final item = component;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (item == null)
              const Text(
                'Belum ada hasil untuk komponen ini.',
                style: TextStyle(color: AppColors.muted),
              )
            else ...[
              Text(item.finalValue ?? item.aiValue),
              if (item.finalValue != null &&
                  item.finalValue != item.aiValue) ...[
                const SizedBox(height: 8),
                Text(
                  'Nilai AI asli: ${item.aiValue}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  Chip(label: Text(item.status.name)),
                  if (item.confidence != null)
                    Chip(
                      label: Text(
                        'Confidence ${(item.confidence! * 100).round()}%',
                      ),
                    ),
                ],
              ),
              for (final evidence in item.evidence)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.link_rounded,
                    color: AppColors.primary,
                  ),
                  title: Text('Halaman ${evidence.pageNumber}'),
                  subtitle: Text('“${evidence.quote}”'),
                  onTap: () => onEvidence(evidence.pageNumber),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PdfPane extends ConsumerWidget {
  const _PdfPane({
    required this.query,
    required this.controller,
    required this.initialPage,
  });
  final PaperResultQuery query;
  final PdfViewerController controller;
  final int initialPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(paperPdfProvider(query))
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            _Failure(onRetry: () => ref.invalidate(paperPdfProvider(query))),
        data: (bytes) => PdfViewer.data(
          bytes,
          sourceName: 'private-paper.pdf',
          controller: controller,
          initialPageNumber: initialPage,
          params: PdfViewerParams(
            onViewerReady: (_, readyController) {
              if (readyController.pageNumber != initialPage) {
                readyController.goToPage(pageNumber: initialPage);
              }
            },
          ),
        ),
      );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => _Message(
    icon: Icons.cloud_off_outlined,
    title: 'Data belum dapat dimuat',
    message: 'Periksa koneksi layanan lokal lalu coba lagi.',
    action: FilledButton(onPressed: onRetry, child: const Text('Coba lagi')),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}
