import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/core/widgets/state_views.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/application/vision_probe_runner.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_run_state.dart';
import 'package:open_ring/features/ai/domain/meal_photo_result.dart';
import 'package:open_ring/features/ai/presentation/ai_failure_message.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/food/application/meal_analysis_providers.dart';
import 'package:open_ring/features/food/application/meal_analysis_queue.dart';
import 'package:open_ring/features/food/application/meal_analysis_view.dart';
import 'package:open_ring/features/food/domain/meal_analysis.dart';
import 'package:open_ring/features/food/presentation/meal_analyze_flow.dart';
import 'package:open_ring/features/food/presentation/meal_items_card.dart';
import 'package:open_ring/features/food/presentation/meal_keep_switch.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

abstract final class MealAnalysisKeys {
  static const section = Key('meal_ai_section');
  static Key view(MealAnalysisViewKind kind) =>
      Key('meal_ai_view_${kind.name}');
  static const sample = Key('meal_ai_sample');
  static const analyze = Key('meal_ai_analyze_this');
  static const cancel = Key('meal_ai_cancel');
  static const retry = Key('meal_ai_retry');
  static const again = Key('meal_ai_again');
  static const link = Key('meal_ai_link');
  static const ceiling = Key('meal_ai_ceiling');
  static const confirmAll = Key('meal_ai_confirm_all');
}

final FutureProvider<int> _monthTokensProvider =
    FutureProvider.autoDispose<int>(
      (ref) => ref
          .read(aiRunMarkerStoreProvider)
          .monthTokens(aiMonthKey(ref.read(clockProvider)())),
    );

/// The photo analysis card of one meal; the screen builds it only with AI and
/// Food on and a photo on the meal.
class MealAnalysisSection extends ConsumerWidget {
  const new({
    required this.mealId,
    this.pending = const {},
    this.onConfirmAll,
    super.key,
  });

  final int mealId;

  /// The suggestions of the done row the person has not confirmed yet.
  final Set<Object> pending;
  final VoidCallback? onConfirmAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(aiConfigProvider).value;
    final rows = ref.watch(mealAnalysesProvider(mealId)).value;
    final keep = ref.watch(mealKeepOnPhoneProvider(mealId)).value;
    if (config == null || rows == null || keep == null) {
      return const SizedBox.shrink();
    }
    final queue = ref.watch(mealAnalysisQueueProvider);
    final view = mealAnalysisViewOf(
      rows.firstOrNull,
      keep: keep,
      pause: ref.watch(aiPhotoQueuePauseProvider).value,
      sendingId: queue.sendingId,
      capReached: queue.capReached,
      demo: ref.watch(demoModeProvider),
      closed: ref.watch(mealPhotoGateProvider).value,
    );
    final l10n = AppLocalizations.of(context);
    final host = config.normalizedUrl?.asciiHost ?? '';
    return MetricCard(
      key: MealAnalysisKeys.section,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.foodAiSectionTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              if (host.isNotEmpty) CaptionText(host),
            ],
          ),
          const SizedBox(height: 8),
          Column(
            key: MealAnalysisKeys.view(view.kind),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _body(context, ref, l10n, config, view),
          ),
        ],
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    AiConfig config,
    MealAnalysisView view,
  ) {
    final queue = ref.read(mealAnalysisQueueProvider.notifier);
    final host = config.normalizedUrl?.asciiHost ?? config.baseUrl;
    void analyze() => unawaited(analyzeMealPhotos(context, ref, [mealId]));
    Widget cancel(MealAnalysis row) => _button(
      MealAnalysisKeys.cancel,
      l10n.settingsDeleteCancel,
      () => unawaited(queue.cancel(row.id)),
    );
    return switch ((view.kind, view.row)) {
      (MealAnalysisViewKind.demo, _) => [
        _Notice(Icons.info_outline_rounded, l10n.aiSampleSummary),
        const SizedBox(height: 10),
        _sample(l10n),
      ],
      (MealAnalysisViewKind.kept, _) => [
        _Notice(Icons.lock_outline_rounded, l10n.foodAiKept),
        MealKeepOnPhoneSwitch(mealId: mealId),
      ],
      (MealAnalysisViewKind.none, _) => [
        BodyText(l10n.foodAiIntro),
        const SizedBox(height: 12),
        ActionButton(
          buttonKey: MealAnalysisKeys.analyze,
          label: l10n.foodAiAnalyzeThis,
          onPressed: analyze,
        ),
        MealKeepOnPhoneSwitch(mealId: mealId),
      ],
      (_, null) => const [],
      (MealAnalysisViewKind.queued, final row?) => [
        _Notice(Icons.schedule_rounded, l10n.foodAiWaiting),
        if (view.capReached) _Ceiling(cap: config.monthlyTokenCap ?? 0),
        cancel(row),
      ],
      (MealAnalysisViewKind.paused || MealAnalysisViewKind.closed, _) =>
        _blocked(context, l10n, config, view),
      (MealAnalysisViewKind.sending, final row?) => [
        _Notice(Icons.send_outlined, l10n.foodAiSending(host)),
        cancel(row),
        const SizedBox(height: 8),
        CaptionText(l10n.foodAiMayBill),
      ],
      (MealAnalysisViewKind.done, final row?) => [
        CaptionText(_tagged(context, l10n, row)),
        const SizedBox(height: 10),
        if (pending.isEmpty)
          BodyText(l10n.foodAiChecked)
        else ...[
          BodyText(l10n.foodAiSuggestedHint),
          _button(
            MealAnalysisKeys.confirmAll,
            l10n.foodAiConfirmAll(pending.length),
            onConfirmAll,
          ),
        ],
        if (ref.watch(mealPhotoItemsEnabledProvider) && _hasItems(row))
          MealItemsCard(key: ValueKey(row.id), row: row),
      ],
      (MealAnalysisViewKind.notFood, _) => [
        _Notice(Icons.no_food_outlined, l10n.foodAiNotFood),
      ],
      (
        MealAnalysisViewKind.rejected || MealAnalysisViewKind.failed,
        final row?,
      ) =>
        [
          _Notice(
            Icons.warning_amber_rounded,
            view.kind == MealAnalysisViewKind.rejected
                ? l10n.foodAiRejected
                : _failed(l10n, config, view, row),
          ),
          _button(
            MealAnalysisKeys.retry,
            l10n.foodRetry,
            () => unawaited(queue.retry(row.id)),
          ),
        ],
      (MealAnalysisViewKind.skipped, _) => [
        _Notice(Icons.block_rounded, l10n.foodAiSkipped(view.reason)),
        _button(MealAnalysisKeys.again, l10n.foodAiAnalyzeAgain, analyze),
      ],
    };
  }

  List<Widget> _blocked(
    BuildContext context,
    AppLocalizations l10n,
    AiConfig config,
    MealAnalysisView view,
  ) {
    final model = aiPhotoTarget(config);
    final photos = (l10n.foodAiOpenPhotos, AppPaths.settingsAiPhotos);
    final (line, (label, path)) = switch ((view.kind, view.reason)) {
      (MealAnalysisViewKind.paused, _) => (
        l10n.foodAiPaused(view.reason),
        photos,
      ),
      (_, 'visionUntested') => (
        l10n.aiPhotosVisionState('unknown', model),
        photos,
      ),
      (_, 'visionNo') => (l10n.foodAiProbeTextOnly(model), photos),
      _ => (
        l10n.foodAiUnavailable,
        (l10n.aiGuideOpen, AppPaths.settingsAiConnection),
      ),
    };
    return [
      _Notice(Icons.pause_circle_outline_rounded, line),
      _button(
        MealAnalysisKeys.link,
        label,
        () => unawaited(GoRouter.maybeOf(context)?.push(path)),
      ),
    ];
  }

  // An answer with items keeps the card after the last one is removed.
  static bool _hasItems(MealAnalysis row) =>
      row.items.isNotEmpty || (row.suggestion?.items.isNotEmpty ?? false);

  Widget _sample(AppLocalizations l10n) => Wrap(
    key: MealAnalysisKeys.sample,
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final tag in [l10n.foodKindMain, l10n.foodProtein, l10n.foodVegSome])
        Chip(label: Text(tag)),
    ],
  );

  String _tagged(
    BuildContext context,
    AppLocalizations l10n,
    MealAnalysis row,
  ) {
    final date = MaterialLocalizations.of(context)
        .formatMediumDate(row.updatedAt.toLocal());
    final level = (row.confidence ?? MealPhotoConfidence.low).name;
    return l10n.foodAiBy(row.target.model, date, l10n.aiConfidenceLevel(level));
  }

  // The A9 line names the model, so it is the one this row was sent to.
  String _failed(
    AppLocalizations l10n,
    AiConfig config,
    MealAnalysisView view,
    MealAnalysis row,
  ) {
    final kind = view.failure;
    if (kind == null) return l10n.foodAiStopped(view.reason);
    final failure = RunModelFailure(AnalysisFailure(kind: kind));
    final line = aiFailureMessage(
      l10n,
      failure,
      config.copyWith(model: row.target.model),
    );
    return line ?? l10n.foodAiStopped(view.reason);
  }
}

Widget _button(Key key, String label, VoidCallback? onPressed) => Padding(
  padding: const EdgeInsets.only(top: 12),
  child: SecondaryButton(buttonKey: key, label: label, onPressed: onPressed),
);

class _Ceiling extends ConsumerWidget {
  const new({required this.cap});

  final int cap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final used = ref.watch(_monthTokensProvider).value ?? cap;
    final l10n = AppLocalizations.of(context);
    return Padding(
      key: MealAnalysisKeys.ceiling,
      padding: const EdgeInsets.only(top: 8),
      child: CaptionText(l10n.aiErrorCeiling(used, cap)),
    );
  }
}

class _Notice extends StatelessWidget {
  const new(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceInner,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colors.textSecondary),
          const SizedBox(width: 10),
          Expanded(child: BodyText(text)),
        ],
      ),
    );
  }
}
