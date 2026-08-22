import 'package:flutter/material.dart';

import 'concept_evidence_map_screen.dart';
import 'research_gap_map_screen.dart';

class MapsScreen extends StatefulWidget {
  const MapsScreen({required this.userId, super.key});
  final String userId;

  @override
  State<MapsScreen> createState() => _MapsScreenState();
}

class _MapsScreenState extends State<MapsScreen> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) => Column(
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
            ConceptEvidenceMapScreen(userId: widget.userId),
            ResearchGapMapScreen(userId: widget.userId),
          ],
        ),
      ),
    ],
  );
}
