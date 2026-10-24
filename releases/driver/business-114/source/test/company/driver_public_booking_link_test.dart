import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/company/driver_public_booking_link.dart';
import 'package:fluxidi_tracking/company/company_public_booking_link.dart';
import 'company_public_booking_link_fixtures.dart';

void main() {
  for (final fault in [
    'none',
    'missing',
    'tenant',
    'vehicle',
    'driver',
    'expired',
    'changed',
    'web',
  ]) {
    test('driver without admin: $fault', () async {
      var current = true;
      final future = resolveDriverPublicBookingLink(
        tenantId: marioCompanyId,
        companyId: marioCompanyId,
        vehicleId: 'V0',
        driverId: 'D0',
        verifyDriver: () async {
          if (fault == 'expired') throw StateError('expired');
        },
        directoryLoader: () async => fault == 'missing'
            ? null
            : {
                'tenant_id': fault == 'tenant' ? 'other' : marioCompanyId,
                'company_id': marioCompanyId,
                'vehicle_id': fault == 'vehicle' ? 'V1' : 'V0',
                'company_code': 'FLX-00028',
                'drivers': [
                  {'driver_id': fault == 'driver' ? 'D1' : 'D0'},
                ],
              },
        scopeIsCurrent: () => current,
        slugLoader: (code) async {
          expect(code, 'FLX-00028');
          return 'taxi-mario';
        },
        contextLoader: (_) async {
          if (fault == 'changed') current = false;
          if (fault == 'web') throw const CompanyBookingLinkUnavailable();
          return bookingContext();
        },
      );
      if (fault == 'none') {
        expect((await future).url, 'https://booking.fluxidi.com/taxi-mario');
      } else {
        await expectLater(future, throwsA(anything));
      }
    });
  }
  for (final location in [
    'https://booking.fluxidi.com/taxi-mario',
    'https://evil.test/taxi-mario',
    'http://booking.fluxidi.com/taxi-mario',
    '/taxi-mario?token=secret',
    '/taxi-mario#secret',
  ]) {
    test('registered redirect: $location', () async {
      final client = MockClient((request) async {
        expect(request.method, 'HEAD');
        expect(request.followRedirects, isFalse);
        expect(request.headers.containsKey('authorization'), isFalse);
        return http.Response('', 308, headers: {'location': location});
      });
      final result = fetchRegisteredBookingSlug('FLX-00028', client: client);
      if (location == 'https://booking.fluxidi.com/taxi-mario') {
        expect(await result, 'taxi-mario');
      } else {
        await expectLater(
          result,
          throwsA(isA<CompanyBookingLinkUnavailable>()),
        );
      }
      client.close();
    });
  }
  test('missing public alias is closed', () async {
    final client = MockClient((_) async => http.Response('', 404));
    await expectLater(
      fetchRegisteredBookingSlug('FLX-00028', client: client),
      throwsA(isA<CompanyBookingLinkUnavailable>()),
    );
    client.close();
  });
}
