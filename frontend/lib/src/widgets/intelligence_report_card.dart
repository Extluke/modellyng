import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/intelligence_report_repository.dart';
import '../theme/app_theme.dart';

class IntelligenceReportCard extends ConsumerStatefulWidget {
  const IntelligenceReportCard({required this.projectId, super.key});
  final String projectId;

  @override
  ConsumerState<IntelligenceReportCard> createState() =>
      _IntelligenceReportCardState();
}

class _IntelligenceReportCardState
    extends ConsumerState<IntelligenceReportCard> {
  String _style = 'apa7';

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(
      intelligenceReportProvider('${widget.projectId}|$_style'),
    );
    return Card(
      key: const Key('intelligence-report-card'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: report.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Row(
            children: [
              const Icon(Icons.analytics_outlined, color: AppColors.muted),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Laporan intelligence belum dapat dimuat.'),
              ),
              IconButton(
                onPressed: () => ref.invalidate(
                  intelligenceReportProvider('${widget.projectId}|$_style'),
                ),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          data: (value) => _content(context, value),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, IntelligenceReport report) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Final Verification & Traceability Report',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          DropdownButton<String>(
            value: _style,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'apa7', child: Text('APA 7')),
              DropdownMenuItem(value: 'ieee', child: Text('IEEE')),
              DropdownMenuItem(value: 'harvard', child: Text('Harvard')),
              DropdownMenuItem(value: 'vancouver', child: Text('Vancouver')),
              DropdownMenuItem(value: 'chicago', child: Text('Chicago')),
            ],
            onChanged: (value) => setState(() => _style = value ?? 'apa7'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text(report.synthesis),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _metric('References', report.references.length),
          _metric('Kandidat gap', report.candidateGapCount),
          _metric('Pasangan', report.comparisonCount),
          _metric('Relasi', report.relationshipCount),
          _metric('Unsupported claim', report.unsupportedClaims.length),
        ],
      ),
      if (report.unsupportedClaims.isNotEmpty) ...[
        const SizedBox(height: 14),
        const Text(
          'Unsupported claim yang perlu ditinjau',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        for (final claim in report.unsupportedClaims.take(4))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.orange,
            ),
            title: Text(claim.parameter),
            subtitle: Text(
              '${claim.claim}\n${claim.reason}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      if (report.clusters.isNotEmpty) ...[
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Research clusters (${report.clusters.length})'),
          children: [
            for (final cluster in report.clusters.take(8))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(cluster.label),
                subtitle: Text(cluster.sharedTerms.join(', ')),
              ),
          ],
        ),
      ],
      if (report.papers.isNotEmpty) ...[
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Structural compression per paper'),
          children: [
            for (final paper in report.papers)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(paper.title),
                subtitle: Text(
                  paper.structure.entries
                      .map((entry) => '${entry.key}: ${entry.value}')
                      .join('\n'),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ],
      if (report.references.isNotEmpty) ...[
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Daftar pustaka otomatis'),
          children: [
            for (final reference in report.references)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(reference.citation),
                subtitle: Text(
                  'Sitasi dalam teks: ${reference.inTextCitation}',
                ),
              ),
          ],
        ),
      ],
    ],
  );

  Widget _metric(String label, int value) => Chip(
    avatar: CircleAvatar(child: Text(value.toString())),
    label: Text(label),
  );
}
