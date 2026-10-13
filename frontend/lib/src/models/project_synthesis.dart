import 'paper_label.dart';

/// Sintesis AI global untuk semua paper terreview di satu project.
class ProjectSynthesis {
  const ProjectSynthesis({
    required this.projectId,
    this.papers = const [],
    this.sections = const [],
    this.researchIdeas = const [],
    this.paperPositions = const [],
    this.academicText = '',
    this.modelName,
    this.generatedAt,
    this.stale = false,
  });

  final String projectId;
  final List<SynthesisPaper> papers;
  final List<SynthesisSection> sections;
  final List<SynthesisIdea> researchIdeas;
  final List<SynthesisPaperPosition> paperPositions;

  /// Paragraf akademik per bagian dengan sitasi penulis-tahun dan daftar
  /// pustaka, siap ditempel ke dokumen.
  final String academicText;
  final String? modelName;
  final DateTime? generatedAt;

  /// True bila hasil review paper berubah sejak sintesis dibuat.
  final bool stale;

  int get includedCount => papers.where((paper) => paper.included).length;

  SynthesisPaper? paper(String paperId) {
    for (final paper in papers) {
      if (paper.paperId == paperId) return paper;
    }
    return null;
  }

  /// "Paper 1 & 3" untuk daftar paper_id.
  String labelFor(List<String> paperIds) => paperNumbersLabel(
    paperIds.map((id) => paper(id)?.number).whereType<int>(),
  );

  /// Versi poin untuk tombol "Salin".
  String toPointsText(String projectTitle) {
    final buffer = StringBuffer()
      ..writeln('Sintesis AI: $projectTitle')
      ..writeln('Mencakup $includedCount paper.');
    for (final section in sections) {
      if (section.points.isEmpty) continue;
      buffer
        ..writeln()
        ..writeln(section.title);
      for (final point in section.points) {
        buffer.writeln('- ${point.text} (${labelFor(point.paperIds)})');
      }
    }
    if (researchIdeas.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Ide Penelitian Lanjutan');
      for (var i = 0; i < researchIdeas.length; i++) {
        final idea = researchIdeas[i];
        buffer.writeln('${i + 1}. ${idea.title} (${labelFor(idea.paperIds)})');
        if (idea.rationale.isNotEmpty) buffer.writeln('   ${idea.rationale}');
      }
    }
    if (paperPositions.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Posisi Tiap Paper');
      for (final position in paperPositions) {
        buffer.writeln('${labelFor([position.paperId])}: ${position.text}');
      }
    }
    buffer
      ..writeln()
      ..writeln('Daftar Paper');
    for (final paper in papers) {
      buffer.writeln('Paper ${paper.number}: ${paper.title} ${paper.citation}');
    }
    return buffer.toString().trimRight();
  }

  factory ProjectSynthesis.fromJson(Map<String, dynamic> json) =>
      ProjectSynthesis(
        projectId: json['project_id']?.toString() ?? '',
        papers: _objects(json['papers'], SynthesisPaper.fromJson),
        sections: _objects(json['sections'], SynthesisSection.fromJson),
        researchIdeas: _objects(json['research_ideas'], SynthesisIdea.fromJson),
        paperPositions: _objects(
          json['paper_positions'],
          SynthesisPaperPosition.fromJson,
        ),
        academicText: json['academic_text']?.toString() ?? '',
        modelName: json['model_name']?.toString(),
        generatedAt: DateTime.tryParse(json['generated_at']?.toString() ?? ''),
        stale: json['stale'] == true,
      );
}

class SynthesisPaper {
  const SynthesisPaper({
    required this.paperId,
    required this.number,
    required this.title,
    required this.citation,
    this.included = true,
  });

  final String paperId;
  final int number;
  final String title;

  /// Sitasi penulis-tahun, misal "(Al-Qaheri dkk., 2010)".
  final String citation;
  final bool included;

  factory SynthesisPaper.fromJson(Map<String, dynamic> json) => SynthesisPaper(
    paperId: json['paper_id'].toString(),
    number: (json['number'] as num?)?.toInt() ?? 0,
    title: json['title']?.toString() ?? 'Paper',
    citation: json['citation']?.toString() ?? '',
    included: json['included'] != false,
  );
}

class SynthesisSection {
  const SynthesisSection({
    required this.key,
    required this.title,
    this.points = const [],
    this.paragraph = '',
  });

  final String key;
  final String title;
  final List<SynthesisPoint> points;
  final String paragraph;

  factory SynthesisSection.fromJson(Map<String, dynamic> json) =>
      SynthesisSection(
        key: json['key']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        points: _objects(json['points'], SynthesisPoint.fromJson),
        paragraph: json['paragraph']?.toString() ?? '',
      );
}

class SynthesisPoint {
  const SynthesisPoint({required this.text, this.paperIds = const []});

  final String text;
  final List<String> paperIds;

  factory SynthesisPoint.fromJson(Map<String, dynamic> json) => SynthesisPoint(
    text: json['text']?.toString() ?? '',
    paperIds: _strings(json['paper_ids']),
  );
}

class SynthesisIdea {
  const SynthesisIdea({
    required this.title,
    required this.rationale,
    this.paperIds = const [],
  });

  final String title;
  final String rationale;
  final List<String> paperIds;

  factory SynthesisIdea.fromJson(Map<String, dynamic> json) => SynthesisIdea(
    title: json['title']?.toString() ?? '',
    rationale: json['rationale']?.toString() ?? '',
    paperIds: _strings(json['paper_ids']),
  );
}

class SynthesisPaperPosition {
  const SynthesisPaperPosition({required this.paperId, required this.text});

  final String paperId;
  final String text;

  factory SynthesisPaperPosition.fromJson(Map<String, dynamic> json) =>
      SynthesisPaperPosition(
        paperId: json['paper_id'].toString(),
        text: json['text']?.toString() ?? '',
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
