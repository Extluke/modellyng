/// Peta alur riset untuk kanvas menu Maps (GAP).
///
/// Dibaca dari kiri ke kanan: topik -> isi -> masalah -> solusi -> fungsi dan
/// kesimpulan. Backend sudah menerapkan aturan kesamaan: solusi `shared`
/// (dipakai minimal dua paper) berlanjut dan berwarna hijau, sedangkan solusi
/// tunggal dan topik tanpa kesamaan berhenti di "end" dan berwarna merah.
library;

class ResearchFlowPaper {
  const ResearchFlowPaper({
    required this.paperId,
    required this.number,
    required this.title,
  });

  final String paperId;
  final int number;
  final String title;

  factory ResearchFlowPaper.fromJson(Map<String, dynamic> json) =>
      ResearchFlowPaper(
        paperId: json['paper_id'].toString(),
        number: (json['number'] as num?)?.toInt() ?? 0,
        title: json['title']?.toString() ?? 'Paper',
      );
}

class ResearchFlowItem {
  const ResearchFlowItem({
    required this.paperId,
    required this.topic,
    required this.problem,
  });

  final String paperId;
  final String topic;
  final String problem;

  factory ResearchFlowItem.fromJson(Map<String, dynamic> json) =>
      ResearchFlowItem(
        paperId: json['paper_id'].toString(),
        topic: json['topic']?.toString() ?? '',
        problem: json['problem']?.toString() ?? '',
      );
}

class ResearchFlowSolution {
  const ResearchFlowSolution({
    required this.label,
    required this.paperIds,
    required this.shared,
    this.functions = const [],
    this.conclusions = const [],
  });

  final String label;
  final List<String> paperIds;

  /// True: dipakai minimal dua paper, sering diteliti, alur berlanjut.
  final bool shared;
  final List<String> functions;
  final List<String> conclusions;

  factory ResearchFlowSolution.fromJson(Map<String, dynamic> json) =>
      ResearchFlowSolution(
        label: json['label']?.toString() ?? '',
        paperIds: _strings(json['paper_ids']),
        shared: json['shared'] == true,
        functions: _strings(json['functions']),
        conclusions: _strings(json['conclusions']),
      );
}

class ResearchFlowTheme {
  const ResearchFlowTheme({
    required this.label,
    required this.items,
    required this.solutions,
  });

  final String label;
  final List<ResearchFlowItem> items;
  final List<ResearchFlowSolution> solutions;

  factory ResearchFlowTheme.fromJson(Map<String, dynamic> json) =>
      ResearchFlowTheme(
        label: json['label']?.toString() ?? '',
        items: _objects(json['items'], ResearchFlowItem.fromJson),
        solutions: _objects(json['solutions'], ResearchFlowSolution.fromJson),
      );
}

class ResearchFlowUnrelated {
  const ResearchFlowUnrelated({required this.paperId, required this.topic});

  final String paperId;
  final String topic;

  factory ResearchFlowUnrelated.fromJson(Map<String, dynamic> json) =>
      ResearchFlowUnrelated(
        paperId: json['paper_id'].toString(),
        topic: json['topic']?.toString() ?? '',
      );
}

class ResearchFlowMap {
  const ResearchFlowMap({
    required this.projectId,
    this.papers = const [],
    this.themes = const [],
    this.unrelated = const [],
    this.modelName,
    this.generatedAt,
  });

  final String projectId;
  final List<ResearchFlowPaper> papers;
  final List<ResearchFlowTheme> themes;
  final List<ResearchFlowUnrelated> unrelated;
  final String? modelName;
  final DateTime? generatedAt;

  bool get isEmpty => themes.isEmpty && unrelated.isEmpty;

  factory ResearchFlowMap.fromJson(Map<String, dynamic> json) =>
      ResearchFlowMap(
        projectId: json['project_id']?.toString() ?? '',
        papers: _objects(json['papers'], ResearchFlowPaper.fromJson),
        themes: _objects(json['themes'], ResearchFlowTheme.fromJson),
        unrelated: _objects(json['unrelated'], ResearchFlowUnrelated.fromJson),
        modelName: json['model_name']?.toString(),
        generatedAt: DateTime.tryParse(json['generated_at']?.toString() ?? ''),
      );
}

List<String> _strings(Object? value) => (value as List<dynamic>? ?? const [])
    .map((item) => item.toString())
    .toList(growable: false);

List<T> _objects<T>(
  Object? value,
  T Function(Map<String, dynamic> json) parse,
) => (value as List<dynamic>? ?? const [])
    .cast<Map<String, dynamic>>()
    .map(parse)
    .toList(growable: false);
