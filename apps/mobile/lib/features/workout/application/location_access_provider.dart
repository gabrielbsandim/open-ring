import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/workout/domain/location_access.dart';
import 'package:open_ring/features/workout/infrastructure/geolocator_location_access.dart';

final locationAccessProvider = Provider<LocationAccess>(
  (ref) => GeolocatorLocationAccess(),
);
