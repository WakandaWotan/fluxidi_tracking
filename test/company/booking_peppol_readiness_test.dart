import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/booking_peppol_readiness.dart';

void main() {
  group('parseBookingPeppolReadinessResponse', () {
    test('ready=true', () {
      final state = parseBookingPeppolReadinessResponse({
        'ok': true,
        'peppol': {'candidate': true, 'ready': true, 'reasons': []},
      });
      expect(state.phase, BookingPeppolReadinessPhase.ready);
      expect(state.ready, isTrue);
      expect(state.reasons, isEmpty);
    });

    test('ready=false with reasons', () {
      final state = parseBookingPeppolReadinessResponse({
        'ok': true,
        'peppol': {
          'candidate': true,
          'ready': false,
          'reasons': ['customer_peppol_target_missing'],
        },
      });
      expect(state.phase, BookingPeppolReadinessPhase.notReady);
      expect(state.ready, isFalse);
      expect(state.reasons, ['customer_peppol_target_missing']);
    });

    test('missing ok=false is unknown', () {
      final state = parseBookingPeppolReadinessResponse({
        'ok': false,
        'error': 'document_not_found',
      });
      expect(state.phase, BookingPeppolReadinessPhase.unknown);
    });

    test('invalid peppol object is unknown', () {
      final state = parseBookingPeppolReadinessResponse({
        'ok': true,
        'peppol': null,
      });
      expect(state.phase, BookingPeppolReadinessPhase.unknown);
    });
  });

  group('shouldFetchBookingPeppolReadiness', () {
    const eligible = {
      'documentType': 'invoice',
      'documentId': 'doc-1',
      'billitEnvironment': 'sandbox',
      'billitOrderId': '2848056',
      'billitSent': false,
      'billitPeppolSent': false,
      'billitTransportType': '',
    };

    test('eligible unsent sandbox invoice fetches', () {
      expect(shouldFetchBookingPeppolReadiness(
        documentType: eligible['documentType']! as String,
        documentId: eligible['documentId']! as String,
        billitEnvironment: eligible['billitEnvironment']! as String,
        billitOrderId: eligible['billitOrderId']! as String,
        billitSent: eligible['billitSent']! as bool,
        billitPeppolSent: eligible['billitPeppolSent']! as bool,
        billitTransportType: eligible['billitTransportType']! as String,
      ), isTrue);
    });

    test('sent document suppresses fetch and chip', () {
      expect(
        shouldFetchBookingPeppolReadiness(
          documentType: 'invoice',
          documentId: 'doc-1',
          billitEnvironment: 'sandbox',
          billitOrderId: '2848056',
          billitSent: true,
          billitPeppolSent: true,
          billitTransportType: 'Peppol',
        ),
        isFalse,
      );
      expect(
        shouldShowBookingPeppolReadinessChip(
          fetchEligible: false,
          sentViaPeppol: true,
        ),
        isFalse,
      );
    });

    test('credit note does not fetch', () {
      expect(
        shouldFetchBookingPeppolReadiness(
          documentType: 'credit_note',
          documentId: 'doc-1',
          billitEnvironment: 'sandbox',
          billitOrderId: '2848056',
          billitSent: false,
          billitPeppolSent: false,
          billitTransportType: '',
        ),
        isFalse,
      );
    });
  });

  group('evaluateBookingPeppolSendGate', () {
    test('ready=false blocks send', () {
      expect(
        evaluateBookingPeppolSendGate(
          BookingPeppolReadinessState.notReady(
            ['customer_peppol_target_missing'],
          ),
        ),
        BookingPeppolSendGate.blockNotReady,
      );
    });

    test('loading blocks send', () {
      expect(
        evaluateBookingPeppolSendGate(BookingPeppolReadinessState.loading),
        BookingPeppolSendGate.blockLoading,
      );
    });

    test('ready=true allows send', () {
      expect(
        evaluateBookingPeppolSendGate(BookingPeppolReadinessState.readyState()),
        BookingPeppolSendGate.allow,
      );
    });

    test('unknown allows backend-guarded send', () {
      expect(
        evaluateBookingPeppolSendGate(BookingPeppolReadinessState.unknown),
        BookingPeppolSendGate.allowWithBackendGuard,
      );
      expect(
        evaluateBookingPeppolSendGate(null),
        BookingPeppolSendGate.allowWithBackendGuard,
      );
    });
  });

  group('billitExportIsSentViaPeppol', () {
    test('peppol_sent true', () {
      expect(
        billitExportIsSentViaPeppol(
          peppolSent: true,
          sent: false,
          transportType: '',
        ),
        isTrue,
      );
    });

    test('transport peppol and sent true', () {
      expect(
        billitExportIsSentViaPeppol(
          peppolSent: false,
          sent: true,
          transportType: 'Peppol',
        ),
        isTrue,
      );
    });
  });
}
