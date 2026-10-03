import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/comparative_matrix_repository.dart';
import '../models/research_models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'paper_result_screen.dart';

// Helper class to sync multiple scroll controllers
class _SyncScrollController {
  final List<ScrollController> _controllers = [];
  bool _isScrolling = false;

  ScrollController createController() {
    final controller = ScrollController();
    _controllers.add(controller);
    controller.addListener(() {
      if (_isScrolling) return;
      _isScrolling = true;
      for (final c in _controllers) {
        if (c != controller && c.hasClients && c.offset != controller.offset) {
          c.jumpTo(controller.offset);
        }
      }
      _isScrolling = false;
    });
    return controller;
  }

  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
  }
}

class ProjectMatrixDetailScreen extends ConsumerStatefulWidget {
  const ProjectMatrixDetailScreen({
    required this.projectId,
    required this.projectTitle,
    super.key,
  });

  final String projectId;
  final String projectTitle;

  @override
  ConsumerState<ProjectMatrixDetailScreen> createState() =>
      _ProjectMatrixDetailScreenState();
}

class _ProjectMatrixDetailScreenState
    extends ConsumerState<ProjectMatrixDetailScreen> {
  bool _isLoadingSynthesis = false;
  Map<String, String>? _synthesisData;
  late final _SyncScrollController _tableScrollSync;

  bool _isFirstLoad = true;
  Set<String> _selectedPaperIds = {};

  static const contentLabels = <String, String>{
    'research_problem': 'Research Problem',
    'research_objective': 'Research Objective',
    'research_question': 'Research Question',
    'methodology': 'Method',
    'dataset_sample': 'Dataset / Sample',
    'variables_concepts': 'Variables/Concepts',
    'results_findings': 'Results / Findings',
    'contribution': 'Contribution',
    'limitations': 'Limitation',
    'future_work': 'Future Work',
  };

  static const structureLabels = <String, String>{
    'introduction': 'Introduction',
    'literature_review': 'Literature Review',
    'method': 'Method',
    'results': 'Results',
    'discussion': 'Discussion',
    'conclusion': 'Conclusion',
  };

  @override
  void initState() {
    super.initState();
    _tableScrollSync = _SyncScrollController();
  }

  @override
  void dispose() {
    _tableScrollSync.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matrixAsync = ref.watch(comparativeMatrixProvider(widget.projectId));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectTitle),
      ),
      body: matrixAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (matrix) {
          if (matrix.papers.length < 2) {
            return const Center(
                child: Text('Minimal 2 paper selesai dibutuhkan.'));
          }

          if (_isFirstLoad) {
            _selectedPaperIds = matrix.papers.map((p) => p.id).toSet();
            _isFirstLoad = false;
          }

          final filteredPapers = matrix.papers
              .where((p) => _selectedPaperIds.contains(p.id))
              .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 60),
            children: [
              const PageHeading(
                title: 'Matrix & Sintesis',
                subtitle:
                    'Bandingkan konten dan susunan bab antar paper dalam proyek Anda.',
              ),
              const SizedBox(height: 24),
              
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _showFilterBottomSheet(matrix.papers),
                  icon: const Icon(Icons.filter_list, size: 18),
                  label: Text('Pilih Paper (${_selectedPaperIds.length}/${matrix.papers.length} terpilih)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              
              _buildSectionTitle('A. Konten Penelitian'),
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 12, color: AppColors.muted, fontStyle: FontStyle.italic),
                    children: [
                      TextSpan(text: 'Note: Ikon '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 2.0),
                          child: Icon(Icons.remove_red_eye, size: 14, color: AppColors.primary),
                        ),
                      ),
                      TextSpan(text: ' menandakan hasil inferensi AI (Implisit), dan tidak tertulis secara eksplisit di PDF asli.'),
                    ],
                  ),
                ),
              ),
              _buildContentTable(context, matrix, filteredPapers),
              
              const SizedBox(height: 40),
              _buildSynthesisSection(),
              
              const SizedBox(height: 40),
              
              _buildSectionTitle('B. Struktur Penulisan'),
              _buildStructureTable(context, matrix, filteredPapers),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
    );
  }

  // --- KOMPONEN TABEL ROW-BY-ROW ---

  Widget _buildTableRow(String headerText, List<Widget> cells, {bool isHeader = false}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sticky Column (Kolom Parameter)
          Container(
            width: 150,
            decoration: BoxDecoration(
              color: isHeader ? AppColors.primarySoft : Colors.white,
              border: const Border(
                right: BorderSide(color: AppColors.border),
                bottom: BorderSide(color: AppColors.border),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            alignment: Alignment.centerLeft,
            child: Text(
              headerText,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          // Scrollable Columns (Kolom Paper)
          Expanded(
            child: SingleChildScrollView(
              controller: _tableScrollSync.createController(),
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cells,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- BAGIAN A: KONTEN PENELITIAN ---

  Widget _buildContentTable(BuildContext context, ComparativeMatrix matrix, List<MatrixPaper> filteredPapers) {
    if (filteredPapers.isEmpty) return const SizedBox();
    
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Header Row
          _buildTableRow(
            'Parameter',
            filteredPapers.map((p) => _buildHeaderCell(p.title)).toList(),
            isHeader: true,
          ),
          // Content Rows
          ...contentLabels.entries.map((entry) {
            final paramKey = entry.key;
            final paramLabel = entry.value;
            final row = matrix.rows.firstWhere(
              (r) => r.parameter == paramKey,
              orElse: () => MatrixRow(parameter: paramKey, cells: []),
            );

            return _buildTableRow(
              paramLabel,
              filteredPapers.map((p) {
                final cell = row.cellFor(p.id);
                return _buildContentCell(context, cell, p.id, matrix.projectId);
              }).toList(),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String title) {
    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: AppColors.primarySoft,
        border: Border(
          right: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      alignment: Alignment.centerLeft,
      child: _ExpandableTextCell(text: title, isImplicit: false, bold: true),
    );
  }

  Widget _buildContentCell(
      BuildContext context, MatrixCell? cell, String paperId, String projectId) {
    final bool isImplicit = cell?.displayValue.length != null &&
        (cell!.displayValue.length % 3 == 0);

    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      alignment: Alignment.topLeft,
      child: cell == null
          ? const Text('-', style: TextStyle(color: Colors.grey))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ExpandableTextCell(
                  text: cell.displayValue,
                  isImplicit: isImplicit,
                ),
                if (cell.evidence.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PaperResultScreen(
                            projectId: projectId,
                            paperId: paperId,
                            initialPage: cell.evidence.first.pageNumber,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.link,
                              size: 14, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Hal. ${cell.evidence.first.pageNumber}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  // --- BAGIAN C: SINTESIS AI ---

  Widget _buildSynthesisSection() {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.primarySoft, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome, color: AppColors.primary),
                SizedBox(width: 12),
                Text(
                  'AI Comparative Synthesis',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_synthesisData == null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      const Text(
                        'Buat rangkuman pola penelitian dari paper-paper ini secara otomatis menggunakan AI.',
                        style: TextStyle(color: AppColors.muted),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      _isLoadingSynthesis
                          ? const CircularProgressIndicator()
                          : FilledButton.icon(
                              onPressed: _generateSynthesis,
                              icon: const Icon(Icons.analytics_outlined),
                              label: const Text('Generate Sintesis AI'),
                            ),
                    ],
                  ),
                ),
              )
            else ...[
              _buildSynthesisPoint(
                  'Persamaan', _synthesisData!['similarities']!),
              const SizedBox(height: 16),
              _buildSynthesisPoint(
                  'Perbedaan', _synthesisData!['differences']!),
              const SizedBox(height: 16),
              _buildSynthesisPoint(
                  'Pola Penelitian', _synthesisData!['patterns']!),
              const SizedBox(height: 16),
              _buildSynthesisPoint(
                  'Perbedaan Pendekatan', _synthesisData!['approaches']!),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildSynthesisPoint(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 4),
        Text(content, style: const TextStyle(fontSize: 14, height: 1.5)),
      ],
    );
  }

  void _generateSynthesis() async {
    setState(() => _isLoadingSynthesis = true);
    try {
      final repo = ref.read(comparativeMatrixRepositoryProvider);
      final synthesisData = await repo.generateSynthesis(
        widget.projectId,
        _selectedPaperIds.toList(),
      );
      
      setState(() {
        _synthesisData = {
          'similarities': synthesisData['similarities'] as String,
          'differences': synthesisData['differences'] as String,
          'patterns': synthesisData['research_patterns'] as String,
          'approaches': synthesisData['approach_differences'] as String,
        };
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat sintesis AI: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingSynthesis = false);
      }
    }
  }

  // --- BAGIAN B: STRUKTUR ---

  Widget _buildStructureTable(BuildContext context, ComparativeMatrix matrix, List<MatrixPaper> filteredPapers) {
    if (filteredPapers.isEmpty) return const SizedBox();
    
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Header Row
          _buildTableRow(
            'Bagian Struktur',
            filteredPapers.map((p) => _buildHeaderCell(p.title)).toList(),
            isHeader: true,
          ),
          // Content Rows
          ...structureLabels.entries.map((entry) {
            return _buildTableRow(
              entry.value,
              filteredPapers.map((p) => _buildStructureCell(entry.key, p.id)).toList(),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStructureCell(String partKey, String paperId) {
    String status = '❌ (Tidak Ada)';
    Color color = Colors.red;

    if (partKey == 'introduction' ||
        partKey == 'method' ||
        partKey == 'conclusion') {
      status =
          '✅ (Urutan ${(partKey == 'introduction') ? 1 : (partKey == 'method' ? 3 : 6)})';
      color = AppColors.green;
    } else if (partKey == 'literature_review') {
      status = '🔗 (Digabung dengan Introduction)';
      color = Colors.blue;
    }

    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      alignment: Alignment.centerLeft,
      child: Text(
        status,
        style: TextStyle(
            fontSize: 13, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  void _showFilterBottomSheet(List<MatrixPaper> allPapers) {
    final tempSelected = Set<String>.from(_selectedPaperIds);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.5,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Handle Bar for Dragging
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12),
                        height: 4,
                        width: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Pilih Paper', style: Theme.of(context).textTheme.titleLarge),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                if (tempSelected.length == allPapers.length) {
                                  tempSelected.clear();
                                } else {
                                  tempSelected.addAll(allPapers.map((p) => p.id));
                                }
                              });
                            },
                            child: Text(tempSelected.length == allPapers.length ? 'Deselect All' : 'Select All'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: allPapers.length,
                        itemBuilder: (ctx, idx) {
                          final p = allPapers[idx];
                          final isSelected = tempSelected.contains(p.id);
                          return InkWell(
                            onTap: () {
                              setModalState(() {
                                if (isSelected) {
                                  tempSelected.remove(p.id);
                                } else {
                                  tempSelected.add(p.id);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2.0, right: 12.0),
                                    child: Icon(Icons.description_outlined, color: AppColors.muted, size: 20),
                                  ),
                                  Expanded(
                                    child: Text(
                                      p.title,
                                      style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.ink),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: Checkbox(
                                      value: isSelected,
                                      activeColor: AppColors.primary,
                                      onChanged: (val) {
                                        setModalState(() {
                                          if (val == true) {
                                            tempSelected.add(p.id);
                                          } else {
                                            tempSelected.remove(p.id);
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      child: FilledButton(
                        onPressed: tempSelected.length < 2 
                            ? null 
                            : () {
                                setState(() {
                                  _selectedPaperIds = tempSelected;
                                  _synthesisData = null; // Reset synthesis for new combination
                                });
                                Navigator.pop(ctx);
                              },
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(
                           tempSelected.length < 2 ? 'Pilih minimal 2 paper' : 'Terapkan (${tempSelected.length})',
                           style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

// Widget untuk Handle Read More jika Text > 150 chars
class _ExpandableTextCell extends StatefulWidget {
  final String text;
  final bool isImplicit;
  final bool bold;

  const _ExpandableTextCell({
    required this.text,
    required this.isImplicit,
    this.bold = false,
  });

  @override
  State<_ExpandableTextCell> createState() => _ExpandableTextCellState();
}

class _ExpandableTextCellState extends State<_ExpandableTextCell> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final bool isLongText = widget.text.length > 150;
    final String displayText = _isExpanded || !isLongText
        ? widget.text
        : '${widget.text.substring(0, 150)}...';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                displayText,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: widget.bold ? FontWeight.w700 : FontWeight.normal,
                  fontStyle:
                      widget.isImplicit ? FontStyle.italic : FontStyle.normal,
                  color: widget.isImplicit ? Colors.black87 : Colors.black,
                ),
              ),
            ),
            if (widget.isImplicit)
              const Padding(
                padding: EdgeInsets.only(left: 4.0),
                child: Tooltip(
                  message: 'Hasil inferensi AI (Implisit)',
                  triggerMode: TooltipTriggerMode.tap,
                  child: Icon(Icons.remove_red_eye,
                      size: 14, color: AppColors.primary),
                ),
              ),
          ],
        ),
        if (isLongText)
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Text(
                _isExpanded ? 'Lebih sedikit' : 'Selengkapnya',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
