import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../models/research_models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class ProjectWorkspaceScreen extends StatelessWidget {
  const ProjectWorkspaceScreen({required this.project, super.key});

  final ResearchProject project;

  static const _tabs = [
    Tab(text: 'Overview', icon: Icon(Icons.dashboard_outlined, size: 18)),
    Tab(text: 'Papers', icon: Icon(Icons.description_outlined, size: 18)),
    Tab(text: 'Structured', icon: Icon(Icons.account_tree_outlined, size: 18)),
    Tab(text: 'Compare', icon: Icon(Icons.table_chart_outlined, size: 18)),
    Tab(text: 'Gap Map', icon: Icon(Icons.hub_outlined, size: 18)),
    Tab(text: 'Review', icon: Icon(Icons.fact_check_outlined, size: 18)),
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                project.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${project.paperCount} paper · ${project.updatedLabel}',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Ekspor',
              onPressed: () => _showExport(context),
              icon: const Icon(Icons.ios_share_outlined),
            ),
            IconButton(
              tooltip: 'Pengaturan proyek',
              onPressed: () {},
              icon: const Icon(Icons.more_vert_rounded),
            ),
            const SizedBox(width: 6),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(50),
            child: Column(
              children: [
                Divider(height: 1),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    dividerHeight: 0,
                    tabs: _tabs,
                  ),
                ),
              ],
            ),
          ),
        ),
        body: const TabBarView(
          children: [
            _OverviewTab(),
            _PapersTab(),
            _StructuredTab(),
            _CompareTab(),
            _GapMapTab(),
            _WorkspaceReviewTab(),
          ],
        ),
      ),
    );
  }

  void _showExport(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ekspor hasil', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Hanya hasil terverifikasi yang disertakan secara default.',
            ),
            const SizedBox(height: 14),
            const ListTile(
              leading: Icon(Icons.table_view_outlined, color: AppColors.green),
              title: Text('Comparative Matrix (.csv)'),
              trailing: Icon(Icons.download_rounded),
            ),
            const ListTile(
              leading: Icon(
                Icons.picture_as_pdf_outlined,
                color: AppColors.red,
              ),
              title: Text('Traceability Report (.pdf)'),
              trailing: Icon(Icons.download_rounded),
            ),
            const ListTile(
              leading: Icon(Icons.data_object_rounded, color: AppColors.blue),
              title: Text('Structured Data (.json)'),
              trailing: Icon(Icons.download_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspacePage extends StatelessWidget {
  const _WorkspacePage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 44),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: child,
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context) {
    return _WorkspacePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            title: 'Ringkasan proyek',
            subtitle:
                'Pantau kualitas data, progres analisis, dan keputusan yang masih diperlukan.',
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 780
                  ? 3
                  : constraints.maxWidth >= 520
                  ? 2
                  : 1;
              const spacing = 12.0;
              final width =
                  (constraints.maxWidth - (columns - 1) * spacing) / columns;
              const metrics = [
                MetricCard(
                  icon: Icons.description_outlined,
                  label: 'Paper',
                  value: '14',
                  color: AppColors.blue,
                ),
                MetricCard(
                  icon: Icons.schema_outlined,
                  label: 'Komponen diekstrak',
                  value: '132',
                  color: AppColors.primary,
                ),
                MetricCard(
                  icon: Icons.fact_check_outlined,
                  label: 'Terverifikasi',
                  value: '89%',
                  color: AppColors.green,
                ),
              ];
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final item in metrics)
                    SizedBox(width: width, child: item),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              const progress = _AnalysisProgressCard();
              const quality = _QualityCard();
              if (constraints.maxWidth < 760)
                return const Column(
                  children: [progress, const SizedBox(height: 14), quality],
                );
              return const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: progress),
                  const SizedBox(width: 14),
                  Expanded(flex: 2, child: quality),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          const SectionHeading(
            title: 'Insight awal',
            subtitle: 'Ringkasan ini belum menggantikan verifikasi evidence.',
          ),
          const SizedBox(height: 12),
          const _InsightCard(
            icon: Icons.auto_awesome_outlined,
            color: AppColors.primary,
            title: 'Pola yang dominan',
            text:
                'Sebagian besar studi menilai solusi berbasis alam untuk mitigasi panas dan banjir, tetapi memakai metrik keberhasilan yang berbeda.',
          ),
          const SizedBox(height: 10),
          const _InsightCard(
            icon: Icons.warning_amber_rounded,
            color: AppColors.orange,
            title: 'Area yang perlu diperiksa',
            text:
                'Dua paper memiliki metadata DOI yang belum cocok dengan judul pada file sumber.',
          ),
        ],
      ),
    );
  }
}

class _AnalysisProgressCard extends StatelessWidget {
  const _AnalysisProgressCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pipeline analisis',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 18),
            const _PipelineStep(
              label: 'Validasi file & metadata',
              detail: '14 dari 14 paper',
              status: _PipelineStatus.done,
            ),
            const _PipelineStep(
              label: 'Ekstraksi struktur',
              detail: '14 dari 14 paper',
              status: _PipelineStatus.done,
            ),
            const _PipelineStep(
              label: 'Claim–evidence matching',
              detail: '13 dari 14 paper',
              status: _PipelineStatus.active,
            ),
            const _PipelineStep(
              label: 'Comparative synthesis',
              detail: 'Menunggu evidence',
              status: _PipelineStatus.waiting,
            ),
            const _PipelineStep(
              label: 'Candidate gap detection',
              detail: 'Menunggu synthesis',
              status: _PipelineStatus.waiting,
              last: true,
            ),
          ],
        ),
      ),
    );
  }
}

enum _PipelineStatus { done, active, waiting }

class _PipelineStep extends StatelessWidget {
  const _PipelineStep({
    required this.label,
    required this.detail,
    required this.status,
    this.last = false,
  });

  final String label;
  final String detail;
  final _PipelineStatus status;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      _PipelineStatus.done => AppColors.green,
      _PipelineStatus.active => AppColors.primary,
      _PipelineStatus.waiting => AppColors.border,
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Column(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                  child: status == _PipelineStatus.done
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 14,
                        )
                      : status == _PipelineStatus.active
                      ? const Padding(
                          padding: EdgeInsets.all(5),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: color.withValues(alpha: 0.35),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QualityCard extends StatelessWidget {
  const _QualityCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kualitas evidence',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 18),
            const _QualityRow(
              label: 'Terverifikasi',
              value: 0.68,
              color: AppColors.green,
              count: '90',
            ),
            const SizedBox(height: 14),
            const _QualityRow(
              label: 'Perlu ditinjau',
              value: 0.23,
              color: AppColors.orange,
              count: '30',
            ),
            const SizedBox(height: 14),
            const _QualityRow(
              label: 'Tanpa dukungan',
              value: 0.09,
              color: AppColors.red,
              count: '12',
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.greenSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '89% claim memiliki kutipan evidence dan lokasi sumber yang lengkap.',
                style: TextStyle(
                  color: AppColors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({
    required this.label,
    required this.value,
    required this.color,
    required this.count,
  });

  final String label;
  final double value;
  final Color color;
  final String count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(count, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 7),
        LinearProgressIndicator(
          value: value,
          minHeight: 7,
          borderRadius: BorderRadius.circular(99),
          backgroundColor: AppColors.border,
          color: color,
        ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(text),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PapersTab extends StatefulWidget {
  const _PapersTab();

  @override
  State<_PapersTab> createState() => _PapersTabState();
}

class _PapersTabState extends State<_PapersTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final papers = DemoData.papers
        .where(
          (paper) => paper.title.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    return _WorkspacePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(
            title: 'Paper dalam proyek',
            subtitle:
                'Validasi status file dan metadata sebelum menggunakan hasil analisis.',
            action: FilledButton.icon(
              onPressed: () => _showAddPaper(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tambah paper'),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Cari judul atau penulis...',
            ),
          ),
          const SizedBox(height: 14),
          for (final paper in papers) ...[
            _PaperCard(paper: paper),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  void _showAddPaper(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Tambah paper', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Pilih PDF atau DOCX'),
            ),
            const SizedBox(height: 10),
            const TextField(
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.link_rounded),
                hintText: 'Atau masukkan DOI',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Validasi dan tambahkan'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaperCard extends StatelessWidget {
  const _PaperCard({required this.paper});

  final PaperRecord paper;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.redSoft,
                    borderRadius: BorderRadius.circular(9),
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
                        paper.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 5),
                      Text('${paper.authors} · ${paper.year}'),
                      const SizedBox(height: 3),
                      Text(
                        '${paper.journal} · ${paper.doi}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                StatusBadge.paper(paper.status),
                PopupMenuButton<String>(
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'open', child: Text('Buka paper')),
                    PopupMenuItem(
                      value: 'reanalyze',
                      child: Text('Analisis ulang'),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text('Hapus dari proyek'),
                    ),
                  ],
                ),
              ],
            ),
            if (paper.status == PaperStatus.processing) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: paper.progress,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(paper.progress * 100).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StructuredTab extends StatelessWidget {
  const _StructuredTab();

  @override
  Widget build(BuildContext context) {
    return _WorkspacePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            title: 'Structured Paper Model',
            subtitle:
                'Komponen penelitian disertai evidence dan lokasi sumber untuk setiap claim.',
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: DemoData.papers.first.id,
            decoration: const InputDecoration(
              labelText: 'Paper aktif',
              prefixIcon: Icon(Icons.description_outlined),
            ),
            items: [
              for (final paper in DemoData.papers)
                DropdownMenuItem(
                  value: paper.id,
                  child: Text(paper.title, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (_) {},
          ),
          const SizedBox(height: 16),
          for (final component in DemoData.components) ...[
            _ComponentCard(component: component),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _ComponentCard extends StatelessWidget {
  const _ComponentCard({required this.component});

  final ExtractedComponent component;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: component.label == 'Research Problem',
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        title: Row(
          children: [
            Expanded(
              child: Text(
                component.label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            StatusBadge.verification(component.status),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            component.value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        children: [
          const Divider(),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(component.value, style: const TextStyle(height: 1.5)),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F7FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EVIDENCE',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '“${component.evidence}”',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 9),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.location_on_outlined, size: 16),
                  label: Text(component.location),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompareTab extends StatelessWidget {
  const _CompareTab();

  @override
  Widget build(BuildContext context) {
    return _WorkspacePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(
            title: 'Comparative Paper Matrix',
            subtitle:
                'Klik lokasi evidence untuk memeriksa konteks sebelum menyimpulkan perbedaan.',
            action: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.download_outlined),
              label: const Text('Ekspor CSV'),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: const WidgetStatePropertyAll(
                    Color(0xFFF3F4F8),
                  ),
                  columnSpacing: 28,
                  dataRowMinHeight: 76,
                  dataRowMaxHeight: 126,
                  columns: const [
                    DataColumn(
                      label: SizedBox(width: 150, child: Text('Parameter')),
                    ),
                    DataColumn(
                      label: SizedBox(width: 240, child: Text('Paper A')),
                    ),
                    DataColumn(
                      label: SizedBox(width: 240, child: Text('Paper B')),
                    ),
                    DataColumn(
                      label: SizedBox(width: 240, child: Text('Paper C')),
                    ),
                  ],
                  rows: const [
                    DataRow(
                      cells: [
                        DataCell(_MatrixLabel('Research Problem')),
                        DataCell(
                          _MatrixCell(
                            'Fragmentasi evaluasi strategi adaptasi lintas risiko.',
                            'Hal. 2',
                          ),
                        ),
                        DataCell(
                          _MatrixCell(
                            'Model risiko banjir sulit dipindahkan antarwilayah.',
                            'Hal. 3',
                          ),
                        ),
                        DataCell(
                          _MatrixCell(
                            'Ketimpangan paparan panas belum terpetakan.',
                            'Hal. 2',
                          ),
                        ),
                      ],
                    ),
                    DataRow(
                      cells: [
                        DataCell(_MatrixLabel('Methodology')),
                        DataCell(
                          _MatrixCell('Systematic review · PRISMA', 'Hal. 4'),
                        ),
                        DataCell(
                          _MatrixCell('Spatiotemporal ML model', 'Hal. 5'),
                        ),
                        DataCell(
                          _MatrixCell(
                            'Mixed-method spatial analysis',
                            'Hal. 6',
                          ),
                        ),
                      ],
                    ),
                    DataRow(
                      cells: [
                        DataCell(_MatrixLabel('Dataset / Sample')),
                        DataCell(
                          _MatrixCell('86 studi peer-reviewed', 'Hal. 5'),
                        ),
                        DataCell(
                          _MatrixCell(
                            '12 tahun data banjir · 4 kota',
                            'Hal. 7',
                          ),
                        ),
                        DataCell(
                          _MatrixCell('28 distrik · 1.240 responden', 'Hal. 8'),
                        ),
                      ],
                    ),
                    DataRow(
                      cells: [
                        DataCell(_MatrixLabel('Limitations')),
                        DataCell(
                          _MatrixCell(
                            'Metrik heterogen; studi longitudinal terbatas.',
                            'Hal. 15',
                          ),
                        ),
                        DataCell(
                          _MatrixCell(
                            'Ketergantungan pada kualitas sensor.',
                            'Hal. 13',
                          ),
                        ),
                        DataCell(
                          _MatrixCell(
                            'Generalisasi di luar kota besar terbatas.',
                            'Hal. 14',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _InsightCard(
            icon: Icons.auto_awesome_outlined,
            color: AppColors.primary,
            title: 'AI comparative synthesis',
            text:
                'Ketiga paper menangani ketahanan kota dari skala berbeda—literatur, sistem, dan populasi. Perbedaan metrik serta konteks wilayah menjadi hambatan utama untuk sintesis kuantitatif langsung.',
          ),
        ],
      ),
    );
  }
}

class _MatrixLabel extends StatelessWidget {
  const _MatrixLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontWeight: FontWeight.w800));
}

class _MatrixCell extends StatelessWidget {
  const _MatrixCell(this.text, this.location);
  final String text;
  final String location;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 5),
          Text(
            location,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _GapMapTab extends StatefulWidget {
  const _GapMapTab();

  @override
  State<_GapMapTab> createState() => _GapMapTabState();
}

class _GapMapTabState extends State<_GapMapTab> {
  bool _showPapers = true;
  bool _showConcepts = true;

  @override
  Widget build(BuildContext context) {
    return _WorkspacePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            title: 'Research Gap & Concept Map',
            subtitle:
                'Gap ditampilkan sebagai kandidat sampai evidence dan hubungan konsep diverifikasi manusia.',
          ),
          const SizedBox(height: 18),
          Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        label: const Text('Paper'),
                        selected: _showPapers,
                        onSelected: (value) =>
                            setState(() => _showPapers = value),
                      ),
                      FilterChip(
                        label: const Text('Concept'),
                        selected: _showConcepts,
                        onSelected: (value) =>
                            setState(() => _showConcepts = value),
                      ),
                      const FilterChip(
                        label: Text('Method'),
                        selected: true,
                        onSelected: null,
                      ),
                      const FilterChip(
                        label: Text('Candidate Gap'),
                        selected: true,
                        onSelected: null,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                SizedBox(
                  height: 430,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _ResearchMapPainter(
                      showPapers: _showPapers,
                      showConcepts: _showConcepts,
                    ),
                    child: const Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Text(
                          'Prototype map · pinch/zoom pada iterasi graph interaktif',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionHeading(
            title: 'Kandidat research gap',
            subtitle:
                'Diurutkan berdasarkan kekuatan evidence, bukan sekadar confidence AI.',
          ),
          const SizedBox(height: 12),
          for (final gap in DemoData.gaps) ...[
            _GapCard(gap: gap),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _GapCard extends StatelessWidget {
  const _GapCard({required this.gap});

  final ResearchGap gap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    gap.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const StatusBadge(
                  label: 'Kandidat',
                  color: AppColors.orange,
                  background: AppColors.orangeSoft,
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(gap.description),
            const SizedBox(height: 13),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                Text(
                  gap.type,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${gap.supportingPapers} supporting papers',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'Evidence strength ${(gap.confidence * 100).round()}%',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: gap.confidence,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(99),
                    color: AppColors.orange,
                    backgroundColor: AppColors.orangeSoft,
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () {},
                  child: const Text('Periksa evidence'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResearchMapPainter extends CustomPainter {
  _ResearchMapPainter({required this.showPapers, required this.showConcepts});

  final bool showPapers;
  final bool showConcepts;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFFFCFCFE);
    canvas.drawRect(Offset.zero & size, background);

    final center = Offset(size.width * 0.5, size.height * 0.48);
    final paperNodes = [
      Offset(size.width * 0.15, size.height * 0.23),
      Offset(size.width * 0.15, size.height * 0.67),
      Offset(size.width * 0.35, size.height * 0.82),
    ];
    final conceptNodes = [
      Offset(size.width * 0.42, size.height * 0.18),
      Offset(size.width * 0.56, size.height * 0.69),
      Offset(size.width * 0.7, size.height * 0.27),
    ];
    final gapNodes = [
      Offset(size.width * 0.84, size.height * 0.47),
      Offset(size.width * 0.78, size.height * 0.78),
    ];

    final line = Paint()
      ..color = const Color(0xFFCBD0DE)
      ..strokeWidth = 1.5;
    if (showPapers) {
      for (final node in paperNodes) canvas.drawLine(node, center, line);
    }
    if (showConcepts) {
      for (final node in conceptNodes) canvas.drawLine(center, node, line);
      for (final node in conceptNodes) {
        for (final gap in gapNodes) canvas.drawLine(node, gap, line);
      }
    }

    _drawNode(canvas, center, 41, AppColors.green, 'Climate\nresilience');
    if (showPapers) {
      _drawNode(canvas, paperNodes[0], 29, AppColors.blue, 'Paper A');
      _drawNode(canvas, paperNodes[1], 29, AppColors.blue, 'Paper B');
      _drawNode(canvas, paperNodes[2], 29, AppColors.blue, 'Paper C');
    }
    if (showConcepts) {
      _drawNode(canvas, conceptNodes[0], 33, AppColors.primary, 'Flood\nrisk');
      _drawNode(canvas, conceptNodes[1], 33, AppColors.primary, 'Green\ninfra');
      _drawNode(
        canvas,
        conceptNodes[2],
        33,
        AppColors.primary,
        'Heat\nexposure',
      );
    }
    _drawNode(canvas, gapNodes[0], 36, AppColors.red, 'Longitudinal\ngap');
    _drawNode(canvas, gapNodes[1], 36, AppColors.orange, 'Equity\ngap');
  }

  void _drawNode(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    String label,
  ) {
    canvas.drawCircle(
      center,
      radius + 4,
      Paint()..color = color.withValues(alpha: 0.12),
    );
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: math.max(9, radius * 0.3),
          fontWeight: FontWeight.w800,
          height: 1.05,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: radius * 1.75);
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _ResearchMapPainter oldDelegate) =>
      showPapers != oldDelegate.showPapers ||
      showConcepts != oldDelegate.showConcepts;
}

class _WorkspaceReviewTab extends StatefulWidget {
  const _WorkspaceReviewTab();

  @override
  State<_WorkspaceReviewTab> createState() => _WorkspaceReviewTabState();
}

class _WorkspaceReviewTabState extends State<_WorkspaceReviewTab> {
  final Set<String> _verified = {};

  @override
  Widget build(BuildContext context) {
    final queue = DemoData.components
        .where(
          (component) =>
              component.status == VerificationStatus.needsReview &&
              !_verified.contains(component.label),
        )
        .toList();
    return _WorkspacePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            title: 'Human review',
            subtitle:
                'Setiap keputusan disimpan sebagai audit record tanpa menghapus keluaran awal AI.',
          ),
          const SizedBox(height: 18),
          if (queue.isEmpty)
            const Card(
              child: EmptyState(
                icon: Icons.task_alt_rounded,
                title: 'Review selesai',
                message:
                    'Semua komponen dalam proyek ini sudah memiliki keputusan reviewer.',
              ),
            )
          else
            for (final component in queue) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              component.label,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          StatusBadge.verification(component.status),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(component.value),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F7FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '“${component.evidence}”',
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              component.location,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () =>
                                setState(() => _verified.add(component.label)),
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Verifikasi'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit'),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _verified.add(component.label)),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Tolak'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}
