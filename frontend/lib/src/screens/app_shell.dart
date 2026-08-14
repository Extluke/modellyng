import 'package:flutter/material.dart';

import '../models/research_models.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'account_screen.dart';
import 'dashboard_screen.dart';
import 'new_project_screen.dart';
import 'project_workspace_screen.dart';
import 'projects_screen.dart';
import 'review_queue_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
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
      label: 'Account',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  Future<void> _createProject() async {
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const NewProjectScreen()));
    if (!mounted || created != true) return;
    setState(() => _selectedIndex = 1);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Proyek dibuat. Job analisis demo telah masuk antrean.'),
      ),
    );
  }

  void _openProject(ResearchProject project) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProjectWorkspaceScreen(project: project),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        final pages = [
          DashboardScreen(
            onNewProject: _createProject,
            onOpenProject: _openProject,
            onOpenReview: () => setState(() => _selectedIndex = 2),
          ),
          ProjectsScreen(
            onNewProject: _createProject,
            onOpenProject: _openProject,
          ),
          const ReviewQueueScreen(),
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
    required this.selectedIndex,
    required this.destinations,
    required this.onSelected,
    required this.onNewProject,
  });

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
                      value: 0.62,
                      minHeight: 6,
                      borderRadius: BorderRadius.all(Radius.circular(99)),
                    ),
                    SizedBox(height: 7),
                    Text(
                      '186 / 300 halaman',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
                leading: CircleAvatar(
                  backgroundColor: AppColors.primarySoft,
                  child: Text(
                    'AS',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                title: Text(
                  'Aditya Saputra',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                subtitle: Text('Researcher', style: TextStyle(fontSize: 11)),
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
              if (destination.label == 'Review') ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.orangeSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '12',
                    style: TextStyle(
                      color: AppColors.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
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
