import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/hotels/hotel_model.dart';
import 'package:fluxidi_tracking/hotels/ratehawk_search.dart';

HotelStay _stay({
  required String id,
  required String name,
  String address = 'Rue Duquesnoy 5, 1000 Brussels, Belgium',
  double lat = 50.845,
  double lng = 4.3543,
  String source = 'approved_local',
  String? provider,
  int? hid,
  String? priceHint,
  String? availabilityLabel,
}) {
  return HotelStay(
    id: id,
    name: name,
    type: HotelStayType.hotel,
    city: 'Brussel',
    region: 'Brussels',
    country: 'Belgium',
    address: address,
    description: '',
    imageRef: '',
    lat: lat,
    lng: lng,
    source: source,
    provider: provider,
    hid: hid,
    sourceId: hid?.toString(),
    externalProviderReference: hid?.toString(),
    priceHint: priceHint,
    availabilityLabel: availabilityLabel,
    isRealApproved: true,
  );
}

void main() {
  test('incomplete criteria means zero request', () async {
    final client = RecordingRatehawkHotelSearchClient();
    final controller = RatehawkSearchController(client: client);
    await controller.submit();
    expect(client.calls, isEmpty);
    expect(controller.requestCount, 0);
    expect(controller.state, RatehawkSearchLifecycleState.searchingDestination);
  });

  test('page-open equivalent: controller starts idle with zero requests', () {
    final client = RecordingRatehawkHotelSearchClient();
    final controller = RatehawkSearchController(client: client);
    expect(controller.state, RatehawkSearchLifecycleState.idle);
    expect(controller.requestCount, 0);
    expect(client.calls, isEmpty);
  });

  test('complete criteria can start a Booking-only search', () async {
    final client = RecordingRatehawkHotelSearchClient(
      response: const RatehawkSearchResponse(
        ok: true,
        invocationAllowed: false,
        warnings: <String>['ratehawk_invocation_blocked'],
      ),
    );
    final controller = RatehawkSearchController(client: client);
    controller.setCriteria(
      RatehawkSearchCriteria(
        destination: 'Brussel, Belgium',
        checkin: DateTime.utc(2026, 9, 3),
        checkout: DateTime.utc(2026, 9, 4),
      ),
    );
    await controller.submit();
    expect(client.calls, hasLength(1));
    expect(controller.state, RatehawkSearchLifecycleState.unavailable);
  });

  test('hid deduplicates and never matches by name alone', () {
    final existing = <HotelStay>[
      _stay(
        id: 'approved-warwick-brussels',
        name: 'Warwick Brussels',
        hid: 8473727,
      ),
      _stay(
        id: 'other-local',
        name: 'Same Name Hotel',
        address: 'Other street 1',
        lat: 51.0,
        lng: 4.0,
      ),
    ];
    final incoming = <HotelStay>[
      _stay(
        id: 'ratehawk:8473727',
        name: 'Warwick Brussels',
        source: 'ratehawk',
        provider: 'ratehawk',
        hid: 8473727,
        priceHint: '€180',
      ),
      _stay(
        id: 'ratehawk:8473727',
        name: 'Warwick Brussels',
        source: 'ratehawk',
        provider: 'ratehawk',
        hid: 8473727,
        priceHint: '€190',
      ),
      _stay(
        id: 'ratehawk:999',
        name: 'Same Name Hotel',
        source: 'ratehawk',
        provider: 'ratehawk',
        hid: 999,
        address: 'Different 9',
        lat: 50.1,
        lng: 4.1,
        priceHint: '€90',
      ),
    ];
    final merged = mergeRatehawkHotelStays(
      existing: existing,
      incoming: incoming,
    );
    expect(
      merged.where((stay) => stay.id == 'approved-warwick-brussels'),
      hasLength(1),
    );
    expect(
      merged
          .firstWhere((stay) => stay.id == 'approved-warwick-brussels')
          .priceHint,
      '€180',
    );
    expect(merged.any((stay) => stay.id == 'ratehawk:999'), isTrue);
    expect(
      resolveRatehawkHotelStayMatch(
        incoming: incoming.last,
        existing: existing,
      ).method,
      'name_only_rejected',
    );
  });

  test('stale price becomes Beschikbaarheid controleren', () {
    final stay = _stay(
      id: 'ratehawk:8473727',
      name: 'Warwick Brussels',
      source: 'ratehawk',
      provider: 'ratehawk',
      hid: 8473727,
    );
    expect(isRatehawkStalePrice(stay), isTrue);
    expect(displayRatehawkPriceHint(stay, 'nl'), kRatehawkStalePriceLabelNl);
    expect(ratehawkStalePriceLabel('en'), 'Checking availability');
    expect(ratehawkStalePriceLabel('fr'), isNotEmpty);
    expect(ratehawkStalePriceLabel('es'), isNotEmpty);
  });

  test('progressive insertion keeps existing cards first', () {
    final existing = <HotelStay>[
      _stay(id: 'approved-local-1', name: 'Local Stay'),
    ];
    final incoming = <HotelStay>[
      _stay(
        id: 'ratehawk:1',
        name: 'RateHawk One',
        source: 'ratehawk',
        hid: 1,
        lat: 50.9,
        lng: 4.4,
        address: 'Other 1',
      ),
    ];
    final merged = mergeRatehawkHotelStays(
      existing: existing,
      incoming: incoming,
    );
    expect(merged.first.id, 'approved-local-1');
    expect(merged.last.id, 'ratehawk:1');
  });

  test('NL EN FR ES state labels exist', () {
    for (final language in <String>['nl', 'en', 'fr', 'es']) {
      for (final state in RatehawkSearchLifecycleState.values) {
        expect(ratehawkStateLabel(state, language), isNotEmpty);
      }
      expect(ratehawkNeutralAvailabilityLabel(language), isNotEmpty);
    }
    expect(ratehawkNeutralAvailabilityLabel('nl'), 'Bekijk beschikbaarheid');
  });

  test(
    'unavailable RateHawk retains empty insertion and existing flow',
    () async {
      final client = RecordingRatehawkHotelSearchClient();
      final controller = RatehawkSearchController(client: client);
      controller.setCriteria(
        RatehawkSearchCriteria(
          destination: 'Brussel, Belgium',
          checkin: DateTime.utc(2026, 9, 3),
          checkout: DateTime.utc(2026, 9, 4),
        ),
      );
      await controller.submit();
      expect(controller.insertedStays, isEmpty);
      expect(controller.state, RatehawkSearchLifecycleState.unavailable);
    },
  );
}
