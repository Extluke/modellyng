import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/data/comparative_matrix_repository.dart';
import 'package:modellyng/src/data/concept_map_repository.dart';
import 'package:modellyng/src/data/export_repository.dart';
import 'package:modellyng/src/data/paper_result_repository.dart';
import 'package:modellyng/src/data/project_chat_repository.dart';
import 'package:modellyng/src/data/project_repository.dart';
import 'package:modellyng/src/data/research_gap_repository.dart';
import 'package:modellyng/src/data/review_repository.dart';
import 'package:modellyng/src/models/research_models.dart';
import 'package:modellyng/src/screens/auth_screen.dart';
import 'package:modellyng/src/screens/comparative_matrix_screen.dart';
import 'package:modellyng/src/screens/concept_evidence_map_screen.dart';
import 'package:modellyng/src/screens/dashboard_screen.dart';
import 'package:modellyng/src/screens/export_results_screen.dart';
import 'package:modellyng/src/screens/paper_result_screen.dart';
import 'package:modellyng/src/screens/project_chat_screen.dart';
import 'package:modellyng/src/screens/research_gap_map_screen.dart';
import 'package:modellyng/src/screens/review_queue_screen.dart';
import 'package:modellyng/src/screens/welcome_screen.dart';
import 'package:modellyng/src/widgets/common_widgets.dart';

void main() {
  test('review text validator rejects whitespace and accepts a reason', () {
    expect(
      validateRequiredReviewText('   ', 'Alasan wajib'),
      'Alasan wajib tidak boleh kosong.',
    );
    expect(
      validateRequiredReviewText('Perlu kutipan sumber', 'Alasan wajib'),
      isNull,
    );
  });

  test('export errors preserve JSON detail returned as response bytes', () {
    final request = RequestOptions(path: '/export/docx');
    final error = DioException(
      requestOptions: request,
      response: Response<List<int>>(
        requestOptions: request,
        statusCode: 409,
        data: utf8.encode(
          '{"detail":"Belum ada paper siap yang dapat diekspor."}',
        ),
      ),
    );

    expect(
      ExportRepository.readableError(error),
      'Belum ada paper siap yang dapat diekspor.',
    );
  });

  testWidgets('password visibility control has a changing accessible label', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AuthScreen())),
    );

    expect(find.byTooltip('Tampilkan password'), findsOneWidget);
    await tester.tap(find.byTooltip('Tampilkan password'));
    await tester.pump();
    expect(find.byTooltip('Sembunyikan password'), findsOneWidget);
  });

  testWidgets('review queue refreshes when its tab becomes active', (
    tester,
  ) async {
    var active = false;
    var queueLoads = 0;
    late StateSetter updateHost;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reviewQueueProvider('test-user').overrideWith((ref) async {
            queueLoads++;
            return const [];
          }),
          reviewHistoryProvider(
            'test-user',
          ).overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return Scaffold(
                body: ReviewQueueScreen(userId: 'test-user', active: active),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(queueLoads, 1);

    updateHost(() => active = true);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(queueLoads, 2);
  });

  testWidgets('audit shortcut request opens review history immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reviewQueueProvider(
            'test-user',
          ).overrideWith((ref) async => const []),
          reviewHistoryProvider('test-user').overrideWith(
            (ref) async => [
              ReviewHistoryItem(
                action: 'accept',
                paperTitle: 'Paper Audit',
                parameter: 'methodology',
                note: null,
                createdAt: DateTime(2026),
              ),
            ],
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ReviewQueueScreen(
              userId: 'test-user',
              historyExpansionRequest: 1,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Paper Audit · accept'), findsOneWidget);
  });

  testWidgets('review queue can confirm accepting every visible result', (
    tester,
  ) async {
    final repository = _FakeReviewRepository();
    const items = [
      ReviewQueueItem(
        componentId: 'component-1',
        paperId: 'paper-1',
        projectId: 'project-1',
        projectTitle: 'Proyek A',
        paperTitle: 'Paper A',
        originalFilename: 'paper-a.pdf',
        parameter: 'contribution',
        aiValue: 'Kontribusi A',
        confidence: 1,
        evidence: [],
        modelName: 'Gemini',
      ),
      ReviewQueueItem(
        componentId: 'component-2',
        paperId: 'paper-1',
        projectId: 'project-1',
        projectTitle: 'Proyek A',
        paperTitle: 'Paper A',
        originalFilename: 'paper-a.pdf',
        parameter: 'limitations',
        aiValue: 'Keterbatasan A',
        confidence: 1,
        evidence: [],
        modelName: 'Gemini',
      ),
    ];
    tester.view.physicalSize = const Size(540, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reviewRepositoryProvider.overrideWithValue(repository),
          reviewQueueProvider('test-user').overrideWith((ref) async => items),
          reviewHistoryProvider(
            'test-user',
          ).overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ReviewQueueScreen(userId: 'test-user')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final acceptAll = find.byKey(const Key('accept-all-visible-reviews'));
    expect(find.text('Terima semua (2)'), findsOneWidget);
    await tester.ensureVisible(acceptAll);
    await tester.tap(acceptAll);
    await tester.pumpAndSettle();

    expect(find.text('Terima semua 2 hasil?'), findsOneWidget);
    expect(
      find.textContaining('semua proyek yang sedang tampil'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('confirm-accept-all-reviews')));
    await tester.pumpAndSettle();

    expect(repository.acceptedIds, ['component-1', 'component-2']);
    expect(find.text('2 hasil berhasil diterima.'), findsOneWidget);
  });

  testWidgets('export screen downloads every evidence-preserving format', (
    tester,
  ) async {
    const project = ResearchProject(
      id: 'project-export',
      title: 'Export Project',
      description: '',
      paperCount: 2,
      reviewCount: 0,
      progress: 1,
      status: ProjectStatus.ready,
      updatedLabel: 'Baru saja',
      accent: Colors.indigo,
    );
    final requested = <String>[];
    final saved = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ExportResultsScreen(
            project: project,
            exportLoader: (format) async {
              requested.add(format);
              return ExportDownload(
                bytes: Uint8List.fromList([1, 2, 3]),
                filename: 'result.$format',
                mediaType: 'application/octet-stream',
              );
            },
            fileSaver: (download) => saved.add(download.filename),
          ),
        ),
      ),
    );

    for (final format in ['docx', 'xlsx', 'csv', 'pptx']) {
      final button = find.byKey(Key('export-$format-button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    expect(requested, ['docx', 'xlsx', 'csv', 'pptx']);
    expect(saved, ['result.docx', 'result.xlsx', 'result.csv', 'result.pptx']);
    expect(find.textContaining('nilai AI asli'), findsOneWidget);
  });

  testWidgets('welcome screen exposes the authentication entry point', (
    tester,
  ) async {
    var started = false;
    await tester.pumpWidget(
      MaterialApp(home: WelcomeScreen(onGetStarted: () => started = true)),
    );

    expect(
      find.text('Ubah paper menjadi\npengetahuan yang\ndapat diverifikasi.'),
      findsOneWidget,
    );
    final getStarted = find.byKey(const Key('get-started-button'));
    await tester.ensureVisible(getStarted);
    await tester.tap(getStarted);

    expect(started, isTrue);
  });

  testWidgets('dashboard uses the authenticated display name', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsProvider('test-user').overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          home: DashboardScreen(
            userId: 'test-user',
            displayName: 'Pengguna Pilot',
            onNewProject: () {},
            onOpenProject: (_) {},
            onOpenReview: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selamat datang, Pengguna Pilot'), findsOneWidget);
    expect(find.text('Proyek baru'), findsWidgets);
    expect(find.text('Belum ada proyek'), findsOneWidget);
  });

  testWidgets('dashboard never reuses projects from another user', (
    tester,
  ) async {
    const privateProject = ResearchProject(
      id: 'project-a',
      title: 'Rahasia Akun A',
      description: 'Tidak boleh terlihat akun B',
      paperCount: 0,
      reviewCount: 0,
      progress: 1,
      status: ProjectStatus.ready,
      updatedLabel: 'Baru saja',
      accent: Colors.indigo,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsProvider(
            'user-a',
          ).overrideWith((ref) async => [privateProject]),
          projectsProvider('user-b').overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          home: DashboardScreen(
            userId: 'user-a',
            displayName: 'Akun A',
            onNewProject: () {},
            onOpenProject: (_) {},
            onOpenReview: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rahasia Akun A'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsProvider(
            'user-a',
          ).overrideWith((ref) async => [privateProject]),
          projectsProvider('user-b').overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          home: DashboardScreen(
            userId: 'user-b',
            displayName: 'Akun B',
            onNewProject: () {},
            onOpenProject: (_) {},
            onOpenReview: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rahasia Akun A'), findsNothing);
    expect(find.text('Belum ada proyek'), findsOneWidget);
  });

  testWidgets('dashboard totals papers waiting for review', (tester) async {
    const reviewProject = ResearchProject(
      id: 'project-review',
      title: 'Proyek review',
      description: '',
      paperCount: 4,
      reviewCount: 2,
      progress: 0.85,
      status: ProjectStatus.needsReview,
      updatedLabel: 'Baru saja',
      accent: Colors.indigo,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsProvider(
            'review-user',
          ).overrideWith((ref) async => [reviewProject]),
        ],
        child: MaterialApp(
          home: DashboardScreen(
            userId: 'review-user',
            displayName: 'Reviewer',
            onNewProject: () {},
            onOpenProject: (_) {},
            onOpenReview: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final reviewCard = find.ancestor(
      of: find.text('Menunggu review'),
      matching: find.byType(MetricCard),
    );
    expect(find.descendant(of: reviewCard, matching: find.text('2')), findsOne);
  });

  testWidgets('paper result displays processing state without exposing PDF', (
    tester,
  ) async {
    const query = (projectId: 'project-a', paperId: 'paper-a');
    const result = PaperResult(
      paper: ProjectPaper(
        id: 'paper-a',
        projectId: 'project-a',
        originalFilename: 'private.pdf',
        storageKey: 'user-a/project-a/private.pdf',
        fileSizeBytes: 1024,
        status: PaperStatus.processing,
        pageCount: null,
        languageCode: null,
        title: null,
        authors: [],
        jobStatus: PaperJobStatus.processing,
        processingStage: 'gemini_extraction',
        processingProgress: 0.7,
        processingError: null,
        createdAt: null,
      ),
      components: [],
      structuredTables: StructuredPaperTables(
        researchQuestions: [],
        methodology: [],
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          paperResultProvider(query).overrideWith((ref) async => result),
        ],
        child: const MaterialApp(
          home: PaperResultScreen(projectId: 'project-a', paperId: 'paper-a'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Paper masih diproses'), findsOneWidget);
    expect(find.text('private.pdf'), findsNothing);
  });

  testWidgets(
    'mobile evidence click opens PDF tab safely before viewer ready',
    (tester) async {
      const query = (projectId: 'project-a', paperId: 'paper-a');
      final waitingPdf = Completer<Uint8List>();
      const result = PaperResult(
        paper: ProjectPaper(
          id: 'paper-a',
          projectId: 'project-a',
          originalFilename: 'private.pdf',
          storageKey: 'user-a/project-a/private.pdf',
          fileSizeBytes: 1024,
          status: PaperStatus.needsReview,
          pageCount: 3,
          languageCode: 'en',
          title: 'Private paper',
          authors: [],
          jobStatus: PaperJobStatus.completed,
          processingStage: 'ai_extraction_complete',
          processingProgress: 1,
          processingError: null,
          createdAt: null,
        ),
        components: [
          PaperComponentResult(
            parameter: 'research_problem',
            aiValue: 'AI value',
            finalValue: null,
            status: VerificationStatus.needsReview,
            confidence: 0.9,
            evidence: [ResultEvidence(quote: 'Verified quote', pageNumber: 3)],
          ),
        ],
        structuredTables: StructuredPaperTables(
          researchQuestions: [],
          methodology: [],
        ),
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paperResultProvider(query).overrideWith((ref) async => result),
            paperPdfProvider(query).overrideWith((ref) => waitingPdf.future),
          ],
          child: const MaterialApp(
            home: PaperResultScreen(projectId: 'project-a', paperId: 'paper-a'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1/11 komponen tersedia'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Halaman 3'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('comparative matrix shows reviewed values for two papers', (
    tester,
  ) async {
    const project = ResearchProject(
      id: 'project-matrix',
      title: 'Matrix Project',
      description: '',
      paperCount: 2,
      reviewCount: 0,
      progress: 1,
      status: ProjectStatus.ready,
      updatedLabel: 'Baru saja',
      accent: Colors.indigo,
    );
    const matrix = ComparativeMatrix(
      projectId: 'project-matrix',
      projectTitle: 'Matrix Project',
      papers: [
        MatrixPaper(id: 'paper-a', title: 'Paper A', originalFilename: 'a.pdf'),
        MatrixPaper(id: 'paper-b', title: 'Paper B', originalFilename: 'b.pdf'),
      ],
      rows: [
        MatrixRow(
          parameter: 'methodology',
          cells: [
            MatrixCell(
              paperId: 'paper-a',
              aiValue: 'AI A',
              finalValue: 'Reviewed A',
              status: VerificationStatus.edited,
              confidence: 0.9,
              evidence: [MatrixEvidence(quote: 'Quote A', pageNumber: 4)],
            ),
            MatrixCell(
              paperId: 'paper-b',
              aiValue: 'Reviewed B',
              finalValue: null,
              status: VerificationStatus.verified,
              confidence: 0.8,
              evidence: [],
            ),
          ],
        ),
      ],
    );
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsProvider(
            'matrix-user',
          ).overrideWith((ref) async => [project]),
          comparativeMatrixProvider(
            'project-matrix',
          ).overrideWith((ref) async => matrix),
        ],
        child: const MaterialApp(
          home: ComparativeMatrixScreen(userId: 'matrix-user'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Paper A'), findsOneWidget);
    expect(find.text('Paper B'), findsOneWidget);
    expect(find.text('Reviewed A'), findsOneWidget);
    expect(find.text('Reviewed B'), findsOneWidget);
    expect(find.text('Evidence · hal. 4'), findsOneWidget);
    expect(find.byKey(const Key('combined-matrix-table')), findsOneWidget);
  });

  testWidgets('mobile matrix keeps all papers in one scrollable table', (
    tester,
  ) async {
    const project = ResearchProject(
      id: 'project-mobile-matrix',
      title: 'Mobile Matrix',
      description: '',
      paperCount: 2,
      reviewCount: 0,
      progress: 1,
      status: ProjectStatus.ready,
      updatedLabel: 'Baru saja',
      accent: Colors.indigo,
    );
    const matrix = ComparativeMatrix(
      projectId: 'project-mobile-matrix',
      projectTitle: 'Mobile Matrix',
      papers: [
        MatrixPaper(id: 'paper-a', title: 'Paper A', originalFilename: 'a.pdf'),
        MatrixPaper(id: 'paper-b', title: 'Paper B', originalFilename: 'b.pdf'),
      ],
      rows: [
        MatrixRow(
          parameter: 'methodology',
          cells: [
            MatrixCell(
              paperId: 'paper-a',
              aiValue: 'Method A',
              finalValue: null,
              status: VerificationStatus.verified,
              confidence: .8,
              evidence: [],
            ),
            MatrixCell(
              paperId: 'paper-b',
              aiValue: 'Method B',
              finalValue: null,
              status: VerificationStatus.verified,
              confidence: .8,
              evidence: [],
            ),
          ],
        ),
      ],
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsProvider(
            'matrix-user',
          ).overrideWith((ref) async => [project]),
          comparativeMatrixProvider(
            'project-mobile-matrix',
          ).overrideWith((ref) async => matrix),
        ],
        child: const MaterialApp(
          home: ComparativeMatrixScreen(userId: 'matrix-user'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('combined-matrix-table')), findsOneWidget);
    expect(find.text('Paper yang ditampilkan'), findsNothing);
    expect(find.textContaining('Semua paper sudah digabung'), findsOneWidget);
  });

  testWidgets(
    'comparative matrix blocks comparison with fewer than two papers',
    (tester) async {
      const project = ResearchProject(
        id: 'project-one',
        title: 'One Paper',
        description: '',
        paperCount: 1,
        reviewCount: 0,
        progress: 1,
        status: ProjectStatus.ready,
        updatedLabel: 'Baru saja',
        accent: Colors.indigo,
      );
      const matrix = ComparativeMatrix(
        projectId: 'project-one',
        projectTitle: 'One Paper',
        papers: [
          MatrixPaper(
            id: 'paper-a',
            title: 'Paper A',
            originalFilename: 'a.pdf',
          ),
        ],
        rows: [],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectsProvider(
              'matrix-user',
            ).overrideWith((ref) async => [project]),
            comparativeMatrixProvider(
              'project-one',
            ).overrideWith((ref) async => matrix),
          ],
          child: const MaterialApp(
            home: ComparativeMatrixScreen(userId: 'matrix-user'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Minimal dua paper siap diperlukan'), findsOneWidget);
    },
  );

  testWidgets('concept map renders paper concept evidence chain', (
    tester,
  ) async {
    const project = ResearchProject(
      id: 'project-map',
      title: 'Map Project With A Very Long Responsive Project Title',
      description: '',
      paperCount: 1,
      reviewCount: 0,
      progress: 1,
      status: ProjectStatus.ready,
      updatedLabel: 'Baru saja',
      accent: Colors.indigo,
    );
    const graph = ConceptEvidenceMap(
      projectId: 'project-map',
      projectTitle: 'Map Project',
      nodes: [
        ConceptMapNode(
          id: 'paper:paper-a',
          kind: 'paper',
          label:
              'How to Optimize SQL Queries? A Comparison Between Split, Holistic, and Hybrid Approaches',
          detail: 'a.pdf',
          paperId: 'paper-a',
          parameter: null,
          pageNumber: null,
        ),
        ConceptMapNode(
          id: 'concept:paper-a:methodology',
          kind: 'concept',
          label: 'methodology',
          detail: 'Reviewed method',
          paperId: 'paper-a',
          parameter: 'methodology',
          pageNumber: null,
        ),
        ConceptMapNode(
          id: 'evidence:paper-a:methodology:0',
          kind: 'evidence',
          label: 'Halaman 4',
          detail: 'Verified quote',
          paperId: 'paper-a',
          parameter: 'methodology',
          pageNumber: 4,
        ),
      ],
      edges: [
        ConceptMapEdge(
          source: 'paper:paper-a',
          target: 'concept:paper-a:methodology',
          relation: 'contains',
        ),
        ConceptMapEdge(
          source: 'concept:paper-a:methodology',
          target: 'evidence:paper-a:methodology:0',
          relation: 'supported_by',
        ),
      ],
    );
    tester.view.physicalSize = const Size(420, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsProvider('map-user').overrideWith((ref) async => [project]),
          conceptMapProvider('project-map').overrideWith((ref) async => graph),
        ],
        child: const MaterialApp(
          home: ConceptEvidenceMapScreen(userId: 'map-user'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'How to Optimize SQL Queries? A Comparison Between Split, Holistic, and Hybrid Approaches',
      ),
      findsOneWidget,
    );
    expect(find.text('Flowchart evidence'), findsOneWidget);
    expect(find.text('MERMAID'), findsOneWidget);
    expect(find.byKey(const Key('research-flowchart-mermaid')), findsOneWidget);
    expect(find.textContaining('Ketuk node konsep'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('research gap map labels candidates and preserves PDF evidence', (
    tester,
  ) async {
    const project = ResearchProject(
      id: 'project-gap',
      title: 'Gap Project',
      description: '',
      paperCount: 1,
      reviewCount: 0,
      progress: 1,
      status: ProjectStatus.ready,
      updatedLabel: 'Baru saja',
      accent: Colors.indigo,
    );
    const graph = ResearchGapMap(
      projectId: 'project-gap',
      projectTitle: 'Gap Project',
      candidateCount: 1,
      nodes: [
        ConceptMapNode(
          id: 'paper:paper-a',
          kind: 'paper',
          label: 'Paper A',
          detail: 'a.pdf',
          paperId: 'paper-a',
          parameter: null,
          pageNumber: null,
        ),
        ConceptMapNode(
          id: 'gap:paper-a:limitations',
          kind: 'gap',
          label: 'limitations',
          detail: 'The sample only covered one city.',
          paperId: 'paper-a',
          parameter: 'limitations',
          pageNumber: null,
        ),
        ConceptMapNode(
          id: 'gap-evidence:paper-a:limitations:0',
          kind: 'evidence',
          label: 'Halaman 9',
          detail: 'The study was restricted to one city.',
          paperId: 'paper-a',
          parameter: 'limitations',
          pageNumber: 9,
        ),
      ],
      edges: [
        ConceptMapEdge(
          source: 'paper:paper-a',
          target: 'gap:paper-a:limitations',
          relation: 'suggests_candidate',
        ),
        ConceptMapEdge(
          source: 'gap:paper-a:limitations',
          target: 'gap-evidence:paper-a:limitations:0',
          relation: 'supported_by',
        ),
      ],
    );
    final repository = _FakeGapRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          researchGapRepositoryProvider.overrideWithValue(repository),
          projectsProvider('gap-user').overrideWith((ref) async => [project]),
          researchGapMapProvider(
            'project-gap',
          ).overrideWith((ref) async => graph),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ResearchGapMapScreen(userId: 'gap-user')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Belum diputuskan'), findsOneWidget);
    expect(find.text('The sample only covered one city.'), findsOneWidget);
    expect(find.text('Paper A'), findsOneWidget);
    expect(find.text('Halaman 9'), findsOneWidget);
    expect(find.text('Buka evidence PDF'), findsOneWidget);
    expect(find.text('Yes, gunakan'), findsOneWidget);
    expect(find.text('No, lewati'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, gunakan'));
    await tester.pumpAndSettle();
    expect(repository.saved, [GapDecision.accepted]);
    expect(find.text('Susun rumusan penelitian'), findsOneWidget);
  });

  testWidgets('structured result renders both requested tables', (
    tester,
  ) async {
    const query = (projectId: 'project-table', paperId: 'paper-table');
    const result = PaperResult(
      paper: ProjectPaper(
        id: 'paper-table',
        projectId: 'project-table',
        originalFilename: 'table.pdf',
        storageKey: 'owner/project/table.pdf',
        fileSizeBytes: 2048,
        status: PaperStatus.ready,
        pageCount: 5,
        languageCode: 'en',
        title: 'Structured paper',
        authors: [],
        jobStatus: PaperJobStatus.completed,
        processingStage: 'ai_extraction_complete',
        processingProgress: 1,
        processingError: null,
        createdAt: null,
      ),
      components: [],
      structuredTables: StructuredPaperTables(
        researchQuestions: [
          ResearchQuestionTableRow(
            number: 1,
            question: 'Which index is fastest?',
            relatedObject: 'B-tree index',
            discussionDirection: 'Measure latency',
            evidencePage: 3,
            evidenceQuote: 'Which index is fastest?',
          ),
        ],
        methodology: [
          MethodologyTableRow(
            content: 'Quantitative experiment',
            form: 'Eksperimen / Kuantitatif',
            mainActivity: 'TPC-H benchmark',
            activityDirection: 'Compare indexes',
            finalGoal: 'Measure latency',
          ),
        ],
      ),
    );
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          paperResultProvider(query).overrideWith((ref) async => result),
        ],
        child: const MaterialApp(
          home: PaperResultScreen(
            projectId: 'project-table',
            paperId: 'paper-table',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('research-question-table')), findsOneWidget);
    expect(find.byKey(const Key('methodology-table')), findsOneWidget);
    expect(find.text('Which index is fastest?'), findsOneWidget);
    expect(find.text('B-tree index'), findsOneWidget);
    expect(
      find.byKey(const Key('download-structured-tables-pdf')),
      findsOneWidget,
    );
  });

  testWidgets('project chatbot displays answer and evidence source', (
    tester,
  ) async {
    const project = ResearchProject(
      id: 'project-chat',
      title: 'Chat Project',
      description: '',
      paperCount: 2,
      reviewCount: 0,
      progress: 1,
      status: ProjectStatus.ready,
      updatedLabel: 'Baru saja',
      accent: Colors.indigo,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectChatRepositoryProvider.overrideWithValue(
            _FakeChatRepository(),
          ),
          paperPdfProvider((
            projectId: 'project-chat',
            paperId: 'paper-a',
          )).overrideWith((ref) async => Uint8List(0)),
        ],
        child: const MaterialApp(home: ProjectChatScreen(project: project)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apa perbedaan metodologi antar paper?'));
    await tester.pumpAndSettle();
    expect(
      find.text('Paper A memakai survei; Paper B memakai eksperimen.'),
      findsOneWidget,
    );
    expect(find.textContaining('S1 · Paper A · hal. 4'), findsOneWidget);
    expect(find.textContaining('perlu diverifikasi'), findsOneWidget);

    final sourceButton = find.byKey(const Key('chat-source-S1'));
    await tester.ensureVisible(sourceButton);
    tester.widget<TextButton>(sourceButton).onPressed!();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final viewer = tester.widget<PaperResultScreen>(
      find.byType(PaperResultScreen),
    );
    expect(viewer.paperId, 'paper-a');
    expect(viewer.initialPage, 4);
    expect(viewer.initialHighlightText, 'We conducted a survey.');
    expect(viewer.initialBlockId, '00000000-0000-0000-0000-000000000099');
  });

  testWidgets('project chatbot restores permanent history with citations', (
    tester,
  ) async {
    const project = ResearchProject(
      id: 'project-history',
      title: 'History Project',
      description: '',
      paperCount: 1,
      reviewCount: 0,
      progress: 1,
      status: ProjectStatus.ready,
      updatedLabel: 'Baru saja',
      accent: Colors.indigo,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectChatRepositoryProvider.overrideWithValue(
            _HistoryChatRepository(),
          ),
        ],
        child: const MaterialApp(home: ProjectChatScreen(project: project)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pertanyaan tersimpan'), findsOneWidget);
    expect(find.text('Jawaban tersimpan dari PDF.'), findsOneWidget);
    expect(
      find.textContaining('S1 · Paper Persisten · hal. 7'),
      findsOneWidget,
    );
    expect(find.textContaining('perlu diverifikasi'), findsOneWidget);
  });

  testWidgets('citation navigation opens the PDF evidence tab immediately', (
    tester,
  ) async {
    const query = (projectId: 'project-citation', paperId: 'paper-citation');
    const result = PaperResult(
      paper: ProjectPaper(
        id: 'paper-citation',
        projectId: 'project-citation',
        originalFilename: 'citation.pdf',
        storageKey: 'owner/project/citation.pdf',
        fileSizeBytes: 1024,
        status: PaperStatus.ready,
        pageCount: 4,
        languageCode: 'en',
        title: 'Citation paper',
        authors: [],
        jobStatus: PaperJobStatus.completed,
        processingStage: 'ai_extraction_complete',
        processingProgress: 1,
        processingError: null,
        createdAt: null,
      ),
      components: [],
      structuredTables: StructuredPaperTables(
        researchQuestions: [],
        methodology: [],
      ),
    );
    tester.view.physicalSize = const Size(540, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          paperResultProvider(query).overrideWith((ref) async => result),
          paperPdfProvider(
            query,
          ).overrideWith((ref) => Completer<Uint8List>().future),
        ],
        child: const MaterialApp(
          home: PaperResultScreen(
            projectId: 'project-citation',
            paperId: 'paper-citation',
            initialPage: 4,
            initialHighlightText: 'The supporting paragraph.',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller!.index, 1);
    expect(find.text('Mengunduh PDF privat…'), findsOneWidget);
  });

  test('PDF citation highlight tolerates line breaks and punctuation', () {
    final pattern = buildPdfHighlightPattern(
      'We conducted a\nsurvey, across multiple organizations.',
      'We conducted a survey across multiple organizations.',
    );
    expect(pattern, isNotNull);
    expect(
      pattern!.hasMatch(
        'We conducted a\nsurvey, across multiple organizations.',
      ),
      isTrue,
    );
    expect(buildPdfHighlightPattern('unrelated page', 'missing quote'), isNull);
  });
}

class _FakeGapRepository extends ResearchGapRepository {
  _FakeGapRepository() : super(Dio());
  final saved = <GapDecision>[];
  final decisions = <ResearchGapDecision>[];

  @override
  Future<List<ResearchGapDecision>> getDecisions(String projectId) async =>
      List.unmodifiable(decisions);

  @override
  Future<ResearchGapDecision> saveDecision({
    required String projectId,
    required String paperId,
    required String parameter,
    required GapDecision decision,
  }) async {
    saved.add(decision);
    final value = ResearchGapDecision(
      id: 'decision-1',
      projectId: projectId,
      paperId: paperId,
      parameter: parameter,
      decision: decision,
      note: null,
    );
    decisions
      ..clear()
      ..add(value);
    return value;
  }
}

class _FakeReviewRepository extends ReviewRepository {
  _FakeReviewRepository() : super(Dio());

  List<String> acceptedIds = [];

  @override
  Future<int> acceptAll(List<String> componentIds) async {
    acceptedIds = List.of(componentIds);
    return componentIds.length;
  }
}

class _FakeChatRepository extends ProjectChatRepository {
  _FakeChatRepository() : super(Dio());

  @override
  Future<List<StoredProjectChatMessage>> getHistory(String projectId) async =>
      const [];

  @override
  Future<ProjectChatAnswer> ask({
    required String projectId,
    required String question,
    required List<ChatHistoryMessage> history,
  }) async => const ProjectChatAnswer(
    answer: 'Paper A memakai survei; Paper B memakai eksperimen.',
    sources: [
      ProjectChatSource(
        sourceId: 'S1',
        paperId: 'paper-a',
        paperTitle: 'Paper A',
        parameter: 'methodology',
        quote: 'We conducted a survey.',
        pageNumber: 4,
        blockId: '00000000-0000-0000-0000-000000000099',
      ),
    ],
    modelName: 'gemini-test',
    reviewNotice: 'Jawaban AI perlu diverifikasi kembali terhadap evidence.',
  );
}

class _HistoryChatRepository extends ProjectChatRepository {
  _HistoryChatRepository() : super(Dio());

  @override
  Future<List<StoredProjectChatMessage>> getHistory(
    String projectId,
  ) async => const [
    StoredProjectChatMessage(
      role: 'user',
      content: 'Pertanyaan tersimpan',
      sources: [],
      reviewNotice: null,
    ),
    StoredProjectChatMessage(
      role: 'assistant',
      content: 'Jawaban tersimpan dari PDF.',
      sources: [
        ProjectChatSource(
          sourceId: 'S1',
          paperId: 'paper-persisted',
          paperTitle: 'Paper Persisten',
          parameter: '',
          quote: 'Evidence persisted.',
          pageNumber: 7,
          blockId: '00000000-0000-0000-0000-000000000099',
        ),
      ],
      reviewNotice: 'Jawaban AI perlu diverifikasi kembali terhadap evidence.',
    ),
  ];
}
