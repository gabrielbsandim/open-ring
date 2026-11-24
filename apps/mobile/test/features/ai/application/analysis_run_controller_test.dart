import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/ai/application/ai_config_providers.dart';
import 'package:open_ring/features/ai/application/ai_gate.dart';
import 'package:open_ring/features/ai/application/ai_report_providers.dart';
import 'package:open_ring/features/ai/application/analysis_run_controller.dart';
import 'package:open_ring/features/ai/application/health_context_providers.dart';
import 'package:open_ring/features/ai/domain/ai_config.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/domain/ai_wire_types.dart';
import 'package:open_ring/features/ai/domain/analysis_model.dart';
import 'package:open_ring/features/ai/domain/analysis_run_state.dart';
import 'package:open_ring/features/ai/domain/health_context_assembly.dart';
import 'package:open_ring/features/ai/domain/health_context_models.dart';
import 'package:open_ring/features/ai/domain/sample_analysis_model.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';

import '../../../helpers/ai_fakes.dart';

final _now = DateTime.utc(2026, 11, 20, 12);

const _payload = BuiltAiPayload(
  contextMap: {
    'reply_language': 'en',
    'window': {'days': 14, 'weeks': 0},
  },
  canonicalContextJson: '{}',
  systemPrompt: 'system',
  userMessage: 'Task: daily_review.\nDATA:\n{"facts":[{"id":"sleep_avg"}]}',
  facts: [
    HealthFact(
      id: 'sleep_avg',
      label: 'Sleep average',
      value: 420,
      unit: AiFactUnit.min,
      family: AiMetricFamily.sleep,
      days: 14,
    ),
  ],
  estimatedTokens: 10,
  contextTokens: 5,
  cacheKey: 'context-sha',
  droppedCount: 0,
);

final String _answer = jsonEncode({
  'summary': 'Your sleep was steady.',
  'cards': [
    {
      'family': 'sleep',
      'title': 'Steady sleep',
      'insight': 'Sleep stayed close to your usual amount.',
      'evidence': ['sleep_avg'],
      'action': 'Keep a regular bedtime.',
      'confidence': 'medium',
    },
  ],
});

typedef _Script = Stream<AnalysisEvent> Function(Future<void> cancel);

final class _FakeModel implements AnalysisModel {
  new(this.scripts);

  final List<_Script> scripts;
  int calls = 0;
  bool cancelSeen = false;

  @override
  Stream<AnalysisEvent> generate(
    AnalysisRequest request, {
    required Future<void> cancel,
  }) {
    unawaited(cancel.then((_) => cancelSeen = true));
    final script = scripts[calls.clamp(0, scripts.length - 1)];
    calls++;
    return script(cancel);
  }

  @override
  Future<List<String>> listModels() => throw UnimplementedError();

  @override
  Future<ConnectionProbe> probe({
    Future<void>? cancel,
    void Function()? onReached,
  }) => throw UnimplementedError();
}

Stream<AnalysisEvent> _ok(Future<void> _) => Stream.fromIterable([
  const AnalysisProgress(12),
  AnalysisCompleted(
    text: _answer,
    finishReason: 'stop',
    usage: const AiTokenUsage(promptTokens: 100, completionTokens: 50),
  ),
]);

_Script _fail(AnalysisFailure failure) =>
    (_) => Stream.error(failure);

Stream<AnalysisEvent> _hang(Future<void> _) =>
    StreamController<AnalysisEvent>().stream;

AnalysisFailure _limited(int? seconds) => AnalysisFailure(
  kind: AnalysisFailureKind.rateLimited,
  statusCode: 429,
  retryAfterSeconds: seconds,
);

void main() {
  late InMemoryAiConfigStore configStore;
  late InMemoryAiReportStore reports;
  late AiReportStore reportStore;
  late Exception? factoryError;
  late Completer<void>? factoryGate;
  late InMemoryAiRunMarkerStore markers;
  late _FakeModel model;
  late int factoryCalls;
  late bool enabled;
  late bool demo;
  late AiPayloadResult payload;

  setUp(() {
    configStore = InMemoryAiConfigStore()
      ..config = const AiConfig(
        baseUrl: 'https://api.example.com/v1',
        model: 'm',
      );
    reports = InMemoryAiReportStore();
    reportStore = reports;
    factoryError = null;
    factoryGate = null;
    markers = InMemoryAiRunMarkerStore();
    model = _FakeModel([_ok]);
    factoryCalls = 0;
    enabled = true;
    demo = false;
    payload = const AiPayloadReady(_payload);
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        aiEnabledProvider.overrideWith((ref) => enabled),
        aiPayloadProvider.overrideWith((ref) async => payload),
        aiConfigStoreProvider.overrideWithValue(configStore),
        aiReportStoreProvider.overrideWithValue(reportStore),
        aiRunMarkerStoreProvider.overrideWithValue(markers),
        demoModeStoreProvider.overrideWithValue(
          InMemoryDemoModeStore(enabled: demo),
        ),
        clockProvider.overrideWithValue(() => _now),
        analysisModelFactoryProvider.overrideWithValue((config) async {
          factoryCalls++;
          await factoryGate?.future;
          if (factoryError != null) throw factoryError!;
          return model;
        }),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  AnalysisRunController notifier(ProviderContainer c) =>
      c.read(analysisRunControllerProvider.notifier);

  AnalysisRunState listenState(ProviderContainer c) {
    c.listen(analysisRunControllerProvider, (_, _) {});
    return c.read(analysisRunControllerProvider);
  }

  AnalysisFailure modelFailure(ProviderContainer c) {
    final state = c.read(analysisRunControllerProvider) as AnalysisFailed;
    return (state.failure as RunModelFailure).failure;
  }

  test('framework retry is disabled on the run and recovery providers', () {
    expect(analysisRunControllerProvider.retry!(0, Exception()), isNull);
    expect(aiRunRecoveryProvider.retry!(0, Exception()), isNull);
  });

  test('AI off: send does nothing', () async {
    enabled = false;
    final c = container();
    listenState(c);
    await notifier(c).send();
    expect(c.read(analysisRunControllerProvider), isA<AnalysisIdle>());
    expect(model.calls, 0);
    expect(reports.reports, isEmpty);
  });

  test('build never sends', () async {
    final c = container();
    expect(listenState(c), isA<AnalysisIdle>());
    await pumpEventQueue();
    expect(model.calls, 0);
  });

  test('not enough data fails without a request', () async {
    payload = const AiPayloadNotEnoughData(3);
    final c = container();
    listenState(c);
    await notifier(c).send();
    final state = c.read(analysisRunControllerProvider) as AnalysisFailed;
    expect((state.failure as RunNotEnoughData).days, 3);
    expect(model.calls, 0);
  });

  test('a run validates, stores a done report and clears the marker', () async {
    final c = container();
    listenState(c);
    await notifier(c).send();
    final state = c.read(analysisRunControllerProvider) as AnalysisDone;
    expect(state.fromCache, isFalse);
    expect(state.isSample, isFalse);
    expect(state.report.status, AiReportStatus.done);
    expect(state.report.cardsJson, contains('Steady sleep'));
    expect(state.report.kind, 'daily_review');
    expect(state.report.contextSha256, 'context-sha');
    expect(reports.reports.single.promptTokens, 100);
    expect(markers.writes, 1);
    expect(markers.value, isNull);
  });

  test('a cached done report is returned with no network call', () async {
    final c = container();
    listenState(c);
    await notifier(c).send();
    await notifier(c).send();
    final state = c.read(analysisRunControllerProvider) as AnalysisDone;
    expect(state.fromCache, isTrue);
    expect(model.calls, 1);
    expect(factoryCalls, 1);
  });

  test('Analyze again bypasses the cache', () async {
    final c = container();
    listenState(c);
    await notifier(c).send();
    await notifier(c).send(force: true);
    final state = c.read(analysisRunControllerProvider) as AnalysisDone;
    expect(state.fromCache, isFalse);
    expect(model.calls, 2);
  });

  test('a second send while one is in flight is a no-op', () async {
    model = _FakeModel([_hang]);
    final c = container();
    listenState(c);
    final first = notifier(c).send();
    final second = notifier(c).send();
    await pumpEventQueue();
    expect(c.read(analysisRunControllerProvider), isA<AnalysisSending>());
    expect(model.calls, 1);
    await second;
    notifier(c).cancel();
    await first;
  });

  test(
    'cancel aborts, fails as cancelled and stores a cancelled row',
    () async {
      model = _FakeModel([_hang]);
      final c = container();
      listenState(c);
      final run = notifier(c).send();
      await pumpEventQueue();
      expect(markers.value, isNotNull);
      notifier(c).cancel();
      await run;
      await pumpEventQueue();
      expect(model.cancelSeen, isTrue);
      expect(modelFailure(c).kind, AnalysisFailureKind.cancelled);
      expect(reports.reports.single.status, AiReportStatus.cancelled);
      expect(markers.value, isNull);
    },
  );

  test('keeps itself alive while sending, then lets go', () async {
    model = _FakeModel([_hang]);
    final c = container();
    final run = notifier(c).send();
    await pumpEventQueue();
    expect(c.read(analysisRunControllerProvider), isA<AnalysisSending>());
    notifier(c).cancel();
    await run;
    await pumpEventQueue();
    // A disposed provider rebuilds from scratch, so the failure is gone.
    expect(c.read(analysisRunControllerProvider), isA<AnalysisIdle>());
  });

  test('invalidating aborts the request and writes nothing', () async {
    model = _FakeModel([_hang]);
    final c = container();
    final sub = c.listen(analysisRunControllerProvider, (_, _) {});
    final run = notifier(c).send();
    await pumpEventQueue();
    sub.close();
    c.invalidate(analysisRunControllerProvider);
    await run;
    await pumpEventQueue();
    expect(model.cancelSeen, isTrue);
    expect(reports.reports, isEmpty);
    expect(markers.month, isNull);
    expect(markers.value, isNull);
  });

  group('invalidated mid run', () {
    Future<void> invalidateWhile(
      ProviderContainer c,
      Completer<void> gate,
    ) async {
      final run = notifier(c).send();
      await pumpEventQueue();
      c.invalidate(analysisRunControllerProvider);
      gate.complete();
      await run;
      await pumpEventQueue();
    }

    test('while preparing: no request, no write', () async {
      factoryGate = Completer<void>();
      final c = container();
      listenState(c);
      await invalidateWhile(c, factoryGate!);
      expect(model.calls, 0);
      expect(markers.writes, 0);
      expect(reports.reports, isEmpty);
    });

    test('during the marker write: no request goes out', () async {
      markers.writeGate = Completer<void>();
      final c = container();
      listenState(c);
      await invalidateWhile(c, markers.writeGate!);
      expect(model.calls, 0);
      expect(reports.reports, isEmpty);
    });

    test('a later send after the abort runs normally', () async {
      factoryGate = Completer<void>();
      final c = container();
      listenState(c);
      await invalidateWhile(c, factoryGate!);
      await notifier(c).send();
      expect(c.read(analysisRunControllerProvider), isA<AnalysisDone>());
      expect(model.calls, 1);
    });

    test('while the insert is pending: no month total', () async {
      final gated = _GatedInsertStore(reports);
      reportStore = gated;
      final c = container();
      listenState(c);
      await invalidateWhile(c, gated.gate);
      expect(model.calls, 1);
      expect(markers.month, isNull);
    });
  });

  test('closing the last listener while sending does not cancel', () async {
    model = _FakeModel([_hang]);
    final c = container();
    final sub = c.listen(analysisRunControllerProvider, (_, _) {});
    final run = notifier(c).send();
    await pumpEventQueue();
    sub.close();
    await pumpEventQueue();
    expect(model.cancelSeen, isFalse);
    expect(c.read(analysisRunControllerProvider), isA<AnalysisSending>());
    expect(markers.value, isNotNull);
    notifier(c).cancel();
    await run;
  });

  test('progress is throttled to at most 4 updates per second', () {
    fakeAsync((async) {
      final events = StreamController<AnalysisEvent>();
      model = _FakeModel([(_) => events.stream]);
      final c = container();
      final seen = <int>[];
      c.listen(analysisRunControllerProvider, (_, next) {
        if (next is AnalysisSending) seen.add(next.receivedChars);
      });
      unawaited(notifier(c).send());
      async.flushMicrotasks();
      seen.clear();
      // 99 events spread over 990 ms, inside one second.
      for (var i = 1; i <= 99; i++) {
        events.add(AnalysisProgress(i * 10));
        async.elapse(const Duration(milliseconds: 10));
      }
      expect(seen.length, inInclusiveRange(2, 4));
      async.elapse(const Duration(milliseconds: 300));
      expect(seen.last, 990);
      notifier(c).cancel();
      async.flushMicrotasks();
    });
  });

  test('a 429 with retry-after of 20 s is resent once after the wait', () {
    fakeAsync((async) {
      model = _FakeModel([_fail(_limited(20)), _ok]);
      final c = container();
      listenState(c);
      unawaited(notifier(c).send());
      async.elapse(const Duration(seconds: 19));
      expect(model.calls, 1);
      expect(c.read(analysisRunControllerProvider), isA<AnalysisSending>());
      async.elapse(const Duration(seconds: 1));
      expect(model.calls, 2);
      expect(c.read(analysisRunControllerProvider), isA<AnalysisDone>());
    });
  });

  test('a second 429 is not resent again', () {
    fakeAsync((async) {
      model = _FakeModel([_fail(_limited(5))]);
      final c = container();
      listenState(c);
      unawaited(notifier(c).send());
      async.elapse(const Duration(minutes: 1));
      expect(model.calls, 2);
      expect(modelFailure(c).kind, AnalysisFailureKind.rateLimited);
    });
  });

  for (final (name, failure) in [
    ('a 429 over 20 s', _limited(21)),
    ('a 429 without retry-after', _limited(null)),
    (
      'a server error',
      const AnalysisFailure(kind: AnalysisFailureKind.serverError),
    ),
    (
      'a 503 with retry-after',
      const AnalysisFailure(
        kind: AnalysisFailureKind.serverError,
        statusCode: 503,
        retryAfterSeconds: 5,
      ),
    ),
  ]) {
    test('$name is not resent automatically', () {
      fakeAsync((async) {
        model = _FakeModel([_fail(failure), _ok]);
        final c = container();
        listenState(c);
        unawaited(notifier(c).send());
        async.elapse(const Duration(minutes: 1));
        expect(model.calls, 1);
        expect(modelFailure(c), failure);
        expect(reports.reports.single.status, AiReportStatus.failed);
        expect(reports.reports.single.errorKind, failure.kind.name);
      });
    });
  }

  test('cancel during the 429 wait stops the resend', () {
    fakeAsync((async) {
      model = _FakeModel([_fail(_limited(20)), _ok]);
      final c = container();
      listenState(c);
      unawaited(notifier(c).send());
      async.elapse(const Duration(seconds: 5));
      notifier(c).cancel();
      async.elapse(const Duration(seconds: 30));
      expect(model.calls, 1);
      expect(modelFailure(c).kind, AnalysisFailureKind.cancelled);
    });
  });

  test('an empty answer at the output limit offers a larger retry', () async {
    model = _FakeModel([
      _fail(const AnalysisFailure(kind: AnalysisFailureKind.emptyAfterLimit)),
    ]);
    final c = container();
    listenState(c);
    await notifier(c).send();
    final state = c.read(analysisRunControllerProvider) as AnalysisFailed;
    expect(state.canRetryLarger, isTrue);
  });

  test('an unreadable answer fails and keeps the raw text', () async {
    model = _FakeModel([
      (_) => Stream.value(
        const AnalysisCompleted(text: 'not json', finishReason: 'stop'),
      ),
    ]);
    final c = container();
    listenState(c);
    await notifier(c).send();
    expect(modelFailure(c).kind, AnalysisFailureKind.unreadable);
    expect(reports.reports.single.rawText, 'not json');
    expect(reports.reports.single.status, AiReportStatus.failed);
  });

  group('monthly token ceiling', () {
    test('at the cap it fails without sending', () async {
      configStore.config = configStore.config.copyWith(monthlyTokenCap: 100);
      markers
        ..month = aiMonthKey(_now)
        ..monthSum = 100;
      final c = container();
      listenState(c);
      await notifier(c).send();
      final state = c.read(analysisRunControllerProvider) as AnalysisFailed;
      final failure = state.failure as RunCeilingReached;
      expect((failure.used, failure.cap), (100, 100));
      expect(model.calls, 0);
    });

    test('61 runs in a month still block past report retention', () async {
      configStore.config = configStore.config.copyWith(
        monthlyTokenCap: 61 * 150,
      );
      final c = container();
      listenState(c);
      for (var i = 0; i < 61; i++) {
        await notifier(c).send(force: true);
      }
      expect(reports.reports, hasLength(aiReportKeepCount));
      await notifier(c).send(force: true);
      final state = c.read(analysisRunControllerProvider) as AnalysisFailed;
      expect(state.failure, isA<RunCeilingReached>());
      expect(model.calls, 61);
    });

    test('tokens from an earlier month do not count', () async {
      configStore.config = configStore.config.copyWith(monthlyTokenCap: 100);
      markers
        ..month = '2026-10'
        ..monthSum = 500;
      final c = container();
      listenState(c);
      await notifier(c).send();
      expect(c.read(analysisRunControllerProvider), isA<AnalysisDone>());
      expect((markers.month, markers.monthSum), ('2026-11', 150));
    });
  });

  test('demo mode answers with a sample and calls no model', () async {
    final real = container();
    listenState(real);
    await notifier(real).send();
    configStore.config = configStore.config.copyWith(monthlyTokenCap: 150);
    reports.reports.clear();
    model.calls = 0;
    factoryCalls = 0;
    markers.writes = 0;
    reports.reports.add(
      (real.read(analysisRunControllerProvider) as AnalysisDone).report,
    );
    demo = true;
    final c = container();
    listenState(c);
    await notifier(c).send();
    final state = c.read(analysisRunControllerProvider) as AnalysisDone;
    expect(state.isSample, isTrue);
    expect(state.fromCache, isFalse);
    expect(state.report.cardsJson, contains('sleep_avg'));
    expect(state.report.cardsJson, contains(SampleAnalysisModel.summary));
    expect(factoryCalls, 0);
    expect(model.calls, 0);
    expect(reports.reports, hasLength(1));
    expect(markers.writes, 0);
  });

  test(
    'launch recovery turns a marker into a cancelled row, no controller needed',
    () async {
      markers.value = sampleAiReport(at: _now);
      final c = container();
      await c.read(aiRunRecoveryProvider.future);
      final row = reports.reports.single;
      expect(row.status, AiReportStatus.cancelled);
      expect(row.errorKind, AnalysisFailureKind.cancelled.name);
      expect(markers.value, isNull);
    },
  );

  test('send waits for recovery before writing its own marker', () async {
    model = _FakeModel([_hang]);
    markers
      ..value = sampleAiReport(at: _now)
      ..readGate = Completer<void>();
    final c = container();
    listenState(c);
    final run = notifier(c).send();
    await pumpEventQueue();
    expect(model.calls, 0);
    markers.readGate!.complete();
    await pumpEventQueue();
    expect(reports.reports.single.providerHost, 'reports.example.com');
    expect(reports.reports.single.errorKind, 'cancelled');
    expect(markers.value?.providerHost, configStore.config.hostKey);
    notifier(c).cancel();
    await run;
  });

  test('a failing marker write ends the run as failed', () async {
    markers.writeError = Exception('disk full');
    final c = container();
    listenState(c);
    await notifier(c).send();
    final state = c.read(analysisRunControllerProvider) as AnalysisFailed;
    expect(state.failure, isA<RunUnexpected>());
    expect(markers.value, isNull);
    expect(model.calls, 0);
  });

  test('a failing marker clear does not undo a finished run', () async {
    markers.clearError = Exception('disk full');
    final c = container();
    listenState(c);
    await notifier(c).send();
    expect(c.read(analysisRunControllerProvider), isA<AnalysisDone>());
  });

  test('a failing report insert ends the run as failed', () async {
    reportStore = _FailingInsertStore();
    final c = container();
    listenState(c);
    await notifier(c).send();
    final state = c.read(analysisRunControllerProvider) as AnalysisFailed;
    expect(state.failure, isA<RunUnexpected>());
    expect(markers.value, isNull);
  });

  test('a failing model factory ends the run as failed', () async {
    factoryError = Exception('keystore');
    final c = container();
    listenState(c);
    await notifier(c).send();
    final state = c.read(analysisRunControllerProvider) as AnalysisFailed;
    expect(state.failure, isA<RunUnexpected>());
  });

  test('a blank model name sends nothing', () async {
    configStore.config = configStore.config.copyWith(model: '  ');
    final c = container();
    listenState(c);
    await notifier(c).send();
    expect(factoryCalls, 0);
    expect(c.read(analysisRunControllerProvider), isA<AnalysisIdle>());
  });
}

final class _FailingInsertStore implements AiReportStore {
  @override
  Future<int> insert(AiReport report) => throw Exception('db locked');

  @override
  Future<AiReport?> newestDone(AiReportCacheKey key) async => null;

  @override
  Future<List<AiReport>> recent({int limit = aiReportKeepCount}) async => [];

  @override
  Future<void> deleteAll() async {}

  @override
  Future<void> applyRetention(DateTime nowUtc) async {}
}

final class _GatedInsertStore implements AiReportStore {
  new(this.inner);

  final InMemoryAiReportStore inner;
  final Completer<void> gate = Completer<void>();

  @override
  Future<int> insert(AiReport report) async {
    await gate.future;
    return await inner.insert(report);
  }

  @override
  Future<AiReport?> newestDone(AiReportCacheKey key) => inner.newestDone(key);

  @override
  Future<List<AiReport>> recent({int limit = aiReportKeepCount}) =>
      inner.recent(limit: limit);

  @override
  Future<void> deleteAll() => inner.deleteAll();

  @override
  Future<void> applyRetention(DateTime nowUtc) => inner.applyRetention(nowUtc);
}
