import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/comparative_matrix_repository.dart';
import '../data/project_repository.dart';
import '../models/research_models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'paper_result_screen.dart';

class ComparativeMatrixScreen extends ConsumerStatefulWidget {
  const ComparativeMatrixScreen({required this.userId, super.key});
  final String userId;
  @override
  ConsumerState<ComparativeMatrixScreen> createState() =>
      _ComparativeMatrixScreenState();
}

class _ComparativeMatrixScreenState
    extends ConsumerState<ComparativeMatrixScreen> {
  String? _projectId;

  static const labels = <String, String>{
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
    final projects = ref.watch(projectsProvider(widget.userId));
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
        children: [
          const PageHeading(
            title: 'Comparative Paper Matrix',
            subtitle:
                'Bandingkan hasil yang sudah direview tanpa memutus evidence ke PDF asli.',
          ),
          const SizedBox(height: 20),
          projects.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => const _MatrixMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Proyek belum dapat dimuat',
              message: 'Periksa layanan lokal lalu coba lagi.',
            ),
            data: (items) {
              if (items.isEmpty) {
                return const _MatrixMessage(
                  icon: Icons.folder_off_outlined,
                  title: 'Belum ada proyek',
                  message:
                      'Buat proyek dan selesaikan review minimal dua paper.',
                );
              }
              _projectId ??= items.first.id;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _projectId,
                    decoration: const InputDecoration(
                      labelText: 'Pilih proyek',
                    ),
                    items: [
                      for (final project in items)
                        DropdownMenuItem(
                          value: project.id,
                          child: Text(project.title),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _projectId = value;
                    }),
                  ),
                  const SizedBox(height: 20),
                  if (_projectId != null)
                    _matrix(ref.watch(comparativeMatrixProvider(_projectId!))),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _matrix(AsyncValue<ComparativeMatrix> matrix) => matrix.when(
    loading: () => const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: CircularProgressIndicator(),
      ),
    ),
    error: (error, _) => _MatrixMessage(
      icon: Icons.error_outline_rounded,
      title: 'Matrix belum dapat dimuat',
      message: 'Coba muat ulang data proyek.',
      action: FilledButton(
        onPressed: () => ref.invalidate(comparativeMatrixProvider(_projectId!)),
        child: const Text('Coba lagi'),
      ),
    ),
    data: (value) {
      if (value.papers.length < 2) {
        return const _MatrixMessage(
          icon: Icons.table_chart_outlined,
          title: 'Minimal dua paper siap diperlukan',
          message:
              'Matrix hanya memasukkan paper yang seluruh komponennya sudah direview.',
        );
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                const _MatrixSwipeNotice(),
                const SizedBox(height: 10),
              ],
              _combinedMatrix(value, compact: compact),
            ],
          );
        },
      );
    },
  );

  Widget _combinedMatrix(ComparativeMatrix matrix, {required bool compact}) =>
      Card(
        key: const Key('combined-matrix-table'),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            dataRowMinHeight: 96,
            dataRowMaxHeight: 180,
            headingRowColor: WidgetStateProperty.all(AppColors.primarySoft),
            columns: [
              const DataColumn(
                label: SizedBox(width: 170, child: Text('Parameter')),
              ),
              for (final paper in matrix.papers)
                DataColumn(
                  label: SizedBox(
                    width: compact ? 220 : 260,
                    child: Text(
                      paper.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
            rows: [
              for (final row in matrix.rows)
                DataRow(
                  cells: [
                    DataCell(
                      Text(
                        labels[row.parameter] ?? row.parameter,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    for (final paper in matrix.papers)
                      DataCell(
                        _cell(
                          matrix,
                          paper,
                          row.cellFor(paper.id),
                          width: compact ? 220 : 260,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      );

  Widget _cell(
    ComparativeMatrix matrix,
    MatrixPaper paper,
    MatrixCell? cell, {
    required double width,
  }) {
    if (cell == null)
      return const Text(
        'Tidak tersedia',
        style: TextStyle(color: AppColors.muted),
      );
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(cell.displayValue, maxLines: 5, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Text(
            cell.status == VerificationStatus.edited
                ? 'Diedit reviewer'
                : 'Terverifikasi',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.green,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (cell.evidence.isNotEmpty)
            TextButton.icon(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => PaperResultScreen(
                    projectId: matrix.projectId,
                    paperId: paper.id,
                    initialPage: cell.evidence.first.pageNumber,
                  ),
                ),
              ),
              icon: const Icon(Icons.link_rounded, size: 17),
              label: Text('Evidence · hal. ${cell.evidence.first.pageNumber}'),
            ),
        ],
      ),
    );
  }
}

class _MatrixSwipeNotice extends StatelessWidget {
  const _MatrixSwipeNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(
      children: [
        Icon(Icons.swipe_rounded, color: AppColors.primary),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Semua paper sudah digabung dalam satu matrix. Geser tabel ke samping untuk membandingkan kolom paper.',
          ),
        ),
      ],
    ),
  );
}

class _MatrixMessage extends StatelessWidget {
  const _MatrixMessage({
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
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(icon, size: 42, color: AppColors.muted),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    ),
  );
}
