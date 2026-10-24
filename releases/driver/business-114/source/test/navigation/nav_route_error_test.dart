// NAV-DIRECTIONS-FAILURE-SECURITY-AND-RECOVERY-1
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/navigation/nav_route_error.dart';

// A tiny translate helper mirroring the app's DriverNavTranslate signature.
// Supported product UI locales are NL/EN/FR/ES. [AppLanguage.de] exists on the
// enum for legacy/fallback paths and must resolve to English — the same rule as
// [mapboxDirectionsLanguageCode] and LocalizedString.of — without inventing DE
// navigation copy in this fixture.
String Function({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) trFor(AppLanguage lang) {
  return ({required nl, required en, required fr, required es}) {
    switch (lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return en;
    }
  };
}

// The exact field failure string shape produced by IOClient on DNS failure.
const String kFieldDnsException =
    "ClientException with SocketException: Failed host lookup: 'api.mapbox.com' "
    "(OS Error: No address associated with hostname, errno = 7), "
    "uri=https://api.mapbox.com/directions/v5/mapbox/driving/"
    "4.351721,50.846557;4.401234,50.901234"
    "?alternatives=false&geometries=geojson&overview=full&steps=true"
    "&banner_instructions=true&roundabout_exits=true&language=en"
    "&access_token=pk.eyJ1IjoiZmx1eGlkaSIsImEiOiJhYmNkZWZnMTIzNDU2Nzg5In0.ABCDEF";

void main() {
  group('classification', () {
    test('DNS failure is classified from the field exception string', () {
      final kind = classifyNavRouteError(
        http.ClientException(kFieldDnsException),
      );
      expect(kind, NavRouteErrorKind.dnsFailure);
    });

    test('SocketException host lookup -> dns_failure', () {
      final kind = classifyNavRouteError(
        const SocketException(
          "Failed host lookup: 'api.mapbox.com'",
          osError: OSError('No address associated with hostname', 7),
        ),
      );
      expect(kind, NavRouteErrorKind.dnsFailure);
    });

    test('TimeoutException -> timeout', () {
      expect(
        classifyNavRouteError(TimeoutException('x')),
        NavRouteErrorKind.timeout,
      );
    });

    test('connection reset -> connection_reset', () {
      expect(
        classifyNavRouteError(
          const SocketException('Connection reset by peer'),
        ),
        NavRouteErrorKind.connectionReset,
      );
    });

    test('generic socket network unreachable -> offline', () {
      expect(
        classifyNavRouteError(
          const SocketException('Network is unreachable'),
        ),
        NavRouteErrorKind.offline,
      );
    });

    test('http status classification', () {
      expect(classifyNavRouteHttpStatus(200), isNull);
      expect(classifyNavRouteHttpStatus(401), NavRouteErrorKind.http401or403);
      expect(classifyNavRouteHttpStatus(403), NavRouteErrorKind.http401or403);
      expect(classifyNavRouteHttpStatus(429), NavRouteErrorKind.http429);
      expect(classifyNavRouteHttpStatus(500), NavRouteErrorKind.server5xx);
      expect(classifyNavRouteHttpStatus(404), NavRouteErrorKind.invalidResponse);
    });

    test('NavRouteHttpStatusException maps by status', () {
      expect(
        classifyNavRouteError(const NavRouteHttpStatusException(503)),
        NavRouteErrorKind.server5xx,
      );
    });

    test('FormatException (bad JSON) -> invalid_response', () {
      expect(
        classifyNavRouteError(const FormatException('bad json')),
        NavRouteErrorKind.invalidResponse,
      );
    });
  });

  group('redaction (token/coord/URI safety)', () {
    test('redacted field exception exposes no token, URI or coordinates', () {
      final safe = redactNavRouteDiagnostic(kFieldDnsException);
      expect(safe.contains('access_token='), isFalse);
      expect(safe.contains('pk.'), isFalse);
      expect(safe.contains('api.mapbox.com'), isFalse);
      expect(safe.contains('https://'), isFalse);
      // No decimal coordinate pair survives.
      expect(RegExp(r'-?\d{1,3}\.\d{3,},-?\d{1,3}\.\d{3,}').hasMatch(safe),
          isFalse);
      // But it still says something diagnostic.
      expect(safe.toLowerCase().contains('host lookup'), isTrue);
    });

    test('redaction strips a bare pk. token and coordinate pair', () {
      final safe = redactNavRouteDiagnostic(
        'boom pk.abc123DEF coords 4.123456,50.654321 end',
      );
      expect(safe.contains('pk.abc'), isFalse);
      expect(safe.contains('4.123456,50.654321'), isFalse);
    });

    test('empty input redacts to empty', () {
      expect(redactNavRouteDiagnostic(null), '');
      expect(redactNavRouteDiagnostic(''), '');
    });

    test('geocode URL (address + token in query) is fully scrubbed', () {
      const raw =
          "ClientException with SocketException: Failed host lookup, "
          "uri=https://api.mapbox.com/geocoding/v5/mapbox.places/"
          "Kerkstraat%2012%20Brussel.json?access_token=pk.abc123&limit=1";
      final safe = redactNavRouteDiagnostic(raw);
      expect(safe.contains('access_token='), isFalse);
      expect(safe.contains('pk.'), isFalse);
      expect(safe.contains('mapbox.com'), isFalse);
      expect(safe.toLowerCase().contains('kerkstraat'), isFalse);
    });
  });

  group('localized copy', () {
    test('Dutch DNS copy is the concise expected message with actions', () {
      final copy = navRouteErrorMessage(
        NavRouteErrorKind.dnsFailure,
        tr: trFor(AppLanguage.nl),
      );
      expect(
        copy.message,
        'Route kon niet worden geladen. Controleer je internetverbinding.',
      );
      expect(copy.retryLabel, 'Opnieuw proberen');
      expect(copy.dismissLabel, 'Sluiten');
      // Never leaks class names / stack.
      expect(copy.message.toLowerCase().contains('exception'), isFalse);
      expect(copy.message.contains('pk.'), isFalse);
    });

    test('English/French/Spanish copy differs from Dutch', () {
      final nl = navRouteErrorMessage(NavRouteErrorKind.offline,
          tr: trFor(AppLanguage.nl));
      final en = navRouteErrorMessage(NavRouteErrorKind.offline,
          tr: trFor(AppLanguage.en));
      final fr = navRouteErrorMessage(NavRouteErrorKind.offline,
          tr: trFor(AppLanguage.fr));
      final es = navRouteErrorMessage(NavRouteErrorKind.offline,
          tr: trFor(AppLanguage.es));
      expect({nl.message, en.message, fr.message, es.message}.length, 4);
      expect(en.retryLabel, 'Retry');
    });
  });

  group('locale parity (Directions language)', () {
    test('nl->nl, fr->fr, en->en, es->es; de falls back to en', () {
      expect(mapboxDirectionsLanguageCode(AppLanguage.nl), 'nl');
      expect(mapboxDirectionsLanguageCode(AppLanguage.fr), 'fr');
      expect(mapboxDirectionsLanguageCode(AppLanguage.en), 'en');
      expect(mapboxDirectionsLanguageCode(AppLanguage.es), 'es');
      // Enum includes de, but product Directions language falls back to en
      // (no incomplete German navigation localization).
      expect(mapboxDirectionsLanguageCode(AppLanguage.de), 'en');
    });

    test('nav route error DE fixture uses English copy, not fabricated DE', () {
      final de = navRouteErrorMessage(
        NavRouteErrorKind.offline,
        tr: trFor(AppLanguage.de),
      );
      final en = navRouteErrorMessage(
        NavRouteErrorKind.offline,
        tr: trFor(AppLanguage.en),
      );
      expect(de.message, en.message);
      expect(de.retryLabel, en.retryLabel);
    });
  });

  group('retry policy', () {
    test('retryable classes are transient connectivity/server', () {
      expect(navRouteErrorIsRetryable(NavRouteErrorKind.dnsFailure), isTrue);
      expect(navRouteErrorIsRetryable(NavRouteErrorKind.offline), isTrue);
      expect(navRouteErrorIsRetryable(NavRouteErrorKind.timeout), isTrue);
      expect(navRouteErrorIsRetryable(NavRouteErrorKind.server5xx), isTrue);
      expect(navRouteErrorIsRetryable(NavRouteErrorKind.http429), isTrue);
      expect(navRouteErrorIsRetryable(NavRouteErrorKind.http401or403), isFalse);
      expect(navRouteErrorIsRetryable(NavRouteErrorKind.invalidResponse),
          isFalse);
    });

    test('backoff is bounded, monotonic and capped at 30s', () {
      final d0 = navRouteRetryBackoff(0);
      final d1 = navRouteRetryBackoff(1);
      final d2 = navRouteRetryBackoff(2);
      expect(d0, const Duration(seconds: 2));
      expect(d1, const Duration(seconds: 4));
      expect(d2, const Duration(seconds: 8));
      expect(navRouteRetryBackoff(100).inSeconds, lessThanOrEqualTo(30));
      expect(navRouteRetryBackoff(-5).inSeconds, greaterThan(0));
    });
  });

  group('diagnostic codes', () {
    test('codes are stable and PII-free', () {
      expect(navRouteErrorCode(NavRouteErrorKind.dnsFailure), 'dns_failure');
      expect(navRouteErrorCode(NavRouteErrorKind.http401or403),
          'http_401_or_403');
      expect(navRouteErrorCode(NavRouteErrorKind.server5xx), 'server_5xx');
    });
  });
}
