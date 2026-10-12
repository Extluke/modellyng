import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/data/global_chat_cache_service.dart';
import 'package:modellyng/src/data/global_chat_repository.dart';
import 'package:modellyng/src/data/project_repository.dart';
import 'package:modellyng/src/models/research_models.dart';
import 'package:modellyng/src/screens/global_chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockGlobalChatRepository extends Fake implements GlobalChatRepository {
  String? lastReceivedProjectId;
  String? lastQuestion;

  @override
  Future<GlobalChatResponse> sendQuestion(
    String question,
    List<GlobalChatMessage> history, {
    String? projectId,
  }) async {
    lastQuestion = question;
    lastReceivedProjectId = projectId;

    if (projectId == 'proj-1') {
      return const GlobalChatResponse(
        answer:
            'Berdasarkan proyek Smart Farming IoT, metodologi menggunakan sensor ESP32.',
        modelName: 'gemini-2.0-flash',
        referencedProject: 'Smart Farming IoT',
      );
    }

    return const GlobalChatResponse(
      answer: 'Ini adalah jawaban AI umum.',
      modelName: 'gemini-2.0-flash',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<ResearchProject> testProjects = [
    const ResearchProject(
      id: 'proj-1',
      title: 'Smart Farming IoT',
      description: 'Penelitian IoT untuk irigasi otomatis',
      status: ProjectStatus.ready,
      paperCount: 3,
      reviewCount: 0,
      readyCount: 3,
      progress: 1.0,
      updatedLabel: 'Baru saja',
      accent: Colors.indigo,
    ),
    const ResearchProject(
      id: 'proj-2',
      title: 'AI Diagnostic Healthcare',
      description: 'Deteksi penyakit paru berbasis CNN',
      status: ProjectStatus.ready,
      paperCount: 5,
      reviewCount: 0,
      readyCount: 5,
      progress: 1.0,
      updatedLabel: 'Baru saja',
      accent: Colors.teal,
    ),
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Typing @ displays project mention popup and tapping a project connects it',
    (tester) async {
      final mockRepo = MockGlobalChatRepository();
      const cacheService = GlobalChatCacheService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            globalChatRepositoryProvider.overrideWithValue(mockRepo),
            globalChatCacheServiceProvider.overrideWithValue(cacheService),
            projectsProvider(
              'user-test',
            ).overrideWith((ref) async => testProjects),
          ],
          child: const MaterialApp(home: GlobalChatScreen(userId: 'user-test')),
        ),
      );

      await tester.pumpAndSettle();

      // Initially no popup
      expect(find.byKey(const Key('project-mention-popup')), findsNothing);

      // Type "@" in the input field
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);

      await tester.enterText(textFieldFinder, '@');
      await tester.pumpAndSettle();

      // Popup should be visible with project options
      expect(find.byKey(const Key('project-mention-popup')), findsOneWidget);
      expect(
        find.text('Pilih Proyek untuk Dijadikan Referensi'),
        findsOneWidget,
      );
      expect(find.text('Smart Farming IoT'), findsOneWidget);
      expect(find.text('AI Diagnostic Healthcare'), findsOneWidget);

      // Filter query: type "@Smart"
      await tester.enterText(textFieldFinder, '@Smart');
      await tester.pumpAndSettle();

      expect(find.text('Smart Farming IoT'), findsOneWidget);
      expect(find.text('AI Diagnostic Healthcare'), findsNothing);

      // Tap on the project item
      await tester.tap(find.byKey(const Key('project-mention-option-proj-1')));
      await tester.pumpAndSettle();

      // Popup should be dismissed
      expect(find.byKey(const Key('project-mention-popup')), findsNothing);

      // Input field text should be updated with mention
      expect(find.text('@Smart Farming IoT '), findsOneWidget);

      // Linked project badge should appear
      expect(find.byKey(const Key('linked-project-badge')), findsOneWidget);
      expect(
        find.text('Tersambung ke proyek: Smart Farming IoT'),
        findsOneWidget,
      );

      // Append text to the question
      await tester.enterText(
        textFieldFinder,
        '@Smart Farming IoT jelaskan sensor apa yang digunakan?',
      );
      await tester.pumpAndSettle();

      // Send the question
      await tester.tap(find.byKey(const Key('send-chat-button')));
      await tester.pumpAndSettle();

      // Verify repository received projectId 'proj-1'
      expect(mockRepo.lastReceivedProjectId, equals('proj-1'));
      expect(
        mockRepo.lastQuestion,
        equals('@Smart Farming IoT jelaskan sensor apa yang digunakan?'),
      );

      // Verify the chat message has project tag
      expect(find.text('Proyek: Smart Farming IoT'), findsWidgets);
      expect(
        find.text(
          'Berdasarkan proyek Smart Farming IoT, metodologi menggunakan sensor ESP32.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'User can unlink project before sending by tapping remove button on badge',
    (tester) async {
      final mockRepo = MockGlobalChatRepository();
      const cacheService = GlobalChatCacheService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            globalChatRepositoryProvider.overrideWithValue(mockRepo),
            globalChatCacheServiceProvider.overrideWithValue(cacheService),
            projectsProvider(
              'user-test',
            ).overrideWith((ref) async => testProjects),
          ],
          child: const MaterialApp(home: GlobalChatScreen(userId: 'user-test')),
        ),
      );

      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);
      await tester.enterText(textFieldFinder, '@');
      await tester.pumpAndSettle();

      // Tap project
      await tester.tap(find.byKey(const Key('project-mention-option-proj-2')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('linked-project-badge')), findsOneWidget);
      expect(
        find.text('Tersambung ke proyek: AI Diagnostic Healthcare'),
        findsOneWidget,
      );

      // Tap remove button
      await tester.tap(find.byKey(const Key('remove-linked-project-button')));
      await tester.pumpAndSettle();

      // Badge removed
      expect(find.byKey(const Key('linked-project-badge')), findsNothing);

      // Send text without project linked
      await tester.enterText(textFieldFinder, 'Pertanyaan umum biasa');
      await tester.tap(find.byKey(const Key('send-chat-button')));
      await tester.pumpAndSettle();

      expect(mockRepo.lastReceivedProjectId, isNull);
    },
  );
}
