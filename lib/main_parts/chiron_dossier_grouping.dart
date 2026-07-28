/* CHIRON-RELEASE-PRESENTATION-REPAIR-1 B:
 * Pure dossier grouper using only server-proven identity linkage.
 *
 * Canonical rule:
 *  - booking:<id> is preferred when a meaningful booking_id exists;
 *  - trip:<id> is used for direct rides without booking_id;
 *  - trip↔booking equivalence is established ONLY when a single event
 *    carries both ids (explicit server alias proof), never by Flutter guess.
 */

/// Identity fields read from one compliance event.
class ChironEventIdentities {
  const ChironEventIdentities({
    this.bookingIdRaw,
    this.tripIdRaw,
    this.eventIdRaw,
    this.createdAtUtcRaw,
  });

  final String? bookingIdRaw;
  final String? tripIdRaw;
  final String? eventIdRaw;
  final String? createdAtUtcRaw;
}

/// Groups events into dossiers. Stable for reversed arrival order when the
/// server alias (both ids on one event) or shared booking_id links them.
Map<String, List<E>> groupChironDossiers<E>({
  required Iterable<E> events,
  required ChironEventIdentities Function(E event) identitiesOf,
  bool Function(String value)? isMeaningfulIdentity,
}) {
  bool defaultMeaningful(String value) => value.trim().isNotEmpty;
  final meaningful = isMeaningfulIdentity ?? defaultMeaningful;

  String? bookingLabel(ChironEventIdentities ids) {
    final raw = ids.bookingIdRaw;
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty || !meaningful(trimmed)) return null;
    return 'booking:${trimmed.toLowerCase()}';
  }

  String? tripLabel(ChironEventIdentities ids) {
    final raw = ids.tripIdRaw;
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty || !meaningful(trimmed)) return null;
    return 'trip:${trimmed.toLowerCase()}';
  }

  String eventLabel(ChironEventIdentities ids, int index) {
    final rawEvent = ids.eventIdRaw;
    if (rawEvent != null && rawEvent.trim().isNotEmpty) {
      return 'event:${rawEvent.trim().toLowerCase()}';
    }
    final rawCreated = ids.createdAtUtcRaw;
    if (rawCreated != null && rawCreated.trim().isNotEmpty) {
      return 'event:${rawCreated.trim().toLowerCase()}';
    }
    return 'event:index_$index';
  }

  final parent = <String, String>{};
  final weight = <String, int>{};

  String find(String x) {
    var root = x;
    while (parent[root] != root) {
      parent[root] = parent[parent[root]!]!;
      root = parent[root]!;
    }
    return root;
  }

  void ensure(String label, int kindWeight) {
    if (!parent.containsKey(label)) {
      parent[label] = label;
      weight[label] = kindWeight;
    }
  }

  // booking > trip > event
  const bookingWeight = 3;
  const tripWeight = 2;
  const eventWeight = 1;

  void union(String a, String b) {
    final ra = find(a);
    final rb = find(b);
    if (ra == rb) return;
    final wa = weight[ra] ?? 0;
    final wb = weight[rb] ?? 0;
    if (wa >= wb) {
      parent[rb] = ra;
    } else {
      parent[ra] = rb;
    }
  }

  final eventList = events.toList(growable: false);
  final perEventLabels = <List<String>>[];

  for (var index = 0; index < eventList.length; index++) {
    final ids = identitiesOf(eventList[index]);
    final labels = <String>[];
    final booking = bookingLabel(ids);
    if (booking != null) {
      ensure(booking, bookingWeight);
      labels.add(booking);
    }
    final trip = tripLabel(ids);
    if (trip != null) {
      ensure(trip, tripWeight);
      labels.add(trip);
    }
    if (labels.isEmpty) {
      final ev = eventLabel(ids, index);
      ensure(ev, eventWeight);
      labels.add(ev);
    }
    // Explicit server alias: both booking_id and trip_id on the same event.
    for (var i = 1; i < labels.length; i++) {
      union(labels[0], labels[i]);
    }
    perEventLabels.add(labels);
  }

  final grouped = <String, List<E>>{};
  for (var index = 0; index < eventList.length; index++) {
    final root = find(perEventLabels[index].first);
    grouped.putIfAbsent(root, () => <E>[]).add(eventList[index]);
  }
  return grouped;
}

/// Canonical ride key for a single event without cross-event bridging.
String chironCanonicalRideKey({
  required String? bookingId,
  required String? tripId,
  required String? eventId,
  required int index,
  bool Function(String value)? isMeaningfulIdentity,
}) {
  bool meaningful(String value) =>
      (isMeaningfulIdentity ?? (v) => v.trim().isNotEmpty)(value);
  final booking = (bookingId ?? '').trim();
  if (booking.isNotEmpty && meaningful(booking)) {
    return 'booking:${booking.toLowerCase()}';
  }
  final trip = (tripId ?? '').trim();
  if (trip.isNotEmpty && meaningful(trip)) {
    return 'trip:${trip.toLowerCase()}';
  }
  final event = (eventId ?? '').trim();
  if (event.isNotEmpty) return 'event:${event.toLowerCase()}';
  return 'event:index_$index';
}
