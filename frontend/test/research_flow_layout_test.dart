import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/models/paper_label.dart';
import 'package:modellyng/src/widgets/research_flow_layout.dart';

import 'fixtures/research_flow_fixture.dart';

void main() {
  final diagram = buildFlowDiagram(figmaFlow());

  List<FlowNodeData> nodesOf(FlowNodeKind kind) =>
      diagram.nodes.where((node) => node.kind == kind).toList();

  Set<String> targetsOf(String id) =>
      diagram.childrenOf(id).map((node) => node.id).toSet();

  test('builds every Figma stage with the expected nodes', () {
    expect(nodesOf(FlowNodeKind.topic), hasLength(4));
    expect(nodesOf(FlowNodeKind.theme), hasLength(1));
    expect(nodesOf(FlowNodeKind.problem), hasLength(3));
    expect(nodesOf(FlowNodeKind.solution), hasLength(2));
    expect(nodesOf(FlowNodeKind.function), hasLength(2));
    expect(nodesOf(FlowNodeKind.conclusion), hasLength(1));
    expect(nodesOf(FlowNodeKind.conclusionPoint), hasLength(2));
    expect(nodesOf(FlowNodeKind.end), hasLength(1));

    final theme = diagram['theme:0']!;
    expect(theme.title, 'Isi');
    expect(theme.text, 'banjir');
    expect(diagram['topic:p1']!.fieldLabel, 'Topik');
    expect(diagram['problem:p1']!.fieldLabel, 'Masalah');
    expect(diagram['solution:0:0']!.title, 'Paper 1 & 2');
    expect(diagram['solution:0:0']!.fieldLabel, 'Solusi');
    expect(diagram['function:0:0:1']!.title, 'Fungsi 2');
    expect(diagram['point:0:0:0']!.title, 'Kesimpulan 1');
  });

  test('edges follow topik -> isi -> masalah -> solusi -> fungsi/kesimpulan', () {
    for (final paper in ['p1', 'p2', 'p3']) {
      expect(targetsOf('topic:$paper'), {'theme:0'});
    }
    expect(targetsOf('theme:0'), {'problem:p1', 'problem:p2', 'problem:p3'});
    expect(targetsOf('problem:p1'), {'solution:0:0'});
    expect(targetsOf('problem:p2'), {'solution:0:0'});
    expect(targetsOf('problem:p3'), {'solution:0:1'});
    expect(targetsOf('solution:0:0'), {
      'function:0:0:0',
      'function:0:0:1',
      'conclusion:0:0',
    });
    expect(targetsOf('conclusion:0:0'), {'point:0:0:0', 'point:0:0:1'});
    // Tanpa kesamaan: alur berhenti.
    expect(targetsOf('solution:0:1'), isEmpty);
    expect(targetsOf('topic:p4'), {'end:p4'});
    expect(targetsOf('end:p4'), isEmpty);
  });

  test('green continues, red ends', () {
    final shared = diagram['solution:0:0']!;
    final single = diagram['solution:0:1']!;
    expect(shared.tone, FlowTone.frequent);
    expect(shared.isEnd, isFalse);
    expect(single.tone, FlowTone.rare);
    expect(single.isEnd, isTrue);
    expect(diagram['end:p4']!.tone, FlowTone.rare);
    expect(diagram['topic:p4']!.tone, FlowTone.neutral);
    expect(diagram['problem:p1']!.tone, FlowTone.neutral);
  });

  test('columns run left to right and parents sit between children', () {
    double left(String id) => diagram[id]!.rect.left;
    expect(left('topic:p1'), lessThan(left('theme:0')));
    expect(left('theme:0'), lessThan(left('problem:p1')));
    expect(left('problem:p1'), lessThan(left('solution:0:0')));
    expect(left('solution:0:0'), lessThan(left('function:0:0:0')));
    expect(left('function:0:0:0'), lessThan(left('conclusion:0:0')));
    expect(left('conclusion:0:0'), lessThan(left('point:0:0:0')));
    expect(left('end:p4'), left('problem:p1'));

    double centerY(String id) => diagram[id]!.rect.center.dy;
    final topics = ['p1', 'p2', 'p3'].map((p) => centerY('topic:$p')).toList();
    expect(centerY('theme:0'), closeTo((topics.first + topics.last) / 2, 0.01));
    expect(
      centerY('solution:0:0'),
      closeTo((centerY('topic:p1') + centerY('topic:p2')) / 2, 0.01),
    );
    expect(centerY('solution:0:1'), closeTo(centerY('topic:p3'), 0.01));
    // Garis ke kesimpulan lewat di antara dua kotak fungsi.
    expect(centerY('function:0:0:0'), lessThan(centerY('conclusion:0:0')));
    expect(centerY('function:0:0:1'), greaterThan(centerY('conclusion:0:0')));
    expect(centerY('end:p4'), closeTo(centerY('topic:p4'), 0.01));
  });

  test('nodes never overlap and everything fits inside the canvas', () {
    for (final a in diagram.nodes) {
      expect(a.rect.left, greaterThanOrEqualTo(0));
      expect(a.rect.top, greaterThanOrEqualTo(0));
      expect(a.rect.right, lessThanOrEqualTo(diagram.size.width));
      expect(a.rect.bottom, lessThanOrEqualTo(diagram.size.height));
      for (final b in diagram.nodes) {
        if (identical(a, b)) continue;
        expect(
          a.rect.overlaps(b.rect),
          isFalse,
          reason: '${a.id} overlaps ${b.id}',
        );
      }
    }
    final lowestNode = diagram.nodes
        .map((node) => node.rect.bottom)
        .reduce((a, b) => a > b ? a : b);
    expect(diagram.legendRect.top, greaterThan(lowestNode));
    expect(diagram['topic:p4']!.rect.top, greaterThan(diagram['topic:p3']!.rect.bottom));
  });

  test('larger text scale makes cards taller', () {
    final scaled = buildFlowDiagram(
      figmaFlow(),
      metrics: const FlowMetrics(heightScale: 1.4),
    );
    expect(
      scaled['topic:p1']!.rect.height,
      closeTo(diagram['topic:p1']!.rect.height * 1.4, 0.01),
    );
    expect(scaled.size.height, greaterThan(diagram.size.height));
  });

  test('paper labels', () {
    expect(paperNumbersLabel([]), 'Paper');
    expect(paperNumbersLabel([3]), 'Paper 3');
    expect(paperNumbersLabel([2, 1]), 'Paper 1 & 2');
    expect(paperNumbersLabel([4, 1, 2, 2]), 'Paper 1, 2 & 4');
  });
}
