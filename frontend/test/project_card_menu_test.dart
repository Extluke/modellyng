import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/data/project_repository.dart';
import 'package:modellyng/src/models/research_models.dart';
import 'package:modellyng/src/screens/dashboard_screen.dart';
import 'package:modellyng/src/screens/projects_screen.dart';

final testProject = ResearchProject(
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

void main() {
  const userId = 'user-test-123';

  group('DashboardScreen - 3-dots project delete removal', () {
    for (final width in [390.0, 1024.0]) {
      testWidgets('dashboard card has no 3-dots menu or delete option at width $width', (
        tester,
      ) async {
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
      });
    }
  });

  group('ProjectsScreen - 3-dots menu for edit and delete', () {
    for (final width in [390.0, 1024.0]) {
      testWidgets('projects card has 3-dots menu with edit and delete at width $width', (
        tester,
      ) async {
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
      });
    }
  });
}
