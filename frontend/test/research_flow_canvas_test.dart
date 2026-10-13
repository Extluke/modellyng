import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/data/research_flow_repository.dart';
import 'package:modellyng/src/models/research_flow.dart';
import 'package:modellyng/src/widgets/research_flow_canvas.dart';

import 'fixtures/research_flow_fixture.dart';

Future<void> pumpPanel(WidgetTester tester, FakeResearchFlowRepository repo) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [researchFlowRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(20),
            child: ResearchFlowPanel(projectId: 'project'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

DioException serverError(String detail) {
  final options = RequestOptions(path: '/research-flow');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: options,
      statusCode: 503,
      data: {'detail': detail},
    ),
  );
}

void main() {
  testWidgets('renders the Figma flow with legend and end markers', (tester) async {
    await pumpPanel(tester, FakeResearchFlowRepository([figmaFlow()]));

    expect(find.byKey(const Key('flow-node-theme:0')), findsOneWidget);
    expect(find.byKey(const Key('flow-node-solution:0:0')), findsOneWidget);
    expect(find.byKey(const Key('flow-node-end:p4')), findsOneWidget);
    expect(find.text('banjir'), findsOneWidget);
    expect(find.text('Paper 1 & 2'), findsOneWidget);
    expect(find.text('cara menyetrika baju'), findsOneWidget);
    // Solusi tunggal dan topik tanpa kesamaan sama-sama berhenti di "End".
    expect(find.text('End'), findsNWidgets(2));
    expect(find.text('Merah = jarang diteliti'), findsOneWidget);
    expect(find.text('Hijau = sering diteliti'), findsOneWidget);
    expect(find.byTooltip('Perbesar'), findsOneWidget);
    expect(find.byTooltip('Layar penuh'), findsOneWidget);

    final colors = <String, Color?>{
      for (final id in ['solution:0:0', 'solution:0:1', 'end:p4', 'topic:p1'])
        id: tester
            .widget<Material>(
              find.ancestor(
                of: find.byKey(Key('flow-node-$id')),
                matching: find.byType(Material),
              ).first,
            )
            .color,
    };
    expect(colors['solution:0:0'], FlowColors.frequent);
    expect(colors['solution:0:1'], FlowColors.rare);
    expect(colors['end:p4'], FlowColors.rare);
    expect(colors['topic:p1'], FlowColors.neutral);
  });

  testWidgets('tapping a node shows its stage, status, and source papers', (tester) async {
    await pumpPanel(tester, FakeResearchFlowRepository([figmaFlow()]));

    await tester.tap(find.byKey(const Key('flow-node-solution:0:1')), warnIfMissed: false);
    await tester.pumpAndSettle();
    if (find.text('SOLUSI').evaluate().isEmpty) {
      // Kotak di luar area terlihat: pakai tampilan seluruh peta lalu ketuk lagi.
      await tester.tap(find.byTooltip('Tampilkan seluruh peta'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-node-solution:0:1')));
      await tester.pumpAndSettle();
    }

    expect(find.text('SOLUSI'), findsOneWidget);
    expect(find.text('web'), findsWidgets);
    expect(
      find.text('Jarang diteliti: tidak ada kesamaan solusi, alur berhenti (end).'),
      findsOneWidget,
    );
    expect(find.text('Paper 3: Banjir longsor'), findsOneWidget);
  });

  testWidgets('zoom buttons change the canvas scale', (tester) async {
    await pumpPanel(tester, FakeResearchFlowRepository([figmaFlow()]));
    final viewer = find.byType(InteractiveViewer);
    double scale() => tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!
        .value
        .getMaxScaleOnAxis();

    final initial = scale();
    await tester.tap(find.byTooltip('Perbesar'));
    await tester.pump();
    expect(scale(), closeTo(initial * 1.25, 0.001));
    await tester.tap(find.byTooltip('Perkecil'));
    await tester.tap(find.byTooltip('Perkecil'));
    await tester.pump();
    expect(scale(), lessThan(initial));
  });

  testWidgets('shows the backend message and retries on failure', (tester) async {
    final repo = FakeResearchFlowRepository([
      serverError('Kuota Gemini sedang habis. Coba lagi beberapa saat lagi.'),
      figmaFlow(),
    ]);
    await pumpPanel(tester, repo);

    expect(find.text('Peta alur belum dapat dimuat'), findsOneWidget);
    expect(
      find.text('Kuota Gemini sedang habis. Coba lagi beberapa saat lagi.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(repo.calls, 2);
    expect(find.byKey(const Key('flow-node-theme:0')), findsOneWidget);
  });

  testWidgets('empty project explains when the map appears', (tester) async {
    await pumpPanel(
      tester,
      FakeResearchFlowRepository([const ResearchFlowMap(projectId: 'project')]),
    );
    expect(find.text('Belum ada alur riset'), findsOneWidget);
  });
}
