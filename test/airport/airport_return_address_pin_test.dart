// The airport return address keeps its pin through a rewrite.
//
// Regression for the client side of the fixed return fare. Measured against the
// live worker: an airport round trip priced 200 + 200 answers 40000 cents while
// return coordinates are present, and answers HTTP 422 when the return address
// is rewritten without them. Losing the pin on every keystroke is what turned a
// good fixed fare into a refused quote.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/airport/airport_return_address_pin.dart';

const String kResolved =
    'Koekamerstraat 48A, 9688 Louise-Marie, Oost-Vlaanderen, België';

void main() {
  group('the pin survives an equivalent rewrite', () {
    test('the same address typed shorter keeps the pin', () {
      expect(
        airportReturnEditKeepsPin(
          anchor: kResolved,
          edited: 'Koekamerstraat 48A, 9688',
        ),
        isTrue,
      );
    });

    test('Louise-Marie rewritten as Maarkedal keeps the pin', () {
      // This exact rewrite made the live worker answer 422 once the pin was
      // gone, because Louise-Marie is a sub-municipality of Maarkedal.
      expect(
        airportReturnEditKeepsPin(
          anchor: kResolved,
          edited: 'Koekamerstraat 48A, 9688 Maarkedal',
        ),
        isTrue,
      );
    });

    test('casing and punctuation do not matter', () {
      expect(
        airportReturnEditKeepsPin(
          anchor: kResolved,
          edited: 'koekamerstraat 48a 9688 maarkedal',
        ),
        isTrue,
      );
    });
  });

  group('the pin is dropped for a different place', () {
    test('another street drops the pin', () {
      expect(
        airportReturnEditKeepsPin(
          anchor: kResolved,
          edited: 'Dorpstraat 48A, 9688 Maarkedal',
        ),
        isFalse,
      );
    });

    test('another house number drops the pin', () {
      expect(
        airportReturnEditKeepsPin(
          anchor: kResolved,
          edited: 'Koekamerstraat 12, 9688 Maarkedal',
        ),
        isFalse,
      );
    });

    test('another postcode drops the pin', () {
      expect(
        airportReturnEditKeepsPin(
          anchor: kResolved,
          edited: 'Koekamerstraat 48A, 9700 Oudenaarde',
        ),
        isFalse,
      );
    });

    test('a cleared field drops the pin', () {
      expect(airportReturnEditKeepsPin(anchor: kResolved, edited: ''), isFalse);
    });

    test('an anchor without a postcode never keeps a pin', () {
      expect(
        airportReturnEditKeepsPin(
          anchor: 'Koekamerstraat 48A',
          edited: 'Koekamerstraat 48A',
        ),
        isFalse,
      );
    });
  });

  group('address parts', () {
    test('the postcode is read, not the house number', () {
      expect(airportReturnPostcodeOf(kResolved), '9688');
      expect(airportReturnHouseNumberOf(kResolved), '48a');
    });

    test('a four digit group is never a house number', () {
      expect(airportReturnHouseNumberOf('Straat 9688'), '');
    });

    test('the street word skips leading numbers', () {
      expect(airportReturnStreetWordOf('48A Koekamerstraat'), 'koekamerstraat');
    });
  });
}
