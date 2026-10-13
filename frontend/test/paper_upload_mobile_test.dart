import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/data/auth_repository.dart';
import 'package:modellyng/src/data/paper_repository.dart';
import 'package:modellyng/src/data/review_repository.dart';
import 'package:modellyng/src/models/research_models.dart';
import 'package:modellyng/src/screens/project_overview_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

const testEmptyProject = ResearchProject(
  id: '00000000-0000-0000-0000-000000000002',
  title: 'Fresh Research Project',
  description: 'Proyek baru tanpa paper.',
  paperCount: 0,
  reviewCount: 0,
  readyCount: 0,
  knowledgeNodeCount: 0,
  progress: 0.0,
  status: ProjectStatus.ready,
  updatedLabel: 'Baru saja',
  accent: const Color(0xFF5747E8),
);

class FakeAuthRepo extends Fake implements AuthRepository {
  @override
  supa.User? get currentUser => const supa.User(
    id: 'user-test-456',
    appMetadata: {},
    userMetadata: {'display_name': 'Peneliti'},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  );

  @override
  supa.Session? get currentSession => null;
}

class FakePaperRepo extends Fake implements PaperRepository {
  bool uploadTriggered = false;

  @override
  Future<List<ProjectPaper>?> pickAndUploadPdf(
    ResearchProject project, {
    List<ProjectPaper> existingPapers = const [],
    void Function(double progress)? onProgress,
  }) async {
    uploadTriggered = true;
    onProgress?.call(0.45);
    // Simulate short async delay
    await Future<void>.delayed(const Duration(milliseconds: 50));
    onProgress?.call(1.0);
    return null;
  }
}

class FakeFailingPaperRepo extends Fake implements PaperRepository {
  @override
  Future<List<ProjectPaper>?> pickAndUploadPdf(
    ResearchProject project, {
    List<ProjectPaper> existingPapers = const [],
    void Function(double progress)? onProgress,
  }) async {
    throw const PaperUploadException('Koneksi terputus saat mengunggah PDF.');
  }
}

void main() {
  group('PaperRepository - Validation & Error Handling', () {
    test('rejects non-PDF extension with Indonesian message', () async {
      expect(
        () => PaperRepository.validatePdf(
          'paper.docx',
          1024,
          bytes: Uint8List(10),
        ),
        throwsA(
          isA<PaperUploadException>().having(
            (e) => e.message,
            'message',
            contains('Hanya file PDF yang dapat diunggah'),
          ),
        ),
      );
    });

    test('rejects 0-byte PDF with Indonesian message', () async {
      expect(
        () => PaperRepository.validatePdf('paper.pdf', 0, bytes: Uint8List(0)),
        throwsA(
          isA<PaperUploadException>().having(
            (e) => e.message,
            'message',
            contains('File PDF kosong (0 byte) dan tidak dapat diproses'),
          ),
        ),
      );
    });

    test('rejects oversized PDF (>50 MB) with Indonesian message', () async {
      // 50 MB + 1 byte
      final oversizedBytes = Uint8List(50 * 1024 * 1024 + 1);
      // Put valid header so only the size check triggers
      oversizedBytes[0] = 0x25;
      oversizedBytes[1] = 0x50;
      oversizedBytes[2] = 0x44;
      oversizedBytes[3] = 0x46;
      oversizedBytes[4] = 0x2D;

      expect(
        () => PaperRepository.validatePdf(
          'large.pdf',
          oversizedBytes.length,
          bytes: oversizedBytes,
        ),
        throwsA(
          isA<PaperUploadException>().having(
            (e) => e.message,
            'message',
            contains('Ukuran PDF melebihi batas 50 MB per file'),
          ),
        ),
      );
    });

    test('rejects invalid PDF magic header (%PDF-)', () async {
      final fakeBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7]);
      expect(
        () => PaperRepository.validatePdf(
          'fake.pdf',
          fakeBytes.length,
          bytes: fakeBytes,
        ),
        throwsA(
          isA<PaperUploadException>().having(
            (e) => e.message,
            'message',
            contains('Isi file tidak dikenali sebagai dokumen PDF yang valid'),
          ),
        ),
      );
    });

    test('accepts valid PDF header and returns bytes', () async {
      final validPdf = Uint8List.fromList([
        0x25, 0x50, 0x44, 0x46, 0x2D, // %PDF-
        0x31, 0x2E, 0x35, // 1.5
      ]);
      final result = await PaperRepository.validatePdf(
        'valid.pdf',
        validPdf.length,
        bytes: validPdf,
      );
      expect(result.length, equals(8));
      expect(result[0], equals(0x25));
    });

    test(
      'readableError handles FileSystemException, Dio 413, timeouts cleanly',
      () {
        final fsError = PaperRepository.readableError(
          const FileSystemException('Permission denied'),
        );
        expect(
          fsError,
          contains('Gagal membaca file dari penyimpanan perangkat'),
        );

        final dio413 = PaperRepository.readableError(
          DioException(
            requestOptions: RequestOptions(path: '/upload'),
            response: Response(
              requestOptions: RequestOptions(path: '/upload'),
              statusCode: 413,
            ),
          ),
        );
        expect(dio413, contains('Ukuran PDF melebihi batas 50 MB'));

        final dioConn = PaperRepository.readableError(
          DioException(
            requestOptions: RequestOptions(path: '/upload'),
            type: DioExceptionType.connectionTimeout,
          ),
        );
        expect(dioConn, contains('FastAPI belum dapat dihubungi'));

        final dioSend = PaperRepository.readableError(
          DioException(
            requestOptions: RequestOptions(path: '/upload'),
            type: DioExceptionType.sendTimeout,
          ),
        );
        expect(dioSend, contains('Waktu unggah habis'));
      },
    );

    test('rejects duplicate filename against existing project papers', () {
      expect(
        () => PaperRepository.validateDuplicateFilenames(
          ['paper_a.pdf'],
          ['paper_a.pdf', 'paper_b.pdf'],
        ),
        throwsA(
          isA<PaperUploadException>().having(
            (e) => e.message,
            'message',
            contains('sudah pernah diunggah atau duplikat dalam pilihan'),
          ),
        ),
      );
    });

    test('rejects case-insensitive and trimmed duplicate filename', () {
      expect(
        () => PaperRepository.validateDuplicateFilenames(
          ['  PAPER_A.PDF  '],
          ['paper_a.pdf'],
        ),
        throwsA(
          isA<PaperUploadException>().having(
            (e) => e.message,
            'message',
            contains('sudah pernah diunggah atau duplikat dalam pilihan'),
          ),
        ),
      );
    });

    test('rejects duplicate filename within the same selection batch', () {
      expect(
        () => PaperRepository.validateDuplicateFilenames(
          ['new_paper.pdf', 'new_paper.pdf'],
          ['existing.pdf'],
        ),
        throwsA(
          isA<PaperUploadException>().having(
            (e) => e.message,
            'message',
            contains('sudah pernah diunggah atau duplikat dalam pilihan'),
          ),
        ),
      );
    });

    test('accepts distinct non-duplicate filenames', () {
      expect(
        () => PaperRepository.validateDuplicateFilenames(
          ['paper_c.pdf', 'paper_d.pdf'],
          ['paper_a.pdf', 'paper_b.pdf'],
        ),
        returnsNormally,
      );
    });
  });

  group('ProjectOverviewScreen - Mobile Aspect Ratio Upload Feedback', () {
    testWidgets(
      'renders sticky AppBar progress bar and reactive EmptyState on mobile screen (390x844)',
      (tester) async {
        // Set mobile viewport: iPhone 12/13/14 size
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final fakePaperRepo = FakePaperRepo();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(FakeAuthRepo()),
              paperRepositoryProvider.overrideWithValue(fakePaperRepo),
              projectPapersProvider((
                userId: 'user-test-456',
                projectId: testEmptyProject.id,
              )).overrideWith((ref) => []),
              reviewQueueProvider('user-test-456').overrideWith((ref) => []),
            ],
            child: const MaterialApp(
              home: ProjectOverviewScreen(project: testEmptyProject),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 1. Initial empty state:
        expect(find.text('Belum ada paper dalam proyek ini'), findsOneWidget);
        expect(
          find.byKey(const Key('empty-state-upload-button')),
          findsOneWidget,
        );
        expect(find.text('Pilih PDF'), findsOneWidget);
        // Sticky appbar progress is not active yet (it is a Divider):
        expect(find.byKey(const Key('appbar-upload-progress')), findsNothing);
        expect(
          find.byKey(const Key('empty-state-upload-progress')),
          findsNothing,
        );

        // 2. Tap upload button on EmptyState:
        await tester.ensureVisible(
          find.byKey(const Key('empty-state-upload-button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('empty-state-upload-button')));
        await tester.pump(); // Start upload state

        // 3. During upload:
        // Sticky AppBar progress MUST appear on mobile screen:
        expect(find.byKey(const Key('appbar-upload-progress')), findsOneWidget);

        // EmptyState progress bar and reactive title/spinner label MUST appear:
        expect(
          find.byKey(const Key('empty-state-upload-progress')),
          findsOneWidget,
        );
        expect(find.text('Sedang mengunggah PDF...'), findsOneWidget);

        // Upload guidance progress bar MUST appear:
        expect(
          find.byKey(const Key('guidance-upload-progress')),
          findsOneWidget,
        );

        // Settle upload completion:
        await tester.pumpAndSettle();

        // 4. After completion, progress bar resets safely:
        expect(find.byKey(const Key('appbar-upload-progress')), findsNothing);
      },
    );

    testWidgets(
      'invalidates paper provider even when upload throws an exception',
      (tester) async {
        int providerBuildCount = 0;
        final fakeFailingPaperRepo = FakeFailingPaperRepo();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(FakeAuthRepo()),
              paperRepositoryProvider.overrideWithValue(fakeFailingPaperRepo),
              projectPapersProvider((
                userId: 'user-test-456',
                projectId: testEmptyProject.id,
              )).overrideWith((ref) {
                providerBuildCount++;
                return [];
              }),
              reviewQueueProvider('user-test-456').overrideWith((ref) => []),
            ],
            child: const MaterialApp(
              home: ProjectOverviewScreen(project: testEmptyProject),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(providerBuildCount, equals(1));

        await tester.ensureVisible(
          find.byKey(const Key('empty-state-upload-button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('empty-state-upload-button')));
        await tester.pumpAndSettle();

        // Provider should have been re-evaluated/invalidated:
        expect(providerBuildCount, greaterThan(1));
        // Error SnackBar should be displayed:
        expect(
          find.text('Koneksi terputus saat mengunggah PDF.'),
          findsOneWidget,
        );
      },
    );
  });
}
