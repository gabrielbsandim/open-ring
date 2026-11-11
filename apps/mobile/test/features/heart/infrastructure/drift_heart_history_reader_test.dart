import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/core/database/app_database.dart';
import 'package:open_ring/features/heart/infrastructure/drift_heart_history_reader.dart';

import '../../../helpers/database.dart';

final _from = DateTime.utc(2026, 11, 10);
final _to = DateTime.utc(2026, 11, 10, 9);

int _ms(DateTime at) => at.millisecondsSinceEpoch;

void main() {
  late AppDatabase db;
  late DriftHeartHistoryReader reader;

  setUp(() async {
    db = await pairedDatabase();
    reader = DriftHeartHistoryReader(db);
  });

  test('heart rate is read as UTC instants inside [from, to)', () async {
    for (final (at, bpm) in [
      (_to, 90),
      (DateTime.utc(2026, 11, 10, 3), 55),
      (_from, 60),
      (_from.subtract(const Duration(minutes: 5)), 70),
    ]) {
      await db
          .into(db.hrSamples)
          .insert(
            HrSamplesCompanion.insert(
              deviceId: ringId,
              atUtcMs: _ms(at),
              offsetMinutes: 60,
              bpm: bpm,
            ),
          );
    }

    final samples = await reader.heartRate(from: _from, to: _to);

    expect(samples.map((s) => s.bpm), [60, 55]);
    expect(samples.first.at, _from);
    expect(samples.first.at.isUtc, isTrue);
  });

  test('HRV, SpO2 and stress read their own tables', () async {
    final at = DateTime.utc(2026, 11, 10, 2);
    await db
        .into(db.hrvSamples)
        .insert(
          HrvSamplesCompanion.insert(
            deviceId: ringId,
            atUtcMs: _ms(at),
            offsetMinutes: -180,
            milliseconds: 48,
          ),
        );
    await db
        .into(db.spo2Samples)
        .insert(
          Spo2SamplesCompanion.insert(
            deviceId: ringId,
            atUtcMs: _ms(at),
            offsetMinutes: -180,
            percent: 96,
          ),
        );
    await db
        .into(db.stressSamples)
        .insert(
          StressSamplesCompanion.insert(
            deviceId: ringId,
            atUtcMs: _ms(_to),
            offsetMinutes: -180,
            level: 40,
          ),
        );

    final (hrv, spo2, stress) = await (
      reader.hrv(from: _from, to: _to),
      reader.spo2(from: _from, to: _to),
      reader.stress(from: _from, to: _to),
    ).wait;

    expect(hrv.single, (at: at, milliseconds: 48));
    expect(spo2.single, (at: at, percent: 96));
    expect(stress, isEmpty);
    expect(
      await reader.stress(from: _from, to: _to.add(const Duration(seconds: 1))),
      [(at: _to, level: 40)],
    );
  });
}
