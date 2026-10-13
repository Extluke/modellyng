import '../models/research_models.dart';

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
    this.saturationStatus,
    this.zoneCategory,
    this.methodCluster,
    this.objectCluster,
  });

  final String id;
  final String label;
  final GraphNodeType type;
  
  final String? gapStatement;
  final GraphGapType? gapType;
  final GapConfidence? confidence;
  final bool isValidated;
  final List<GapEvidence> evidence;
  final List<String> relatedConceptIds;
  final String? saturationStatus;
  final String? zoneCategory;
  final String? methodCluster;
  final String? objectCluster;
}

