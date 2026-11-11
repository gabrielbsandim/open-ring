import 'package:go_router/go_router.dart';
import 'package:open_ring/features/export/presentation/export_screen.dart';
import 'package:open_ring/features/health_sync/presentation/health_status_screen.dart';
import 'package:open_ring/features/settings/presentation/data_sources_screen.dart';
import 'package:open_ring/features/settings/presentation/settings_screen.dart';
import 'package:open_ring/features/widgets/presentation/today_widget_config_screen.dart';
import 'package:open_ring/features/widgets/presentation/widgets_screen.dart';

GoRoute settingsRoute() => GoRoute(
  path: 'settings',
  builder: (_, _) => const SettingsScreen(),
  routes: [
    GoRoute(path: 'health', builder: (_, _) => const HealthStatusScreen()),
    GoRoute(path: 'export', builder: (_, _) => const ExportScreen()),
    GoRoute(path: 'sources', builder: (_, _) => const DataSourcesScreen()),
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
