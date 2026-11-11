import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/records/source_priority.dart';

void main() {
  const watch = 'com.garmin.android.apps.connectmobile';
  const band = 'com.mi.health';

  group('resolveSourcePriority', () {
    test('puts the ring first when nothing is stored', () {
      expect(resolveSourcePriority(const [], const [band, watch]), [
        ringSource,
        watch,
        band,
      ]);
    });

    test('keeps the stored order and appends new sources', () {
      expect(
        resolveSourcePriority(const [watch, ringSource], const [watch, band]),
        [watch, ringSource, band],
      );
    });

    test('drops sources without data and never lists OpenRing itself', () {
      expect(
        resolveSourcePriority(const [band, ringSource], const [ownPackage, '']),
        [ringSource],
      );
    });
  });

  group('moveSource', () {
    const order = [ringSource, watch, band];

    test('moves an entry to the new index', () {
      expect(moveSource(order, 2, 0), [band, ringSource, watch]);
      expect(moveSource(order, 0, 1), [watch, ringSource, band]);
    });

    test('ignores a move past either end', () {
      expect(moveSource(order, 0, -1), same(order));
      expect(moveSource(order, 2, 3), same(order));
      expect(moveSource(order, 1, 1), same(order));
    });
  });
}
