import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main_parts/receipt_route_address.dart';

void main() {
  group('receiptLooksLikeCoordinatePair', () {
    test('detects lat,lon pairs', () {
      expect(receiptLooksLikeCoordinatePair('50.772006, 3.669447'), isTrue);
      expect(receiptLooksLikeCoordinatePair('3.669447,50.772006'), isTrue);
    });

    test('rejects street addresses', () {
      expect(
        receiptLooksLikeCoordinatePair('Koekamerstraat 48A, 9688 Schorisse'),
        isFalse,
      );
    });
  });

  group('resolveReceiptRouteAddresses', () {
    test('1. stored readable pickup/drop-off wins over coordinates', () {
      final resolved = resolveReceiptRouteAddresses(
        rawSource: {
          'from': '50.772006, 3.669447',
          'to': '50.80, 3.70',
          'invoice_from_address': 'Koekamerstraat 48A, 9688 Schorisse',
          'invoice_to_address': 'Stationsstraat 1, 9700 Oudenaarde',
        },
        origin: '50.772006, 3.669447',
        destination: '50.80, 3.70',
      );
      expect(resolved.from, 'Koekamerstraat 48A, 9688 Schorisse');
      expect(resolved.to, 'Stationsstraat 1, 9700 Oudenaarde');
    });

    test('2. frozen route labels win when direct address fields absent', () {
      final resolved = resolveReceiptRouteAddresses(
        rawSource: {
          'from': 'Straatrit',
          'route_address_snapshot': {
            'from_address': 'Markt 2, 9000 Gent',
            'to_address': 'Korenmarkt 1, 9000 Gent',
          },
        },
        origin: 'Straatrit',
        destination: '50.80, 3.70',
      );
      expect(resolved.from, 'Markt 2, 9000 Gent');
      expect(resolved.to, 'Korenmarkt 1, 9000 Gent');
    });

    test('3. reverse-geocoded frozen street label used when only coords in from', () {
      final resolved = resolveReceiptRouteAddresses(
        bookingDetails: {
          'from': '50.772006, 3.669447',
          'invoice_from_address': 'Nederzwalmstraat 12, 9636 Zwalm',
          'invoice_from_address_source': 'mapbox_reverse_geocode',
          'to_label': 'Oudenaarde station',
        },
        origin: '50.772006, 3.669447',
        destination: 'Straatrit',
      );
      expect(resolved.from, 'Nederzwalmstraat 12, 9636 Zwalm');
      expect(resolved.to, 'Oudenaarde station');
    });

    test('4. raw coordinates never win; missing yields null for sanitize fallback', () {
      final resolved = resolveReceiptRouteAddresses(
        rawSource: {
          'from': '50.772006, 3.669447',
          'to': '3.669447, 50.772006',
        },
        origin: '50.772006, 3.669447',
        destination: '3.669447, 50.772006',
      );
      expect(resolved.from, isNull);
      expect(resolved.to, isNull);
      expect(resolved.source, 'missing');
    });

    test('Straatrit placeholder never wins over booking label', () {
      final resolved = resolveReceiptRouteAddresses(
        rawSource: {
          'from': 'Straatrit',
          'booking': {
            'from_label': 'Brusselsesteenweg 10, 9090 Melle',
            'to': 'Gent-Sint-Pieters',
          },
        },
        origin: 'Straatrit',
        destination: '-',
      );
      expect(resolved.from, 'Brusselsesteenweg 10, 9090 Melle');
      expect(resolved.to, 'Gent-Sint-Pieters');
    });
  });

  group('receipt logo box', () {
    test('5. logo box is approximately 4× previous 82px width', () {
      expect(kReceiptPdfLogoBoxWidth, 328);
      expect(kReceiptPdfLogoBoxWidth / 82.0, closeTo(4.0, 0.01));
      expect(kReceiptPdfLogoBoxHeight, greaterThan(82 * 0.9));
      expect(kReceiptPdfLogoBoxHeight, lessThanOrEqualTo(120));
    });
  });

  group('mergeReceiptRouteAddressFields', () {
    test('copies frozen fields without coordinate overwrite', () {
      final target = <String, dynamic>{
        'from': '50.1, 3.2',
      };
      mergeReceiptRouteAddressFields(
        target: target,
        authoritative: {
          'invoice_from_address': 'Teststraat 1, 9000 Gent',
          'from': '50.1, 3.2',
          'route_address_snapshot': {
            'from_address': 'Teststraat 1, 9000 Gent',
          },
          'booking': {
            'invoice_to_address': 'Dest 2',
          },
        },
      );
      expect(target['invoice_from_address'], 'Teststraat 1, 9000 Gent');
      // Coordinate `from` in authoritative is skipped; prior target value stays.
      expect(target['from'], '50.1, 3.2');
      expect(target['route_address_snapshot'], isA<Map>());
      expect(
        (target['booking'] as Map)['invoice_to_address'],
        'Dest 2',
      );
    });
  });
}
