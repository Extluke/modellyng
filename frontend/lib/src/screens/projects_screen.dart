import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Future<void> _editProject(ResearchProject project) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _EditProjectDialog(
        project: project,
        onSave: (title, description) => ref
            .read(projectRepositoryProvider)
            .updateProject(
              projectId: project.id,
              title: title,
              description: description,
            ),
      ),
    );

    if (updated == true && mounted) {
      ref.invalidate(projectsProvider(widget.userId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Proyek berhasil diperbarui.')),
      );
    }
  }

  Future<void> _deleteProject(ResearchProject project) async {
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _DeleteProjectDialog(
        project: project,
        onDelete: () =>
            ref.read(projectRepositoryProvider).deleteProject(project.id),
      ),
    );

    if (deleted == true && mounted) {
      ref.invalidate(projectsProvider(widget.userId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Proyek "${project.title}" telah dihapus.')),
      );
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
                    isExpanded: true,
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
                          onEdit: () => _editProject(project),
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
    required this.onEdit,
    required this.onDelete,
  });

  final ResearchProject project;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Widget _buildMenu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20, color: AppColors.muted),
      onSelected: (value) {
        if (value == 'edit') {
          onEdit();
        } else if (value == 'delete') {
          onDelete();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 8),
              Text('Edit Proyek'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: AppColors.red),
              SizedBox(width: 8),
              Text('Hapus Proyek', style: TextStyle(color: AppColors.red)),
            ],
          ),
        ),
      ],
    );
  }

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
              final menu = _buildMenu();

              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        icon,
                        const Spacer(),
                        StatusBadge.project(project.status),
                        const SizedBox(width: 4),
                        menu,
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      project.title,
                      style: Theme.of(context).textTheme.titleMedium,
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
                  menu,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EditProjectDialog extends StatefulWidget {
  const _EditProjectDialog({required this.project, required this.onSave});

  final ResearchProject project;
  final Future<void> Function(String title, String description) onSave;

  @override
  State<_EditProjectDialog> createState() => _EditProjectDialogState();
}

class _EditProjectDialogState extends State<_EditProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.project.title);
    _descriptionController = TextEditingController(
      text: widget.project.description,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Proyek'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 480,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nama proyek',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _titleController,
                  maxLength: 180,
                  autofocus: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Contoh: Literature Review Smart City 2026',
                  ),
                  validator: (value) {
                    final title = value?.trim() ?? '';
                    if (title.length < 3) {
                      return 'Nama proyek minimal 3 karakter.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'Deskripsi (opsional)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Jelaskan fokus atau tujuan riset Anda...',
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.red),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  if (!(_formKey.currentState?.validate() ?? false)) {
                    return;
                  }
                  setState(() {
                    _saving = true;
                    _errorMessage = null;
                  });
                  try {
                    await widget.onSave(
                      _titleController.text.trim(),
                      _descriptionController.text.trim(),
                    );
                    if (context.mounted) {
                      Navigator.pop(context, true);
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() {
                        _saving = false;
                        _errorMessage = ProjectRepository.readableError(e);
                      });
                    }
                  }
                },
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Simpan'),
        ),
      ],
    );
  }
}

class _DeleteProjectDialog extends StatefulWidget {
  const _DeleteProjectDialog({required this.project, required this.onDelete});

  final ResearchProject project;
  final Future<void> Function() onDelete;

  @override
  State<_DeleteProjectDialog> createState() => _DeleteProjectDialogState();
}

class _DeleteProjectDialogState extends State<_DeleteProjectDialog> {
  late final TextEditingController _controller;
  bool _isMatched = false;
  bool _deleting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  text: widget.project.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: ' untuk konfirmasi:'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('delete-project-confirm-field'),
            controller: _controller,
            enabled: !_deleting,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Nama proyek',
            ),
            onChanged: (val) {
              setState(() {
                _isMatched = val.trim() == widget.project.title.trim();
              });
            },
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: AppColors.red),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          key: const Key('confirm-delete-project-button'),
          onPressed: (_isMatched && !_deleting)
              ? () async {
                  setState(() {
                    _deleting = true;
                    _errorMessage = null;
                  });
                  try {
                    await widget.onDelete();
                    if (context.mounted) {
                      Navigator.pop(context, true);
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() {
                        _deleting = false;
                        _errorMessage = ProjectRepository.readableError(e);
                      });
                    }
                  }
                }
              : null,
          icon: _deleting
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.delete_forever),
          label: Text(_deleting ? 'Menghapus...' : 'Hapus Permanen'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
        ),
      ],
    );
  }
}
