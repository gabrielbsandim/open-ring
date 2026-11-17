import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrics/metrics.dart';
import 'package:open_ring/core/clock/clock.dart';
import 'package:open_ring/core/records/data_revision.dart';
import 'package:open_ring/features/body/application/weight_summary.dart';
import 'package:open_ring/features/goals/application/goal_store_providers.dart';
import 'package:open_ring/features/goals/domain/goal.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';

final softModeProvider = FutureProvider<bool?>((ref) async {
  ref.watch(dataRevisionProvider);
  return newestSoftMode(await ref.watch(goalStoreProvider).screenings());
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
