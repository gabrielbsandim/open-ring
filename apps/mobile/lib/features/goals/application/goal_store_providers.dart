import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/goals/domain/goal_store.dart';

final goalStoreProvider = Provider<GoalStore>((ref) => InMemoryGoalStore());
