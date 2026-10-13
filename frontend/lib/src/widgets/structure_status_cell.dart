import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../data/comparative_matrix_repository.dart';
import '../theme/app_theme.dart';

/// Status satu bagian struktur penulisan untuk satu paper.
enum StructureStatus { present, merged, absent }

/// Menentukan status bagian struktur [partKey] untuk paper [paperId].
///
/// Aturannya sama persis dengan tampilan lama (emoji + teks); hanya
/// presentasinya yang berubah menjadi ikon.
StructureStatus structureStatusFor(
  ComparativeMatrix matrix,
  String partKey,
  String paperId,
) {
  bool hasContent(String param) {
    for (final row in matrix.rows) {
      if (row.parameter != param) continue;
      final value = row.cellFor(paperId)?.displayValue.trim();
      return value != null && value.isNotEmpty && value != '-';
    }
    return false;
  }

  switch (partKey) {
    case 'introduction':
      final hasIntro = hasContent('research_problem') ||
          hasContent('research_objective') ||
          hasContent('research_question');
      return hasIntro ? StructureStatus.present : StructureStatus.absent;
    case 'literature_review':
      return StructureStatus.merged;
    case 'method':
      final hasMethod =
          hasContent('methodology') || hasContent('dataset_sample');
      return hasMethod ? StructureStatus.present : StructureStatus.absent;
    case 'results':
      return hasContent('results_findings')
          ? StructureStatus.present
          : StructureStatus.absent;
    case 'discussion':
      final merged = hasContent('results_findings') &&
          (hasContent('limitations') || hasContent('future_work'));
      return merged ? StructureStatus.merged : StructureStatus.absent;
    case 'conclusion':
      final hasConclusion = hasContent('contribution') ||
          hasContent('limitations') ||
          hasContent('future_work');
      return hasConclusion ? StructureStatus.present : StructureStatus.absent;
  }
  return StructureStatus.absent;
}

/// Ikon RemixIcon untuk satu [StructureStatus], dengan label pembaca layar.
class StructureStatusIcon extends StatelessWidget {
  const StructureStatusIcon({super.key, required this.status});

  final StructureStatus status;

  static const double size = 20;

  static IconData iconFor(StructureStatus status) => switch (status) {
        StructureStatus.present => RemixIcons.check_line,
        StructureStatus.merged => RemixIcons.link,
        StructureStatus.absent => RemixIcons.close_line,
      };

  static Color colorFor(StructureStatus status) => switch (status) {
        StructureStatus.present => AppColors.green,
        StructureStatus.merged => Colors.blue,
        StructureStatus.absent => Colors.red,
      };

  static String labelFor(StructureStatus status) => switch (status) {
        StructureStatus.present => 'Ada',
        StructureStatus.merged => 'Digabung',
        StructureStatus.absent => 'Tidak ada',
      };

  @override
  Widget build(BuildContext context) {
    return Icon(
      iconFor(status),
      size: size,
      color: colorFor(status),
      semanticLabel: labelFor(status),
    );
  }
}
