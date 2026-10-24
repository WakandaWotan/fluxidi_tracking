List<T> topUniqueById<T>({
  required Iterable<T> items,
  required String Function(T item) idOf,
  int limit = 3,
}) {
  if (limit <= 0) return <T>[];
  final out = <T>[];
  final seen = <String>{};
  var index = 0;
  for (final item in items) {
    final rawId = idOf(item).trim();
    final dedupeId = rawId.isEmpty ? '__idx_$index' : rawId;
    index += 1;
    if (!seen.add(dedupeId)) continue;
    out.add(item);
    if (out.length >= limit) break;
  }
  return out;
}
