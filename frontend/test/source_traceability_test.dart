import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/data/paper_result_repository.dart';
import 'package:modellyng/src/data/source_verification_repository.dart';
import 'package:modellyng/src/models/research_models.dart';
import 'package:modellyng/src/widgets/source_verification_card.dart';

const query = (projectId: 'project-a', paperId: 'paper-a');
final paper = ProjectPaper.fromJson({
  'id': query.paperId,
  'project_id': query.projectId,
  'title': 'A Study',
  'doi': '10.1234/example',
  'authors': ['Ada Lovelace'],
  'publication_year': 2024,
  'journal': 'Journal A',
  'publisher': 'Publisher A',
  'volume': '2',
  'issue': '1',
  'pages': '10-20',
  'publication_status': 'preprint',
});
final report = SourceVerification.fromJson({
  'id': 'report-a',
  'created_at': '2026-09-07T00:00:00Z',
  'report': {
    'status': 'mismatch',
    'requested_doi': '10.1234/example',
    'checks': [
      {
        'field': 'title',
        'local_value': 'A Study',
        'source_value': 'Another Study',
        'status': 'mismatch',
      },
    ],
    'sources': [
      {
        'provider': 'Crossref',
        'url': 'https://api.crossref.org/works/10.1234%2Fexample',
        'status': 'found',
      },
    ],
    'warnings': ['Review manusia tetap wajib.'],
  },
  'reviews': [],
});

class FakeRepository extends SourceVerificationRepository {
  FakeRepository() : super(Dio());
  final calls = <String>[];
  @override
  Future<void> verify(PaperResultQuery q, String doi) async {
    calls.add('verify:${q.paperId}:$doi');
  }

  @override
  Future<void> review(
    PaperResultQuery q,
    String id,
    String decision,
    String note,
  ) async {
    calls.add('$decision:$id:$note');
  }
}

void main() {
  test(
    'paper and evidence models preserve every metadata and source locator',
    () {
      expect(paper.bibliographicValues.length, 10);
      expect(paper.bibliographicValues['pages'], '10-20');
      final evidence = ResultEvidence.fromJson({
        'quote': 'Table 2 reports 91%.',
        'page_number': 3,
        'block_id': 'block-a',
        'evidence_kind': 'table',
        'section': '2 Results',
        'subsection': '2.1 Evaluation',
        'source_label': 'Table 2',
      });
      expect(evidence.blockId, 'block-a');
      expect(evidence.kindLabel, 'Tabel');
      expect(evidence.locationLabel, contains('2.1 Evaluation'));
      expect(evidence.locationLabel, contains('Table 2'));
      expect(
        ResultEvidence.fromJson({
          'quote': 'Old evidence',
          'page_number': 1,
        }).kindLabel,
        'Teks persis',
      );
    },
  );

  for (final width in [390.0, 1280.0]) {
    testWidgets('source comparison and human review work at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceVerificationRepositoryProvider.overrideWithValue(repo),
            sourceVerificationsProvider(
              query,
            ).overrideWith((ref) async => [report]),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ListView(children: [SourceVerificationCard(paper: paper)]),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Validasi paper & sumber'));
      await tester.pumpAndSettle();
      expect(find.text('Penerbit: Publisher A'), findsOneWidget);
      expect(find.text('Halaman publikasi: 10-20'), findsOneWidget);
      final verify = find.byKey(const Key('verify-source'));
      await tester.ensureVisible(verify);
      await tester.tap(verify);
      await tester.pumpAndSettle();
      expect(repo.calls.single, 'verify:paper-a:10.1234/example');
      final accept = find.text('Terima sumber');
      await tester.ensureVisible(accept);
      await tester.tap(accept);
      await tester.pumpAndSettle();
      expect(repo.calls.length, 1);
      expect(find.text('Catatan review wajib diisi.'), findsOneWidget);
      final note = find.byType(TextField).last;
      await tester.ensureVisible(note);
      await tester.enterText(note, 'Checked PDF and registry');
      await tester.ensureVisible(find.text('Tolak sumber'));
      await tester.tap(find.text('Tolak sumber'));
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'reject:report-a:Checked PDF and registry');
      expect(find.text('Registri: Another Study'), findsOneWidget);
      expect(find.text('Belum ditinjau manusia.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('source failure is recoverable and never displays approval', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (count, error) => null,
        overrides: [
          sourceVerificationsProvider(
            query,
          ).overrideWith((ref) async => throw Exception('offline')),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(children: [SourceVerificationCard(paper: paper)]),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Validasi paper & sumber'));
    await tester.pumpAndSettle();
    expect(find.text('Riwayat belum dapat dimuat. Coba lagi'), findsOneWidget);
    expect(find.text('Terima sumber'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
