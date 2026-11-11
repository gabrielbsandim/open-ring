import 'package:flutter/material.dart';
import 'package:open_ring/app/theme/app_colors.dart';

class AppPage extends StatelessWidget {
  const new({
    required this.title,
    required this.children,
    this.subtitle,
    this.titleTrailing,
    this.actions = const [],
    this.onRefresh,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? titleTrailing;
  final List<Widget> children;
  final List<Widget> actions;
  final RefreshCallback? onRefresh;

  // AppBar clamps its title's text scale, so the title lives in the scrolling
  // body where it can grow and wrap with the user's font size.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = subtitle;
    final refresh = onRefresh;
    final trailing = titleTrailing;
    final heading = Semantics(
      header: true,
      child: Text(title, style: theme.textTheme.headlineMedium),
    );
    final list = ListView(
      physics: refresh == null ? null : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        if (trailing == null) heading,
        if (trailing != null)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [heading, trailing],
          ),
        if (caption != null)
          Text(
            caption,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.of(context).textLabel,
            ),
          ),
        const SizedBox(height: 24),
        ...children,
      ],
    );
    return Scaffold(
      appBar: AppBar(actions: actions),
      body: SafeArea(
        child: refresh == null
            ? list
            : RefreshIndicator(onRefresh: refresh, child: list),
      ),
    );
  }
}
