import 'package:modellyng/src/data/paper_comparison_repository.dart';

// Synthetic test content; these are not results from uploaded research papers.
Map<String, dynamic> pairFixture({
  String id = 'pair-a-b',
  String status = 'completed',
}) => {
  'id': id,
  'left_paper_id': 'paper-a',
  'right_paper_id': 'paper-b',
  'status': status,
  'left_source': {'title': 'Faktor perilaku pengelolaan sampah rumah tangga'},
  'right_source': {'title': 'Faktor perilaku pemilahan sampah rumah tangga'},
  'error_message': status == 'failed'
      ? 'Model tidak tersedia. Coba lagi.'
      : null,
  'reviews': <Map<String, dynamic>>[],
  'result': status != 'completed'
      ? null
      : {
          'outcome': 'candidate_gap',
          'stop_aspect': 'data_object',
          'candidate': {
            'kind': 'population_context',
            'summary':
                'Rumah tangga umum berbeda dengan rumah tangga pemilah sampah.',
            'validation_question':
                'Periksa cakupan populasi dan literatur tambahan sebelum menyatakan kebaruan.',
          },
          'steps': [
            for (var i = 0; i < comparisonAspects.length; i++)
              {
                'aspect': comparisonAspects[i],
                'decision': i < 2
                    ? 'yes'
                    : i == 2
                    ? 'no'
                    : 'not_compared',
                'reason': i < 2
                    ? 'Konsep perilaku serta variabel pengetahuan, sikap, dan fasilitas berhubungan.'
                    : i == 2
                    ? 'Populasi rumah tangga berbeda.'
                    : 'Alur berhenti pada data/objek.',
                'left_evidence': i > 2 ? [] : [_evidence('a', i)],
                'right_evidence': i > 2 ? [] : [_evidence('b', i)],
              },
          ],
        },
};

Map<String, dynamic> _evidence(String side, int index) => {
  'paper_id': 'paper-$side',
  'component_id': 'component-$side-$index',
  'ref': 'evidence-$side-$index',
  'quote': index == 2
      ? (side == 'a'
            ? 'The sample included households in the city.'
            : 'The sample included only households that sort their waste.')
      : 'Knowledge, attitudes and facilities influence waste behavior.',
  'page_number': side == 'a' ? 3 : 5,
  'block_id': 'block-$side-$index',
  'section': 'Methods',
  'subsection': 'Participants',
  'evidence_kind': 'text',
};

PairComparisonOverview overviewFixture({
  List<Map<String, dynamic>>? pairs,
  int readyPapers = 2,
}) => PairComparisonOverview.fromJson({
  'total_papers': readyPapers,
  'ready_papers': readyPapers,
  'expected_pairs': readyPapers * (readyPapers - 1) ~/ 2,
  'pairs': pairs ?? [pairFixture()],
});
