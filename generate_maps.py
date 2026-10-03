import re

with open('frontend/lib/src/screens/comparative_matrix_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

new_maps_screen = content.replace('ComparativeMatrix', 'Maps')
new_maps_screen = new_maps_screen.replace('ProjectMatrixDetailScreen', 'ProjectMapsDetailScreen')
new_maps_screen = new_maps_screen.replace('project_matrix_detail_screen.dart', 'project_maps_detail_screen.dart')
new_maps_screen = new_maps_screen.replace('melihat matriks komparasi', 'melihat visualisasi peta')
new_maps_screen = new_maps_screen.replace('Matriks membutuhkan minimal 2 paper selesai.', 'Pemetaan membutuhkan minimal 1 paper selesai direview.')
new_maps_screen = new_maps_screen.replace('project.readyCount < 2', 'project.readyCount < 1')
new_maps_screen = new_maps_screen.replace('Siap Matriks', 'Siap Pemetaan')

new_maps_screen = new_maps_screen.replace(
    'projectId: project.id,\n          projectTitle: project.title,',
    'projectId: project.id,\n          projectTitle: project.title,\n          userId: widget.userId,'
)

with open('frontend/lib/src/screens/maps_screen.dart', 'w', encoding='utf-8') as f:
    f.write(new_maps_screen)


detail_screen = """import 'package:flutter/material.dart';

import 'concept_evidence_map_screen.dart';
import 'research_gap_map_screen.dart';
import '../theme/app_theme.dart';

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
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Visualisasi Pemetaan', style: TextStyle(fontSize: 16)),
            Text(
              widget.projectTitle,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      icon: Icon(Icons.hub_outlined),
                      label: Text('Concept / Evidence'),
                    ),
                    ButtonSegment(
                      value: 1,
                      icon: Icon(Icons.lightbulb_outline_rounded),
                      label: Text('Research Gap'),
                    ),
                  ],
                  selected: {_selected},
                  onSelectionChanged: (value) =>
                      setState(() => _selected = value.first),
                ),
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _selected,
              children: [
                ConceptEvidenceMapScreen(
                  userId: widget.userId,
                  projectId: widget.projectId,
                ),
                ResearchGapMapScreen(
                  userId: widget.userId,
                  projectId: widget.projectId,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
"""

with open('frontend/lib/src/screens/project_maps_detail_screen.dart', 'w', encoding='utf-8') as f:
    f.write(detail_screen)


with open('frontend/lib/src/screens/concept_evidence_map_screen.dart', 'r', encoding='utf-8') as f:
    cem_content = f.read()

cem_content = cem_content.replace(
    'const ConceptEvidenceMapScreen({required this.userId, super.key});',
    'const ConceptEvidenceMapScreen({required this.userId, required this.projectId, super.key});'
)
cem_content = cem_content.replace(
    'final String userId;',
    'final String userId;\n  final String projectId;'
)

cem_content = re.sub(r'''\s*DropdownButtonFormField<String>\(\s*initialValue: _projectId,.*?onChanged: \(value\) => setState\(\(\) \{\s*_projectId = value;\s*_paperId = null;\s*\}\),\s*\),\s*const SizedBox\(height: 18\),''', '', cem_content, flags=re.DOTALL)
cem_content = re.sub(r'''projects\.when\(\s*loading:.*?data: \(items\) \{.*?_projectId \?\?= items\.first\.id;\s*return Column\(''', "Column(", cem_content, flags=re.DOTALL)
cem_content = re.sub(r'''_map\(ref\.watch\(conceptMapProvider\(_projectId!\)\)\),\s*],\s*\);\s*},\s*\),''', "_map(ref.watch(conceptMapProvider(widget.projectId))),\n                ],\n              ),", cem_content, flags=re.DOTALL)
cem_content = cem_content.replace('String? _projectId;\n', '')
cem_content = cem_content.replace('import \'../data/project_repository.dart\';\n', '')
cem_content = cem_content.replace('final projects = ref.watch(projectsProvider(widget.userId));\n', '')

with open('frontend/lib/src/screens/concept_evidence_map_screen.dart', 'w', encoding='utf-8') as f:
    f.write(cem_content)


with open('frontend/lib/src/screens/research_gap_map_screen.dart', 'r', encoding='utf-8') as f:
    rgm_content = f.read()

rgm_content = rgm_content.replace(
    'const ResearchGapMapScreen({required this.userId, super.key});',
    'const ResearchGapMapScreen({required this.userId, required this.projectId, super.key});'
)
rgm_content = rgm_content.replace(
    'final String userId;',
    'final String userId;\n  final String projectId;'
)

rgm_content = re.sub(r'''\s*DropdownButtonFormField<String>\(\s*initialValue: _projectId,.*?onChanged: \(value\) => setState\(\(\) => _projectId = value\),\s*\),\s*const SizedBox\(height: 14\),''', '', rgm_content, flags=re.DOTALL)
rgm_content = re.sub(r'''projects\.when\(\s*loading:.*?data: \(items\) \{.*?_projectId \?\?= items\.first\.id;\s*return Column\(''', "Column(", rgm_content, flags=re.DOTALL)
rgm_content = re.sub(r'''_map\(\s*ref\.watch\(researchGapMapProvider\(_projectId!\)\),\s*ref\.watch\(researchGapDecisionsProvider\(_projectId!\)\),\s*\),\s*],\s*\);\s*},\s*\),''', "_map(\n                    ref.watch(researchGapMapProvider(widget.projectId)),\n                    ref.watch(researchGapDecisionsProvider(widget.projectId)),\n                  ),\n                ],\n              ),", rgm_content, flags=re.DOTALL)
rgm_content = rgm_content.replace("PaperComparisonPanel(key: ValueKey('gap-pairs-$_projectId'), projectId: _projectId!)", "PaperComparisonPanel(key: ValueKey('gap-pairs-${widget.projectId}'), projectId: widget.projectId)")

rgm_content = rgm_content.replace('String? _projectId;\n', '')
rgm_content = rgm_content.replace('import \'../data/project_repository.dart\';\n', '')
rgm_content = rgm_content.replace('final projects = ref.watch(projectsProvider(widget.userId));\n', '')

with open('frontend/lib/src/screens/research_gap_map_screen.dart', 'w', encoding='utf-8') as f:
    f.write(rgm_content)

print("Refactoring complete.")
