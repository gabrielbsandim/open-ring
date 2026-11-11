enum UnitSystem { metric, imperial }

abstract final class ImperialUnits {
  static const centimetersPerInch = 2.54;
  static const kilogramsPerPound = 0.45359237;
  static const inchesPerFoot = 12;
  static const metersPerMile = 1609.344;
  static const metersPerFoot = 0.3048;

  static double inches(double centimeters) => centimeters / centimetersPerInch;

  static double centimeters(double inches) => inches * centimetersPerInch;

  static double pounds(double kilograms) => kilograms / kilogramsPerPound;

  static double kilograms(double pounds) => pounds * kilogramsPerPound;

  static double feet(double meters) => meters / metersPerFoot;
}

abstract interface class UnitSystemStore {
  Future<UnitSystem?> read();

  Future<void> write(UnitSystem units);
}

final class InMemoryUnitSystemStore implements UnitSystemStore {
  new([this.units]);

  UnitSystem? units;

  @override
  Future<UnitSystem?> read() async => units;

  @override
  Future<void> write(UnitSystem units) async => this.units = units;
}
