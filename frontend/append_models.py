import sys

dart_code = '''
class AiResearchSynthesis {
  const AiResearchSynthesis({
    required this.usulanJudul,
    required this.rumusanMasalah,
    required this.pernyataanNovelty,
    required this.alasanPemilihan,
  });

  final List<String> usulanJudul;
  final List<String> rumusanMasalah;
  final String pernyataanNovelty;
  final String alasanPemilihan;

  factory AiResearchSynthesis.fromJson(Map<String, dynamic> json) {
    return AiResearchSynthesis(
      usulanJudul: (json['usulan_judul'] as List<dynamic>?)?.cast<String>() ?? [],
      rumusanMasalah: (json['rumusan_masalah'] as List<dynamic>?)?.cast<String>() ?? [],
      pernyataanNovelty: json['pernyataan_novelty']?.toString() ?? '',
      alasanPemilihan: json['alasan_pemilihan']?.toString() ?? '',
    );
  }
}

class KnowledgeGraphNode {
  const KnowledgeGraphNode({
    required this.id,
    required this.kind,
    required this.label,
    required this.detail,
    this.parentId,
    this.gapTypology,
    this.saturationStatus,
    this.confidenceScore,
    this.zoneCategory,
    this.x,
    this.y,
  });

  final String id;
  final String kind;
  final String label;
  final String detail;
  final String? parentId;
  final String? gapTypology;
  final String? saturationStatus;
  final double? confidenceScore;
  final String? zoneCategory;
  final double? x;
  final double? y;

  factory KnowledgeGraphNode.fromJson(Map<String, dynamic> json) {
    return KnowledgeGraphNode(
      id: json['id']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
      parentId: json['parent_id']?.toString(),
      gapTypology: json['gap_typology']?.toString(),
      saturationStatus: json['saturation_status']?.toString(),
      confidenceScore: (json['confidence_score'] as num?)?.toDouble(),
      zoneCategory: json['zone_category']?.toString(),
      x: (json['x'] as num?)?.toDouble(),
      y: (json['y'] as num?)?.toDouble(),
    );
  }
}

class KnowledgeGraphEdge {
  const KnowledgeGraphEdge({
    required this.source,
    required this.target,
    required this.relation,
    this.detail,
  });

  final String source;
  final String target;
  final String relation;
  final String? detail;

  factory KnowledgeGraphEdge.fromJson(Map<String, dynamic> json) {
    return KnowledgeGraphEdge(
      source: json['source']?.toString() ?? '',
      target: json['target']?.toString() ?? '',
      relation: json['relation']?.toString() ?? '',
      detail: json['detail']?.toString(),
    );
  }
}

class KnowledgeGraphMap {
  const KnowledgeGraphMap({
    required this.projectId,
    required this.projectTitle,
    required this.nodes,
    required this.edges,
  });

  final String projectId;
  final String projectTitle;
  final List<KnowledgeGraphNode> nodes;
  final List<KnowledgeGraphEdge> edges;

  factory KnowledgeGraphMap.fromJson(Map<String, dynamic> json) {
    return KnowledgeGraphMap(
      projectId: json['project_id']?.toString() ?? '',
      projectTitle: json['project_title']?.toString() ?? '',
      nodes: (json['nodes'] as List<dynamic>?)
              ?.map((e) => KnowledgeGraphNode.fromJson(e))
              .toList(growable: false) ??
          [],
      edges: (json['edges'] as List<dynamic>?)
              ?.map((e) => KnowledgeGraphEdge.fromJson(e))
              .toList(growable: false) ??
          [],
    );
  }
}
'''
with open('lib/src/models/research_models.dart', 'a', encoding='utf-8') as f:
    f.write(dart_code)

print("Appended models to research_models.dart")
