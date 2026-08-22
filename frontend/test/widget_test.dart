import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/data/comparative_matrix_repository.dart';
import 'package:modellyng/src/data/concept_map_repository.dart';
import 'package:modellyng/src/data/paper_result_repository.dart';
import 'package:modellyng/src/data/project_repository.dart';
import 'package:modellyng/src/data/research_gap_repository.dart';
import 'package:modellyng/src/models/research_models.dart';
import 'package:modellyng/src/screens/comparative_matrix_screen.dart';
import 'package:modellyng/src/screens/concept_evidence_map_screen.dart';
import 'package:modellyng/src/screens/dashboard_screen.dart';
import 'package:modellyng/src/screens/paper_result_screen.dart';
import 'package:modellyng/src/screens/research_gap_map_screen.dart';
import 'package:modellyng/src/screens/welcome_screen.dart';
import 'package:modellyng/src/widgets/common_widgets.dart';

void main() {
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
      title: 'Map Project',
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
          label: 'Paper A',
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
    expect(find.text('Paper A'), findsWidgets);
    expect(find.text('Metodologi'), findsOneWidget);
    expect(find.text('Verified quote'), findsOneWidget);
    expect(find.text('Buka halaman PDF'), findsOneWidget);
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectsProvider('gap-user').overrideWith((ref) async => [project]),
          researchGapMapProvider(
            'project-gap',
          ).overrideWith((ref) async => graph),
        ],
        child: const MaterialApp(
          home: ResearchGapMapScreen(userId: 'gap-user'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kandidat · perlu ditinjau'), findsOneWidget);
    expect(find.text('The sample only covered one city.'), findsOneWidget);
    expect(find.text('Paper A'), findsOneWidget);
    expect(find.text('Halaman 9'), findsOneWidget);
    expect(find.text('Buka evidence PDF'), findsOneWidget);
  });
}
