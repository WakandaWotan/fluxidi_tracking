import 'event_data_source.dart';
import 'event_models.dart';

bool eventRecordHasPhoto(EventDetailData event) {
  bool filled(String? value) => (value ?? '').trim().isNotEmpty;
  return filled(event.heroImageUrl) ||
      filled(event.imageUrl) ||
      filled(event.thumbnailUrl);
}

/// Prefers the loaded record with the same id when the caller only has a
/// limited copy. A different id is ignored.
EventDetailData resolveEventRecordById(
  EventDetailData limited,
  Iterable<EventDetailData> loaded,
) {
  final id = limited.id.trim();
  if (id.isEmpty) return limited;
  for (final candidate in loaded) {
    if (candidate.id.trim() != id) continue;
    if (eventRecordHasPhoto(limited) && !eventRecordHasPhoto(candidate)) {
      return limited;
    }
    return candidate;
  }
  return limited;
}

/// Loads the full public record when [events] has no photo fields.
///
/// The lookup is the existing events feed, filtered by event id. Records that
/// already include a photo are left unchanged.
Future<List<EventDetailData>> loadMissingEventPhotos(
  EventDataSource source,
  List<EventDetailData> events,
) async {
  final resolved = <EventDetailData>[];
  for (final event in events) {
    if (eventRecordHasPhoto(event) || event.id.trim().isEmpty) {
      resolved.add(event);
      continue;
    }
    try {
      final detail = await source.loadEventFeed(
        query: EventFeedQuery(
          searchQuery: event.id.trim(),
          limit: 8,
          dateMode: EventDateMode.all,
        ),
      );
      resolved.add(resolveEventRecordById(event, detail.events));
    } catch (_) {
      resolved.add(event);
    }
  }
  return resolved;
}
