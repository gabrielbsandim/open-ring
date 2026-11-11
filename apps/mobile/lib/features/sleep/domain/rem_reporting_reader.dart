import 'package:metrics/metrics.dart';

abstract interface class RemReportingReader {
  Future<RemReporting> pairedRing();
}

final class UnknownRemReportingReader implements RemReportingReader {
  const new();

  @override
  Future<RemReporting> pairedRing() async => RemReporting.unknown;
}
