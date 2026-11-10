import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/app_page.dart';

class PlaceholderView extends StatelessWidget {
  const new({
    required this.title,
    required this.message,
    required this.icon,
    required this.accent,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color accent;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppPage(
      title: title,
      actions: actions,
      children: [
        Icon(icon, size: 48, color: accent),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: AppColors.of(context).textSecondary,
          ),
        ),
      ],
    );
  }
}
