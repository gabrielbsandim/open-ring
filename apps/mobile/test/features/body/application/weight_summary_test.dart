import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/body/application/weigh_in_providers.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/body/domain/weigh_in_store.dart';

final _now = DateTime.utc(2026, 11, 10, 9);

Future<WeightSummary?> _summary(List<WeighInDraft> drafts) async {
  final store = InMemoryWeighInStore();
  for (final draft in drafts) {
    await store.add(draft);
  }
  final container = ProviderContainer(
    overrides: [
      weighInStoreProvider.overrideWithValue(store),
      clockProvider.overrideWithValue(() => _now),
    ],
  );
  addTearDown(container.dispose);
  return await container.read(weightSummaryProvider.future);
}

void main() {
  test('with no weigh-ins there is no summary', () async {
    expect(await _summary(const []), isNull);
  });

  test('a weigh-in belongs to the day on its own clock', () async {
    final summary = await _summary([
      WeighInDraft(
        at: DateTime.utc(2026, 11, 9, 23, 30),
        offsetMinutes: 120,
        kilograms: 80,
      ),
      WeighInDraft(
        at: DateTime.utc(2026, 11, 10, 8),
        offsetMinutes: 120,
        kilograms: 82,
      ),
    ]);

    expect(summary?.trend, 81);
    expect(summary?.last.kilograms, 82);
    expect(summary?.rate, isA<WeightRateBuilding>());
  });

  test('fifteen days of steady loss give a rate', () async {
    final summary = await _summary([
      for (var day = 0; day < 15; day++)
        WeighInDraft(
          at: _now.subtract(Duration(days: day)),
          offsetMinutes: 0,
          kilograms: 80 + day * 0.1,
        ),
    ]);

    final rate = summary?.rate;
    expect(rate, isA<WeightRateReady>());
    expect((rate! as WeightRateReady).perWeek, closeTo(-0.7, 1e-6));
  });
}
