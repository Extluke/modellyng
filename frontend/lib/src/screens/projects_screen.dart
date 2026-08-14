import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../models/research_models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({
    required this.onNewProject,
    required this.onOpenProject,
    super.key,
  });

  final VoidCallback onNewProject;
  final ValueChanged<ResearchProject> onOpenProject;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  String _query = '';
  ProjectStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final projects = DemoData.projects.where((project) {
      final matchesQuery = project.title.toLowerCase().contains(
        _query.toLowerCase(),
      );
      return matchesQuery && (_filter == null || project.status == _filter);
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeading(
                title: 'Proyek riset',
                subtitle:
                    'Kelola paper, model terstruktur, matrix, dan research gap dalam satu workspace.',
                action: FilledButton.icon(
                  onPressed: widget.onNewProject,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Proyek baru'),
                ),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final search = TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Cari proyek...',
                    ),
                  );
                  final filter = DropdownButtonFormField<ProjectStatus?>(
                    initialValue: _filter,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.filter_list_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: null,
                        child: Text('Semua status'),
                      ),
                      DropdownMenuItem(
                        value: ProjectStatus.ready,
                        child: Text('Siap'),
                      ),
                      DropdownMenuItem(
                        value: ProjectStatus.processing,
                        child: Text('Diproses'),
                      ),
                      DropdownMenuItem(
                        value: ProjectStatus.needsReview,
                        child: Text('Perlu ditinjau'),
                      ),
                    ],
                    onChanged: (value) => setState(() => _filter = value),
                  );
                  if (constraints.maxWidth < 620) {
                    return Column(
                      children: [search, const SizedBox(height: 10), filter],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: search),
                      const SizedBox(width: 12),
                      SizedBox(width: 210, child: filter),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              if (projects.isEmpty)
                const Card(
                  child: EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Proyek tidak ditemukan',
                    message: 'Coba ubah kata kunci atau filter status.',
                  ),
                )
              else
                for (final project in projects) ...[
                  _ProjectListTile(
                    project: project,
                    onTap: () => widget.onOpenProject(project),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectListTile extends StatelessWidget {
  const _ProjectListTile({required this.project, required this.onTap});

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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final icon = Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: project.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.folder_open_outlined, color: project.accent),
              );
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          project.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusBadge.project(project.status),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    project.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 16,
                        color: project.accent,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${project.paperCount} paper',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: project.progress,
                          minHeight: 5,
                          borderRadius: BorderRadius.circular(99),
                          backgroundColor: AppColors.border,
                          color: project.accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(project.progress * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              );
              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [icon, const SizedBox(height: 12), details],
                );
              }
              return Row(
                children: [
                  icon,
                  const SizedBox(width: 16),
                  Expanded(child: details),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.muted,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
