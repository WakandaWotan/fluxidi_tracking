import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/hotels/hotel_data_source.dart';
import 'package:fluxidi_tracking/hotels/ratehawk_search.dart';

void main() {
  test('maps a privacy-safe RateHawk card without hashes', () {
    final stay = hotelStayFromPublicHotelJson(<String, dynamic>{
      'id': 'ratehawk:8473727',
      'provider': 'ratehawk',
      'provider_id': '8473727',
      'name': 'Warwick Brussels',
      'type': 'hotel',
      'address': 'Rue Duquesnoy 5, 1000 Brussels, Belgium',
      'city': 'Brussel',
      'region': 'Brussels',
      'country': 'Belgium',
      'lat': 50.845,
      'lng': 4.3543,
      'price_label': '€180',
      'availability_label': '2 rooms',
      'source': 'ratehawk',
      'is_real_approved': true,
    });
    expect(stay, isNotNull);
    expect(stay!.hid, 8473727);
    expect(stay.priceHint, '€180');
    expect(stay.availabilityLabel, '2 rooms');
    expect(isRatehawkStay(stay), isTrue);
  });

  test('rejects name-only identity in public JSON without coordinates', () {
    final stay = hotelStayFromPublicHotelJson(<String, dynamic>{
      'id': 'ratehawk:1',
      'provider': 'ratehawk',
      'name': 'Nameless Match',
      'source': 'ratehawk',
    });
    expect(stay, isNull);
  });
}
