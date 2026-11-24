import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/ai_report_providers.dart';
import 'package:open_ring/features/ai/application/health_context_providers.dart';
import 'package:open_ring/features/ai/domain/ai_advanced_input.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_consent_scope.dart';
import 'package:open_ring/features/ai/domain/ai_cost.dart';
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
const Duration aiRunAbortWait = Duration(seconds: 5);
const Duration aiProgressInterval = Duration(milliseconds: 250);

const _cancelled = AnalysisFailure(kind: AnalysisFailureKind.cancelled);
const _unreadable = AnalysisFailure(kind: AnalysisFailureKind.unreadable);

// A null retry falls back to Riverpod's default, which retries; a paid
// request must never be resent by the framework.
Duration? _noRetry(int _, Object _) => null;

typedef AnalysisModelFactory = Future<AnalysisModel> Function(AiConfig config);

/// Builds a model with exactly [apiKey], so a caller decides which key
/// may go to the config's host.
typedef KeyedAnalysisModelFactory = AnalysisModel Function(
  AiConfig config,
  String? apiKey,
);

final keyedAnalysisModelFactoryProvider = Provider<KeyedAnalysisModelFactory>(
  (ref) =>
      (config, apiKey) => HttpAnalysisModel(
        baseUrl: config.normalizedUrl!,
        model: config.trimmedModel,
        apiKey: apiKey,
        local: config.preset.isLocal,
        requestTimeout: Duration(seconds: config.requestTimeoutSeconds),
        profileStore: ref.read(aiConfigStoreProvider),
      ),
);

final analysisModelFactoryProvider = Provider<AnalysisModelFactory>(
  (ref) =>
      (config) async => ref.read(keyedAnalysisModelFactoryProvider)(
        config,
        await ref.read(secretStoreProvider).read(aiApiKeySecretName),
      ),
);

final aiRunMarkerStoreProvider = Provider<AiRunMarkerStore>(
  (ref) => throw UnimplementedError('Override aiRunMarkerStoreProvider.'),
);

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
  bool _dead = false;
  Completer<void> _cancel = Completer<void>();
  Completer<AnalysisCompleted>? _done;
  StreamSubscription<AnalysisEvent>? _sub;
  KeepAliveLink? _link;
  Timer? _throttle;
  int? _pendingChars;
  AnalysisCompleted? _completed;

  @override
  AnalysisRunState build() {
    ref.onDispose(_dispose);
    return const AnalysisIdle();
  }

  // The notifier and a listened Ref outlive an invalidation, so the run keeps
  // its own flag and checks it before every request and every write.
  void _dispose() {
    _dead = true;
    cancel();
  }

  /// Settles when the run in flight, if any, has finished or aborted.
  Future<void> idle = Future.value();

  /// [maxOutputTokens] overrides Advanced for this run only.
  Future<void> send({
    AiAnalysisKind kind = AiAnalysisKind.dailyReview,
    bool force = false,
    int? maxOutputTokens,
  }) {
    if (_busy || !ref.read(aiEnabledProvider)) return Future.value();
    _busy = true;
    _dead = false;
    _cancel = Completer<void>();
    _maxOutput = maxOutputTokens;
    return idle = _run(kind, force: force);
  }

  int? _maxOutput;

  Future<void> _run(AiAnalysisKind kind, {required bool force}) async {
    try {
      await _prepare(kind, force: force);
    } on Object catch (error) {
      _fail(RunUnexpected(error));
    } finally {
      _busy = false;
      _link?.close();
    }
  }

  void cancel() {
    _throttle?.cancel();
    if (_cancel.isCompleted) return;
    _cancel.complete();
    unawaited(_sub?.cancel());
    _settle(_done, _cancelled);
  }

  Future<void> _prepare(AiAnalysisKind kind, {required bool force}) async {
    await ref.read(aiRunRecoveryProvider.future).catchError((Object _) {});
    if (_dead) return;
    final result = await ref.read(aiPayloadProvider(kind).future);
    if (_dead) return;
    final config = await ref.read(aiConfigProvider.future);
    if (_dead) return;
    if (result is AiPayloadNotEnoughData) {
      return _fail(RunNotEnoughData(result.days));
    }
    if (result is! AiPayloadReady) return;
    final clock = ref.read(clockProvider);
    final store = ref.read(aiReportStoreProvider);
    _RunBase base(String host) =>
        (ready: result, config: config, at: clock(), host: host);
    if (ref.read(demoModeProvider)) {
      final sample = SampleAnalysisModel(result.payload.facts.firstOrNull?.id);
      return await _execute(sample, base(aiSampleProviderHost));
    }
    final host = config.hostKey;
    if (host == null || config.trimmedModel.isEmpty) return;
    final consent = await ref.read(aiConfigStoreProvider).readConsent();
    if (_dead) return;
    if (!aiConsentCoversPayload(consent, config, result.payload)) {
      return _fail(const RunConsentNeeded());
    }
    final run = base(host);
    final key = _report(run).cacheKey;
    final cached = force ? null : await store.newestDone(key);
    if (_dead) return;
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
    final profile = await ref
        .read(aiConfigStoreProvider)
        .readCapabilityProfile(host, config.trimmedModel);
    if (_dead) return;
    await _execute(
      model,
      run,
      profile: profile ?? AiCapabilityProfile.defaults,
      store: store,
      markers: markers,
    );
  }

  // Demo mode passes no store and no markers, so nothing is persisted.
  Future<void> _execute(
    AnalysisModel model,
    _RunBase base, {
    AiCapabilityProfile profile = AiCapabilityProfile.defaults,
    AiReportStore? store,
    AiRunMarkerStore? markers,
  }) async {
    final clock = ref.read(clockProvider);
    final startedAt = clock();
    final config = base.config;
    final payload = base.ready.payload;
    final draft = _report(base);
    _completed = null;
    _link = ref.keepAlive();
    state = AnalysisSending(receivedChars: 0, startedAt: startedAt);
    final request = AnalysisRequest(
      systemPrompt: payload.systemPrompt,
      userContent: AiTextContent(payload.userMessage),
      maxOutputTokens: _maxOutput ?? config.maxOutputTokens,
      profile: profile,
      pin: aiOutputPin(config),
      jsonSchema: aiReportOutputSchema,
      reasoningEffort: config.reasoningEffort,
    );
    int elapsed() => clock().difference(startedAt).inMilliseconds;
    Future<(AiReport, AnalysisRunState)> attempt() async {
      try {
        final completed = _completed = await _generate(model, request);
        _throttle?.cancel();
        _set(const AnalysisValidating());
        final report = _validated(base, completed, elapsed());
        return (report, AnalysisDone(report));
      } on Object catch (error) {
        final failure = _asFailure(error);
        // fromWire maps every kind but cancelled to failed.
        final report = _report(
          base,
          status: AiReportStatus.fromWire(failure.kind.name),
          completed: _completed,
          durationMs: elapsed(),
          errorKind: failure.kind.name,
        );
        final larger = failure.kind == AnalysisFailureKind.emptyAfterLimit;
        final next = AnalysisFailed(
          RunModelFailure(failure),
          canRetryLarger: larger,
          report: report,
          outputLimit: request.maxOutputTokens,
        );
        return (report, next);
      }
    }

    try {
      await markers?.write(draft);
      final (report, next) = await attempt();
      if (_dead) return;
      await store?.insert(report);
      final tokens =
          (report.promptTokens ?? 0) + (report.completionTokens ?? 0);
      if (_dead) return;
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
    if (_cancel.isCompleted) throw _cancelled;
    try {
      return await _stream(model, request);
    } on AnalysisFailure catch (failure) {
      final wait = aiAutoRetryWait(failure);
      if (wait == null || _cancel.isCompleted) rethrow;
      await Future.any([Future<void>.delayed(wait), _cancel.future]);
      if (_cancel.isCompleted) throw _cancelled;
      return await _stream(model, request);
    }
  }

  Future<AnalysisCompleted> _stream(
    AnalysisModel model,
    AnalysisRequest request,
  ) {
    final done = _done = Completer<AnalysisCompleted>();
    _sub = model
        .generate(request, cancel: _cancel.future)
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
    if (_cancel.isCompleted) return _cancelled;
    if (error is AnalysisFailure) return error;
    return _unreadable;
  }

  AiReport _validated(
    _RunBase base,
    AnalysisCompleted completed,
    int durationMs,
  ) {
    final raw = AiOutputExtractor.extractReport(completed.text);
    if (raw == null) {
      throw _unreadable;
    }
    final valid = AiReportValidator.validateForPayload(raw, base.ready.payload);
    return _report(
      base,
      status: AiReportStatus.done,
      completed: completed,
      durationMs: durationMs,
      droppedCards: valid.droppedCards.length,
      cardsJson: jsonEncode({
        'summary': valid.summary,
        'cards': [for (final card in valid.cards) card.toJson()],
        'facts': _factsSnapshot(base.ready.payload),
        'dropped': [
          for (final d in valid.droppedCards)
            {'title': d.card.title, 'reason': d.reason.name},
        ],
      }),
    );
  }

  void _fail(AnalysisRunFailure failure) => _set(AnalysisFailed(failure));

  void _set(AnalysisRunState next) {
    if (ref.mounted) state = next;
  }
}

/// The wait before the one automatic resend a 429 allows, or null.
Duration? aiAutoRetryWait(AnalysisFailure f) {
  final seconds = f.retryAfterSeconds;
  if (f.kind != AnalysisFailureKind.rateLimited || seconds == null) return null;
  if (seconds < 0 || seconds > aiAutoRetryMaxSeconds) return null;
  return Duration(seconds: seconds);
}

int aiLargerOutputTokens(int current) =>
    math.min(aiMaxOutputTokens, math.max(16000, 2 * current));

String aiMonthKey(DateTime now) =>
    now.toLocal().toIso8601String().substring(0, 7);

typedef _RunBase = ({
  AiPayloadReady ready,
  AiConfig config,
  DateTime at,
  String host,
});

AiReport _report(
  _RunBase b, {
  AiReportStatus status = AiReportStatus.failed,
  AnalysisCompleted? completed,
  int? durationMs,
  int droppedCards = 0,
  String? cardsJson,
  String? errorKind,
}) {
  final payload = b.ready.payload;
  final usage = completed?.usage;
  final cost = aiReportCost(usage, b.config);
  return AiReport(
    createdAtUtc: b.at.toUtc(),
    offsetMin: b.at.timeZoneOffset.inMinutes,
    kind: b.ready.kind.wireName,
    contextSchema: aiContextSchemaVersion,
    contextSha256: payload.cacheKey,
    detailLevel: b.config.detailLevel.wireName,
    promptVersion: 'v$aiPromptVersion',
    providerHost: b.host,
    model: b.config.trimmedModel,
    status: status,
    payloadJson: jsonEncode({
      'system': payload.systemPrompt,
      'user': payload.userMessage,
    }),
    cardsJson:
        cardsJson ??
        (completed == null
            ? null
            : jsonEncode({'facts': _factsSnapshot(payload)})),
    rawText: completed?.text,
    droppedCards: droppedCards,
    promptTokens: usage?.promptTokens,
    completionTokens: usage?.completionTokens,
    reasoningTokens: usage?.reasoningTokens,
    cost: cost?.cost,
    costCurrency: cost?.currency,
    costSource: cost?.source ?? AiCostSource.none,
    durationMs: durationMs,
    errorKind: errorKind,
  );
}

// The numbers as they were sent, so a chip never shows a later value under
// the text the model wrote about this one.
List<Map<String, Object?>> _factsSnapshot(BuiltAiPayload payload) => [
  for (final f in payload.facts)
    {
      'id': f.id,
      'label': f.label,
      'value': f.value,
      'unit': f.unit.wireName,
      'days': f.days,
      'family': f.family.name,
    },
];
