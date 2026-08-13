import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../models/research_models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class ReviewQueueScreen extends StatefulWidget {
  const ReviewQueueScreen({super.key});

  @override
  State<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends State<ReviewQueueScreen> {
  final Set<String> _resolved = {};

  @override
  Widget build(BuildContext context) {
    final items = DemoData.components
        .where(
          (item) =>
              item.status == VerificationStatus.needsReview &&
              !_resolved.contains(item.label),
        )
        .toList();
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
                    'Validasi hubungan Result → Evidence → Source sebelum data menjadi final.',
              ),
              const SizedBox(height: 24),
              if (items.isEmpty)
                const Card(
                  child: EmptyState(
                    icon: Icons.task_alt_rounded,
                    title: 'Semua hasil sudah ditinjau',
                    message: 'Tidak ada claim yang menunggu keputusan Anda.',
                  ),
                )
              else
                for (final item in items) ...[
                  _ReviewCard(
                    component: item,
                    onResolve: (message) {
                      setState(() => _resolved.add(item.label));
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(message)));
                    },
                  ),
                  const SizedBox(height: 14),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.component, required this.onResolve});

  final ExtractedComponent component;
  final ValueChanged<String> onResolve;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    component.label,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                StatusBadge.verification(component.status),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Urban Climate Resilience: A Systematic Review',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 18),
            _LabeledBlock(
              label: 'HASIL EKSTRAKSI AI',
              child: Text(component.value),
            ),
            const SizedBox(height: 12),
            _LabeledBlock(
              label: 'SUPPORTING EVIDENCE',
              background: const Color(0xFFF8F7FF),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '“${component.evidence}”',
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          component.location,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _showSource(context, component),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('Buka sumber'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () =>
                      onResolve('${component.label} ditandai terverifikasi.'),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Terima'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showEdit(context),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                OutlinedButton.icon(
                  onPressed: () => onResolve('${component.label} ditolak.'),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Tolak'),
                ),
                TextButton.icon(
                  onPressed: () => onResolve(
                    'Analisis ulang ${component.label} telah diminta.',
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Analisis ulang'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSource(BuildContext context, ExtractedComponent component) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 640),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(
                      Icons.picture_as_pdf_outlined,
                      color: AppColors.red,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Preview evidence · halaman sumber',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(28),
                  color: const Color(0xFFF2F3F6),
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 510),
                      padding: const EdgeInsets.all(34),
                      color: Colors.white,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'INTRODUCTION',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Urban areas face increasingly interconnected climate risks. Existing studies discuss multiple intervention pathways across infrastructure systems.',
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(8),
                            color: const Color(0xFFFFEB85),
                            child: Text(component.evidence),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'This motivates a structured synthesis of the available evidence and its limitations.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEdit(BuildContext context) {
    final controller = TextEditingController(text: component.value);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit ${component.label}'),
        content: SizedBox(
          width: 520,
          child: TextField(controller: controller, maxLines: 6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onResolve(
                '${component.label} disimpan sebagai hasil koreksi manusia.',
              );
            },
            child: const Text('Simpan koreksi'),
          ),
        ],
      ),
    );
  }
}

class _LabeledBlock extends StatelessWidget {
  const _LabeledBlock({
    required this.label,
    required this.child,
    this.background = const Color(0xFFFAFAFC),
  });

  final String label;
  final Widget child;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
