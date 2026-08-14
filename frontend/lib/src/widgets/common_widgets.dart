import 'package:flutter/material.dart';

import '../models/research_models.dart';
import '../theme/app_theme.dart';

class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.compact = false, this.light = false});

  final bool compact;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final color = light ? Colors.white : AppColors.ink;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 34 : 40,
          height: compact ? 34 : 40,
          decoration: BoxDecoration(
            color: light
                ? Colors.white.withValues(alpha: 0.14)
                : AppColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.layers_rounded,
            color: light ? Colors.white : Colors.white,
            size: 22,
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Modellyng',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class PageHeading extends StatelessWidget {
  const PageHeading({
    required this.title,
    required this.subtitle,
    this.action,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          ],
        );
        if (action == null) return copy;
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [copy, const SizedBox(height: 16), action!],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: copy),
            const SizedBox(width: 24),
            action!,
          ],
        );
      },
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    required this.label,
    required this.color,
    required this.background,
    super.key,
  });

  factory StatusBadge.project(ProjectStatus status) {
    return switch (status) {
      ProjectStatus.ready => const StatusBadge(
        label: 'Siap',
        color: AppColors.green,
        background: AppColors.greenSoft,
      ),
      ProjectStatus.processing => const StatusBadge(
        label: 'Diproses',
        color: AppColors.primary,
        background: AppColors.primarySoft,
      ),
      ProjectStatus.needsReview => const StatusBadge(
        label: 'Perlu ditinjau',
        color: AppColors.orange,
        background: AppColors.orangeSoft,
      ),
    };
  }

  factory StatusBadge.paper(PaperStatus status) {
    return switch (status) {
      PaperStatus.validating => const StatusBadge(
        label: 'Dalam antrean',
        color: AppColors.blue,
        background: AppColors.blueSoft,
      ),
      PaperStatus.ready => const StatusBadge(
        label: 'Siap',
        color: AppColors.green,
        background: AppColors.greenSoft,
      ),
      PaperStatus.processing => const StatusBadge(
        label: 'Diproses',
        color: AppColors.primary,
        background: AppColors.primarySoft,
      ),
      PaperStatus.needsReview => const StatusBadge(
        label: 'Perlu ditinjau',
        color: AppColors.orange,
        background: AppColors.orangeSoft,
      ),
      PaperStatus.failed => const StatusBadge(
        label: 'Gagal',
        color: AppColors.red,
        background: AppColors.redSoft,
      ),
    };
  }

  factory StatusBadge.verification(VerificationStatus status) {
    return switch (status) {
      VerificationStatus.verified => const StatusBadge(
        label: 'Terverifikasi',
        color: AppColors.green,
        background: AppColors.greenSoft,
      ),
      VerificationStatus.needsReview => const StatusBadge(
        label: 'Perlu ditinjau',
        color: AppColors.orange,
        background: AppColors.orangeSoft,
      ),
      VerificationStatus.edited => const StatusBadge(
        label: 'Diedit',
        color: AppColors.blue,
        background: Color(0xFFEAF2FF),
      ),
      VerificationStatus.unsupported => const StatusBadge(
        label: 'Tanpa dukungan',
        color: AppColors.red,
        background: AppColors.redSoft,
      ),
      VerificationStatus.rejected => const StatusBadge(
        label: 'Ditolak',
        color: AppColors.red,
        background: AppColors.redSoft,
      ),
    };
  }

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.note,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? note;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(value, style: Theme.of(context).textTheme.headlineSmall),
                  if (note != null)
                    Text(
                      note!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.green,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}
