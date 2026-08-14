import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/project_repository.dart';
import '../models/research_models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class NewProjectScreen extends ConsumerStatefulWidget {
  const NewProjectScreen({super.key});

  @override
  ConsumerState<NewProjectScreen> createState() => _NewProjectScreenState();
}

class _NewProjectScreenState extends ConsumerState<NewProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _saving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final project = await ref
          .read(projectRepositoryProvider)
          .createProject(
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop<ResearchProject>(context, project);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = ProjectRepository.readableError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const BrandLockup(),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Buat proyek riset',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Proyek akan disimpan di Supabase lokal dan hanya dapat dilihat oleh akun Anda.',
                  ),
                  const SizedBox(height: 26),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Informasi proyek',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Nama proyek',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            key: const Key('project-title-field'),
                            controller: _titleController,
                            autofocus: true,
                            maxLength: 180,
                            decoration: const InputDecoration(
                              hintText:
                                  'Contoh: Literature Review Smart City 2026',
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
                            maxLines: 4,
                            maxLength: 2000,
                            decoration: const InputDecoration(
                              hintText:
                                  'Jelaskan fokus atau tujuan riset Anda...',
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
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: AppColors.primary),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Setelah proyek tersimpan, langkah pengembangan berikutnya adalah unggah PDF asli dan validasi file.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text('Batal'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        key: const Key('create-project-button'),
                        onPressed: _saving ? null : _submit,
                        icon: _saving
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.add_rounded),
                        label: Text(_saving ? 'Menyimpan...' : 'Buat proyek'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
