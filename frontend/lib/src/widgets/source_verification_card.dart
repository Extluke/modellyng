import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/paper_result_repository.dart';
import '../data/source_verification_repository.dart';
import '../models/research_models.dart';
import '../theme/app_theme.dart';

class SourceVerificationCard extends ConsumerStatefulWidget {
  const SourceVerificationCard({required this.paper, super.key});
  final ProjectPaper paper;
  @override
  ConsumerState<SourceVerificationCard> createState() =>
      _SourceVerificationCardState();
}

class _SourceVerificationCardState
    extends ConsumerState<SourceVerificationCard> {
  late final TextEditingController _doi;
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _selectedId;
  PaperResultQuery get _query =>
      (projectId: widget.paper.projectId, paperId: widget.paper.id);
  @override
  void initState() {
    super.initState();
    _doi = TextEditingController(text: widget.paper.doi);
  }

  @override
  void dispose() {
    _doi.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SourceVerificationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paper.id != widget.paper.id) {
      _doi.text = widget.paper.doi ?? '';
      _note.clear();
      _selectedId = null;
      _error = null;
    }
  }

  Future<void> _run(
    Future<void> Function(SourceVerificationRepository) action,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(sourceVerificationRepositoryProvider));
      if (!mounted) return;
      _note.clear();
      ref.invalidate(sourceVerificationsProvider(_query));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Verifikasi belum tersimpan. Periksa koneksi lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _review(SourceVerification report, String decision) {
    if (_note.text.trim().isEmpty) {
      setState(() => _error = 'Catatan review wajib diisi.');
      return;
    }
    _run((repo) => repo.review(_query, report.id, decision, _note.text));
  }

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('source-verification-card'),
    child: ExpansionTile(
      title: const Text('Validasi paper & sumber'),
      subtitle: const Text(
        'Metadata, DOI, sumber eksternal, dan review manusia',
      ),
      childrenPadding: const EdgeInsets.all(16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Metadata hasil ekstraksi — belum merupakan verifikasi sumber.',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 8),
        for (final field in metadataLabels.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${field.value}: ${widget.paper.bibliographicValues[field.key] ?? 'Tidak dinyatakan'}',
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _doi,
          enabled: !_busy,
          maxLength: 255,
          decoration: const InputDecoration(
            labelText: 'DOI paper utama',
            hintText: '10.…/…',
            helperText: 'Hanya DOI dikirim ke Crossref / DataCite.',
            helperMaxLines: 2,
          ),
        ),
        FilledButton.icon(
          key: const Key('verify-source'),
          onPressed: _busy
              ? null
              : () {
                  _selectedId = null;
                  _run((repo) => repo.verify(_query, _doi.text));
                },
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(_busy ? 'Memproses…' : 'Periksa sumber'),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (_error != null && _error != 'Catatan review wajib diisi.')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: AppColors.red)),
          ),
        const SizedBox(height: 16),
        ref
            .watch(sourceVerificationsProvider(_query))
            .when(
              loading: () => const Text('Memuat riwayat verifikasi…'),
              error: (_, stack) => TextButton(
                onPressed: () =>
                    ref.invalidate(sourceVerificationsProvider(_query)),
                child: const Text('Riwayat belum dapat dimuat. Coba lagi'),
              ),
              data: (reports) {
                if (reports.isEmpty)
                  return const Text(
                    'Belum ada pemeriksaan sumber. DOI yang tidak ditemukan akan ditandai belum dapat diverifikasi.',
                  );
                final selected =
                    reports.where((r) => r.id == _selectedId).firstOrNull ??
                    reports.first;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButton<String>(
                      isExpanded: true,
                      value: selected.id,
                      items: [
                        for (final r in reports)
                          DropdownMenuItem(
                            value: r.id,
                            child: Text(
                              '${r.createdAt.toLocal().toString().split('.').first} · ${verificationStatusLabel(r.status)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (id) => setState(() {
                              _selectedId = id;
                              _note.clear();
                              _error = null;
                            }),
                    ),
                    const Text(
                      'Riwayat: 20 pemeriksaan terbaru. Keputusan berlaku untuk snapshot ini.',
                    ),
                    const SizedBox(height: 12),
                    for (final warning in selected.warnings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          warning,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ),
                    Text(
                      'DOI yang diperiksa: ${selected.doi ?? 'Tidak tersedia'}',
                    ),
                    for (final source in selected.sources)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${source.provider}: ${verificationStatusLabel(source.status)}',
                            ),
                            SelectableText(
                              source.url,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    for (final check in selected.checks)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: check.status == 'mismatch'
                              ? AppColors.orange.withAlpha(22)
                              : AppColors.canvas,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${metadataLabels[check.field] ?? check.field} · ${verificationStatusLabel(check.status)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Paper: ${check.localValue ?? 'Tidak dinyatakan'}',
                            ),
                            Text(
                              'Registri: ${check.sourceValue ?? 'Tidak dinyatakan'}',
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      'Review manusia',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text(
                      'Tinjau PDF dan sumber sebelum mengambil keputusan. Keputusan ini tidak menyelesaikan review klaim AI.',
                    ),
                    if (selected.reviews.isEmpty)
                      const Text('Belum ditinjau manusia.'),
                    for (final review in selected.reviews)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          '${review.decision == 'accept' ? 'Diterima' : 'Ditolak'} · ${review.createdAt.toLocal().toString().split('.').first}\n${review.note}',
                        ),
                      ),
                    TextField(
                      controller: _note,
                      enabled: !_busy,
                      maxLength: 2000,
                      maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Catatan review (wajib)',
                      errorText: _error == 'Catatan review wajib diisi.' ? _error : null,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _review(selected, 'accept'),
                          child: const Text('Terima sumber'),
                        ),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _review(selected, 'reject'),
                          child: const Text('Tolak sumber'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
      ],
    ),
  );
}
