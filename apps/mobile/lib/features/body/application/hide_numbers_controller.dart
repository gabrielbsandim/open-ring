import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/body/domain/hide_numbers_store.dart';
import 'package:open_ring/features/modules/application/enabled_modules_controller.dart';
import 'package:open_ring/features/modules/domain/module_id.dart';

final hideNumbersStoreProvider = Provider<HideNumbersStore>(
  (ref) => InMemoryHideNumbersStore(),
);

final hideNumbersProvider = AsyncNotifierProvider<HideNumbersController, bool>(
  HideNumbersController.new,
);

class HideNumbersController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.watch(hideNumbersStoreProvider).read();

  Future<void> set({required bool hidden}) async {
    state = AsyncData(hidden);
    await ref.read(hideNumbersStoreProvider).write(hidden: hidden);
  }
}

// Until the choice is read the numbers stay hidden, so a hidden weight never
// shows for a frame.
final numbersHiddenProvider = Provider<bool>(
  (ref) => ref.watch(hideNumbersProvider).value ?? true,
);

final profileWeightHiddenProvider = Provider<bool>((ref) {
  final bodyOn =
      ref.watch(enabledModulesProvider).value?.contains(ModuleId.body) ?? true;
  return bodyOn && ref.watch(numbersHiddenProvider);
});
