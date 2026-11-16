import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/activity/application/activity_providers.dart';
import 'package:open_ring/features/body/application/logged_weight.dart';
import 'package:open_ring/features/energy/domain/energy_day.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:open_ring/features/workout/application/workout_history_providers.dart';
import 'package:open_ring/features/workout/application/workout_source_selection.dart';
import 'package:open_ring/features/workout/domain/workout_history.dart';

// A workout outside the day can still hide an overlapping one inside it, so
// the selection runs over a wider window than the day.
const energySelectionPadding = Duration(days: 1);

final FutureProviderFamily<EnergyDay, LocalDate> energyDayProvider =
    FutureProvider.family<EnergyDay, LocalDate>((ref, day) async {
      ref.watch(dataRevisionProvider);
      final now = ref.watch(clockProvider)();
      final from = localMidnight(day, now.timeZoneOffset);
      final to = localMidnight(day.addDays(1), now.timeZoneOffset);
      final (profile, logged, slots, own, imported) = await (
        ref.watch(userProfileProvider.future),
        ref.watch(loggedWeightProvider.future),
        ref
            .watch(activityHistoryReaderProvider)
            .activitySlots(from: day, to: day),
        ref
            .watch(workoutHistoryReaderProvider)
            .intersecting(
              from: from.subtract(energySelectionPadding),
              to: to.add(energySelectionPadding),
            ),
        ref
            .watch(importedWorkoutReaderProvider)
            .intersecting(
              from: from.subtract(energySelectionPadding),
              to: to.add(energySelectionPadding),
            ),
      ).wait;
      final selected = selectWorkouts([
        ...own,
        ...imported.workouts,
      ], imported.priority);
      return energyDay(
        sex: _sexOf(profile?.sex),
        age: profile?.ageIn(day.year),
        kilograms: logged ?? profile?.weightKilograms,
        centimeters: profile?.heightCentimeters,
        slots: [
          for (final slot in slots)
            (start: slot.start, duration: slot.duration, steps: slot.steps),
        ],
        workouts: [
          for (final entry in selected)
            if (entry.end.isAfter(from) && entry.start.isBefore(to))
              _workoutOf(entry),
        ],
        from: from,
        to: to,
        now: now,
      );
    });

final energyTodayProvider = FutureProvider<EnergyDay>(
  (ref) => ref.watch(energyDayProvider(ref.watch(currentDateProvider)).future),
);

EnergySex? _sexOf(Sex? sex) => switch (sex) {
  null => null,
  Sex.female => EnergySex.female,
  Sex.male => EnergySex.male,
};

EnergyWorkout _workoutOf(WorkoutEntry entry) => (
  start: entry.start,
  end: entry.end,
  elapsed: entry.elapsed,
  met: entry.type.met,
  storedKilocalories: switch (entry) {
    WorkoutListItem(:final activeKilocalories) => activeKilocalories,
    ImportedWorkout() => null,
  },
);
