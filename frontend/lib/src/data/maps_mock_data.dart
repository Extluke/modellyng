import 'package:flutter/material.dart';

enum GraphNodeType {
  paper,
  concept,
  variable,
  method,
  object,
  researchArea,
  researchGap,
  result,
}

enum GapType {
  unexploredConcept,
  populationGap,
  missingRelationship,
  datasetGap,
  methodologicalGap,
  empiricalGap,
}

enum GapConfidence {
  high,
  medium,
  low,
}

class GapEvidence {
  const GapEvidence({
    required this.paperId,
    required this.paperTitle,
    required this.section,
    required this.quote,
  });

  final String paperId;
  final String paperTitle;
  final String section;
  final String quote;
}

class GraphNode {
  const GraphNode({
    required this.id,
    required this.label,
    required this.type,
    // Gap specific fields
    this.gapStatement,
    this.gapType,
    this.confidence,
    this.isValidated = false,
    this.evidence = const [],
    this.relatedConceptIds = const [],
  });

  final String id;
  final String label;
  final GraphNodeType type;
  
  final String? gapStatement;
  final GapType? gapType;
  final GapConfidence? confidence;
  final bool isValidated;
  final List<GapEvidence> evidence;
  final List<String> relatedConceptIds;
}

class GraphEdge {
  const GraphEdge({
    required this.sourceId,
    required this.targetId,
    required this.label,
  });

  final String sourceId;
  final String targetId;
  final String label;
}

abstract final class MapsMockData {
  static const nodes = <GraphNode>[
    GraphNode(id: 'pA', label: 'Paper A', type: GraphNodeType.paper),
    GraphNode(id: 'pB', label: 'Paper B', type: GraphNodeType.paper),
    GraphNode(id: 'pC', label: 'Paper C', type: GraphNodeType.paper),
    GraphNode(id: 'ra1', label: 'Educational Technology', type: GraphNodeType.researchArea),
    GraphNode(id: 'c1', label: 'Artificial Intelligence', type: GraphNodeType.concept),
    GraphNode(id: 'c2', label: 'Personalized Learning', type: GraphNodeType.concept),
    GraphNode(id: 'v1', label: 'AI Usage', type: GraphNodeType.variable),
    GraphNode(id: 'v2', label: 'Student Motivation', type: GraphNodeType.concept),
    GraphNode(id: 'm1', label: 'Quantitative Survey', type: GraphNodeType.method),
    GraphNode(id: 'o1', label: 'University Students', type: GraphNodeType.object),
    GraphNode(id: 'res1', label: 'Positive Effect', type: GraphNodeType.result),
    
    // Gaps
    GraphNode(
      id: 'g1',
      label: 'Missing relation AI & Motivation',
      type: GraphNodeType.researchGap,
      gapStatement: 'Belum banyak penelitian yang menghubungkan AI dengan Student Motivation secara empiris.',
      gapType: GapType.missingRelationship,
      confidence: GapConfidence.high,
      isValidated: true,
      relatedConceptIds: ['c1', 'v2'],
      evidence: [
        GapEvidence(
          paperId: 'pC',
          paperTitle: 'Paper C',
          section: 'Conclusion',
          quote: 'Future studies should focus on the missing link between AI and motivation.',
        ),
      ],
    ),
  ];

  static const edges = <GraphEdge>[
    GraphEdge(sourceId: 'pA', targetId: 'ra1', label: 'membahas'),
    GraphEdge(sourceId: 'ra1', targetId: 'c1', label: 'mengandung'),
    GraphEdge(sourceId: 'c1', targetId: 'c2', label: 'bercabang'),
    GraphEdge(sourceId: 'c1', targetId: 'v1', label: 'diukur'),
    GraphEdge(sourceId: 'c2', targetId: 'v2', label: 'mempengaruhi'),
    GraphEdge(sourceId: 'v1', targetId: 'm1', label: 'metode'),
    GraphEdge(sourceId: 'v2', targetId: 'o1', label: 'subjek'),
    GraphEdge(sourceId: 'm1', targetId: 'res1', label: 'hasil'),
    GraphEdge(sourceId: 'o1', targetId: 'res1', label: 'hasil'),
    GraphEdge(sourceId: 'v2', targetId: 'g1', label: 'celah'),
    GraphEdge(sourceId: 'pC', targetId: 'g1', label: 'mendukung'),
    GraphEdge(sourceId: 'pB', targetId: 'c1', label: 'membahas'),
  ];
}
