import 'package:meta/meta.dart';
import 'package:ring_driver/ring_driver.dart';

const defaultMeasureWindow = Duration(seconds: 30);

enum MeasurePhase { idle, connecting, searching, reading, done, failed }

enum MeasureFailure { noRing, busy, unreachable, noReading }

@immutable
final class MeasureTiming {
  const new({
    this.window = defaultMeasureWindow,
    this.tick = const Duration(seconds: 1),
    this.connectTimeout = const Duration(seconds: 20),
  });

  final Duration window;
  final Duration tick;
  final Duration connectTimeout;
}

@immutable
final class MeasureResult {
  const new({required this.reading, required this.saved});

  final LiveReading reading;
  final bool saved;
}

@immutable
final class MeasureState {
  const new({
    this.kind = LiveKind.heartRate,
    this.phase = MeasurePhase.idle,
    this.window = defaultMeasureWindow,
    this.elapsed = Duration.zero,
    this.latest,
    this.result,
    this.failure,
    this.cancelled = false,
  });

  final LiveKind kind;
  final MeasurePhase phase;
  final Duration window;
  final Duration elapsed;
  final int? latest;
  final MeasureResult? result;
  final MeasureFailure? failure;
  final bool cancelled;

  bool get running => switch (phase) {
    MeasurePhase.connecting ||
    MeasurePhase.searching ||
    MeasurePhase.reading => true,
    MeasurePhase.idle || MeasurePhase.done || MeasurePhase.failed => false,
  };

  Duration get remaining {
    final left = window - elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  double get progress {
    if (phase == MeasurePhase.done) return 1;
    if (window <= Duration.zero) return 0;
    return (elapsed.inMilliseconds / window.inMilliseconds).clamp(0, 1);
  }

  int? get shownValue => result?.reading.value ?? (running ? latest : null);

  MeasureState next({MeasurePhase? phase, Duration? elapsed, int? latest}) =>
      MeasureState(
        kind: kind,
        phase: phase ?? this.phase,
        window: window,
        elapsed: elapsed ?? this.elapsed,
        latest: latest ?? this.latest,
      );
}
