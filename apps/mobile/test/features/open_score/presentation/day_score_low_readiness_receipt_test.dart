import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/widgets/metric_card.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/modules/domain/module_store.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/open_score/domain/day_score_history.dart';
import 'package:open_ring/features/open_score/presentation/day_score_receipt_screen.dart';

import '../../../helpers/day_score_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';

const lowText =
    'Goal of the day: 4,800 steps, 60% of 8,000, because readiness was low '
    '(48). With the full goal the steps would earn 7.5 of 15 points.';

Future<void> pumpYesterday(
  WidgetTester tester,
  DayScoreInputs yesterday,
) async {
  final history = DayScoreHistory(
    today: metricsToday,
    days: {metricsToday.addDays(-1): yesterday, metricsToday: day()},
  );
  await pumpScaled(
    tester,
    screenHost(const DayScoreReceiptScreen()),
    textScaler: TextScaler.noScaling,
    brightness: Brightness.dark,
    locale: const Locale('en'),
    overrides: <Override>[
      clockProvider.overrideWithValue(() => metricsNow),
      moduleStoreProvider.overrideWithValue(
        InMemoryModuleStore(const {ModuleId.openScore}),
      ),
      dayScoreHistoryProvider.overrideWith((ref) async => history),
    ],
    size: const Size(360, 6000),
  );
  await tester.tap(find.byKey(DayScoreReceiptKeys.previous));
  await tester.pumpAndSettle();
}

String captionOf(WidgetTester tester) => tester
    .widget<CaptionText>(find.byKey(DayScoreReceiptKeys.lowReadiness))
    .text;

void main() {
  group('the receipt of a low readiness day', () {
    testWidgets('says the goal of the day and what the full goal earns', (
      tester,
    ) async {
      await pumpYesterday(tester, day(steps: 4000, readiness: 48));

      expect(captionOf(tester), lowText);
    });

    testWidgets('a day with readiness 80 shows no note', (tester) async {
      await pumpYesterday(tester, day(steps: 4000, readiness: 80));

      expect(find.byKey(DayScoreReceiptKeys.lowReadiness), findsNothing);
    });

    testWidgets('a day without readiness shows no note', (tester) async {
      await pumpYesterday(tester, day(steps: 4000));

      expect(find.byKey(DayScoreReceiptKeys.lowReadiness), findsNothing);
    });

    testWidgets('a low day without steps shows no note', (tester) async {
      await pumpYesterday(tester, day(steps: null, readiness: 48));

      expect(find.byKey(DayScoreReceiptKeys.lowReadiness), findsNothing);
    });
  });
}
