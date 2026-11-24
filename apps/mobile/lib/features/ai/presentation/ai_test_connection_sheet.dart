import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/app/theme/app_colors.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/base_url_policy.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/l10n/generated/app_localizations.dart';

enum AiTestStepState { pending, running, ok, failed }

abstract final class AiTestKeys {
  static const sheet = Key('ai_test_sheet');
  static const message = Key('ai_test_message');
  static const details = Key('ai_test_details');
  static const ready = Key('ai_test_ready');
  static const again = Key('ai_test_again');

  static Key step(int index, AiTestStepState state) =>
      Key('ai_test_step_${index}_${state.name}');
}

const int _stepCount = 4;
const int _keyStep = 1;
const int _modelStep = 2;
const int _formatStep = 3;

/// The 2.3 line for a failure the test can hit, or null for the kinds the
/// reading flow words, which then show only their details.
String? aiTestFailureMessage(
  AppLocalizations l10n,
  AnalysisFailure failure, {
  required String host,
  required String model,
  required bool local,
}) {
  final unreachable =
      failure.kind == AnalysisFailureKind.unreachable ||
      failure.timeoutStage == TimeoutStage.connect;
  if (unreachable) {
    return local
        ? l10n.aiErrorUnreachableLocal(host)
        : l10n.aiErrorUnreachable(host);
  }
  return switch (failure.kind) {
    AnalysisFailureKind.tls => l10n.aiErrorTls(host),
    AnalysisFailureKind.redirect => l10n.aiErrorRedirect(host),
    AnalysisFailureKind.cleartextBlocked => l10n.aiConnectionRefusalCleartext(
      host,
    ),
    AnalysisFailureKind.unauthorized => l10n.aiErrorKey,
    AnalysisFailureKind.modelNotFound => l10n.aiErrorModelNotFound(model),
    _ => null,
  };
}

String aiTestFailureDetails(AnalysisFailure failure, String? apiKey) => [
  if (failure.statusCode != null) '${failure.statusCode}',
  if (failure.detail.isNotEmpty) scrubApiKey(failure.detail, apiKey),
].join(' · ');

String aiTestFormatLine(AppLocalizations l10n, AiJsonMode mode) =>
    switch (mode) {
      AiJsonMode.jsonSchema => l10n.aiTestFormatSchema,
      AiJsonMode.jsonObject => l10n.aiTestFormatObject,
      AiJsonMode.none => l10n.aiTestFormatText,
    };

/// A status from the model list means the host answered, so the stop is
/// the key step; a redirect never counts as reaching the host.
int _failedStep(AnalysisFailure failure, {required bool reached}) =>
    switch (failure.kind) {
      AnalysisFailureKind.unauthorized ||
      AnalysisFailureKind.forbidden => _keyStep,
      _ when reached => _modelStep,
      AnalysisFailureKind.redirect => 0,
      _ when failure.statusCode != null => _keyStep,
      _ => 0,
    };

class AiTestConnectionSheet extends ConsumerStatefulWidget {
  const new({required this.config, super.key});

  final AiConfig config;

  @override
  ConsumerState<AiTestConnectionSheet> createState() =>
      _AiTestConnectionSheetState();
}

class _AiTestConnectionSheetState extends ConsumerState<AiTestConnectionSheet> {
  var _cancel = Completer<void>();
  var _running = true;
  var _reached = false;
  ConnectionProbe? _result;
  AnalysisFailure? _failure;
  String? _apiKey;

  NormalizedBaseUrl get _url => widget.config.normalizedUrl!;

  @override
  void initState() {
    super.initState();
    unawaited(_probe());
  }

  @override
  void dispose() {
    if (!_cancel.isCompleted) _cancel.complete();
    super.dispose();
  }

  void _again() {
    setState(() {
      _running = true;
      _reached = false;
      _result = null;
      _failure = null;
    });
    unawaited(_probe());
  }

  Future<void> _probe() async {
    final cancel = _cancel = Completer<void>();
    final config = widget.config;
    final controller = ref.read(aiConfigProvider.notifier);
    final clock = ref.read(clockProvider);
    final factory = ref.read(analysisModelFactoryProvider);
    final secrets = ref.read(secretStoreProvider);
    try {
      _apiKey = await secrets.read(aiApiKeySecretName);
      final model = await factory(config);
      final result = await model.probe(
        cancel: cancel.future,
        onReached: _markReached,
      );
      await controller.recordTest(
        hostKey: _url.hostKey,
        model: config.trimmedModel,
        profile: result.profile,
        at: clock(),
      );
      _finish(result: result);
    } on AnalysisFailure catch (failure) {
      _finish(failure: failure);
    } on Object catch (error) {
      _finish(
        failure: AnalysisFailure(
          kind: AnalysisFailureKind.unreadable,
          detail: '$error',
        ),
      );
    }
  }

  void _markReached() {
    if (mounted) setState(() => _reached = true);
  }

  void _finish({ConnectionProbe? result, AnalysisFailure? failure}) {
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
      _failure = failure;
    });
  }

  int get _doneSteps {
    final failure = _failure;
    if (_result != null) return _stepCount;
    if (failure != null) return _failedStep(failure, reached: _reached);
    return _reached ? _modelStep : 0;
  }

  AiTestStepState _stateOf(int index) {
    final done = _doneSteps;
    if (index < done) return AiTestStepState.ok;
    if (index > done) return AiTestStepState.pending;
    if (_failure != null) return AiTestStepState.failed;
    return _running ? AiTestStepState.running : AiTestStepState.pending;
  }

  String? _subtitle(AppLocalizations l10n, int index, AiTestStepState state) {
    final failure = _failure;
    final mode = _result?.profile.jsonMode;
    if (state == AiTestStepState.failed && failure != null) {
      return aiTestFailureMessage(
        l10n,
        failure,
        host: _url.asciiHost,
        model: widget.config.trimmedModel,
        local: widget.config.preset.isLocal || _url.isCleartext,
      );
    }
    if (index != _formatStep || mode == null) return null;
    return aiTestFormatLine(l10n, mode);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final host = _url.asciiHost;
    final labels = [
      l10n.aiTestStepReach(host),
      l10n.aiTestStepKey,
      l10n.aiTestStepModel,
      l10n.aiTestStepFormat,
    ];
    return SafeArea(
      child: SingleChildScrollView(
        key: AiTestKeys.sheet,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.aiTestButton,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 4),
            BodyText(l10n.aiTestNoData),
            const SizedBox(height: 8),
            CaptionText('$host · ${widget.config.trimmedModel}'),
            const SizedBox(height: 12),
            for (var i = 0; i < _stepCount; i++)
              _step(l10n, i, labels[i], _stateOf(i)),
            ..._outcome(l10n),
          ],
        ),
      ),
    );
  }

  Widget _step(
    AppLocalizations l10n,
    int index,
    String label,
    AiTestStepState state,
  ) {
    final subtitle = _subtitle(l10n, index, state);
    return Padding(
      key: AiTestKeys.step(index, state),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepIcon(state),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BodyText(label),
                if (subtitle != null)
                  CaptionText(
                    key: state == AiTestStepState.failed
                        ? AiTestKeys.message
                        : null,
                    subtitle,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepIcon(AiTestStepState state) {
    final colors = AppColors.of(context);
    final (icon, color) = switch (state) {
      AiTestStepState.pending => (
        Icons.radio_button_unchecked_rounded,
        colors.textLabel,
      ),
      AiTestStepState.running => (
        Icons.hourglass_top_rounded,
        colors.textPrimary,
      ),
      AiTestStepState.ok => (Icons.check_circle_rounded, colors.activity),
      AiTestStepState.failed => (Icons.cancel_rounded, colors.heart),
    };
    return Icon(icon, size: 22, color: color);
  }

  List<Widget> _outcome(AppLocalizations l10n) {
    if (_running) return const [];
    final failure = _failure;
    final details = failure == null
        ? ''
        : aiTestFailureDetails(failure, _apiKey);
    return [
      const SizedBox(height: 12),
      if (failure == null) BodyText(key: AiTestKeys.ready, l10n.aiTestReady),
      if (details.isNotEmpty) ...[
        Text(
          l10n.aiErrorDetails,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        CaptionText(key: AiTestKeys.details, details),
      ],
      const SizedBox(height: 16),
      OutlinedButton(
        key: AiTestKeys.again,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: _again,
        child: Text(l10n.aiTestAgain),
      ),
    ];
  }
}
