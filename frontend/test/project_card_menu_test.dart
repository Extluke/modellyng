import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/data/project_repository.dart';
import 'package:modellyng/src/models/research_models.dart';
import 'package:modellyng/src/screens/dashboard_screen.dart';
import 'package:modellyng/src/screens/projects_screen.dart';

const testProject = ResearchProject(
  id: '00000000-0000-0000-0000-000000000001',
  title: 'Smart City Research',
  description: 'Studi literatur perkotaan pintar.',
  paperCount: 2,
  reviewCount: 0,
  readyCount: 2,
  knowledgeNodeCount: 4,
  progress: 1.0,
  status: ProjectStatus.ready,
  updatedLabel: 'Baru saja',
  accent: const Color(0xFF5747E8),
);

class FakeProjectRepo extends Fake implements ProjectRepository {
  FakeProjectRepo({this.onDelete});

  final void Function(String projectId)? onDelete;

  @override
  Future<void> deleteProject(String projectId) async {
    onDelete?.call(projectId);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  const userId = 'user-test-123';

  group('DashboardScreen - 3-dots project delete removal', () {
    for (final width in [390.0, 1024.0]) {
      testWidgets(
        'dashboard card has no 3-dots menu or delete option at width $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          ResearchProject? openedProject;

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                projectsProvider(userId).overrideWith((ref) => [testProject]),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: DashboardScreen(
                    userId: userId,
                    displayName: 'Peneliti',
                    onGoToProjects: () {},
                    onOpenProject: (p) => openedProject = p,
                    onOpenReview: () {},
                  ),
                ),
              ),
            ),
          );

          await tester.pumpAndSettle();

          expect(find.text('Smart City Research'), findsOneWidget);
          // Verify 3-dots menu button is removed from Dashboard
          expect(find.byIcon(Icons.more_vert), findsNothing);
          expect(find.text('Hapus Proyek'), findsNothing);

          // Verify tapping the project card still opens the project
          await tester.ensureVisible(find.text('Smart City Research'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Smart City Research'));
          await tester.pumpAndSettle();
          expect(openedProject?.id, testProject.id);
        },
      );
    }
  });

  group('ProjectsScreen - 3-dots menu for edit and delete', () {
    for (final width in [390.0, 1024.0]) {
      testWidgets(
        'projects card has 3-dots menu with edit and delete at width $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                projectsProvider(userId).overrideWith((ref) => [testProject]),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: ProjectsScreen(
                    userId: userId,
                    onNewProject: () {},
                    onOpenProject: (_) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pumpAndSettle();

          expect(find.text('Smart City Research'), findsOneWidget);

          // Verify 3-dots icon is present on both mobile and desktop
          final moreVertFinder = find.byIcon(Icons.more_vert);
          expect(moreVertFinder, findsOneWidget);

          // Tap the 3-dots menu button
          await tester.tap(moreVertFinder);
          await tester.pumpAndSettle();

          // Verify both Edit Proyek and Hapus Proyek options appear in popup menu
          expect(find.text('Edit Proyek'), findsOneWidget);
          expect(find.text('Hapus Proyek'), findsOneWidget);
        },
      );
    }

    testWidgets('delete project dialog confirms title and executes deletion', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool deleteCalled = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectsProvider(userId).overrideWith((ref) => [testProject]),
            projectRepositoryProvider.overrideWithValue(
              FakeProjectRepo(onDelete: (id) => deleteCalled = true),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ProjectsScreen(
                userId: userId,
                onNewProject: () {},
                onOpenProject: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open popup menu
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // Tap Hapus Proyek
      await tester.tap(find.text('Hapus Proyek'));
      await tester.pumpAndSettle();

      // Verify dialog is open
      expect(find.text('Hapus Proyek?'), findsOneWidget);
      final confirmBtn = find.byKey(const Key('confirm-delete-project-button'));
      expect(confirmBtn, findsOneWidget);

      // Button is disabled until title matches
      await tester.tap(confirmBtn);
      await tester.pump();
      expect(deleteCalled, isFalse);

      // Enter matching title
      await tester.enterText(
        find.byKey(const Key('delete-project-confirm-field')),
        testProject.title,
      );
      await tester.pump();

      // Now tap confirm
      await tester.tap(confirmBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();

      expect(deleteCalled, isTrue);
      expect(
        find.text('Proyek "${testProject.title}" telah dihapus.'),
        findsOneWidget,
      );
    });
  });
}
