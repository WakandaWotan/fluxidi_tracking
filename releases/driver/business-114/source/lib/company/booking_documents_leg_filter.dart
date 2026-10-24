/// P1-B: client-side leg filter for roundtrip leg cards in company bookings.
///
/// Fetches still return all parent documents; this module filters which rows
/// are shown per leg card. Documents without leg metadata only appear in
/// unfiltered (parent/single-trip) contexts.
library;

/// Minimal leg metadata used for per-leg document filtering.
class BookingDocumentLegFields {
  const BookingDocumentLegFields({
    this.sourceLegId = '',
    this.sourceLegType = '',
  });

  final String sourceLegId;
  final String sourceLegType;
}

String _readAny(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final text = (json[key] ?? '').toString().trim();
    if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
  }
  return '';
}

String _readFromMap(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final text = (map[key] ?? '').toString().trim();
    if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
  }
  return '';
}

/// Tolerant leg-field extraction mirroring [_BookingDocumentMetadata.fromJson].
BookingDocumentLegFields readBookingDocumentLegFieldsFromJson(
  Map<String, dynamic> json,
) {
  var sourceLegId = _readAny(json, const ['source_leg_id', 'sourceLegId']);
  var sourceLegType = _readAny(json, const ['source_leg_type', 'sourceLegType']);
  final rawSource = json['source'];
  if (rawSource is Map) {
    final sourceMap = rawSource.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    if (sourceLegId.isEmpty) {
      sourceLegId = _readFromMap(
        sourceMap,
        const ['leg_id', 'legId', 'source_leg_id'],
      );
    }
    if (sourceLegType.isEmpty) {
      sourceLegType = _readFromMap(
        sourceMap,
        const ['leg_type', 'legType', 'source_leg_type'],
      );
    }
  }
  return BookingDocumentLegFields(
    sourceLegId: sourceLegId,
    sourceLegType: sourceLegType,
  );
}

/// Returns true when [doc] should be visible for the optional leg filter.
bool bookingDocumentMatchesLegFilter(
  BookingDocumentLegFields doc, {
  String? sourceLegId,
  String? sourceLegType,
}) {
  final filterLegId = (sourceLegId ?? '').trim();
  final filterLegType = (sourceLegType ?? '').trim().toLowerCase();
  if (filterLegId.isEmpty && filterLegType.isEmpty) return true;

  final docLegId = doc.sourceLegId.trim();
  final docLegType = doc.sourceLegType.trim().toLowerCase();
  if (docLegId.isEmpty && docLegType.isEmpty) return false;

  var idOk = true;
  var typeOk = true;
  if (filterLegId.isNotEmpty) {
    idOk = docLegId.isNotEmpty && docLegId == filterLegId;
  }
  if (filterLegType.isNotEmpty) {
    typeOk = docLegType.isNotEmpty && docLegType == filterLegType;
  }
  return idOk && typeOk;
}

/// Applies the leg filter to API document maps and returns document numbers.
List<String> filterBookingDocumentNumbersByLeg(
  Iterable<Map<String, dynamic>> documents, {
  String? sourceLegId,
  String? sourceLegType,
}) {
  final out = <String>[];
  for (final doc in documents) {
    final legFields = readBookingDocumentLegFieldsFromJson(doc);
    if (!bookingDocumentMatchesLegFilter(
      legFields,
      sourceLegId: sourceLegId,
      sourceLegType: sourceLegType,
    )) {
      continue;
    }
    final number = _readAny(doc, const [
      'document_number',
      'documentNumber',
      'invoice_number',
      'invoiceNumber',
    ]);
    if (number.isNotEmpty) out.add(number);
  }
  return out;
}

/// Whether a company booking list row should pass a leg filter to the UI.
bool isRoundtripOperationalLegRowForDocumentsFilter({
  required bool isOperationalLeg,
  required bool isRoundtripParent,
  required String legId,
}) {
  return isOperationalLeg && isRoundtripParent && legId.trim().isNotEmpty;
}
