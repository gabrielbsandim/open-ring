import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/application/goals_gate.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';
import 'package:open_ring/features/goals/domain/goal_setup.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

final softModeProvider = FutureProvider<bool?>((ref) async {
  ref.watch(dataRevisionProvider);
  return newestSoftMode(await ref.watch(goalStoreProvider).screenings());
});

final newestPregnancyProvider = FutureProvider<bool?>((ref) async {
  ref.watch(dataRevisionProvider);
  return newestPregnancy(await ref.watch(goalStoreProvider).screenings());
});

final asksPregnancyProvider = FutureProvider<bool>((ref) async {
  ref.watch(dataRevisionProvider);
  final profile = await ref.watch(userProfileProvider.future);
  return asksPregnancy(
    profile?.sex,
    await ref.watch(goalStoreProvider).screenings(),
  );
});

final intakeFactsProvider = FutureProvider<IntakeFacts>((ref) async {
  final today = ref.watch(currentDateProvider);
  final modules = await ref.watch(enabledModulesProvider.future);
  final profile = await ref.watch(userProfileProvider.future);
  final summary = await ref.watch(weightSummaryProvider.future);
  return (
    bodyOn: modules.contains(ModuleId.body),
    age: _youngestAge(profile, today.year),
    heightCm: profile?.heightCentimeters,
    trendKg: summary?.trend,
    softMode: await ref.watch(softModeProvider.future),
  );
});

// A birth year has no month: the refusal of minors takes the lowest age.
int? _youngestAge(UserProfile? profile, int year) {
  final age = profile?.ageIn(year);
  return age == null ? null : age - 1;
}

final goalStartControllerProvider = Provider<GoalStartController>(
  GoalStartController.new,
);

final class GoalStartController {
  const new(this.ref);

  final Ref ref;

  /// Starts a goal that reads no weight, with no lever yet. Null when Goals is
  /// off or a goal is already active.
  Future<Goal?> startWithoutWeight(GoalKind kind) async {
    if (kind == GoalKind.loseFat) throw ArgumentError.value(kind, 'kind');
    if (!ref.read(goalsEnabledProvider)) return null;
    final goal = await ref
        .read(goalStoreProvider)
        .start(
          GoalDraft(
            kind: kind,
            pace: null,
            startedOn: ref.read(currentDateProvider),
            anchorKg: null,
            referenceKg: null,
            levers: const [],
          ),
        );
    if (goal == null || !ref.mounted) return goal;
    ref.read(dataRevisionProvider.notifier).bump();
    return goal;
  }
}

final screeningControllerProvider = Provider<ScreeningController>(
  ScreeningController.new,
);

final class ScreeningController {
  const new(this.ref);

  final Ref ref;

  /// Stores the result and the date, never the answers. True is soft mode.
  Future<bool> submit(List<bool> answers) async {
    if (answers.length != goalScreeningQuestions) {
      throw ArgumentError.value(answers.length, 'answers');
    }
    final result = softMode(answers.where((yes) => yes).length);
    await ref
        .read(goalStoreProvider)
        .addScreening(
          GoalScreening(
            on: ref.read(currentDateProvider),
            softMode: result,
            pregnantOrBreastfeeding: null,
          ),
        );
    if (!ref.mounted) return result;
    ref.read(dataRevisionProvider.notifier).bump();
    return result;
  }
}

final softModeControllerProvider = Provider<SoftModeController>(
  SoftModeController.new,
);

final class SoftModeController {
  const new(this.ref);

  final Ref ref;

  /// Turns soft mode off with a row whose result is false. False, writing
  /// nothing, when Goals is off, in demo mode, or soft mode is not on.
  Future<bool> leave() async {
    // Demo history shares the tables, so a write in demo mode lands on the
    // real screenings.
    if (!ref.read(goalsEnabledProvider) || ref.read(demoModeProvider)) {
      return false;
    }
    final store = ref.read(goalStoreProvider);
    final rows = await store.screenings();
    if (newestSoftMode(rows) != true) return false;
    await store.addScreening(
      GoalScreening(
        on: _notBefore(ref.read(currentDateProvider), rows.firstOrNull?.on),
        softMode: false,
        pregnantOrBreastfeeding: null,
      ),
    );
    if (!ref.mounted) return true;
    ref.read(dataRevisionProvider.notifier).bump();
    return true;
  }
}

// Rows sort by date first, so a yes dated after today (a clock moved back)
// would still read as the newest answer over a row dated today.
LocalDate _notBefore(LocalDate today, LocalDate? newest) =>
    newest != null && newest.compareTo(today) > 0 ? newest : today;

final goalSetupControllerProvider = Provider<GoalSetupController>(
  GoalSetupController.new,
);

final class GoalSetupController {
  const new(this.ref);

  final Ref ref;

  /// Starts a lose fat goal from the setup, with the trend as its anchor and
  /// no lever yet. A yes to pregnancy is stored and starts nothing.
  Future<SetupOutcome> start({
    required GoalPace pace,
    required double? referenceKg,
    required bool? pregnantOrBreastfeeding,
  }) async {
    // Demo history shares the tables, so a write in demo mode lands on the
    // real goal.
    if (!ref.read(goalsEnabledProvider) || ref.read(demoModeProvider)) {
      return SetupOutcome.notAllowed;
    }
    final facts = await ref.read(intakeFactsProvider.future);
    final trendKg = facts.trendKg;
    final heightCm = facts.heightCm;
    if (trendKg == null || heightCm == null || !_setsUp(facts)) {
      return SetupOutcome.notAllowed;
    }
    final store = ref.read(goalStoreProvider);
    if (await store.active() != null) return SetupOutcome.alreadyActive;
    _checkReference(referenceKg, heightCm: heightCm, trendKg: trendKg);
    final rows = await store.screenings();
    final profile = await ref.read(userProfileProvider.future);
    final asked = asksPregnancy(profile?.sex, rows);
    if (asked && pregnantOrBreastfeeding == null) {
      throw ArgumentError.notNull('pregnantOrBreastfeeding');
    }
    final today = ref.read(currentDateProvider);
    var wrote = false;
    try {
      if (asked) {
        await store.addScreening(
          GoalScreening(
            on: _notBefore(today, rows.firstOrNull?.on),
            softMode: null,
            pregnantOrBreastfeeding: pregnantOrBreastfeeding,
          ),
        );
        wrote = true;
      }
      if (asked && pregnantOrBreastfeeding == true) {
        return SetupOutcome.pregnancy;
      }
      final goal = await store.start(
        GoalDraft(
          kind: GoalKind.loseFat,
          pace: pace,
          startedOn: today,
          anchorKg: trendKg,
          referenceKg: referenceKg,
          levers: const [],
        ),
      );
      wrote = wrote || goal != null;
      return goal == null ? SetupOutcome.alreadyActive : SetupOutcome.started;
    } finally {
      if (wrote && ref.mounted) ref.read(dataRevisionProvider.notifier).bump();
    }
  }

  bool _setsUp(IntakeFacts facts) =>
      switch (pickStep(GoalKind.loseFat, facts)) {
        PickWeight(next: IntakeNext.setup) => true,
        _ => false,
      };

  void _checkReference(
    double? referenceKg, {
    required double heightCm,
    required double trendKg,
  }) {
    if (referenceKg == null) return;
    final bounds = referenceBounds(heightCm: heightCm, trendKg: trendKg);
    final fits =
        bounds != null &&
        referenceKg >= bounds.minKg &&
        referenceKg <= bounds.maxKg;
    if (!fits) throw ArgumentError.value(referenceKg, 'referenceKg');
  }
}
