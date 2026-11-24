import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/ai_report_providers.dart';
import 'package:open_ring/features/ai/application/health_context_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_output_extractor.dart';
import 'package:open_ring/features/ai/domain/ai_prompt.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/ai_report_validator.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/analysis_run_state.dart';
import 'package:open_ring/features/ai/domain/health_context_assembly.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/domain/openai_wire_codec.dart';
import 'package:open_ring/features/ai/domain/sample_analysis_model.dart';
import 'package:open_ring/features/ai/domain/secret_store.dart';
import 'package:open_ring/features/ai/infrastructure/http_analysis_model.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';

const int aiAutoRetryMaxSeconds = 20;
const Duration aiProgressInterval = Duration(milliseconds: 250);

const _cancelled = AnalysisFailure(kind: AnalysisFailureKind.cancelled);
const _unreadable = AnalysisFailure(kind: AnalysisFailureKind.unreadable);

// A null retry falls back to Riverpod's default, which retries; a paid
// request must never be resent by the framework.
Duration? _noRetry(int _, Object _) => null;

typedef AnalysisModelFactory = Future<AnalysisModel> Function(AiConfig config);

final analysisModelFactoryProvider = Provider<AnalysisModelFactory>(
  (ref) =>
      (config) async => HttpAnalysisModel(
        baseUrl: config.normalizedUrl!,
        model: config.trimmedModel,
        apiKey: await ref.read(secretStoreProvider).read(aiApiKeySecretName),
        local: config.preset.isLocal,
        requestTimeout: Duration(seconds: config.requestTimeoutSeconds),
        profileStore: ref.read(aiConfigStoreProvider),
      ),
);

final aiRunMarkerStoreProvider = Provider<AiRunMarkerStore>(
  (ref) => throw UnimplementedError('Override aiRunMarkerStoreProvider.'),
);

// Runs once per process, so a marker left by a killed run is stored once.
final aiRunRecoveryProvider = FutureProvider<void>((ref) async {
  final markers = ref.read(aiRunMarkerStoreProvider);
  final draft = await markers.read();
  if (draft == null) return;
  await ref.read(aiReportStoreProvider).insert(draft);
  await markers.clear();
}, retry: _noRetry);

final NotifierProvider<AnalysisRunController, AnalysisRunState>
analysisRunControllerProvider =
    NotifierProvider.autoDispose<AnalysisRunController, AnalysisRunState>(
      AnalysisRunController.new,
      retry: _noRetry,
    );

class AnalysisRunController extends Notifier<AnalysisRunState> {
  bool _busy = false;
  Completer<void>? _cancel;
  Completer<AnalysisCompleted>? _done;
  StreamSubscription<AnalysisEvent>? _sub;
  KeepAliveLink? _link;
  Timer? _throttle;
  int? _pendingChars;
  AnalysisCompleted? _completed;

  @override
  AnalysisRunState build() {
    ref
      ..onDispose(cancel)
      ..read(aiRunRecoveryProvider);
    return const AnalysisIdle();
  }

  Future<void> send({bool force = false}) async {
    if (_busy || !ref.read(aiEnabledProvider)) return;
    _busy = true;
    try {
      await _prepare(force: force);
    } on Object catch (error) {
      _fail(RunUnexpected(error));
    } finally {
      _busy = false;
      _link?.close();
    }
  }

  void cancel() {
    final cancel = _cancel;
    _throttle?.cancel();
    if (cancel == null || cancel.isCompleted) return;
    cancel.complete();
    unawaited(_sub?.cancel());
    _settle(_done, _cancelled);
  }

  Future<void> _prepare({required bool force}) async {
    await ref.read(aiRunRecoveryProvider.future).catchError((Object _) {});
    if (!ref.mounted) return;
    final result = await ref.read(aiPayloadProvider.future);
    if (!ref.mounted) return;
    final config = await ref.read(aiConfigProvider.future);
    if (!ref.mounted) return;
    if (result is AiPayloadNotEnoughData) {
      return _fail(RunNotEnoughData(result.days));
    }
    if (result is! AiPayloadReady) return;
    final clock = ref.read(clockProvider);
    final store = ref.read(aiReportStoreProvider);
    if (ref.read(demoModeProvider)) {
      final draft = _draft(result, config, clock(), aiSampleProviderHost);
      final sample = SampleAnalysisModel(result.payload.facts.firstOrNull?.id);
      return await _execute(sample, result, draft, config);
    }
    final host = config.hostKey;
    if (host == null || config.trimmedModel.isEmpty) return;
    final draft = _draft(result, config, clock(), host);
    final cached = force ? null : await store.newestDone(draft.cacheKey);
    if (!ref.mounted) return;
    if (cached != null) {
      state = AnalysisDone(cached, fromCache: true);
      return;
    }
    final cap = config.monthlyTokenCap;
    final markers = ref.read(aiRunMarkerStoreProvider);
    final used = cap == null
        ? 0
        : await markers.monthTokens(aiMonthKey(clock()));
    if (cap != null && used >= cap) {
      return _fail(RunCeilingReached(used: used, cap: cap));
    }
    final model = await ref.read(analysisModelFactoryProvider)(config);
    if (!ref.mounted) return;
    final profile = await ref
        .read(aiConfigStoreProvider)
        .readCapabilityProfile(host, config.trimmedModel);
    if (!ref.mounted) return;
    await _execute(
      model,
      result,
      draft,
      config,
      profile: profile ?? AiCapabilityProfile.defaults,
      store: store,
      markers: markers,
    );
  }

  // Demo mode passes no store and no markers, so nothing is persisted.
  Future<void> _execute(
    AnalysisModel model,
    AiPayloadReady ready,
    AiReport draft,
    AiConfig config, {
    AiCapabilityProfile profile = AiCapabilityProfile.defaults,
    AiReportStore? store,
    AiRunMarkerStore? markers,
  }) async {
    final clock = ref.read(clockProvider);
    final startedAt = clock();
    _cancel = Completer<void>();
    _completed = null;
    _link = ref.keepAlive();
    state = AnalysisSending(receivedChars: 0, startedAt: startedAt);
    final payload = ready.payload;
    final request = AnalysisRequest(
      systemPrompt: payload.systemPrompt,
      userContent: AiTextContent(payload.userMessage),
      maxOutputTokens: config.maxOutputTokens,
      profile: profile,
      jsonSchema: aiReportOutputSchema,
      reasoningEffort: config.reasoningEffort,
    );
    int elapsed() => clock().difference(startedAt).inMilliseconds;
    Future<(AiReport, AnalysisRunState)> attempt() async {
      try {
        final completed = _completed = await _generate(model, request);
        _throttle?.cancel();
        _set(const AnalysisValidating());
        final report = _validated(draft, payload, completed, elapsed());
        return (report, AnalysisDone(report));
      } on Object catch (error) {
        final failure = _asFailure(error);
        // fromWire maps every kind but cancelled to failed.
        final report = finishAiReport(
          draft,
          status: AiReportStatus.fromWire(failure.kind.name),
          completed: _completed,
          durationMs: elapsed(),
          errorKind: failure.kind.name,
        );
        final larger = failure.kind == AnalysisFailureKind.emptyAfterLimit;
        final next = AnalysisFailed(
          RunModelFailure(failure),
          canRetryLarger: larger,
        );
        return (report, next);
      }
    }

    try {
      await markers?.write(draft);
      final (report, next) = await attempt();
      await store?.insert(report);
      final tokens =
          (report.promptTokens ?? 0) + (report.completionTokens ?? 0);
      await markers?.addMonthTokens(aiMonthKey(startedAt), tokens);
      _set(next);
    } finally {
      _throttle?.cancel();
      await markers?.clear().catchError((Object _) {});
    }
  }

  Future<AnalysisCompleted> _generate(
    AnalysisModel model,
    AnalysisRequest request,
  ) async {
    try {
      return await _stream(model, request);
    } on AnalysisFailure catch (failure) {
      final wait = _autoRetryWait(failure);
      if (wait == null || _cancel!.isCompleted) rethrow;
      await Future.any([Future<void>.delayed(wait), _cancel!.future]);
      if (_cancel!.isCompleted) throw _cancelled;
      return await _stream(model, request);
    }
  }

  Future<AnalysisCompleted> _stream(
    AnalysisModel model,
    AnalysisRequest request,
  ) {
    final done = _done = Completer<AnalysisCompleted>();
    _sub = model
        .generate(request, cancel: _cancel!.future)
        .listen(
          (event) => _onEvent(done, event),
          onError: (Object error) => _settle(done, error),
          onDone: () => _settle(done, _unreadable),
          cancelOnError: true,
        );
    return done.future;
  }

  void _onEvent(Completer<AnalysisCompleted> done, AnalysisEvent event) {
    switch (event) {
      case AnalysisProgress(:final receivedChars):
        _pendingChars = receivedChars;
        if (_throttle?.isActive ?? false) return;
        _emitProgress();
      case AnalysisCompleted():
        _settle(done, event);
    }
  }

  void _emitProgress() {
    final chars = _pendingChars;
    if (chars == null || !ref.mounted) return;
    final current = state;
    if (current is! AnalysisSending) return;
    _pendingChars = null;
    state = AnalysisSending(receivedChars: chars, startedAt: current.startedAt);
    _throttle = Timer(aiProgressInterval, _emitProgress);
  }

  void _settle(Completer<AnalysisCompleted>? done, Object outcome) {
    if (done == null || done.isCompleted) return;
    if (outcome is AnalysisCompleted) return done.complete(outcome);
    done.completeError(outcome);
  }

  AnalysisFailure _asFailure(Object error) {
    if (_cancel?.isCompleted ?? false) return _cancelled;
    if (error is AnalysisFailure) return error;
    return _unreadable;
  }

  AiReport _validated(
    AiReport draft,
    BuiltAiPayload payload,
    AnalysisCompleted completed,
    int durationMs,
  ) {
    final raw = AiOutputExtractor.extractReport(completed.text);
    if (raw == null) {
      throw _unreadable;
    }
    final valid = AiReportValidator.validateForPayload(raw, payload);
    return finishAiReport(
      draft,
      status: AiReportStatus.done,
      completed: completed,
      durationMs: durationMs,
      droppedCards: valid.droppedCards.length,
      cardsJson: jsonEncode({
        'summary': valid.summary,
        'cards': [for (final card in valid.cards) card.toJson()],
      }),
    );
  }

  void _fail(AnalysisRunFailure failure) => _set(AnalysisFailed(failure));

  void _set(AnalysisRunState next) {
    if (ref.mounted) state = next;
  }
}

Duration? _autoRetryWait(AnalysisFailure f) {
  final seconds = f.retryAfterSeconds;
  if (f.kind != AnalysisFailureKind.rateLimited || seconds == null) return null;
  if (seconds < 0 || seconds > aiAutoRetryMaxSeconds) return null;
  return Duration(seconds: seconds);
}

String aiMonthKey(DateTime now) {
  final local = now.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}';
}

AiReport _draft(
  AiPayloadReady ready,
  AiConfig config,
  DateTime now,
  String host,
) {
  final payload = ready.payload;
  return AiReport(
    createdAtUtc: now.toUtc(),
    offsetMin: now.timeZoneOffset.inMinutes,
    kind: ready.kind.wireName,
    contextSchema: aiContextSchemaVersion,
    contextSha256: payload.cacheKey,
    detailLevel: config.detailLevel.wireName,
    promptVersion: 'v$aiPromptVersion',
    providerHost: host,
    model: config.trimmedModel,
    status: AiReportStatus.failed,
    payloadJson: jsonEncode({
      'system': payload.systemPrompt,
      'user': payload.userMessage,
    }),
  );
}

AiReport finishAiReport(
  AiReport d, {
  required AiReportStatus status,
  AnalysisCompleted? completed,
  int? durationMs,
  int droppedCards = 0,
  String? cardsJson,
  String? errorKind,
}) {
  final usage = completed?.usage;
  return AiReport(
    createdAtUtc: d.createdAtUtc,
    offsetMin: d.offsetMin,
    kind: d.kind,
    contextSchema: d.contextSchema,
    contextSha256: d.contextSha256,
    detailLevel: d.detailLevel,
    promptVersion: d.promptVersion,
    providerHost: d.providerHost,
    model: d.model,
    status: status,
    payloadJson: d.payloadJson,
    cardsJson: cardsJson,
    rawText: completed?.text,
    droppedCards: droppedCards,
    promptTokens: usage?.promptTokens,
    completionTokens: usage?.completionTokens,
    reasoningTokens: usage?.reasoningTokens,
    durationMs: durationMs,
    errorKind: errorKind,
  );
}
