import 'package:flutter/material.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/widgets/open_ring_logo.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

extension AppTabLabels on AppTab {
  String label(AppLocalizations l10n) => switch (this) {
    AppTab.today => l10n.tabToday,
    AppTab.sleep => l10n.tabSleep,
    AppTab.heart => l10n.tabHeart,
    AppTab.activity => l10n.tabActivity,
    AppTab.ring => l10n.tabRing,
  };

  Widget icon({required double size, required Color color}) => switch (this) {
    AppTab.today => Icon(Icons.today_rounded, size: size, color: color),
    AppTab.sleep => Icon(Icons.bedtime_rounded, size: size, color: color),
    AppTab.heart => Icon(Icons.favorite_rounded, size: size, color: color),
    AppTab.activity => Icon(
      Icons.directions_walk_rounded,
      size: size,
      color: color,
    ),
    AppTab.ring => OpenRingMark(size: size, color: color),
  };
}
