/// One payment method row, and the wording that goes on it.
///
/// Taxi, airport and limousine all show the customer the same list of methods,
/// so the wording and the row itself live here instead of being restated per
/// surface. What stays with each surface is its theme and its own language
/// resolution, because those already differ between them.
///
/// Which methods appear, and which of them a customer may confirm with, is
/// decided by `booking_payment_options.dart`. This file only draws the result.
library;

import 'package:flutter/material.dart';

import 'payment_method_catalog.dart';
import 'payment_method_logo.dart';
import 'payment_method_resolver.dart';

/// Picks the caller's translation of one string.
///
/// Surfaces differ in how they treat languages they have no copy for, so each
/// one passes its own existing helper rather than inheriting a fallback.
typedef PaymentCopyResolver =
    String Function({
      required String nl,
      required String en,
      required String fr,
      required String es,
    });

/// Customer-facing name of a payment method.
String paymentMethodDisplayLabel(String methodId, PaymentCopyResolver t) {
  switch (normalizePaymentMethodId(methodId)) {
    case PaymentMethodIds.inVehicleCard:
      return t(
        nl: 'Betalen in de auto',
        en: 'Pay in the car',
        fr: 'Payer dans la voiture',
        es: 'Pagar en el coche',
      );
    case PaymentMethodIds.bancontact:
      return 'Bancontact';
    case PaymentMethodIds.kbcCbc:
      return 'KBC/CBC Payment Button';
    case PaymentMethodIds.belfius:
      return 'Belfius Pay Button';
    case PaymentMethodIds.bancontactQr:
      return 'Payconiq / Bancontact Pay QR';
    case PaymentMethodIds.qrCode:
      return t(
        nl: 'QR-betaling',
        en: 'QR payment',
        fr: 'Paiement par QR',
        es: 'Pago por QR',
      );
    case PaymentMethodIds.ideal:
      return 'iDEAL';
    case PaymentMethodIds.cardPayment:
      return t(
        nl: 'Kaartbetaling',
        en: 'Card payment',
        fr: 'Paiement par carte',
        es: 'Pago con tarjeta',
      );
    case PaymentMethodIds.applePay:
      return 'Apple Pay';
    case PaymentMethodIds.googlePay:
      return 'Google Pay';
    case PaymentMethodIds.paypal:
      return 'PayPal';
    case PaymentMethodIds.bizum:
      return 'Bizum';
    case PaymentMethodIds.cartesBancaires:
      return 'Carte Bancaire / CB';
    case PaymentMethodIds.payconiqWero:
      return 'Payconiq / Wero';
    default:
      return methodId;
  }
}

String paymentMethodUnavailableMessage(PaymentCopyResolver t) {
  return t(
    nl: 'Deze betaalmethode is niet beschikbaar voor dit bedrijf.',
    en: 'This payment method is not available for this company.',
    fr: 'Ce moyen de paiement n’est pas disponible pour cette entreprise.',
    es: 'Este método de pago no está disponible para esta empresa.',
  );
}

String qrPaymentSetupRequiredMessage(PaymentCopyResolver t) {
  return t(
    nl: 'Vul eerst de bankgegevens in bij de bedrijfsinstellingen.',
    en: 'Add bank details in business settings first.',
    fr: 'Ajoutez d’abord les coordonnées bancaires dans les paramètres de l’entreprise.',
    es: 'Añade primero los datos bancarios en la configuración de la empresa.',
  );
}

String payconiqWeroPendingMessage(PaymentCopyResolver t) {
  return t(
    nl: 'Payconiq / Wero wordt later als aparte betaaloptie gekoppeld.',
    en: 'Payconiq / Wero will be connected later as a separate payment option.',
    fr: 'Payconiq / Wero sera connecté plus tard comme option de paiement séparée.',
    es: 'Payconiq / Wero se conectará más adelante como una opción de pago separada.',
  );
}

/// Why a method the customer just tapped cannot be used.
String displayOnlyPaymentMethodMessage(
  String methodId,
  PaymentCopyResolver t, {
  required String languageCode,
}) {
  final id = normalizePaymentMethodId(methodId);
  if (id == PaymentMethodIds.qrCode) {
    return qrPaymentSetupRequiredMessage(t);
  }
  if (id == PaymentMethodIds.payconiqWero) {
    return payconiqWeroPendingMessage(t);
  }
  if (id == PaymentMethodIds.googlePay) {
    return PaymentMethodResolver.googlePayTestModeUnavailableMessage(
      languageCode: languageCode,
    );
  }
  return paymentMethodUnavailableMessage(t);
}

/// What happens after confirming, per method.
///
/// The airport review page words two of these differently and keeps its own
/// version; it is not a second rule set, only different copy.
String paymentMethodShortDescription(
  String methodId,
  PaymentCopyResolver t, {
  required bool qrPaymentConfigured,
}) {
  final id = normalizePaymentMethodId(methodId);
  if (id == PaymentMethodIds.inVehicleCard || id == PaymentMethodIds.cash) {
    return t(
      nl: 'Boeking wordt meteen aangemaakt, betaling volgt tijdens de rit.',
      en: 'Booking is created immediately, payment follows during the ride.',
      fr: 'La réservation est créée immédiatement, paiement pendant le trajet.',
      es: 'La reserva se crea al instante, el pago se realiza durante el trayecto.',
    );
  }
  if (id == PaymentMethodIds.qrCode) {
    if (!qrPaymentConfigured) {
      return t(
        nl: 'Bankgegevens ontbreken in de bedrijfsinstellingen.',
        en: 'Bank details are missing in business settings.',
        fr: 'Les coordonnées bancaires manquent dans les paramètres de l’entreprise.',
        es: 'Faltan los datos bancarios en la configuración de la empresa.',
      );
    }
    return t(
      nl: 'Scan en betaal naar de rekening van het bedrijf.',
      en: 'Scan and pay to the company bank account.',
      fr: 'Scannez et payez sur le compte bancaire de l’entreprise.',
      es: 'Escanea y paga a la cuenta bancaria de la empresa.',
    );
  }
  if (id == PaymentMethodIds.payconiqWero) {
    return t(
      nl: 'Payconiq / Wero — binnenkort beschikbaar',
      en: 'Payconiq / Wero — coming soon',
      fr: 'Payconiq / Wero — bientôt disponible',
      es: 'Payconiq / Wero — próximamente',
    );
  }
  if (id == PaymentMethodIds.bancontactQr) {
    return t(
      nl: 'Scan met Bancontact Pay, Payconiq by Bancontact of je bank-app.',
      en: 'Scan with Bancontact Pay, Payconiq by Bancontact, or your Belgian banking app.',
      fr: 'Scannez avec Bancontact Pay, Payconiq by Bancontact ou votre application bancaire belge.',
      es: 'Escanea con Bancontact Pay, Payconiq by Bancontact o tu app bancaria belga.',
    );
  }
  return t(
    nl: 'Open de beveiligde betaalpagina na het bevestigen.',
    en: 'Open the secure checkout page after confirming.',
    fr: 'Ouvrez la page de paiement sécurisée après confirmation.',
    es: 'Abre la página de pago segura tras confirmar.',
  );
}

/// Theme values one surface uses to draw its payment rows.
class BookingPaymentTileStyle {
  const BookingPaymentTileStyle({
    required this.animationDuration,
    required this.padding,
    required this.selectedBackground,
    required this.unselectedBackground,
    required this.selectedBorderColor,
    required this.unselectedBorderColor,
    required this.accentColor,
    required this.labelColor,
    required this.mutedColor,
    required this.descriptionColor,
    required this.unselectedLogoColor,
    this.descriptionFontSize = 11.2,
  });

  final Duration animationDuration;
  final EdgeInsets padding;
  final Color selectedBackground;
  final Color unselectedBackground;
  final Color selectedBorderColor;
  final Color unselectedBorderColor;

  /// Colour of the selected state: border, radio icon and logo fallback.
  final Color accentColor;

  final Color labelColor;
  final Color mutedColor;
  final Color descriptionColor;

  /// Logo fallback colour for an unselected, selectable method.
  final Color unselectedLogoColor;

  final double descriptionFontSize;
}

/// A single selectable payment method row.
class BookingPaymentMethodTile extends StatelessWidget {
  const BookingPaymentMethodTile({
    super.key,
    required this.methodId,
    required this.label,
    required this.description,
    required this.selected,
    required this.displayOnly,
    required this.style,
    this.onSelect,
    this.onDisplayOnlyTap,
  });

  final String methodId;
  final String label;
  final String description;
  final bool selected;

  /// Shown for information: tapping explains why it cannot be used.
  final bool displayOnly;

  final BookingPaymentTileStyle style;

  /// Null while the surface is busy, which disables the row.
  final VoidCallback? onSelect;
  final VoidCallback? onDisplayOnlyTap;

  @override
  Widget build(BuildContext context) {
    final fallbackIconColor = displayOnly
        ? style.mutedColor.withOpacity(0.72)
        : selected
        ? style.accentColor
        : style.unselectedLogoColor;
    final disabled = displayOnly ? onDisplayOnlyTap == null : onSelect == null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: disabled ? null : (displayOnly ? onDisplayOnlyTap : onSelect),
      child: AnimatedContainer(
        duration: style.animationDuration,
        width: double.infinity,
        padding: style.padding,
        decoration: BoxDecoration(
          color: selected
              ? style.selectedBackground
              : style.unselectedBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? style.selectedBorderColor
                : style.unselectedBorderColor,
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Row(
          children: [
            buildPaymentMethodLogo(
              methodId: methodId,
              fallbackIconColor: fallbackIconColor,
              plateWidth: 44,
              plateHeight: 32,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: displayOnly ? style.mutedColor : style.labelColor,
                      fontSize: 12.8,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      color: style.descriptionColor,
                      fontSize: style.descriptionFontSize,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              displayOnly
                  ? Icons.info_outline_rounded
                  : selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: displayOnly
                  ? style.mutedColor.withOpacity(0.72)
                  : selected
                  ? style.accentColor
                  : style.mutedColor.withOpacity(0.8),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
