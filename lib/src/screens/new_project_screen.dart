import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class NewProjectScreen extends StatefulWidget {
  const NewProjectScreen({super.key});

  @override
  State<NewProjectScreen> createState() => _NewProjectScreenState();
}

class _NewProjectScreenState extends State<NewProjectScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _doiController = TextEditingController();
  final Set<String> _parameters = {
    'Research Problem',
    'Research Objective',
    'Methodology',
    'Results / Findings',
    'Limitations',
  };
  int _step = 0;
  bool _fileAdded = false;

  static const _stepLabels = [
    'Informasi',
    'Tambahkan paper',
    'Parameter',
    'Konfirmasi',
  ];
  static const _availableParameters = [
    'Research Problem',
    'Research Objective',
    'Research Question',
    'Methodology',
    'Dataset / Sample',
    'Variables / Concepts',
    'Results / Findings',
    'Contribution',
    'Limitations',
    'Future Work',
    'Key Claims',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _doiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const BrandLockup(),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Buat proyek baru',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Siapkan workspace dan tentukan bagaimana paper akan dianalisis.',
                      ),
                      const SizedBox(height: 28),
                      _StepIndicator(currentStep: _step, labels: _stepLabels),
                      const SizedBox(height: 28),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: KeyedSubtree(
                          key: ValueKey(_step),
                          child: _buildStep(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Row(
                    children: [
                      if (_step > 0)
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _step--),
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text('Kembali'),
                        )
                      else
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Batal'),
                        ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _canContinue ? _continue : null,
                        icon: Icon(
                          _step == 3
                              ? Icons.rocket_launch_outlined
                              : Icons.arrow_forward_rounded,
                        ),
                        label: Text(
                          _step == 3 ? 'Buat & mulai analisis' : 'Lanjutkan',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _canContinue {
    return switch (_step) {
      0 => _titleController.text.trim().isNotEmpty,
      1 => _fileAdded || _doiController.text.trim().isNotEmpty,
      2 => _parameters.isNotEmpty,
      _ => true,
    };
  }

  void _continue() {
    if (_step < 3) {
      setState(() => _step++);
      return;
    }
    Navigator.pop(context, true);
  }

  Widget _buildStep(BuildContext context) {
    return switch (_step) {
      0 => _ProjectInformationStep(
        titleController: _titleController,
        descriptionController: _descriptionController,
        onChanged: () => setState(() {}),
      ),
      1 => _AddPapersStep(
        doiController: _doiController,
        fileAdded: _fileAdded,
        onFileAdded: () => setState(() => _fileAdded = true),
        onChanged: () => setState(() {}),
      ),
      2 => _ParameterStep(
        parameters: _availableParameters,
        selected: _parameters,
        onToggle: (parameter, selected) => setState(() {
          if (selected) {
            _parameters.add(parameter);
          } else {
            _parameters.remove(parameter);
          }
        }),
      ),
      _ => _ConfirmationStep(
        title: _titleController.text.trim(),
        fileAdded: _fileAdded,
        doi: _doiController.text.trim(),
        parameterCount: _parameters.length,
      ),
    };
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.currentStep, required this.labels});

  final int currentStep;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 540;
        return Row(
          children: [
            for (var index = 0; index < labels.length; index++) ...[
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (index > 0)
                          Expanded(
                            child: Container(
                              height: 2,
                              color: index <= currentStep
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                          ),
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: index <= currentStep
                                ? AppColors.primary
                                : Colors.white,
                            border: Border.all(
                              color: index <= currentStep
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                          ),
                          child: Center(
                            child: index < currentStep
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 17,
                                  )
                                : Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: index == currentStep
                                          ? Colors.white
                                          : AppColors.muted,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                          ),
                        ),
                        if (index < labels.length - 1)
                          Expanded(
                            child: Container(
                              height: 2,
                              color: index < currentStep
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                          ),
                      ],
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 7),
                      Text(
                        labels[index],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: index == currentStep
                              ? AppColors.ink
                              : AppColors.muted,
                          fontWeight: index == currentStep
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ProjectInformationStep extends StatelessWidget {
  const _ProjectInformationStep({
    required this.titleController,
    required this.descriptionController,
    required this.onChanged,
  });

  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Informasi proyek',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 5),
            const Text(
              'Gunakan nama yang mudah dikenali saat jumlah proyek bertambah.',
            ),
            const SizedBox(height: 22),
            const Text(
              'Nama proyek',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('project-title-field'),
              controller: titleController,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                hintText: 'Contoh: Literature Review Smart City 2026',
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Deskripsi (opsional)',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Jelaskan fokus dan tujuan riset Anda...',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPapersStep extends StatelessWidget {
  const _AddPapersStep({
    required this.doiController,
    required this.fileAdded,
    required this.onFileAdded,
    required this.onChanged,
  });

  final TextEditingController doiController;
  final bool fileAdded;
  final VoidCallback onFileAdded;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unggah paper',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 5),
                const Text(
                  'PDF dengan text layer memberikan hasil dan lokasi evidence terbaik.',
                ),
                const SizedBox(height: 18),
                InkWell(
                  onTap: onFileAdded,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 34,
                    ),
                    decoration: BoxDecoration(
                      color: fileAdded
                          ? AppColors.greenSoft
                          : const Color(0xFFFAFAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: fileAdded ? AppColors.green : AppColors.border,
                        width: 1.4,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          fileAdded
                              ? Icons.task_alt_rounded
                              : Icons.cloud_upload_outlined,
                          size: 42,
                          color: fileAdded
                              ? AppColors.green
                              : AppColors.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          fileAdded
                              ? 'urban-climate-resilience.pdf'
                              : 'Klik untuk memilih PDF atau DOCX',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          fileAdded
                              ? '12,4 MB · siap divalidasi'
                              : 'Maksimal 50 MB per file',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Atau tambahkan DOI',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: doiController,
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.link_rounded),
                    hintText: '10.xxxx/xxxxx',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'DOI digunakan untuk validasi metadata. Full text tetap memerlukan file atau akses sumber yang sah.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ParameterStep extends StatelessWidget {
  const _ParameterStep({
    required this.parameters,
    required this.selected,
    required this.onToggle,
  });

  final List<String> parameters;
  final Set<String> selected;
  final void Function(String parameter, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Parameter ekstraksi',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  '${selected.length} dipilih',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            const Text(
              'Semakin banyak parameter, semakin besar waktu dan processing credits yang diperlukan.',
            ),
            const SizedBox(height: 18),
            for (final parameter in parameters)
              CheckboxListTile(
                value: selected.contains(parameter),
                onChanged: (value) => onToggle(parameter, value ?? false),
                title: Text(
                  parameter,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmationStep extends StatelessWidget {
  const _ConfirmationStep({
    required this.title,
    required this.fileAdded,
    required this.doi,
    required this.parameterCount,
  });

  final String title;
  final bool fileAdded;
  final String doi;
  final int parameterCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.rocket_launch_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  'Siap memulai analisis',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SummaryRow(
              icon: Icons.folder_outlined,
              label: 'Proyek',
              value: title,
            ),
            const Divider(height: 28),
            _SummaryRow(
              icon: Icons.description_outlined,
              label: 'Sumber',
              value: fileAdded
                  ? '1 file siap divalidasi${doi.isNotEmpty ? ' + 1 DOI' : ''}'
                  : 'DOI: $doi',
            ),
            const Divider(height: 28),
            _SummaryRow(
              icon: Icons.tune_rounded,
              label: 'Ekstraksi',
              value: '$parameterCount parameter + source traceability',
            ),
            const Divider(height: 28),
            const _SummaryRow(
              icon: Icons.schedule_rounded,
              label: 'Estimasi demo',
              value: '2–4 menit untuk paper 12 halaman',
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.primary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Analisis berjalan di background. Anda boleh menutup halaman dan kembali melalui dashboard.',
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

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 12),
        SizedBox(
          width: 90,
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
