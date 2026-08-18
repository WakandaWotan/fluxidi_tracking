/// Extra-vehicle add-on purchase preview and fail-closed lifecycle.
///
/// Amounts come from the authoritative catalog / subscription profile.
/// This helper never invents VAT, never cancels the base subscription, and
/// never deletes or replaces an existing vehicle.
library;

import 'package:fluxidi_tracking/company/subscription_addon_card_price.dart';
import 'package:fluxidi_tracking/company/subscription_fiscal_treatment.dart';

class ExtraVehiclePurchasePreview {
  const ExtraVehiclePurchasePreview({
    required this.usedVehicles,
    required this.capacity,
    required this.additionalSlots,
    required this.unitExclCents,
    required this.currentSubtotalExclCents,
    required this.newSubtotalExclCents,
  });

  final int usedVehicles;
  final int capacity;
  final int additionalSlots;
  final int unitExclCents;
  final int currentSubtotalExclCents;
  final int newSubtotalExclCents;

  bool get isAtCapacity => capacity > 0 && usedVehicles >= capacity;
}

/// Build the pre-purchase facts for one extra vehicle slot.
///
/// [currentSubtotalExclCents] must already be the authoritative recurring
/// excl. total (profile / quote / catalog composition). The new subtotal is
/// that amount plus one catalog extra-vehicle unit — never a client total.
ExtraVehiclePurchasePreview buildExtraVehiclePurchasePreview({
  required int usedVehicles,
  required int capacity,
  required int unitExclCents,
  required int currentSubtotalExclCents,
  int additionalSlots = 1,
}) {
  final slots = additionalSlots < 1 ? 1 : additionalSlots;
  final unit = unitExclCents < 0 ? 0 : unitExclCents;
  final current = currentSubtotalExclCents < 0 ? 0 : currentSubtotalExclCents;
  return ExtraVehiclePurchasePreview(
    usedVehicles: usedVehicles < 0 ? 0 : usedVehicles,
    capacity: capacity < 0 ? 0 : capacity,
    additionalSlots: slots,
    unitExclCents: unit,
    currentSubtotalExclCents: current,
    newSubtotalExclCents: current + (unit * slots),
  );
}

ExtraVehiclePurchasePreview extraVehiclePurchasePreviewFromAuthoritative({
  required int usedVehicles,
  required int capacity,
  required int catalogExtraVehicleExclCents,
  int? profileRecurringAmountCents,
  int? quoteRecurringExclVatCents,
  required int baseExclCents,
  required int extraDriverUnitExclCents,
  required int extraVehicleActiveQuantity,
  required int extraDriverActiveQuantity,
  int additionalSlots = 1,
}) {
  final current = resolveHeroRecurringExclCents(
    profileRecurringAmountCents: profileRecurringAmountCents,
    quoteRecurringExclVatCents: quoteRecurringExclVatCents,
    baseExclCents: baseExclCents,
    extraVehicleUnitExclCents: catalogExtraVehicleExclCents,
    extraDriverUnitExclCents: extraDriverUnitExclCents,
    extraVehicleActiveQuantity: extraVehicleActiveQuantity,
    extraDriverActiveQuantity: extraDriverActiveQuantity,
  );
  return buildExtraVehiclePurchasePreview(
    usedVehicles: usedVehicles,
    capacity: capacity,
    unitExclCents: catalogExtraVehicleExclCents,
    currentSubtotalExclCents: current,
    additionalSlots: additionalSlots,
  );
}

enum ExtraVehiclePurchasePhase {
  idle,
  awaitingConfirmation,
  cancelled,
  blockedFiscal,
  checkoutStarting,
  checkoutFailed,
  awaitingPayment,
  activated,
}

/// In-memory purchase lock. Capacity only moves after confirmed success.
class ExtraVehiclePurchaseSession {
  ExtraVehiclePurchaseSession({
    required this.startingCapacity,
    SubscriptionFiscalVerdict? fiscal,
  }) : capacity = startingCapacity,
       fiscal = fiscal ?? const SubscriptionFiscalVerdict();

  final int startingCapacity;
  final SubscriptionFiscalVerdict fiscal;

  ExtraVehiclePurchasePhase phase = ExtraVehiclePurchasePhase.idle;
  int capacity;
  bool confirmationAccepted = false;

  bool get isBusy =>
      phase == ExtraVehiclePurchasePhase.checkoutStarting ||
      phase == ExtraVehiclePurchasePhase.awaitingPayment;

  bool get mayOpenVehicleCreateForm =>
      phase == ExtraVehiclePurchasePhase.activated &&
      capacity > startingCapacity;

  bool get subscriptionUnchanged => capacity == startingCapacity;

  ExtraVehiclePurchasePhase beginConfirmation() {
    if (fiscal.isBlocked) {
      phase = ExtraVehiclePurchasePhase.blockedFiscal;
      return phase;
    }
    if (isBusy || phase == ExtraVehiclePurchasePhase.activated) {
      return phase;
    }
    phase = ExtraVehiclePurchasePhase.awaitingConfirmation;
    return phase;
  }

  /// Explicit confirm. A second call while busy is ignored (idempotent).
  bool acceptConfirmation() {
    if (fiscal.isBlocked) {
      phase = ExtraVehiclePurchasePhase.blockedFiscal;
      return false;
    }
    if (phase != ExtraVehiclePurchasePhase.awaitingConfirmation) {
      return false;
    }
    confirmationAccepted = true;
    phase = ExtraVehiclePurchasePhase.checkoutStarting;
    return true;
  }

  void cancelConfirmation() {
    if (phase == ExtraVehiclePurchasePhase.activated) return;
    confirmationAccepted = false;
    phase = ExtraVehiclePurchasePhase.cancelled;
  }

  /// Double-tap / overlapping start while a payment is already in flight.
  bool tryBeginCheckout() {
    if (!confirmationAccepted) return false;
    if (fiscal.isBlocked) {
      phase = ExtraVehiclePurchasePhase.blockedFiscal;
      return false;
    }
    if (phase == ExtraVehiclePurchasePhase.checkoutStarting ||
        phase == ExtraVehiclePurchasePhase.awaitingPayment ||
        phase == ExtraVehiclePurchasePhase.activated) {
      return false;
    }
    phase = ExtraVehiclePurchasePhase.checkoutStarting;
    return true;
  }

  void markAwaitingPayment() {
    if (!confirmationAccepted) return;
    if (phase != ExtraVehiclePurchasePhase.checkoutStarting) return;
    phase = ExtraVehiclePurchasePhase.awaitingPayment;
  }

  void markUpstreamFailure() {
    if (phase == ExtraVehiclePurchasePhase.activated) return;
    phase = ExtraVehiclePurchasePhase.checkoutFailed;
  }

  void markActivated({required int newCapacity}) {
    if (!confirmationAccepted) return;
    if (newCapacity <= startingCapacity) {
      markUpstreamFailure();
      return;
    }
    capacity = newCapacity;
    phase = ExtraVehiclePurchasePhase.activated;
  }
}

String formatSubscriptionExclCents(int cents) {
  final safe = cents < 0 ? 0 : cents;
  if (safe % 100 == 0) return '€${safe ~/ 100}';
  final whole = safe ~/ 100;
  final fraction = (safe % 100).toString().padLeft(2, '0');
  return '€$whole.$fraction';
}

String extraVehicleCapacityLine({
  required String languageCode,
  required ExtraVehiclePurchasePreview preview,
}) {
  return _t(
    languageCode,
    nl: 'Huidige capaciteit ${preview.usedVehicles}/${preview.capacity}',
    en: 'Current capacity ${preview.usedVehicles}/${preview.capacity}',
    fr: 'Capacité actuelle ${preview.usedVehicles}/${preview.capacity}',
    es: 'Capacidad actual ${preview.usedVehicles}/${preview.capacity}',
  );
}

String extraVehicleAdditionalSlotLine({
  required String languageCode,
  required ExtraVehiclePurchasePreview preview,
}) {
  return _t(
    languageCode,
    nl: '${preview.additionalSlots} extra voertuigslot',
    en: '${preview.additionalSlots} additional vehicle slot',
    fr: '${preview.additionalSlots} emplacement véhicule supplémentaire',
    es: '${preview.additionalSlots} plaza de vehículo adicional',
  );
}

String extraVehicleUnitPriceLine({
  required String languageCode,
  required ExtraVehiclePurchasePreview preview,
}) {
  final price = formatSubscriptionExclCents(preview.unitExclCents);
  return _t(
    languageCode,
    nl: '$price/maand excl. btw',
    en: '$price/month excl. VAT',
    fr: '$price/mois HT',
    es: '$price/mes sin IVA',
  );
}

String extraVehicleNewSubtotalLine({
  required String languageCode,
  required ExtraVehiclePurchasePreview preview,
}) {
  final price = formatSubscriptionExclCents(preview.newSubtotalExclCents);
  return _t(
    languageCode,
    nl: 'Nieuw subtotaal $price/maand excl. btw',
    en: 'New subtotal $price/month excl. VAT',
    fr: 'Nouveau sous-total $price/mois HT',
    es: 'Nuevo subtotal $price/mes sin IVA',
  );
}

String extraVehicleConfirmActionLabel(String languageCode) {
  return _t(
    languageCode,
    nl: 'Bevestig extra voertuig',
    en: 'Confirm extra vehicle',
    fr: 'Confirmer le véhicule extra',
    es: 'Confirmar vehículo extra',
  );
}

String extraVehicleCancelActionLabel(String languageCode) {
  return _t(
    languageCode,
    nl: 'Annuleren',
    en: 'Cancel',
    fr: 'Annuler',
    es: 'Cancelar',
  );
}

String _t(
  String languageCode, {
  required String nl,
  required String en,
  required String fr,
  required String es,
}) {
  switch (languageCode.trim().toLowerCase()) {
    case 'en':
      return en;
    case 'fr':
      return fr;
    case 'es':
      return es;
    case 'nl':
    default:
      return nl;
  }
}
