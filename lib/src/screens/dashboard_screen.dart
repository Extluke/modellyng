import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../models/research_models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    required this.onNewProject,
    required this.onOpenProject,
    required this.onOpenReview,
    super.key,
  });

  final VoidCallback onNewProject;
  final ValueChanged<ResearchProject> onOpenProject;
  final VoidCallback onOpenReview;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeading(
                title: 'Selamat datang, Aditya',
                subtitle:
                    'Lanjutkan sintesis literatur Anda atau mulai workspace riset baru.',
                action: FilledButton.icon(
                  onPressed: onNewProject,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Proyek baru'),
                ),
              ),
              const SizedBox(height: 24),
              const _DashboardMetrics(),
              const SizedBox(height: 28),
              _AttentionBanner(onReview: onOpenReview),
              const SizedBox(height: 30),
              SectionHeading(
                title: 'Proyek terbaru',
                subtitle: 'Workspace yang terakhir Anda kerjakan.',
                trailing: TextButton(
                  onPressed: () {},
                  child: const Text('Lihat semua'),
                ),
              ),
              const SizedBox(height: 14),
              _ProjectGrid(onOpenProject: onOpenProject),
              const SizedBox(height: 30),
              const _ProcessingPanel(),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardMetrics extends StatelessWidget {
  const _DashboardMetrics();

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
        const cards = [
          MetricCard(
            icon: Icons.description_outlined,
            label: 'Paper dianalisis',
            value: '44',
            color: AppColors.blue,
            note: '+8 bulan ini',
          ),
          MetricCard(
            icon: Icons.folder_outlined,
            label: 'Proyek aktif',
            value: '3',
            color: AppColors.primary,
          ),
          MetricCard(
            icon: Icons.hub_outlined,
            label: 'Knowledge nodes',
            value: '326',
            color: AppColors.green,
          ),
          MetricCard(
            icon: Icons.fact_check_outlined,
            label: 'Menunggu review',
            value: '12',
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

class _AttentionBanner extends StatelessWidget {
  const _AttentionBanner({required this.onReview});

  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF7E9), Color(0xFFFFFBF4)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF6D9A9)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.orangeSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.rule_folder_outlined,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '12 hasil AI menunggu verifikasi Anda',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tinjau claim dan evidence sebelum hasil digunakan dalam sintesis akhir.',
                    ),
                  ],
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 660) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content,
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: onReview,
                  child: const Text('Buka antrean review'),
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: content),
              const SizedBox(width: 18),
              OutlinedButton(
                onPressed: onReview,
                child: const Text('Tinjau sekarang'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProjectGrid extends StatelessWidget {
  const _ProjectGrid({required this.onOpenProject});

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
            for (final project in DemoData.projects)
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
                project.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: project.progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(999),
                backgroundColor: AppColors.border,
                color: project.accent,
              ),
              const SizedBox(height: 10),
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
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      project.updatedLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
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

class _ProcessingPanel extends StatelessWidget {
  const _ProcessingPanel();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeading(
              title: 'Aktivitas pemrosesan',
              subtitle: 'Job analisis berjalan secara asynchronous.',
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Heat Vulnerability and Green Infrastructure',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Mencocokkan claim dengan evidence · tahap 4 dari 6',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text('64%', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
