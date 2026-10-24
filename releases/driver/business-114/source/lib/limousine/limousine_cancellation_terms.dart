// Frozen cancellation terms from an accepted limousine quotation.
// Never rereads live company policy.

import 'package:flutter/foundation.dart';

import '../app_strings.dart';
import 'limousine_quote_presentation.dart';

const String kLimousineFrozenCancellationSource = 'frozen_quotation';

const Key kLimousineCancellationPreviewKey = ValueKey<String>(
  'limousine_cancellation_preview',
);
const Key kLimousineCancellationKeepKey = ValueKey<String>(
  'limousine_cancellation_keep',
);
const Key kLimousineCancellationConfirmKey = ValueKey<String>(
  'limousine_cancellation_confirm',
);

class LimousineFrozenCancellationTerms {
  const LimousineFrozenCancellationTerms({
    required this.deadlineHours,
    required this.cancellationPenaltyPercent,
    required this.noShowPenaltyPercent,
    required this.canonicalGrossCents,
    required this.termsRevision,
  });

  final int deadlineHours;
  final int cancellationPenaltyPercent;
  final int noShowPenaltyPercent;
  final int canonicalGrossCents;
  final int termsRevision;
}

class LimousineCancellationPreview {
  const LimousineCancellationPreview({
    required this.terms,
    required this.pickupIso,
    required this.minutesUntilPickup,
    required this.isNoShow,
    required this.beforeFreeDeadline,
    required this.applicablePenaltyPercent,
    required this.penaltyCents,
    required this.paidCents,
    required this.refundCents,
    required this.outstandingCents,
    required this.isPaid,
  });

  final LimousineFrozenCancellationTerms terms;
  final String pickupIso;
  final int? minutesUntilPickup;
  final bool isNoShow;
  final bool beforeFreeDeadline;
  final int applicablePenaltyPercent;
  final int penaltyCents;
  final int paidCents;
  final int refundCents;
  final int outstandingCents;
  final bool isPaid;

  DateTime? get freeUntil {
    final pickup = DateTime.tryParse(pickupIso.trim());
    if (pickup == null) return null;
    return pickup.subtract(Duration(hours: terms.deadlineHours));
  }
}

int? _readInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.truncate();
  return int.tryParse(value.toString().trim());
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const <String, dynamic>{};
}

int? _firstInt(List<dynamic> values) {
  for (final value in values) {
    final n = _readInt(value);
    if (n != null) return n;
  }
  return null;
}

bool _isPaidPaymentStatus(String status) {
  final token = status.trim().toLowerCase();
  return token == 'paid' ||
      token == 'confirmed' ||
      token == 'completed' ||
      token == 'success' ||
      token == 'settled';
}

/// Reads frozen terms from a booking record / customer view source.
LimousineFrozenCancellationTerms? limousineFrozenCancellationTermsFromDetails(
  Map<String, dynamic> details,
) {
  final booking = _asMap(details['booking']);
  final record = _asMap(details['record']);
  final quote = _asMap(
    details['quote'] ?? record['quote'] ?? booking['quote'],
  );
  final accepted = _asMap(
    quote['limousine_accepted_price'] ??
        details['limousine_accepted_price'] ??
        booking['limousine_accepted_price'] ??
        record['limousine_accepted_price'],
  );
  final source = (accepted['cancellation_terms_source'] ??
          details['cancellation_terms_source'] ??
          booking['cancellation_terms_source'] ??
          record['cancellation_terms_source'] ??
          '')
      .toString();
  final hours = _firstInt(<dynamic>[
    accepted['cancellation_deadline_hours'],
    details['cancellation_deadline_hours'],
    booking['cancellation_deadline_hours'],
    record['cancellation_deadline_hours'],
  ]);
  final penalty = _firstInt(<dynamic>[
    accepted['cancellation_penalty_percent'],
    details['cancellation_penalty_percent'],
    booking['cancellation_penalty_percent'],
    record['cancellation_penalty_percent'],
  ]);
  final noShow = _firstInt(<dynamic>[
    accepted['no_show_penalty_percent'],
    details['no_show_penalty_percent'],
    booking['no_show_penalty_percent'],
    record['no_show_penalty_percent'],
  ]);
  if (hours == null && penalty == null && noShow == null) return null;
  final service = (details['service_type'] ??
          details['serviceType'] ??
          booking['service_type'] ??
          record['service_type'] ??
          accepted['service_category'] ??
          '')
      .toString()
      .trim()
      .toLowerCase();
  if (source.isNotEmpty && source != kLimousineFrozenCancellationSource) {
    return null;
  }
  if (service.isNotEmpty && service != 'limousine') return null;
  if (source != kLimousineFrozenCancellationSource && service != 'limousine') {
    return null;
  }
  final money = limousineCanonicalMoneyFromBookingDetails(details);
  final gross = _firstInt(<dynamic>[
        accepted['cancellation_canonical_gross_cents'],
        details['cancellation_canonical_gross_cents'],
        booking['cancellation_canonical_gross_cents'],
        record['cancellation_canonical_gross_cents'],
        accepted['total_incl_vat_cents'],
      ]) ??
      money?.grossCents ??
      0;
  return LimousineFrozenCancellationTerms(
    deadlineHours: hours ?? 0,
    cancellationPenaltyPercent: penalty ?? 0,
    noShowPenaltyPercent: noShow ?? 0,
    canonicalGrossCents: gross < 0 ? 0 : gross,
    termsRevision:
        _firstInt(<dynamic>[
          accepted['terms_revision'],
          details['terms_revision'],
          booking['terms_revision'],
          record['terms_revision'],
        ]) ??
        0,
  );
}

LimousineCancellationPreview? limousineCancellationPreviewFromDetails(
  Map<String, dynamic> details, {
  String? pickupIso,
  String? paymentStatus,
  int? paidAmountCents,
  DateTime? now,
}) {
  final terms = limousineFrozenCancellationTermsFromDetails(details);
  if (terms == null) return null;
  final pickup = (pickupIso ??
          details['pickup_iso'] ??
          details['pickupStartIso'] ??
          _asMap(details['booking'])['pickupStartIso'] ??
          '')
      .toString();
  final pickupAt = DateTime.tryParse(pickup);
  final clock = now ?? DateTime.now();
  final minutesUntil = pickupAt == null
      ? null
      : pickupAt.difference(clock).inMinutes;
  final isNoShow = minutesUntil != null && minutesUntil < 0;
  final cutoffMinutes = terms.deadlineHours * 60;
  final beforeDeadline =
      minutesUntil != null && minutesUntil >= cutoffMinutes;
  final percent = isNoShow
      ? terms.noShowPenaltyPercent
      : (beforeDeadline ? 0 : terms.cancellationPenaltyPercent);
  final penaltyCents = ((terms.canonicalGrossCents * percent) / 100).round();
  final paidStatus = (paymentStatus ??
          details['payment_status'] ??
          details['paymentStatus'] ??
          '')
      .toString();
  final paid = _isPaidPaymentStatus(paidStatus);
  final paidCents = paid
      ? (paidAmountCents ??
            _firstInt(<dynamic>[
              details['paid_amount_cents'],
              details['payment_amount_cents'],
            ]) ??
            terms.canonicalGrossCents)
      : 0;
  final refundCents = paid ? (paidCents - penaltyCents).clamp(0, paidCents) : 0;
  final outstandingCents = paid ? 0 : penaltyCents;
  return LimousineCancellationPreview(
    terms: terms,
    pickupIso: pickup,
    minutesUntilPickup: minutesUntil,
    isNoShow: isNoShow,
    beforeFreeDeadline: beforeDeadline,
    applicablePenaltyPercent: percent,
    penaltyCents: penaltyCents,
    paidCents: paidCents,
    refundCents: refundCents,
    outstandingCents: outstandingCents,
    isPaid: paid,
  );
}

LocalizedText limousineCancellationPreviewBody(
  LimousineCancellationPreview preview,
) {
  final total = formatLimousineEuroAmount(preview.terms.canonicalGrossCents);
  final penalty = formatLimousineEuroAmount(preview.penaltyCents);
  final deadline = preview.terms.deadlineHours;
  final percent = preview.applicablePenaltyPercent;
  final noShow = preview.terms.noShowPenaltyPercent;
  final refund = formatLimousineEuroAmount(preview.refundCents);
  final outstanding = formatLimousineEuroAmount(preview.outstandingCents);
  final paid = formatLimousineEuroAmount(preview.paidCents);
  final deadlineLine = preview.beforeFreeDeadline
      ? 'gratis tot $deadline u voor ophalen'
      : (preview.isNoShow
            ? 'no-show ($noShow%)'
            : 'na de vrije termijn van $deadline u');
  if (preview.isPaid) {
    return LocalizedText(
      nl:
          'Geaccepteerd totaal $total.\n'
          'Vrije annulering: $deadline u voor ophalen.\n'
          'Nu van toepassing: $percent% ($deadlineLine).\n'
          'Annulatiekost $penalty.\n'
          'Betaald $paid. Terugbetaling $refund.\n'
          'No-show: $noShow%.',
      en:
          'Accepted total $total.\n'
          'Free cancellation: $deadline h before pickup.\n'
          'Now applicable: $percent% ($deadlineLine).\n'
          'Cancellation cost $penalty.\n'
          'Paid $paid. Refund $refund.\n'
          'No-show: $noShow%.',
      fr:
          'Total accepté $total.\n'
          'Annulation gratuite : $deadline h avant la prise en charge.\n'
          'Applicable maintenant : $percent% ($deadlineLine).\n'
          'Frais d’annulation $penalty.\n'
          'Payé $paid. Remboursement $refund.\n'
          'No-show : $noShow%.',
      es:
          'Total aceptado $total.\n'
          'Cancelación gratuita: $deadline h antes de la recogida.\n'
          'Aplicable ahora: $percent% ($deadlineLine).\n'
          'Coste de cancelación $penalty.\n'
          'Pagado $paid. Reembolso $refund.\n'
          'No-show: $noShow%.',
    );
  }
  return LocalizedText(
    nl:
        'Geaccepteerd totaal $total.\n'
        'Vrije annulering: $deadline u voor ophalen.\n'
        'Nu van toepassing: $percent% ($deadlineLine).\n'
        'Annulatiekost $penalty.\n'
        'Openstaand $outstanding.\n'
        'No-show: $noShow%.',
    en:
        'Accepted total $total.\n'
        'Free cancellation: $deadline h before pickup.\n'
        'Now applicable: $percent% ($deadlineLine).\n'
        'Cancellation cost $penalty.\n'
        'Outstanding $outstanding.\n'
        'No-show: $noShow%.',
    fr:
        'Total accepté $total.\n'
        'Annulation gratuite : $deadline h avant la prise en charge.\n'
        'Applicable maintenant : $percent% ($deadlineLine).\n'
        'Frais d’annulation $penalty.\n'
        'Reste dû $outstanding.\n'
        'No-show : $noShow%.',
    es:
        'Total aceptado $total.\n'
        'Cancelación gratuita: $deadline h antes de la recogida.\n'
        'Aplicable ahora: $percent% ($deadlineLine).\n'
        'Coste de cancelación $penalty.\n'
        'Pendiente $outstanding.\n'
        'No-show: $noShow%.',
  );
}
