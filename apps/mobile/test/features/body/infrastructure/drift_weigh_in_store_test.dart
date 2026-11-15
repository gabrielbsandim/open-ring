import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/body/domain/weigh_in.dart';
import 'package:open_ring/features/body/infrastructure/drift_weigh_in_store.dart';

import '../../../helpers/database.dart';

void main() {
  test('a stored row lands in weigh_ins with the SQL column values', () async {
    final db = memoryDatabase();
    final store = DriftWeighInStore(db);

    await store.add(
      WeighInDraft(
        at: DateTime.utc(2026, 11, 14, 2, 50),
        offsetMinutes: -180,
        kilograms: 78.2,
        bodyFatPercent: 18.5,
        waistCentimeters: 82.4,
        source: WeighInSource.demo,
      ),
    );

    final row = await db.customSelect('SELECT * FROM weigh_ins').getSingle();
    expect(row.read<int>('at_utc_ms'), 1794624600000);
    expect(row.read<int>('offset_minutes'), -180);
    expect(row.read<double>('kilograms'), closeTo(78.2, 1e-9));
    expect(row.read<double>('body_fat_percent'), 18.5);
    expect(row.read<double>('waist_centimeters'), 82.4);
    expect(row.read<String>('source'), 'demo');
  });

  test('a user draft is stored with source manual and null extras', () async {
    final db = memoryDatabase();
    final store = DriftWeighInStore(db);

    await store.add(
      WeighInDraft(
        at: DateTime.utc(2026, 11, 14),
        offsetMinutes: 0,
        kilograms: 70,
      ),
    );

    final row = await db.customSelect('SELECT * FROM weigh_ins').getSingle();
    expect(row.read<String>('source'), 'manual');
    expect(row.readNullable<double>('body_fat_percent'), isNull);
    expect(row.readNullable<double>('waist_centimeters'), isNull);
  });
}
