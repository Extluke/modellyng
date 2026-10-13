import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/data/research_flow_repository.dart';
import 'package:modellyng/src/models/research_flow.dart';

class FakeResearchFlowRepository extends Fake implements ResearchFlowRepository {
  FakeResearchFlowRepository(this.responses);

  /// Hasil berurutan: ResearchFlowMap atau Exception untuk dilempar.
  final List<Object> responses;
  int calls = 0;

  @override
  Future<ResearchFlowMap> getFlow(String projectId) async {
    final next = responses[calls < responses.length ? calls : responses.length - 1];
    calls++;
    if (next is ResearchFlowMap) return next;
    throw next;
  }
}

/// Contoh Figma reviewer: tiga paper banjir dengan satu solusi bersama
/// (apk), satu solusi tunggal (web), dan satu paper yang topiknya tidak
/// berkaitan (menyetrika baju).
ResearchFlowMap figmaFlow() => const ResearchFlowMap(
  projectId: 'project',
  papers: [
    ResearchFlowPaper(paperId: 'p1', number: 1, title: 'Banjir curah hujan'),
    ResearchFlowPaper(paperId: 'p2', number: 2, title: 'Banjir sungai'),
    ResearchFlowPaper(paperId: 'p3', number: 3, title: 'Banjir longsor'),
    ResearchFlowPaper(paperId: 'p4', number: 4, title: 'Menyetrika baju'),
  ],
  themes: [
    ResearchFlowTheme(
      label: 'banjir',
      items: [
        ResearchFlowItem(
          paperId: 'p1',
          topic: 'banjir akibat curah hujan',
          problem: 'curah hujan',
        ),
        ResearchFlowItem(
          paperId: 'p2',
          topic: 'banjir akibat sungai',
          problem: 'sungai',
        ),
        ResearchFlowItem(
          paperId: 'p3',
          topic: 'banjir akibat longsor',
          problem: 'longsor',
        ),
      ],
      solutions: [
        ResearchFlowSolution(
          label: 'apk',
          paperIds: ['p1', 'p2'],
          shared: true,
          functions: ['peringatan dini banjir', 'peta titik rawan'],
          conclusions: ['evakuasi lebih cepat', 'data hujan real-time'],
        ),
        ResearchFlowSolution(label: 'web', paperIds: ['p3'], shared: false),
      ],
    ),
  ],
  unrelated: [
    ResearchFlowUnrelated(paperId: 'p4', topic: 'cara menyetrika baju'),
  ],
);
