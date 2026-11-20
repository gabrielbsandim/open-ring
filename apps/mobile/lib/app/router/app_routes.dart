import 'package:metrics/metrics.dart';
import 'package:open_ring/features/goals/domain/goal_intake.dart';

enum AppTab {
  today('/today'),
  sleep('/sleep'),
  heart('/heart'),
  activity('/activity'),
  ring('/ring');

  new(this.path);

  final String path;
}

abstract final class AppPaths {
  static const readiness = '/today/readiness';
  static const readinessFormula = '/today/readiness/formula';
  static const body = '/today/body';
  static const effort = '/today/effort';
  static const effortFormula = '/today/effort/formula';
  static const energy = '/today/energy';
  static const energyFormula = '/today/energy/formula';
  static const food = '/today/food';
  static const foodGallery = '/today/food/gallery';

  static String foodGalleryOn(LocalDate day) => '$foodGallery?day=${day.iso}';
  static const dayScore = '/today/day-score';
  static const dayScoreFormula = '/today/day-score/formula';
  static const dayScoreHistory = '/today/day-score/history';
  static const dayScoreLevel = '/today/day-score/level';
  static const dayScoreOverall = '/today/day-score/overall';
  static const dayScoreOverallWeeks = '/today/day-score/overall/weeks';

  static String dayScoreOn(String isoDate) => '$dayScore?day=$isoDate';
  static const goals = '/today/goals';
  static const goalsPick = '/today/goals/pick';
  static const goalsReview = '/today/goals/review';
  static const goalsFormula = '/today/goals/formula';
  static const goalsEnd = '/today/goals/end';
  static const goalsRefused = '/today/goals/refused';
  static const goalsScreening = '/today/goals/screening';
  static const goalsSetup = '/today/goals/setup';
  static const goalsRefusedPregnancy = '/today/goals/pregnancy';

  static String goalsPickWith(GoalKind? kind) =>
      kind == null ? goalsPick : '$goalsPick?goal=${kind.name}';

  static String goalsRefusedFor(IntakeBlock block) =>
      '$goalsRefused/${block.name}';
  static const sleepFormula = '/sleep/formula';
  static const privacy = '/privacy';
  static const settings = '/ring/settings';
  static const settingsHealth = '/ring/settings/health';
  static const settingsExport = '/ring/settings/export';
  static const settingsSources = '/ring/settings/sources';
  static const settingsWorkoutNotification =
      '/ring/settings/workout-notification';
  static const settingsWidgets = '/ring/settings/widgets';
  static const settingsWidgetToday = '/ring/settings/widgets/today';
  static const settingsModules = '/ring/settings/modules';
  static const settingsModuleBody = '/ring/settings/modules/body';
  static const settingsModuleOpenScore = '/ring/settings/modules/open-score';
  static const settingsModuleEnergy = '/ring/settings/modules/energy';
  static const settingsModuleEffort = '/ring/settings/modules/effort';
  static const settingsModuleGoals = '/ring/settings/modules/goals';
  static const measure = '/heart/measure';
  static const trends = '/heart/trends';
  static const pair = '/ring/pair';
  static const onboarding = '/onboarding';
  static const onboardingPermissions = '/onboarding/permissions';
  static const onboardingProfile = '/onboarding/profile';
  static const onboardingHealth = '/onboarding/health';
  static const onboardingPair = '/onboarding/pair';
  static const onboardingModules = '/onboarding/modules';
  static const workout = '/activity/workout';
  static const workoutLocation = '/activity/workout/location';
  static const workoutLive = '/activity/live-workout';
  static const workoutSummary = '/activity/workout-summary';
  static const importedWorkout = '/activity/imported-workout';
}

enum PairFlow {
  onboarding(AppPaths.onboardingPair, step: 4),
  ring(AppPaths.pair);

  new(this.path, {this.step});

  final String path;
  final int? step;

  String errorPath(String reason) => '$path/error/$reason';

  String get syncPath => '$path/sync';

  String get donePath => switch (this) {
    PairFlow.onboarding => AppPaths.onboardingModules,
    PairFlow.ring => AppTab.today.path,
  };
}
