import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/data/project_synthesis_repository.dart';
import 'package:modellyng/src/models/project_synthesis.dart';
import 'package:modellyng/src/widgets/project_synthesis_card.dart';

class FakeSynthesisRepository extends Fake implements ProjectSynthesisRepository {
  FakeSynthesisRepository({this.saved, List<Object>? generated})
    : generated = generated ?? [sampleSynthesis()];

  final ProjectSynthesis? saved;
  final List<Object> generated;
  final List<bool> forceFlags = [];

  @override
  Future<ProjectSynthesis?> getSynthesis(String projectId) async => saved;

  @override
  Future<ProjectSynthesis> generateSynthesis(
    String projectId, {
    bool forceRegenerate = false,
  }) async {
    forceFlags.add(forceRegenerate);
    final next = generated[forceFlags.length - 1 < generated.length
        ? forceFlags.length - 1
        : generated.length - 1];
    if (next is ProjectSynthesis) return next;
    throw next;
  }
}

ProjectSynthesis sampleSynthesis({bool stale = false}) => ProjectSynthesis.fromJson({
  'project_id': 'project',
  'stale': stale,
  'model_name': 'gemini-flash-latest',
  'generated_at': '2026-10-13T02:05:00Z',
  'papers': [
    {'paper_id': 'a', 'number': 1, 'title': 'Hiding inside Html', 'citation': '(Al-Qaheri dkk., 2010)'},
    {'paper_id': 'b', 'number': 2, 'title': 'Embedding Secret Data', 'citation': '(Dey dkk., 2010)'},
    {'paper_id': 'c', 'number': 3, 'title': 'Web Retrieval', 'citation': '(Bassil, 2012)', 'included': false},
  ],
  'sections': [
    {
      'key': 'similarities',
      'title': 'Persamaan',
      'points': [
        {'text': 'Keduanya menyisipkan data pada tag HTML', 'paper_ids': ['a', 'b']},
      ],
      'paragraph': 'Keduanya menyisipkan data (Al-Qaheri dkk., 2010; Dey dkk., 2010).',
    },
    {
      'key': 'gaps',
      'title': 'Celah & Peluang Penelitian',
      'points': [
        {'text': 'Belum diuji terhadap steganalisis', 'paper_ids': ['a']},
      ],
      'paragraph': 'Belum diuji (Al-Qaheri dkk., 2010).',
    },
  ],
  'research_ideas': [
    {'title': 'Steganografi tahan minifikasi', 'rationale': 'Menguji ketahanan.', 'paper_ids': ['a', 'b']},
  ],
  'paper_positions': [
    {'paper_id': 'a', 'text': 'Pelopor teknik huruf kapital'},
    {'paper_id': 'b', 'text': 'Merancang automata DFA'},
  ],
  'academic_text': 'Persamaan\nKeduanya menyisipkan data (Al-Qaheri dkk., 2010; Dey dkk., 2010).\n\nDaftar Pustaka\nAl-Qaheri, H. (2010). Hiding inside Html.',
});

Future<void> pumpCard(WidgetTester tester, FakeSynthesisRepository repo) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [projectSynthesisRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProjectSynthesisCard(
              projectId: 'project',
              projectTitle: 'HTML new',
              paperCount: 3,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> mockClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

void main() {
  testWidgets('generates a global synthesis with paper references', (tester) async {
    final repo = FakeSynthesisRepository();
    await pumpCard(tester, repo);

    expect(find.textContaining('semua 3 paper'), findsWidgets);
    await tester.tap(find.byKey(const Key('synthesis-generate')));
    await tester.pumpAndSettle();

    expect(repo.forceFlags, [false]);
    expect(find.text('Persamaan'), findsOneWidget);
    expect(find.text('Keduanya menyisipkan data pada tag HTML'), findsOneWidget);
    expect(find.text('Paper 1 & 2'), findsWidgets);
    expect(find.text('Celah & Peluang Penelitian'), findsOneWidget);
    expect(find.text('Steganografi tahan minifikasi'), findsOneWidget);
    expect(find.text('Posisi Tiap Paper'), findsOneWidget);
    expect(find.textContaining('(belum ada hasil review)'), findsOneWidget);
    expect(find.textContaining('gemini-flash-latest'), findsOneWidget);
  });

  testWidgets('saved synthesis loads without calling AI and can be copied', (tester) async {
    final repo = FakeSynthesisRepository(saved: sampleSynthesis());
    final copied = mockClipboard(tester);
    await pumpCard(tester, repo);

    expect(repo.forceFlags, isEmpty);
    expect(find.text('Persamaan'), findsOneWidget);

    await tester.tap(find.byKey(const Key('synthesis-copy-academic')));
    await tester.pumpAndSettle();
    expect(copied.last, sampleSynthesis().academicText);
    expect(find.text('Paragraf akademik dan daftar pustaka disalin.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('synthesis-copy-points')));
    await tester.pumpAndSettle();
    expect(copied.last, contains('Sintesis AI: HTML new'));
    expect(copied.last, contains('- Keduanya menyisipkan data pada tag HTML (Paper 1 & 2)'));
    expect(copied.last, contains('1. Steganografi tahan minifikasi (Paper 1 & 2)'));
    expect(copied.last, contains('Paper 1: Pelopor teknik huruf kapital'));
    expect(copied.last, contains('Paper 3: Web Retrieval (Bassil, 2012)'));
  });

  testWidgets('stale synthesis offers a forced update', (tester) async {
    final repo = FakeSynthesisRepository(saved: sampleSynthesis(stale: true));
    await pumpCard(tester, repo);

    expect(find.byKey(const Key('synthesis-stale')), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('synthesis-stale')),
        matching: find.text('Perbarui'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repo.forceFlags, [true]);
    expect(find.byKey(const Key('synthesis-stale')), findsNothing);
  });

  testWidgets('shows the backend error and retries', (tester) async {
    final options = RequestOptions(path: '/synthesis');
    final repo = FakeSynthesisRepository(
      generated: [
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: options,
            statusCode: 503,
            data: {'detail': 'Kuota Gemini sedang habis. Coba lagi beberapa saat lagi.'},
          ),
        ),
        sampleSynthesis(),
      ],
    );
    await pumpCard(tester, repo);

    await tester.tap(find.byKey(const Key('synthesis-generate')));
    await tester.pumpAndSettle();
    expect(
      find.text('Kuota Gemini sedang habis. Coba lagi beberapa saat lagi.'),
      findsOneWidget,
    );
    expect(find.textContaining('DioException'), findsNothing);

    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(repo.forceFlags, [false, false]);
    expect(find.byKey(const Key('synthesis-error')), findsNothing);
    expect(find.text('Persamaan'), findsOneWidget);
  });
}
