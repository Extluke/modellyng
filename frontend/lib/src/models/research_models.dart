import 'package:flutter/material.dart';

enum ProjectStatus { ready, processing, needsReview }

enum PaperStatus { ready, processing, needsReview, failed }

enum VerificationStatus { verified, needsReview, edited, unsupported, rejected }

class ResearchProject {
  const ResearchProject({
    required this.id,
    required this.title,
    required this.description,
    required this.paperCount,
    required this.progress,
    required this.status,
    required this.updatedLabel,
    required this.accent,
  });

  final String id;
  final String title;
  final String description;
  final int paperCount;
  final double progress;
  final ProjectStatus status;
  final String updatedLabel;
  final Color accent;
}

class PaperRecord {
  const PaperRecord({
    required this.id,
    required this.title,
    required this.authors,
    required this.year,
    required this.journal,
    required this.doi,
    required this.status,
    required this.progress,
  });

  final String id;
  final String title;
  final String authors;
  final int year;
  final String journal;
  final String doi;
  final PaperStatus status;
  final double progress;
}

class ExtractedComponent {
  const ExtractedComponent({
    required this.label,
    required this.value,
    required this.evidence,
    required this.location,
    required this.status,
  });

  final String label;
  final String value;
  final String evidence;
  final String location;
  final VerificationStatus status;
}

class ResearchGap {
  const ResearchGap({
    required this.title,
    required this.description,
    required this.supportingPapers,
    required this.confidence,
    required this.type,
  });

  final String title;
  final String description;
  final int supportingPapers;
  final double confidence;
  final String type;
}
