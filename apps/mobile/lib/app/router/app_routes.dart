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
  static const sleepFormula = '/sleep/formula';
  static const privacy = '/privacy';
  static const settings = '/ring/settings';
  static const settingsHealth = '/ring/settings/health';
  static const settingsExport = '/ring/settings/export';
  static const settingsSources = '/ring/settings/sources';
  static const settingsWidgets = '/ring/settings/widgets';
  static const settingsWidgetToday = '/ring/settings/widgets/today';
  static const protocolLab = '/ring/lab';
  static const measure = '/heart/measure';
  static const trends = '/heart/trends';
  static const pair = '/ring/pair';
  static const onboarding = '/onboarding';
  static const onboardingPermissions = '/onboarding/permissions';
  static const onboardingProfile = '/onboarding/profile';
  static const onboardingHealth = '/onboarding/health';
  static const onboardingPair = '/onboarding/pair';
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
}
