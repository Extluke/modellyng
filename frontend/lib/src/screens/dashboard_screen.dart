import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/project_repository.dart';
import '../models/research_models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({
    required this.userId,
    required this.displayName,
    required this.onNewProject,
    required this.onOpenProject,
    required this.onOpenReview,
    super.key,
  });

  final String userId;
  final String displayName;
  final VoidCallback onNewProject;
  final ValueChanged<ResearchProject> onOpenProject;
  final VoidCallback onOpenReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider(userId));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeading(
                title: 'Selamat datang, $displayName',
                subtitle:
                    'Lanjutkan sintesis literatur Anda atau mulai workspace riset baru.',
                action: FilledButton.icon(
                  onPressed: onNewProject,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Proyek baru'),
                ),
              ),
              const SizedBox(height: 24),
              projects.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(36),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (error, _) => _LoadError(
                  onRetry: () => ref.invalidate(projectsProvider(userId)),
                ),
                data: (items) => _DashboardContent(
                  projects: items,
                  onNewProject: onNewProject,
                  onOpenProject: onOpenProject,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.projects,
    required this.onNewProject,
    required this.onOpenProject,
  });

  final List<ResearchProject> projects;
  final VoidCallback onNewProject;
  final ValueChanged<ResearchProject> onOpenProject;

  @override
  Widget build(BuildContext context) {
    final paperCount = projects.fold<int>(
      0,
      (total, project) => total + project.paperCount,
    );
    final reviewCount = projects.fold<int>(
      0,
      (total, project) => total + project.reviewCount,
    );
    final knowledgeNodeCount = projects.fold<int>(
      0,
      (total, project) => total + project.knowledgeNodeCount,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DashboardMetrics(
          projectCount: projects.length,
          paperCount: paperCount,
          reviewCount: reviewCount,
          knowledgeNodeCount: knowledgeNodeCount,
        ),
        const SizedBox(height: 30),
        const SectionHeading(
          title: 'Proyek terbaru',
          subtitle: 'Workspace yang terakhir Anda kerjakan.',
        ),
        const SizedBox(height: 14),
        if (projects.isEmpty)
          Card(
            child: EmptyState(
              icon: Icons.create_new_folder_outlined,
              title: 'Belum ada proyek',
              message:
                  'Buat proyek pertama untuk menyiapkan workspace ekstraksi paper.',
              action: FilledButton.icon(
                onPressed: onNewProject,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Buat proyek pertama'),
              ),
            ),
          )
        else
          _ProjectGrid(
            projects: projects.take(3).toList(growable: false),
            onOpenProject: onOpenProject,
          ),
        const SizedBox(height: 26),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_outlined, color: AppColors.primary),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Data dashboard berasal dari akun dan proyek Anda. Hasil Gemini baru menjadi knowledge node setelah Anda menerima atau mengoreksinya di halaman Review.',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashboardMetrics extends StatelessWidget {
  const _DashboardMetrics({
    required this.projectCount,
    required this.paperCount,
    required this.reviewCount,
    required this.knowledgeNodeCount,
  });

  final int projectCount;
  final int paperCount;
  final int reviewCount;
  final int knowledgeNodeCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        final cards = [
          MetricCard(
            icon: Icons.description_outlined,
            label: 'Paper',
            value: '$paperCount',
            color: AppColors.blue,
          ),
          MetricCard(
            icon: Icons.folder_outlined,
            label: 'Proyek',
            value: '$projectCount',
            color: AppColors.primary,
          ),
          MetricCard(
            icon: Icons.hub_outlined,
            label: 'Knowledge nodes',
            value: '$knowledgeNodeCount',
            color: AppColors.green,
          ),
          MetricCard(
            icon: Icons.fact_check_outlined,
            label: 'Menunggu review',
            value: '$reviewCount',
            color: AppColors.orange,
          ),
        ];
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class _ProjectGrid extends StatelessWidget {
  const _ProjectGrid({required this.projects, required this.onOpenProject});

  final List<ResearchProject> projects;
  final ValueChanged<ResearchProject> onOpenProject;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 960
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        const spacing = 14.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final project in projects)
              SizedBox(
                width: width,
                child: _ProjectCard(
                  project: project,
                  onTap: () => onOpenProject(project),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});

  final ResearchProject project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: project.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.folder_open_outlined,
                      color: project.accent,
                    ),
                  ),
                  const Spacer(),
                  StatusBadge.project(project.status),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                project.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                project.description.isEmpty
                    ? 'Belum ada deskripsi.'
                    : project.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    '${project.paperCount} paper',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    project.updatedLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Data proyek belum dapat dimuat',
        message: 'Pastikan FastAPI dan Supabase lokal sedang berjalan.',
        action: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Coba lagi'),
        ),
      ),
    );
  }
}
