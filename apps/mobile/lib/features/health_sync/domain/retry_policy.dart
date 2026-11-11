import 'package:meta/meta.dart';

@immutable
final class RetryPolicy {
  const new({
    this.maxAttempts = 8,
    this.base = const Duration(minutes: 1),
    this.cap = const Duration(hours: 6),
  });

  final int maxAttempts;
  final Duration base;
  final Duration cap;

  DateTime? nextAttempt(int attempts, DateTime now) {
    if (attempts >= maxAttempts) return null;
    final delay = base * (1 << (attempts - 1).clamp(0, 30));
    return now.add(delay > cap ? cap : delay);
  }
}
