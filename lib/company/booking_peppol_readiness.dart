/// B12-G2: Peppol readiness preview parsing and send gating for company
/// documents UI.
library;

enum BookingPeppolReadinessPhase {
  loading,
  ready,
  notReady,
  unknown,
}

enum BookingPeppolSendGate {
  allow,
  blockNotReady,
  blockLoading,
  allowWithBackendGuard,
}

class BookingPeppolReadinessState {
  const BookingPeppolReadinessState({
    required this.phase,
    this.ready = false,
    this.reasons = const <String>[],
  });

  final BookingPeppolReadinessPhase phase;
  final bool ready;
  final List<String> reasons;

  static const BookingPeppolReadinessState loading = BookingPeppolReadinessState(
    phase: BookingPeppolReadinessPhase.loading,
  );

  static const BookingPeppolReadinessState unknown = BookingPeppolReadinessState(
    phase: BookingPeppolReadinessPhase.unknown,
  );

  factory BookingPeppolReadinessState.readyState() {
    return const BookingPeppolReadinessState(
      phase: BookingPeppolReadinessPhase.ready,
      ready: true,
    );
  }

  factory BookingPeppolReadinessState.notReady(List<String> reasons) {
    return BookingPeppolReadinessState(
      phase: BookingPeppolReadinessPhase.notReady,
      ready: false,
      reasons: List<String>.unmodifiable(reasons),
    );
  }
}

bool billitExportIsSentViaPeppol({
  required bool peppolSent,
  required bool sent,
  required String transportType,
}) {
  return peppolSent ||
      (transportType.trim().toLowerCase() == 'peppol' && sent);
}

bool shouldFetchBookingPeppolReadiness({
  required String documentType,
  required String documentId,
  required String billitEnvironment,
  required String billitOrderId,
  required bool billitSent,
  required bool billitPeppolSent,
  required String billitTransportType,
}) {
  if (documentType.trim().toLowerCase() != 'invoice') return false;
  if (documentId.trim().isEmpty) return false;
  if (billitEnvironment.trim().toLowerCase() != 'sandbox') return false;
  if (billitOrderId.trim().isEmpty) return false;
  if (billitExportIsSentViaPeppol(
    peppolSent: billitPeppolSent,
    sent: billitSent,
    transportType: billitTransportType,
  )) {
    return false;
  }
  return true;
}

bool shouldShowBookingPeppolReadinessChip({
  required bool fetchEligible,
  required bool sentViaPeppol,
}) {
  return fetchEligible && !sentViaPeppol;
}

List<String> extractPeppolReadinessReasons(Map<String, dynamic> decoded) {
  final peppol = decoded['peppol'];
  if (peppol is! Map) return const <String>[];
  final raw = peppol['reasons'];
  if (raw is! List) return const <String>[];
  final out = <String>[];
  for (final entry in raw) {
    final text = entry?.toString().trim() ?? '';
    if (text.isNotEmpty) out.add(text);
  }
  return out;
}

BookingPeppolReadinessState parseBookingPeppolReadinessResponse(
  Map<String, dynamic> decoded,
) {
  if (decoded['ok'] != true) return BookingPeppolReadinessState.unknown;
  final peppol = decoded['peppol'];
  if (peppol is! Map) return BookingPeppolReadinessState.unknown;
  final ready = peppol['ready'] == true;
  final reasons = extractPeppolReadinessReasons(decoded);
  if (ready) return BookingPeppolReadinessState.readyState();
  return BookingPeppolReadinessState.notReady(reasons);
}

BookingPeppolSendGate evaluateBookingPeppolSendGate(
  BookingPeppolReadinessState? state,
) {
  if (state == null || state.phase == BookingPeppolReadinessPhase.unknown) {
    return BookingPeppolSendGate.allowWithBackendGuard;
  }
  switch (state.phase) {
    case BookingPeppolReadinessPhase.loading:
      return BookingPeppolSendGate.blockLoading;
    case BookingPeppolReadinessPhase.notReady:
      return BookingPeppolSendGate.blockNotReady;
    case BookingPeppolReadinessPhase.ready:
      return BookingPeppolSendGate.allow;
    case BookingPeppolReadinessPhase.unknown:
      return BookingPeppolSendGate.allowWithBackendGuard;
  }
}
