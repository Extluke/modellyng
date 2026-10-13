import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/data/concept_map_repository.dart';
import 'package:modellyng/src/data/project_repository.dart';
import 'package:modellyng/src/data/research_flow_repository.dart';
import 'package:modellyng/src/data/research_gap_repository.dart';
import 'package:modellyng/src/models/research_models.dart';
import 'package:modellyng/src/screens/project_maps_detail_screen.dart';
import 'package:modellyng/src/screens/research_gap_map_screen.dart';

import 'fixtures/research_flow_fixture.dart';

class FakeProjectRepositoryForMaps extends Fake implements ProjectRepository {
  @override
  Future<KnowledgeGraphMap> getKnowledgeGraph(String projectId) async {
    return const KnowledgeGraphMap(
      projectId: 'proj-123',
      projectTitle: 'Smart IoT Infrastructure',
      nodes: [
        KnowledgeGraphNode(
          id: 'gap-iot-1',
          kind: 'research_gap',
          label: 'Keterbatasan Device IoT',
          detail:
              'Keterbatasan kemampuan komputasi dan memori pada device IoT sensor.',
          gapTypology: 'missing_relation',
          confidenceScore: 0.9,
          evidence: [
            KnowledgeGraphEvidence(
              paperId: 'paper-1',
              paperTitle: 'Studi Efisiensi Edge AI',
              section: 'Kesimpulan',
              quote:
                  'Perangkat mikrokontroler IoT standar tidak mampu memproses inferensi AI secara mandiri.',
            ),
          ],
        ),
      ],
      edges: [],
      zones: [],
    );
  }
}

class FakeResearchGapRepository extends Fake implements ResearchGapRepository {
  @override
  Future<ResearchGapMap> getMap(String projectId) async {
    return const ResearchGapMap(
      projectId: 'proj-123',
      projectTitle: 'Smart IoT Infrastructure',
      candidateCount: 1,
      nodes: [
        ConceptMapNode(
          id: 'paper:p1',
          kind: 'paper',
          label: 'Studi Efisiensi Edge AI',
          detail: 'Analisis implementasi IoT dan Edge computing.',
          paperId: 'p1',
          parameter: null,
          pageNumber: null,
        ),
        ConceptMapNode(
          id: 'gap:p1:limitations',
          kind: 'gap',
          label: 'Keterbatasan Device IoT',
          detail:
              'Keterbatasan kemampuan komputasi dan memori pada device IoT sensor.',
          paperId: 'p1',
          parameter: 'limitations',
          pageNumber: 1,
        ),
      ],
      edges: [
        ConceptMapEdge(
          source: 'paper:p1',
          target: 'gap:p1:limitations',
          relation: 'suggests_candidate',
        ),
      ],
    );
  }

  final List<ResearchGapDecision> _decisions = [];

  @override
  Future<List<ResearchGapDecision>> getDecisions(String projectId) async {
    return List.unmodifiable(_decisions);
  }

  @override
  Future<ResearchGapDecision> saveDecision({
    required String projectId,
    required String paperId,
    required String parameter,
    required GapDecision decision,
  }) async {
    final d = ResearchGapDecision(
      id: 'dec-${_decisions.length + 1}',
      projectId: projectId,
      paperId: paperId,
      parameter: parameter,
      decision: decision,
      note: null,
    );
    _decisions.add(d);
    return d;
  }
}

void main() {
  group('ProjectMapsDetailScreen - Gap Detail Selesai & Summary', () {
    testWidgets(
      'tapping SELESAI displays comprehensive summary (selamat di akhir, kutipan gap, apa yang bisa dilakukan user, bagaimana kelanjutannya)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final fakeRepo = FakeProjectRepositoryForMaps();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              projectRepositoryProvider.overrideWithValue(fakeRepo),
              researchFlowRepositoryProvider.overrideWithValue(
                FakeResearchFlowRepository([figmaFlow()]),
              ),
            ],
            child: const MaterialApp(
              home: ProjectMapsDetailScreen(
                projectId: 'proj-123',
                projectTitle: 'Smart IoT Infrastructure',
                userId: 'user-123',
              ),
            ),
          ),
        );

        // Wait for graph data to load
        await tester.pumpAndSettle();

        // Tap on the gap card in the list at the bottom
        final gapCardFinder = find.byKey(const Key('gap-card-gap-iot-1'));
        await tester.scrollUntilVisible(
          gapCardFinder,
          500,
          scrollable: find.byType(Scrollable).first,
        );
        expect(gapCardFinder, findsOneWidget);
        await tester.tap(gapCardFinder);
        await tester.pumpAndSettle();

        // Bottom sheet should be visible with GAP DETAIL title
        expect(
          find.text('GAP DETAIL: KETERBATASAN DEVICE IOT'),
          findsOneWidget,
        );

        // Finish button should be present
        final finishButtonFinder = find.byKey(const Key('gap-finish-button'));
        await tester.scrollUntilVisible(
          finishButtonFinder,
          500,
          scrollable: find.byType(Scrollable).last,
        );
        expect(finishButtonFinder, findsOneWidget);
        expect(find.text('SELESAI'), findsOneWidget);

        // Tap SELESAI
        await tester.tap(finishButtonFinder);
        await tester.pumpAndSettle();

        // 1. Pesan Selamat di akhir
        expect(find.text('Selamat anda sudah berada di akhir'), findsWidgets);

        // 2. Kutipan Gap yang di-klik
        expect(
          find.text(
            '"Keterbatasan kemampuan komputasi dan memori pada device IoT sensor."',
          ),
          findsWidgets,
        );

        // 3. Apa yang bisa dilakukan user (Solusi konkret: migrasi IoT -> Raspberry Pi)
        expect(
          find.text('APA YANG BISA DILAKUKAN USER (SOLUSI KONKRET)'),
          findsOneWidget,
        );
        expect(find.textContaining('Raspberry Pi'), findsWidgets);

        // 4. Bagaimana kelanjutannya (Roadmap riset)
        expect(
          find.text('BAGAIMANA KELANJUTANNYA (ROADMAP RISET)'),
          findsOneWidget,
        );
        expect(find.textContaining('Tahap 1'), findsWidgets);

        // Close the alert dialog by tapping OK / Tutup
        await tester.tap(find.text('OK / Tutup'));
        await tester.pumpAndSettle();

        // In bottom sheet, button should now say TUTUP
        expect(find.text('TUTUP'), findsOneWidget);

        // Tapping TUTUP dismisses bottom sheet
        await tester.tap(finishButtonFinder);
        await tester.pumpAndSettle();

        expect(find.text('GAP DETAIL: KETERBATASAN DEVICE IOT'), findsNothing);
      },
    );
  });

  group('ResearchGapMapScreen - SELESAI Button & Summary', () {
    testWidgets(
      'displays SELESAI button and shows summary with recommendation on click',
      (tester) async {
        final fakeGapRepo = FakeResearchGapRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              researchGapRepositoryProvider.overrideWithValue(fakeGapRepo),
            ],
            child: const MaterialApp(
              home: ResearchGapMapScreen(
                userId: 'user-123',
                projectId: 'proj-123',
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Finish button should be present instead of tolak/setujui
        final finishBtn = find.byKey(const Key('finish-gap-p1-limitations'));
        await tester.scrollUntilVisible(
          finishBtn,
          500,
          scrollable: find.byType(Scrollable).first,
        );
        expect(finishBtn, findsOneWidget);
        expect(find.text('SELESAI'), findsOneWidget);

        // Tap SELESAI
        await tester.tap(finishBtn);
        await tester.pumpAndSettle();

        // Summary items should appear
        expect(find.text('Selamat anda sudah berada di akhir'), findsOneWidget);
        expect(
          find.text(
            '"Keterbatasan kemampuan komputasi dan memori pada device IoT sensor."',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Raspberry Pi'), findsOneWidget);
      },
    );
  });
}
