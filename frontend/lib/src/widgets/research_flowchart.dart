import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart';

import '../data/concept_map_repository.dart';
import '../theme/app_theme.dart';

final MermaidStyle _researchFlowchartStyle = MermaidStyle(
  backgroundColor: Colors.white.toARGB32(),
  defaultNodeStyle: NodeStyle(
    fillColor: AppColors.primarySoft.toARGB32(),
    strokeColor: AppColors.primary.toARGB32(),
    strokeWidth: 2,
    textColor: AppColors.ink.toARGB32(),
    fontSize: 12,
    fontWeight: FontWeight.w700,
    borderRadius: 14,
  ),
  defaultEdgeStyle: EdgeStyle(
    strokeColor: AppColors.muted.toARGB32(),
    strokeWidth: 1.8,
    labelColor: AppColors.muted.toARGB32(),
    labelFontSize: 11,
    labelBackgroundColor: Colors.white.toARGB32(),
  ),
  nodeSpacingX: 72,
  nodeSpacingY: 28,
  padding: 32,
  fontFamily: 'Arial',
  classDefs: {
    'paper': NodeStyle(
      fillColor: AppColors.primarySoft.toARGB32(),
      strokeColor: AppColors.primary.toARGB32(),
      strokeWidth: 2,
      textColor: AppColors.primaryDark.toARGB32(),
      fontSize: 12,
      fontWeight: FontWeight.w800,
      borderRadius: 16,
    ),
    'concept': NodeStyle(
      fillColor: AppColors.blueSoft.toARGB32(),
      strokeColor: AppColors.blue.toARGB32(),
      strokeWidth: 2,
      textColor: AppColors.ink.toARGB32(),
      fontSize: 12,
      fontWeight: FontWeight.w700,
      borderRadius: 14,
    ),
    'evidence': NodeStyle(
      fillColor: AppColors.greenSoft.toARGB32(),
      strokeColor: AppColors.green.toARGB32(),
      strokeWidth: 2,
      textColor: AppColors.ink.toARGB32(),
      fontSize: 12,
      fontWeight: FontWeight.w600,
      borderRadius: 14,
    ),
  },
);

/// A parser-safe Mermaid document built from the owner-scoped API graph.
///
/// API node IDs and document text are never emitted as Mermaid identifiers.
/// Generated identifiers also provide a stable route from a tapped Mermaid
/// node back to the authenticated paper result or evidence page.
class ResearchMermaidDocument {
  ResearchMermaidDocument._(this.code, Map<String, ConceptMapNode> nodesById)
    : _nodesById = UnmodifiableMapView(nodesById);

  factory ResearchMermaidDocument.fromGraph(
    List<ConceptMapNode> nodes,
    List<ConceptMapEdge> edges, {
    bool compact = false,
  }) {
    final sourceToMermaidId = <String, String>{};
    final nodesByMermaidId = <String, ConceptMapNode>{};

    for (final node in nodes) {
      final sourceId = node.id.trim();
      if (sourceId.isEmpty || sourceToMermaidId.containsKey(sourceId)) {
        continue;
      }
      final mermaidId = 'node${nodesByMermaidId.length}';
      sourceToMermaidId[sourceId] = mermaidId;
      nodesByMermaidId[mermaidId] = node;
    }

    final buffer = StringBuffer('flowchart LR\n');
    for (final entry in nodesByMermaidId.entries) {
      buffer.writeln(
        '  ${entry.key}[${_nodeLabel(entry.value, compact: compact)}]',
      );
    }

    for (final edge in edges) {
      final source = sourceToMermaidId[edge.source];
      final target = sourceToMermaidId[edge.target];
      if (source == null || target == null) continue;
      final relation = _edgeLabel(edge.relation);
      buffer.writeln(
        relation.isEmpty
            ? '  $source --> $target'
            : '  $source -->|$relation| $target',
      );
    }

    // flutter_mermaid uses class definitions in the source to assign each
    // class and the matching MermaidStyle definitions to paint it.
    buffer
      ..writeln(
        '  classDef paper fill:#EEECFF,stroke:#5147E5,'
        'color:#3730A3,stroke-width:2px',
      )
      ..writeln(
        '  classDef concept fill:#EAF3FF,stroke:#2878F0,'
        'color:#172033,stroke-width:2px',
      )
      ..writeln(
        '  classDef evidence fill:#E8F7F1,stroke:#158466,'
        'color:#172033,stroke-width:2px',
      );

    for (final entry in nodesByMermaidId.entries) {
      buffer.writeln('  class ${entry.key} ${_nodeClass(entry.value.kind)}');
    }

    return ResearchMermaidDocument._(buffer.toString(), nodesByMermaidId);
  }

  final String code;
  final Map<String, ConceptMapNode> _nodesById;

  ConceptMapNode? nodeForMermaidId(String id) => _nodesById[id];

  Iterable<ConceptMapNode> get nodes => _nodesById.values;
}

/// Converts the graph JSON returned by the API into parser-safe Mermaid code.
String researchGraphToMermaid(
  List<ConceptMapNode> nodes,
  List<ConceptMapEdge> edges,
) => ResearchMermaidDocument.fromGraph(nodes, edges).code;

class ResearchFlowchart extends StatelessWidget {
  const ResearchFlowchart({
    required this.nodes,
    required this.edges,
    required this.onOpen,
    super.key,
  });

  final List<ConceptMapNode> nodes;
  final List<ConceptMapEdge> edges;
  final ValueChanged<ConceptMapNode> onOpen;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) return const SizedBox.shrink();

    final isCompact = MediaQuery.sizeOf(context).width < 600;
    final document = ResearchMermaidDocument.fromGraph(
      nodes,
      edges,
      compact: isCompact,
    );
    final chartHeight = isCompact ? 430.0 : 540.0;
    final semantics = document.nodes
        .map((node) => '${_kindLabel(node.kind)}: ${node.label}')
        .join('. ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(isCompact ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: AppColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.account_tree_outlined,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Flowchart evidence',
                        style: TextStyle(
                          color: AppColors.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text('Dibuat seketika dari graph JSON hasil review.'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'MERMAID',
                    style: TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Semantics(
              container: true,
              label: 'Flowchart paper, konsep, dan evidence. $semantics',
              hint:
                  'Geser untuk menjelajah, cubit atau scroll untuk zoom, '
                  'dan ketuk konsep atau evidence untuk membuka sumber.',
              child: Container(
                key: const Key('research-flowchart-mermaid'),
                height: chartHeight,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: InteractiveMermaidDiagram(
                  code: document.code,
                  style: _researchFlowchartStyle,
                  minScale: isCompact ? 0.65 : 0.2,
                  maxScale: 3,
                  onNodeTap: (id) {
                    final node = document.nodeForMermaidId(id);
                    if (node != null && node.kind != 'paper') onOpen(node);
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Row(
              children: [
                Icon(Icons.pan_tool_alt_outlined, size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Geser dan zoom untuk menjelajah. Ketuk node konsep atau '
                    'evidence untuk membuka detail dan PDF privat.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _nodeLabel(ConceptMapNode node, {required bool compact}) {
  final primary = switch (node.kind) {
    'concept' => _parameterLabel(node.parameter ?? node.label),
    _ => node.label,
  };
  final detail = compact || node.kind == 'paper'
      ? ''
      : _safeMermaidText(node.detail, 62);
  final parts = <String>[
    _kindLabel(node.kind),
    _safeMermaidText(
      primary,
      compact
          ? node.kind == 'paper'
                ? 42
                : 30
          : node.kind == 'paper'
          ? 82
          : 42,
    ),
    if (detail.isNotEmpty) detail,
  ];
  return _safeMermaidText(
    parts.where((part) => part.isNotEmpty).join(' · '),
    compact ? 60 : 112,
  );
}

String _edgeLabel(String relation) {
  return switch (relation.trim().toLowerCase()) {
    'contains' => 'memuat',
    'supported_by' => 'didukung',
    final value => _safeMermaidText(value.replaceAll('_', ' '), 28),
  };
}

String _safeMermaidText(String value, int maxRunes) {
  var safe = value
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .replaceAll(RegExp(r'[\[\]{}()<>|\\=]'), ' ')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'\.{3,}'), '…')
      .replaceAll(RegExp(r'%{2,}'), '%')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final runes = safe.runes.toList(growable: false);
  if (runes.length > maxRunes) {
    safe = '${String.fromCharCodes(runes.take(maxRunes)).trimRight()}…';
  }
  return safe;
}

String _nodeClass(String kind) => switch (kind) {
  'paper' => 'paper',
  'evidence' => 'evidence',
  _ => 'concept',
};

String _kindLabel(String kind) => switch (kind) {
  'paper' => 'PAPER',
  'concept' => 'KONSEP',
  'evidence' => 'EVIDENCE',
  _ => 'KOMPONEN',
};

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
