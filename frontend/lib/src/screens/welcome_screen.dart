import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({required this.onGetStarted, super.key});

  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 920;
            return Stack(
              children: [
                Positioned(
                  right: -140,
                  top: -180,
                  child: Container(
                    width: 470,
                    height: 470,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0x325147E5), Color(0x005147E5)],
                      ),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 64 : 24,
                    vertical: wide ? 36 : 24,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - (wide ? 72 : 48),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const BrandLockup(),
                        SizedBox(height: wide ? 60 : 44),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: _HeroCopy(onGetStarted: onGetStarted),
                              ),
                              const SizedBox(width: 72),
                              const Expanded(child: _ProductPreview()),
                            ],
                          )
                        else ...[
                          _HeroCopy(onGetStarted: onGetStarted),
                          const SizedBox(height: 42),
                          const _ProductPreview(),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'AI-POWERED ACADEMIC KNOWLEDGE MODELING',
            style: TextStyle(
              color: AppColors.primaryDark,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Ubah paper menjadi\npengetahuan yang\ndapat diverifikasi.',
          style: Theme.of(
            context,
          ).textTheme.displaySmall?.copyWith(fontSize: 46),
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Text(
            'Ekstrak struktur penelitian, bandingkan banyak paper, dan temukan kandidat research gap dengan evidence yang selalu dapat ditelusuri ke sumber asli.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              key: const Key('get-started-button'),
              onPressed: onGetStarted,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Mulai menggunakan Modellyng'),
            ),
            OutlinedButton.icon(
              onPressed: () => _showPrinciples(context),
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Lihat prinsip verifikasi'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const Wrap(
          spacing: 22,
          runSpacing: 10,
          children: [
            _TrustItem(icon: Icons.link_rounded, label: 'Source traceability'),
            _TrustItem(
              icon: Icons.fact_check_outlined,
              label: 'Human-in-the-loop',
            ),
            _TrustItem(
              icon: Icons.lock_outline_rounded,
              label: 'Private workspace',
            ),
          ],
        ),
      ],
    );
  }

  void _showPrinciples(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI membantu, manusia memutuskan',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 12),
            Text(
              'Setiap hasil AI menyertakan kutipan evidence, lokasi sumber, dan status verifikasi. Pengguna dapat menerima, mengedit, menolak, atau meminta analisis ulang.',
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppColors.green),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _ProductPreview extends StatelessWidget {
  const _ProductPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 570),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF0EFFF),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x185147E5),
            blurRadius: 42,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.description_outlined, color: AppColors.primary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Urban Climate Resilience',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                StatusBadge(
                  label: 'AI selesai',
                  color: AppColors.green,
                  background: AppColors.greenSoft,
                ),
              ],
            ),
            const SizedBox(height: 18),
            const _PreviewComponent(
              color: AppColors.blue,
              icon: Icons.help_outline_rounded,
              title: 'Research Problem',
              text:
                  'Strategi adaptasi infrastruktur kota masih dinilai secara terpisah.',
              location: 'Hal. 2 · Introduction',
            ),
            const SizedBox(height: 10),
            const _PreviewComponent(
              color: AppColors.green,
              icon: Icons.science_outlined,
              title: 'Methodology',
              text: 'Systematic review menggunakan kerangka PRISMA.',
              location: 'Hal. 4 · Methodology',
            ),
            const SizedBox(height: 10),
            const _PreviewComponent(
              color: AppColors.orange,
              icon: Icons.lightbulb_outline_rounded,
              title: 'Candidate Gap',
              text: 'Kurangnya studi longitudinal pada kota lapis kedua.',
              location: 'Didukung 7 paper',
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewComponent extends StatelessWidget {
  const _PreviewComponent({
    required this.color,
    required this.icon,
    required this.title,
    required this.text,
    required this.location,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String text;
  final String location;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(text, style: const TextStyle(fontSize: 13, height: 1.35)),
                const SizedBox(height: 7),
                Text(
                  location,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
