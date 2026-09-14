import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/auth_failure_kind.dart';
import 'package:fluxidi_tracking/company/booking_host_failure_text.dart';

String _en({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) => en;

void main() {
  test('socket errors stay user-facing and omit the raw URI', () {
    const error =
        'ClientException with SocketException: connection refused, address = 127.0.0.1, port = 53767, uri=http://127.0.0.1:8788/admin/tax/profile?tenant_id=fluxidi_fluxidi_ddmh9g';
    final text = bookingHostFailureUserText(error, _en);
    expect(text, isNot(contains('fluxidi_fluxidi')));
    expect(text, isNot(contains('SocketException')));
    expect(text.toLowerCase(), contains('connection'));
  });

  test('http 401 never repeats the raw status code', () {
    final text = bookingHostFailureUserTextForKind(
      AuthFailureKind.generic,
      _en,
      rawCode: 'http_401',
    );
    expect(text, isNot(contains('http_401')));
    expect(text.toLowerCase(), contains('session'));
  });
}
