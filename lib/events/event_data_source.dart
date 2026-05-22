import 'event_models.dart';
import 'event_seed_data.dart';

abstract class EventDataSource {
  List<EventDetailData>? getInitialEvents() => null;

  Future<List<EventDetailData>> loadEvents();

  Future<EventFeedResult> loadEventFeed({
    EventFeedQuery query = const EventFeedQuery(),
  }) async {
    final events = await loadEvents();
    return EventFeedResult(
      events: events,
      source: 'load_events',
      receivedAtUtc: DateTime.now().toUtc(),
      isFromCache: false,
      warnings: const <String>[],
    );
  }
}

class LocalSeedEventDataSource implements EventDataSource {
  const LocalSeedEventDataSource();

  @override
  List<EventDetailData> getInitialEvents() {
    return kEventSeedData;
  }

  @override
  Future<List<EventDetailData>> loadEvents() async {
    return kEventSeedData;
  }

  @override
  Future<EventFeedResult> loadEventFeed({
    EventFeedQuery query = const EventFeedQuery(),
  }) async {
    return EventFeedResult(
      events: kEventSeedData,
      source: 'local_seed',
      receivedAtUtc: DateTime.now().toUtc(),
      isFromCache: false,
      warnings: const <String>[],
    );
  }
}
