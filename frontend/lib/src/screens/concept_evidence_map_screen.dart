import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/concept_map_repository.dart';
import '../data/project_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/research_flowchart.dart';
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
          ResearchFlowchart(
            nodes: nodes,
            edges: edges,
            onOpen: (node) => _openNode(graph, node),
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
