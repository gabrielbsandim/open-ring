import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class AiHistoryRowKeys {
  static const row = Key('ai_history_row');
}

/// The one way into readings from Histórico: only once the connection is
/// tested, or in demo mode, and never while availability is loading.
class AiHistoryRow extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(aiEnabledProvider)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final demo = ref.watch(demoModeProvider);
    final shown =
        demo ||
        switch (ref.watch(aiAvailabilityProvider).value) {
          AiAvailability.consentNeeded || AiAvailability.ready => true,
          _ => false,
        };
    if (!shown) return const SizedBox.shrink();
    final config = ref.watch(aiConfigProvider).value;
    final host = config?.normalizedUrl?.asciiHost;
    final detail = demo || host == null
        ? l10n.aiReadingSampleBy
        : '$host · ${config!.trimmedModel}';
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TileGroup(
        children: [
          SettingsTile(
            key: AiHistoryRowKeys.row,
            leading: const Icon(Icons.chat_bubble_outline_rounded),
            title: l10n.aiHistoryRow,
            detail: detail,
            chevron: true,
            onTap: () => unawaited(context.push(AppPaths.aiReadings)),
          ),
        ],
      ),
    );
  }
}
