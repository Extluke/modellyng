import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../data/project_repository.dart';
import '../data/review_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class ReviewQueueScreen extends ConsumerWidget {
  const ReviewQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(authRepositoryProvider).currentUser?.id;
    final queue = userId == null
        ? const AsyncValue<List<ReviewQueueItem>>.data([])
        : ref.watch(reviewQueueProvider(userId));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeading(
                title: 'Antrean verifikasi',
                subtitle:
                    'Periksa hasil Gemini dan kutipan sumber sebelum data menjadi final.',
              ),
              const SizedBox(height: 24),
              queue.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (error, _) => Card(
                  child: EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Antrean review belum dapat dimuat',
                    message: 'Pastikan FastAPI dan Supabase lokal berjalan.',
                    action: FilledButton.icon(
                      onPressed: userId == null
                          ? null
                          : () => ref.invalidate(reviewQueueProvider(userId)),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Coba lagi'),
                    ),
                  ),
                ),
                data: (items) => items.isEmpty
                    ? const Card(
                        child: EmptyState(
                          icon: Icons.task_alt_rounded,
                          title: 'Belum ada hasil yang perlu ditinjau',
                          message:
                              'Hasil ekstraksi Gemini akan muncul setelah paper selesai diproses.',
                        ),
                      )
                    : Column(
                        children: [
                          for (final item in items) ...[
                            _ReviewCard(item: item, userId: userId!),
                            const SizedBox(height: 14),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewCard extends ConsumerStatefulWidget {
  const _ReviewCard({required this.item, required this.userId});

  final ReviewQueueItem item;
  final String userId;

  @override
  ConsumerState<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<_ReviewCard> {
  bool _submitting = false;

  Future<void> _submit(
    ReviewDecision decision, {
    String? correctedValue,
  }) async {
    setState(() => _submitting = true);
    try {
      await ref.read(reviewRepositoryProvider).submitDecision(
        componentId: widget.item.componentId,
        decision: decision,
        correctedValue: correctedValue,
      );
      ref.invalidate(reviewQueueProvider(widget.userId));
      ref.invalidate(projectsProvider(widget.userId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keputusan review berhasil disimpan.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keputusan belum dapat disimpan. Silakan coba kembali.'),
          backgroundColor: AppColors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _edit() async {
    final controller = TextEditingController(text: widget.item.aiValue);
    final corrected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${widget.item.parameterLabel}'),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            minLines: 5,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: 'Nilai final hasil koreksi',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('Simpan koreksi'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (corrected != null) {
      await _submit(ReviewDecision.edit, correctedValue: corrected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final confidence = item.confidence == null
        ? 'Tidak tersedia'
        : '${(item.confidence! * 100).round()}%';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.parameterLabel,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text('${item.paperTitle} · ${item.projectTitle}'),
                    ],
                  ),
                ),
                StatusBadge(
                  label: 'Keyakinan $confidence',
                  color: item.evidence.isEmpty
                      ? AppColors.orange
                      : AppColors.blue,
                  background: item.evidence.isEmpty
                      ? AppColors.orangeSoft
                      : AppColors.blueSoft,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(item.aiValue, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            Text('Bukti sumber', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (item.evidence.isEmpty)
              const Text(
                'Gemini tidak memberikan kutipan yang dapat diverifikasi. Periksa hasil dengan hati-hati.',
                style: TextStyle(color: AppColors.orange),
              )
            else
              for (final evidence in item.evidence)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: AppColors.blueSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Halaman ${evidence.pageNumber}: “${evidence.quote}”',
                    style: const TextStyle(height: 1.45),
                  ),
                ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _submitting
                      ? null
                      : () => _submit(ReviewDecision.accept),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Terima'),
                ),
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _edit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: _submitting
                      ? null
                      : () => _submit(ReviewDecision.reject),
                  icon: const Icon(Icons.close_rounded, color: AppColors.red),
                  label: const Text(
                    'Tolak',
                    style: TextStyle(color: AppColors.red),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Model: ${item.modelName} · File: ${item.originalFilename}',
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
