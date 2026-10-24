import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/public_company_code.dart';

void main() {
  test('accepts Worker public codes including local synthetic codes', () {
    expect(isValidPublicCompanyCode('FLX-4821'), isTrue);
    expect(isValidPublicCompanyCode('FLX-DEMO1'), isTrue);
    expect(isValidPublicCompanyCode('NTC-LIMO1'), isTrue);
    expect(isValidPublicCompanyCode('  flx-demo1  '), isTrue);
  });

  test('rejects empty, too short, too long, and illegal characters', () {
    expect(isValidPublicCompanyCode(''), isFalse);
    expect(isValidPublicCompanyCode('AB'), isFalse);
    expect(isValidPublicCompanyCode('A' * 25), isFalse);
    expect(isValidPublicCompanyCode('FLX.DEMO'), isFalse);
    expect(isValidPublicCompanyCode('FLX_DEMO1'), isFalse);
  });
}
