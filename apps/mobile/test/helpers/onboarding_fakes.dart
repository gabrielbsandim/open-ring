import 'dart:async';

import 'package:flutter_riverpod/misc.dart';
import 'package:open_ring/features/health_sync/application/health_sync_controller.dart';
import 'package:open_ring/features/onboarding/application/onboarding_controller.dart';
import 'package:open_ring/features/onboarding/domain/app_permissions.dart';
import 'package:open_ring/features/onboarding/domain/onboarding_store.dart';
import 'package:open_ring/features/ring/application/pair_controller.dart';
import 'package:open_ring/features/ring/application/pair_state.dart';
import 'package:open_ring/features/ring/application/ring_sync_controller.dart';
import 'package:open_ring/features/ring/application/ring_sync_state.dart';
import 'package:open_ring/features/ring/domain/discovered_device.dart';
import 'package:open_ring/features/ring/domain/ring_pairing.dart';
import 'package:open_ring/features/settings/application/user_profile_providers.dart';
import 'package:open_ring/features/settings/domain/user_profile.dart';
import 'package:ring_driver/ring_driver.dart';

import 'fake_health_writer.dart';

class InMemoryOnboardingStore implements OnboardingStore {
  new({this.completed = false});

  @override
  bool completed;

  int writes = 0;

  @override
  Future<void> complete() async {
    completed = true;
    writes++;
  }

  @override
  Future<void> reset() async {
    completed = false;
    writes++;
  }
}

class FakeAppPermissions implements AppPermissions {
  new({
    Map<AppPermission, PermissionStatus>? statuses,
    this.grantOnRequest = true,
  }) : statuses = statuses ?? {};

  final Map<AppPermission, PermissionStatus> statuses;
  bool grantOnRequest;
  final requests = <AppPermission>[];
  int settingsOpened = 0;

  @override
  Future<PermissionStatus> status(AppPermission permission) async =>
      statuses[permission] ?? PermissionStatus.denied;

  @override
  Future<PermissionStatus> request(AppPermission permission) async {
    requests.add(permission);
    final current = statuses[permission] ?? PermissionStatus.denied;
    if (current.isGranted) return current;
    final next = grantOnRequest
        ? PermissionStatus.granted
        : PermissionStatus.permanentlyDenied;
    statuses[permission] = next;
    return next;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

class FakeBluetoothRadio implements BluetoothRadio {
  new({this.on = true});

  bool on;
  int checks = 0;

  @override
  Future<bool> ensureOn() async {
    checks++;
    return on;
  }
}

class RecordingPairedRingStore implements PairedRingStore {
  new({this.fail = false});

  final bool fail;
  final saved = <RingIdentity>[];

  @override
  Future<void> save(RingIdentity ring, {required DateTime at}) async {
    if (fail) throw StateError('database is locked');
    saved.add(ring);
  }
}

class SeededPairController extends PairController {
  new(this.seed);

  final PairState seed;

  @override
  PairState build() {
    super.build();
    return seed;
  }
}

// Holds the sync open so a screen can be inspected mid-run.
class HeldRingSyncController extends RingSyncController {
  new(this.seed);

  final RingSyncState seed;
  final _never = Completer<void>();

  @override
  RingSyncState build() => seed;

  @override
  Future<void> refresh() => _never.future;
}

const colmiRing = DiscoveredDevice(
  id: 'AA:BB:CC:00:00:09',
  name: 'R09_F800',
  rssi: -52,
);

const bondedRing = DiscoveredDevice(
  id: 'AA:BB:CC:00:00:0A',
  name: 'R02_1A2B',
  rssi: 0,
);

const otherBand = DiscoveredDevice(
  id: 'AA:BB:CC:00:00:10',
  name: 'Mi Band 8',
  rssi: -40,
);

List<Override> onboardingOverrides({
  FakeAppPermissions? permissions,
  FakeBluetoothRadio? radio,
  RecordingPairedRingStore? pairedStore,
  UserProfileStore? profileStore,
  FakeHealthWriter? healthWriter,
  PairState? pairSeed,
}) => [
  appPermissionsProvider.overrideWithValue(permissions ?? FakeAppPermissions()),
  bluetoothRadioProvider.overrideWithValue(radio ?? FakeBluetoothRadio()),
  pairedRingStoreProvider.overrideWithValue(
    pairedStore ?? RecordingPairedRingStore(),
  ),
  userProfileStoreProvider.overrideWithValue(
    profileStore ?? InMemoryUserProfileStore(),
  ),
  healthWriterProvider.overrideWithValue(healthWriter ?? FakeHealthWriter()),
  if (pairSeed != null)
    pairProvider.overrideWith(() => SeededPairController(pairSeed)),
];
