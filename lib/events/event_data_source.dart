import 'event_models.dart';
import 'event_seed_data.dart';

abstract class EventDataSource {
  Future<List<EventDetailData>> loadEvents();
}

class LocalSeedEventDataSource implements EventDataSource {
  const LocalSeedEventDataSource();

  @override
  Future<List<EventDetailData>> loadEvents() async {
    return kEventSeedData;
  }
}
