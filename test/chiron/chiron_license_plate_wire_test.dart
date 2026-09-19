import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/chiron/chiron_license_plate_wire.dart';

void main() {
  test('T-XAA-674 becomes TXAA674 and meets CH1211', () {
    expect(chironOfficialKentekenplaatWire('T-XAA-674'), 'TXAA674');
    expect(chironOfficialPlateMeetsCh1211('T-XAA-674'), isTrue);
  });

  test('TAX002 stays TAX002 and is not padded to 7 characters', () {
    expect(chironOfficialKentekenplaatWire('TAX002'), 'TAX002');
    expect(chironOfficialPlateMeetsCh1211('TAX002'), isFalse);
    expect(chironOfficialKentekenplaatWire('TAX002')!.length, 6);
  });

  test('an invalid event plate yields to the fleet plate', () {
    expect(
      chironPreferredKentekenplaat(
        eventPlate: 'TAX002',
        fleetPlate: 'T-XAA-674',
      ),
      'T-XAA-674',
    );
  });

  test('a valid event plate is kept', () {
    expect(
      chironPreferredKentekenplaat(
        eventPlate: 'T-XAA-674',
        fleetPlate: '1-ABC-123',
      ),
      'T-XAA-674',
    );
  });
}
