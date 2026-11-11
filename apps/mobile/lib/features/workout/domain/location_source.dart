import 'package:open_ring/features/workout/domain/location_fix.dart';

enum LocationProblem { serviceDisabled, denied, deniedForever, failed }

final class LocationUnavailable implements Exception {
  const new(this.problem);

  final LocationProblem problem;

  @override
  String toString() => 'LocationUnavailable(${problem.name})';
}

final class LocationNotice {
  const new({required this.title, required this.text, required this.channel});

  final String title;
  final String text;
  final String channel;
}

abstract interface class LocationSource {
  Stream<LocationFix> fixes(LocationNotice notice);
}
