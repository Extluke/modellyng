import 'package:flutter_mermaid/flutter_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modellyng/src/data/concept_map_repository.dart';
import 'package:modellyng/src/widgets/research_flowchart.dart';

void main() {
  const nodes = [
    ConceptMapNode(
      id: 'paper:paper-a',
      kind: 'paper',
      label: 'Reliable research',
      detail: 'paper.pdf',
      paperId: 'paper-a',
      parameter: null,
      pageNumber: null,
    ),
    ConceptMapNode(
      id: 'concept:paper-a:methodology',
      kind: 'concept',
      label: 'methodology',
      detail: 'A mixed-method approach',
      paperId: 'paper-a',
      parameter: 'methodology',
      pageNumber: null,
    ),
    ConceptMapNode(
      id: 'evidence:paper-a:methodology:0',
      kind: 'evidence',
      label: 'Halaman 4',
      detail: 'The study combines interviews and survey data.',
      paperId: 'paper-a',
      parameter: 'methodology',
      pageNumber: 4,
    ),
  ];
  const edges = [
    ConceptMapEdge(
      source: 'paper:paper-a',
      target: 'concept:paper-a:methodology',
      relation: 'contains',
    ),
    ConceptMapEdge(
      source: 'concept:paper-a:methodology',
      target: 'evidence:paper-a:methodology:0',
      relation: 'supported_by',
    ),
  ];

  test('builds a valid styled Mermaid flowchart from graph JSON', () {
    final document = ResearchMermaidDocument.fromGraph(nodes, edges);
    final diagram = const MermaidParser().parse(document.code);

    expect(document.code, startsWith('flowchart LR\n'));
    expect(document.code, contains('node0 -->|memuat| node1'));
    expect(document.code, contains('node1 -->|didukung| node2'));
    expect(diagram, isNotNull);
    expect(diagram!.nodes, hasLength(3));
    expect(diagram.edges, hasLength(2));
    expect(diagram.nodes[1].label, contains('Metodologi'));
    expect(diagram.nodes[2].label, contains('Halaman 4'));
    expect(diagram.nodes.map((node) => node.className), [
      'paper',
      'concept',
      'evidence',
    ]);
    expect(document.nodeForMermaidId('node2'), same(nodes[2]));
  });

  test('document text cannot inject Mermaid nodes or edges', () {
    const maliciousNodes = [
      ConceptMapNode(
        id: 'paper-a',
        kind: 'paper',
        label: 'Trusted ]\nattacker --> injected[ %% hidden',
        detail: '',
        paperId: 'paper-a',
        parameter: null,
        pageNumber: null,
      ),
      ConceptMapNode(
        id: 'concept-a',
        kind: 'concept',
        label: 'methodology',
        detail: 'quote | classDef hacked fill:#000 ===> extra',
        paperId: 'paper-a',
        parameter: 'methodology',
        pageNumber: null,
      ),
    ];
    const maliciousEdges = [
      ConceptMapEdge(
        source: 'paper-a',
        target: 'concept-a',
        relation: 'contains',
      ),
      ConceptMapEdge(
        source: 'missing',
        target: 'concept-a',
        relation: 'ignored',
      ),
    ];

    final document = ResearchMermaidDocument.fromGraph(
      maliciousNodes,
      maliciousEdges,
    );
    final diagram = const MermaidParser().parse(document.code);

    expect(diagram, isNotNull);
    expect(diagram!.nodes, hasLength(2));
    expect(diagram.edges, hasLength(1));
    expect(document.code, isNot(contains('attacker --> injected')));
    expect(document.code, isNot(contains('%%')));
    expect(document.code, isNot(contains('===>')));
  });

  test('compact mobile document stays valid without long detail text', () {
    final document = ResearchMermaidDocument.fromGraph(
      nodes,
      edges,
      compact: true,
    );
    final diagram = const MermaidParser().parse(document.code);

    expect(diagram, isNotNull);
    expect(diagram!.nodes, hasLength(3));
    expect(document.code, contains('KONSEP · Metodologi'));
    expect(document.code, isNot(contains('mixed-method approach')));
    expect(document.nodeForMermaidId('node2'), same(nodes[2]));
  });

  test('duplicate or empty source IDs do not create ambiguous tap routes', () {
    final document = ResearchMermaidDocument.fromGraph([
      nodes.first,
      nodes.first,
      _copyWithId(nodes[1], ''),
    ], edges);
    final diagram = const MermaidParser().parse(document.code);

    expect(diagram, isNotNull);
    expect(diagram!.nodes, hasLength(1));
    expect(document.nodeForMermaidId('node0'), same(nodes.first));
    expect(document.nodeForMermaidId('node1'), isNull);
  });
}

ConceptMapNode _copyWithId(ConceptMapNode node, String id) => ConceptMapNode(
  id: id,
  kind: node.kind,
  label: node.label,
  detail: node.detail,
  paperId: node.paperId,
  parameter: node.parameter,
  pageNumber: node.pageNumber,
);
