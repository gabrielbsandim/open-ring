import 'package:go_router/go_router.dart';
import 'package:open_ring/features/ai/presentation/ai_connection_screen.dart';
import 'package:open_ring/features/ai/presentation/ai_key_info_screen.dart';
import 'package:open_ring/features/body/presentation/body_module_screen.dart';
import 'package:open_ring/features/effort/presentation/effort_module_screen.dart';
import 'package:open_ring/features/energy/presentation/energy_module_screen.dart';
import 'package:open_ring/features/export/presentation/export_screen.dart';
import 'package:open_ring/features/food/presentation/food_module_screen.dart';
import 'package:open_ring/features/food/presentation/food_storage_screen.dart';
import 'package:open_ring/features/goals/presentation/goals_module_screen.dart';
import 'package:open_ring/features/health_sync/presentation/health_status_screen.dart';
import 'package:open_ring/features/modules/presentation/modules_screen.dart';
import 'package:open_ring/features/open_score/presentation/open_score_module_screen.dart';
import 'package:open_ring/features/settings/presentation/data_sources_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_screen.dart';
import 'package:open_ring/features/widgets/presentation/today_widget_config_screen.dart';
import 'package:open_ring/features/widgets/presentation/widgets_screen.dart';
import 'package:open_ring/features/workout/presentation/workout_notification_how_screen.dart';

GoRoute settingsRoute() => GoRoute(
  path: 'settings',
  builder: (_, _) => const SettingsScreen(),
  routes: [
    GoRoute(path: 'health', builder: (_, _) => const HealthStatusScreen()),
    GoRoute(path: 'export', builder: (_, _) => const ExportScreen()),
    GoRoute(path: 'sources', builder: (_, _) => const DataSourcesScreen()),
    GoRoute(
      path: 'workout-notification',
      builder: (_, _) => const WorkoutNotificationHowScreen(),
    ),
    GoRoute(path: 'food-photos', builder: (_, _) => const FoodStorageScreen()),
    GoRoute(
      path: 'ai-connection',
      builder: (_, _) => const AiConnectionScreen(),
      routes: [
        GoRoute(path: 'key', builder: (_, _) => const AiKeyInfoScreen()),
      ],
    ),
    GoRoute(
      path: 'modules',
      builder: (_, _) => const ModulesScreen(),
      routes: [
        GoRoute(path: 'body', builder: (_, _) => const BodyModuleScreen()),
        GoRoute(
          path: 'open-score',
          builder: (_, _) => const OpenScoreModuleScreen(),
        ),
        GoRoute(path: 'energy', builder: (_, _) => const EnergyModuleScreen()),
        GoRoute(path: 'effort', builder: (_, _) => const EffortModuleScreen()),
        GoRoute(path: 'goals', builder: (_, _) => const GoalsModuleScreen()),
        GoRoute(path: 'food', builder: (_, _) => const FoodModuleScreen()),
      ],
    ),
    GoRoute(
      path: 'widgets',
      builder: (_, _) => const WidgetsScreen(),
      routes: [
        GoRoute(
          path: 'today',
          builder: (_, _) => const TodayWidgetConfigScreen(),
        ),
      ],
    ),
  ],
);
