/// COMMERCIAL-ENTITLEMENT-FLUTTER-P0 — pure entitlement UX helpers.
///
/// Server remains authoritative. These helpers only classify denials and
/// produce localized, user-safe copy. Never surfaces machine error codes.
library;

import 'package:fluxidi_tracking/company/fluxidi_play_distribution.dart';

/// Machine tokens that mean NEW operational work is denied.
const Set<String> kSubscriptionEntitlementDenyTokens = {
  'subscription_entitlement_denied',
  'subscription_suspended',
  'payment_required',
  'company_unavailable',
};

enum SubscriptionEntitlementDenyKind {
  none,
  companyOperational,
  publicCompanyUnavailable,
}

class SubscriptionEntitlementDeny {
  const SubscriptionEntitlementDeny({
    required this.kind,
    this.httpStatus,
    this.token = '',
  });

  final SubscriptionEntitlementDenyKind kind;
  final int? httpStatus;
  final String token;

  bool get isDenied => kind != SubscriptionEntitlementDenyKind.none;
  bool get isPublicUnavailable =>
      kind == SubscriptionEntitlementDenyKind.publicCompanyUnavailable;
  bool get isCompanyOperationalDeny =>
      kind == SubscriptionEntitlementDenyKind.companyOperational;
}

/// Parse HTTP status + body/error text into an entitlement deny verdict.
SubscriptionEntitlementDeny classifySubscriptionEntitlementDeny({
  int? httpStatus,
  String? errorBody,
  String? errorToken,
}) {
  final token = (errorToken ?? '').trim().toLowerCase();
  final body = (errorBody ?? '').trim().toLowerCase();
  final combined = '$token $body';

  final status = httpStatus;
  final hasCompanyUnavailable =
      token == 'company_unavailable' || body.contains('company_unavailable');
  final hasEntitlementToken = kSubscriptionEntitlementDenyTokens.any(
    (t) => t != 'company_unavailable' && (token == t || body.contains(t)),
  );

  if (status == 503 || hasCompanyUnavailable) {
    // Public/customer neutral path. Prefer this when company_unavailable is
    // present even if status is missing.
    if (hasCompanyUnavailable || status == 503) {
      return SubscriptionEntitlementDeny(
        kind: SubscriptionEntitlementDenyKind.publicCompanyUnavailable,
        httpStatus: status,
        token: hasCompanyUnavailable ? 'company_unavailable' : token,
      );
    }
  }

  if (status == 402 || hasEntitlementToken) {
    return SubscriptionEntitlementDeny(
      kind: SubscriptionEntitlementDenyKind.companyOperational,
      httpStatus: status,
      token: token.isNotEmpty
          ? token
          : (hasEntitlementToken
                ? kSubscriptionEntitlementDenyTokens.firstWhere(
                    (t) => body.contains(t),
                    orElse: () => 'subscription_entitlement_denied',
                  )
                : 'subscription_entitlement_denied'),
    );
  }

  // Exception strings like "HTTP 402: {...}" or bare error codes.
  final httpMatch = RegExp(r'http\s+(\d{3})').firstMatch(combined);
  if (httpMatch != null) {
    final parsed = int.tryParse(httpMatch.group(1) ?? '');
    if (parsed == 402) {
      return const SubscriptionEntitlementDeny(
        kind: SubscriptionEntitlementDenyKind.companyOperational,
        httpStatus: 402,
        token: 'subscription_entitlement_denied',
      );
    }
    if (parsed == 503 && hasCompanyUnavailable) {
      return const SubscriptionEntitlementDeny(
        kind: SubscriptionEntitlementDenyKind.publicCompanyUnavailable,
        httpStatus: 503,
        token: 'company_unavailable',
      );
    }
  }
  if (hasEntitlementToken) {
    return SubscriptionEntitlementDeny(
      kind: SubscriptionEntitlementDenyKind.companyOperational,
      token: token.isNotEmpty ? token : 'subscription_entitlement_denied',
    );
  }
  return const SubscriptionEntitlementDeny(
    kind: SubscriptionEntitlementDenyKind.none,
  );
}

/// True when a direct/planned start failure must hard-abort (no local-only).
bool isSubscriptionEntitlementHardAbort(Object error) {
  final text = error.toString();
  final match = RegExp(r'HTTP\s+(\d{3})').firstMatch(text);
  final status = match == null ? null : int.tryParse(match.group(1) ?? '');
  final deny = classifySubscriptionEntitlementDeny(
    httpStatus: status,
    errorBody: text,
  );
  return deny.isCompanyOperationalDeny;
}

String subscriptionStatusLabel({
  required String statusRaw,
  required String languageCode,
}) {
  final status = statusRaw.trim().toLowerCase();
  switch (status) {
    case 'trialing':
    case 'trial':
    case 'trial_active':
      return _t(languageCode,
          nl: 'Proefperiode',
          en: 'Trial',
          fr: 'Période d’essai',
          es: 'Periodo de prueba');
    case 'active':
      return _t(languageCode,
          nl: 'Actief', en: 'Active', fr: 'Actif', es: 'Activo');
    case 'past_due':
      return _t(languageCode,
          nl: 'Betaling vereist',
          en: 'Payment required',
          fr: 'Paiement requis',
          es: 'Pago requerido');
    case 'grace_period':
      return _t(languageCode,
          nl: 'Betalingstermijn',
          en: 'Grace period',
          fr: 'Délai de grâce',
          es: 'Periodo de gracia');
    case 'payment_required':
      return _t(languageCode,
          nl: 'Abonnement vereist',
          en: 'Subscription required',
          fr: 'Abonnement requis',
          es: 'Suscripción requerida');
    case 'cancelled':
    case 'canceled':
      return _t(languageCode,
          nl: 'Geannuleerd',
          en: 'Cancelled',
          fr: 'Annulé',
          es: 'Cancelado');
    case 'suspended':
      return _t(languageCode,
          nl: 'Opgeschort',
          en: 'Suspended',
          fr: 'Suspendu',
          es: 'Suspendido');
    case 'inactive':
      return _t(languageCode,
          nl: 'Inactief',
          en: 'Inactive',
          fr: 'Inactif',
          es: 'Inactivo');
    default:
      return status.isEmpty
          ? _t(languageCode,
              nl: 'Onbekend',
              en: 'Unknown',
              fr: 'Inconnu',
              es: 'Desconocido')
          : statusRaw.trim();
  }
}

/// Warning-only during past_due / grace (backend still allows ops).
String? subscriptionDunningWarningMessage({
  required String statusRaw,
  required String languageCode,
}) {
  final status = statusRaw.trim().toLowerCase();
  if (status == 'past_due' || status == 'grace_period') {
    return _t(
      languageCode,
      nl: 'Er is een openstaand abonnementsbedrag. Je hebt nog een betalingstermijn; vernieuw je abonnement om onderbreking te vermijden.',
      en: 'There is an outstanding subscription payment. You are still in a grace period; renew to avoid interruption.',
      fr: 'Un paiement d’abonnement est en souffrance. Vous êtes encore dans un délai de grâce ; renouvelez pour éviter une interruption.',
      es: 'Hay un pago de suscripción pendiente. Aún estás en periodo de gracia; renueva para evitar interrupciones.',
    );
  }
  return null;
}

String? subscriptionBlockedStateMessage({
  required String statusRaw,
  required String languageCode,
  required bool cancelAtPeriodEnd,
}) {
  final status = statusRaw.trim().toLowerCase();
  if (status == 'payment_required') {
    return _t(
      languageCode,
      nl: 'Je proefperiode is afgelopen. Voor operationeel gebruik is een actief abonnement vereist.',
      en: 'Your trial has ended. An active subscription is required for operational use.',
      fr: 'Votre période d’essai est terminée. Un abonnement actif est requis pour l’usage opérationnel.',
      es: 'Tu periodo de prueba ha terminado. Se requiere una suscripción activa para el uso operativo.',
    );
  }
  if (status == 'cancelled' || status == 'canceled') {
    // After period end only — do not imply immediate cancel while still active.
    return _t(
      languageCode,
      nl: 'Je abonnement is afgelopen. Voor nieuwe ritten is een actief abonnement vereist.',
      en: 'Your subscription has ended. An active subscription is required for new rides.',
      fr: 'Votre abonnement est terminé. Un abonnement actif est requis pour de nouvelles courses.',
      es: 'Tu suscripción ha terminado. Se requiere una suscripción activa para nuevos viajes.',
    );
  }
  if (status == 'suspended') {
    return _t(
      languageCode,
      nl: 'Je abonnement is opgeschort. Nieuwe ritten zijn geblokkeerd tot de betaling is hersteld.',
      en: 'Your subscription is suspended. New rides are blocked until payment is restored.',
      fr: 'Votre abonnement est suspendu. Les nouvelles courses sont bloquées jusqu’au rétablissement du paiement.',
      es: 'Tu suscripción está suspendida. Los nuevos viajes están bloqueados hasta restablecer el pago.',
    );
  }
  // Still active with cancel scheduled — informational only (not blocked).
  if (status == 'active' && cancelAtPeriodEnd) {
    return null;
  }
  return null;
}

String companyEntitlementDeniedMessage({
  required String languageCode,
  bool playDistribution = kFluxidiPlayDistribution,
}) {
  final base = _t(
    languageCode,
    nl: 'Abonnement vereist.\nJe bedrijf kan momenteel geen nieuwe ritten starten.\nOpen Abonnement & facturatie voor meer informatie.',
    en: 'Subscription required.\nYour company cannot start new rides right now.\nOpen Subscription & billing for more information.',
    fr: 'Abonnement requis.\nVotre entreprise ne peut pas démarrer de nouvelles courses pour le moment.\nOuvrez Abonnement & facturation pour plus d’informations.',
    es: 'Suscripción requerida.\nTu empresa no puede iniciar nuevos viajes ahora.\nAbre Suscripción y facturación para más información.',
  );
  if (!playDistribution) return base;
  final outside = fluxidiPlaySaasManagedOutsideMessage(
    languageCode: languageCode,
  );
  return '$base\n$outside';
}

String publicCompanyUnavailableMessage({required String languageCode}) {
  return _t(
    languageCode,
    nl: 'Dit bedrijf is momenteel niet actief en kan geen nieuwe boekingen ontvangen.',
    en: 'This company is currently inactive and cannot accept new bookings.',
    fr: 'Cette entreprise est actuellement inactive et ne peut pas accepter de nouvelles réservations.',
    es: 'Esta empresa está actualmente inactiva y no puede aceptar nuevas reservas.',
  );
}

/// Maps booking/quote errors to user-safe text. Returns null when not entitlement.
String? friendlyEntitlementUserMessage({
  required String rawError,
  required String languageCode,
  required bool isPublicCustomer,
  int? httpStatus,
}) {
  final deny = classifySubscriptionEntitlementDeny(
    httpStatus: httpStatus,
    errorBody: rawError,
  );
  if (!deny.isDenied) return null;
  if (isPublicCustomer || deny.isPublicUnavailable) {
    return publicCompanyUnavailableMessage(languageCode: languageCode);
  }
  return companyEntitlementDeniedMessage(languageCode: languageCode);
}

bool subscriptionStatusIsWarningOnly(String statusRaw) {
  final s = statusRaw.trim().toLowerCase();
  return s == 'past_due' || s == 'grace_period';
}

bool subscriptionStatusIsOperationallyBlocked(String statusRaw) {
  final s = statusRaw.trim().toLowerCase();
  return s == 'payment_required' ||
      s == 'suspended' ||
      s == 'cancelled' ||
      s == 'canceled';
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
