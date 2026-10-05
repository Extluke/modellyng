import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/research_gap_repository.dart';
import '../models/research_models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class SynthesisScreen extends ConsumerStatefulWidget {
  const SynthesisScreen({required this.projectId, super.key});
  final String projectId;

  @override
  ConsumerState<SynthesisScreen> createState() => _SynthesisScreenState();
}

class _SynthesisScreenState extends ConsumerState<SynthesisScreen> {
  bool _loading = false;
  String? _error;
  AiResearchSynthesis? _synthesis;

  @override
  void initState() {
    super.initState();
    _synthesize();
  }

  Future<void> _synthesize() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = ref.read(researchGapRepositoryProvider);
      final result = await repo.synthesizeGaps(widget.projectId);
      if (mounted) {
        setState(() {
          _synthesis = result;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Gagal melakukan sintesis riset: ${e.toString()}';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Research Formulation Synthesizer'),
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('AI sedang merumuskan penelitian...'),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: AppColors.red),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _synthesize,
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : _synthesis != null
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const PageHeading(
                          title: 'Hasil Sintesis Riset',
                          subtitle:
                              'Rekomendasi judul dan rumusan masalah berdasarkan celah penelitian yang Anda pilih.',
                        ),
                        const SizedBox(height: 24),
                        
                        _SectionTitle('Pernyataan Novelty'),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_synthesis!.pernyataanNovelty),
                          ),
                        ),
                        const SizedBox(height: 24),

                        _SectionTitle('Usulan Judul Penelitian'),
                        ..._synthesis!.usulanJudul.map((judul) => Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_circle_outline, color: Colors.green),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        judul,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )),
                        const SizedBox(height: 24),

                        _SectionTitle('Rumusan Masalah (Research Questions)'),
                        ..._synthesis!.rumusanMasalah.map((rq) => Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    const Icon(Icons.help_outline, color: Colors.blue),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(rq),
                                    ),
                                  ],
                                ),
                              ),
                            )),
                        const SizedBox(height: 24),
                        
                        _SectionTitle('Alasan Pemilihan'),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_synthesis!.alasanPemilihan),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    )
                  : const SizedBox(),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
