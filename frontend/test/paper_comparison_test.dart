import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/data/paper_comparison_repository.dart';
import 'package:modellyng/src/widgets/pair_comparison_flowchart.dart';
import 'package:modellyng/src/widgets/paper_comparison_panel.dart';

import 'fixtures/paper_comparison_fixture.dart';

void main() {
  test('flowchart stops at data and never draws later decisions', () {
    final pair = PaperPair.fromJson(pairFixture());
    final code = pairFlowchartCode(pair);
    final graph = const MermaidParser().parse(code);
    expect(graph, isNotNull);
    expect(code, contains('s0 -->|Yes| s1'));
    expect(code, contains('s1 -->|Yes| s2'));
    expect(code, contains('s2 -->|No| outcome'));
    expect(code, isNot(contains('s3')));
    expect(code, contains('Review manusia'));
    expect(pair.steps[2].rightEvidence.single.source.pageNumber, 5);
    expect(pair.steps[2].leftEvidence.single.source.blockId, 'block-a-2');
  });

  test('untrusted paper titles cannot add nodes or change decisions', () {
    final input = pairFixture();
    input['left_source'] = {'title': 'Paper]\nhacked --> fake[Confirmed gap'};
    final code = pairFlowchartCode(PaperPair.fromJson(input));
    expect(code, isNot(contains('hacked')));
    expect(const MermaidParser().parse(code), isNotNull);
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('pair flowchart, evidence and review work at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _FakeRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paperComparisonRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PaperComparisonPanel(projectId: 'project'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pair-flowchart')), findsOneWidget);
      expect(find.text('1 kandidat gap'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Data / objek penelitian'));
      await tester.tap(find.text('Data / objek penelitian'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The sample included households in the city.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('The sample included only households'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Halaman 3 · Methods · Participants'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Halaman 5 · Methods · Participants'),
        findsOneWidget,
      );
      final accept = find.widgetWithText(FilledButton, 'Layak ditelusuri');
      expect(tester.widget<FilledButton>(accept).onPressed, isNull);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(
        find.byType(TextField),
        'Bandingkan kriteria inklusi dan perluas literatur.',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(accept);
      await tester.tap(accept);
      await tester.pumpAndSettle();
      expect(repository.saved.single, [
        'project',
        'pair-a-b',
        'accepted',
        'Bandingkan kriteria inklusi dan perluas literatur.',
      ]);
      expect(find.text('Keputusan terakhir: Layak ditelusuri'), findsOneWidget);
      await tester.ensureVisible(find.text('Matrix'));
      await tester.tap(find.text('Matrix'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pair-comparison-matrix')), findsOneWidget);
      expect(find.text('No · Berbeda'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'failed comparison can be queued again without fabricating a result',
    (tester) async {
      final repository = _FakeRepository()
        ..data = overviewFixture(pairs: [pairFixture(status: 'failed')]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paperComparisonRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PaperComparisonPanel(projectId: 'project'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0 kandidat gap'), findsOneWidget);
      expect(find.byKey(const Key('pair-flowchart')), findsNothing);
      await tester.tap(find.text('Analisis / coba lagi'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.started, 1);
      expect(find.textContaining('Dalam antrean'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('fewer than two reviewed papers disables analysis', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          paperComparisonsProvider('project').overrideWith(
            (ref) async => overviewFixture(pairs: [], readyPapers: 1),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PaperComparisonPanel(projectId: 'project'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Analisis / coba lagi'),
          )
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('pair-flowchart')), findsNothing);
  });
}

class _FakeRepository extends PaperComparisonRepository {
  _FakeRepository() : super(Dio());
  PairComparisonOverview data = overviewFixture();
  final saved = <List<String>>[];
  int started = 0;
  @override
  Future<PairComparisonOverview> get(String projectId) async => data;
  @override
  Future<PairComparisonOverview> start(String projectId) async {
    started++;
    data = overviewFixture(pairs: [pairFixture(status: 'queued')]);
    return data;
  }

  @override
  Future<void> review(
    String projectId,
    String pairId,
    String decision,
    String note,
  ) async {
    saved.add([projectId, pairId, decision, note]);
    final pair = pairFixture();
    pair['reviews'] = [
      {
        'decision': decision,
        'note': note,
        'created_at': '2026-09-09T00:00:00Z',
      },
    ];
    data = overviewFixture(pairs: [pair]);
  }
}
