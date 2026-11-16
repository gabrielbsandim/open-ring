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

// A workout outside the day can still hide one inside it, or cover a bucket
// stored on this date under another offset, so the read is wider than the day.
const energySelectionPadding = Duration(days: 1);

// The instant a day is computed at. New data moves it, and so does whoever
// invalidates it, which is how a screen asks for the day at the clock of now.
final energyAsOfProvider = Provider<DateTime>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.read(clockProvider)();
});

typedef _Inputs = ({
  EnergySex? sex,
  int? age,
  double? kilograms,
  double? centimeters,
  List<StepBucket> slots,
  List<EnergyWorkout> workouts,
  DateTime from,
  DateTime to,
  DateTime now,
});

final FutureProviderFamily<_Inputs, LocalDate> _energyInputsProvider =
    FutureProvider.family<_Inputs, LocalDate>((ref, day) async {
      final now = ref.watch(energyAsOfProvider);
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
      return (
        sex: _sexOf(profile?.sex),
        age: profile?.ageIn(day.year),
        kilograms: logged ?? profile?.weightKilograms,
        centimeters: profile?.heightCentimeters,
        slots: [
          for (final slot in slots)
            (start: slot.start, duration: slot.duration, steps: slot.steps),
        ],
        workouts: selected.map(_workoutOf).toList(),
        from: from,
        to: to,
        now: now,
      );
    });

final FutureProviderFamily<EnergyDay, LocalDate> energyDayProvider =
    FutureProvider.family<EnergyDay, LocalDate>((ref, day) async {
      final inputs = await ref.watch(_energyInputsProvider(day).future);
      return energyDay(
        sex: inputs.sex,
        age: inputs.age,
        kilograms: inputs.kilograms,
        centimeters: inputs.centimeters,
        slots: inputs.slots,
        workouts: inputs.workouts,
        from: inputs.from,
        to: inputs.to,
        now: inputs.now,
      );
    });

// Today hour by hour, from the same inputs and the same instant as the day.
final energyTodayCurveProvider = FutureProvider<EnergyCurve>((ref) async {
  final asOf = ref.watch(energyAsOfProvider);
  final today = LocalDate.fromInstant(asOf, asOf.timeZoneOffset);
  final inputs = await ref.watch(_energyInputsProvider(today).future);
  return energyCurve(
    sex: inputs.sex,
    age: inputs.age,
    kilograms: inputs.kilograms,
    centimeters: inputs.centimeters,
    slots: inputs.slots,
    workouts: inputs.workouts,
    from: inputs.from,
    to: inputs.to,
    now: inputs.now,
  );
});

// Today is the date of the instant, so a resume after midnight moves the day
// together with the clock.
final energyTodayProvider = FutureProvider<EnergyDay>((ref) {
  final asOf = ref.watch(energyAsOfProvider);
  final today = LocalDate.fromInstant(asOf, asOf.timeZoneOffset);
  return ref.watch(energyDayProvider(today).future);
});

typedef EnergyNow = ({EnergyDay day, DateTime asOf});

// Today together with the instant it was computed at, so a view that still
// shows the last day while a new one loads keeps the time of that day.
final energyNowProvider = FutureProvider<EnergyNow>((ref) async {
  final asOf = ref.watch(energyAsOfProvider);
  return (day: await ref.watch(energyTodayProvider.future), asOf: asOf);
});

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
