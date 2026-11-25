import 'package:metrics/metrics.dart' show LocalDate;

/// The day Weekly energy was turned on and how many soft mode screenings
/// existed then; any newer one ends it.
typedef FoodEnergyOptIn = ({LocalDate on, int softSeen});

abstract interface class FoodEnergyStore {
  /// Null when it was never turned on or the stored value is unreadable.
  Future<FoodEnergyOptIn?> read();

  Future<void> write(FoodEnergyOptIn optIn);

  Future<void> clear();
}

final class InMemoryFoodEnergyStore implements FoodEnergyStore {
  new([this.optIn]);

  FoodEnergyOptIn? optIn;

  @override
  Future<FoodEnergyOptIn?> read() async => optIn;

  @override
  Future<void> write(FoodEnergyOptIn optIn) async => this.optIn = optIn;

  @override
  Future<void> clear() async => optIn = null;
}
