import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/data/global_chat_cache_service.dart';
import 'package:modellyng/src/data/global_chat_repository.dart';
import 'package:modellyng/src/screens/global_chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeGlobalChatRepository extends Fake implements GlobalChatRepository {
  @override
  Future<GlobalChatResponse> sendQuestion(
    String question,
    List<GlobalChatMessage> history,
  ) async {
    return const GlobalChatResponse(
      answer: 'Ini adalah respons asisten AI yang dicache.',
      modelName: 'gemini-2.0-flash',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GlobalChatCacheService - 24-Hour Cache Logic', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves and retrieves valid chat messages within 24 hours', () async {
      const service = GlobalChatCacheService();
      final now = DateTime.now();

      final initialMessages = [
        GlobalChatMessage(
          role: 'user',
          content: 'Halo, bagaimana cara membuat proyek baru?',
          timestamp: now.subtract(const Duration(hours: 2)),
        ),
        GlobalChatMessage(
          role: 'assistant',
          content: 'Ketuk tombol "+ Proyek Baru" di halaman Proyek.',
          timestamp: now.subtract(const Duration(hours: 1)),
        ),
      ];

      await service.saveHistory('user-123', initialMessages);

      final retrieved = await service.getValidHistory('user-123', now: now);
      expect(retrieved.length, equals(2));
      expect(retrieved[0].role, equals('user'));
      expect(
        retrieved[0].content,
        equals('Halo, bagaimana cara membuat proyek baru?'),
      );
      expect(retrieved[1].role, equals('assistant'));
      expect(
        retrieved[1].content,
        equals('Ketuk tombol "+ Proyek Baru" di halaman Proyek.'),
      );
    });

    test(
      'automatically purges messages older than 24 hours (TTL expiration)',
      () async {
        const service = GlobalChatCacheService();
        final now = DateTime.now();

        final mixedMessages = [
          // Expired message: 25 hours old
          GlobalChatMessage(
            role: 'user',
            content: 'Pesan kemarin yang sudah kedaluwarsa.',
            timestamp: now.subtract(const Duration(hours: 25)),
          ),
          // Expired assistant reply: 24.5 hours old
          GlobalChatMessage(
            role: 'assistant',
            content: 'Jawaban kemarin.',
            timestamp: now.subtract(const Duration(hours: 24, minutes: 30)),
          ),
          // Active message: 2 hours old
          GlobalChatMessage(
            role: 'user',
            content: 'Pesan hari ini yang masih valid.',
            timestamp: now.subtract(const Duration(hours: 2)),
          ),
        ];

        await service.saveHistory('user-123', mixedMessages);

        // Verify getValidHistory filters out expired ones
        final valid = await service.getValidHistory('user-123', now: now);
        expect(valid.length, equals(1));
        expect(valid.first.content, equals('Pesan hari ini yang masih valid.'));

        // Verify the storage was pruned
        final prefs = await SharedPreferences.getInstance();
        final storedRaw = prefs.getString(
          GlobalChatCacheService.cacheKey('user-123'),
        );
        expect(storedRaw, isNotNull);
        final storedList = jsonDecode(storedRaw!) as List;
        expect(storedList.length, equals(1));
        expect(
          storedList[0]['content'],
          equals('Pesan hari ini yang masih valid.'),
        );
      },
    );

    test('enforces user isolation: User A cannot see User B cache', () async {
      const service = GlobalChatCacheService();
      final now = DateTime.now();

      await service.saveHistory('user-A', [
        GlobalChatMessage(
          role: 'user',
          content: 'Rahasia User A',
          timestamp: now,
        ),
      ]);

      await service.saveHistory('user-B', [
        GlobalChatMessage(
          role: 'user',
          content: 'Catatan User B',
          timestamp: now,
        ),
      ]);

      final userAMessages = await service.getValidHistory('user-A', now: now);
      final userBMessages = await service.getValidHistory('user-B', now: now);

      expect(userAMessages.length, equals(1));
      expect(userAMessages.first.content, equals('Rahasia User A'));

      expect(userBMessages.length, equals(1));
      expect(userBMessages.first.content, equals('Catatan User B'));
    });

    test('clearHistory completely removes the user cache key', () async {
      const service = GlobalChatCacheService();
      await service.saveHistory('user-123', [
        GlobalChatMessage(
          role: 'user',
          content: 'Akan dihapus',
          timestamp: DateTime.now(),
        ),
      ]);

      await service.clearHistory('user-123');

      final result = await service.getValidHistory('user-123');
      expect(result, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey(GlobalChatCacheService.cacheKey('user-123')),
        isFalse,
      );
    });

    test('gracefully handles corrupt JSON in SharedPreferences', () async {
      const service = GlobalChatCacheService();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        GlobalChatCacheService.cacheKey('user-corrupt'),
        '{invalid-json',
      );

      final result = await service.getValidHistory('user-corrupt');
      expect(result, isEmpty);
    });
  });

  group('GlobalChatScreen - UI 24-Hour Cache Integration', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets(
      'renders 24-hour cache notice banner before user inputs first prompt, and hides it once prompt is entered',
      (tester) async {
        const cacheService = GlobalChatCacheService();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              globalChatRepositoryProvider.overrideWithValue(
                FakeGlobalChatRepository(),
              ),
              globalChatCacheServiceProvider.overrideWithValue(cacheService),
            ],
            child: const MaterialApp(
              home: GlobalChatScreen(userId: 'user-empty'),
            ),
          ),
        );

        // Initial loading state
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        await tester.pumpAndSettle();

        // Banner check: Before any user prompt, banner MUST appear
        expect(find.byKey(const Key('chat-cache-banner')), findsOneWidget);
        expect(
          find.text('Sistem akan menghapus riwayat chat dalam waktu 1x24 jam.'),
          findsOneWidget,
        );

        // User inputs their first prompt
        await tester.enterText(
          find.byType(TextField),
          'Halo asisten, jelaskan metodologi penelitian ini.',
        );
        await tester.tap(find.byKey(const Key('send-chat-button')));
        await tester.pumpAndSettle();

        // The banner MUST now disappear because the first prompt was successfully entered
        expect(find.byKey(const Key('chat-cache-banner')), findsNothing);
        expect(
          find.text('Sistem akan menghapus riwayat chat dalam waktu 1x24 jam.'),
          findsNothing,
        );

        // Both user prompt and assistant response should be visible
        expect(
          find.text('Halo asisten, jelaskan metodologi penelitian ini.'),
          findsOneWidget,
        );
        expect(
          find.text('Ini adalah respons asisten AI yang dicache.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'banner does not show if history already contains previous user prompts',
      (tester) async {
        final now = DateTime.now();
        const cacheService = GlobalChatCacheService();
        await cacheService.saveHistory('user-456', [
          GlobalChatMessage(
            role: 'user',
            content: 'Pertanyaan tersimpan dari sesi sebelumnya',
            timestamp: now.subtract(const Duration(hours: 1)),
          ),
          GlobalChatMessage(
            role: 'assistant',
            content: 'Jawaban tersimpan dari sesi sebelumnya',
            timestamp: now.subtract(const Duration(minutes: 50)),
          ),
        ]);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              globalChatRepositoryProvider.overrideWithValue(
                FakeGlobalChatRepository(),
              ),
              globalChatCacheServiceProvider.overrideWithValue(cacheService),
            ],
            child: const MaterialApp(
              home: GlobalChatScreen(userId: 'user-456'),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Banner should NOT be visible because user prompt already exists
        expect(find.byKey(const Key('chat-cache-banner')), findsNothing);

        // Cached messages rendered
        expect(
          find.text('Pertanyaan tersimpan dari sesi sebelumnya'),
          findsOneWidget,
        );
        expect(
          find.text('Jawaban tersimpan dari sesi sebelumnya'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'clearing chat history prompts confirmation, wipes cache, and brings banner back',
      (tester) async {
        const cacheService = GlobalChatCacheService();
        await cacheService.saveHistory('user-789', [
          GlobalChatMessage(
            role: 'user',
            content: 'Pesan yang akan dihapus manual',
            timestamp: DateTime.now(),
          ),
          GlobalChatMessage(
            role: 'assistant',
            content: 'Jawaban yang akan dihapus manual',
            timestamp: DateTime.now(),
          ),
        ]);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              globalChatRepositoryProvider.overrideWithValue(
                FakeGlobalChatRepository(),
              ),
              globalChatCacheServiceProvider.overrideWithValue(cacheService),
            ],
            child: const MaterialApp(
              home: GlobalChatScreen(userId: 'user-789'),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.text('Pesan yang akan dihapus manual'), findsOneWidget);
        // Banner initially hidden because user prompt exists
        expect(find.byKey(const Key('chat-cache-banner')), findsNothing);

        // Tap clear history button in AppBar
        expect(
          find.byKey(const Key('clear-chat-history-button')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('clear-chat-history-button')));
        await tester.pumpAndSettle();

        // Confirmation dialog should be visible
        expect(find.text('Hapus Riwayat Chat?'), findsOneWidget);
        expect(
          find.text(
            'Percakapan sementara Anda akan dihapus dari penyimpanan perangkat.',
          ),
          findsOneWidget,
        );

        // Tap "Hapus" button in dialog
        await tester.tap(find.text('Hapus'));
        await tester.pumpAndSettle();

        // Messages should be cleared and reset to initial greeting
        expect(find.text('Pesan yang akan dihapus manual'), findsNothing);
        expect(
          find.text(
            'Halo! Saya adalah asisten AI Modellyng. Ada yang bisa saya bantu terkait penggunaan aplikasi ini, atau apakah Anda ingin berdiskusi mengenai penelitian secara umum?',
          ),
          findsOneWidget,
        );

        // Banner should now reappar because there are no user prompts anymore
        expect(find.byKey(const Key('chat-cache-banner')), findsOneWidget);
        expect(
          find.text('Sistem akan menghapus riwayat chat dalam waktu 1x24 jam.'),
          findsOneWidget,
        );

        // Storage should now be empty for user-789
        final validInCache = await cacheService.getValidHistory('user-789');
        expect(validInCache, isEmpty);
      },
    );
  });
}
