import 'dart:math' as math;
import 'dart:ui';

import '../models/paper_label.dart';
import '../models/research_flow.dart';

/// Jenis simpul pada peta alur riset, berurutan dari kiri ke kanan.
enum FlowNodeKind {
  topic,
  theme,
  problem,
  solution,
  function,
  conclusion,
  conclusionPoint,
  end,
}

/// Abu-abu netral, hijau (sering diteliti), atau merah (jarang diteliti).
enum FlowTone { neutral, frequent, rare }

class FlowNodeData {
  const FlowNodeData({
    required this.id,
    required this.kind,
    required this.title,
    required this.rect,
    this.fieldLabel,
    this.text = '',
    this.tone = FlowTone.neutral,
    this.isEnd = false,
    this.paperIds = const [],
  });

  final String id;
  final FlowNodeKind kind;

  /// Baris pertama kartu, misal "Paper 1 & 2", "Isi", "Fungsi 1".
  final String title;

  /// Label isian seperti di Figma ("Topik", "Masalah", "Solusi").
  final String? fieldLabel;
  final String text;
  final FlowTone tone;

  /// True bila alur berhenti di simpul ini ("end").
  final bool isEnd;
  final List<String> paperIds;
  final Rect rect;
}

class FlowEdgeData {
  const FlowEdgeData(this.from, this.to);

  final String from;
  final String to;
}

class FlowDiagram {
  FlowDiagram({
    required this.nodes,
    required this.edges,
    required this.size,
    required this.legendRect,
  }) : _byId = {for (final node in nodes) node.id: node};

  final List<FlowNodeData> nodes;
  final List<FlowEdgeData> edges;
  final Size size;
  final Rect legendRect;
  final Map<String, FlowNodeData> _byId;

  FlowNodeData? operator [](String id) => _byId[id];

  Iterable<FlowNodeData> childrenOf(String id) => edges
      .where((edge) => edge.from == id)
      .map((edge) => _byId[edge.to])
      .whereType<FlowNodeData>();
}

/// Ukuran tata letak. [heightScale] mengikuti skala teks perangkat agar teks
/// di dalam kartu tetap muat.
class FlowMetrics {
  const FlowMetrics({this.heightScale = 1});

  final double heightScale;

  static const double padding = 24;
  static const double columnGap = 56;
  static const double rowGap = 18;
  static const double groupGap = 30;
  static const double themeGap = 44;

  /// Celah di tengah kolom fungsi agar garis solusi -> kesimpulan lewat
  /// di antara kartu fungsi, seperti di Figma.
  static const double centerGap = 22;
  static const double legendGap = 36;
  static const double legendItemGap = 10;
  static const double legendWidth = 210;
  static const double endWidth = 72;

  /// Kolom: topik, isi, masalah (dan end), solusi, fungsi, kesimpulan, poin.
  static const List<double> columnWidths = [160, 120, 160, 160, 160, 120, 160];

  double get cardHeight => 104 * heightScale;
  double get pointHeight => 88 * heightScale;
  double get hubHeight => 72 * heightScale;
  double get compactHeight => 40 * heightScale;
  double get legendItemHeight => 32 * heightScale;

  double columnX(int column) {
    var x = padding;
    for (var index = 0; index < column; index++) {
      x += columnWidths[index] + columnGap;
    }
    return x;
  }
}

int columnOf(FlowNodeKind kind) => switch (kind) {
  FlowNodeKind.topic => 0,
  FlowNodeKind.theme => 1,
  FlowNodeKind.problem || FlowNodeKind.end => 2,
  FlowNodeKind.solution => 3,
  FlowNodeKind.function => 4,
  FlowNodeKind.conclusion => 5,
  FlowNodeKind.conclusionPoint => 6,
};

/// Menyusun posisi simpul dan garis seperti Figma: tiap kelompok solusi
/// menempati satu pita horizontal, simpul induk berada di tengah anak-anaknya,
/// dan paper tanpa kesamaan topik diletakkan di bawah dengan simpul end.
FlowDiagram buildFlowDiagram(
  ResearchFlowMap flow, {
  FlowMetrics metrics = const FlowMetrics(),
}) {
  final numberOf = {for (final paper in flow.papers) paper.paperId: paper.number};
  String titleFor(List<String> paperIds) => paperNumbersLabel(
    paperIds.map((id) => numberOf[id] ?? 0).where((number) => number > 0),
  );

  final nodes = <FlowNodeData>[];
  final edges = <FlowEdgeData>[];

  Rect place(FlowNodeKind kind, double top, double height, {double? width}) {
    final column = columnOf(kind);
    return Rect.fromLTWH(
      metrics.columnX(column),
      top,
      width ?? FlowMetrics.columnWidths[column],
      height,
    );
  }

  var y = FlowMetrics.padding;
  var placedRows = false;

  for (var t = 0; t < flow.themes.length; t++) {
    final theme = flow.themes[t];
    final itemsById = {for (final item in theme.items) item.paperId: item};
    final themeId = 'theme:$t';
    final topicCenters = <double>[];
    final themeEdges = <FlowEdgeData>[];

    for (var s = 0; s < theme.solutions.length; s++) {
      final solution = theme.solutions[s];
      final members = solution.paperIds.where(itemsById.containsKey).toList();
      if (members.isEmpty) continue;
      if (placedRows) {
        y += topicCenters.isEmpty ? FlowMetrics.themeGap : FlowMetrics.groupGap;
      }
      placedRows = true;

      final functions = solution.shared ? solution.functions : const <String>[];
      final points = solution.shared ? solution.conclusions : const <String>[];
      final above = (functions.length + 1) ~/ 2;
      final below = functions.length - above;
      final leftHeight = _stack(members.length, metrics.cardHeight);
      final pointsExtent = _stack(points.length, metrics.pointHeight);
      // Ruang di atas dan di bawah garis tengah pita dihitung terpisah agar
      // jumlah fungsi ganjil tidak menyisakan ruang kosong.
      double extent(int functionCount) => [
        leftHeight / 2,
        metrics.cardHeight / 2,
        pointsExtent / 2,
        if (functions.isNotEmpty)
          _stack(functionCount, metrics.pointHeight) + FlowMetrics.centerGap / 2,
      ].reduce(math.max);
      final up = extent(above);
      final bandHeight = up + extent(below);
      final center = y + up;
      final solutionId = 'solution:$t:$s';

      var rowTop = center - leftHeight / 2;
      for (final paperId in members) {
        final item = itemsById[paperId]!;
        final topicId = 'topic:$paperId';
        final problemId = 'problem:$paperId';
        nodes
          ..add(
            FlowNodeData(
              id: topicId,
              kind: FlowNodeKind.topic,
              title: titleFor([paperId]),
              fieldLabel: 'Topik',
              text: item.topic,
              paperIds: [paperId],
              rect: place(FlowNodeKind.topic, rowTop, metrics.cardHeight),
            ),
          )
          ..add(
            FlowNodeData(
              id: problemId,
              kind: FlowNodeKind.problem,
              title: titleFor([paperId]),
              fieldLabel: 'Masalah',
              text: item.problem,
              paperIds: [paperId],
              rect: place(FlowNodeKind.problem, rowTop, metrics.cardHeight),
            ),
          );
        themeEdges
          ..add(FlowEdgeData(topicId, themeId))
          ..add(FlowEdgeData(themeId, problemId));
        edges.add(FlowEdgeData(problemId, solutionId));
        topicCenters.add(rowTop + metrics.cardHeight / 2);
        rowTop += metrics.cardHeight + FlowMetrics.rowGap;
      }

      nodes.add(
        FlowNodeData(
          id: solutionId,
          kind: FlowNodeKind.solution,
          title: titleFor(members),
          fieldLabel: 'Solusi',
          text: solution.label,
          tone: solution.shared ? FlowTone.frequent : FlowTone.rare,
          isEnd: !solution.shared,
          paperIds: members,
          rect: place(
            FlowNodeKind.solution,
            center - metrics.cardHeight / 2,
            metrics.cardHeight,
          ),
        ),
      );

      var functionTop =
          center - FlowMetrics.centerGap / 2 - _stack(above, metrics.pointHeight);
      for (var i = 0; i < functions.length; i++) {
        if (i == above) functionTop = center + FlowMetrics.centerGap / 2;
        final id = 'function:$t:$s:$i';
        nodes.add(
          FlowNodeData(
            id: id,
            kind: FlowNodeKind.function,
            title: 'Fungsi ${i + 1}',
            text: functions[i],
            paperIds: members,
            rect: place(FlowNodeKind.function, functionTop, metrics.pointHeight),
          ),
        );
        edges.add(FlowEdgeData(solutionId, id));
        functionTop += metrics.pointHeight + FlowMetrics.rowGap;
      }

      if (points.isNotEmpty) {
        final conclusionId = 'conclusion:$t:$s';
        nodes.add(
          FlowNodeData(
            id: conclusionId,
            kind: FlowNodeKind.conclusion,
            title: 'Kesimpulan',
            paperIds: members,
            rect: place(
              FlowNodeKind.conclusion,
              center - metrics.compactHeight / 2,
              metrics.compactHeight,
            ),
          ),
        );
        edges.add(FlowEdgeData(solutionId, conclusionId));
        var pointTop = center - pointsExtent / 2;
        for (var j = 0; j < points.length; j++) {
          final id = 'point:$t:$s:$j';
          nodes.add(
            FlowNodeData(
              id: id,
              kind: FlowNodeKind.conclusionPoint,
              title: 'Kesimpulan ${j + 1}',
              text: points[j],
              paperIds: members,
              rect: place(
                FlowNodeKind.conclusionPoint,
                pointTop,
                metrics.pointHeight,
              ),
            ),
          );
          edges.add(FlowEdgeData(conclusionId, id));
          pointTop += metrics.pointHeight + FlowMetrics.rowGap;
        }
      }
      y += bandHeight;
    }

    if (topicCenters.isEmpty) continue;
    final hubCenter = (topicCenters.first + topicCenters.last) / 2;
    nodes.add(
      FlowNodeData(
        id: themeId,
        kind: FlowNodeKind.theme,
        title: 'Isi',
        text: theme.label,
        paperIds: [for (final item in theme.items) item.paperId],
        rect: place(
          FlowNodeKind.theme,
          hubCenter - metrics.hubHeight / 2,
          metrics.hubHeight,
        ),
      ),
    );
    edges.addAll(themeEdges);
  }

  for (var u = 0; u < flow.unrelated.length; u++) {
    final entry = flow.unrelated[u];
    if (placedRows) {
      y += u == 0 ? FlowMetrics.themeGap : FlowMetrics.rowGap;
    }
    placedRows = true;
    final topicId = 'topic:${entry.paperId}';
    final endId = 'end:${entry.paperId}';
    nodes
      ..add(
        FlowNodeData(
          id: topicId,
          kind: FlowNodeKind.topic,
          title: titleFor([entry.paperId]),
          fieldLabel: 'Topik',
          text: entry.topic,
          paperIds: [entry.paperId],
          rect: place(FlowNodeKind.topic, y, metrics.cardHeight),
        ),
      )
      ..add(
        FlowNodeData(
          id: endId,
          kind: FlowNodeKind.end,
          title: 'End',
          tone: FlowTone.rare,
          isEnd: true,
          paperIds: [entry.paperId],
          rect: place(
            FlowNodeKind.end,
            y + (metrics.cardHeight - metrics.compactHeight) / 2,
            metrics.compactHeight,
            width: FlowMetrics.endWidth,
          ),
        ),
      );
    edges.add(FlowEdgeData(topicId, endId));
    y += metrics.cardHeight;
  }

  final legendRect = Rect.fromLTWH(
    FlowMetrics.padding,
    y + FlowMetrics.legendGap,
    FlowMetrics.legendWidth,
    metrics.legendItemHeight * 2 + FlowMetrics.legendItemGap,
  );
  final right = nodes.fold<double>(
    legendRect.right,
    (value, node) => math.max(value, node.rect.right),
  );
  return FlowDiagram(
    nodes: nodes,
    edges: edges,
    size: Size(
      right + FlowMetrics.padding,
      legendRect.bottom + FlowMetrics.padding,
    ),
    legendRect: legendRect,
  );
}

double _stack(int count, double height) =>
    count <= 0 ? 0 : count * height + (count - 1) * FlowMetrics.rowGap;
