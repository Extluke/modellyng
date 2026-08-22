import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../data/project_repository.dart';
import '../data/review_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

String? validateRequiredReviewText(String value, String label) =>
    value.trim().isEmpty ? '$label tidak boleh kosong.' : null;

class ReviewQueueScreen extends ConsumerStatefulWidget {
  const ReviewQueueScreen({super.key});

  @override
  ConsumerState<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends ConsumerState<ReviewQueueScreen> {
  String? _projectFilter;

  @override
  Widget build(BuildContext context) {
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
                    : _buildGroupedQueue(items, userId!),
              ),
              if (userId != null) ...[
                const SizedBox(height: 28),
                ExpansionTile(
                  title: const Text('Riwayat keputusan review'),
                  subtitle: const Text(
                    '100 keputusan terbaru tetap dapat diaudit.',
                  ),
                  children: [
                    ref
                        .watch(reviewHistoryProvider(userId))
                        .when(
                          loading: () => const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                          error: (error, _) => const ListTile(
                            title: Text('Riwayat belum dapat dimuat.'),
                          ),
                          data: (history) => history.isEmpty
                              ? const ListTile(
                                  title: Text('Belum ada riwayat keputusan.'),
                                )
                              : Column(
                                  children: [
                                    for (final item in history)
                                      ListTile(
                                        leading: const Icon(
                                          Icons.history_rounded,
                                        ),
                                        title: Text(
                                          '${item.paperTitle} · ${item.action}',
                                        ),
                                        subtitle: Text(
                                          item.note?.trim().isNotEmpty == true
                                              ? item.note!
                                              : item.parameter,
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupedQueue(List<ReviewQueueItem> items, String userId) {
    final projects = {
      for (final item in items) item.projectId: item.projectTitle,
    };
    final visible = _projectFilter == null
        ? items
        : items.where((item) => item.projectId == _projectFilter).toList();
    final groups = <String, List<ReviewQueueItem>>{};
    for (final item in visible) {
      groups.putIfAbsent(item.paperId, () => []).add(item);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String?>(
          initialValue: _projectFilter,
          decoration: const InputDecoration(labelText: 'Filter proyek'),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Semua proyek'),
            ),
            for (final entry in projects.entries)
              DropdownMenuItem<String?>(
                value: entry.key,
                child: Text(entry.value),
              ),
          ],
          onChanged: (value) => setState(() => _projectFilter = value),
        ),
        const SizedBox(height: 18),
        for (final group in groups.values) ...[
          Text(
            group.first.paperTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            '${11 - group.length}/11 selesai ditinjau · ${group.length} tersisa',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          for (final item in group) ...[
            _ReviewCard(item: item, userId: userId),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 10),
        ],
      ],
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
      await ref
          .read(reviewRepositoryProvider)
          .submitDecision(
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
          content: Text(
            'Keputusan belum dapat disimpan. Silakan coba kembali.',
          ),
          backgroundColor: AppColors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _edit() async {
    final corrected = await showDialog<String>(
      context: context,
      builder: (context) => _RequiredTextDialog(
        title: 'Edit ${widget.item.parameterLabel}',
        label: 'Nilai final hasil koreksi',
        submitLabel: 'Simpan koreksi',
        initialValue: widget.item.aiValue,
        minLines: 5,
        maxLines: 12,
      ),
    );
    if (corrected != null) {
      await _submit(ReviewDecision.edit, correctedValue: corrected);
    }
  }

  Future<void> _submitWithReason(ReviewDecision decision) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _RequiredTextDialog(
        title: decision == ReviewDecision.reject
            ? 'Alasan penolakan'
            : 'Minta analisis ulang',
        label: 'Alasan wajib',
        submitLabel: 'Kirim',
        minLines: 3,
        maxLines: 6,
      ),
    );
    if (reason != null) {
      setState(() => _submitting = true);
      try {
        await ref
            .read(reviewRepositoryProvider)
            .submitDecision(
              componentId: widget.item.componentId,
              decision: decision,
              note: reason,
            );
        ref.invalidate(reviewQueueProvider(widget.userId));
        ref.invalidate(projectsProvider(widget.userId));
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                decision == ReviewDecision.reject
                    ? 'Hasil ditolak.'
                    : 'Analisis ulang masuk antrean.',
              ),
            ),
          );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Keputusan belum dapat dikirim. Silakan coba kembali.',
              ),
              backgroundColor: AppColors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
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
            Text(
              'Bukti sumber',
              style: Theme.of(context).textTheme.titleMedium,
            ),
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
                      : () => _submitWithReason(ReviewDecision.reject),
                  icon: const Icon(Icons.close_rounded, color: AppColors.red),
                  label: const Text(
                    'Tolak',
                    style: TextStyle(color: AppColors.red),
                  ),
                ),
                TextButton.icon(
                  onPressed: _submitting
                      ? null
                      : () =>
                            _submitWithReason(ReviewDecision.requestReanalysis),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Analisis ulang'),
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

class _RequiredTextDialog extends StatefulWidget {
  const _RequiredTextDialog({
    required this.title,
    required this.label,
    required this.submitLabel,
    required this.minLines,
    required this.maxLines,
    this.initialValue = '',
  });

  final String title;
  final String label;
  final String submitLabel;
  final String initialValue;
  final int minLines;
  final int maxLines;

  @override
  State<_RequiredTextDialog> createState() => _RequiredTextDialogState();
}

class _RequiredTextDialogState extends State<_RequiredTextDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    final error = validateRequiredReviewText(value, widget.label);
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 560,
      child: TextField(
        controller: _controller,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        autofocus: true,
        onChanged: (_) {
          if (_errorText != null) setState(() => _errorText = null);
        },
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: _errorText,
          alignLabelWithHint: true,
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.submitLabel)),
    ],
  );
}
