import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/data/global_chat_cache_service.dart';
import 'package:modellyng/src/data/global_chat_repository.dart';
import 'package:modellyng/src/screens/global_chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _greeting = GlobalChatMessage(
  role: 'assistant',
  content: 'Halo! Saya adalah asisten AI Modellyng.',
);

GlobalChatMessage _user(String content) =>
    GlobalChatMessage(role: 'user', content: content);
GlobalChatMessage _assistant(String content) =>
    GlobalChatMessage(role: 'assistant', content: content);

DioException _dioError({
  int? status,
  Object? data,
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  final options = RequestOptions(path: '/api/v1/assistant/chat');
  return DioException(
    requestOptions: options,
    type: type,
    response: status == null
        ? null
        : Response<Object?>(
            requestOptions: options,
            statusCode: status,
            data: data,
          ),
  );
}

/// Merekam riwayat yang diterima dan bisa dipaksa gagal pada panggilan tertentu.
class _RecordingChatRepository extends Fake implements GlobalChatRepository {
  _RecordingChatRepository({this.failure});

  Object? failure;
  final histories = <List<GlobalChatMessage>>[];
  final questions = <String>[];
  final projectIds = <String?>[];
  final paperIds = <String?>[];

  @override
  Future<GlobalChatResponse> sendQuestion(
    String question,
    List<GlobalChatMessage> history, {
    String? projectId,
    String? paperId,
  }) async {
    questions.add(question);
    histories.add(history);
    projectIds.add(projectId);
    paperIds.add(paperId);
    final error = failure;
    if (error != null) throw error;
    return GlobalChatResponse(
      answer: 'Jawaban untuk "$question"',
      modelName: 'gemini-test',
    );
  }
}

Future<void> _pumpChat(
  WidgetTester tester,
  _RecordingChatRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        globalChatRepositoryProvider.overrideWithValue(repository),
        globalChatCacheServiceProvider.overrideWithValue(
          const GlobalChatCacheService(),
        ),
      ],
      child: const MaterialApp(home: GlobalChatScreen(userId: 'user-history')),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _ask(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byKey(const Key('send-chat-button')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildChatHistory', () {
    test('returns nothing when only the local greeting exists', () {
      expect(buildChatHistory([_greeting]), isEmpty);
      expect(buildChatHistory(const []), isEmpty);
    });

    test('drops the greeting but keeps user questions and AI answers', () {
      final history = buildChatHistory([
        _greeting,
        _user('Apa itu RAG?'),
        _assistant('RAG menggabungkan pencarian dan generasi.'),
        _user('Berikan contoh.'),
      ]);

      expect(history.map((m) => m.role), ['user', 'assistant', 'user']);
      expect(history.first.content, 'Apa itu RAG?');
      expect(history[1].content, 'RAG menggabungkan pencarian dan generasi.');
    });

    test('keeps only the most recent messages in order', () {
      final messages = [
        _greeting,
        for (var i = 0; i < 20; i++)
          i.isEven ? _user('pertanyaan-$i') : _assistant('jawaban-$i'),
      ];

      final history = buildChatHistory(messages);

      expect(history, hasLength(chatHistoryMessageLimit));
      expect(history.first.content, 'pertanyaan-14');
      expect(history.last.content, 'jawaban-19');
    });

    test('never exceeds the limits the backend enforces', () {
      // Backend: maksimal 15 pesan (chat biasa) dan 10 pesan (mode @proyek).
      final history = buildChatHistory([
        for (var i = 0; i < 200; i++) _user('pertanyaan-$i'),
      ]);

      expect(history.length, lessThanOrEqualTo(10));
    });

    test('truncates long answers below the backend 4000 character cap', () {
      final history = buildChatHistory([
        _user('Jelaskan'),
        _assistant('a' * 9000),
      ]);

      final answer = history.last.content;
      expect(answer.length, chatHistoryMessageMaxChars + 1);
      expect(answer, endsWith('…'));
      expect(answer.length, lessThan(4000));
    });

    test('does not split an emoji at the truncation boundary', () {
      final text = '${'a' * (chatHistoryMessageMaxChars - 1)}😀 selesai';

      final truncated = buildChatHistory([_user(text)]).single.content;

      expect(truncated, endsWith('…'));
      // Tidak ada unit surrogate yatim sebelum tanda elipsis.
      final beforeEllipsis = truncated.codeUnitAt(truncated.length - 2);
      expect(beforeEllipsis >= 0xD800 && beforeEllipsis <= 0xDBFF, isFalse);
    });

    test('leaves short messages untouched', () {
      final history = buildChatHistory([_user('Halo')]);

      expect(history.single.content, 'Halo');
    });
  });

  group('chatErrorMessage', () {
    test('shows the backend detail instead of raw Dio text', () {
      final message = chatErrorMessage(
        _dioError(
          status: 503,
          data: {
            'detail':
                'Gemini sedang sibuk atau kuotanya habis. Coba lagi beberapa saat.',
          },
        ),
      );

      expect(
        message,
        'Gemini sedang sibuk atau kuotanya habis. Coba lagi beberapa saat.',
      );
      expect(message, isNot(contains('DioException')));
    });

    test('explains validation errors in plain language', () {
      final message = chatErrorMessage(
        _dioError(
          status: 422,
          data: {
            'detail': [
              {'type': 'string_too_long', 'loc': ['body', 'question']},
            ],
          },
        ),
      );

      expect(message, contains('terlalu panjang'));
      expect(message, isNot(contains('string_too_long')));
    });

    test('handles server errors without a body', () {
      expect(chatErrorMessage(_dioError(status: 500)), contains('tidak tersedia'));
      expect(chatErrorMessage(_dioError(status: 503)), contains('tidak tersedia'));
    });

    test('handles connection problems and timeouts', () {
      expect(
        chatErrorMessage(_dioError(type: DioExceptionType.connectionError)),
        contains('belum dapat dihubungi'),
      );
      expect(
        chatErrorMessage(_dioError(type: DioExceptionType.receiveTimeout)),
        contains('terlalu lama'),
      );
    });

    test('falls back to a generic message for unknown errors', () {
      expect(
        chatErrorMessage(StateError('boom')),
        'Pesan belum dapat dikirim. Silakan coba lagi.',
      );
    });
  });

  group('GlobalChatScreen history and failures', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('sends a bounded history that includes AI answers', (
      tester,
    ) async {
      final repository = _RecordingChatRepository();
      await _pumpChat(tester, repository);

      for (var i = 1; i <= 20; i++) {
        await _ask(tester, 'pertanyaan $i');
      }

      expect(repository.histories, hasLength(20));
      // Pertanyaan pertama belum punya konteks: sapaan lokal tidak dikirim.
      expect(repository.histories.first, isEmpty);
      // Pertanyaan kedua melihat pertanyaan dan jawaban sebelumnya.
      expect(repository.histories[1].map((m) => m.role), ['user', 'assistant']);
      expect(repository.histories[1].last.content, contains('pertanyaan 1'));
      // Setelah banyak giliran, riwayat tetap dibatasi.
      for (final history in repository.histories) {
        expect(history.length, lessThanOrEqualTo(chatHistoryMessageLimit));
      }
      expect(repository.histories.last.last.role, 'assistant');
    });

    testWidgets(
      'a failed question shows the backend message, leaves the history and returns to the input',
      (tester) async {
        final repository = _RecordingChatRepository(
          failure: _dioError(
            status: 503,
            data: {
              'detail':
                  'Gemini sedang sibuk atau kuotanya habis. Coba lagi beberapa saat.',
            },
          ),
        );
        await _pumpChat(tester, repository);
        expect(find.byKey(const Key('chat-cache-banner')), findsOneWidget);

        await _ask(tester, 'Jelaskan metodologi penelitian ini.');

        // Pesan error ramah, bukan teks mentah DioException.
        expect(
          find.text(
            'Gemini sedang sibuk atau kuotanya habis. Coba lagi beberapa saat.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('DioException'), findsNothing);

        // Pertanyaan tidak tertinggal di percakapan tanpa jawaban,
        // tetapi kembali ke kolom ketik untuk dikirim ulang.
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, 'Jelaskan metodologi penelitian ini.');
        expect(
          find.text('Jelaskan metodologi penelitian ini.'),
          findsOneWidget,
          reason: 'hanya muncul di kolom ketik, bukan di daftar pesan',
        );

        // Belum ada prompt yang berhasil, jadi pemberitahuan 24 jam tetap tampil.
        expect(find.byKey(const Key('chat-cache-banner')), findsOneWidget);

        // Pertanyaan yang gagal tidak ikut tersimpan 24 jam.
        final cached = await const GlobalChatCacheService().getValidHistory(
          'user-history',
        );
        expect(cached.where((m) => m.role == 'user'), isEmpty);

        // Setelah layanan pulih, kirim ulang langsung berhasil dengan riwayat bersih.
        repository.failure = null;
        await tester.tap(find.byKey(const Key('send-chat-button')));
        await tester.pumpAndSettle();

        expect(repository.questions.last, 'Jelaskan metodologi penelitian ini.');
        expect(repository.histories.last, isEmpty);
        expect(
          find.text('Jawaban untuk "Jelaskan metodologi penelitian ini."'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('chat-cache-banner')), findsNothing);
      },
    );
  });
}
