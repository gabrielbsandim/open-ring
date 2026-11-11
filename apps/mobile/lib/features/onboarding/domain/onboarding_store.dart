abstract interface class OnboardingStore {
  bool get completed;

  Future<void> complete();

  Future<void> reset();
}
