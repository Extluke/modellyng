import sys
import os

screen_code = """import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/project_repository.dart';
import '../models/research_models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class KnowledgeGraphScreen extends ConsumerStatefulWidget {
  const KnowledgeGraphScreen({
    required this.projectId,
    required this.projectTitle,
    required this.userId,
    super.key,
  });

  final String projectId;
  final String projectTitle;
  final String userId;

  @override
  ConsumerState<KnowledgeGraphScreen> createState() => _KnowledgeGraphScreenState();
}

class _KnowledgeGraphScreenState extends ConsumerState<KnowledgeGraphScreen> {
  final TransformationController _transformController = TransformationController();
  bool _isLoading = true;
  KnowledgeGraphMap? _graphMap;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _fetchGraph();
  }

  Future<void> _fetchGraph() async {
    try {
      final repo = ref.read(projectRepositoryProvider);
      final map = await repo.getKnowledgeGraph(widget.projectId);
      setState(() {
        _graphMap = map;
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _centerView();
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _centerView() {
    if (!mounted || _graphMap == null || _graphMap!.nodes.isEmpty) return;
    
    // Find average x, y to center
    double sumX = 0, sumY = 0;
    int count = 0;
    for (var n in _graphMap!.nodes) {
      if (n.x != null && n.y != null) {
        sumX += n.x!;
        sumY += n.y!;
        count++;
      }
    }
    if (count == 0) return;
    
    final avgX = sumX / count;
    final avgY = sumY / count;
    
    final size = MediaQuery.of(context).size;
    const double scale = 0.5;
    final dx = (size.width / 2) - (avgX * scale);
    final dy = (size.height / 2) - (avgY * scale);
    
    _transformController.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text('Knowledge Graph: ${widget.projectTitle}'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(child: Text('Gagal memuat: $_error'));
    }
    if (_graphMap == null || _graphMap!.nodes.isEmpty) {
      return const Center(child: Text('Graph kosong. Pastikan PDF sudah diproses.'));
    }

    return Stack(
      children: [
        InteractiveViewer(
          transformationController: _transformController,
          constrained: false,
          boundaryMargin: const EdgeInsets.all(5000),
          minScale: 0.1,
          maxScale: 2.0,
          child: SizedBox(
            width: 5000,
            height: 5000,
            child: Stack(
              children: [
                _buildEdges(),
                ..._graphMap!.nodes.map((node) => _buildNode(node)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEdges() {
    return CustomPaint(
      size: const Size(5000, 5000),
      painter: _GraphEdgePainter(_graphMap!),
    );
  }

  Widget _buildNode(KnowledgeGraphNode node) {
    final x = node.x ?? 0.0;
    final y = node.y ?? 0.0;
    
    Color bgColor = Colors.white;
    Color borderColor = Colors.blue.shade300;
    if (node.kind == 'gap') {
      bgColor = Colors.orange.shade50;
      borderColor = Colors.orange.shade400;
    } else if (node.kind == 'result') {
      bgColor = Colors.green.shade50;
      borderColor = Colors.green.shade400;
    }

    return Positioned(
      left: x - 100, // half width
      top: y - 50,  // half height
      child: GestureDetector(
        onTap: () => _showNodeDetail(node),
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                node.kind.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: borderColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                node.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNodeDetail(KnowledgeGraphNode node) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'DETAIL ${node.kind.toUpperCase()}',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo.shade800),
              ),
              const SizedBox(height: 16),
              Text(
                node.label,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(node.detail, style: const TextStyle(fontSize: 16, height: 1.5)),
                ),
              ),
              if (node.kind == 'gap')
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _generateSynthesis(node.id);
                  },
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Buat Rumusan Masalah (AI)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _generateSynthesis(String nodeId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final repo = ref.read(projectRepositoryProvider);
      final synth = await repo.synthesizeGraphNodes(widget.projectId, [nodeId]);
      Navigator.pop(context); // close loading
      _showSynthesisResult(synth);
    } catch (e) {
      Navigator.pop(context); // close loading
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showSynthesisResult(AiResearchSynthesis synth) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: ListView(
            children: [
              const Text('RUMUSAN MASALAH (HASIL SINTESIS)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              const Text('Usulan Judul:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...synth.usulanJudul.map((j) => Padding(padding: const EdgeInsets.only(top: 8), child: Text('- $j'))),
              const SizedBox(height: 16),
              const Text('Pertanyaan Penelitian:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...synth.rumusanMasalah.map((r) => Padding(padding: const EdgeInsets.only(top: 8), child: Text('- $r'))),
              const SizedBox(height: 16),
              const Text('Pernyataan Novelty:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(synth.pernyataanNovelty),
              const SizedBox(height: 16),
              const Text('Alasan Pemilihan:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(synth.alasanPemilihan),
            ],
          ),
        );
      },
    );
  }
}

class _GraphEdgePainter extends CustomPainter {
  _GraphEdgePainter(this.map);
  final KnowledgeGraphMap map;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.indigo.shade200
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final Map<String, KnowledgeGraphNode> nodeMap = {
      for (var n in map.nodes) n.id: n
    };

    for (var edge in map.edges) {
      final src = nodeMap[edge.source];
      final tgt = nodeMap[edge.target];
      if (src != null && tgt != null && src.x != null && src.y != null && tgt.x != null && tgt.y != null) {
        canvas.drawLine(Offset(src.x!, src.y!), Offset(tgt.x!, tgt.y!), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
"""

os.makedirs('lib/src/screens', exist_ok=True)
with open('lib/src/screens/knowledge_graph_screen.dart', 'w', encoding='utf-8') as f:
    f.write(screen_code)

print("Created knowledge_graph_screen.dart")
