import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/open_score/application/day_score_providers.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/today/application/today_providers.dart';
import 'package:open_ring/features/widgets/application/widget_snapshot_builder.dart';

import '../../../helpers/metrics_fakes.dart';

Future<ProviderContainer> _afterFirstSave() async {
  final container = ProviderContainer.test(
    overrides: fullDataScenario.overrides(),
  );
  await container.read(userProfileProvider.future);
  await container
      .read(userProfileProvider.notifier)
      .save(const UserProfile(dailyStepGoal: 10000));
  return container;
}

void main() {
  test('the step goal provider reads the new goal after the save', () async {
    final container = await _afterFirstSave();

    expect(container.read(stepGoalProvider), 10000);
  });

  test('the activity day view carries the new goal after the save', () async {
    final container = await _afterFirstSave();

    final view = await container.read(activityDayProvider.future);

    expect(view.stepGoal, 10000);
  });

  test('the widget snapshot carries the new goal after the save', () async {
    final container = await _afterFirstSave();

    final snapshot = buildWidgetSnapshot(
      await container.read(todayViewProvider.future),
    );

    expect(snapshot.stepGoal, 10000);
  });

  test(
    'the day score history keeps the earlier goal for earlier days',
    () async {
      final container = ProviderContainer.test(
        overrides: fullDataScenario.overrides(),
      );
      await container.read(userProfileProvider.future);
      final before = await container.read(dayScoreHistoryProvider.future);
      final earlier = metricsToday.addDays(-7);
      expect(before.inputsOn(earlier)!.stepGoal, 8000);

      await container
          .read(userProfileProvider.notifier)
          .save(const UserProfile(dailyStepGoal: 10000));
      final after = await container.read(dayScoreHistoryProvider.future);

      expect(after.inputsOn(earlier)!.stepGoal, 8000);
      expect(after.inputsOn(metricsToday.addDays(-1))!.stepGoal, 8000);
      expect(after.inputsOn(metricsToday)!.stepGoal, 10000);
      expect(after.scoredOn(earlier)!.total, before.scoredOn(earlier)!.total);
    },
  );
}
