import 'package:flutter/material.dart';

import '../models/research_models.dart';

abstract final class DemoData {
  static const projects = <ResearchProject>[
    ResearchProject(
      id: 'climate-urban',
      title: 'Climate Change Impacts on Urban Infrastructure',
      description:
          'Sintesis strategi adaptasi infrastruktur kota terhadap perubahan iklim.',
      paperCount: 14,
      progress: 0.82,
      status: ProjectStatus.needsReview,
      updatedLabel: 'Diperbarui 2 jam lalu',
      accent: Color(0xFF2878F0),
    ),
    ResearchProject(
      id: 'quantum-error',
      title: 'Quantum Computing Error Correction Methods',
      description:
          'Perbandingan metode koreksi error untuk arsitektur quantum modern.',
      paperCount: 8,
      progress: 0.48,
      status: ProjectStatus.processing,
      updatedLabel: 'Diperbarui kemarin',
      accent: Color(0xFF7457D9),
    ),
    ResearchProject(
      id: 'neuromorphic',
      title: 'Neuromorphic Hardware Architectures',
      description:
          'Pemetaan arsitektur dan efisiensi komputasi perangkat neuromorfik.',
      paperCount: 22,
      progress: 1,
      status: ProjectStatus.ready,
      updatedLabel: 'Diperbarui 3 hari lalu',
      accent: Color(0xFF158466),
    ),
  ];

  static const papers = <PaperRecord>[
    PaperRecord(
      id: 'paper-a',
      title:
          'Urban Climate Resilience: A Systematic Review of Adaptive Infrastructure',
      authors: 'Chen, A., Rahman, F., & Silva, M.',
      year: 2024,
      journal: 'Journal of Climate Adaptation',
      doi: '10.1016/j.jca.2024.0142',
      status: PaperStatus.needsReview,
      progress: 1,
    ),
    PaperRecord(
      id: 'paper-b',
      title: 'Data-driven Flood Risk Modeling for Rapidly Growing Cities',
      authors: 'Kurniawan, D. & Patel, S.',
      year: 2023,
      journal: 'Sustainable Cities and Society',
      doi: '10.1016/j.scs.2023.104388',
      status: PaperStatus.ready,
      progress: 1,
    ),
    PaperRecord(
      id: 'paper-c',
      title:
          'Heat Vulnerability and Green Infrastructure in Southeast Asian Cities',
      authors: 'Nguyen, T., Putri, A., & Wong, K.',
      year: 2025,
      journal: 'Urban Climate',
      doi: '10.1016/j.uclim.2025.101221',
      status: PaperStatus.processing,
      progress: 0.64,
    ),
  ];

  static const components = <ExtractedComponent>[
    ExtractedComponent(
      label: 'Research Problem',
      value:
          'Kota berkembang menghadapi risiko iklim yang meningkat, tetapi strategi adaptasi infrastrukturnya masih dinilai secara terpisah.',
      evidence:
          'Existing reviews examine individual hazards, leaving an integrated view of urban infrastructure adaptation unresolved.',
      location: 'Hal. 2 · Introduction · Paragraf 3',
      status: VerificationStatus.verified,
    ),
    ExtractedComponent(
      label: 'Research Objective',
      value:
          'Mensintesis bukti mengenai efektivitas intervensi infrastruktur adaptif pada berbagai risiko iklim perkotaan.',
      evidence:
          'This review synthesizes evidence on adaptive infrastructure interventions across multiple urban climate hazards.',
      location: 'Hal. 3 · Introduction · Paragraf 1',
      status: VerificationStatus.needsReview,
    ),
    ExtractedComponent(
      label: 'Methodology',
      value:
          'Systematic literature review mengikuti PRISMA dengan pencarian pada Scopus, Web of Science, dan Dimensions.',
      evidence:
          'A PRISMA-guided systematic search was conducted across Scopus, Web of Science, and Dimensions.',
      location: 'Hal. 4 · Methodology · Paragraf 2',
      status: VerificationStatus.verified,
    ),
    ExtractedComponent(
      label: 'Dataset / Sample',
      value: '86 studi peer-reviewed yang diterbitkan antara 2014–2024.',
      evidence:
          'After screening, 86 peer-reviewed studies published between 2014 and 2024 were included.',
      location: 'Hal. 5 · Study Selection · Paragraf 4',
      status: VerificationStatus.edited,
    ),
    ExtractedComponent(
      label: 'Key Findings',
      value:
          'Infrastruktur hijau konsisten menurunkan paparan panas, tetapi bukti dampak jangka panjang dan kota kecil masih terbatas.',
      evidence:
          'Green infrastructure consistently reduced heat exposure; longitudinal evidence and evidence from smaller cities remained scarce.',
      location: 'Hal. 11 · Results · Paragraf 6',
      status: VerificationStatus.needsReview,
    ),
    ExtractedComponent(
      label: 'Limitations',
      value:
          'Heterogenitas metrik dan kurangnya studi longitudinal membatasi generalisasi hasil.',
      evidence:
          'Heterogeneous metrics and a shortage of longitudinal studies limit the generalizability of our findings.',
      location: 'Hal. 15 · Limitations · Paragraf 1',
      status: VerificationStatus.needsReview,
    ),
  ];

  static const gaps = <ResearchGap>[
    ResearchGap(
      title: 'Evaluasi adaptasi jangka panjang pada kota lapis kedua',
      description:
          'Sebagian besar studi mengukur dampak jangka pendek dan berfokus pada kota metropolitan.',
      supportingPapers: 7,
      confidence: 0.87,
      type: 'Population & empirical gap',
    ),
    ResearchGap(
      title: 'Standarisasi metrik ketahanan lintas jenis infrastruktur',
      description:
          'Metrik yang heterogen menghambat perbandingan efektivitas antarintervensi.',
      supportingPapers: 11,
      confidence: 0.79,
      type: 'Methodological gap',
    ),
    ResearchGap(
      title: 'Hubungan intervensi hijau dengan ketimpangan sosial',
      description:
          'Dampak distribusi manfaat belum banyak diuji untuk kelompok sosial yang berbeda.',
      supportingPapers: 5,
      confidence: 0.72,
      type: 'Conceptual gap',
    ),
  ];
}
