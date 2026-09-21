import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_customer/api/public_company_presentation.dart';
import 'package:fluxidi_customer/api/public_partner_api.dart';
import 'package:fluxidi_customer/api/public_partner_visibility.dart';
import 'package:http/http.dart' as http;

const String _base = 'https://example.invalid';

PublicApiHttpGet _respond(
  String body, {
  int status = 200,
  List<Uri>? seen,
}) {
  return (Uri url, {Map<String, String>? headers}) async {
    seen?.add(url);
    return http.Response(body, status, headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
    });
  };
}

String _nearbyBody(List<Map<String, dynamic>> partners) => jsonEncode(
  <String, dynamic>{
    'ok': true,
    'postcode': '9600',
    'count': partners.length,
    'partners': partners,
  },
);

void main() {
  group('searchByPostcode request', () {
    test('sends exactly the postcode parameter the existing flow sends', () async {
      final seen = <Uri>[];
      final api = PublicPartnerApi(
        baseUrl: '$_base/',
        httpGet: _respond(_nearbyBody(const <Map<String, dynamic>>[]), seen: seen),
      );

      await api.searchByPostcode(' 9600 ');

      expect(seen, hasLength(1));
      expect(seen.single.path, '/partners/nearby');
      expect(seen.single.queryParameters, <String, String>{'postcode': '9600'});
      // Trailing slash on the configured base must not double up.
      expect(seen.single.toString(), '$_base/partners/nearby?postcode=9600');
    });

    test('normalizes case and inner whitespace like the existing flow', () {
      expect(normalizePublicSearchPostcode(' 1000 bru '), '1000BRU');
      expect(normalizePublicSearchPostcode(''), '');
    });

    test('refuses an empty postcode without calling the transport', () async {
      var called = false;
      final api = PublicPartnerApi(
        baseUrl: _base,
        httpGet: (Uri url, {Map<String, String>? headers}) async {
          called = true;
          return http.Response('{}', 200);
        },
      );

      await expectLater(
        api.searchByPostcode('   '),
        throwsA(
          isA<PublicApiException>().having(
            (e) => e.failure,
            'failure',
            PublicApiFailure.missingInput,
          ),
        ),
      );
      expect(called, isFalse);
    });
  });

  group('searchByPostcode results', () {
    test('maps the fields the customer list needs and keeps server order', () async {
      final api = PublicPartnerApi(
        baseUrl: _base,
        httpGet: _respond(
          _nearbyBody(<Map<String, dynamic>>[
            <String, dynamic>{
              'partner_id': 'company:t1:c1',
              'company_name': 'Taxi Schorisse',
              'city': 'Maarkedal',
              'postcode': '9680',
              'country_code': 'be',
              'logo_url': 'https://cdn.example.invalid/logo.png',
              'hero_photo_url': 'https://cdn.example.invalid/hero.jpg',
              'service_badges': <String>['Luchthaven'],
              'bookable': true,
              'distance_km': 4.25,
            },
            <String, dynamic>{
              'partner_id': 'company:t2:c2',
              'company_name': 'Taxi Ronse',
              'availability_status': 'inactive',
            },
          ]),
        ),
      );

      final result = await api.searchByPostcode('9600');

      expect(result.count, 2);
      expect(result.postcode, '9600');
      expect(
        result.partners.map((p) => p.partnerId),
        <String>['company:t1:c1', 'company:t2:c2'],
      );

      final first = result.partners.first;
      expect(first.companyName, 'Taxi Schorisse');
      expect(first.locationLabel, 'Maarkedal · 9680 · BE');
      expect(first.logoUrl, 'https://cdn.example.invalid/logo.png');
      expect(first.heroPhotoUrl, 'https://cdn.example.invalid/hero.jpg');
      expect(first.serviceBadges, <String>['Luchthaven']);
      expect(first.bookable, isTrue);
      expect(first.distanceKm, 4.25);

      final second = result.partners.last;
      expect(second.bookable, isFalse, reason: 'inactive must stay unbookable');
      expect(second.locationLabel, isEmpty);
      expect(second.distanceKm, isNull, reason: 'distance is never invented');
      expect(second.logoUrl, isEmpty);
    });

    test('a partner without an id is dropped instead of shown', () async {
      final api = PublicPartnerApi(
        baseUrl: _base,
        httpGet: _respond(
          _nearbyBody(<Map<String, dynamic>>[
            <String, dynamic>{'company_name': 'Naamloos'},
          ]),
        ),
      );

      final result = await api.searchByPostcode('9600');

      expect(result.partners, isEmpty);
    });

    test('bookability is not assumed when the server is silent', () async {
      final api = PublicPartnerApi(
        baseUrl: _base,
        httpGet: _respond(
          _nearbyBody(<Map<String, dynamic>>[
            <String, dynamic>{'partner_id': 'p1', 'company_name': 'Taxi Stil'},
          ]),
        ),
      );

      final result = await api.searchByPostcode('9600');

      expect(result.partners.single.bookable, isFalse);
    });

    test('an explicitly published name is kept, even when it is Fluxidi', () async {
      // A company really called Fluxidi may not be hidden or replaced just
      // because of its name. Only a *fallback* refuses the platform brand.
      final api = PublicPartnerApi(
        baseUrl: _base,
        httpGet: _respond(
          _nearbyBody(<Map<String, dynamic>>[
            <String, dynamic>{
              'partner_id': 'p1',
              'company_name': 'Fluxidi',
              'company_code': 'FLX-0001',
            },
          ]),
        ),
      );

      final partner = (await api.searchByPostcode('9600')).partners.single;

      expect(partner.companyName, 'Fluxidi');
      expect(partner.displayName, 'Fluxidi');
    });

    test('the platform brand is refused as a fallback name', () async {
      final api = PublicPartnerApi(
        baseUrl: _base,
        httpGet: _respond(
          _nearbyBody(<Map<String, dynamic>>[
            <String, dynamic>{'partner_id': 'p1', 'company_code': 'Fluxidi'},
          ]),
        ),
      );

      final partner = (await api.searchByPostcode('9600')).partners.single;

      expect(partner.companyName, isEmpty);
      expect(partner.displayName, 'p1');
    });

    test('an internal identifier is never shown as a name', () async {
      final api = PublicPartnerApi(
        baseUrl: _base,
        httpGet: _respond(
          _nearbyBody(<Map<String, dynamic>>[
            <String, dynamic>{
              'partner_id': 'company:t1:c1',
              'company_name': 'cmp_1a2b3c',
            },
          ]),
        ),
      );

      final partner = (await api.searchByPostcode('9600')).partners.single;

      expect(partner.companyName, isEmpty);
    });

    test('an explicit bookable=false survives an is_active=true fallback', () {
      expect(
        isPublicPartnerBookable(<String, dynamic>{
          'bookable': false,
          'is_active': true,
          'availability_status': 'active',
        }),
        isFalse,
      );
      expect(
        isPublicPartnerBookable(<String, dynamic>{
          'bookable': 'False',
          'is_active': true,
        }),
        isFalse,
      );
      expect(
        isPublicPartnerBookable(<String, dynamic>{
          'bookable': 0,
          'is_active': true,
        }),
        isFalse,
      );
    });

    test('an unknown availability status never becomes bookable', () {
      expect(
        isPublicPartnerBookable(<String, dynamic>{
          'availability_status': 'suspended',
          'is_active': true,
        }),
        isFalse,
      );
      expect(
        isPublicPartnerBookable(<String, dynamic>{
          'availability_status': 'active',
        }),
        isTrue,
      );
      expect(
        isPublicPartnerBookable(<String, dynamic>{'is_active': true}),
        isTrue,
      );
      expect(isPublicPartnerBookable(const <String, dynamic>{}), isFalse);
    });

    test('an http-only image url is not rendered', () async {
      final api = PublicPartnerApi(
        baseUrl: _base,
        httpGet: _respond(
          _nearbyBody(<Map<String, dynamic>>[
            <String, dynamic>{
              'partner_id': 'p1',
              'company_name': 'Taxi Http',
              'logo_url': 'http://cdn.example.invalid/logo.png',
            },
          ]),
        ),
      );

      final result = await api.searchByPostcode('9600');

      expect(result.partners.single.logoUrl, isEmpty);
    });

    test('the example company keeps its badge and notice', () async {
      final api = PublicPartnerApi(
        baseUrl: _base,
        httpGet: _respond(
          _nearbyBody(<Map<String, dynamic>>[
            <String, dynamic>{
              'partner_id': 'p1',
              'company_name': 'Voorbeeld Taxi',
              'example_company': true,
              'public_presentation': <String, dynamic>{
                'role': 'example',
                'badge': <String, dynamic>{
                  'nl': 'Voorbeeldbedrijf',
                  'en': 'Example company',
                },
                'notice': <String, dynamic>{'nl': 'Dit is een voorbeeld.'},
              },
            },
          ]),
        ),
      );

      final partner = (await api.searchByPostcode('9600')).partners.single;

      expect(partner.presentation.isExample, isTrue);
      expect(partner.presentation.badge, 'Voorbeeldbedrijf');
      expect(partner.presentation.notice, 'Dit is een voorbeeld.');
    });

    test('example_company alone still yields the default badge', () async {
      final api = PublicPartnerApi(
        baseUrl: _base,
        httpGet: _respond(
          _nearbyBody(<Map<String, dynamic>>[
            <String, dynamic>{
              'partner_id': 'p1',
              'company_name': 'Voorbeeld Taxi',
              'example_company': true,
            },
          ]),
        ),
      );

      final partner = (await api.searchByPostcode('9600')).partners.single;

      expect(partner.presentation.badge, kExampleBadgeNl);
      expect(partner.presentation.notice, kExampleNoticeNl);
    });

    test('an ordinary company carries no presentation marking', () async {
      final api = PublicPartnerApi(
        baseUrl: _base,
        httpGet: _respond(
          _nearbyBody(<Map<String, dynamic>>[
            <String, dynamic>{
              'partner_id': 'p1',
              'company_name': 'Taxi Gewoon',
              'bookable': true,
            },
          ]),
        ),
      );

      final partner = (await api.searchByPostcode('9600')).partners.single;

      expect(partner.presentation.isPlain, isTrue);
    });

    test('an empty partner list is a normal empty result', () async {
      final api = PublicPartnerApi(
        baseUrl: _base,
        httpGet: _respond(_nearbyBody(const <Map<String, dynamic>>[])),
      );

      final result = await api.searchByPostcode('9600');

      expect(result.isEmpty, isTrue);
      expect(result.count, 0);
    });
  });

  group('failures', () {
    test('an unconfigured base URL fails before any request', () async {
      var called = false;
      final api = PublicPartnerApi(
        baseUrl: '   ',
        httpGet: (Uri url, {Map<String, String>? headers}) async {
          called = true;
          return http.Response('{}', 200);
        },
      );

      expect(api.isConfigured, isFalse);
      await expectLater(
        api.searchByPostcode('9600'),
        throwsA(
          isA<PublicApiException>().having(
            (e) => e.failure,
            'failure',
            PublicApiFailure.notConfigured,
          ),
        ),
      );
      expect(called, isFalse);
    });

    test('a transport error becomes a network failure', () async {
      final api = PublicPartnerApi(
        baseUrl: _base,
        httpGet: (Uri url, {Map<String, String>? headers}) async =>
            throw http.ClientException('boom'),
      );

      await expectLater(
        api.searchByPostcode('9600'),
        throwsA(
          isA<PublicApiException>().having(
            (e) => e.failure,
            'failure',
            PublicApiFailure.network,
          ),
        ),
      );
    });

    test('a non-2xx status is reported with its code', () async {
      final api = PublicPartnerApi(
        baseUrl: _base,
        httpGet: _respond('{"ok":false,"error":"postcode or lat/lng is required"}', status: 400),
      );

      await expectLater(
        api.searchByPostcode('9600'),
        throwsA(
          isA<PublicApiException>()
              .having((e) => e.failure, 'failure', PublicApiFailure.badStatus)
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('non-JSON and non-map bodies are invalid responses', () async {
      final broken = PublicPartnerApi(
        baseUrl: _base,
        httpGet: _respond('<html>nope</html>'),
      );
      final listBody = PublicPartnerApi(
        baseUrl: _base,
        httpGet: _respond('[1,2,3]'),
      );

      for (final api in <PublicPartnerApi>[broken, listBody]) {
        await expectLater(
          api.searchByPostcode('9600'),
          throwsA(
            isA<PublicApiException>().having(
              (e) => e.failure,
              'failure',
              PublicApiFailure.invalidResponse,
            ),
          ),
        );
      }
    });

    test('ok:false with status 200 is an invalid response', () async {
      final api = PublicPartnerApi(
        baseUrl: _base,
        httpGet: _respond('{"ok":false}'),
      );

      await expectLater(
        api.searchByPostcode('9600'),
        throwsA(
          isA<PublicApiException>().having(
            (e) => e.failure,
            'failure',
            PublicApiFailure.invalidResponse,
          ),
        ),
      );
    });
  });

  group('loadProfile', () {
    test('sends partner_id and maps the shown profile fields', () async {
      final seen = <Uri>[];
      final api = PublicPartnerApi(
        baseUrl: _base,
        httpGet: _respond(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'profile': <String, dynamic>{
              'company_name': 'Taxi Schorisse',
              'tagline': 'Altijd op tijd',
              'about_long': 'Wij rijden in de Vlaamse Ardennen.',
              'coverage': <String, dynamic>{
                'region_label': 'Vlaamse Ardennen',
                'postcodes': <String>['9600', '9680'],
              },
              'public_contact': <String, dynamic>{
                'website': 'https://taxischorisse.example',
                'public_phone': '+32 55 00 00 00',
                'booking_email': 'boeking@taxischorisse.example',
              },
              'media': <String, dynamic>{
                'logo_url': 'https://cdn.example.invalid/logo.png',
                'hero_photo_url': 'https://cdn.example.invalid/hero.jpg',
              },
              'services': <String>['taxi', 'airport', 'limousine'],
              'payment_methods': <String>['bancontact', 'cash'],
              'trust': <String, dynamic>{'verified_partner': true},
              'bookable': true,
            },
          }),
          seen: seen,
        ),
      );

      final profile = await api.loadProfile(' company:t1:c1 ');

      expect(seen.single.path, '/partners/profile');
      expect(seen.single.queryParameters, <String, String>{
        'partner_id': 'company:t1:c1',
      });
      expect(profile.partnerId, 'company:t1:c1');
      expect(profile.companyName, 'Taxi Schorisse');
      expect(profile.tagline, 'Altijd op tijd');
      expect(profile.about, 'Wij rijden in de Vlaamse Ardennen.');
      expect(profile.regionLabel, 'Vlaamse Ardennen');
      expect(profile.postcodes, <String>['9600', '9680']);
      expect(profile.website, 'https://taxischorisse.example');
      expect(profile.publicPhone, '+32 55 00 00 00');
      expect(profile.bookingEmail, 'boeking@taxischorisse.example');
      expect(profile.heroPhotoUrl, 'https://cdn.example.invalid/hero.jpg');
      expect(profile.verifiedPartner, isTrue);
      expect(profile.bookable, isTrue);
      expect(
        profile.services,
        <String>['taxi', 'airport'],
        reason: 'limousine has no surface in this app yet',
      );
      expect(profile.paymentMethods, <String>['bancontact', 'cash']);
    });

    test('missing optional fields collapse to empty, not to guesses', () async {
      final api = PublicPartnerApi(
        baseUrl: _base,
        httpGet: _respond(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'profile': <String, dynamic>{'company_name': 'Taxi Kaal'},
          }),
        ),
      );

      final profile = await api.loadProfile('p1');

      expect(profile.companyName, 'Taxi Kaal');
      expect(profile.tagline, isEmpty);
      expect(profile.about, isEmpty);
      expect(profile.regionLabel, isEmpty);
      expect(profile.postcodes, isEmpty);
      expect(profile.website, isEmpty);
      expect(profile.heroPhotoUrl, isEmpty);
      expect(profile.logoUrl, isEmpty);
      expect(profile.services, isEmpty);
      expect(profile.paymentMethods, isEmpty);
      expect(profile.verifiedPartner, isFalse);
      expect(profile.bookable, isFalse);
      expect(profile.hasContactDetails, isFalse);
    });

    test('services sent as a boolean map are read as enabled tokens', () async {
      final api = PublicPartnerApi(
        baseUrl: _base,
        httpGet: _respond(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'profile': <String, dynamic>{
              'company_name': 'Taxi Map',
              'services': <String, dynamic>{
                'taxi': true,
                'airport': false,
                'limousine': true,
              },
            },
          }),
        ),
      );

      final profile = await api.loadProfile('p1');

      expect(profile.services, <String>['taxi']);
    });

    test('an empty profile object is an invalid response', () async {
      final api = PublicPartnerApi(
        baseUrl: _base,
        httpGet: _respond('{"ok":true,"profile":{}}'),
      );

      await expectLater(
        api.loadProfile('p1'),
        throwsA(
          isA<PublicApiException>().having(
            (e) => e.failure,
            'failure',
            PublicApiFailure.invalidResponse,
          ),
        ),
      );
    });
  });
}
