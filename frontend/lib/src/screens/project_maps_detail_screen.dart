import 'dart:math';

import 'package:flutter/material.dart';

import '../data/maps_mock_data.dart';
import '../theme/app_theme.dart';
import 'package:graphview/GraphView.dart';

class ProjectMapsDetailScreen extends StatefulWidget {
  const ProjectMapsDetailScreen({
    required this.projectId,
    required this.projectTitle,
    required this.userId,
    super.key,
  });

  final String projectId;
  final String projectTitle;
  final String userId;

  @override
  State<ProjectMapsDetailScreen> createState() => _ProjectMapsDetailScreenState();
}

class _ProjectMapsDetailScreenState extends State<ProjectMapsDetailScreen> {
  int _selectedMap = 0; // 0 for Concept Map, 1 for Gap Map
  final TransformationController _transformController = TransformationController();
  
  final Map<String, Offset> _nodePositions = {};
  List<GraphNode> _visibleNodes = [];
  List<GraphEdge> _visibleEdges = [];
  
  final TextEditingController _searchController = TextEditingController();

  // Filter state
  final Set<GraphNodeType> _visibleNodeTypes = {
    GraphNodeType.concept,
    GraphNodeType.researchGap,
    GraphNodeType.paper,
    GraphNodeType.variable,
    GraphNodeType.method,
    GraphNodeType.object,
    GraphNodeType.researchArea,
    GraphNodeType.result,
  };

  @override
  void initState() {
    super.initState();
    _generateLayout();
    _updateVisibleGraph();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerView();
    });
  }
  
  void _centerView() {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    const double scale = 0.5;
    // Center at node c1 roughly (1150, 900)
    final dx = (size.width / 2) - (1150 * scale);
    final dy = (size.height / 2) - (900 * scale);
    
    final centerMatrix = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);
    _transformController.value = centerMatrix;
  }

  Graph _buildGraphViewGraph() {
    final graph = Graph()..isTree = false;
    final Map<String, Node> gvNodes = {};
    for (final n in _visibleNodes) {
      final node = Node.Id(n);
      gvNodes[n.id] = node;
      graph.addNode(node);
    }
    for (final e in _visibleEdges) {
      if (gvNodes.containsKey(e.sourceId) && gvNodes.containsKey(e.targetId)) {
        graph.addEdge(gvNodes[e.sourceId]!, gvNodes[e.targetId]!, paint: Paint()..color = Colors.indigo.shade200..strokeWidth = 1.5..style = PaintingStyle.stroke);
      }
    }
    return graph;
  }

  void _generateLayout() {
    // Hardcoded layout to perfectly match the wireframe
    final manualOffsets = {
      'pA': const Offset(800, 600),
      'pB': const Offset(1500, 600),
      'ra1': const Offset(800, 750),
      'c1': const Offset(1150, 900),
      'c2': const Offset(1500, 900),
      'v1': const Offset(800, 1050),
      'v2': const Offset(1500, 1050),
      'm1': const Offset(800, 1200),
      'o1': const Offset(1500, 1200),
      'res1': const Offset(1150, 1350),
      'g1': const Offset(1500, 1500),
      'pC': const Offset(1150, 1500),
    };
    
    for (final node in MapsMockData.nodes) {
      _nodePositions[node.id] = manualOffsets[node.id] ?? const Offset(1000, 1000);
    }
  }

  void _updateVisibleGraph() {
    setState(() {
      final query = _searchController.text.toLowerCase();
      
      _visibleNodes = MapsMockData.nodes.where((n) {
        if (!_visibleNodeTypes.contains(n.type)) return false;
        
        if (query.isNotEmpty && !n.label.toLowerCase().contains(query)) {
          return false;
        }
        
        if (_selectedMap == 1) {
          // Concept map: hide gaps
          return n.type != GraphNodeType.researchGap;
        } else {
          // Gap map and Semua: show everything
          return true;
        }
      }).toList();

      final visibleIds = _visibleNodes.map((n) => n.id).toSet();
      
      _visibleEdges = MapsMockData.edges.where((e) {
        return visibleIds.contains(e.sourceId) && visibleIds.contains(e.targetId);
      }).toList();
    });
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      children: [
                        const Text('Filter Map', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E2340))),
                        const SizedBox(height: 24),
                        
                        // 1. Tampilkan Tipe NODE
                        const Text('Tampilkan Tipe NODE', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.muted)),
                        const SizedBox(height: 12),
                        LayoutBuilder(builder: (context, constraints) {
                          final width = (constraints.maxWidth - 12) / 2;
                          final items = [
                            {'icon': Icons.article_outlined, 'label': 'Paper Nodes'},
                            {'icon': Icons.lightbulb_outline, 'label': 'Concept Nodes'},
                            {'icon': Icons.data_object, 'label': 'Variable Nodes'},
                            {'icon': Icons.warning_amber_rounded, 'label': 'Research GAP Nodes'},
                            {'icon': Icons.public, 'label': 'Research Area'},
                            {'icon': Icons.science_outlined, 'label': 'Method Nodes'},
                          ];
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: items.map((item) => _buildFilterButton(
                              width: width,
                              icon: item['icon'] as IconData,
                              label: item['label'] as String,
                              isSelected: true,
                              onTap: () {}, // TODO: state logic
                            )).toList(),
                          );
                        }),
                        
                        const SizedBox(height: 32),
                        
                        // 2. Saring Tipe Celah
                        const Text('Saring Tipe Celah', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.muted)),
                        const SizedBox(height: 12),
                        LayoutBuilder(builder: (context, constraints) {
                          final width = (constraints.maxWidth - 12) / 2;
                          final items = [
                            {'icon': Icons.travel_explore, 'label': 'Unexplored Concept'},
                            {'icon': Icons.link_off, 'label': 'Missing Relation'},
                            {'icon': Icons.science, 'label': 'Methodological'},
                            {'icon': Icons.groups, 'label': 'Population Gap'},
                            {'icon': Icons.dataset, 'label': 'Dataset Gap'},
                            {'icon': Icons.analytics, 'label': 'Empirical Gap'},
                          ];
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: items.map((item) => _buildFilterButton(
                              width: width,
                              icon: item['icon'] as IconData,
                              label: item['label'] as String,
                              isSelected: true,
                              onTap: () {},
                            )).toList(),
                          );
                        }),
                        
                        const SizedBox(height: 32),
                        
                        // 3. Saring Area Cakupan
                        const Text('Saring Area Cakupan', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.muted)),
                        const SizedBox(height: 12),
                        LayoutBuilder(builder: (context, constraints) {
                          final width = (constraints.maxWidth - 12) / 2;
                          final items = [
                            {'color': Colors.green, 'label': 'Banyak di teliti'},
                            {'color': Colors.yellow.shade700, 'label': 'Cukup di teliti'},
                            {'color': Colors.orange, 'label': 'Jarang di teliti'},
                            {'color': Colors.red, 'label': 'Belum di teliti'},
                          ];
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: items.map((item) => _buildFilterButton(
                              width: width,
                              icon: Icons.square,
                              iconColor: item['color'] as Color,
                              label: item['label'] as String,
                              isSelected: true,
                              onTap: () {},
                            )).toList(),
                          );
                        }),
                        
                        const SizedBox(height: 32),
                        
                        // 4. Saring Klaster Penelitian
                        const Text('Saring Klaster Penelitian', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.muted)),
                        const SizedBox(height: 12),
                        _buildDropdownFilter(Icons.category, 'Method Cluster'),
                        const SizedBox(height: 12),
                        _buildDropdownFilter(Icons.interests, 'Object Cluster'),
                        
                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                  
                  // Footer Actions
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            setModalState(() {});
                          },
                          child: const Text('Reset', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 16),
                        FilledButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _updateVisibleGraph();
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Terapkan Filter', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterButton({
    required double width,
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo.withOpacity(0.08) : Colors.transparent,
          border: Border.all(color: isSelected ? Colors.indigo.shade300 : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColor ?? (isSelected ? Colors.indigo.shade600 : Colors.grey.shade600)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.indigo.shade900 : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownFilter(IconData icon, String hint) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                hint: Text(hint, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                isExpanded: true,
                items: const [],
                onChanged: (value) {},
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showGapDetail(GraphNode node) {
    if (node.type != GraphNodeType.researchGap) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(24),
                children: [
                  // Handle for dragging
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  
                  // Header Title
                  Text(
                    'GAP DETAIL: ${node.label.toUpperCase()}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo.shade800, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 24),
                  
                  // 1. Gap Statement
                  const Text('GAP STATEMENT', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E2340))),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      '"${node.gapStatement ?? node.label}"',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1E2340), height: 1.5, fontStyle: FontStyle.italic),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // 2. Jenis Gap
                  const Text('JENIS GAP', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E2340))),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.indigo.withOpacity(0.15)),
                    ),
                    child: Text(
                      node.gapType?.name.toUpperCase() ?? 'MISSING CONCEPT RELATIONSHIP',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.indigo.shade900),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 3. Status & Confidence Row
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.local_police_outlined, size: 16, color: Colors.indigo.shade600),
                              const SizedBox(width: 6),
                              Builder(
                                builder: (context) {
                                  final confStr = node.confidence?.name.toLowerCase() ?? 'medium';
                                  String percentage = '75%';
                                  if (confStr.contains('high')) percentage = '90%';
                                  else if (confStr.contains('low')) percentage = '30%';
                                  
                                  return Text(
                                    'CONFIDENCE $percentage',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade600),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: node.isValidated ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                node.isValidated ? Icons.check_circle : Icons.pending, 
                                size: 16, 
                                color: node.isValidated ? Colors.green.shade600 : Colors.orange.shade700
                              ),
                              const SizedBox(width: 6),
                              Text(
                                node.isValidated ? 'Validated' : 'Pending',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: node.isValidated ? Colors.green.shade700 : Colors.orange.shade800),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // 4. Supporting Papers
                  const Text('BUKTI PENDUKUNG (SUPPORTING EVIDENCE)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E2340))),
                  const SizedBox(height: 16),
                  
                  ...node.evidence.map((ev) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.white,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ev.paperTitle,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Ditemukan pada: ',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted),
                                ),
                                Expanded(
                                  child: Text(
                                    ev.section,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E2340)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text('Kutipan Asli:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(12),
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border(left: BorderSide(color: Colors.indigo.shade300, width: 4)),
                              ),
                              child: Text(
                                '"${ev.quote}"',
                                style: const TextStyle(fontStyle: FontStyle.italic, color: Color(0xFF4A5568), fontSize: 13, height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  
                  const SizedBox(height: 16),
                  
                  // 5. Related Concepts
                  const Text('KONSEP TERKAIT (RELATED CONCEPTS)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E2340))),
                  const SizedBox(height: 16),
                  
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final itemWidth = (constraints.maxWidth - 12) / 2; // 2 kolom dengan jarak 12
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: node.relatedConceptIds.map((id) {
                          final concept = MapsMockData.nodes.firstWhere((n) => n.id == id);
                          IconData cIcon = Icons.lightbulb_outline;
                          if (concept.label.toLowerCase().contains('student') || concept.type == GraphNodeType.object) cIcon = Icons.person_outline;
                          if (concept.label.toLowerCase().contains('education') || concept.type == GraphNodeType.researchArea) cIcon = Icons.menu_book_outlined;
                          if (concept.label.toLowerCase().contains('ai') || concept.type == GraphNodeType.concept) cIcon = Icons.psychology_outlined;
                          
                          return InkWell(
                            onTap: () {
                              Navigator.pop(context);
                              final pos = _nodePositions[concept.id]!;
                              const double scale = 0.8;
                              final dx = MediaQuery.of(context).size.width / 2 - pos.dx * scale;
                              final dy = MediaQuery.of(context).size.height / 2 - pos.dy * scale;
                              _transformController.value = Matrix4.identity()
                                ..translate(dx, dy)
                                ..scale(scale);
                            },
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              width: itemWidth,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.indigo.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Row(
                                children: [
                                  Icon(cIcon, color: Colors.indigo.shade700, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      concept.label,
                                      style: TextStyle(color: Colors.indigo.shade900, fontWeight: FontWeight.w600, fontSize: 13),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 48),
                  
                  // 6. Button Baca Sumber
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        // Aksi baca sumber paper
                      },
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('BACA PAPER SUMBER', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.indigo,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNodeWidget(GraphNode node) {
    IconData icon;
    Color color;
    
    switch (node.type) {
      case GraphNodeType.concept:
        icon = Icons.psychology_outlined;
        color = Colors.blue;
        break;
      case GraphNodeType.researchGap:
        icon = Icons.warning_amber_rounded;
        color = Colors.orange;
        break;
      case GraphNodeType.paper:
        icon = Icons.article_outlined;
        color = Colors.green;
        break;
      case GraphNodeType.variable:
        icon = Icons.show_chart_rounded;
        color = Colors.teal;
        break;
      case GraphNodeType.method:
        icon = Icons.description_outlined;
        color = Colors.blueGrey;
        break;
      case GraphNodeType.object:
        icon = Icons.school_outlined;
        color = Colors.indigo;
        break;
      case GraphNodeType.researchArea:
        icon = Icons.folder_open_rounded;
        color = Colors.brown;
        break;
      case GraphNodeType.result:
        icon = Icons.lightbulb_outline_rounded;
        color = Colors.deepPurple;
        break;
    }

    // Gaps are rendered larger as requested in wireframe
    final isGap = node.type == GraphNodeType.researchGap;

    return GestureDetector(
      onTap: () {
        if (isGap) _showGapDetail(node);
      },
      child: Container(
        width: isGap ? 240 : 180,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: color.withOpacity(0.4), width: isGap ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                node.label,
                style: TextStyle(fontSize: 12, fontWeight: isGap ? FontWeight.bold : FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPillButton(int index, String label) {
    final isSelected = _selectedMap == index;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedMap = index;
          _updateVisibleGraph();
        });
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: isSelected ? null : Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF1E2340),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  void _zoom(double factor) {
    final currentMatrix = _transformController.value;
    final scale = currentMatrix.getMaxScaleOnAxis();
    final newScale = (scale * factor).clamp(0.1, 2.0);
    final ratio = newScale / scale;
    
    // Zoom around center of canvas
    final size = MediaQuery.of(context).size;
    final center = Offset(size.width / 2, 200); // 200 is half of canvas height
    
    final Matrix4 newMatrix = Matrix4.identity()
      ..translate(
        center.dx * (1 - ratio) + currentMatrix.getTranslation().x * ratio,
        center.dy * (1 - ratio) + currentMatrix.getTranslation().y * ratio,
      )
      ..scale(newScale);
      
    _transformController.value = newMatrix;
  }

  @override
  Widget build(BuildContext context) {
    final visibleGapNodes = _visibleNodes.where((n) => n.type == GraphNodeType.researchGap).toList();
    final totalPapers = MapsMockData.nodes.where((n) => n.type == GraphNodeType.paper).length;
    final totalGaps = MapsMockData.nodes.where((n) => n.type == GraphNodeType.researchGap).length;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(widget.projectTitle, style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showFilterSheet,
        icon: const Icon(Icons.filter_list_rounded),
        label: const Text('Filter Map'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Tipografi
              const Text(
                'Research Gap Map',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1E2340)),
              ),
              const SizedBox(height: 6),
              Text(
                widget.projectTitle,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E2340)),
              ),
              const SizedBox(height: 4),
              Text(
                '$totalPapers paper dianalisis',
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              
              // 2. Kartu Statistik
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.white,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.indigo.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.description_outlined, color: Colors.indigo, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$totalPapers',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const Text('Papers', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.white,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.indigo.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.track_changes_outlined, color: Colors.indigo, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$totalGaps',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const Text('Gaps', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              // 3. Toggle Filter
              Row(
                children: [
                  _buildPillButton(0, 'Semua'),
                  const SizedBox(width: 8),
                  _buildPillButton(1, 'Concept'),
                  const SizedBox(width: 8),
                  _buildPillButton(2, 'Gap'),
                ],
              ),
              const SizedBox(height: 24),
              
              // 4. Box Canvas Interaktif
              Container(
                height: 400,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F5F9), // Warna kanvas kebiruan sangat muda
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade200, width: 1.5),
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: InteractiveViewer(
                        transformationController: _transformController,
                        boundaryMargin: const EdgeInsets.all(2000),
                        minScale: 0.1,
                        maxScale: 2.0,
                        constrained: false,
                        child: SizedBox(
                          width: 2000,
                          height: 2000,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // Zone Backgrounds if Gap Map is active
                              if (_selectedMap == 2) ...[
                                Positioned(
                                  top: 500,
                                  left: 500,
                                  right: 0,
                                  height: 600,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.05),
                                      border: Border(top: BorderSide(color: Colors.green.withOpacity(0.3), width: 2)),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Text(
                                        '🟩 ZONA: WELL-STUDIED AREA',
                                        style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 18),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 1100,
                                  left: 500,
                                  right: 0,
                                  height: 600,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withOpacity(0.05),
                                      border: Border(top: BorderSide(color: Colors.amber.withOpacity(0.3), width: 2)),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Text(
                                        '🟨 ZONA: UNDER-STUDIED AREA',
                                        style: TextStyle(color: Colors.amber.shade800, fontWeight: FontWeight.bold, fontSize: 18),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              // GraphView to render nodes and edges with Sugiyama auto layout
                              Positioned.fill(
                                child: GraphView(
                                  graph: _buildGraphViewGraph(),
                                  algorithm: SugiyamaAlgorithm(SugiyamaConfiguration()
                                    ..nodeSeparation = 120
                                    ..levelSeparation = 300
                                    ..orientation = SugiyamaConfiguration.ORIENTATION_LEFT_RIGHT
                                  ),
                                  paint: Paint()..color = Colors.indigo.shade200..strokeWidth = 1.5..style = PaintingStyle.stroke,
                                  builder: (Node node) {
                                    final graphNode = node.key!.value as GraphNode;
                                    return _buildNodeWidget(graphNode);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Zoom Buttons Overlay
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.add, size: 20),
                              onPressed: () => _zoom(1.2),
                              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                              padding: EdgeInsets.zero,
                            ),
                            Container(height: 1, width: 40, color: Colors.grey.shade200),
                            IconButton(
                              icon: const Icon(Icons.remove, size: 20),
                              onPressed: () => _zoom(0.8),
                              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              
              // 5. Research Gaps Section
              const Text(
                'Research Gaps',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E2340)),
              ),
              const SizedBox(height: 16),
              
              if (visibleGapNodes.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: const Text('Tidak ada research gap yang ditampilkan pada filter ini.', style: TextStyle(color: AppColors.muted)),
                )
              else
                SizedBox(
                  height: 150,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: visibleGapNodes.length,
                    separatorBuilder: (context, _) => const SizedBox(width: 16),
                    itemBuilder: (context, index) {
                      final gap = visibleGapNodes[index];
                      // Ekstrak angka "01" dari "Gap 01" atau gunakan indeks
                      final gapNumber = (index + 1).toString().padLeft(2, '0');
                      final relatedPapers = gap.evidence.length;
                      
                      return Container(
                        width: MediaQuery.of(context).size.width - 40,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.warning_amber_rounded, color: Colors.indigo, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Gap $gapNumber',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: Text(
                                gap.gapStatement ?? gap.label,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF4A5568)),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  '$relatedPapers papers',
                                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Text('•', style: TextStyle(color: AppColors.muted)),
                                ),
                                Text(
                                  gap.confidence?.name.toUpperCase() ?? 'MEDIUM',
                                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                                ),
                                const Spacer(),
                                InkWell(
                                  onTap: () => _showGapDetail(gap),
                                  child: Row(
                                    children: [
                                      Text(
                                        'Detail',
                                        style: TextStyle(fontSize: 12, color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.arrow_forward_rounded, size: 14, color: Theme.of(context).primaryColor),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 80), // Padding tambahan agar tidak tertutup FAB
            ],
          ),
        ),
      ),
    );
  }
}

class _GraphEdgePainter extends CustomPainter {
  _GraphEdgePainter({
    required this.edges,
    required this.positions,
  });

  final List<GraphEdge> edges;
  final Map<String, Offset> positions;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final edge in edges) {
      final p1 = positions[edge.sourceId];
      final p2 = positions[edge.targetId];

      if (p1 == null || p2 == null) continue;

      // Adjust for node center (assuming 180x50 node roughly)
      final start = p1 + const Offset(90, 25);
      final end = p2 + const Offset(90, 25);

      canvas.drawLine(start, end, linePaint);
      
      // Draw arrow head
      final d = end - start;
      final angle = atan2(d.dy, d.dx);
      const arrowLen = 12.0;
      final arrowEnd = end - Offset(cos(angle) * 45, sin(angle) * 45); 
      
      final pA = arrowEnd - Offset(cos(angle - pi/6) * arrowLen, sin(angle - pi/6) * arrowLen);
      final pB = arrowEnd - Offset(cos(angle + pi/6) * arrowLen, sin(angle + pi/6) * arrowLen);
      
      final path = Path()
        ..moveTo(arrowEnd.dx, arrowEnd.dy)
        ..lineTo(pA.dx, pA.dy)
        ..lineTo(pB.dx, pB.dy)
        ..close();
        
      canvas.drawPath(path, Paint()..color = Colors.grey.shade500);

      // Draw label
      textPainter.text = TextSpan(
        text: edge.label,
        style: TextStyle(
          color: Colors.grey.shade600,
          backgroundColor: Colors.white.withOpacity(0.9),
          fontSize: 10,
        ),
      );
      textPainter.layout();
      
      final mid = start + d / 2;
      textPainter.paint(canvas, mid - Offset(textPainter.width / 2, textPainter.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _GraphEdgePainter oldDelegate) => true;
}
