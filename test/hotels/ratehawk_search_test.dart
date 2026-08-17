import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/hotels/hotel_model.dart';
import 'package:fluxidi_tracking/hotels/ratehawk_search.dart';

class _DelayedRatehawkHotelSearchClient implements RatehawkHotelSearchClient {
  _DelayedRatehawkHotelSearchClient(this.responses, this.shouldReleaseFirst);

  final List<RatehawkSearchResponse> responses;
  final bool Function() shouldReleaseFirst;
  int _index = 0;

  @override
  Future<RatehawkSearchResponse> search(RatehawkSearchCriteria criteria) async {
    final index = _index++;
    if (index == 0) {
      while (!shouldReleaseFirst()) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }
    return responses[index];
  }
}

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

  test('per-stay rhctx1 is parsed and bound to hid/dates/guests', () {
    final payload = <String, dynamic>{
      'ok': true,
      'ratehawk': <String, dynamic>{'invocation_allowed': true},
      'retrieved_at': 1755424800000,
      'stays': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'ratehawk:6117198',
          'name': 'Example Brussels Hotel',
          'type': 'hotel',
          'address': 'Rue Example 1, 1000 Brussels',
          'city': 'Brussels',
          'region': 'Brussels',
          'country': 'BE',
          'lat': 50.8467,
          'lng': 4.3525,
          'source': 'ratehawk',
          'provider': 'ratehawk',
          'provider_id': '6117198',
          'hid': 6117198,
          'price_label': 'EUR 180.00',
          'view_stay_context': 'rhctx1.payload.sig',
          'view_stay_context_expires_at': 1755425700000,
          'stay_context': <String, dynamic>{
            'hid': 6117198,
            'checkin': '2026-09-03',
            'checkout': '2026-09-04',
            'residency': 'be',
            'currency': 'EUR',
            'guests': <Map<String, dynamic>>[
              <String, dynamic>{'adults': 2, 'children': <int>[]},
            ],
          },
        },
      ],
    };
    final parsed = parseRatehawkPublicSearchPayload(payload);
    expect(parsed.invocationAllowed, isTrue);
    expect(parsed.stays, hasLength(1));
    expect(parsed.stays.single.hid, 6117198);
    expect(parsed.stays.single.viewStay, isNotNull);
    expect(parsed.stays.single.viewStay!.hid, 6117198);
    expect(parsed.stays.single.viewStay!.checkin, '2026-09-03');
    expect(parsed.stays.single.viewStay!.residency, 'be');
    expect(parsed.stays.single.viewStay!.currency, 'EUR');
    expect(parsed.stays.single.viewStay!.guests.single.adults, 2);
  });

  test('cancelled or superseded results are not inserted', () async {
    var releaseFirst = false;
    final first = RatehawkSearchResponse(
      ok: true,
      invocationAllowed: true,
      stays: <HotelStay>[
        _stay(
          id: 'ratehawk:1',
          name: 'First',
          source: 'ratehawk',
          hid: 1,
          lat: 50.9,
          lng: 4.4,
          address: 'First 1',
          priceHint: 'EUR 10.00',
        ),
      ],
    );
    final second = RatehawkSearchResponse(
      ok: true,
      invocationAllowed: true,
      stays: <HotelStay>[
        _stay(
          id: 'ratehawk:2',
          name: 'Second',
          source: 'ratehawk',
          hid: 2,
          lat: 50.8,
          lng: 4.3,
          address: 'Second 2',
          priceHint: 'EUR 20.00',
        ),
      ],
    );
    final client = _DelayedRatehawkHotelSearchClient(<RatehawkSearchResponse>[
      first,
      second,
    ], () => releaseFirst);
    final controller = RatehawkSearchController(client: client);
    controller.setCriteria(
      RatehawkSearchCriteria(
        destination: 'Brussel, Belgium',
        checkin: DateTime.utc(2026, 9, 3),
        checkout: DateTime.utc(2026, 9, 4),
      ),
    );
    final firstSubmit = controller.submit();
    await Future<void>.delayed(Duration.zero);
    await controller.submit();
    releaseFirst = true;
    await firstSubmit;
    expect(controller.insertedStays, hasLength(1));
    expect(controller.insertedStays.single.hid, 2);
    expect(controller.requestCount, 2);
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
