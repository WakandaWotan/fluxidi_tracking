import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/events/event_data_source.dart';
import 'package:fluxidi_tracking/events/event_models.dart';
import 'package:fluxidi_tracking/events/event_record_resolve.dart';

EventDetailData _event({required String id, String? imageUrl}) {
  return EventDetailData(
    id: id,
    title: 'Leuven Food & Culture Market',
    category: 'Vandaag',
    dateTimeLabel: 'Vandaag • 17:00',
    locationName: 'Grote Markt Leuven',
    city: 'Leuven',
    address: 'Grote Markt 1, 3000 Leuven, België',
    lat: 50.879842,
    lng: 4.700517,
    distanceOrStatus: '',
    gradient: const <Color>[Color(0xFF2E220B), Color(0xFF141108)],
    imageUrl: imageUrl,
  );
}

void main() {
  test('same event id keeps the loaded photo', () {
    final limited = _event(id: 'evt_leuven_food_market_2026');
    final full = _event(
      id: 'evt_leuven_food_market_2026',
      imageUrl: 'https://images.example/leuven-market.jpg',
    );
    final resolved = resolveEventRecordById(limited, <EventDetailData>[
      _event(id: 'other', imageUrl: 'https://images.example/other.jpg'),
      full,
    ]);
    expect(resolved.imageUrl, 'https://images.example/leuven-market.jpg');
    expect(resolved.id, limited.id);
  });

  test('a different id does not replace the limited record', () {
    final limited = _event(id: 'evt_leuven_food_market_2026');
    final resolved = resolveEventRecordById(limited, <EventDetailData>[
      _event(id: 'other', imageUrl: 'https://images.example/other.jpg'),
    ]);
    expect(resolved.imageUrl, isNull);
    expect(resolved.id, limited.id);
  });

  test('missing photos are loaded through the existing feed lookup', () async {
    final limited = _event(id: 'evt_leuven_food_market_2026');
    final full = _event(
      id: 'evt_leuven_food_market_2026',
      imageUrl: 'https://images.example/leuven-market.jpg',
    );
    final source = _LookupSource(limited: limited, full: full);
    final resolved = await loadMissingEventPhotos(source, <EventDetailData>[
      limited,
    ]);
    expect(resolved.single.imageUrl, full.imageUrl);
    expect(source.queries.single, limited.id);
  });
}

class _LookupSource implements EventDataSource {
  _LookupSource({required this.limited, required this.full});

  final EventDetailData limited;
  final EventDetailData full;
  final List<String> queries = <String>[];

  @override
  List<EventDetailData>? getInitialEvents() => <EventDetailData>[limited];

  @override
  Future<List<EventDetailData>> loadEvents() async => <EventDetailData>[
    limited,
  ];

  @override
  Future<EventFeedResult> loadEventFeed({
    EventFeedQuery query = const EventFeedQuery(),
  }) async {
    final search = (query.searchQuery ?? '').trim();
    queries.add(search);
    return EventFeedResult(
      events: <EventDetailData>[search == limited.id ? full : limited],
      source: 'test',
    );
  }
}
