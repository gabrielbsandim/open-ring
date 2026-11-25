import 'package:metrics/metrics.dart';
import 'package:test/test.dart';

void main() {
  group('energyStepped rounds to 50, half away from zero', () {
    test('exactly -125 is -150', () {
      expect(energyStepped(-125), -150);
    });

    test('exactly 125 is 150', () {
      expect(energyStepped(125), 150);
    });

    test('just inside the half stays', () {
      expect(energyStepped(-124.99), -100);
      expect(energyStepped(124.99), 100);
    });

    test('zero and exact multiples stay', () {
      expect(energyStepped(0), 0);
      expect(energyStepped(-450), -450);
      expect(energyStepped(300), 300);
    });

    test('energyRange keeps using it', () {
      expect(energyRange(1000, 0.1), (low: 900, high: 1100));
    });
  });

  group('stepKilometers', () {
    test('2000 steps at 178 cm is 1.4774 km', () {
      expect(
        stepKilometers(steps: 2000, centimeters: 178),
        closeTo(1.4774, 0.00001),
      );
    });

    test('zero steps is zero km', () {
      expect(stepKilometers(steps: 0, centimeters: 178), 0);
    });

    test('stepEnergy is 0.5 kcal per kg per km of it', () {
      final km = stepKilometers(steps: 2000, centimeters: 178);
      final kcal = stepEnergy(
        steps: 2000,
        kilograms: 77.6045,
        centimeters: 178,
      );
      expect(kcal, closeTo(0.5 * 77.6045 * km, 1e-9));
      expect(kcal, closeTo(57.33, 0.01));
    });
  });
}
