import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/hotels/google_places_refresh.dart';
import 'package:fluxidi_tracking/hotels/hotel_data_source.dart';
import 'package:fluxidi_tracking/hotels/hotel_model.dart';
import 'package:fluxidi_tracking/hotels/stay22_search.dart';

void main() {
  test('latest generation wins and stale generations are ignored', () {
    final gate = GooglePlacesRefreshGate();
    expect(gate.shouldStart('BE|Belgium||||'), isTrue);
    final first = gate.start('BE|Belgium||||');
    expect(gate.shouldStart('ES|Spain||||'), isTrue);
    final second = gate.start('ES|Spain||||');
    expect(gate.shouldApply(first), isFalse);
    expect(gate.shouldApply(second), isTrue);
    gate.complete(generation: first, key: 'BE|Belgium||||');
    expect(gate.appliedKey, isNull);
    gate.complete(generation: second, key: 'ES|Spain||||');
    expect(gate.appliedKey, 'ES|Spain||||');
    expect(gate.shouldStart('ES|Spain||||'), isFalse);
    final stale = gate.start('BE|Belgium||||');
    gate.invalidate();
    expect(gate.shouldApply(stale), isFalse);
  });

  test('coordinate centres produce distinct places query keys', () {
    final spirit = googlePlacesQueryKey(
      const HotelStayQuery(
        source: 'google-places',
        countryCode: 'BE',
        country: 'Belgium',
        lat: 50.59353,
        lng: 5.86109,
        radiusKm: 15,
      ),
    );
    final brussels = googlePlacesQueryKey(
      const HotelStayQuery(
        source: 'google-places',
        countryCode: 'BE',
        country: 'Belgium',
        lat: 50.847232,
        lng: 4.348831,
        radiusKm: 15,
      ),
    );
    final countrywide = googlePlacesQueryKey(
      const HotelStayQuery(
        source: 'google-places',
        countryCode: 'BE',
        country: 'Belgium',
      ),
    );
    expect(spirit, isNot(brussels));
    expect(spirit, isNot(countrywide));
    expect(spirit, contains('50.593530'));
    expect(spirit, contains('15.00'));
    expect(countrywide, isNot(contains('50.593530')));
  });

  test('unchanged query keys are not restarted', () {
    final gate = GooglePlacesRefreshGate();
    final key = googlePlacesQueryKey(
      const HotelStayQuery(
        source: 'google-places',
        countryCode: 'ES',
        country: 'Spain',
      ),
    );
    gate.start(key);
    gate.complete(generation: 1, key: key);
    expect(gate.shouldStart(key), isFalse);
  });

  test('location formatting skips empty components', () {
    expect(
      formatHotelStayLocation(city: 'Denmark', region: '', country: ''),
      'Denmark',
    );
    expect(
      formatHotelStayLocation(city: '', region: '', country: 'Denemarken'),
      'Denemarken',
    );
    expect(formatHotelStayLocation(city: '', region: '', country: ''), '');
    expect(
      hotelStayLocationLabel(
        const HotelStay(
          id: 'google_places:1',
          name: 'Hotel',
          type: HotelStayType.hotel,
          city: '',
          region: '',
          country: 'DK',
          address: 'Denmark',
          description: '',
          imageRef: '',
          lat: 55.6761,
          lng: 12.5683,
        ),
        'nl',
      ),
      'Denemarken',
    );
  });

  test('featured wording uses the actual unique card count', () {
    expect(stay22FeaturedCountLabel(7, 'nl'), '7 uitgelichte verblijven');
    expect(stay22FeaturedCountLabel(20, 'nl'), '20 uitgelichte verblijven');
    expect(
      stay22FeaturedFilterLabel(20, 'nl'),
      '20 uitgelichte verblijven in deze selectie',
    );
    expect(stay22FeaturedCountLabel(40, 'es'), '40 alojamientos destacados');
    expect(kGooglePlacesManualNextPageEnabled, isTrue);
  });

  test('localized P1B strings are complete in nl fr en es', () {
    for (final language in <String>['nl', 'fr', 'en', 'es']) {
      expect(stay22EmptyFeaturedTitle(language), isNotEmpty);
      expect(stay22EmptyFeaturedBody(language), isNotEmpty);
      expect(stay22CityRegionGuidance(language), isNotEmpty);
      expect(stay22UnseededGeoControlHint(language), isNotEmpty);
      expect(stay22BroadInspirationLabel(language), isNotEmpty);
      expect(stay22FeaturedExplanation(language), contains('Stay22'));
      expect(stay22MoreFeaturedStaysLabel(language), isNotEmpty);
      expect(stay22MajorCitiesPickerTitle(language), isNotEmpty);
      expect(stay22MajorCitiesFieldGuidance(language), isNotEmpty);
    }
    expect(stay22CityRegionGuidance('nl'), contains('Lissabon'));
    expect(stay22EmptyFeaturedBody('nl'), contains('Stay22'));
  });
}
