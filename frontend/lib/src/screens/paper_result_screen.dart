import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/paper_result_repository.dart';
import '../models/research_models.dart';
import '../platform/download_file.dart';
import '../theme/app_theme.dart';

class PaperResultScreen extends ConsumerStatefulWidget {
  const PaperResultScreen({
    required this.projectId,
    required this.paperId,
    this.initialPage = 1,
    this.initialHighlightText,
    this.initialBlockId,
    super.key,
  });
  final String projectId;
  final String paperId;
  final int initialPage;
  final String? initialHighlightText;
  final String? initialBlockId;

  @override
  ConsumerState<PaperResultScreen> createState() => _PaperResultScreenState();
}

class _PaperResultScreenState extends ConsumerState<PaperResultScreen>
    with SingleTickerProviderStateMixin {
  final _pdfController = PdfViewerController();
  late final TabController _tabController;
  late int _targetPage;
  bool _downloadingTables = false;

  @override
  void initState() {
    super.initState();
    _targetPage = widget.initialPage;
    _tabController = TabController(
      length: 2,
      initialIndex: widget.initialHighlightText?.trim().isNotEmpty == true
          ? 1
          : 0,
      vsync: this,
    );
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

  Future<void> _downloadStructuredTables() async {
    if (_downloadingTables) return;
    setState(() => _downloadingTables = true);
    try {
      final artifact = await ref
          .read(paperResultRepositoryProvider)
          .downloadStructuredTables(widget.projectId, widget.paperId);
      downloadFile(artifact.bytes, artifact.filename, 'application/pdf');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF tabel terstruktur berhasil dibuat.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF tabel belum dapat diunduh. Silakan coba lagi.'),
          backgroundColor: AppColors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _downloadingTables = false);
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
          final resultPane = _ResultPane(
            result: value,
            onEvidence: _showPage,
            onDownloadTables: _downloadStructuredTables,
            downloadingTables: _downloadingTables,
          );
          final pdfPane = _PdfPane(
            query: _query,
            controller: _pdfController,
            initialPage: _targetPage,
            highlightText: widget.initialHighlightText,
            blockId: widget.initialBlockId,
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
  const _ResultPane({
    required this.result,
    required this.onEvidence,
    required this.onDownloadTables,
    required this.downloadingTables,
  });
  final PaperResult result;
  final ValueChanged<int> onEvidence;
  final VoidCallback onDownloadTables;
  final bool downloadingTables;

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
    final narrativeParameters = parameters.entries.where(
      (entry) => entry.key != 'research_question' && entry.key != 'methodology',
    );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              key: const Key('download-structured-tables-pdf'),
              onPressed: downloadingTables ? null : onDownloadTables,
              icon: downloadingTables
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: Text(downloadingTables ? 'Membuat...' : 'Unduh tabel PDF'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _ResearchQuestionTable(
          rows: result.structuredTables.researchQuestions,
          onEvidence: onEvidence,
        ),
        const SizedBox(height: 12),
        _MethodologyTable(rows: result.structuredTables.methodology),
        const SizedBox(height: 20),
        Text(
          'Hasil naratif dan evidence',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        for (final entry in narrativeParameters)
          _ComponentCard(
            parameter: entry.key,
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
    required this.parameter,
    required this.label,
    required this.component,
    required this.onEvidence,
  });
  final String parameter;
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
              _NarrativeValue(
                value: item.finalValue ?? item.aiValue,
                preferBullets: const {
                  'results_findings',
                  'limitations',
                  'future_work',
                  'key_claims',
                }.contains(parameter),
              ),
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

class _ResearchQuestionTable extends StatelessWidget {
  const _ResearchQuestionTable({required this.rows, required this.onEvidence});
  final List<ResearchQuestionTableRow> rows;
  final ValueChanged<int> onEvidence;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pertanyaan penelitian',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'Setiap pertanyaan disejajarkan dengan objek/konsep dan arah pembahasannya.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const Text('Pertanyaan penelitian belum tersedia.')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                key: const Key('research-question-table'),
                dataRowMinHeight: 72,
                dataRowMaxHeight: 180,
                headingRowColor: WidgetStateProperty.all(AppColors.primarySoft),
                columns: const [
                  DataColumn(label: Text('No')),
                  DataColumn(
                    label: SizedBox(width: 260, child: Text('Pertanyaan')),
                  ),
                  DataColumn(
                    label: SizedBox(width: 220, child: Text('Objek / konsep')),
                  ),
                  DataColumn(
                    label: SizedBox(width: 240, child: Text('Arah pembahasan')),
                  ),
                  DataColumn(label: Text('Evidence')),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      cells: [
                        DataCell(Text('${row.number}')),
                        DataCell(
                          SizedBox(width: 260, child: Text(row.question)),
                        ),
                        DataCell(
                          SizedBox(width: 220, child: Text(row.relatedObject)),
                        ),
                        DataCell(
                          SizedBox(
                            width: 240,
                            child: Text(row.discussionDirection),
                          ),
                        ),
                        DataCell(
                          row.evidencePage == null
                              ? const Text('-')
                              : TextButton(
                                  onPressed: () =>
                                      onEvidence(row.evidencePage!),
                                  child: Text('Hal. ${row.evidencePage}'),
                                ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _MethodologyTable extends StatelessWidget {
  const _MethodologyTable({required this.rows});
  final List<MethodologyTableRow> rows;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Metodologi', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Lima komponen utama ditampilkan dalam satu pandangan.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const Text('Metodologi belum tersedia.')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                key: const Key('methodology-table'),
                dataRowMinHeight: 96,
                dataRowMaxHeight: 240,
                headingRowColor: WidgetStateProperty.all(AppColors.primarySoft),
                columns: const [
                  DataColumn(label: SizedBox(width: 230, child: Text('Isi'))),
                  DataColumn(
                    label: SizedBox(width: 150, child: Text('Bentuk')),
                  ),
                  DataColumn(
                    label: SizedBox(width: 220, child: Text('Kegiatan utama')),
                  ),
                  DataColumn(
                    label: SizedBox(width: 220, child: Text('Arah kegiatan')),
                  ),
                  DataColumn(
                    label: SizedBox(width: 220, child: Text('Tujuan akhir')),
                  ),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      cells: [
                        DataCell(
                          SizedBox(width: 230, child: Text(row.content)),
                        ),
                        DataCell(SizedBox(width: 150, child: Text(row.form))),
                        DataCell(
                          SizedBox(width: 220, child: Text(row.mainActivity)),
                        ),
                        DataCell(
                          SizedBox(
                            width: 220,
                            child: Text(row.activityDirection),
                          ),
                        ),
                        DataCell(
                          SizedBox(width: 220, child: Text(row.finalGoal)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _NarrativeValue extends StatelessWidget {
  const _NarrativeValue({required this.value, required this.preferBullets});
  final String value;
  final bool preferBullets;

  @override
  Widget build(BuildContext context) {
    final items = value
        .split(RegExp(r'\n+|\s*;\s*'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (!preferBullets || items.length < 2) return Text(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: Text(item)),
              ],
            ),
          ),
      ],
    );
  }
}

class _PdfPane extends ConsumerWidget {
  const _PdfPane({
    required this.query,
    required this.controller,
    required this.initialPage,
    required this.highlightText,
    required this.blockId,
  });
  final PaperResultQuery query;
  final PdfViewerController controller;
  final int initialPage;
  final String? highlightText;
  final String? blockId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evidenceBlockId = blockId?.trim();
    if (evidenceBlockId != null && evidenceBlockId.isNotEmpty) {
      final previewQuery = (
        projectId: query.projectId,
        paperId: query.paperId,
        blockId: evidenceBlockId,
      );
      return ref
          .watch(evidencePreviewProvider(previewQuery))
          .when(
            loading: () => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('Membuka halaman evidence…'),
                ],
              ),
            ),
            error: (error, _) => _Failure(
              onRetry: () =>
                  ref.invalidate(evidencePreviewProvider(previewQuery)),
            ),
            data: (bytes) => ColoredBox(
              color: AppColors.canvas,
              child: InteractiveViewer(
                minScale: 0.7,
                maxScale: 5,
                child: Center(
                  child: Image.memory(
                    bytes,
                    key: const Key('evidence-page-preview'),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          );
    }
    return ref
        .watch(paperPdfProvider(query))
        .when(
          loading: () => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text('Mengunduh PDF privat…'),
              ],
            ),
          ),
          error: (error, _) =>
              _Failure(onRetry: () => ref.invalidate(paperPdfProvider(query))),
          data: (bytes) => _PdfDocumentViewer(
            bytes: bytes,
            paperId: query.paperId,
            controller: controller,
            initialPage: initialPage,
            highlightText: highlightText,
          ),
        );
  }
}

class _PdfDocumentViewer extends StatefulWidget {
  const _PdfDocumentViewer({
    required this.bytes,
    required this.paperId,
    required this.controller,
    required this.initialPage,
    required this.highlightText,
  });

  final Uint8List bytes;
  final String paperId;
  final PdfViewerController controller;
  final int initialPage;
  final String? highlightText;

  @override
  State<_PdfDocumentViewer> createState() => _PdfDocumentViewerState();
}

class _PdfDocumentViewerState extends State<_PdfDocumentViewer> {
  bool _ready = false;
  PdfTextSearcher? _textSearcher;
  bool _highlightStarted = false;
  bool _highlightFound = false;
  bool _highlightFinished = false;
  PdfPageTextRange? _highlightMatch;

  @override
  void dispose() {
    _textSearcher?.dispose();
    super.dispose();
  }

  Future<void> _highlightCitation() async {
    final quote = widget.highlightText?.trim();
    if (quote == null || quote.isEmpty || _highlightStarted) return;
    _highlightStarted = true;
    final searcher = _textSearcher;
    if (searcher == null) return;
    final pageText = await searcher.loadText(pageNumber: widget.initialPage);
    if (!mounted || pageText == null) return;
    final pattern = buildPdfHighlightPattern(pageText.fullText, quote);
    if (pattern == null) {
      setState(() => _highlightFinished = true);
      return;
    }
    await for (final match in pageText.allMatches(
      pattern,
      caseInsensitive: true,
    )) {
      if (!mounted) return;
      _highlightMatch = match;
      setState(() {
        _highlightFound = true;
        _highlightFinished = true;
      });
      await searcher.goToMatch(match);
      widget.controller.invalidate();
      return;
    }
    if (mounted) setState(() => _highlightFinished = true);
  }

  void _paintCitationHighlight(Canvas canvas, Rect pageRect, PdfPage page) {
    final match = _highlightMatch;
    if (match == null || match.pageNumber != page.pageNumber) return;
    final rect = match.bounds
        .toRect(page: page, scaledPageSize: pageRect.size)
        .translate(pageRect.left, pageRect.top);
    canvas.drawRect(rect, Paint()..color = Colors.amber.withAlpha(180));
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: PdfViewer.data(
          widget.bytes,
          sourceName: 'private-paper-${widget.paperId}.pdf',
          controller: widget.controller,
          initialPageNumber: widget.initialPage,
          params: PdfViewerParams(
            matchTextColor: Colors.yellow.withAlpha(150),
            activeMatchTextColor: Colors.amber.withAlpha(190),
            pagePaintCallbacks: [_paintCitationHighlight],
            onViewerReady: (_, readyController) {
              if (readyController.pageNumber != widget.initialPage) {
                readyController.goToPage(pageNumber: widget.initialPage);
              }
              _textSearcher ??= PdfTextSearcher(widget.controller);
              if (mounted) {
                setState(() => _ready = true);
                _highlightCitation();
              }
            },
          ),
        ),
      ),
      if (!_ready)
        const Positioned.fill(
          child: ColoredBox(
            color: AppColors.canvas,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('Menyiapkan PDF privat…'),
                ],
              ),
            ),
          ),
        ),
      if (_ready && widget.highlightText?.trim().isNotEmpty == true)
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(190),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Text(
                    _highlightFound
                        ? 'Evidence disorot pada halaman ${widget.initialPage}'
                        : _highlightFinished
                        ? 'Halaman ${widget.initialPage} dibuka; teks evidence tidak dapat dicocokkan tepat'
                        : 'Mencari evidence pada halaman ${widget.initialPage}…',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

@visibleForTesting
RegExp? buildPdfHighlightPattern(String pageText, String quote) {
  final wordPattern = RegExp(r'[A-Za-z0-9]+');
  final pageWords = wordPattern
      .allMatches(pageText)
      .map((match) => match.group(0)!.toLowerCase())
      .toList(growable: false);
  final quoteWords = wordPattern
      .allMatches(quote)
      .map((match) => match.group(0)!.toLowerCase())
      .toList(growable: false);
  if (pageWords.isEmpty || quoteWords.isEmpty) return null;
  final pageNormalized = pageWords.join(' ');
  final maxWindow = quoteWords.length.clamp(1, 18);
  for (var size = maxWindow; size >= 4; size--) {
    for (var start = 0; start + size <= quoteWords.length; start++) {
      final words = quoteWords.sublist(start, start + size);
      if (!pageNormalized.contains(words.join(' '))) continue;
      return RegExp(
        words.map(RegExp.escape).join(r'[^A-Za-z0-9]+'),
        caseSensitive: false,
      );
    }
  }
  return null;
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
