import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/data/auth_repository.dart';
import 'package:modellyng/src/data/paper_repository.dart';
import 'package:modellyng/src/data/review_repository.dart';
import 'package:modellyng/src/models/research_models.dart';
import 'package:modellyng/src/screens/project_overview_screen.dart';
import 'package:modellyng/src/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

const _userId = 'user-bulk-accept';
const _acceptAllKey = Key('accept-all-project-analyses');
const _confirmKey = Key('confirm-accept-all-project-analyses');
const _subtitle =
    'File tersimpan privat dan hanya dapat diakses oleh pemilik proyek.';

const _project = ResearchProject(
  id: 'project-a',
  title: 'Adaptasi Iklim',
  description: 'Proyek uji terima semua analisis.',
  paperCount: 3,
  reviewCount: 2,
  readyCount: 0,
  progress: 0.85,
  status: ProjectStatus.needsReview,
  updatedLabel: 'Baru saja',
  accent: Color(0xFF5747E8),
);

class _FakeAuthRepo extends Fake implements AuthRepository {
  @override
  supa.User? get currentUser => const supa.User(
    id: _userId,
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  );
}

/// Mirrors the accept-all RPC: a request accepts every listed component or
/// fails without changing anything.
class _FakeReviewRepo extends Fake implements ReviewRepository {
  _FakeReviewRepo(this.pending, {this.failingCalls = const {}, this.gate});

  final List<ReviewQueueItem> pending;
  final Set<int> failingCalls;
  final Completer<void>? gate;
  final calls = <List<String>>[];

  @override
  Future<int> acceptAll(List<String> componentIds) async {
    calls.add(List.of(componentIds));
    await gate?.future;
    if (failingCalls.contains(calls.length)) {
      throw Exception('Sebagian komponen sudah ditinjau');
    }
    pending.removeWhere((item) => componentIds.contains(item.componentId));
    return componentIds.length;
  }
}

List<ReviewQueueItem> _components(
  String paperId, {
  String projectId = 'project-a',
  int count = 11,
}) => [
  for (var index = 0; index < count; index++)
    ReviewQueueItem(
      componentId: '$paperId-component-$index',
      paperId: paperId,
      projectId: projectId,
      projectTitle: 'Proyek',
      paperTitle: 'Paper $paperId',
      originalFilename: '$paperId.pdf',
      parameter: 'parameter_$index',
      aiValue: 'Nilai AI $index',
      confidence: 0.9,
      evidence: const [],
      modelName: 'gemini',
    ),
];

ProjectPaper _paper(
  String id,
  PaperStatus status, {
  PaperJobStatus jobStatus = PaperJobStatus.completed,
}) => ProjectPaper(
  id: id,
  projectId: _project.id,
  originalFilename: '$id.pdf',
  storageKey: 'owner/$id.pdf',
  fileSizeBytes: 2048,
  status: status,
  pageCount: 12,
  languageCode: 'en',
  title: 'Paper $id',
  authors: const [],
  jobStatus: jobStatus,
  processingStage: null,
  // A determinate value keeps progress bars static so the test can settle.
  processingProgress: 0.4,
  processingError: null,
  createdAt: null,
);

Future<void> _pumpProject(
  WidgetTester tester, {
  required List<ProjectPaper> papers,
  required _FakeReviewRepo reviews,
  Size size = const Size(1280, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuthRepo()),
        reviewRepositoryProvider.overrideWithValue(reviews),
        projectPapersProvider((
          userId: _userId,
          projectId: _project.id,
        )).overrideWith((ref) => papers),
        // Re-read on every invalidation, like the real queue endpoint.
        reviewQueueProvider(
          _userId,
        ).overrideWith((ref) => List.of(reviews.pending)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const ProjectOverviewScreen(project: _project),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openConfirmation(WidgetTester tester) async {
  final button = find.byKey(_acceptAllKey);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void _expectOnHeadingRow(WidgetTester tester, Finder button) {
  final title = tester.getRect(find.text('Paper dalam proyek'));
  final action = tester.getRect(button);
  expect(
    action.left,
    greaterThanOrEqualTo(title.right),
    reason: 'the shortcut sits to the right of the heading text',
  );
  expect(
    title.center.dy,
    inInclusiveRange(action.top, action.bottom),
    reason: 'the shortcut shares the heading row',
  );
  expect(
    tester.getRect(find.text(_subtitle)).top,
    greaterThanOrEqualTo(action.bottom),
    reason: 'the subtitle stays below the heading row',
  );
}

void main() {
  group('planBulkAcceptBatches', () {
    test('keeps every paper in a single request within the limit', () {
      final batches = planBulkAcceptBatches([
        ..._components('a', count: 3),
        ..._components('b', count: 3),
        ..._components('c', count: 2),
      ], maxBatchSize: 5);

      expect(batches, [
        ['a-component-0', 'a-component-1', 'a-component-2'],
        [
          'b-component-0',
          'b-component-1',
          'b-component-2',
          'c-component-0',
          'c-component-1',
        ],
      ]);
    });

    test('groups interleaved queue rows by paper and drops repeated IDs', () {
      final a = _components('a', count: 2);
      final b = _components('b', count: 2);

      expect(planBulkAcceptBatches([a[0], b[0], a[1], b[1], a[0]]), [
        ['a-component-0', 'a-component-1', 'b-component-0', 'b-component-1'],
      ]);
    });

    test('splits a paper that alone exceeds the limit', () {
      final batches = planBulkAcceptBatches([
        ..._components('a', count: 2),
        ..._components('large', count: 7),
      ], maxBatchSize: 5);

      expect(batches.map((batch) => batch.length), [2, 5, 2]);
    });

    test('uses the backend limit of 200 IDs per request by default', () {
      final items = [
        for (var index = 0; index < 19; index++)
          ..._components('paper-$index'),
      ];

      final batches = planBulkAcceptBatches(items);

      expect(batches.map((batch) => batch.length), [198, 11]);
      expect(batches.expand((batch) => batch).toList(), [
        for (final item in items) item.componentId,
      ]);
    });
  });

  group('ProjectOverviewScreen accept-all shortcut', () {
    testWidgets('is hidden when nothing in the project awaits review', (
      tester,
    ) async {
      final reviews = _FakeReviewRepo([
        ..._components('foreign-paper', projectId: 'project-b'),
        // Older components of a paper that is being re-analysed.
        ..._components('paper-reanalysis', count: 4),
      ]);
      await _pumpProject(
        tester,
        papers: [
          _paper('paper-ready', PaperStatus.ready),
          _paper(
            'paper-reanalysis',
            PaperStatus.processing,
            jobStatus: PaperJobStatus.processing,
          ),
        ],
        reviews: reviews,
      );

      expect(find.text('Paper dalam proyek'), findsOneWidget);
      expect(find.byKey(_acceptAllKey), findsNothing);
    });

    testWidgets(
      'accepts only this project\'s papers awaiting review after confirmation',
      (tester) async {
        final awaiting = [..._components('paper-1'), ..._components('paper-2')];
        final reviews = _FakeReviewRepo([
          ...awaiting,
          ..._components('paper-reanalysis', count: 4),
          ..._components('foreign-paper', projectId: 'project-b'),
        ]);
        await _pumpProject(
          tester,
          papers: [
            _paper('paper-1', PaperStatus.needsReview),
            _paper('paper-2', PaperStatus.needsReview),
            _paper(
              'paper-reanalysis',
              PaperStatus.processing,
              jobStatus: PaperJobStatus.processing,
            ),
          ],
          reviews: reviews,
        );

        final button = find.byKey(_acceptAllKey);
        expect(
          find.descendant(
            of: button,
            matching: find.text('Terima semua analisis (22)'),
          ),
          findsOneWidget,
        );
        _expectOnHeadingRow(tester, button);
        // Right-aligned with the 920 px content column.
        expect(
          tester.getRect(button).right,
          moreOrLessEquals(
            tester.getRect(find.text('Paper dalam proyek')).left + 920,
          ),
        );

        await _openConfirmation(tester);
        expect(find.text('Terima semua 22 hasil analisis?'), findsOneWidget);
        expect(
          find.textContaining('dari 2 paper di proyek "Adaptasi Iklim"'),
          findsOneWidget,
        );
        expect(
          find.textContaining('1 paper yang masih diproses tidak termasuk.'),
          findsOneWidget,
        );
        expect(find.textContaining('bertahap'), findsNothing);

        await tester.tap(find.byKey(_confirmKey));
        await tester.pumpAndSettle();

        expect(reviews.calls, hasLength(1));
        expect(reviews.calls.single.toSet(), {
          for (final item in awaiting) item.componentId,
        });
        expect(find.text('22 hasil analisis berhasil diterima.'), findsOneWidget);
        expect(find.byKey(_acceptAllKey), findsNothing);
      },
    );

    testWidgets('sends nothing when the confirmation is cancelled', (
      tester,
    ) async {
      final reviews = _FakeReviewRepo(_components('paper-1'));
      await _pumpProject(
        tester,
        papers: [_paper('paper-1', PaperStatus.needsReview)],
        reviews: reviews,
      );

      await _openConfirmation(tester);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();

      expect(reviews.calls, isEmpty);
      expect(find.byKey(_acceptAllKey), findsOneWidget);
    });

    testWidgets('disables the shortcut while the request is running', (
      tester,
    ) async {
      final gate = Completer<void>();
      final reviews = _FakeReviewRepo(_components('paper-1'), gate: gate);
      await _pumpProject(
        tester,
        papers: [_paper('paper-1', PaperStatus.needsReview)],
        reviews: reviews,
      );

      await _openConfirmation(tester);
      await tester.tap(find.byKey(_confirmKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final button = tester.widget<FilledButton>(find.byKey(_acceptAllKey));
      expect(button.onPressed, isNull);
      expect(reviews.calls, hasLength(1));

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('11 hasil analisis berhasil diterima.'), findsOneWidget);
      expect(find.byKey(_acceptAllKey), findsNothing);
    });

    testWidgets('keeps a shorter label on the heading row on mobile', (
      tester,
    ) async {
      final reviews = _FakeReviewRepo(_components('paper-1'));
      await _pumpProject(
        tester,
        size: const Size(390, 844),
        papers: [_paper('paper-1', PaperStatus.needsReview)],
        reviews: reviews,
      );

      final button = find.byKey(_acceptAllKey);
      expect(
        find.descendant(of: button, matching: find.text('Terima semua (11)')),
        findsOneWidget,
      );
      _expectOnHeadingRow(tester, button);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'sends more than 200 results in per-paper batches and reports a partial failure',
      (tester) async {
        final paperIds = [for (var index = 0; index < 19; index++) 'paper-$index'];
        final reviews = _FakeReviewRepo([
          for (final id in paperIds) ..._components(id),
        ], failingCalls: {2});
        await _pumpProject(
          tester,
          papers: [
            for (final id in paperIds) _paper(id, PaperStatus.needsReview),
          ],
          reviews: reviews,
        );

        expect(
          find.descendant(
            of: find.byKey(_acceptAllKey),
            matching: find.text('Terima semua analisis (209)'),
          ),
          findsOneWidget,
        );
        await _openConfirmation(tester);
        expect(find.textContaining('bertahap dalam 2 kelompok'), findsOneWidget);
        await tester.tap(find.byKey(_confirmKey));
        await tester.pumpAndSettle();

        expect(reviews.calls.map((call) => call.length), [198, 11]);
        for (final id in paperIds) {
          final paperComponents = {
            for (final item in _components(id)) item.componentId,
          };
          final touching = reviews.calls
              .where((call) => call.any(paperComponents.contains))
              .toList();
          expect(touching, hasLength(1), reason: '$id is never split');
          expect(touching.single.toSet().containsAll(paperComponents), isTrue);
        }
        expect(
          find.text(
            '198 dari 209 hasil analisis diterima. 11 hasil lainnya gagal '
            'diterima, silakan coba lagi.',
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(_acceptAllKey),
            matching: find.text('Terima semua analisis (11)'),
          ),
          findsOneWidget,
        );
      },
    );
  });
}
