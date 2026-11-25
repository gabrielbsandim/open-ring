import 'package:metrics/metrics.dart' show LocalDate;

typedef SoftScreeningIdentity = ({int? id, LocalDate on});

/// The day Weekly energy was turned on and the newest soft mode screening
/// then, null if none; any other newest soft row ends it.
typedef FoodEnergyOptIn = ({LocalDate on, SoftScreeningIdentity? soft});

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
