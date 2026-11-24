import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_ring/app/router/app_routes.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
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
import 'package:open_ring/features/ai/domain/ai_usage_summary.dart';
import 'package:open_ring/features/ai/domain/analysis_run_state.dart';
import 'package:open_ring/features/ai/domain/base_url_policy.dart';
import 'package:open_ring/features/ai/domain/health_context_assembly.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/presentation/ai_consent_sheet.dart';
import 'package:open_ring/features/ai/presentation/ai_failure_message.dart';
import 'package:open_ring/features/ai/presentation/ai_raw_text_sheet.dart';
import 'package:open_ring/features/ai/presentation/ai_reading_card.dart';
import 'package:open_ring/features/ai/presentation/ai_reading_sheets.dart';
import 'package:open_ring/features/settings/presentation/settings_widgets.dart';
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
  AiReport? _picked;
  ({bool force, int? maxOutput}) _options = (force: false, maxOutput: null);

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
      if (next is AnalysisDone || next is AnalysisFailed) {
        ref.invalidate(aiRecentReportsProvider);
      }
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
            AnalysisDone(:final report) => _stored(l10n, report),
            AnalysisFailed() => [
              ..._failure(l10n, state, config),
              ..._stored(l10n, null),
            ],
            AnalysisIdle() => _stored(l10n, null),
          },
        if (on && !busy) ..._usage30(l10n, config),
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

  // A consent race reopens the sheet with `ask`, and the resend after Allow
  // keeps the options of the tap that started it.
  Future<void> _read(
    AiAnalysisKind kind, {
    bool ask = false,
    bool force = false,
    int? maxOutput,
  }) async {
    if (!ask) _options = (force: force, maxOutput: maxOutput);
    setState(() {
      _kind = kind;
      _picked = null;
    });
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
    await run.send(
      kind: kind,
      force: _options.force,
      maxOutputTokens: _options.maxOutput,
    );
  }

  List<Widget> _stored(AppLocalizations l10n, AiReport? done) {
    final shown = _picked ?? done ?? ref.watch(aiLatestReadingProvider).value;
    final earlier = [
      for (final r in ref.watch(aiHostReportsProvider).value ?? <AiReport>[])
        if (_identity(r) != _identity(shown)) r,
    ];
    final fmt = MetricFormat.of(context);
    return [
      if (shown != null && aiNoMatch(shown))
        ..._noMatch(l10n, shown)
      else if (shown != null)
        _ReadingView(shown),
      if (earlier.isNotEmpty) SectionHeader(l10n.aiReadingsEarlier),
      for (final r in earlier)
        SettingsTile(
          key: AiReadingKeys.earlier(r.createdAtUtc),
          leading: r.status == AiReportStatus.done
              ? null
              : const Icon(Icons.error_outline_rounded),
          title: l10n.aiReadingKind(_kindArg(r.kind)),
          detail: fmt.dayAndClock(
            r.createdAtUtc,
            Duration(minutes: r.offsetMin),
          ),
          value: switch (r.status) {
            AiReportStatus.done => l10n.aiReadingCards(
              AiReading.fromReport(r).cards.length,
            ),
            AiReportStatus.cancelled => l10n.aiReadingFailedRow('cancelled'),
            AiReportStatus.failed => l10n.aiReadingFailedRow('failed'),
          },
          onTap: r.status == AiReportStatus.done
              ? () => setState(() => _picked = r)
              : null,
        ),
    ];
  }

  List<Widget> _usage30(AppLocalizations l10n, AiConfig? config) {
    final reports = ref.watch(aiRecentReportsProvider).value;
    if (reports == null) return const [];
    final summary = aiUsageSummary(reports, ref.read(clockProvider)().toUtc());
    return [
      const SizedBox(height: 12),
      SettingsTile(
        key: AiReadingKeys.usage30,
        title: l10n.aiUsage30Title(summary.readings),
        chevron: true,
        onTap: () => unawaited(
          showAiUsage30Sheet(context, summary, cap: config?.monthlyTokenCap),
        ),
      ),
    ];
  }

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
    AnalysisFailed failed,
    AiConfig? config,
  ) {
    if (config == null) return const [];
    final line = aiFailureMessage(l10n, failed.failure, config);
    if (line == null) return const [];
    final raw = failed.report?.rawText == null ? null : failed.report;
    final actions = aiFailureActions(
      failed.failure,
      canRetryLarger: failed.canRetryLarger,
      hasRaw: raw != null,
    );
    final larger = aiLargerOutputTokens(config.maxOutputTokens);
    return _errorCard(l10n, line, aiFailureDetails(failed.failure), [
      for (final a in actions)
        switch (a) {
          AiFailureAction.retry => _button(
            a,
            l10n.syncRetry,
            () => _again(_kind),
          ),
          AiFailureAction.connection => _button(
            a,
            l10n.aiGuideOpen,
            () => context.go(AppPaths.settingsAiConnection),
          ),
          AiFailureAction.larger => _button(
            a,
            l10n.aiRetryLarger,
            () => _again(_kind, maxOutput: larger),
          ),
          AiFailureAction.raw => _button(
            a,
            l10n.aiShowRaw('raw'),
            () => _showRaw(raw),
          ),
        },
    ]);
  }

  List<Widget> _noMatch(AppLocalizations l10n, AiReport report) {
    final kind = AiAnalysisKind.values.firstWhere(
      (k) => k.wireName == report.kind,
      orElse: () => _kind,
    );
    return _errorCard(
      l10n,
      l10n.aiErrorNoMatch,
      l10n.aiDroppedTitle(report.droppedCards),
      [
        if (report.rawText != null)
          _button(
            AiFailureAction.raw,
            l10n.aiShowRaw('unverified'),
            () => _showRaw(report),
          ),
        _button(AiFailureAction.retry, l10n.syncRetry, () => _again(kind)),
      ],
    );
  }

  // Through `_read`, so the consent gate runs before the one send.
  void _again(AiAnalysisKind kind, {int? maxOutput}) =>
      unawaited(_read(kind, force: true, maxOutput: maxOutput));

  void _showRaw(AiReport? report) {
    if (report == null) return;
    unawaited(
      showAiRawTextSheet(
        context,
        report,
        replyLanguage: ref.read(aiReplyLanguageProvider),
      ),
    );
  }

  Widget _button(
    AiFailureAction action,
    String label,
    VoidCallback onPressed,
  ) => OutlinedButton(
    key: AiReadingKeys.action(action),
    onPressed: onPressed,
    child: Text(label),
  );

  List<Widget> _errorCard(
    AppLocalizations l10n,
    String line,
    String? details,
    List<Widget> buttons,
  ) => [
    MetricCard(
      key: AiReadingKeys.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              Expanded(child: BodyText(line)),
            ],
          ),
          if (details != null) CaptionText('${l10n.aiErrorDetails}: $details'),
          if (buttons.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: buttons),
        ],
      ),
    ),
    const SizedBox(height: 12),
  ];
}

// The store keeps milliseconds while the run state holds the clock's
// microseconds, and only stored copies carry an id.
(int?, String?) _identity(AiReport? r) =>
    (r?.createdAtUtc.millisecondsSinceEpoch, r?.kind);

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
            onTap: () =>
                unawaited(showAiDroppedSheet(context, reading, dropped)),
            child: BodyText(
              l10n.aiReadingDropped(dropped, reading.cards.length + dropped),
            ),
          ),
        SettingsTile(
          key: AiReadingKeys.usage,
          title: l10n.aiUsageThis,
          chevron: true,
          onTap: () => unawaited(showAiUsageSheet(context, report)),
        ),
        if (report.payloadJson != null)
          SettingsTile(
            key: AiReadingKeys.sent,
            title: l10n.aiReadingSent,
            chevron: true,
            onTap: () => unawaited(
              context.push(AppPaths.aiReadingsPreview, extra: report),
            ),
          ),
        const SizedBox(height: 12),
        CaptionText(l10n.aiReadingFooter),
      ],
    );
  }
}
