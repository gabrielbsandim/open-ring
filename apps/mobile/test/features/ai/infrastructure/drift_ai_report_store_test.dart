import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/ai/domain/ai_report.dart';
import 'package:open_ring/features/ai/infrastructure/drift_ai_report_store.dart';

import '../../../helpers/ai_fakes.dart';
import '../../../helpers/database.dart';

final _now = DateTime.utc(2026, 11, 23, 12);

AiReport _report({
  DateTime? at,
  AiReportStatus status = AiReportStatus.done,
  String sha = 'abc',
  String model = 'model-x',
}) => AiReport(
  createdAtUtc: at ?? _now,
  offsetMin: -180,
  kind: 'daily',
  contextSchema: 'health_context_v2',
  contextSha256: sha,
  detailLevel: 'standard',
  promptVersion: 'v1',
  providerHost: 'api.example.com',
  model: model,
  status: status,
  payloadJson: '{"messages":[]}',
  cardsJson: '[]',
  rawText: 'raw',
  droppedCards: 1,
  promptTokens: 4612,
  completionTokens: 1180,
  reasoningTokens: 640,
  cost: 0.0041,
  costCurrency: 'credits',
  costSource: AiCostSource.userPrice,
  durationMs: 2300,
  errorKind: status == AiReportStatus.done ? null : 'timeout',
);

const _key = AiReportCacheKey(
  kind: 'daily',
  contextSha256: 'abc',
  promptVersion: 'v1',
  providerHost: 'api.example.com',
  model: 'model-x',
);

void main() {
  final stores = <String, AiReportStore Function()>{
    'drift': () => DriftAiReportStore(memoryDatabase()),
    'in memory': InMemoryAiReportStore.new,
  };

  for (final MapEntry(key: name, value: create) in stores.entries) {
    group(name, () {
      test('round trips every field', () async {
        final store = create();
        final id = await store.insert(_report());
        final back = (await store.recent()).single;
        expect(back.id, id);
        expect(back.createdAtUtc, _now);
        expect(back.offsetMin, -180);
        expect(back.contextSchema, 'health_context_v2');
        expect(back.detailLevel, 'standard');
        expect(back.status, AiReportStatus.done);
        expect(back.payloadJson, '{"messages":[]}');
        expect(back.cardsJson, '[]');
        expect(back.rawText, 'raw');
        expect(back.droppedCards, 1);
        expect(back.promptTokens, 4612);
        expect(back.completionTokens, 1180);
        expect(back.reasoningTokens, 640);
        expect(back.cost, 0.0041);
        expect(back.costCurrency, 'credits');
        expect(back.costSource, AiCostSource.userPrice);
        expect(back.durationMs, 2300);
        expect(back.errorKind, isNull);
        expect(back.cacheKey, _key);
      });

      test('newestDone returns the newest done report of the key', () async {
        final store = create();
        await store.insert(
          _report(at: _now.subtract(const Duration(hours: 2))),
        );
        final newest = await store.insert(
          _report(at: _now.subtract(const Duration(hours: 1))),
        );
        await store.insert(_report(status: AiReportStatus.failed));
        await store.insert(_report(status: AiReportStatus.cancelled));
        await store.insert(_report(sha: 'other'));
        await store.insert(_report(model: 'model-y'));

        expect((await store.newestDone(_key))?.id, newest);
        expect(
          await store.newestDone(
            const AiReportCacheKey(
              kind: 'weekly',
              contextSha256: 'abc',
              promptVersion: 'v1',
              providerHost: 'api.example.com',
              model: 'model-x',
            ),
          ),
          isNull,
        );
      });

      test('keeps the newest 60 reports, ties broken by id', () async {
        final store = create();
        final ids = <int>[];
        for (var i = 0; i < aiReportKeepCount + 1; i++) {
          ids.add(await store.insert(_report()));
        }
        final kept = await store.recent(limit: 100);
        expect(kept, hasLength(aiReportKeepCount));
        expect(kept.map((r) => r.id), isNot(contains(ids.first)));
        expect(kept.first.id, ids.last);
      });

      test('an older insert past the cap is the one dropped', () async {
        final store = create();
        for (var i = 0; i < aiReportKeepCount; i++) {
          await store.insert(_report(at: _now.add(Duration(minutes: i))));
        }
        final old = await store.insert(
          _report(at: _now.subtract(const Duration(days: 1))),
        );
        final kept = await store.recent(limit: 100);
        expect(kept, hasLength(aiReportKeepCount));
        expect(kept.map((r) => r.id), isNot(contains(old)));
      });

      test('clears payload and raw text only past 30 days', () async {
        final store = create();
        final cutoff = _now.subtract(const Duration(days: aiReportPayloadDays));
        final atCutoff = await store.insert(_report(at: cutoff));
        final older = await store.insert(
          _report(at: cutoff.subtract(const Duration(milliseconds: 1))),
        );
        await store.applyRetention(_now);

        final byId = {for (final r in await store.recent()) r.id: r};
        expect(byId[atCutoff]!.payloadJson, isNotNull);
        expect(byId[atCutoff]!.rawText, isNotNull);
        expect(byId[older]!.payloadJson, isNull);
        expect(byId[older]!.rawText, isNull);
        expect(byId[older]!.cardsJson, '[]');
      });

      test('insert purges old payloads in the same step', () async {
        final store = create();
        final old = await store.insert(
          _report(at: _now.subtract(const Duration(days: 31))),
        );
        await store.insert(_report());
        final byId = {for (final r in await store.recent()) r.id: r};
        expect(byId[old]!.payloadJson, isNull);
      });

      test('deleteAll empties the store', () async {
        final store = create();
        await store.insert(_report());
        await store.deleteAll();
        expect(await store.recent(), isEmpty);
        expect(await store.newestDone(_key), isNull);
      });
    });
  }
}
