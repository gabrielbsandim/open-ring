import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/shell/app_navigation_bar.dart';
import 'package:open_ring/features/demo/presentation/demo_banner.dart';

class TabsShell extends StatelessWidget {
  const new({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _select(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DemoBanner(),
          AppNavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onSelected: _select,
          ),
        ],
      ),
    );
  }
}
