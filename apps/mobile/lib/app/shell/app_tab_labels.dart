import 'package:flutter/material.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

extension AppTabLabels on AppTab {
  String label(AppLocalizations l10n) => switch (this) {
    AppTab.today => l10n.tabToday,
    AppTab.sleep => l10n.tabSleep,
    AppTab.heart => l10n.tabHeart,
    AppTab.activity => l10n.tabActivity,
    AppTab.ring => l10n.tabRing,
  };

  IconData get icon => switch (this) {
    AppTab.today => Icons.today_rounded,
    AppTab.sleep => Icons.bedtime_rounded,
    AppTab.heart => Icons.favorite_rounded,
    AppTab.activity => Icons.directions_walk_rounded,
    AppTab.ring => Icons.radio_button_unchecked_rounded,
  };
}
