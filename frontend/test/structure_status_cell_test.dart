import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/data/comparative_matrix_repository.dart';
import 'package:modellyng/src/models/research_models.dart';
import 'package:modellyng/src/theme/app_theme.dart';
import 'package:modellyng/src/widgets/structure_status_cell.dart';
import 'package:remixicon/remixicon.dart';

const _params = [
  'research_problem',
  'research_objective',
  'research_question',
  'methodology',
  'dataset_sample',
  'results_findings',
  'limitations',
  'future_work',
  'contribution',
];

const _parts = [
  'introduction',
  'literature_review',
  'method',
  'results',
  'discussion',
  'conclusion',
];

MatrixCell _cell(String paperId, String value) => MatrixCell(
      paperId: paperId,
      aiValue: value,
      finalValue: null,
      status: VerificationStatus.needsReview,
      confidence: null,
      evidence: const [],
    );

ComparativeMatrix _matrix(Map<String, String> values, {String paperId = 'p1'}) =>
    ComparativeMatrix(
      projectId: 'project',
      projectTitle: 'Proyek',
      papers: [MatrixPaper(id: paperId, title: 'Paper', originalFilename: 'p.pdf')],
      rows: [
        for (final entry in values.entries)
          MatrixRow(parameter: entry.key, cells: [_cell(paperId, entry.value)]),
      ],
    );

/// Oracle independen yang menyalin aturan lama emoji + teks.
StructureStatus _expected(String part, Set<String> has) {
  bool any(List<String> keys) => keys.any(has.contains);
  return switch (part) {
    'introduction' =>
      any(['research_problem', 'research_objective', 'research_question'])
          ? StructureStatus.present
          : StructureStatus.absent,
    'literature_review' => StructureStatus.merged,
    'method' => any(['methodology', 'dataset_sample'])
        ? StructureStatus.present
        : StructureStatus.absent,
    'results' => has.contains('results_findings')
        ? StructureStatus.present
        : StructureStatus.absent,
    'discussion' => has.contains('results_findings') &&
            any(['limitations', 'future_work'])
        ? StructureStatus.merged
        : StructureStatus.absent,
    'conclusion' => any(['contribution', 'limitations', 'future_work'])
        ? StructureStatus.present
        : StructureStatus.absent,
    _ => StructureStatus.absent,
  };
}

void main() {
  test('status sama dengan aturan lama untuk seluruh 512 kombinasi', () {
    for (var mask = 0; mask < 1 << _params.length; mask++) {
      final has = {
        for (var i = 0; i < _params.length; i++)
          if (mask & (1 << i) != 0) _params[i],
      };
      final matrix = _matrix({
        for (final p in _params) p: has.contains(p) ? 'isi' : '',
      });
      for (final part in _parts) {
        expect(
          structureStatusFor(matrix, part, 'p1'),
          _expected(part, has),
          reason: 'part=$part has=$has',
        );
      }
    }
  });

  test('kosong, spasi, "-", baris atau sel hilang dianggap tidak ada konten',
      () {
    for (final value in ['', '   ', '-', '  -  ']) {
      expect(
        structureStatusFor(_matrix({'results_findings': value}), 'results', 'p1'),
        StructureStatus.absent,
      );
    }
    expect(
      structureStatusFor(_matrix({}), 'results', 'p1'),
      StructureStatus.absent,
    );
    expect(
      structureStatusFor(
          _matrix({'results_findings': 'isi'}, paperId: 'other'),
          'results',
          'p1'),
      StructureStatus.absent,
    );
  });

  final cases = {
    StructureStatus.present: (RemixIcons.check_line, AppColors.green, 'Ada'),
    StructureStatus.merged: (RemixIcons.link, Colors.blue, 'Digabung'),
    StructureStatus.absent: (RemixIcons.close_line, Colors.red, 'Tidak ada'),
  };

  for (final MapEntry(key: status, value: (icon, color, label))
      in cases.entries) {
    testWidgets('ikon $status: RemixIcon, warna, ukuran, label, tanpa teks',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StructureStatusIcon(status: status)),
      ));

      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      expect(icons, hasLength(1));
      expect(icons.single.icon, icon);
      expect(icons.single.icon!.fontPackage, 'remixicon');
      expect(icons.single.color, color);
      expect(icons.single.size, 20);
      expect(find.bySemanticsLabel(label), findsOneWidget);
      expect(find.byType(Text), findsNothing);
      for (final legacy in ['✅', '❌', '🔗', 'Urutan', 'Tidak Ada', 'Digabung dengan']) {
        expect(find.textContaining(legacy), findsNothing);
      }
      semantics.dispose();
    });
  }
}
