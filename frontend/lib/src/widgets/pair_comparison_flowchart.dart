import 'package:flutter/material.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart';

import '../data/paper_comparison_repository.dart';
import '../theme/app_theme.dart';

/// Only fixed labels enter Mermaid. Paper/model text is rendered by Flutter.
String pairFlowchartCode(PaperPair pair) {
  final code = StringBuffer('flowchart TD\n');
  code.writeln('left[Paper A]\nright[Paper B]\nleft --> s0\nright --> s0');
  final visited = pair.steps
      .where((s) => s.decision != 'not_compared')
      .toList();
  for (var i = 0; i < visited.length; i++) {
    final step = visited[i];
    code.writeln('s$i{${aspectLabel(step.aspect)} sesuai?}');
    if (step.decision == 'yes' && i + 1 < visited.length) {
      code.writeln('s$i -->|Yes| s${i + 1}');
    } else {
      final edge = switch (step.decision) {
        'yes' => 'Yes',
        'no' => 'No',
        _ => 'Belum cukup',
      };
      code.writeln('s$i -->|$edge| outcome[${outcomeLabel(pair.outcome)}]');
    }
  }
  if (pair.outcome == 'candidate_gap') {
    code.writeln('outcome --> review[Review manusia dan literatur tambahan]');
  }
  return code.toString();
}

class PairComparisonFlowchart extends StatelessWidget {
  const PairComparisonFlowchart({
    required this.pair,
    required this.onStep,
    super.key,
  });
  final PaperPair pair;
  final ValueChanged<int> onStep;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'A · ${pair.leftTitle}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      Text(
        'B · ${pair.rightTitle}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      Container(
        key: const Key('pair-flowchart'),
        height: 450,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          label: pair.steps
              .map(
                (s) => '${aspectLabel(s.aspect)}: ${decisionLabel(s.decision)}',
              )
              .join('. '),
          child: InteractiveMermaidDiagram(
            code: pairFlowchartCode(pair),
            style: MermaidStyle(
              backgroundColor: Colors.white.toARGB32(),
              defaultNodeStyle: NodeStyle(
                fillColor: AppColors.primarySoft.toARGB32(),
                strokeColor: AppColors.primary.toARGB32(),
                textColor: AppColors.ink.toARGB32(),
                fontSize: 14,
                strokeWidth: 2,
                borderRadius: 10,
              ),
              defaultEdgeStyle: EdgeStyle(
                strokeColor: AppColors.muted.toARGB32(),
                labelColor: AppColors.ink.toARGB32(),
                labelBackgroundColor: Colors.white.toARGB32(),
              ),
              nodeSpacingY: 30,
              nodeSpacingX: 40,
              padding: 24,
            ),
            minScale: .25,
            maxScale: 3,
            onNodeTap: (id) {
              if (id.startsWith('s')) {
                final index = int.tryParse(id.substring(1));
                if (index != null && index < pair.steps.length) onStep(index);
              }
            },
          ),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Geser / zoom alur. Ketuk keputusan untuk melihat alasan dan evidence kedua paper.',
        style: TextStyle(fontSize: 12, color: AppColors.muted),
      ),
    ],
  );
}
