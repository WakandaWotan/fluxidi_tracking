import 'event_models.dart';
import 'event_seed_data.dart';

abstract class EventDataSource {
  List<EventDetailData>? getInitialEvents() => null;

  Future<List<EventDetailData>> loadEvents();
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
}
