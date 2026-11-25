import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_report_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/ai_usage_summary.dart';
import 'package:open_ring/features/ai/presentation/ai_reading_sheets.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/presentation/module_widgets.dart';
import 'package:open_ring/features/open_score/presentation/day_score_receipt_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class AiModuleKeys {
  static const state = Key('ai_module_state');
  static const readings = Key('ai_module_readings');
  static const connection = Key('ai_module_connection');
  static const usage = Key('ai_module_usage');
  static const adds = Key('ai_module_adds');
  static const uses = Key('ai_module_uses');
  static const sends = Key('ai_module_sends');
  static const stores = Key('ai_module_stores');
  static const never = Key('ai_module_never');
  static const guide = Key('ai_module_guide');
  static const formula = Key('ai_module_formula');
  static const toggle = Key('ai_module_toggle');
}

class AiModuleScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<AiModuleScreen> createState() => _AiModuleScreenState();
}

class _AiModuleScreenState extends ConsumerState<AiModuleScreen> {
  var _toggling = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final on =
        ref.watch(enabledModulesProvider).value?.contains(ModuleId.ai) ?? false;
    final toggleAction = _toggling ? null : () => unawaited(_toggle(on: !on));
    return AppPage(
      title: l10n.moduleAiName,
      subtitle: l10n.moduleAiDetail,
      children: [
        ModuleStatePill(
          key: AiModuleKeys.state,
          on: on,
          label: on ? l10n.modulesOn : l10n.modulesOff,
        ),
        const SizedBox(height: 16),
        if (on) ...[_tiles(l10n), const SizedBox(height: cardGap)],
        ..._facts(l10n),
        DayScoreLink(
          key: AiModuleKeys.guide,
          title: l10n.aiGuideTitle,
          caption: l10n.moduleAiGuideCaption,
          path: AppPaths.settingsAiGuide,
          push: true,
        ),
        const SizedBox(height: cardGap),
        DayScoreLink(
          key: AiModuleKeys.formula,
          title: l10n.formulaLink,
          caption: l10n.moduleAiFormulaCaption,
          path: AppPaths.aiFormula,
          push: true,
        ),
        const SizedBox(height: 12),
        CaptionText(l10n.moduleBodyFoot),
        const SizedBox(height: 24),
        if (on)
          SecondaryButton(
            key: AiModuleKeys.toggle,
            label: l10n.moduleAiTurnOff,
            onPressed: toggleAction,
          ),
        if (!on)
          ActionButton(
            key: AiModuleKeys.toggle,
            label: l10n.moduleAiTurnOn,
            onPressed: toggleAction,
          ),
        const SizedBox(height: 8),
        CaptionText(
          on ? l10n.moduleAiTurnOffNote : l10n.moduleAiTurnOnNote,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  List<Widget> _facts(AppLocalizations l10n) {
    final cards = [
      (
        AiModuleKeys.adds,
        l10n.moduleBodyAddsTitle,
        Icons.check_rounded,
        [
          for (final item in const ['readings', 'goals', 'food', 'guide'])
            l10n.moduleAiAdds(item),
        ],
      ),
      (
        AiModuleKeys.uses,
        l10n.moduleOpenScoreUsesTitle,
        Icons.smartphone_rounded,
        [
          for (final item in const ['service', 'summary', 'internet'])
            l10n.moduleAiUses(item),
        ],
      ),
      (
        AiModuleKeys.sends,
        l10n.moduleAiSendsTitle,
        Icons.send_rounded,
        [
          for (final item in const ['summary', 'never', 'service'])
            l10n.moduleAiSends(item),
        ],
      ),
      (
        AiModuleKeys.stores,
        l10n.moduleBodyStoresTitle,
        Icons.receipt_long_rounded,
        [
          for (final item in const ['config', 'key', 'readings'])
            l10n.moduleAiStores(item, aiReportKeepCount, aiReportPayloadDays),
        ],
      ),
      (
        AiModuleKeys.never,
        l10n.moduleBodyNeverTitle,
        Icons.block_rounded,
        [
          for (final item in const [
            'today',
            'auto',
            'score',
            'unchecked',
            'words',
          ])
            l10n.moduleAiNever(item),
        ],
      ),
    ];
    return [
      for (final (key, title, icon, facts) in cards) ...[
        ModuleFactsCard(key: key, title: title, icon: icon, facts: facts),
        const SizedBox(height: cardGap),
      ],
    ];
  }

  Widget _tiles(AppLocalizations l10n) {
    final config = ref.watch(aiConfigProvider).value;
    final reports = ref.watch(aiRecentReportsProvider).value;
    final summary = reports == null
        ? null
        : aiUsageSummary(reports, ref.read(clockProvider)().toUtc());
    return TileGroup(
      children: [
        SettingsTile(
          key: AiModuleKeys.readings,
          leading: const Icon(Icons.chat_bubble_outline_rounded),
          title: l10n.aiReadingsTitle,
          detail: _readingsLine(l10n),
          chevron: true,
          onTap: () => unawaited(context.push(AppPaths.aiReadings)),
        ),
        SettingsTile(
          key: AiModuleKeys.connection,
          leading: const Icon(Icons.link_rounded),
          title: l10n.aiConnectionTitle,
          detail: _connectionLine(l10n, config),
          chevron: true,
          onTap: () => unawaited(context.push(AppPaths.settingsAiConnection)),
        ),
        SettingsTile(
          key: AiModuleKeys.usage,
          leading: const Icon(Icons.data_usage_rounded),
          title: l10n.moduleAiUsageTitle,
          detail: summary == null ? null : _usageLine(summary),
          chevron: true,
          onTap: summary == null
              ? null
              : () => unawaited(
                  showAiUsage30Sheet(
                    context,
                    summary,
                    cap: config?.monthlyTokenCap,
                  ),
                ),
        ),
      ],
    );
  }

  String? _readingsLine(AppLocalizations l10n) {
    if (ref.watch(demoModeProvider)) return l10n.aiReadingSampleBy;
    final latest = ref.watch(aiLatestReadingProvider);
    if (!latest.hasValue) return null;
    final report = latest.value;
    if (report == null) return l10n.moduleAiReadingsNone;
    final at = MetricFormat.of(context)
        .dayAndClock(report.createdAtUtc, Duration(minutes: report.offsetMin));
    // `weekly_review` gives the `weekly` select value of aiReadingKind.
    final kind = l10n.aiReadingKind(report.kind.split('_').first);
    return l10n.moduleAiReadingsLast(at, kind);
  }

  String? _connectionLine(AppLocalizations l10n, AiConfig? config) {
    final host = config?.normalizedUrl?.asciiHost ?? '';
    final model = config?.trimmedModel ?? '';
    final state = switch (ref.watch(aiAvailabilityProvider).value) {
      null => null,
      AiAvailability.off || AiAvailability.notConfigured => 'none',
      AiAvailability.notTested => 'untested',
      AiAvailability.consentNeeded || AiAvailability.ready => 'ready',
    };
    if (state == null) return null;
    return l10n.moduleAiConnection(state, host, model);
  }

  String _usageLine(AiUsageSummary summary) {
    final format = MetricFormat.of(context);
    final tokens = format.integer(summary.tokensIn + summary.tokensOut);
    return format.l10n.moduleAiUsage(summary.readings, tokens);
  }

  // Calls the module list directly until OfferedModule.ai exists (A14e),
  // so the module is not listed before the privacy text changes.
  Future<void> _toggle({required bool on}) async {
    if (_toggling) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final modules = ref.read(enabledModulesProvider.notifier);
    setState(() => _toggling = true);
    try {
      await (on ? modules.enable(ModuleId.ai) : modules.disable(ModuleId.ai));
    } on Object {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l10n.syncErrorSaving)));
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }
}
