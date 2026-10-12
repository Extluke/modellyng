import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/data/global_chat_cache_service.dart';
import 'package:modellyng/src/data/global_chat_repository.dart';
import 'package:modellyng/src/data/paper_repository.dart';
import 'package:modellyng/src/data/project_repository.dart';
import 'package:modellyng/src/models/research_models.dart';
import 'package:modellyng/src/screens/global_chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockGlobalChatRepository extends Fake implements GlobalChatRepository {
  String? lastReceivedProjectId;
  String? lastReceivedPaperId;
  String? lastQuestion;

  @override
  Future<GlobalChatResponse> sendQuestion(
    String question,
    List<GlobalChatMessage> history, {
    String? projectId,
    String? paperId,
  }) async {
    lastQuestion = question;
    lastReceivedProjectId = projectId;
    lastReceivedPaperId = paperId;

    if (projectId == 'proj-1') {
      if (paperId == 'paper-1') {
        return const GlobalChatResponse(
          answer:
              'Berdasarkan dokumen Sensor Node Dataset, akurasi sensor adalah 98%.',
          modelName: 'gemini-2.0-flash',
          referencedProject: 'Smart Farming IoT',
          referencedPaper: 'Sensor Node Dataset',
        );
      }
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

  final List<ProjectPaper> testPapers = [
    ProjectPaper(
      id: 'paper-1',
      projectId: 'proj-1',
      title: 'Sensor Node Dataset',
      originalFilename: 'sensor_node_dataset.pdf',
      storageKey: 'proj-1/sensor_node_dataset.pdf',
      fileSizeBytes: 102400,
      status: PaperStatus.ready,
      pageCount: 12,
      languageCode: 'en',
      authors: const [],
      jobStatus: PaperJobStatus.completed,
      processingStage: null,
      processingProgress: 1.0,
      processingError: null,
      createdAt: DateTime.parse('2026-10-10T10:00:00Z'),
    ),
    ProjectPaper(
      id: 'paper-2',
      projectId: 'proj-1',
      title: 'Irrigation Control Algorithm',
      originalFilename: 'irrigation_control.pdf',
      storageKey: 'proj-1/irrigation_control.pdf',
      fileSizeBytes: 204800,
      status: PaperStatus.ready,
      pageCount: 8,
      languageCode: 'en',
      authors: const [],
      jobStatus: PaperJobStatus.completed,
      processingStage: null,
      processingProgress: 1.0,
      processingError: null,
      createdAt: DateTime.parse('2026-10-10T11:00:00Z'),
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
            projectPapersProvider((
              userId: 'user-test',
              projectId: 'proj-1',
            )).overrideWith((ref) async => testPapers),
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
      expect(find.text('Proyek: Smart Farming IoT'), findsOneWidget);

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
      expect(mockRepo.lastReceivedPaperId, isNull);
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
    'Typing / without selected project displays warning notice to select project first',
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
      await tester.enterText(textFieldFinder, '/');
      await tester.pumpAndSettle();

      // Warning popup must appear
      expect(
        find.byKey(const Key('paper-mention-popup-no-project')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Pilih proyek menggunakan @ terlebih dahulu sebelum memilih dokumen PDF (/).',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Typing / with project selected shows extracted PDFs, filters by query, and connects PDF parameter',
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
            projectPapersProvider((
              userId: 'user-test',
              projectId: 'proj-1',
            )).overrideWith((ref) async => testPapers),
          ],
          child: const MaterialApp(home: GlobalChatScreen(userId: 'user-test')),
        ),
      );

      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);

      // 1. Select project first via @
      await tester.enterText(textFieldFinder, '@');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('project-mention-option-proj-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('linked-project-badge')), findsOneWidget);
      expect(find.text('Proyek: Smart Farming IoT'), findsOneWidget);

      // 2. Now type /
      await tester.enterText(textFieldFinder, '@Smart Farming IoT /');
      await tester.pumpAndSettle();

      // Paper mention popup should appear with documents
      expect(find.byKey(const Key('paper-mention-popup')), findsOneWidget);
      expect(find.text('Sensor Node Dataset'), findsOneWidget);
      expect(find.text('Irrigation Control Algorithm'), findsOneWidget);

      // 3. Filter query with /Sensor
      await tester.enterText(textFieldFinder, '@Smart Farming IoT /Sensor');
      await tester.pumpAndSettle();

      expect(find.text('Sensor Node Dataset'), findsOneWidget);
      expect(find.text('Irrigation Control Algorithm'), findsNothing);

      // 4. Tap the PDF item
      await tester.tap(find.byKey(const Key('paper-mention-option-paper-1')));
      await tester.pumpAndSettle();

      // Popup dismissed
      expect(find.byKey(const Key('paper-mention-popup')), findsNothing);

      // Input field updated with mention
      expect(
        find.text('@Smart Farming IoT /Sensor Node Dataset '),
        findsOneWidget,
      );

      // Linked badge now shows both Project and PDF
      expect(find.text('Proyek: Smart Farming IoT'), findsOneWidget);
      expect(find.text('PDF: Sensor Node Dataset'), findsOneWidget);

      // 5. Append question and send
      await tester.enterText(
        textFieldFinder,
        '@Smart Farming IoT /Sensor Node Dataset berapa akurasi sensornya?',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('send-chat-button')));
      await tester.pumpAndSettle();

      // Verify parameters sent to repository
      expect(mockRepo.lastReceivedProjectId, equals('proj-1'));
      expect(mockRepo.lastReceivedPaperId, equals('paper-1'));
      expect(
        mockRepo.lastQuestion,
        equals(
          '@Smart Farming IoT /Sensor Node Dataset berapa akurasi sensornya?',
        ),
      );

      // Verify chat UI renders badges for both Proyek and PDF
      expect(find.text('Proyek: Smart Farming IoT'), findsWidgets);
      expect(find.text('PDF: Sensor Node Dataset'), findsWidgets);
      expect(
        find.text(
          'Berdasarkan dokumen Sensor Node Dataset, akurasi sensor adalah 98%.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'User can unlink project and paper before sending by tapping remove button on badge',
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
            projectPapersProvider((
              userId: 'user-test',
              projectId: 'proj-2',
            )).overrideWith((ref) async => []),
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
      expect(find.text('Proyek: AI Diagnostic Healthcare'), findsOneWidget);

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
      expect(mockRepo.lastReceivedPaperId, isNull);
    },
  );
}
