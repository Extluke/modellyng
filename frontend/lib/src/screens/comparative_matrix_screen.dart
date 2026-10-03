import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/project_repository.dart';
import '../models/research_models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'project_matrix_detail_screen.dart';

class ComparativeMatrixScreen extends ConsumerStatefulWidget {
  const ComparativeMatrixScreen({required this.userId, super.key});
  final String userId;
  @override
  ConsumerState<ComparativeMatrixScreen> createState() =>
      _ComparativeMatrixScreenState();
}

class _ComparativeMatrixScreenState
    extends ConsumerState<ComparativeMatrixScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider(widget.userId));
    
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 28, 24, 12),
            child: PageHeading(
              title: 'Pilih Proyek',
              subtitle: 'Pilih proyek untuk melihat matriks komparasi.',
            ),
          ),
          
          Expanded(
            child: projects.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => const _MatrixListMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Proyek belum dapat dimuat',
                message: 'Periksa layanan lokal lalu coba lagi.',
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const _MatrixListMessage(
                    icon: Icons.folder_off_outlined,
                    title: 'Belum ada proyek',
                    message:
                        'Buat proyek pertamamu dan selesaikan review minimal dua paper.',
                    showAddButton: true,
                  );
                }
                
                // 1. Sorting berdasarkan updatedAt terbaru
                var sortedItems = List.of(items)
                  ..sort((a, b) {
                    final dateA = a.updatedAt ?? DateTime(1970);
                    final dateB = b.updatedAt ?? DateTime(1970);
                    return dateB.compareTo(dateA); 
                  });
                  
                // Filter jika ada search query
                if (_searchQuery.isNotEmpty) {
                  sortedItems = sortedItems.where((p) => 
                    p.title.toLowerCase().contains(_searchQuery.toLowerCase())
                  ).toList();
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 100), // Padding bawah lega untuk BottomNav
                  children: [
                    // Search bar dinamis jika total proyek > 3
                    if (items.length > 3) ...[
                      _SearchBar(
                        onChanged: (val) => setState(() => _searchQuery = val),
                      ),
                      const SizedBox(height: 20),
                    ],
                    
                    // Render List Proyek
                    ...sortedItems.asMap().entries.map((entry) {
                      final index = entry.key;
                      final project = entry.value;
                      final isLatest = (index == 0 && _searchQuery.isEmpty);
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: _ProjectCard(
                          project: project,
                          isLatest: isLatest,
                          onTap: () => _handleCardTap(context, project),
                        ),
                      );
                    }),
                    
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _handleCardTap(BuildContext context, ResearchProject project) {
    final incompletePapers = project.paperCount - project.readyCount;
    
    // Peraturan validasi sebelum mengizinkan klik (sesuai masukan Anda)
    if (incompletePapers > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tersisa $incompletePapers paper belum selesai direview.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    
    if (project.readyCount < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Matriks membutuhkan minimal 2 paper selesai.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProjectMatrixDetailScreen(
          projectId: project.id,
          projectTitle: project.title,
        ),
      ),
    );
  }
}

// --- Komponen UI ---

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.isLatest,
    required this.onTap,
  });

  final ResearchProject project;
  final bool isLatest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progressVal = project.paperCount > 0 
        ? project.readyCount / project.paperCount 
        : 0.0;
        
    final isComplete = progressVal == 1.0 && project.paperCount >= 2;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppColors.primarySoft.withValues(alpha: 0.5), 
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isLatest) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Terakhir dibuka',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.folder_outlined,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Texts
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${project.paperCount} paper · ${project.updatedLabel}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
                ],
              ),
              const SizedBox(height: 16),
              
              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(3), // half of 6px height
                child: LinearProgressIndicator(
                  value: progressVal,
                  minHeight: 6,
                  backgroundColor: AppColors.primarySoft.withValues(alpha: 0.5),
                  color: isComplete ? AppColors.green : AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              
              // Labels Bawah
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${project.readyCount} dari ${project.paperCount} selesai',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted,
                    ),
                  ),
                  if (isComplete)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Siap Matriks',
                        style: TextStyle(
                          fontSize: 10, 
                          fontWeight: FontWeight.bold,
                          color: AppColors.green,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Cari proyek...',
        prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.muted),
        filled: true,
        fillColor: Theme.of(context).cardColor,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primarySoft.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primarySoft.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}

class _MatrixListMessage extends StatelessWidget {
  const _MatrixListMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.showAddButton = false,
  });
  final IconData icon;
  final String title;
  final String message;
  final bool showAddButton;
  
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.primarySoft.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title, 
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 18,
              )
            ),
            const SizedBox(height: 8),
            Text(
              message, 
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 14),
            ),
            if (showAddButton) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Buat Proyek'),
              ),
            ]
          ],
        ),
      ),
    ),
  );
}
