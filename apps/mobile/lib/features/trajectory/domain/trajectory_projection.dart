import 'package:metrics/metrics.dart';

/// The 4 week band as it stood on [monday], kept to grade it later and never
/// edited.
final class TrajectoryProjection {
  const new({
    required this.monday,
    required this.trendKg,
    required this.rateKgPerWeek,
    required this.lowKg,
    required this.midKg,
    required this.highKg,
    required this.createdAt,
  });

  final LocalDate monday;
  final double trendKg;
  final double rateKgPerWeek;
  final double lowKg;
  final double midKg;
  final double highKg;
  final DateTime createdAt;
}
