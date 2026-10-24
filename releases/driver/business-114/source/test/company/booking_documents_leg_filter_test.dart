import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/booking_documents_leg_filter.dart';

void main() {
  group('bookingDocumentMatchesLegFilter', () {
    test('no filter shows all documents', () {
      const doc = BookingDocumentLegFields(
        sourceLegId: '2026-07-726907:OUTBOUND',
        sourceLegType: 'outbound',
      );
      expect(
        bookingDocumentMatchesLegFilter(doc),
        isTrue,
      );
    });

    test('doc without leg metadata is hidden on filtered leg cards', () {
      const doc = BookingDocumentLegFields();
      expect(
        bookingDocumentMatchesLegFilter(
          doc,
          sourceLegId: '2026-07-726907:OUTBOUND',
          sourceLegType: 'outbound',
        ),
        isFalse,
      );
    });

    test('outbound filter matches only outbound invoice', () {
      const outbound = BookingDocumentLegFields(
        sourceLegId: '2026-07-726907:OUTBOUND',
        sourceLegType: 'outbound',
      );
      const returnLeg = BookingDocumentLegFields(
        sourceLegId: '2026-07-726907:RETURN',
        sourceLegType: 'return',
      );
      const filterLegId = '2026-07-726907:OUTBOUND';
      const filterLegType = 'outbound';

      expect(
        bookingDocumentMatchesLegFilter(
          outbound,
          sourceLegId: filterLegId,
          sourceLegType: filterLegType,
        ),
        isTrue,
      );
      expect(
        bookingDocumentMatchesLegFilter(
          returnLeg,
          sourceLegId: filterLegId,
          sourceLegType: filterLegType,
        ),
        isFalse,
      );
    });

    test('return filter matches only return invoice', () {
      const outbound = BookingDocumentLegFields(
        sourceLegId: '2026-07-726907:OUTBOUND',
        sourceLegType: 'outbound',
      );
      const returnLeg = BookingDocumentLegFields(
        sourceLegId: '2026-07-726907:RETURN',
        sourceLegType: 'return',
      );
      const filterLegId = '2026-07-726907:RETURN';
      const filterLegType = 'return';

      expect(
        bookingDocumentMatchesLegFilter(
          returnLeg,
          sourceLegId: filterLegId,
          sourceLegType: filterLegType,
        ),
        isTrue,
      );
      expect(
        bookingDocumentMatchesLegFilter(
          outbound,
          sourceLegId: filterLegId,
          sourceLegType: filterLegType,
        ),
        isFalse,
      );
    });

    test('leg type match is case-insensitive', () {
      const doc = BookingDocumentLegFields(
        sourceLegId: 'leg-1',
        sourceLegType: 'OUTBOUND',
      );
      expect(
        bookingDocumentMatchesLegFilter(
          doc,
          sourceLegType: 'outbound',
        ),
        isTrue,
      );
    });

    test('nested source.leg_* fallback is parsed from API shape', () {
      final fields = readBookingDocumentLegFieldsFromJson({
        'document_number': 'INV-2026-000020',
        'source': {
          'leg_id': '2026-07-726907:OUTBOUND',
          'leg_type': 'outbound',
        },
      });
      expect(fields.sourceLegId, '2026-07-726907:OUTBOUND');
      expect(fields.sourceLegType, 'outbound');
    });
  });

  group('filterBookingDocumentNumbersByLeg — live booking fixture', () {
    final liveDocuments = <Map<String, dynamic>>[
      {
        'document_number': 'INV-2026-000020',
        'source_leg_id': '2026-07-726907:OUTBOUND',
        'source_leg_type': 'outbound',
      },
      {
        'document_number': 'INV-2026-000021',
        'source_leg_id': '2026-07-726907:RETURN',
        'source_leg_type': 'return',
      },
    ];

    test('parent/unfiltered context shows both invoices', () {
      expect(
        filterBookingDocumentNumbersByLeg(liveDocuments),
        ['INV-2026-000020', 'INV-2026-000021'],
      );
    });

    test('outbound leg card shows badge count 1 and only INV-2026-000020', () {
      expect(
        filterBookingDocumentNumbersByLeg(
          liveDocuments,
          sourceLegId: '2026-07-726907:OUTBOUND',
          sourceLegType: 'outbound',
        ),
        ['INV-2026-000020'],
      );
    });

    test('return leg card shows badge count 1 and only INV-2026-000021', () {
      expect(
        filterBookingDocumentNumbersByLeg(
          liveDocuments,
          sourceLegId: '2026-07-726907:RETURN',
          sourceLegType: 'return',
        ),
        ['INV-2026-000021'],
      );
    });
  });

  group('isRoundtripOperationalLegRowForDocumentsFilter', () {
    test('operational roundtrip leg rows get a filter', () {
      expect(
        isRoundtripOperationalLegRowForDocumentsFilter(
          isOperationalLeg: true,
          isRoundtripParent: true,
          legId: '2026-07-726907:OUTBOUND',
        ),
        isTrue,
      );
    });

    test('parent-only row stays unfiltered', () {
      expect(
        isRoundtripOperationalLegRowForDocumentsFilter(
          isOperationalLeg: false,
          isRoundtripParent: true,
          legId: '',
        ),
        isFalse,
      );
    });

    test('single-trip row stays unfiltered', () {
      expect(
        isRoundtripOperationalLegRowForDocumentsFilter(
          isOperationalLeg: false,
          isRoundtripParent: false,
          legId: '',
        ),
        isFalse,
      );
    });
  });
}
