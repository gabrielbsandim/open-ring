import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/features/demo/domain/demo_data_generator.dart';
import 'package:open_ring/features/demo/infrastructure/drift_demo_data_store.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';

import '../../../helpers/database.dart';
import '../../../store/store_screenshots_test.dart' show appOverrides, now;

void main() {
  test('the demo data gives the Day Score a history to show', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    await DriftDemoDataStore(db)
        .replace(DemoDataGenerator(now: now).generate());
    final container = ProviderContainer(overrides: appOverrides(db));
    addTearDown(container.dispose);

    final history = await container.read(dayScoreHistoryProvider.future);
    final today = LocalDate(now.year, now.month, now.day);
    final scored = [
      for (final date in history.dates)
        if (history.scoredOn(date) != null) date,
    ];

    expect(history.today, today);
    expect(history.scoredOn(today.addDays(-1)), isNotNull);
    expect(scored.length, greaterThanOrEqualTo(7));
    printOnFailure('scored ${scored.length} of ${history.dates.length}');
  });
}
