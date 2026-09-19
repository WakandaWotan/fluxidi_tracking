import 'package:flutter/widgets.dart';

enum FluxidiPaymentStatus { pending, paid, confirmed, failed }

class FluxidiPendingPayment {
  const FluxidiPendingPayment({
    required this.paymentBookingId,
    this.publicBookingId,
    this.status = FluxidiPaymentStatus.pending,
    this.lastCheckedAt,
    this.isChecking = false,
  });

  final String paymentBookingId;
  final String? publicBookingId;
  final FluxidiPaymentStatus status;
  final DateTime? lastCheckedAt;
  final bool isChecking;

  FluxidiPendingPayment copyWith({
    FluxidiPaymentStatus? status,
    DateTime? lastCheckedAt,
    String? publicBookingId,
    bool? isChecking,
  }) {
    return FluxidiPendingPayment(
      paymentBookingId: paymentBookingId,
      publicBookingId: publicBookingId ?? this.publicBookingId,
      status: status ?? this.status,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      isChecking: isChecking ?? this.isChecking,
    );
  }
}

final ValueNotifier<FluxidiPendingPayment?> fluxidiPendingPaymentNotifier =
    ValueNotifier<FluxidiPendingPayment?>(null);

void setFluxidiPendingPayment({
  required String paymentBookingId,
  String? publicBookingId,
}) {
  if (paymentBookingId.trim().isEmpty) return;
  fluxidiPendingPaymentNotifier.value = FluxidiPendingPayment(
    paymentBookingId: paymentBookingId.trim(),
    publicBookingId: (publicBookingId ?? '').trim().isEmpty
        ? null
        : publicBookingId!.trim(),
  );
}

void markFluxidiPendingPaymentChecking({required String paymentBookingId}) {
  final normalizedId = paymentBookingId.trim();
  if (normalizedId.isEmpty) return;
  final pending = fluxidiPendingPaymentNotifier.value;
  if (pending == null || pending.paymentBookingId != normalizedId) return;
  fluxidiPendingPaymentNotifier.value = pending.copyWith(
    isChecking: true,
    lastCheckedAt: DateTime.now(),
  );
}

void clearFluxidiPendingPayment() {
  fluxidiPendingPaymentNotifier.value = null;
}
