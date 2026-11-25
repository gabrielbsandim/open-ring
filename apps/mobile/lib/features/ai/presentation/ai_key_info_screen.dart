import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class AiKeyInfoKeys {
  static const saved = Key('ai_key_info_saved');
  static const goesTo = Key('ai_key_info_goes_to');
  static const remove = Key('ai_key_info_remove');
}

class AiKeyInfoScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<AiKeyInfoScreen> createState() => _AiKeyInfoScreenState();
}

class _AiKeyInfoScreenState extends ConsumerState<AiKeyInfoScreen> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(aiConfigProvider).value;
    final on = ref.watch(aiEnabledProvider);
    return AppPage(
      title: l10n.aiKeyInfoTitle,
      subtitle: l10n.aiKeyInfoLead,
      children: config == null || !on ? const [] : _body(l10n, config),
    );
  }

  List<Widget> _body(AppLocalizations l10n, AiConfig config) {
    final lastFour = config.keyLastFour;
    final host = config.normalizedUrl?.asciiHost;
    final removable = lastFour != null && !ref.watch(demoModeProvider);
    return [
      if (lastFour != null)
        _line(
          Icons.key_rounded,
          l10n.aiConnectionKeySaved(lastFour.isEmpty ? 'hidden' : lastFour),
          key: AiKeyInfoKeys.saved,
        ),
      if (host != null)
        _line(
          Icons.call_made_rounded,
          l10n.aiKeyInfoGoesTo(host),
          key: AiKeyInfoKeys.goesTo,
        ),
      SectionHeader(l10n.aiKeyInfoStoredTitle),
      _line(Icons.lock_outline_rounded, l10n.aiKeyInfoStored1),
      _line(Icons.block_rounded, l10n.aiKeyInfoStored2),
      _line(Icons.cloud_off_rounded, l10n.aiKeyInfoStored3),
      _line(Icons.link_rounded, l10n.aiKeyInfoBound),
      _line(Icons.system_update_rounded, l10n.aiKeyInfoShorebird),
      if (removable) ...[
        const SizedBox(height: 24),
        OutlinedButton(
          key: AiKeyInfoKeys.remove,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: AppColors.of(context).heart,
          ),
          onPressed: _busy ? null : () => unawaited(_remove()),
          child: Text(l10n.aiKeyInfoRemove),
        ),
      ],
    ];
  }

  Widget _line(IconData icon, String text, {Key? key}) => Padding(
    key: key,
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.of(context).textLabel),
        const SizedBox(width: 12),
        Expanded(child: BodyText(text)),
      ],
    ),
  );

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await ref.read(aiConfigProvider.notifier).setApiKey('');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
