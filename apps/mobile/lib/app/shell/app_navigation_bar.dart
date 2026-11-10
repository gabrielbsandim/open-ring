import 'package:flutter/material.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/shell/app_tab_labels.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

// Material's NavigationBar clamps label text scale and has a fixed height, so
// this bar keeps icons fixed and lets labels scale, wrap and grow the bar.
class AppNavigationBar extends StatelessWidget {
  const new({required this.selectedIndex, required this.onSelected, super.key});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static Key destinationKey(AppTab tab) => Key('tab_${tab.name}');

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.navBar,
      shape: Border(top: BorderSide(color: colors.surfaceBorder)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final tab in AppTab.values)
                  Expanded(
                    child: _Destination(
                      key: destinationKey(tab),
                      tab: tab,
                      selected: tab.index == selectedIndex,
                      onTap: () => onSelected(tab.index),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Destination extends StatelessWidget {
  const new({
    required this.tab,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final foreground = selected ? colors.textPrimary : colors.textLabel;
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 32,
                    decoration: BoxDecoration(
                      color: selected ? colors.surfaceInner : null,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(tab.icon, size: 24, color: foreground),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tab.label(AppLocalizations.of(context)),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
