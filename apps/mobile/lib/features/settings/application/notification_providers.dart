import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_ring/features/settings/domain/notification_access.dart';

final notificationAccessProvider = Provider<NotificationAccess>(
  (ref) => InMemoryNotificationAccess(),
);

final FutureProvider<bool> notificationsEnabledProvider =
    FutureProvider.autoDispose(
      (ref) => ref.watch(notificationAccessProvider).enabled(),
    );
