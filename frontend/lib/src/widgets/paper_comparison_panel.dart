import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/paper_comparison_repository.dart';
import '../data/project_repository.dart';
import '../screens/paper_result_screen.dart';
import '../theme/app_theme.dart';
import 'pair_comparison_flowchart.dart';

class PaperComparisonPanel extends ConsumerStatefulWidget {
  const PaperComparisonPanel({
    required this.projectId,
    this.initialMatrix = false,
    super.key,
  });
  final String projectId;
  final bool initialMatrix;
  @override
  ConsumerState<PaperComparisonPanel> createState() =>
      _PaperComparisonPanelState();
}

class _PaperComparisonPanelState extends ConsumerState<PaperComparisonPanel> {
  late bool _matrix = widget.initialMatrix;
  String? _pairId;
  bool _starting = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(paperComparisonsProvider(widget.projectId));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Analisis antar-paper',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Telusuri kesamaan dan berhenti pada perbedaan pertama: '
              'konsep → variabel → data/objek → metode → permasalahan.',
            ),
            const SizedBox(height: 14),
            result.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Analisis belum dapat dimuat. Periksa koneksi ke backend.',
                  ),
                  TextButton(
                    onPressed: _refresh,
                    child: const Text('Muat ulang analisis'),
                  ),
                ],
              ),
              data: _content,
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(PairComparisonOverview overview) {
    final selected =
        overview.pairs.where((p) => p.id == _pairId).firstOrNull ??
        overview.pairs.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              label: Text(
                '${overview.readyPapers}/${overview.totalPapers} paper selesai direview',
              ),
            ),
            Chip(
              label: Text(
                '${overview.completed}/${overview.expectedPairs} pasangan selesai',
              ),
            ),
            Chip(label: Text('${overview.candidates} kandidat gap')),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Hanya hasil review terkini yang dibandingkan. Perubahan sumber memerlukan analisis ulang '
          'pasangan terkait. Kandidat gap masih perlu penilaian manusia dan literatur tambahan.',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: _starting || overview.readyPapers < 2 ? null : _start,
              icon: _starting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(_starting ? 'Mengantrekan…' : 'Analisis / coba lagi'),
            ),
            TextButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Perbarui'),
            ),
          ],
        ),
        if (_message != null || overview.warning != null) ...[
          const SizedBox(height: 8),
          Text(
            _message ?? overview.warning!,
            style: const TextStyle(color: AppColors.orange),
          ),
        ],
        if (overview.readyPapers < 2) ...[
          const SizedBox(height: 12),
          const Text(
            'Unggah minimal dua paper dalam proyek yang sama, lalu selesaikan review komponennya. '
            'Analisis pasangan akan diantrekan setelah review selesai.',
          ),
        ] else if (overview.pairs.isEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Belum ada perbandingan untuk versi sumber saat ini. Klik Analisis / coba lagi.',
          ),
        ],
        if (overview.pairs.length < overview.expectedPairs &&
            overview.pairs.isNotEmpty)
          const Text(
            'Ada pasangan baru atau sumber yang berubah. Jalankan analisis untuk melengkapinya.',
          ),
        if (overview.pending) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: overview.expectedPairs == 0
                ? null
                : overview.completed / overview.expectedPairs,
          ),
          const SizedBox(height: 8),
          const Text(
            'Worker memproses pasangan secara bertahap. Status diperbarui otomatis. '
            'Jika antrean tidak bergerak, pastikan worker aktif lalu coba lagi.',
            style: TextStyle(fontSize: 12),
          ),
        ],
        if (selected != null) ...[
          const SizedBox(height: 20),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Flowchart'),
                icon: Icon(Icons.account_tree_outlined),
              ),
              ButtonSegment(
                value: true,
                label: Text('Matrix'),
                icon: Icon(Icons.table_chart_outlined),
              ),
            ],
            selected: {_matrix},
            onSelectionChanged: (v) => setState(() => _matrix = v.first),
          ),
          const SizedBox(height: 16),
          if (_matrix) _comparisonMatrix(overview),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('pair-selector-${widget.projectId}-${selected.id}'),
            initialValue: selected.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Pasangan paper'),
            items: [
              for (var i = 0; i < overview.pairs.length; i++)
                DropdownMenuItem(
                  value: overview.pairs[i].id,
                  child: Text(
                    '${i + 1}. ${overview.pairs[i].label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _pairId = v),
          ),
          const SizedBox(height: 16),
          _pairDetail(selected),
        ],
      ],
    );
  }

  Widget _comparisonMatrix(PairComparisonOverview overview) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Matrix keputusan · geser horizontal; ketuk sel untuk evidence.',
        style: TextStyle(fontSize: 12),
      ),
      SingleChildScrollView(
        key: const Key('pair-comparison-matrix'),
        scrollDirection: Axis.horizontal,
        child: DataTable(
          dataRowMinHeight: 68,
          dataRowMaxHeight: 96,
          columns: [
            const DataColumn(label: Text('Pasangan')),
            for (final aspect in comparisonAspects)
              DataColumn(label: Text(aspectLabel(aspect))),
            const DataColumn(label: Text('Hasil / review')),
          ],
          rows: [
            for (var i = 0; i < overview.pairs.length; i++)
              _matrixRow(overview.pairs[i], i),
          ],
        ),
      ),
    ],
  );

  DataRow _matrixRow(PaperPair pair, int index) => DataRow(
    cells: [
      DataCell(
        SizedBox(
          width: 210,
          child: Text(
            '${index + 1}. ${pair.label}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        onTap: () => setState(() => _pairId = pair.id),
      ),
      for (final aspect in comparisonAspects)
        DataCell(
          Text(
            pair.steps.isEmpty
                ? 'Belum dianalisis'
                : decisionLabel(
                    pair.steps.firstWhere((s) => s.aspect == aspect).decision,
                  ),
          ),
          onTap: () {
            final step = pair.steps
                .where((s) => s.aspect == aspect)
                .firstOrNull;
            if (step != null) _showStep(pair, step);
          },
        ),
      DataCell(
        SizedBox(
          width: 210,
          child: Text(
            '${pair.statusLabel}'
            '${pair.reviews.isEmpty ? '' : '\nReview: ${pair.reviews.first.decision == 'accepted' ? 'Layak ditelusuri' : 'Ditolak'}'}',
          ),
        ),
        onTap: () => setState(() => _pairId = pair.id),
      ),
    ],
  );

  Widget _pairDetail(PaperPair pair) {
    if (pair.status != 'completed') {
      return Text('${pair.label}\n${pair.statusLabel}. ${pair.error ?? ''}');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_matrix)
          PairComparisonFlowchart(
            pair: pair,
            onStep: (i) => _showStep(pair, pair.steps[i]),
          ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: pair.outcome == 'candidate_gap'
                ? AppColors.orangeSoft
                : AppColors.primarySoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pair.statusLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (pair.stopAspect != null)
                Text('Alur berhenti: ${aspectLabel(pair.stopAspect!)}'),
              if (pair.candidate != null) ...[
                const SizedBox(height: 8),
                Text(pair.candidate!['summary'] as String),
                const SizedBox(height: 8),
                Text(pair.candidate!['validation_question'] as String),
              ],
              if (pair.outcome == 'no_gap')
                const Text(
                  'Tidak ada kandidat dari jalur ini. Ini tidak membuktikan '
                  'bahwa seluruh bidang penelitian bebas dari research gap.',
                ),
              if (pair.outcome == 'unrelated')
                const Text(
                  'Perbedaan konsep ini tidak ditetapkan sebagai kandidat gap.',
                ),
              if (pair.outcome == 'insufficient_evidence')
                const Text(
                  'Lengkapi atau tinjau ulang evidence sebelum mengambil keputusan.',
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final step in pair.steps)
          if (step.decision == 'not_compared')
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '${aspectLabel(step.aspect)} · Tidak dilanjutkan',
                style: const TextStyle(color: AppColors.muted),
              ),
            )
          else
            ExpansionTile(
              key: PageStorageKey('${pair.id}:${step.aspect}'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 16),
              leading: Icon(
                step.decision == 'yes'
                    ? Icons.check_circle_outline
                    : Icons.pause_circle_outline,
                color: step.decision == 'yes'
                    ? AppColors.green
                    : AppColors.orange,
              ),
              title: Text(aspectLabel(step.aspect)),
              subtitle: Text(decisionLabel(step.decision)),
              children: [_stepDetail(pair, step)],
            ),
        if (pair.candidate != null)
          _PairReviewForm(
            key: ValueKey('review-${pair.id}'),
            pair: pair,
            onSave: (decision, note) async {
              await ref
                  .read(paperComparisonRepositoryProvider)
                  .review(widget.projectId, pair.id, decision, note);
              _refresh();
            },
          ),
      ],
    );
  }

  Widget _stepDetail(PaperPair pair, PairStep step) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(step.reason),
      const SizedBox(height: 14),
      _evidenceList('A · ${pair.leftTitle}', step.leftEvidence),
      const SizedBox(height: 12),
      _evidenceList('B · ${pair.rightTitle}', step.rightEvidence),
    ],
  );

  Widget _evidenceList(String title, List<PairEvidence> evidence) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      if (evidence.isEmpty) const Text('Evidence yang cukup belum tersedia.'),
      for (final e in evidence)
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectionArea(child: Text('“${e.source.quote}”')),
              const SizedBox(height: 6),
              Text(
                '${e.source.kindLabel} · ${e.source.locationLabel}',
                style: const TextStyle(fontSize: 12),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => PaperResultScreen(
                      projectId: widget.projectId,
                      paperId: e.paperId,
                      initialPage: e.source.pageNumber,
                      initialHighlightText: e.source.quote,
                      initialBlockId: e.source.blockId,
                    ),
                  ),
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Buka evidence PDF'),
              ),
            ],
          ),
        ),
    ],
  );

  void _showStep(PaperPair pair, PairStep step) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .78,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              '${aspectLabel(step.aspect)} · ${decisionLabel(step.decision)}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _stepDetail(pair, step),
          ],
        ),
      ),
    ),
  );

  void _refresh() => ref.invalidate(paperComparisonsProvider(widget.projectId));
  Future<void> _start() async {
    setState(() {
      _starting = true;
      _message = null;
    });
    try {
      final result = await ref
          .read(paperComparisonRepositoryProvider)
          .start(widget.projectId);
      if (!mounted) return;
      setState(() => _message = result.warning);
      _refresh();
    } catch (e) {
      if (mounted)
        setState(() => _message = ProjectRepository.readableError(e));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }
}

class _PairReviewForm extends StatefulWidget {
  const _PairReviewForm({required this.pair, required this.onSave, super.key});
  final PaperPair pair;
  final Future<void> Function(String, String) onSave;
  @override
  State<_PairReviewForm> createState() => _PairReviewFormState();
}

class _PairReviewFormState extends State<_PairReviewForm> {
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 12),
      Text('Review kandidat', style: Theme.of(context).textTheme.titleMedium),
      const Text(
        'Terima berarti layak ditelusuri lebih lanjut. Kebaruan penelitian tetap harus dibuktikan.',
      ),
      if (widget.pair.reviews.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(
          'Keputusan terakhir: ${widget.pair.reviews.first.decision == 'accepted' ? 'Layak ditelusuri' : 'Ditolak'}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(widget.pair.reviews.first.note),
        ExpansionTile(
          title: Text('Riwayat review (${widget.pair.reviews.length})'),
          children: [
            for (final review in widget.pair.reviews)
              ListTile(
                title: Text(
                  review.decision == 'accepted'
                      ? 'Layak ditelusuri'
                      : 'Ditolak',
                ),
                subtitle: Text('${review.note}\n${review.createdAt.toLocal()}'),
              ),
          ],
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: _note,
        enabled: !_saving,
        maxLength: 2000,
        minLines: 2,
        maxLines: 5,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Alasan review (wajib)',
          hintText:
              'Jelaskan relevansi perbedaan dan langkah validasi selanjutnya.',
        ),
      ),
      if (_error != null)
        Text(_error!, style: const TextStyle(color: AppColors.red)),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: _saving || _note.text.trim().isEmpty
                ? null
                : () => _save('accepted'),
            icon: const Icon(Icons.check),
            label: const Text('Layak ditelusuri'),
          ),
          OutlinedButton.icon(
            onPressed: _saving || _note.text.trim().isEmpty
                ? null
                : () => _save('rejected'),
            icon: const Icon(Icons.close),
            label: const Text('Tolak kandidat'),
          ),
        ],
      ),
      if (_saving) const LinearProgressIndicator(),
    ],
  );
  Future<void> _save(String decision) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(decision, _note.text.trim());
      if (mounted) _note.clear();
    } catch (e) {
      if (mounted) setState(() => _error = ProjectRepository.readableError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
