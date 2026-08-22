import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../data/project_repository.dart';
import '../models/research_models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'account_screen.dart';
import 'comparative_matrix_screen.dart';
import 'dashboard_screen.dart';
import 'maps_screen.dart';
import 'new_project_screen.dart';
import 'project_overview_screen.dart';
import 'projects_screen.dart';
import 'review_queue_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;

  static const _destinations = <_Destination>[
    _Destination(
      label: 'Dashboard',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _Destination(
      label: 'Projects',
      icon: Icons.folder_outlined,
      selectedIcon: Icons.folder_rounded,
    ),
    _Destination(
      label: 'Review',
      icon: Icons.fact_check_outlined,
      selectedIcon: Icons.fact_check_rounded,
    ),
    _Destination(
      label: 'Matrix',
      icon: Icons.table_chart_outlined,
      selectedIcon: Icons.table_chart_rounded,
    ),
    _Destination(
      label: 'Maps',
      icon: Icons.hub_outlined,
      selectedIcon: Icons.hub_rounded,
    ),
    _Destination(
      label: 'Account',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  Future<void> _createProject() async {
    final created = await Navigator.of(context).push<ResearchProject>(
      MaterialPageRoute(builder: (_) => const NewProjectScreen()),
    );
    if (!mounted || created == null) return;
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (userId != null) ref.invalidate(projectsProvider(userId));
    setState(() => _selectedIndex = 1);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Proyek berhasil disimpan di Supabase lokal.'),
      ),
    );
  }

  void _openProject(ResearchProject project) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProjectOverviewScreen(project: project),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authRepositoryProvider).currentUser;
    if (user == null) return const SizedBox.shrink();
    final email = user.email ?? 'Pengguna lokal';
    final metadataName = user.userMetadata?['display_name'] as String?;
    final displayName = metadataName?.trim().isNotEmpty == true
        ? metadataName!.trim()
        : email.split('@').first;

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        final pages = [
          DashboardScreen(
            userId: user.id,
            displayName: displayName,
            onNewProject: _createProject,
            onOpenProject: _openProject,
            onOpenReview: () => setState(() => _selectedIndex = 2),
          ),
          ProjectsScreen(
            userId: user.id,
            onNewProject: _createProject,
            onOpenProject: _openProject,
          ),
          const ReviewQueueScreen(),
          ComparativeMatrixScreen(userId: user.id),
          MapsScreen(userId: user.id),
          const AccountScreen(),
        ];

        return Scaffold(
          appBar: desktop
              ? null
              : AppBar(
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.white,
                  title: const BrandLockup(),
                  actions: [
                    IconButton(
                      tooltip: 'Notifikasi',
                      onPressed: () {},
                      icon: const Badge(
                        smallSize: 8,
                        child: Icon(Icons.notifications_outlined),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  bottom: const PreferredSize(
                    preferredSize: Size.fromHeight(1),
                    child: Divider(height: 1),
                  ),
                ),
          body: desktop
              ? Row(
                  children: [
                    _DesktopSidebar(
                      displayName: displayName,
                      email: email,
                      selectedIndex: _selectedIndex,
                      destinations: _destinations,
                      onSelected: (index) =>
                          setState(() => _selectedIndex = index),
                      onNewProject: _createProject,
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: pages,
                      ),
                    ),
                  ],
                )
              : IndexedStack(index: _selectedIndex, children: pages),
          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) =>
                      setState(() => _selectedIndex = index),
                  destinations: [
                    for (final destination in _destinations)
                      NavigationDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.selectedIcon),
                        label: destination.label,
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.displayName,
    required this.email,
    required this.selectedIndex,
    required this.destinations,
    required this.onSelected,
    required this.onNewProject,
  });

  final String displayName;
  final String email;
  final int selectedIndex;
  final List<_Destination> destinations;
  final ValueChanged<int> onSelected;
  final VoidCallback onNewProject;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 244,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 6, 8, 20),
                child: BrandLockup(),
              ),
              FilledButton.icon(
                onPressed: onNewProject,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Proyek baru'),
              ),
              const SizedBox(height: 18),
              for (var index = 0; index < destinations.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: _NavigationTile(
                    destination: destinations[index],
                    selected: index == selectedIndex,
                    onTap: () => onSelected(index),
                  ),
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Student Pilot',
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: 0,
                      minHeight: 6,
                      borderRadius: BorderRadius.all(Radius.circular(99)),
                    ),
                    SizedBox(height: 7),
                    Text(
                      '0 / 5 paper hari ini',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: CircleAvatar(
                  backgroundColor: AppColors.primarySoft,
                  child: Text(
                    displayName.isEmpty ? 'ML' : displayName[0].toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                title: Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationTile extends StatelessWidget {
  const _NavigationTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primarySoft : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                color: selected ? AppColors.primary : AppColors.muted,
                size: 21,
              ),
              const SizedBox(width: 12),
              Text(
                destination.label,
                style: TextStyle(
                  color: selected ? AppColors.primaryDark : AppColors.ink,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
