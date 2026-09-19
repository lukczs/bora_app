import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../communities/communities_tab.dart';
import '../profile/profile_tab.dart';
import '../trips/trips_tab.dart';
import 'map_tab.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [MapTab(), TripsTab(), CommunitiesTab(), ProfileTab()],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.surface,
        indicatorColor: const Color(0x3322C55E),
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Início'),
          NavigationDestination(
              icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Viagens'),
          NavigationDestination(
              icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Comunidades'),
          NavigationDestination(
              icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}
