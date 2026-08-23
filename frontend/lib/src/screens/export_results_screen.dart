import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/export_repository.dart';
import '../models/research_models.dart';
import '../platform/download_file.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

typedef ExportFileSaver = void Function(ExportDownload download);
typedef ExportLoader = Future<ExportDownload> Function(String format);

class ExportResultsScreen extends ConsumerStatefulWidget {
  const ExportResultsScreen({
    required this.project,
    this.fileSaver,
    this.exportLoader,
    super.key,
  });

  final ResearchProject project;
  final ExportFileSaver? fileSaver;
  final ExportLoader? exportLoader;

  @override
  ConsumerState<ExportResultsScreen> createState() =>
      _ExportResultsScreenState();
}

class _ExportResultsScreenState extends ConsumerState<ExportResultsScreen> {
  String? _activeFormat;

  Future<void> _export(_ExportOption option) async {
    if (_activeFormat != null) return;
    setState(() => _activeFormat = option.format);
    try {
      final loader = widget.exportLoader;
      final result = loader != null
          ? await loader(option.format)
          : await ref
                .read(exportRepositoryProvider)
                .exportProject(
                  projectId: widget.project.id,
                  format: option.format,
                );
      if (!mounted) return;
      final saver = widget.fileSaver;
      if (saver != null) {
        saver(result);
      } else {
        downloadFile(result.bytes, result.filename, result.mediaType);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.filename} berhasil diunduh.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ExportRepository.readableError(error)),
          backgroundColor: AppColors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _activeFormat = null);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeading(
                  title: 'Ekspor hasil',
                  subtitle:
                      'Unduh hasil review “${widget.project.title}” beserta evidence yang dapat ditelusuri.',
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 13),
                      Expanded(
                        child: Text(
                          'Hanya paper berstatus siap yang diekspor. Nilai hasil review, nilai AI asli, status, confidence, kutipan, halaman, block ID, dan paper ID tetap disertakan.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth >= 720
                        ? (constraints.maxWidth - 16) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final option in _options)
                          SizedBox(
                            width: width,
                            child: _ExportCard(
                              option: option,
                              loading: _activeFormat == option.format,
                              disabled: _activeFormat != null,
                              onPressed: () => _export(option),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({
    required this.option,
    required this.loading,
    required this.disabled,
    required this.onPressed,
  });

  final _ExportOption option;
  final bool loading;
  final bool disabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: option.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(option.icon, color: option.color),
            ),
            const SizedBox(height: 15),
            Text(option.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(option.description),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: Key('export-${option.format}-button'),
                onPressed: disabled ? null : onPressed,
                icon: loading
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(
                  loading ? 'Menyiapkan...' : 'Unduh ${option.extension}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportOption {
  const _ExportOption({
    required this.format,
    required this.extension,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String format;
  final String extension;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
}

const _options = <_ExportOption>[
  _ExportOption(
    format: 'docx',
    extension: 'Word',
    title: 'Laporan Word',
    description:
        'Dokumen terstruktur per paper dan parameter untuk penyuntingan lanjutan.',
    icon: Icons.description_outlined,
    color: AppColors.blue,
  ),
  _ExportOption(
    format: 'xlsx',
    extension: 'Excel',
    title: 'Workbook Excel',
    description:
        'Tabel siap filter dengan nilai reviewed, AI asli, status, dan evidence.',
    icon: Icons.table_view_outlined,
    color: AppColors.green,
  ),
  _ExportOption(
    format: 'csv',
    extension: 'CSV',
    title: 'Data CSV',
    description:
        'Data UTF-8 portabel untuk statistik, coding, dan alat analisis lain.',
    icon: Icons.data_object_rounded,
    color: AppColors.orange,
  ),
  _ExportOption(
    format: 'pptx',
    extension: 'PowerPoint',
    title: 'Presentasi PowerPoint',
    description:
        'Slide ringkas siap presentasi dengan konteks evidence di setiap bagian.',
    icon: Icons.slideshow_outlined,
    color: AppColors.red,
  ),
];
