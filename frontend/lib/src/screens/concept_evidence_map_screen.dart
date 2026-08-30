import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/concept_map_repository.dart';
import '../data/project_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'paper_result_screen.dart';

class ConceptEvidenceMapScreen extends ConsumerStatefulWidget {
  const ConceptEvidenceMapScreen({required this.userId, super.key});
  final String userId;
  @override
  ConsumerState<ConceptEvidenceMapScreen> createState() =>
      _ConceptEvidenceMapScreenState();
}

class _ConceptEvidenceMapScreenState
    extends ConsumerState<ConceptEvidenceMapScreen> {
  String? _projectId;
  String? _paperId;

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider(widget.userId));
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
        children: [
          const PageHeading(
            title: 'Concept / Evidence Map',
            subtitle:
                'Jelajahi hubungan paper, konsep hasil review, dan evidence pada PDF privat.',
          ),
          const SizedBox(height: 20),
          projects.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                const _MapMessage('Proyek belum dapat dimuat.'),
            data: (items) {
              if (items.isEmpty)
                return const _MapMessage('Belum ada proyek untuk dipetakan.');
              _projectId ??= items.first.id;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _projectId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Pilih proyek',
                    ),
                    items: [
                      for (final project in items)
                        DropdownMenuItem(
                          value: project.id,
                          child: Text(
                            project.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _projectId = value;
                      _paperId = null;
                    }),
                  ),
                  const SizedBox(height: 18),
                  _map(ref.watch(conceptMapProvider(_projectId!))),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _map(AsyncValue<ConceptEvidenceMap> value) => value.when(
    loading: () => const Center(
      child: Padding(
        padding: EdgeInsets.all(36),
        child: CircularProgressIndicator(),
      ),
    ),
    error: (error, _) => const _MapMessage('Concept map belum dapat dimuat.'),
    data: (graph) {
      final papers = graph.nodes.where((node) => node.kind == 'paper').toList();
      if (papers.isEmpty)
        return const _MapMessage(
          'Selesaikan review paper sebelum membuat concept map.',
        );
      _paperId ??= papers.first.paperId;
      final nodes = graph.nodes
          .where((node) => node.paperId == _paperId)
          .toList();
      final ids = nodes.map((node) => node.id).toSet();
      final edges = graph.edges
          .where(
            (edge) => ids.contains(edge.source) && ids.contains(edge.target),
          )
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _paperId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Fokus paper'),
            items: [
              for (final paper in papers)
                DropdownMenuItem(
                  value: paper.paperId,
                  child: Text(
                    paper.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _paperId = value),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 900
                ? _DesktopGraph(
                    nodes: nodes,
                    edges: edges,
                    onOpen: (node) => _openNode(graph, node),
                  )
                : _MobileGraph(
                    nodes: nodes,
                    edges: edges,
                    onOpen: (node) => _openNode(graph, node),
                  ),
          ),
        ],
      );
    },
  );

  void _openNode(ConceptEvidenceMap graph, ConceptMapNode node) {
    if (node.kind == 'paper') return;
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
}

class _DesktopGraph extends StatelessWidget {
  const _DesktopGraph({
    required this.nodes,
    required this.edges,
    required this.onOpen,
  });
  final List<ConceptMapNode> nodes;
  final List<ConceptMapEdge> edges;
  final ValueChanged<ConceptMapNode> onOpen;

  @override
  Widget build(BuildContext context) {
    final positions = <String, Offset>{};
    final paper = nodes.firstWhere((node) => node.kind == 'paper');
    positions[paper.id] = const Offset(30, 40);
    final concepts = nodes.where((node) => node.kind == 'concept').toList();
    final evidence = nodes.where((node) => node.kind == 'evidence').toList();
    for (var i = 0; i < concepts.length; i++) {
      positions[concepts[i].id] = Offset(330, 25 + i * 145);
    }
    for (var i = 0; i < evidence.length; i++) {
      final parent = edges
          .firstWhere((edge) => edge.target == evidence[i].id)
          .source;
      final parentY = positions[parent]?.dy ?? 25;
      final siblings = evidence
          .take(i)
          .where(
            (item) => edges.any(
              (edge) => edge.source == parent && edge.target == item.id,
            ),
          )
          .length;
      positions[evidence[i].id] = Offset(690, parentY + siblings * 92);
    }
    final height = math.max(
      520.0,
      [...positions.values].map((p) => p.dy).fold(0.0, math.max) + 150,
    );
    return Card(
      child: SizedBox(
        height: 620,
        child: InteractiveViewer(
          constrained: false,
          boundaryMargin: const EdgeInsets.all(120),
          minScale: 0.55,
          maxScale: 1.8,
          child: SizedBox(
            width: 1030,
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _EdgePainter(positions, edges)),
                ),
                for (final node in nodes)
                  Positioned(
                    left: positions[node.id]?.dx ?? 0,
                    top: positions[node.id]?.dy ?? 0,
                    child: _NodeCard(
                      node: node,
                      onTap: node.kind == 'paper' ? null : () => onOpen(node),
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

class _EdgePainter extends CustomPainter {
  _EdgePainter(this.positions, this.edges);
  final Map<String, Offset> positions;
  final List<ConceptMapEdge> edges;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 2;
    for (final edge in edges) {
      final start = positions[edge.source];
      final end = positions[edge.target];
      if (start == null || end == null) continue;
      canvas.drawLine(
        start + const Offset(250, 48),
        end + const Offset(0, 48),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) =>
      oldDelegate.positions != positions || oldDelegate.edges != edges;
}

class _MobileGraph extends StatelessWidget {
  const _MobileGraph({
    required this.nodes,
    required this.edges,
    required this.onOpen,
  });
  final List<ConceptMapNode> nodes;
  final List<ConceptMapEdge> edges;
  final ValueChanged<ConceptMapNode> onOpen;
  @override
  Widget build(BuildContext context) {
    final concepts = nodes.where((node) => node.kind == 'concept');
    return Column(
      children: [
        _NodeCard(node: nodes.firstWhere((node) => node.kind == 'paper')),
        const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.muted),
        for (final concept in concepts) ...[
          _NodeCard(node: concept, onTap: () => onOpen(concept)),
          for (final edge in edges.where(
            (edge) => edge.source == concept.id,
          )) ...[
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.muted,
            ),
            _NodeCard(
              node: nodes.firstWhere((node) => node.id == edge.target),
              onTap: () =>
                  onOpen(nodes.firstWhere((node) => node.id == edge.target)),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.node, this.onTap});
  final ConceptMapNode node;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final color = node.kind == 'paper'
        ? AppColors.primary
        : node.kind == 'concept'
        ? AppColors.blue
        : AppColors.green;
    return SizedBox(
      width: 260,
      child: Card(
        color: color.withValues(alpha: 0.08),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.kind.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _parameterLabel(node.label),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(node.detail, maxLines: 3, overflow: TextOverflow.ellipsis),
                if (onTap != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    node.kind == 'evidence'
                        ? 'Buka halaman PDF'
                        : 'Buka hasil terstruktur',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _parameterLabel(String value) => switch (value) {
  'research_problem' => 'Masalah penelitian',
  'research_objective' => 'Tujuan penelitian',
  'research_question' => 'Pertanyaan penelitian',
  'methodology' => 'Metodologi',
  'dataset_sample' => 'Dataset atau sampel',
  'variables_concepts' => 'Variabel dan konsep',
  'results_findings' => 'Hasil dan temuan',
  'contribution' => 'Kontribusi',
  'limitations' => 'Keterbatasan',
  'future_work' => 'Penelitian berikutnya',
  'key_claims' => 'Klaim utama',
  _ => value,
};

class _MapMessage extends StatelessWidget {
  const _MapMessage(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Icon(Icons.hub_outlined, size: 42, color: AppColors.muted),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
