import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/events/event_models.dart';
import 'package:fluxidi_tracking/hotels/event_stay_search.dart';
import 'package:fluxidi_tracking/hotels/hotel_model.dart';

EventDetailData _event({
  required String id,
  required String locationName,
  required String city,
  String address = '',
  double lat = 0,
  double lng = 0,
  DateTime? startAtUtc,
  String? timeZone = 'Europe/Brussels',
}) {
  return EventDetailData(
    id: id,
    title: 'Concert',
    category: 'Muziek',
    dateTimeLabel: 'gepland',
    locationName: locationName,
    city: city,
    address: address,
    lat: lat,
    lng: lng,
    distanceOrStatus: '',
    gradient: const <Color>[],
    countryCode: 'BE',
    startAtUtc: startAtUtc,
    timeZone: timeZone,
  );
}

HotelStay _stay({
  required String id,
  required String name,
  double? latitude,
  double? longitude,
}) {
  return HotelStay(
    id: id,
    name: name,
    type: HotelStayType.hotel,
    city: name,
    region: '',
    country: 'Belgium',
    address: name,
    description: name,
    imageRef: '',
    lat: latitude ?? 0,
    lng: longitude ?? 0,
    latitude: latitude,
    longitude: longitude,
  );
}

void main() {
  test('Spirit of 66 uses coordinates and the next calendar day', () {
    final search = EventStaySearch.fromEvent(
      _event(
        id: 'spirit',
        locationName: 'Spirit of 66',
        city: 'Verviers',
        address: 'Place du Martyr, 16',
        lat: 50.59353,
        lng: 5.86109,
        startAtUtc: DateTime.utc(2026, 9, 25, 18),
      ),
    );

    expect(search.centerKind, EventStayCenterKind.coordinates);
    expect(search.venueLabel, 'Spirit of 66');
    expect(search.latitude, 50.59353);
    expect(search.longitude, 5.86109);
    expect(search.stay22Address, contains('Place du Martyr, 16'));
    expect(search.stay22Address, contains('Verviers'));
    expect(search.stay22Address, isNot(contains('Spirit of 66')));
    expect(search.checkinYmd, '2026-09-25');
    expect(search.checkoutYmd, '2026-09-26');
    expect(
      eventStayCoordinatesStillApply(
        search: search,
        destinationText: search.stay22Address,
      ),
      isTrue,
    );
    expect(
      eventStayCoordinatesStillApply(
        search: search,
        destinationText: 'Brussel',
      ),
      isFalse,
    );
  });

  test('a late UTC start uses the Brussels calendar day', () {
    final search = EventStaySearch.fromEvent(
      _event(
        id: 'late',
        locationName: 'Spirit of 66',
        city: 'Verviers',
        lat: 50.59353,
        lng: 5.86109,
        startAtUtc: DateTime.utc(2026, 10, 3, 22, 30),
      ),
    );

    expect(search.checkinYmd, '2026-10-04');
    expect(search.checkoutYmd, '2026-10-05');
  });

  test('missing coordinates fall back to the venue address, then the city', () {
    final address = EventStaySearch.fromEvent(
      _event(
        id: 'address',
        locationName: 'Spirit of 66',
        city: 'Verviers',
        address: 'Place du Martyr, 16',
      ),
    );
    expect(address.centerKind, EventStayCenterKind.address);
    expect(address.hasCoordinates, isFalse);
    expect(address.stay22Address, contains('Place du Martyr, 16'));

    final city = EventStaySearch.fromEvent(
      _event(
        id: 'city',
        locationName: 'Ancienne Belgique',
        city: 'Brussels',
      ),
    );
    expect(city.centerKind, EventStayCenterKind.city);
    expect(city.venueLabel, 'Ancienne Belgique');
    expect(city.stay22Address, contains('Brussels'));
    expect(city.stay22Address, isNot(contains('Ancienne Belgique')));
  });

  test('stays with coordinates sort nearest to the event first', () {
    const spiritLat = 50.59353;
    const spiritLng = 5.86109;
    final sorted = sortHotelStaysByEventDistance(
      stays: <HotelStay>[
        _stay(id: 'far', name: 'Hotel Brussel', latitude: 50.847232, longitude: 4.348831),
        _stay(id: 'none', name: 'Zonder locatie'),
        _stay(id: 'near', name: 'Hotel des Ardennes', latitude: 50.589, longitude: 5.87),
      ],
      latitude: spiritLat,
      longitude: spiritLng,
    );

    expect(sorted.map((stay) => stay.id).toList(), <String>[
      'near',
      'far',
      'none',
    ]);

    final brusselsFirst = sortHotelStaysByEventDistance(
      stays: sorted,
      latitude: 50.847232,
      longitude: 4.348831,
    );
    expect(brusselsFirst.first.id, 'far');
  });
}
