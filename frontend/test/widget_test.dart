import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/data/project_repository.dart';
import 'package:modellyng/src/models/research_models.dart';
import 'package:modellyng/src/screens/dashboard_screen.dart';
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
}
