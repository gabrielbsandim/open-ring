import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/open_score/presentation/day_score_card.dart';

import '../../../helpers/day_score_fakes.dart';
import '../../../helpers/layout_harness.dart';
import '../../../helpers/metrics_fakes.dart';

const lowText =
    'Low readiness (48). Today the score asks for less: the step goal is '
    '4,800, 60% of your 8,000.';

Future<void> pumpCard(WidgetTester tester, DayScoreInputs today) => pumpScaled(
  tester,
  screenHost(
    const Scaffold(body: SingleChildScrollView(child: DayScoreCard())),
  ),
  textScaler: TextScaler.noScaling,
  brightness: Brightness.dark,
  locale: const Locale('en'),
  overrides: <Override>[
    clockProvider.overrideWithValue(() => metricsNow),
    dayScoreHistoryProvider.overrideWith((ref) async => historyOf(today)),
  ],
);

void main() {
  group('the card on a low readiness day', () {
    testWidgets('says the step goal is lower today', (tester) async {
      await pumpCard(tester, day(readiness: 48));

      expect(find.byKey(DayScoreCardKeys.lowReadiness), findsOneWidget);
      expect(find.text(lowText), findsOneWidget);
    });

    testWidgets('a day without readiness shows no note', (tester) async {
      await pumpCard(tester, day());

      expect(find.byKey(DayScoreCardKeys.card), findsOneWidget);
      expect(find.byKey(DayScoreCardKeys.lowReadiness), findsNothing);
    });

    testWidgets('readiness 55 shows no note', (tester) async {
      await pumpCard(tester, day(readiness: 55));

      expect(find.byKey(DayScoreCardKeys.lowReadiness), findsNothing);
    });
  });
}
