import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';

import '../data/project_repository.dart';
import '../models/research_models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({
    required this.userId,
    required this.onNewProject,
    required this.onOpenProject,
    super.key,
  });

  final String userId;
  final VoidCallback onNewProject;
  final ValueChanged<ResearchProject> onOpenProject;

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  String _query = '';
  ProjectStatus? _filter;

  Future<void> _deleteProject(ResearchProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        bool isMatched = false;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Hapus Proyek?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tindakan ini tidak dapat dibatalkan. Semua PDF, hasil analisis, '
                    'dan riwayat review dalam proyek ini akan dihapus permanen.',
                  ),
                  const SizedBox(height: 16),
                  Text.rich(
                    TextSpan(
                      text: 'Ketik ulang ',
                      children: [
                        TextSpan(
                          text: project.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(text: ' untuk konfirmasi:'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Nama proyek',
                    ),
                    onChanged: (val) {
                      setState(() {
                        isMatched = val.trim() == project.title;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Batal'),
                ),
                FilledButton.icon(
                  onPressed: isMatched ? () => Navigator.pop(context, true) : null,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Hapus Permanen'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    try {
      await ref.read(projectRepositoryProvider).deleteProject(project.id);
      
      final userId = ref.read(authRepositoryProvider).currentUser?.id;
      if (userId != null) {
        ref.invalidate(projectsProvider(userId));
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Proyek "${project.title}" telah dihapus.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ProjectRepository.readableError(e)),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider(widget.userId));

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
              projects.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Card(
                  child: EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Data proyek belum dapat dimuat',
                    message:
                        'Pastikan FastAPI dan Supabase lokal sedang berjalan.',
                    action: FilledButton.icon(
                      onPressed: () =>
                          ref.invalidate(projectsProvider(widget.userId)),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Coba lagi'),
                    ),
                  ),
                ),
                data: (items) {
                  final filtered = items.where((project) {
                    final matchesQuery = project.title.toLowerCase().contains(
                      _query.toLowerCase(),
                    );
                    return matchesQuery &&
                        (_filter == null || project.status == _filter);
                  }).toList();
                  if (filtered.isEmpty) {
                    return Card(
                      child: EmptyState(
                        icon: items.isEmpty
                            ? Icons.create_new_folder_outlined
                            : Icons.search_off_rounded,
                        title: items.isEmpty
                            ? 'Belum ada proyek'
                            : 'Proyek tidak ditemukan',
                        message: items.isEmpty
                            ? 'Buat proyek pertama untuk memulai workspace riset.'
                            : 'Coba ubah kata kunci atau filter status.',
                        action: items.isEmpty
                            ? FilledButton.icon(
                                onPressed: widget.onNewProject,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Buat proyek pertama'),
                              )
                            : null,
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final project in filtered) ...[
                        _ProjectListTile(
                          project: project,
                          onTap: () => widget.onOpenProject(project),
                          onDelete: () => _deleteProject(project),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectListTile extends StatelessWidget {
  const _ProjectListTile({
    required this.project,
    required this.onTap,
    required this.onDelete,
  });

  final ResearchProject project;
  final VoidCallback onTap;
  final VoidCallback onDelete;

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
                      const Spacer(),
                      Text(
                        project.updatedLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
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
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Hapus Proyek',
                          style: TextStyle(color: AppColors.red),
                        ),
                      ),
                    ],
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
