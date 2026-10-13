import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/project_repository.dart';
import '../data/research_flow_repository.dart';
import '../models/research_flow.dart';
import '../theme/app_theme.dart';
import 'research_flow_layout.dart';

/// Warna kanvas mengikuti Figma: abu-abu netral, hijau untuk sering
/// diteliti, merah untuk jarang diteliti.
abstract final class FlowColors {
  static const neutral = Color(0xFFDFE2E7);
  static const frequent = Color(0xFF6EDC7C);
  static const rare = Color(0xFFFF6B6B);
  static const edge = Color(0xFFC3C8D0);

  static Color of(FlowTone tone) => switch (tone) {
    FlowTone.neutral => neutral,
    FlowTone.frequent => frequent,
    FlowTone.rare => rare,
  };
}

/// Kotak kanvas di layar Maps (GAP): memuat peta lalu menampilkan status
/// memuat, gagal, kosong, atau kanvasnya.
class ResearchFlowPanel extends ConsumerWidget {
  const ResearchFlowPanel({required this.projectId, this.height = 480, super.key});

  final String projectId;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(researchFlowProvider(projectId));
    return Container(
      key: const Key('research-flow-panel'),
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: flow.when(
        skipLoadingOnRefresh: false,
        loading: () => const _FlowMessage(
          loading: true,
          title: 'Menyusun peta alur riset…',
          message: 'Penyusunan pertama bisa memakan waktu hingga satu menit.',
        ),
        error: (error, _) => _FlowMessage(
          icon: Icons.error_outline_rounded,
          title: 'Peta alur belum dapat dimuat',
          message: _errorText(error),
          actionLabel: 'Coba lagi',
          onAction: () => ref.invalidate(researchFlowProvider(projectId)),
        ),
        data: (map) => map.isEmpty
            ? const _FlowMessage(
                icon: Icons.account_tree_outlined,
                title: 'Belum ada alur riset',
                message:
                    'Peta muncul setelah minimal satu paper selesai direview.',
              )
            : ResearchFlowCanvas(flow: map),
      ),
    );
  }

  static String _errorText(Object error) {
    if (error is DioException &&
        error.type == DioExceptionType.receiveTimeout) {
      return 'Penyusunan peta memakan waktu lebih lama dari biasanya. Coba lagi sebentar lagi.';
    }
    return ProjectRepository.readableError(error);
  }
}

/// Kanvas interaktif (geser, cubit untuk zoom, tombol zoom) berisi peta alur.
class ResearchFlowCanvas extends StatefulWidget {
  const ResearchFlowCanvas({
    required this.flow,
    this.allowFullscreen = true,
    super.key,
  });

  final ResearchFlowMap flow;
  final bool allowFullscreen;

  @override
  State<ResearchFlowCanvas> createState() => _ResearchFlowCanvasState();
}

class _ResearchFlowCanvasState extends State<ResearchFlowCanvas> {
  static const _minScale = 0.2;
  static const _maxScale = 2.0;

  /// Skala terkecil tampilan awal agar tulisan di kotak masih terbaca.
  static const _readableScale = 0.6;

  final _controller = TransformationController();
  Size _viewport = Size.zero;
  Size? _viewFor;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textScale = (MediaQuery.textScalerOf(context).scale(10) / 10)
        .clamp(1.0, 1.6)
        .toDouble();
    final diagram = buildFlowDiagram(
      widget.flow,
      metrics: FlowMetrics(heightScale: textScale),
    );

    final canvas = LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        if (viewport != _viewport || diagram.size != _viewFor) {
          final firstView = _viewFor == null;
          _viewport = viewport;
          _viewFor = diagram.size;
          final initial = _initialView(diagram.size);
          if (firstView) {
            // Belum ada listener: aman diatur sebelum InteractiveViewer dibuat.
            _controller.value = initial;
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _controller.value = initial;
            });
          }
        }

        return InteractiveViewer(
          transformationController: _controller,
          constrained: false,
          minScale: _minScale,
          maxScale: _maxScale,
          boundaryMargin: const EdgeInsets.all(120),
          child: SizedBox.fromSize(
            size: diagram.size,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _FlowEdgePainter(diagram)),
                ),
                for (final node in diagram.nodes)
                  Positioned.fromRect(
                    rect: node.rect,
                    child: FlowNodeCard(
                      node: node,
                      onTap: () => _showDetail(node, diagram),
                    ),
                  ),
                Positioned.fromRect(
                  rect: diagram.legendRect,
                  child: const _FlowLegend(),
                ),
              ],
            ),
          ),
        );
      },
    );

    // Tombol berada di luar area gambar agar tidak menutupi kotak alur.
    return Column(
      children: [
        _CanvasToolbar(
          onZoomIn: () => _zoomBy(1.25),
          onZoomOut: () => _zoomBy(0.8),
          onFit: () => _controller.value = _fitView(diagram.size),
          onFullscreen: widget.allowFullscreen ? _openFullscreen : null,
        ),
        const Divider(height: 1, thickness: 1, color: AppColors.border),
        Expanded(child: canvas),
      ],
    );
  }

  double _fitScale(Size content) {
    if (_viewport.isEmpty || content.isEmpty) return 1;
    return math
        .min(_viewport.width / content.width, _viewport.height / content.height)
        .clamp(_minScale, 1.0)
        .toDouble();
  }

  /// Seluruh peta terlihat bila tulisannya masih terbaca (layar lebar).
  /// Di layar sempit, peta dimulai dari kolom paling kiri (topik) setinggi
  /// kotak kanvas, lalu pengguna menggeser ke kanan mengikuti alur.
  Matrix4 _initialView(Size content) {
    if (_fitScale(content) >= _readableScale) return _fitView(content);
    final scale = (_viewport.height / content.height)
        .clamp(_readableScale, 1.0)
        .toDouble();
    final height = content.height * scale;
    final dy = height < _viewport.height ? (_viewport.height - height) / 2 : 0.0;
    return _matrix(scale, 0, dy);
  }

  Matrix4 _fitView(Size content) {
    final scale = _fitScale(content);
    return _matrix(
      scale,
      (_viewport.width - content.width * scale) / 2,
      (_viewport.height - content.height * scale) / 2,
    );
  }

  void _zoomBy(double factor) {
    final current = _controller.value;
    final scale = current.getMaxScaleOnAxis();
    final next = (scale * factor).clamp(_minScale, _maxScale).toDouble();
    final ratio = next / scale;
    final focal = _viewport.center(Offset.zero);
    final translation = current.getTranslation();
    _controller.value = _matrix(
      next,
      focal.dx - (focal.dx - translation.x) * ratio,
      focal.dy - (focal.dy - translation.y) * ratio,
    );
  }

  // Skala ketiga sumbu sama seperti InteractiveViewer, agar
  // getMaxScaleOnAxis() mengembalikan skala zoom yang sebenarnya.
  static Matrix4 _matrix(double scale, double dx, double dy) =>
      Matrix4.diagonal3Values(scale, scale, scale)..setTranslationRaw(dx, dy, 0);

  void _openFullscreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: const Text('Peta Alur Riset', style: TextStyle(fontSize: 16)),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
          ),
          body: SafeArea(
            child: ResearchFlowCanvas(flow: widget.flow, allowFullscreen: false),
          ),
        ),
      ),
    );
  }

  void _showDetail(FlowNodeData node, FlowDiagram diagram) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      builder: (_) =>
          _FlowNodeDetail(node: node, flow: widget.flow, diagram: diagram),
    );
  }
}

/// Satu kartu simpul dengan format Figma: judul, label isian, lalu isinya.
class FlowNodeCard extends StatelessWidget {
  const FlowNodeCard({required this.node, required this.onTap, super.key});

  final FlowNodeData node;
  final VoidCallback onTap;

  static const _title = TextStyle(
    fontSize: 11.5,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );
  static const _label = TextStyle(
    fontSize: 10.5,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: Color(0xFF3B4558),
  );
  static const _value = TextStyle(
    fontSize: 11.5,
    height: 1.25,
    color: AppColors.ink,
  );

  @override
  Widget build(BuildContext context) {
    final compact =
        node.kind == FlowNodeKind.conclusion || node.kind == FlowNodeKind.end;
    return Semantics(
      button: true,
      label: flowNodeSemanticLabel(node),
      excludeSemantics: true,
      child: Material(
        color: FlowColors.of(node.tone),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          key: Key('flow-node-${node.id}'),
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: compact ? 0 : 10,
            ),
            child: compact
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      node.title,
                      style: _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.title,
                        style: _title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: node.fieldLabel == null ? 4 : 6),
                      if (node.fieldLabel != null)
                        Text('${node.fieldLabel}:', style: _label, maxLines: 1),
                      Expanded(
                        child: Text(
                          node.text,
                          style: _value,
                          maxLines: node.isEnd ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (node.isEnd) const Text('End', style: _title),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

String flowNodeSemanticLabel(FlowNodeData node) {
  final parts = <String>[node.title];
  if (node.fieldLabel != null) parts.add('${node.fieldLabel}: ${node.text}');
  if (node.fieldLabel == null && node.text.isNotEmpty) parts.add(node.text);
  if (node.tone == FlowTone.frequent) parts.add('sering diteliti');
  if (node.tone == FlowTone.rare && node.kind != FlowNodeKind.end) {
    parts.add('jarang diteliti');
  }
  if (node.isEnd && node.kind != FlowNodeKind.end) parts.add('end');
  return parts.join('. ');
}

class _FlowEdgePainter extends CustomPainter {
  _FlowEdgePainter(this.diagram);

  final FlowDiagram diagram;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FlowColors.edge
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    for (final edge in diagram.edges) {
      final from = diagram[edge.from];
      final to = diagram[edge.to];
      if (from == null || to == null) continue;
      final start = from.rect.centerRight;
      final end = to.rect.centerLeft;
      final bend = (end.dx - start.dx) / 2;
      canvas.drawPath(
        Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(
            start.dx + bend,
            start.dy,
            end.dx - bend,
            end.dy,
            end.dx,
            end.dy,
          ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FlowEdgePainter oldDelegate) =>
      oldDelegate.diagram != diagram;
}

class _FlowLegend extends StatelessWidget {
  const _FlowLegend();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _LegendItem(
            color: FlowColors.rare,
            label: 'Merah = jarang diteliti',
          ),
        ),
        SizedBox(height: FlowMetrics.legendItemGap),
        Expanded(
          child: _LegendItem(
            color: FlowColors.frequent,
            label: 'Hijau = sering diteliti',
          ),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

class _CanvasToolbar extends StatelessWidget {
  const _CanvasToolbar({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
    this.onFullscreen,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;
  final VoidCallback? onFullscreen;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String tooltip, VoidCallback onPressed) {
      return IconButton(
        icon: Icon(icon, size: 20, color: AppColors.ink),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      );
    }

    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 4),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Geser untuk menjelajah, cubit atau tombol untuk zoom.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
            button(Icons.remove, 'Perkecil', onZoomOut),
            button(Icons.add, 'Perbesar', onZoomIn),
            button(Icons.fit_screen_outlined, 'Tampilkan seluruh peta', onFit),
            if (onFullscreen != null)
              button(Icons.open_in_full_rounded, 'Layar penuh', onFullscreen!),
          ],
        ),
      ),
    );
  }
}

class _FlowMessage extends StatelessWidget {
  const _FlowMessage({
    required this.title,
    required this.message,
    this.icon,
    this.loading = false,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final IconData? icon;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox.square(
                dimension: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            else if (icon != null)
              Icon(icon, size: 36, color: AppColors.muted),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FlowNodeDetail extends StatelessWidget {
  const _FlowNodeDetail({
    required this.node,
    required this.flow,
    required this.diagram,
  });

  final FlowNodeData node;
  final ResearchFlowMap flow;
  final FlowDiagram diagram;

  @override
  Widget build(BuildContext context) {
    final papers = {for (final paper in flow.papers) paper.paperId: paper};
    final points = node.kind == FlowNodeKind.conclusion
        ? diagram.childrenOf(node.id).toList()
        : const <FlowNodeData>[];
    final status = _status();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _stageName(node.kind).toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              node.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            if (status != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: FlowColors.of(node.tone).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
            if (node.text.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                node.text,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: AppColors.ink,
                ),
              ),
            ],
            for (final point in points) ...[
              const SizedBox(height: 10),
              Text(
                '${point.title}: ${point.text}',
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.ink,
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'Paper sumber',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            for (final paperId in node.paperIds)
              if (papers[paperId] case final paper?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Paper ${paper.number}: ${paper.title}',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Color(0xFF3B4558),
                    ),
                  ),
                ),
            const SizedBox(height: 20),
            const Text(
              'Disusun AI dari hasil review paper yang sudah diverifikasi. '
              'Periksa kembali ke paper sumber sebelum dipakai.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  String? _status() {
    if (node.kind == FlowNodeKind.end) {
      return 'Topik tidak memiliki kesamaan dengan paper lain, alur berhenti (end).';
    }
    if (node.kind != FlowNodeKind.solution) return null;
    if (node.tone == FlowTone.frequent) {
      return 'Sering diteliti: solusi sama dipakai ${node.paperIds.length} paper, alur berlanjut.';
    }
    return 'Jarang diteliti: tidak ada kesamaan solusi, alur berhenti (end).';
  }

  static String _stageName(FlowNodeKind kind) => switch (kind) {
    FlowNodeKind.topic => 'Topik',
    FlowNodeKind.theme => 'Isi',
    FlowNodeKind.problem => 'Masalah',
    FlowNodeKind.solution => 'Solusi',
    FlowNodeKind.function => 'Fungsi solusi',
    FlowNodeKind.conclusion => 'Kesimpulan',
    FlowNodeKind.conclusionPoint => 'Poin kesimpulan',
    FlowNodeKind.end => 'End',
  };
}
