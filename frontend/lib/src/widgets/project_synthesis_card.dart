import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/project_repository.dart';
import '../data/project_synthesis_repository.dart';
import '../models/project_synthesis.dart';
import '../theme/app_theme.dart';

/// Kartu "AI Comparative Synthesis" di menu Matriks & Sintesis.
///
/// Sintesis bersifat global: mencakup semua paper terreview di project dan
/// tidak terpengaruh pilihan paper pada tabel. Hasil tersimpan langsung
/// dimuat; AI hanya dipanggil saat pengguna membuat atau memperbarui.
class ProjectSynthesisCard extends ConsumerStatefulWidget {
  const ProjectSynthesisCard({
    required this.projectId,
    required this.projectTitle,
    required this.paperCount,
    super.key,
  });

  final String projectId;
  final String projectTitle;
  final int paperCount;

  @override
  ConsumerState<ProjectSynthesisCard> createState() =>
      _ProjectSynthesisCardState();
}

class _ProjectSynthesisCardState extends ConsumerState<ProjectSynthesisCard> {
  bool _generating = false;
  bool _lastForce = false;
  String? _error;
  ProjectSynthesis? _latest;

  Future<void> _generate({bool force = false}) async {
    setState(() {
      _generating = true;
      _lastForce = force;
      _error = null;
    });
    try {
      final result = await ref
          .read(projectSynthesisRepositoryProvider)
          .generateSynthesis(widget.projectId, forceRegenerate: force);
      if (mounted) setState(() => _latest = result);
    } catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static String _readableError(Object error) {
    if (error is DioException &&
        error.type == DioExceptionType.receiveTimeout) {
      return 'Penyusunan sintesis memakan waktu terlalu lama. Coba lagi sebentar lagi.';
    }
    // Pesan "detail" dari backend sudah ramah pengguna (misal kuota Gemini).
    if (error is DioException) return ProjectRepository.readableError(error);
    return 'Sintesis AI belum dapat disusun. Coba lagi.';
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(projectSynthesisProvider(widget.projectId));
    final synthesis = _latest ?? saved.value;

    final Widget body;
    if (_generating) {
      body = _ProgressMessage(
        title: 'Menyusun sintesis dari ${widget.paperCount} paper…',
        subtitle: 'Biasanya 20–60 detik. Tetap di halaman ini.',
      );
    } else if (synthesis != null) {
      body = _SynthesisResult(
        synthesis: synthesis,
        onCopyPoints: () => _copy(
          synthesis.toPointsText(widget.projectTitle),
          'Sintesis disalin sebagai poin.',
        ),
        onCopyAcademic: synthesis.academicText.isEmpty
            ? null
            : () => _copy(
                synthesis.academicText,
                'Paragraf akademik dan daftar pustaka disalin.',
              ),
        onRegenerate: () => _generate(force: true),
      );
    } else if (saved.isLoading) {
      body = const _ProgressMessage(title: 'Memuat sintesis tersimpan…');
    } else {
      body = _EmptyState(
        paperCount: widget.paperCount,
        loadError: saved.hasError
            ? 'Sintesis tersimpan belum dapat dimuat: '
                  '${_readableError(saved.error!)}'
            : null,
        onRetryLoad: () =>
            ref.invalidate(projectSynthesisProvider(widget.projectId)),
        onGenerate: () => _generate(),
      );
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.primarySoft, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(paperCount: widget.paperCount),
            const SizedBox(height: 16),
            if (_error != null) ...[
              _Notice(
                key: const Key('synthesis-error'),
                icon: Icons.error_outline_rounded,
                color: AppColors.red,
                background: AppColors.redSoft,
                message: _error!,
                actionLabel: 'Coba lagi',
                onAction: _generating ? null : () => _generate(force: _lastForce),
              ),
              const SizedBox(height: 16),
            ],
            body,
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.paperCount});

  final int paperCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.auto_awesome, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AI Comparative Synthesis',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Mencakup semua $paperCount paper di proyek, tidak terpengaruh pilihan paper di atas.',
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.paperCount,
    required this.onGenerate,
    required this.onRetryLoad,
    this.loadError,
  });

  final int paperCount;
  final VoidCallback onGenerate;
  final VoidCallback onRetryLoad;
  final String? loadError;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (loadError != null) ...[
          _Notice(
            icon: Icons.cloud_off_rounded,
            color: AppColors.orange,
            background: AppColors.orangeSoft,
            message: loadError!,
            actionLabel: 'Muat ulang',
            onAction: onRetryLoad,
          ),
          const SizedBox(height: 16),
        ],
        Text(
          'Rangkum persamaan, perbedaan, pola, pendekatan, serta celah dan ide '
          'penelitian dari semua $paperCount paper. Setiap poin menyebut paper '
          'sumbernya dan bisa disalin sebagai paragraf akademik.',
          style: const TextStyle(color: AppColors.muted, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('synthesis-generate'),
          onPressed: onGenerate,
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text('Buat Sintesis AI'),
        ),
      ],
    );
  }
}

class _ProgressMessage extends StatelessWidget {
  const _ProgressMessage({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SynthesisResult extends StatelessWidget {
  const _SynthesisResult({
    required this.synthesis,
    required this.onCopyPoints,
    required this.onCopyAcademic,
    required this.onRegenerate,
  });

  final ProjectSynthesis synthesis;
  final VoidCallback onCopyPoints;
  final VoidCallback? onCopyAcademic;
  final VoidCallback onRegenerate;

  static const _sectionIcons = <String, IconData>{
    'similarities': Icons.done_all_rounded,
    'differences': Icons.compare_arrows_rounded,
    'research_patterns': Icons.timeline_rounded,
    'approach_differences': Icons.alt_route_rounded,
    'gaps': Icons.lightbulb_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final sections = synthesis.sections.where((s) => s.points.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (synthesis.stale) ...[
          _Notice(
            key: const Key('synthesis-stale'),
            icon: Icons.update_rounded,
            color: AppColors.orange,
            background: AppColors.orangeSoft,
            message:
                'Hasil review paper berubah sejak sintesis ini dibuat. Perbarui agar sintesis memakai data terbaru.',
            actionLabel: 'Perbarui',
            onAction: onRegenerate,
          ),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('synthesis-copy-points'),
              onPressed: onCopyPoints,
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Salin'),
            ),
            OutlinedButton.icon(
              key: const Key('synthesis-copy-academic'),
              onPressed: onCopyAcademic,
              icon: const Icon(Icons.article_outlined, size: 18),
              label: const Text('Salin sebagai paragraf'),
            ),
            TextButton.icon(
              key: const Key('synthesis-regenerate'),
              onPressed: onRegenerate,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Perbarui'),
            ),
          ],
        ),
        for (final section in sections) ...[
          const SizedBox(height: 24),
          _BlockTitle(
            icon: _sectionIcons[section.key] ?? Icons.notes_rounded,
            title: section.title,
          ),
          const SizedBox(height: 10),
          for (final point in section.points)
            _Bullet(
              text: point.text,
              tag: synthesis.labelFor(point.paperIds),
            ),
        ],
        if (synthesis.researchIdeas.isNotEmpty) ...[
          const SizedBox(height: 24),
          const _BlockTitle(
            icon: Icons.rocket_launch_outlined,
            title: 'Ide Penelitian Lanjutan',
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < synthesis.researchIdeas.length; i++)
            _IdeaTile(
              number: i + 1,
              idea: synthesis.researchIdeas[i],
              tag: synthesis.labelFor(synthesis.researchIdeas[i].paperIds),
            ),
        ],
        if (synthesis.paperPositions.isNotEmpty) ...[
          const SizedBox(height: 24),
          const _BlockTitle(
            icon: Icons.place_outlined,
            title: 'Posisi Tiap Paper',
          ),
          const SizedBox(height: 10),
          for (final position in synthesis.paperPositions)
            _LabeledLine(
              label: synthesis.labelFor([position.paperId]),
              text: position.text,
            ),
        ],
        const SizedBox(height: 24),
        const _BlockTitle(
          icon: Icons.menu_book_outlined,
          title: 'Daftar Paper',
        ),
        const SizedBox(height: 10),
        for (final paper in synthesis.papers)
          _LabeledLine(
            label: 'Paper ${paper.number}',
            text: [
              paper.title,
              paper.citation,
              if (!paper.included) '(belum ada hasil review)',
            ].join(' '),
            muted: true,
          ),
        const SizedBox(height: 20),
        Text(
          _footer(synthesis),
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    );
  }

  static String _footer(ProjectSynthesis synthesis) {
    final parts = <String>[
      if (synthesis.generatedAt != null)
        'Dibuat ${_formatDate(synthesis.generatedAt!)}',
      if (synthesis.modelName != null) synthesis.modelName!,
    ];
    final meta = parts.isEmpty ? '' : '${parts.join(' · ')}. ';
    return '${meta}Disusun AI dari hasil review terverifikasi. '
        'Periksa kembali ke paper sumber sebelum dipakai.';
  }

  static String _formatDate(DateTime value) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year}, '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _BlockTitle extends StatelessWidget {
  const _BlockTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text, required this.tag});

  final String text;
  final String tag;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, right: 10),
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                _PaperTag(label: tag),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaperTag extends StatelessWidget {
  const _PaperTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryDark,
        ),
      ),
    );
  }
}

class _IdeaTile extends StatelessWidget {
  const _IdeaTile({required this.number, required this.idea, required this.tag});

  final int number;
  final SynthesisIdea idea;
  final String tag;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.primary,
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  idea.title,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                if (idea.rationale.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    idea.rationale,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: Color(0xFF3B4558),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                _PaperTag(label: tag),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledLine extends StatelessWidget {
  const _LabeledLine({
    required this.label,
    required this.text,
    this.muted = false,
  });

  final String label;
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
            TextSpan(text: text),
          ],
        ),
        style: TextStyle(
          fontSize: muted ? 13 : 14,
          height: 1.5,
          color: muted ? const Color(0xFF3B4558) : AppColors.ink,
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.background,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.ink,
              ),
            ),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
