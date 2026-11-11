const ringSource = 'openring:ring';

const ownPackage = 'gbs.openring.app';

bool isExternalSource(String source) =>
    source.isNotEmpty && source != ownPackage && source != ringSource;

// Stored order first, limited to sources that still have data; the ring leads
// when it was never placed, and new sources join at the end.
List<String> resolveSourcePriority(List<String> stored, Iterable<String> seen) {
  final present = {ringSource, ...seen.where(isExternalSource)};
  final order = [
    for (final source in stored)
      if (present.contains(source)) source,
  ];
  if (!order.contains(ringSource)) order.insert(0, ringSource);
  final added = present.difference(order.toSet()).toList()..sort();
  return [...order, ...added];
}

List<String> moveSource(List<String> order, int from, int to) {
  if (from < 0 || from >= order.length) return order;
  if (to < 0 || to >= order.length || to == from) return order;
  final next = [...order];
  final source = next.removeAt(from);
  next.insert(to, source);
  return next;
}
