import 'package:flutter_riverpod/misc.dart';
import 'package:open_ring/features/demo/application/demo_mode_controller.dart';
import 'package:open_ring/features/demo/domain/demo_data.dart';
import 'package:open_ring/features/demo/domain/demo_data_store.dart';
import 'package:open_ring/features/demo/domain/demo_mode_store.dart';

class RecordingDemoDataStore implements DemoDataStore {
  final replaced = <DemoData>[];
  int wipes = 0;
  Error? replaceError;
  Error? wipeError;

  @override
  Future<void> replace(DemoData data) async {
    final error = replaceError;
    if (error != null) throw error;
    replaced.add(data);
  }

  @override
  Future<void> wipe() async {
    final error = wipeError;
    if (error != null) throw error;
    wipes++;
  }
}

List<Override> demoOverrides({
  InMemoryDemoModeStore? store,
  RecordingDemoDataStore? data,
}) => [
  demoModeStoreProvider.overrideWithValue(store ?? InMemoryDemoModeStore()),
  demoDataStoreProvider.overrideWithValue(data ?? RecordingDemoDataStore()),
];
