import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_tab_labels.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class TabsShell extends StatelessWidget {
  const new({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _select(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _select,
        destinations: [
          for (final tab in AppTab.values)
            NavigationDestination(icon: Icon(tab.icon), label: tab.label(l10n)),
        ],
      ),
    );
  }
}
