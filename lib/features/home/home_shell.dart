import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../ratings/rating_sheet.dart';

import '../communities/communities_tab.dart';
import '../events/events_tab.dart';
import '../profile/profile_tab.dart';
import '../trips/trips_tab.dart';
import 'map_tab.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Viagem acabou e falta avaliar? Pergunta quando a tela inicial estiver na frente.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(storeProvider).addListener(_maybeAskRatings);
      _maybeAskRatings();
    });
  }

  @override
  void dispose() {
    ref.read(storeProvider).removeListener(_maybeAskRatings);
    super.dispose();
  }

  void _maybeAskRatings() {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final store = ref.read(storeProvider);
    if (store.pendingRatings.any((p) => !store.skippedRatings.contains(p.bookingId))) {
      Future.microtask(() {
        if (mounted) askPendingRatings(context, ref);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [MapTab(), EventsTab(), TripsTab(), CommunitiesTab(), ProfileTab()],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF2C3A5C)))),
        child: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Início'),
          NavigationDestination(
              icon: Icon(Icons.local_activity_outlined), selectedIcon: Icon(Icons.local_activity), label: 'Eventos'),
          NavigationDestination(
              icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Viagens'),
          NavigationDestination(
              icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Comunidades'),
          NavigationDestination(
              icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
        ],
        ),
      ),
    );
  }
}
