import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/format/metric_format.dart';
import 'package:open_ring/core/widgets/app_page.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/ai_report_providers.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/application/health_context_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_consent_scope.dart';
import 'package:open_ring/features/ai/domain/ai_reading.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_run_state.dart';
import 'package:open_ring/features/ai/domain/base_url_policy.dart';
import 'package:open_ring/features/ai/domain/health_context_assembly.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/presentation/ai_consent_sheet.dart';
import 'package:open_ring/features/ai/presentation/ai_reading_card.dart';
import 'package:open_ring/features/ai/presentation/ai_test_connection_sheet.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

class AiReadingsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<AiReadingsScreen> createState() => _AiReadingsScreenState();
}

class _AiReadingsScreenState extends ConsumerState<AiReadingsScreen> {
  AnalysisRunController? _run;
  AiAnalysisKind _kind = AiAnalysisKind.weeklyReview;
  bool _visible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A tab switch keeps this screen mounted offstage, which still leaves it.
    _visible = TickerMode.valuesOf(context).enabled;
    if (!_visible) _run?.cancel();
  }

  @override
  void dispose() {
    _run?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(analysisRunControllerProvider);
    _run = ref.read(analysisRunControllerProvider.notifier);
    ref.listen(analysisRunControllerProvider, (_, next) {
      if (next case AnalysisFailed(failure: RunConsentNeeded())) {
        unawaited(_read(_kind, ask: true));
      }
      if (next is AnalysisDone) ref.invalidate(aiLatestReadingProvider);
    });
    final on = ref.watch(aiEnabledProvider);
    final config = on ? ref.watch(aiConfigProvider).value : null;
    final busy = state is AnalysisSending || state is AnalysisValidating;
    return AppPage(
      title: l10n.aiReadingsTitle,
      subtitle: l10n.aiReadingsLead,
      children: [
        if (config?.normalizedUrl case final url?)
          ..._top(l10n, config!, url, busy: busy),
        if (on)
          ...switch (state) {
            AnalysisSending(receivedChars: final n) => [
              _sending(l10n, config, n),
            ],
            AnalysisValidating() => [_sending(l10n, config, null)],
            AnalysisDone(:final report) => [_ReadingView(report)],
            AnalysisFailed(:final failure) => [
              ..._failure(l10n, failure, config),
              ..._stored(),
            ],
            AnalysisIdle() => _stored(),
          },
      ],
    );
  }

  List<Widget> _top(
    AppLocalizations l10n,
    AiConfig config,
    NormalizedBaseUrl url, {
    required bool busy,
  }) => [
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(
          avatar: url.isCleartext
              ? Icon(
                  Icons.lock_open_rounded,
                  color: AppColors.of(context).heart,
                )
              : const Icon(Icons.lock_outline_rounded),
          label: Text(url.asciiHost),
        ),
        Chip(label: Text(config.trimmedModel)),
      ],
    ),
    const SizedBox(height: 16),
    Row(
      children: [
        Expanded(
          child: FilledButton(
            key: AiReadingKeys.weekly,
            onPressed: busy ? null : () => _tap(AiAnalysisKind.weeklyReview),
            child: Text(l10n.aiReadingKind('weekly')),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            key: AiReadingKeys.daily,
            onPressed: busy ? null : () => _tap(AiAnalysisKind.dailyReview),
            child: Text(l10n.aiReadingKind('daily')),
          ),
        ),
      ],
    ),
    TextButton(
      onPressed: busy
          ? null
          : () => unawaited(
              context.push(
                '${AppPaths.aiReadingsPreview}?kind=${_kindArg(_kind.wireName)}',
              ),
            ),
      child: Text(l10n.aiReadingSeeSent),
    ),
    const SizedBox(height: 8),
  ];

  void _tap(AiAnalysisKind kind) => unawaited(_read(kind));

  Future<void> _read(AiAnalysisKind kind, {bool ask = false}) async {
    setState(() => _kind = kind);
    final config = await ref.read(aiConfigProvider.future);
    final result = await ref.read(aiPayloadProvider(kind).future);
    final consent = await ref.read(aiConsentProvider.future);
    final run = _run;
    if (!mounted || !_visible || run == null) return;
    final uncovered = switch (result) {
      AiPayloadReady(:final payload)
          when ask || !aiConsentCoversPayload(consent, config, payload) =>
        payload,
      _ => null,
    };
    final granted =
        uncovered == null ||
        await showAiConsentSheet(
          context,
          config: config,
          payload: uncovered,
          previous: consent,
        );
    if (!granted || !mounted || !_visible) return;
    await run.send(kind: kind);
  }

  List<Widget> _stored() => [
    if (ref.watch(aiLatestReadingProvider).value case final report?)
      _ReadingView(report),
  ];

  Widget _sending(AppLocalizations l10n, AiConfig? config, int? chars) {
    final host = config?.normalizedUrl?.asciiHost ?? '';
    final limit = (config?.maxOutputTokens ?? aiDefaultOutputTokens) * 4;
    return MetricCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(
            l10n.aiReadingKind(_kindArg(_kind.wireName)),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          BodyText(
            chars == null
                ? l10n.aiReadingChecking
                : l10n.aiReadingReceiving(
                    host,
                    MetricFormat.of(context).integer(chars),
                  ),
          ),
          LinearProgressIndicator(
            value: chars == null ? 1 : math.min(0.95, chars / limit),
          ),
          CaptionText(l10n.aiReadingSendingNote),
          OutlinedButton(
            key: AiReadingKeys.cancel,
            onPressed: chars == null ? null : _run?.cancel,
            child: Text(l10n.settingsDeleteCancel),
          ),
        ],
      ),
    );
  }

  List<Widget> _failure(
    AppLocalizations l10n,
    AnalysisRunFailure failure,
    AiConfig? config,
  ) {
    final url = config?.normalizedUrl;
    final line = switch (failure) {
      RunModelFailure(failure: AnalysisFailure(:final kind))
          when kind == AnalysisFailureKind.cancelled =>
        l10n.aiReadingCancelled,
      RunModelFailure(:final failure) when url != null && config != null =>
        aiTestFailureMessage(
          l10n,
          failure,
          host: url.asciiHost,
          model: config.trimmedModel,
          local: config.preset.isLocal || url.isCleartext,
        ),
      RunNotEnoughData(:final days) => l10n.aiPreviewNotEnough(days),
      _ => null,
    };
    final details = switch (failure) {
      RunModelFailure(:final failure)
          when failure.kind != AnalysisFailureKind.cancelled =>
        aiTestFailureDetails(failure, null),
      RunCeilingReached(:final used, :final cap) => '$used / $cap',
      RunUnexpected(:final error) => '${error.runtimeType}',
      _ => null,
    };
    if (line == null && details == null) return const [];
    return [
      MetricCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (line != null) BodyText(line),
            if (details != null)
              CaptionText('${l10n.aiErrorDetails}: $details'),
          ],
        ),
      ),
      const SizedBox(height: 12),
    ];
  }
}

// `weekly_review` gives the `weekly` select value of the ARB messages.
String _kindArg(String wire) => wire.split('_').first;

class _ReadingView extends StatelessWidget {
  const new(this.report);

  final AiReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reading = AiReading.fromReport(report);
    final host = Uri.tryParse(report.providerHost)?.host ?? '';
    final at = MetricFormat.of(context)
        .dayAndClock(report.createdAtUtc, Duration(minutes: report.offsetMin));
    final dropped = report.droppedCards;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetricCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              Text(
                l10n.aiReadingKind(_kindArg(report.kind)),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              CaptionText(at),
              CaptionText(l10n.aiReadingByLine(report.model, host)),
              if (reading.summary.isNotEmpty) BodyText(reading.summary),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final card in reading.cards)
          AiReadingCard(card: card, facts: reading.facts, model: report.model),
        if (dropped > 0)
          MetricCard(
            key: AiReadingKeys.dropped,
            child: BodyText(
              l10n.aiReadingDropped(dropped, reading.cards.length + dropped),
            ),
          ),
        const SizedBox(height: 12),
        CaptionText(l10n.aiReadingFooter),
      ],
    );
  }
}
