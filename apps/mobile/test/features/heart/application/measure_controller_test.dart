import 'package:flutter_test/flutter_test.dart';
import 'package:open_ring/features/heart/application/measure_controller.dart';
import 'package:open_ring/features/heart/application/measure_state.dart';
import 'package:ring_driver/ring_driver.dart';

LiveReading _hr(int value, [int second = 0]) => LiveReading(
  kind: LiveKind.heartRate,
  value: value,
  at: DateTime.utc(2026, 11, 10, 22, 5, second),
);

void main() {
  test('the result is the median, stamped with the last reading', () {
    final result = spotResult([_hr(80, 1), _hr(70, 2), _hr(74, 3)]);

    expect(result?.value, 74);
    expect(result?.at, DateTime.utc(2026, 11, 10, 22, 5, 3));
    expect(spotResult([_hr(70), _hr(73)])?.value, 72);
    expect(spotResult(const []), isNull);
  });

  test('implausible live values are ignored', () {
    expect(plausibleLiveReading(_hr(29)), isFalse);
    expect(plausibleLiveReading(_hr(72)), isTrue);
    expect(plausibleLiveReading(_hr(221)), isFalse);
    LiveReading spo2(int value) =>
        LiveReading(kind: LiveKind.spo2, value: value, at: DateTime.utc(2026));
    expect(plausibleLiveReading(spo2(69)), isFalse);
    expect(plausibleLiveReading(spo2(97)), isTrue);
    expect(plausibleLiveReading(spo2(101)), isFalse);
  });

  test('state reports progress and time left', () {
    const state = MeasureState(
      phase: MeasurePhase.reading,
      elapsed: Duration(seconds: 12),
      latest: 71,
    );

    expect(state.running, isTrue);
    expect(state.progress, closeTo(0.4, 1e-9));
    expect(state.remaining, const Duration(seconds: 18));
    expect(state.shownValue, 71);
    expect(const MeasureState().running, isFalse);
    expect(const MeasureState(phase: MeasurePhase.done).progress, 1);
  });
}
