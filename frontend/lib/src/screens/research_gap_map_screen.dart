import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/concept_map_repository.dart';
import '../data/project_repository.dart';
import '../data/research_gap_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'paper_result_screen.dart';

class ResearchGapMapScreen extends ConsumerStatefulWidget {
  const ResearchGapMapScreen({required this.userId, super.key});
  final String userId;

  @override
  ConsumerState<ResearchGapMapScreen> createState() =>
      _ResearchGapMapScreenState();
}

class _ResearchGapMapScreenState extends ConsumerState<ResearchGapMapScreen> {
  String? _projectId;
  String _source = 'all';
  String? _savingCandidateKey;

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider(widget.userId));
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
        children: [
          const PageHeading(
            title: 'Research Gap Map',
            subtitle:
                'Petakan kandidat gap dari keterbatasan dan future work yang sudah direview, lengkap dengan evidence asli.',
          ),
          const SizedBox(height: 10),
          const _HumanReviewNotice(),
          const SizedBox(height: 18),
          projects.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                const _GapMessage('Proyek belum dapat dimuat.'),
            data: (items) {
              if (items.isEmpty) {
                return const _GapMessage(
                  'Belum ada proyek untuk mencari kandidat research gap.',
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
                    onChanged: (value) => setState(() => _projectId = value),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('Semua')),
                      ButtonSegment(
                        value: 'limitations',
                        label: Text('Keterbatasan'),
                      ),
                      ButtonSegment(
                        value: 'future_work',
                        label: Text('Future work'),
                      ),
                    ],
                    selected: {_source},
                    onSelectionChanged: (value) =>
                        setState(() => _source = value.first),
                  ),
                  const SizedBox(height: 18),
                  _map(
                    ref.watch(researchGapMapProvider(_projectId!)),
                    ref.watch(researchGapDecisionsProvider(_projectId!)),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _map(
    AsyncValue<ResearchGapMap> value,
    AsyncValue<List<ResearchGapDecision>> decisions,
  ) => value.when(
    loading: () => const Center(
      child: Padding(
        padding: EdgeInsets.all(36),
        child: CircularProgressIndicator(),
      ),
    ),
    error: (error, _) =>
        const _GapMessage('Research gap map belum dapat dimuat.'),
    data: (graph) {
      final decisionByKey = {
        for (final decision in decisions.value ?? const <ResearchGapDecision>[])
          decision.candidateKey: decision,
      };
      final gaps = graph.nodes
          .where(
            (node) =>
                node.kind == 'gap' &&
                (_source == 'all' || node.parameter == _source),
          )
          .toList();
      if (gaps.isEmpty) {
        return const _GapMessage(
          'Belum ada keterbatasan atau future work yang selesai direview.',
        );
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth >= 900
              ? (constraints.maxWidth - 16) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final gap in gaps)
                SizedBox(
                  width: width,
                  child: _GapChainCard(
                    graph: graph,
                    gap: gap,
                    decision: decisionByKey['${gap.paperId}:${gap.parameter}'],
                    saving:
                        _savingCandidateKey ==
                        '${gap.paperId}:${gap.parameter}',
                    onOpen: _openNode,
                    onDecision: (decision) => _saveDecision(gap, decision),
                  ),
                ),
            ],
          );
        },
      );
    },
  );

  void _openNode(ResearchGapMap graph, ConceptMapNode node) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PaperResultScreen(
          projectId: graph.projectId,
          paperId: node.paperId,
          initialPage: node.pageNumber ?? 1,
        ),
      ),
    );
  }

  Future<void> _saveDecision(ConceptMapNode gap, GapDecision decision) async {
    final projectId = _projectId;
    final parameter = gap.parameter;
    if (projectId == null || parameter == null) return;
    final candidateKey = '${gap.paperId}:$parameter';
    setState(() => _savingCandidateKey = candidateKey);
    try {
      await ref
          .read(researchGapRepositoryProvider)
          .saveDecision(
            projectId: projectId,
            paperId: gap.paperId,
            parameter: parameter,
            decision: decision,
          );
      ref.invalidate(researchGapDecisionsProvider(projectId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision == GapDecision.accepted
                ? 'Kandidat gap dipilih untuk proses rumusan penelitian.'
                : 'Kandidat dilewati. Lanjutkan ke kandidat berikutnya.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keputusan gap belum dapat disimpan.'),
          backgroundColor: AppColors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingCandidateKey = null);
    }
  }
}

class _GapChainCard extends StatelessWidget {
  const _GapChainCard({
    required this.graph,
    required this.gap,
    required this.decision,
    required this.saving,
    required this.onOpen,
    required this.onDecision,
  });
  final ResearchGapMap graph;
  final ConceptMapNode gap;
  final ResearchGapDecision? decision;
  final bool saving;
  final void Function(ResearchGapMap, ConceptMapNode) onOpen;
  final ValueChanged<GapDecision> onDecision;

  @override
  Widget build(BuildContext context) {
    final paperEdge = graph.edges.firstWhere(
      (edge) => edge.target == gap.id && edge.relation == 'suggests_candidate',
    );
    final paper = graph.nodes.firstWhere((node) => node.id == paperEdge.source);
    final evidence = graph.edges
        .where(
          (edge) => edge.source == gap.id && edge.relation == 'supported_by',
        )
        .map((edge) => graph.nodes.firstWhere((node) => node.id == edge.target))
        .toList();
    final sourceLabel = gap.parameter == 'limitations'
        ? 'Keterbatasan'
        : 'Future work';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  avatar: Icon(
                    decision == null
                        ? Icons.help_outline_rounded
                        : decision!.decision == GapDecision.accepted
                        ? Icons.check_circle_outline_rounded
                        : Icons.skip_next_rounded,
                    size: 16,
                  ),
                  label: Text(
                    decision == null
                        ? 'Belum diputuskan'
                        : decision!.decision == GapDecision.accepted
                        ? 'Dipilih'
                        : 'Dilewati',
                  ),
                ),
                const Spacer(),
                Text(
                  sourceLabel,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _MapStep(
              icon: Icons.description_outlined,
              eyebrow: '1 · SUMBER PAPER',
              title: paper.label,
              subtitle: paper.detail,
            ),
            const _FlowConnector(),
            _MapStep(
              icon: Icons.lightbulb_outline_rounded,
              eyebrow: '2 · KANDIDAT GAP',
              title: sourceLabel,
              subtitle: gap.detail,
            ),
            const _FlowConnector(),
            if (evidence.isEmpty)
              const _MapStep(
                icon: Icons.warning_amber_rounded,
                eyebrow: '3 · VALIDASI EVIDENCE',
                title: 'Evidence belum tersedia',
                subtitle: 'Kandidat tidak boleh dianggap sebagai gap final.',
              )
            else
              for (var index = 0; index < evidence.length; index++)
                _MapStep(
                  icon: Icons.fact_check_outlined,
                  eyebrow: index == 0 ? '3 · VALIDASI EVIDENCE' : null,
                  title: evidence[index].label,
                  subtitle: evidence[index].detail,
                  action: 'Buka evidence PDF',
                  onTap: () => onOpen(graph, evidence[index]),
                ),
            const _FlowConnector(),
            const Text(
              '4 · AMBIL KANDIDAT GAP INI?',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: Key('accept-gap-${gap.paperId}-${gap.parameter}'),
                    onPressed: saving
                        ? null
                        : () => onDecision(GapDecision.accepted),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Yes, gunakan'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('reject-gap-${gap.paperId}-${gap.parameter}'),
                    onPressed: saving
                        ? null
                        : () => onDecision(GapDecision.rejected),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('No, lewati'),
                  ),
                ),
              ],
            ),
            if (saving) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            if (decision != null) ...[
              const _FlowConnector(),
              _MapStep(
                icon: decision!.decision == GapDecision.accepted
                    ? Icons.edit_note_rounded
                    : Icons.navigate_next_rounded,
                eyebrow: '5 · PROSES BERIKUTNYA',
                title: decision!.decision == GapDecision.accepted
                    ? 'Susun rumusan penelitian'
                    : 'Lanjut ke kandidat berikutnya',
                subtitle: decision!.decision == GapDecision.accepted
                    ? 'Kandidat masuk daftar gap terpilih dan siap menjadi dasar pertanyaan/tujuan baru.'
                    : 'Kandidat tetap tersimpan sebagai riwayat keputusan, tetapi tidak dipakai.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MapStep extends StatelessWidget {
  const _MapStep({
    required this.icon,
    this.eyebrow,
    required this.title,
    required this.subtitle,
    this.action,
    this.onTap,
  });
  final IconData icon;
  final String? eyebrow;
  final String title;
  final String subtitle;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: AppColors.primarySoft,
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
                if (action != null)
                  Text(
                    action!,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _FlowConnector extends StatelessWidget {
  const _FlowConnector();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(left: 10, top: 3, bottom: 3),
    child: Icon(
      Icons.arrow_downward_rounded,
      size: 20,
      color: AppColors.primary,
    ),
  );
}

class _HumanReviewNotice extends StatelessWidget {
  const _HumanReviewNotice();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(
      children: [
        Icon(Icons.info_outline_rounded, color: AppColors.primary),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Peta ini menampilkan kandidat, bukan kesimpulan otomatis. Validasi kembali terhadap literatur sebelum digunakan.',
          ),
        ),
      ],
    ),
  );
}

class _GapMessage extends StatelessWidget {
  const _GapMessage(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Icon(
            Icons.lightbulb_outline_rounded,
            size: 42,
            color: AppColors.muted,
          ),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
