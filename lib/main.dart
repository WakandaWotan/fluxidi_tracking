import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:fluxidi_tracking/calculator_page.dart';
import 'package:fluxidi_tracking/customer_booking_store.dart';
import 'package:fluxidi_tracking/customer_bookings_store.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/payment_return.dart';
export 'package:fluxidi_tracking/payment_return.dart'
    show
        kFluxidiPaymentReturnScheme,
        kFluxidiPaymentReturnHost,
        kFluxidiPaymentReturnUrl,
        FluxidiPaymentStatus,
        FluxidiPendingPayment,
        fluxidiPendingPaymentNotifier,
        setFluxidiPendingPayment,
        clearFluxidiPendingPayment,
        paymentReturnCoordinator,
        PaymentReturnCoordinator;
import 'package:fluxidi_tracking/business_settings_page.dart';
import 'package:fluxidi_tracking/vehicle_management_page.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/company_onboarding_page.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

import 'widgets/cockpit_widget.dart';
import 'widgets/route_marquee.dart';

final bool kIsWindows = !kIsWeb && Platform.isWindows;

/// White-label config aliases (keeps existing code paths stable).
final String kAppTitle = appConfig.appTitle;
final String kCompanyName = appConfig.companyName;
String get kBookingsTitle =>
    appConfig.strings.bookingsTitle.of(appConfig.currentLanguage);
String get kLiveRideTitle =>
    appConfig.strings.liveRideTitle.of(appConfig.currentLanguage);
String get kActiveRideTitle =>
    appConfig.strings.activeRideTitle.of(appConfig.currentLanguage);
String get kRefreshBookingsLabel =>
    appConfig.strings.refreshBookingsLabel.of(appConfig.currentLanguage);
String get kCenterOnMeLabel =>
    appConfig.strings.centerOnMeLabel.of(appConfig.currentLanguage);
String get kDrawerDriverIdLabel =>
    appConfig.strings.drawerDriverIdLabel.of(appConfig.currentLanguage);
String get kDrawerWorkerLabel =>
    appConfig.strings.drawerWorkerLabel.of(appConfig.currentLanguage);
String get kDrawerMapboxTokenLabel =>
    appConfig.strings.drawerMapboxTokenLabel.of(appConfig.currentLanguage);
String get kDrawerLanguageLabel =>
    appConfig.strings.drawerLanguageLabel.of(appConfig.currentLanguage);
String get kDrawerBusinessSettingsLabel =>
    appConfig.strings.drawerBusinessSettingsLabel.of(appConfig.currentLanguage);
String get kDrawerBusinessSettingsSubtitle => appConfig
    .strings
    .drawerBusinessSettingsSubtitle
    .of(appConfig.currentLanguage);
String get kDrawerVehiclesLabel =>
    appConfig.strings.drawerVehiclesLabel.of(appConfig.currentLanguage);
String get kDrawerVehiclesSubtitle =>
    appConfig.strings.drawerVehiclesSubtitle.of(appConfig.currentLanguage);
String get kFollowCarLabel =>
    appConfig.strings.followCarLabel.of(appConfig.currentLanguage);
String get kFollowCarSubtitle =>
    appConfig.strings.followCarSubtitle.of(appConfig.currentLanguage);
String get kBookingsMenuSubtitle =>
    appConfig.strings.bookingsMenuSubtitle.of(appConfig.currentLanguage);
String get kLiveRideMenuSubtitle =>
    appConfig.strings.liveRideMenuSubtitle.of(appConfig.currentLanguage);
String get kCalculatorMenuSubtitle =>
    appConfig.strings.calculatorMenuSubtitle.of(appConfig.currentLanguage);
String get kActiveRideMenuSubtitle =>
    appConfig.strings.activeRideMenuSubtitle.of(appConfig.currentLanguage);
String get kAvailableBookingsTitle =>
    appConfig.strings.availableBookingsTitle.of(appConfig.currentLanguage);
String get kRefreshShortLabel =>
    appConfig.strings.refreshShortLabel.of(appConfig.currentLanguage);
String get kBookingsEmptyLabel =>
    appConfig.strings.bookingsEmptyLabel.of(appConfig.currentLanguage);
String get kStopShortLabel =>
    appConfig.strings.stopShortLabel.of(appConfig.currentLanguage);
String get kRideActionCompletedLabel =>
    appConfig.strings.rideActionCompletedLabel.of(appConfig.currentLanguage);
String get kRideActionCancelledLabel =>
    appConfig.strings.rideActionCancelledLabel.of(appConfig.currentLanguage);
String get kRideGoToRideLabel =>
    appConfig.strings.rideGoToRideLabel.of(appConfig.currentLanguage);
String get kRideDeleteLabel =>
    appConfig.strings.rideDeleteLabel.of(appConfig.currentLanguage);
String get kRideStatusPendingLabel =>
    appConfig.strings.rideStatusPendingLabel.of(appConfig.currentLanguage);
String get kPickupLabel =>
    appConfig.strings.pickupLabel.of(appConfig.currentLanguage);
String get kDropoffLabel =>
    appConfig.strings.dropoffLabel.of(appConfig.currentLanguage);
final String kDefaultCurrency = appConfig.defaultCurrency;
final Color kGlow = appConfig.accentColor;

/// ✅ Mapbox token for REST calls (geocoding + directions).
/// Set at run/build time:
/// flutter run --dart-define=MAPBOX_TOKEN=pk.xxx
const String kMapboxToken = String.fromEnvironment(
  'MAPBOX_TOKEN',
  defaultValue: '',
);

Map<String, String> _adminHeaders() {
  final t = kAdminToken.trim();
  if (t.isEmpty) return <String, String>{};
  return <String, String>{'Authorization': 'Bearer $t', 'x-admin-token': t};
}

// Pending Mollie payment tracking lives in lib/payment_return.dart and is
// re-exported above so existing references in this file (and other modules)
// keep working unchanged.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadLocalTenantState();
  await CompanySessionStore.instance.bootstrap();
  await DriverSessionStore.instance.bootstrap(driversNotifier.value);
  // Mapbox REST token is optional in this build.
  // If not provided, the app will fall back to Worker-side routing where possible.
  if (kMapboxToken.trim().isEmpty) {
    // ignore: avoid_print
    print('⚠️ MAPBOX_TOKEN not set (using fallback routing).');
  } else {
    mb.MapboxOptions.setAccessToken(kMapboxToken);
  }
  // App-level Mollie return-to-app coordinator. Started here (not inside any
  // screen State) so deep links + lifecycle resume are handled regardless of
  // which page is currently mounted.
  paymentReturnCoordinator.start(bookingBaseUrl: kBookingBaseUrl);
  runApp(const FluxidiDriverApp());
}

/// ===============================
/// CONFIG
/// ===============================

/// ✅ Production default Worker base URL (NO trailing slash)
final String kWorkerBaseUrlDefault = appConfig.workerBaseUrl;

/// ✅ Booking API base URL (used for pricing + route helpers).
/// Default points to the booking Worker (NOT the tracking API Worker).
final String kBookingBaseUrlDefault = appConfig.bookingBaseUrl;

/// Optional override via dart-define (handy for staging)
/// flutter run ... --dart-define=BOOKING_BASE_URL=https://...workers.dev
const String kBookingBaseUrlOverride = String.fromEnvironment(
  'BOOKING_BASE_URL',
  defaultValue: '',
);

String get kBookingBaseUrl {
  final v = kBookingBaseUrlOverride.trim();
  if (v.isNotEmpty) return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  return kBookingBaseUrlDefault;
}

/// Optional override via dart-define (handig voor staging)
/// flutter run ... --dart-define=WORKER_BASE_URL=https://...workers.dev
const String kWorkerBaseUrlOverride = String.fromEnvironment(
  'WORKER_BASE_URL',
  defaultValue: '',
);

String get kWorkerBaseUrl {
  final v = kWorkerBaseUrlOverride.trim();
  if (v.isNotEmpty) return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  return kWorkerBaseUrlDefault;
}

/// Driver id for Worker `driver_id` fields — chauffeur session [DriverProfile.id] when logged in,
/// otherwise [kFallbackDriverTrackingId] for legacy/company-preview driver view.
String get kDriverId => resolvedDriverTrackingId;

/// Admin token (optional) for driver actions like complete/cancel/delete.
/// Set at run/build time:
/// flutter run --dart-define=ADMIN_TOKEN=yourSecret
const String kAdminToken = String.fromEnvironment(
  'ADMIN_TOKEN',
  defaultValue: '',
);

/// Endpoints (adjust if your Worker uses different paths)
const String kListBookingsPath = '/bookings';
const String kGetBookingPath =
    '/track/booking'; // returns booking + quote/pricing
const String kTrackingBookingPath =
    '/tracking/booking'; // booking Worker detail endpoint

// Admin endpoints (require x-admin-token if enabled in Worker)
const String kUpdateBookingStatusPath =
    '/bookings'; // POST /bookings/:id/status
const String kDeleteBookingPath = '/bookings'; // POST /bookings/:id/delete

const String kStartTripPath = '/track/session/start';
const String kPingPath = '/track/ping';
const String kStopTripPath = '/track/session/stop'; // optional
const String kStartDirectTripPath = '/trip/start-direct';
const String kRecordPlannedTripStopPath = '/trip/record-planned-stop';
const String kDirectTripWaitStartPath = '/trip/wait-start';
const String kDirectTripWaitEndPath = '/trip/wait-end';
const String kStopDirectTripPath = '/trip/stop';
const String kTripsHistoryPath = '/trips/history';
const String kTripsArchivePath = '/trips/archive';

/// Optional: Worker route endpoint (recommended, avoids exposing Mapbox token)
/// Implement later in Worker: POST { from, to } -> { coords:[[lon,lat],...], distance_m, duration_s }
const String kWorkerRoutePath = '/track/route';

/// ===============================
/// BRANDING (Fluxidi Taxi UI)
/// ===============================

/// Put your logo in this path (recommended):
///   assets/fluxidi/fluxidi_logo.png
/// and add it to pubspec.yaml under flutter/assets.
final String kFluxidiLogoAsset = appConfig.logoAsset;

/// Fluxidi Taxi colors (premium black + warm taxi yellow)
final Color kFluxidiYellow = appConfig.primaryColor;
final Color kFluxidiYellowSoft = appConfig.branding.softAccentColor;
final Color kFluxidiBlack = appConfig.backgroundColor;
final Color kFluxidiPanel = appConfig.branding.surfaceColor;
final Color kFluxidiCard = appConfig.branding.cardColor;
final Color kFluxidiTextSoft = appConfig.branding.textSoftColor;

String _tr({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) {
  final lang = appConfig.currentLanguage;
  if (lang == AppLanguage.en) return en;
  if (lang == AppLanguage.fr) return fr;
  if (lang == AppLanguage.es) return es;
  return nl;
}

String _receiptText(String key) {
  switch (key) {
    case 'receiptTitle':
      return _tr(nl: 'Ritbon', en: 'Receipt', fr: 'Reçu', es: 'Recibo');
    case 'rideReceipt':
      return _tr(
        nl: 'Bewijs van rit',
        en: 'Ride receipt',
        fr: 'Justificatif de course',
        es: 'Comprobante del viaje',
      );
    case 'receiptUnavailable':
      return _tr(
        nl: 'Ritbon is beschikbaar na afronden van de rit.',
        en: 'Receipt is available after completing the ride.',
        fr: 'Le reçu est disponible après la fin de la course.',
        es: 'El recibo esta disponible despues de finalizar el viaje.',
      );
    case 'tripHistoryTitle':
      return _tr(
        nl: 'Ritten historiek',
        en: 'Ride history',
        fr: 'Historique des courses',
        es: 'Historial de viajes',
      );
    case 'refresh':
      return _tr(
        nl: 'Vernieuw',
        en: 'Refresh',
        fr: 'Actualiser',
        es: 'Actualizar',
      );
    case 'historyLoadFailed':
      return _tr(
        nl: 'Kon ritten historiek niet laden.',
        en: 'Could not load ride history.',
        fr: "Impossible de charger l'historique.",
        es: 'No se pudo cargar el historial.',
      );
    case 'historyEmpty':
      return _tr(
        nl: 'Nog geen ritten gevonden.',
        en: 'No rides found yet.',
        fr: 'Aucune course trouvée.',
        es: 'Aun no hay viajes.',
      );
    case 'archiveTripLabel':
      return _tr(nl: 'Verberg', en: 'Hide', fr: 'Masquer', es: 'Ocultar');
    case 'archiveTripTitle':
      return _tr(
        nl: 'Deze rit verbergen uit de historiek?',
        en: 'Hide this ride from history?',
        fr: 'Masquer cette course de l’historique ?',
        es: '¿Ocultar este viaje del historial?',
      );
    case 'archiveTripBody':
      return _tr(
        nl: 'De ritbon blijft bewaard voor administratie.',
        en: 'The receipt will remain stored for administration.',
        fr: 'Le reçu reste conservé pour l’administration.',
        es: 'El recibo seguirá guardado para la administración.',
      );
    case 'archiveTripCancel':
      return _tr(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar');
    case 'archiveTripConfirm':
      return _tr(nl: 'Verbergen', en: 'Hide', fr: 'Masquer', es: 'Ocultar');
    case 'archiveTripSuccess':
      return _tr(
        nl: 'Rit verborgen uit historiek.',
        en: 'Ride hidden from history.',
        fr: 'Course masquée de l’historique.',
        es: 'Viaje ocultado del historial.',
      );
    case 'archiveTripFailed':
      return _tr(
        nl: 'Kon rit niet verbergen.',
        en: 'Could not hide ride.',
        fr: 'Impossible de masquer la course.',
        es: 'No se pudo ocultar el viaje.',
      );
    case 'waitingCompact':
      return _tr(nl: 'wachten', en: 'waiting', fr: 'attente', es: 'espera');
    case 'type':
      return _tr(nl: 'Type', en: 'Type', fr: 'Type', es: 'Tipo');
    case 'streetRide':
      return _tr(
        nl: 'Straatrit',
        en: 'Street ride',
        fr: 'Course directe',
        es: 'Viaje directo',
      );
    case 'plannedRide':
      return _tr(
        nl: 'Geplande rit',
        en: 'Planned ride',
        fr: 'Course planifiée',
        es: 'Viaje planificado',
      );
    case 'outboundRide':
      return _tr(
        nl: 'Heenrit',
        en: 'Outbound ride',
        fr: 'Trajet aller',
        es: 'Viaje de ida',
      );
    case 'returnRide':
      return _tr(
        nl: 'Retourrit',
        en: 'Return ride',
        fr: 'Trajet retour',
        es: 'Viaje de vuelta',
      );
    case 'subtype':
      return _tr(nl: 'Subtype', en: 'Subtype', fr: 'Sous-type', es: 'Subtipo');
    case 'receiptNumber':
      return _tr(
        nl: 'Bonnummer',
        en: 'Receipt no.',
        fr: 'Numéro de reçu',
        es: 'Número de recibo',
      );
    case 'tripId':
      return _tr(nl: 'Trip ID', en: 'Trip ID', fr: 'ID course', es: 'ID viaje');
    case 'bookingId':
      return _tr(
        nl: 'Booking ID',
        en: 'Booking ID',
        fr: 'ID réservation',
        es: 'ID reserva',
      );
    case 'date':
      return _tr(nl: 'Datum', en: 'Date', fr: 'Date', es: 'Fecha');
    case 'startTime':
      return _tr(
        nl: 'Starttijd',
        en: 'Start time',
        fr: 'Heure de début',
        es: 'Hora de inicio',
      );
    case 'endTime':
      return _tr(
        nl: 'Stoptijd',
        en: 'End time',
        fr: 'Heure de fin',
        es: 'Hora de fin',
      );
    case 'duration':
      return _tr(nl: 'Duur', en: 'Duration', fr: 'Durée', es: 'Duracion');
    case 'pickup':
      return _tr(
        nl: 'Ophaaladres',
        en: 'Pickup',
        fr: 'Prise en charge',
        es: 'Recogida',
      );
    case 'destination':
      return _tr(
        nl: 'Bestemming',
        en: 'Destination',
        fr: 'Destination',
        es: 'Destino',
      );
    case 'from':
      return _tr(nl: 'Van', en: 'From', fr: 'De', es: 'Desde');
    case 'to':
      return _tr(nl: 'Naar', en: 'To', fr: 'À', es: 'A');
    case 'distance':
      return _tr(
        nl: 'Afstand',
        en: 'Distance',
        fr: 'Distance',
        es: 'Distancia',
      );
    case 'actualDistance':
      return _tr(
        nl: 'Werkelijke afstand',
        en: 'Actual distance',
        fr: 'Distance réelle',
        es: 'Distancia real',
      );
    case 'waitingTime':
      return _tr(
        nl: 'Wachttijd',
        en: 'Waiting time',
        fr: "Temps d'attente",
        es: 'Tiempo de espera',
      );
    case 'bookedWaitingTime':
      return _tr(
        nl: 'Geboekte wachttijd',
        en: 'Booked waiting time',
        fr: "Attente réservée",
        es: 'Espera reservada',
      );
    case 'actualWaitingTime':
      return _tr(
        nl: 'Werkelijke wachttijd',
        en: 'Actual waiting time',
        fr: "Attente réelle",
        es: 'Espera real',
      );
    case 'plannedBookingDetails':
      return _tr(
        nl: 'Geplande boeking',
        en: 'Planned booking details',
        fr: 'Détails de réservation',
        es: 'Detalles de reserva',
      );
    case 'bookingDetails':
      return _tr(
        nl: 'Boekingsdetails',
        en: 'Booking details',
        fr: 'Détails de réservation',
        es: 'Detalles de reserva',
      );
    case 'customer':
      return _tr(nl: 'Klant', en: 'Customer', fr: 'Client', es: 'Cliente');
    case 'customerDetails':
      return _tr(
        nl: 'Klantgegevens',
        en: 'Customer details',
        fr: 'Coordonnées client',
        es: 'Datos del cliente',
      );
    case 'customerName':
      return _tr(
        nl: 'Klantnaam',
        en: 'Customer name',
        fr: 'Nom du client',
        es: 'Nombre del cliente',
      );
    case 'customerPhone':
      return _tr(
        nl: 'Telefoon',
        en: 'Customer phone',
        fr: 'Téléphone client',
        es: 'Telefono del cliente',
      );
    case 'customerEmail':
      return _tr(
        nl: 'E-mail',
        en: 'Customer email',
        fr: 'E-mail client',
        es: 'Email del cliente',
      );
    case 'scheduledPickup':
      return _tr(
        nl: 'Geplande ophaal',
        en: 'Scheduled pickup',
        fr: 'Prise en charge prévue',
        es: 'Recogida programada',
      );
    case 'service':
      return _tr(nl: 'Service', en: 'Service', fr: 'Service', es: 'Servicio');
    case 'passengerTransport':
      return _tr(
        nl: 'Personenvervoer',
        en: 'Passenger transport',
        fr: 'Transport de passagers',
        es: 'Transporte de pasajeros',
      );
    case 'businessRide':
      return _tr(
        nl: 'Zakelijke rit',
        en: 'Business ride',
        fr: "Course d'affaires",
        es: 'Viaje de negocios',
      );
    case 'airportTransfer':
      return _tr(
        nl: 'Luchthavenvervoer',
        en: 'Airport transfer',
        fr: 'Transfert aeroport',
        es: 'Traslado al aeropuerto',
      );
    case 'tier':
      return _tr(nl: 'Tier', en: 'Tier', fr: 'Catégorie', es: 'Categoría');
    case 'tierComfort':
      return _tr(nl: 'Comfort', en: 'Comfort', fr: 'Confort', es: 'Confort');
    case 'tierPrivate':
      return _tr(nl: 'Private', en: 'Private', fr: 'Prive', es: 'Privado');
    case 'tierPremium':
      return _tr(nl: 'Premium', en: 'Premium', fr: 'Premium', es: 'Premium');
    case 'passengers':
      return _tr(
        nl: 'Passagiers / Pax',
        en: 'Passengers / Pax',
        fr: 'Passagers / Pax',
        es: 'Pasajeros / Pax',
      );
    case 'bags':
      return _tr(nl: 'Bagage', en: 'Bags', fr: 'Bagages', es: 'Equipaje');
    case 'extraStops':
      return _tr(
        nl: 'Extra stops',
        en: 'Extra stops',
        fr: 'Arrêts supplémentaires',
        es: 'Paradas extra',
      );
    case 'extras':
      return _tr(nl: 'Extras', en: 'Extras', fr: 'Extras', es: 'Extras');
    case 'notes':
      return _tr(nl: 'Notities', en: 'Notes', fr: 'Notes', es: 'Notas');
    case 'routeAndPrices':
      return _tr(
        nl: 'Route en prijzen',
        en: 'Route and prices',
        fr: 'Itinéraire et prix',
        es: 'Ruta y precios',
      );
    case 'route':
      return _tr(nl: 'Route', en: 'Route', fr: 'Itinéraire', es: 'Ruta');
    case 'routeDetails':
      return _tr(
        nl: 'Route details',
        en: 'Route details',
        fr: "Détails de l'itinéraire",
        es: 'Detalles de ruta',
      );
    case 'outboundRoute':
      return _tr(
        nl: 'Heenroute',
        en: 'Outbound route',
        fr: 'Itinéraire aller',
        es: 'Ruta de ida',
      );
    case 'returnRoute':
      return _tr(
        nl: 'Retour route',
        en: 'Return route',
        fr: 'Itinéraire retour',
        es: 'Ruta de vuelta',
      );
    case 'returnTrip':
      return _tr(
        nl: 'Retourrit',
        en: 'Return trip',
        fr: 'Trajet retour',
        es: 'Viaje de vuelta',
      );
    case 'returnPlanned':
      return _tr(
        nl: 'Retour gepland',
        en: 'Return planned',
        fr: 'Retour prevu',
        es: 'Vuelta programada',
      );
    case 'fixedPrice':
      return _tr(
        nl: 'Vaste prijs',
        en: 'Fixed price',
        fr: 'Prix fixe',
        es: 'Precio fijo',
      );
    case 'fixedQuotePrice':
      return _tr(
        nl: 'Vaste offerteprijs',
        en: 'Fixed quote price',
        fr: 'Prix devis fixe',
        es: 'Precio fijo cotizado',
      );
    case 'packagePrice':
      return _tr(
        nl: 'Pakketprijs incl. btw',
        en: 'Package price incl. VAT',
        fr: 'Prix forfaitaire TVA incl.',
        es: 'Precio paquete IVA incl.',
      );
    case 'ridePrice':
      return _tr(
        nl: 'Ritprijs incl. btw',
        en: 'Ride price incl. VAT',
        fr: 'Prix course TVA incl.',
        es: 'Precio viaje IVA incl.',
      );
    case 'outboundPrice':
      return _tr(
        nl: 'Prijs heen incl. btw',
        en: 'Outbound price incl. VAT',
        fr: 'Prix aller TVA incl.',
        es: 'Precio ida IVA incl.',
      );
    case 'returnPrice':
      return _tr(
        nl: 'Prijs retour incl. btw',
        en: 'Return price incl. VAT',
        fr: 'Prix retour TVA incl.',
        es: 'Precio vuelta IVA incl.',
      );
    case 'total':
      return _tr(nl: 'Totaal', en: 'Total', fr: 'Total', es: 'Total');
    case 'amount':
      return _tr(nl: 'Bedrag', en: 'Amount', fr: 'Montant', es: 'Importe');
    case 'payment':
      return _tr(nl: 'Betalen', en: 'Payment', fr: 'Paiement', es: 'Pago');
    case 'receiptActions':
      return _tr(nl: 'Bon', en: 'Receipt', fr: 'Reçu', es: 'Recibo');
    case 'statusPaymentSection':
      return _tr(
        nl: 'Status en betaling',
        en: 'Status and payment',
        fr: 'Statut et paiement',
        es: 'Estado y pago',
      );
    case 'paymentActions':
      return _tr(nl: 'Betaalzone', en: 'Payment', fr: 'Paiement', es: 'Pago');
    case 'moreOptions':
      return _tr(
        nl: 'Meer opties',
        en: 'More options',
        fr: 'Plus d’options',
        es: 'Más opciones',
      );
    case 'payByQr':
      return _tr(
        nl: 'Betaal via QR',
        en: 'Pay by QR',
        fr: 'Payer par QR',
        es: 'Pagar con QR',
      );
    case 'cashReceived':
      return _tr(
        nl: 'Cash ontvangen',
        en: 'Cash received',
        fr: 'Espèces reçues',
        es: 'Efectivo recibido',
      );
    case 'paidByCardTerminal':
      return _tr(
        nl: 'Betaald via Bancontact',
        en: 'Paid by card terminal',
        fr: 'Payé par terminal bancaire',
        es: 'Pagado con terminal de tarjeta',
      );
    case 'confirmQrPaid':
      return _tr(
        nl: 'QR betaling bevestigd',
        en: 'QR payment confirmed',
        fr: 'Paiement QR confirme',
        es: 'Pago QR confirmado',
      );
    case 'paymentStatus':
      return _tr(
        nl: 'Betaalstatus',
        en: 'Payment status',
        fr: 'Statut du paiement',
        es: 'Estado del pago',
      );
    case 'rideStatus':
      return _tr(
        nl: 'Ritstatus',
        en: 'Ride status',
        fr: 'Statut de la course',
        es: 'Estado del viaje',
      );
    case 'paid':
      return _tr(nl: 'Betaald', en: 'Paid', fr: 'Payé', es: 'Pagado');
    case 'unpaid':
      return _tr(
        nl: 'Onbetaald',
        en: 'Unpaid',
        fr: 'Non payé',
        es: 'No pagado',
      );
    case 'paymentSent':
      return _tr(
        nl: 'Betaalverzoek verstuurd',
        en: 'Payment request sent',
        fr: 'Demande de paiement envoyée',
        es: 'Solicitud de pago enviada',
      );
    case 'paymentMarkedPaid':
      return _tr(
        nl: 'Betaling als betaald opgeslagen.',
        en: 'Payment saved as paid.',
        fr: 'Paiement enregistre comme paye.',
        es: 'Pago guardado como pagado.',
      );
    case 'paymentMarkFailed':
      return _tr(
        nl: 'Kon betaling niet opslaan. Probeer opnieuw.',
        en: 'Could not save payment. Please retry.',
        fr: 'Impossible denregistrer le paiement. Reessayez.',
        es: 'No se pudo guardar el pago. Intentalo de nuevo.',
      );
    case 'bookingIdMissing':
      return _tr(
        nl: 'Boekings-ID ontbreekt.',
        en: 'Booking ID is missing.',
        fr: 'ID de reservation manquant.',
        es: 'Falta el ID de reserva.',
      );
    case 'demoPayment':
      return _tr(
        nl: 'Markeer betaald (demo)',
        en: 'Mark paid (demo)',
        fr: 'Marquer comme payé (demo)',
        es: 'Marcar pagado (demo)',
      );
    case 'qrPayment':
      return _tr(
        nl: 'QR betaling',
        en: 'QR payment',
        fr: 'Paiement QR',
        es: 'Pago QR',
      );
    case 'showPaymentLink':
      return _tr(
        nl: 'Toon betaallink',
        en: 'Show payment link',
        fr: 'Voir le lien de paiement',
        es: 'Mostrar enlace de pago',
      );
    case 'showQrPayment':
      return _tr(
        nl: 'Toon QR betaling',
        en: 'Show QR payment',
        fr: 'Voir le QR de paiement',
        es: 'Mostrar pago QR',
      );
    case 'copyPaymentLink':
      return _tr(
        nl: 'Kopieer betaallink',
        en: 'Copy payment link',
        fr: 'Copier le lien de paiement',
        es: 'Copiar enlace de pago',
      );
    case 'sharePaymentRequest':
      return _tr(
        nl: 'Deel betaalverzoek',
        en: 'Share payment request',
        fr: 'Partager la demande de paiement',
        es: 'Compartir solicitud de pago',
      );
    case 'paymentPlaceholder':
      return _tr(
        nl: 'MVP: deze link is een interne demolink en verwerkt nog geen echte betalingen.',
        en: 'MVP: this is an internal demo link and does not process real payments yet.',
        fr: 'MVP : ce lien est un lien interne de démonstration et ne traite pas encore de paiements réels.',
        es: 'MVP: este enlace es un enlace interno de demostración y aún no procesa pagos reales.',
      );
    case 'driver':
      return _tr(
        nl: 'Chauffeur',
        en: 'Driver',
        fr: 'Chauffeur',
        es: 'Conductor',
      );
    case 'vehicle':
      return _tr(nl: 'Voertuig', en: 'Vehicle', fr: 'Véhicule', es: 'Vehículo');
    case 'licensePlate':
      return _tr(
        nl: 'Nummerplaat',
        en: 'License plate',
        fr: "Plaque d'immatriculation",
        es: 'Matricula',
      );
    case 'status':
      return _tr(nl: 'Status', en: 'Status', fr: 'Statut', es: 'Estado');
    case 'notAvailable':
      return _tr(
        nl: 'Niet beschikbaar',
        en: 'Not available',
        fr: 'Non disponible',
        es: 'No disponible',
      );
    case 'unknown':
      return _tr(
        nl: 'Onbekend',
        en: 'Unknown',
        fr: 'Inconnu',
        es: 'Desconocido',
      );
    case 'close':
      return _tr(nl: 'Sluiten', en: 'Close', fr: 'Fermer', es: 'Cerrar');
    case 'copy':
      return _tr(nl: 'Kopieer', en: 'Copy', fr: 'Copier', es: 'Copiar');
    case 'copyLink':
      return _tr(
        nl: 'Kopieer link',
        en: 'Copy link',
        fr: 'Copier le lien',
        es: 'Copiar enlace',
      );
    case 'share':
      return _tr(nl: 'Delen', en: 'Share', fr: 'Partager', es: 'Compartir');
    case 'shareReceipt':
      return _tr(
        nl: 'Deel bon',
        en: 'Share receipt',
        fr: 'Partager le reçu',
        es: 'Compartir recibo',
      );
    case 'send':
      return _tr(nl: 'Verstuur', en: 'Send', fr: 'Envoyer', es: 'Enviar');
    case 'emailReceipt':
      return _tr(
        nl: 'Mail bon',
        en: 'Email receipt',
        fr: 'Envoyer le reçu',
        es: 'Enviar recibo',
      );
    case 'printReceipt':
      return _tr(
        nl: 'Print bon',
        en: 'Print receipt',
        fr: 'Imprimer le reçu',
        es: 'Imprimir recibo',
      );
    case 'viewPdf':
      return _tr(
        nl: 'Bekijk PDF',
        en: 'View PDF',
        fr: 'Voir PDF',
        es: 'Ver PDF',
      );
    case 'sharePdf':
      return _tr(
        nl: 'Deel PDF',
        en: 'Share PDF',
        fr: 'Partager PDF',
        es: 'Compartir PDF',
      );
    case 'emailPdf':
      return _tr(
        nl: 'Stuur PDF via e-mail',
        en: 'Send PDF by email',
        fr: 'Envoyer PDF par e-mail',
        es: 'Enviar PDF por correo',
      );
    case 'whatsappPdf':
      return _tr(
        nl: 'Stuur PDF via WhatsApp',
        en: 'Send PDF via WhatsApp',
        fr: 'Envoyer PDF via WhatsApp',
        es: 'Enviar PDF por WhatsApp',
      );
    case 'pdfReady':
      return _tr(
        nl: 'PDF klaar om te delen.',
        en: 'PDF is ready to share.',
        fr: 'PDF prêt à partager.',
        es: 'PDF listo para compartir.',
      );
    case 'pdfGenerationFailed':
      return _tr(
        nl: 'PDF maken mislukt, we gebruiken de tekstversie.',
        en: 'PDF generation failed, using text fallback.',
        fr: 'Échec de génération PDF, utilisation de la version texte.',
        es: 'Falló la generación del PDF, usando versión de texto.',
      );
    case 'paymentReceiptLabel':
      return _tr(
        nl: 'Betaalbewijs / Ritbon',
        en: 'Payment receipt / Ride receipt',
        fr: 'Justificatif de paiement / Reçu de course',
        es: 'Comprobante de pago / Recibo de viaje',
      );
    case 'invoiceLabel':
      return _tr(nl: 'Factuur', en: 'Invoice', fr: 'Facture', es: 'Factura');
    case 'subtotalExVat':
      return _tr(
        nl: 'Subtotaal excl. btw',
        en: 'Subtotal excl. VAT',
        fr: 'Sous-total HT',
        es: 'Subtotal sin IVA',
      );
    case 'vatAmount':
      return _tr(
        nl: 'BTW-bedrag',
        en: 'VAT amount',
        fr: 'Montant TVA',
        es: 'Importe IVA',
      );
    case 'vatRate':
      return _tr(
        nl: 'BTW-tarief',
        en: 'VAT rate',
        fr: 'Taux TVA',
        es: 'Tasa IVA',
      );
    case 'paymentMethod':
      return _tr(
        nl: 'Betaalmethode',
        en: 'Payment method',
        fr: 'Méthode de paiement',
        es: 'Método de pago',
      );
    case 'paymentSource':
      return _tr(
        nl: 'Betalingsbron',
        en: 'Payment source',
        fr: 'Source du paiement',
        es: 'Origen del pago',
      );
    case 'company':
      return _tr(nl: 'Bedrijf', en: 'Company', fr: 'Entreprise', es: 'Empresa');
    case 'legalName':
      return _tr(
        nl: 'Juridische naam',
        en: 'Legal name',
        fr: 'Raison sociale',
        es: 'Razón social',
      );
    case 'companyAddress':
      return _tr(nl: 'Adres', en: 'Address', fr: 'Adresse', es: 'Dirección');
    case 'companyVat':
      return _tr(
        nl: 'BTW-nummer',
        en: 'VAT number',
        fr: 'Numéro TVA',
        es: 'NIF/IVA',
      );
    case 'companyPhone':
      return _tr(
        nl: 'Telefoon',
        en: 'Company phone',
        fr: 'Téléphone entreprise',
        es: 'Teléfono de empresa',
      );
    case 'companyEmail':
      return _tr(
        nl: 'E-mail',
        en: 'Company email',
        fr: 'E-mail entreprise',
        es: 'Email de empresa',
      );
    case 'companyWebsite':
      return _tr(nl: 'Website', en: 'Website', fr: 'Site web', es: 'Sitio web');
    case 'printLater':
      return _tr(
        nl: 'Printfunctie wordt later gekoppeld aan printer.',
        en: 'Printing will be connected to a printer later.',
        fr: 'L’impression sera connectée à une imprimante ultérieurement.',
        es: 'La impresión se conectará a una impresora más adelante.',
      );
    case 'whatsappReceipt':
      return _tr(
        nl: 'Stuur bon via WhatsApp',
        en: 'Send receipt via WhatsApp',
        fr: 'Envoyer le reçu via WhatsApp',
        es: 'Enviar recibo por WhatsApp',
      );
    case 'emailReceiptToCustomer':
      return _tr(
        nl: 'Mail bon naar klant',
        en: 'Email receipt to customer',
        fr: 'Envoyer le reçu au client',
        es: 'Enviar recibo al cliente',
      );
    case 'whatsappPaymentRequest':
      return _tr(
        nl: 'Stuur betaallink via WhatsApp',
        en: 'Send payment link via WhatsApp',
        fr: 'Envoyer le lien de paiement via WhatsApp',
        es: 'Enviar enlace de pago por WhatsApp',
      );
    case 'emailPaymentRequest':
      return _tr(
        nl: 'Mail betaallink naar klant',
        en: 'Email payment link to customer',
        fr: 'Envoyer le lien de paiement au client',
        es: 'Enviar enlace de pago al cliente',
      );
    case 'noCustomerContact':
      return _tr(
        nl: 'Geen klantcontactgegevens beschikbaar voor gerichte verzending.',
        en: 'No customer contact details available for targeted sending.',
        fr: 'Aucune coordonnée client disponible pour un envoi ciblé.',
        es: 'No hay datos de contacto del cliente disponibles para el envío directo.',
      );
    case 'phoneNeedsCountryCode':
      return _tr(
        nl: 'Gebruik een telefoonnummer met landcode, bijvoorbeeld +32.',
        en: 'Use a phone number with country code, for example +32.',
        fr: 'Utilisez un numéro avec indicatif pays, par exemple +32.',
        es: 'Usa un número con prefijo internacional, por ejemplo +32.',
      );
    case 'noValidWhatsappPhone':
      return _tr(
        nl: 'Geen klanttelefoonnummer gevonden.',
        en: 'No customer phone number found.',
        fr: 'Aucun numéro de téléphone client trouvé.',
        es: 'No se encontró ningún teléfono del cliente.',
      );
    case 'whatsappOpenFailed':
      return _tr(
        nl: 'WhatsApp kon niet worden geopend.',
        en: 'Could not open WhatsApp.',
        fr: 'Impossible d’ouvrir WhatsApp.',
        es: 'No se pudo abrir WhatsApp.',
      );
    case 'emailOpenFailed':
      return _tr(
        nl: 'E-mailapp kon niet worden geopend.',
        en: 'Could not open email app.',
        fr: 'Impossible d’ouvrir l’application e-mail.',
        es: 'No se pudo abrir la app de correo.',
      );
    case 'receiptEmailSubject':
      return _tr(
        nl: 'Uw ritbon',
        en: 'Your ride receipt',
        fr: 'Votre reçu de course',
        es: 'Su recibo de viaje',
      );
    case 'paymentEmailSubject':
      return _tr(
        nl: 'Betaalverzoek / demolink',
        en: 'Payment request / demo link',
        fr: 'Demande de paiement / lien de démonstration',
        es: 'Solicitud de pago / enlace de demostración',
      );
    case 'paymentRequestDemoTitle':
      return _tr(
        nl: 'Betaalverzoek / demolink',
        en: 'Payment request / demo link',
        fr: 'Demande de paiement / lien de démonstration',
        es: 'Solicitud de pago / enlace de demostración',
      );
    case 'reference':
      return _tr(
        nl: 'Referentie',
        en: 'Reference',
        fr: 'Référence',
        es: 'Referencia',
      );
    case 'ride':
      return _tr(nl: 'Rit', en: 'Ride', fr: 'Course', es: 'Viaje');
    case 'thanksRide':
      return _tr(
        nl: 'Bedankt voor uw rit.',
        en: 'Thank you for your ride.',
        fr: 'Merci pour votre course.',
        es: 'Gracias por su viaje.',
      );
    case 'pdfFooterDefault':
      return _tr(
        nl: 'Bedankt voor uw vertrouwen in Fluxidi.',
        en: 'Thank you for choosing Fluxidi.',
        fr: 'Merci pour votre confiance en Fluxidi.',
        es: 'Gracias por confiar en Fluxidi.',
      );
    case 'currentLocation':
      return _tr(
        nl: 'Huidige locatie',
        en: 'Current location',
        fr: 'Position actuelle',
        es: 'Ubicación actual',
      );
    case 'receiptFrom':
      return _tr(
        nl: 'Bon van',
        en: 'Receipt from',
        fr: 'Reçu de',
        es: 'Recibo de',
      );
    case 'paymentRequestFrom':
      return _tr(
        nl: 'Betaalverzoek van',
        en: 'Payment request from',
        fr: 'Demande de paiement de',
        es: 'Solicitud de pago de',
      );
    case 'downloadSave':
      return _tr(
        nl: 'Download / opslaan',
        en: 'Download / save',
        fr: 'Télécharger / enregistrer',
        es: 'Descargar / guardar',
      );
    case 'comingSoon':
      return _tr(
        nl: 'komt later.',
        en: 'coming later.',
        fr: 'arrive plus tard.',
        es: 'llegara mas tarde.',
      );
    case 'paymentLink':
      return _tr(
        nl: 'Betaallink',
        en: 'Payment link',
        fr: 'Lien de paiement',
        es: 'Enlace de pago',
      );
    case 'paymentLinkCopied':
      return _tr(
        nl: 'Betaallink gekopieerd.',
        en: 'Payment link copied.',
        fr: 'Lien de paiement copié.',
        es: 'Enlace de pago copiado.',
      );
    case 'paymentRequestCopied':
      return _tr(
        nl: 'Betaalverzoek gekopieerd om te delen.',
        en: 'Payment request copied for sharing.',
        fr: 'Demande de paiement copiée pour partage.',
        es: 'Solicitud de pago copiada para compartir.',
      );
    case 'receiptCopied':
      return _tr(
        nl: 'Bontekst gekopieerd om te delen.',
        en: 'Receipt text copied for sharing.',
        fr: 'Texte du reçu copié pour partage.',
        es: 'Texto del recibo copiado para compartir.',
      );
  }
  return key;
}

String _localizedRideKind(String kind) {
  return kind.toLowerCase().trim() == 'planned'
      ? _receiptText('plannedRide')
      : _receiptText('streetRide');
}

String _localizedRideSubtype(String? raw) {
  final value = (raw ?? '').toLowerCase().trim();
  if (value == 'retourrit' || value == 'return ride' || value == 'return') {
    return _receiptText('returnRide');
  }
  if (value == 'heenrit' || value == 'outbound ride' || value == 'outbound') {
    return _receiptText('outboundRide');
  }
  return raw?.trim().isNotEmpty == true ? raw!.trim() : _receiptText('unknown');
}

String _localizedRideStatus(String? raw) {
  final value = (raw ?? '').toLowerCase().trim();
  switch (value) {
    case 'stopped':
    case 'completed':
    case 'complete':
    case 'done':
      return _tr(
        nl: 'Afgerond',
        en: 'Completed',
        fr: 'Terminée',
        es: 'Finalizada',
      );
    case 'active':
    case 'running':
      return _tr(nl: 'Actief', en: 'Active', fr: 'Active', es: 'Activa');
    case 'waiting':
    case 'wait':
      return _tr(
        nl: 'Wachten',
        en: 'Waiting',
        fr: 'En attente',
        es: 'En espera',
      );
    case 'cancelled':
    case 'canceled':
      return _tr(
        nl: 'Geannuleerd',
        en: 'Cancelled',
        fr: 'Annulée',
        es: 'Cancelada',
      );
  }
  return raw?.trim().isNotEmpty == true ? raw!.trim() : _receiptText('unknown');
}

class FluxidiDriverApp extends StatelessWidget {
  const FluxidiDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ Less dark / better contrast
    final theme = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: kFluxidiBlack,
      colorScheme: ColorScheme.dark(
        primary: kFluxidiYellow,
        secondary: kFluxidiYellow,
        surface: kFluxidiPanel,
        error: const Color(0xFFED6A5A),
        onPrimary: Colors.black,
        onSecondary: Colors.black,
      ),
      textTheme: Typography.whiteMountainView.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: kFluxidiYellow,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: kFluxidiYellow, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );

    return ValueListenableBuilder(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: kAppTitle,
        theme: theme,
        builder: (context, child) {
          return FluxidiFrame(child: child ?? const SizedBox.shrink());
        },
        home: const RoleEntryPage(),
      ),
    );
  }
}

class RoleEntryPage extends StatelessWidget {
  const RoleEntryPage({super.key});

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  Widget _roleButton({
    required String label,
    required VoidCallback onTap,
    required IconData icon,
    required double height,
  }) {
    return SizedBox(
      height: height,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          elevation: 2,
          shadowColor: const Color(0xFFE5B641).withOpacity(0.35),
          backgroundColor: const Color(0xFFE5B641),
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 10),
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  Widget _languageChip({
    required String code,
    required String flag,
    required String label,
    required bool selected,
  }) {
    return SizedBox(
      height: 42,
      child: Material(
        color: selected ? const Color(0xFFE5B641) : const Color(0xFF101625),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setAppLanguageByCode(code),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$flag $label',
                  style: TextStyle(
                    color: selected ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.check, size: 16, color: Colors.black),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _goCustomer(BuildContext context) async {
    setAppRole(AppRole.customer);
    final existingProfile = await CustomerProfileStore.instance.load();
    if (!context.mounted) return;
    if (existingProfile != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CustomerHomePage()),
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CustomerOnboardingPage()),
    );
  }

  Future<void> _goBusiness(BuildContext context) async {
    await CompanySessionStore.instance.bootstrap();
    if (!context.mounted) return;
    if (CompanySessionStore.instance.hasValidCompanyContext) {
      setAppRole(AppRole.companyAdmin);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const BusinessHomePage()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => CompanyOnboardingPage(
            onCompleted: (ctx) {
              setAppRole(AppRole.companyAdmin);
              Navigator.of(ctx).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => const BusinessHomePage(),
                ),
              );
            },
          ),
        ),
      );
    }
  }

  Future<void> _goDriver(BuildContext context) async {
    await DriverSessionStore.instance.bootstrap(driversNotifier.value);
    if (!context.mounted) return;
    if (activeDriverSessionNotifier.value != null) {
      setAppRole(AppRole.driver);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DriverHomePage()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ChauffeurLoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: kFluxidiBlack,
        body: SafeArea(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.65),
                radius: 1.15,
                colors: [
                  const Color(0xFF1A1F31).withOpacity(0.65),
                  const Color(0xFF070A10),
                ],
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 780;
                final veryCompact = constraints.maxHeight < 720;

                final logoHeight = veryCompact
                    ? 160.0
                    : (compact ? 188.0 : 228.0);
                final buttonHeight = veryCompact
                    ? 62.0
                    : (compact ? 66.0 : 72.0);
                final buttonGap = veryCompact ? 10.0 : (compact ? 12.0 : 16.0);
                final verticalPadding = veryCompact
                    ? 16.0
                    : (compact ? 20.0 : 28.0);
                final titleTopGap = veryCompact
                    ? 12.0
                    : (compact ? 16.0 : 20.0);
                final sectionGap = veryCompact ? 12.0 : (compact ? 14.0 : 18.0);
                final estimatedContentHeight =
                    logoHeight +
                    6 +
                    92 +
                    titleTopGap +
                    34 +
                    6 +
                    20 +
                    sectionGap +
                    (buttonHeight * 3) +
                    (buttonGap * 2);
                final topOffset = math.max(
                  0.0,
                  (constraints.maxHeight - estimatedContentHeight) / 2,
                );

                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: verticalPadding,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(height: topOffset),
                              Image.asset(
                                kFluxidiLogoAsset,
                                height: logoHeight,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Text(
                                  'FLUXIDI',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 38,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                              SizedBox(height: veryCompact ? 4 : 6),
                              Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _languageChip(
                                          code: 'en',
                                          flag: '🇬🇧',
                                          label: 'EN',
                                          selected: currentLanguageCode == 'en',
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _languageChip(
                                          code: 'nl',
                                          flag: '🇳🇱',
                                          label: 'NL',
                                          selected: currentLanguageCode == 'nl',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _languageChip(
                                          code: 'fr',
                                          flag: '🇫🇷',
                                          label: 'FR',
                                          selected: currentLanguageCode == 'fr',
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _languageChip(
                                          code: 'es',
                                          flag: '🇪🇸',
                                          label: 'ES',
                                          selected: currentLanguageCode == 'es',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              SizedBox(height: titleTopGap),
                              Text(
                                _t(
                                  nl: 'Wie ben je?',
                                  en: 'Who are you?',
                                  fr: 'Qui êtes-vous ?',
                                  es: '¿Quién eres?',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _t(
                                  nl: 'Kies hoe je Fluxidi wilt gebruiken.',
                                  en: 'Choose how you want to use Fluxidi.',
                                  fr: 'Choisissez comment vous souhaitez utiliser Fluxidi.',
                                  es: 'Elige cómo quieres usar Fluxidi.',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.82),
                                  letterSpacing: 0.2,
                                ),
                              ),
                              SizedBox(height: sectionGap),
                              _roleButton(
                                label: _t(
                                  nl: 'Klant',
                                  en: 'Customer',
                                  fr: 'Client',
                                  es: 'Cliente',
                                ),
                                icon: Icons.person_outline_rounded,
                                height: buttonHeight,
                                onTap: () => _goCustomer(context),
                              ),
                              SizedBox(height: buttonGap),
                              _roleButton(
                                label: _t(
                                  nl: 'Zelfstandige / Bedrijf',
                                  en: 'Self-employed / Business',
                                  fr: 'Independant / Entreprise',
                                  es: 'Autonomo / Empresa',
                                ),
                                icon: Icons.business_center_rounded,
                                height: buttonHeight,
                                onTap: () => unawaited(_goBusiness(context)),
                              ),
                              SizedBox(height: buttonGap),
                              _roleButton(
                                label: _t(
                                  nl: 'Chauffeur',
                                  en: 'Driver',
                                  fr: 'Chauffeur',
                                  es: 'Conductor',
                                ),
                                icon: Icons.local_taxi_rounded,
                                height: buttonHeight,
                                onTap: () => _goDriver(context),
                              ),
                              SizedBox(height: verticalPadding),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class ChauffeurLoginPage extends StatefulWidget {
  const ChauffeurLoginPage({super.key});

  @override
  State<ChauffeurLoginPage> createState() => _ChauffeurLoginPageState();
}

class _ChauffeurLoginPageState extends State<ChauffeurLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _idCtrl = TextEditingController();
  bool _busy = false;
  String? _lookupError;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void initState() {
    super.initState();
    _idCtrl.addListener(() {
      if (_lookupError != null) setState(() => _lookupError = null);
    });
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _lookupError = null);
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final drivers = driversNotifier.value;
    final match = DriverSessionStore.instance.findDriverByEnteredId(
      drivers,
      _idCtrl.text,
    );
    if (match == null) {
      debugPrint('[DRIVER_LOGIN][FAIL] reason=not_found');
      if (mounted) {
        setState(() {
          _busy = false;
          _lookupError = _t(
            nl: 'Geen actieve chauffeur gevonden met deze ID.',
            en: 'No active driver found with this ID.',
            fr: 'Aucun chauffeur actif trouvé avec cet ID.',
            es: 'No se encontró ningún conductor activo con este ID.',
          );
        });
      }
      return;
    }
    final prev = await DriverSessionStore.instance.load();
    await DriverSessionStore.instance.saveFromDriverProfile(
      match,
      previous: prev,
    );
    DriverSessionStore.instance.logOk(match.id);
    if (!mounted) return;
    setState(() => _busy = false);
    setAppRole(AppRole.driver);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DriverHomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: kFluxidiBlack,
        appBar: AppBar(
          backgroundColor: kFluxidiBlack,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _busy
                ? null
                : () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const RoleEntryPage()),
                    );
                  },
          ),
          title: Text(
            _t(
              nl: 'Chauffeur login',
              en: 'Driver login',
              fr: 'Connexion chauffeur',
              es: 'Acceso conductor',
            ),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121A2E),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFE5B641).withOpacity(0.3),
                    ),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _t(
                            nl: 'Vul je chauffeur-ID in om je ritten te openen.',
                            en: 'Enter your driver ID to open your rides.',
                            fr: 'Saisissez votre ID chauffeur pour ouvrir vos courses.',
                            es: 'Introduce tu ID de conductor para abrir tus viajes.',
                          ),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _idCtrl,
                          enabled: !_busy,
                          style: const TextStyle(color: Colors.white),
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (!_busy) unawaited(_submit());
                          },
                          decoration: InputDecoration(
                            labelText: _t(
                              nl: 'Chauffeur-ID',
                              en: 'Driver ID',
                              fr: 'ID chauffeur',
                              es: 'ID de conductor',
                            ),
                            labelStyle: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                            ),
                            filled: true,
                            fillColor: const Color(0xFF141B2F),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                          ),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) {
                              return _t(
                                nl: 'Vul je chauffeur-ID in.',
                                en: 'Enter your driver ID.',
                                fr: 'Saisissez votre ID chauffeur.',
                                es: 'Introduce tu ID de conductor.',
                              );
                            }
                            return null;
                          },
                        ),
                        if (_lookupError != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _lookupError!,
                            style: const TextStyle(
                              color: Color(0xFFFF8A8A),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  unawaited(_submit());
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE5B641),
                            foregroundColor: Colors.black,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black54,
                                  ),
                                )
                              : Text(
                                  _t(
                                    nl: 'Inloggen',
                                    en: 'Log in',
                                    fr: 'Se connecter',
                                    es: 'Iniciar sesión',
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CustomerOnboardingPage extends StatefulWidget {
  const CustomerOnboardingPage({super.key});

  @override
  State<CustomerOnboardingPage> createState() => _CustomerOnboardingPageState();
}

class _CustomerOnboardingPageState extends State<CustomerOnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _companyNameCtrl = TextEditingController();
  final _vatNumberCtrl = TextEditingController();
  bool _saving = false;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _companyNameCtrl.dispose();
    _vatNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _goToCustomerHome() async {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CustomerHomePage()),
    );
  }

  Future<void> _saveAndContinue() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await CustomerProfileStore.instance.save(
      name: _nameCtrl.text,
      phone: _phoneCtrl.text,
      email: _emailCtrl.text,
      companyName: _companyNameCtrl.text,
      vatNumber: _vatNumberCtrl.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    await _goToCustomerHome();
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF141B2F),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: kFluxidiBlack,
        appBar: AppBar(
          backgroundColor: kFluxidiBlack,
          elevation: 0,
          title: const Text('FLUXIDI'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121A2E),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFE5B641).withOpacity(0.3),
                    ),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _t(
                            nl: 'Maak je ritten makkelijker',
                            en: 'Make your rides easier',
                            fr: 'Simplifiez vos trajets',
                            es: 'Haz tus viajes más fáciles',
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _t(
                            nl: 'Vul één keer je gegevens in. Dan hoef je ze bij je volgende boeking niet opnieuw te typen.',
                            en: 'Enter your details once, so you do not have to type them again for your next booking.',
                            fr: 'Saisissez vos informations une seule fois pour ne plus devoir les retaper lors de votre prochaine réservation.',
                            es: 'Introduce tus datos una vez para no tener que escribirlos de nuevo en tu próxima reserva.',
                          ),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.82),
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _field(
                          label: _t(
                            nl: 'Naam',
                            en: 'Name',
                            fr: 'Nom',
                            es: 'Nombre',
                          ),
                          controller: _nameCtrl,
                          validator: (v) {
                            final text = (v ?? '').trim();
                            if (text.isEmpty) {
                              return _t(
                                nl: 'Vul je naam in',
                                en: 'Enter your name',
                                fr: 'Saisissez votre nom',
                                es: 'Introduce tu nombre',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _field(
                          label: _t(
                            nl: 'Telefoonnummer',
                            en: 'Phone number',
                            fr: 'Numéro de téléphone',
                            es: 'Número de teléfono',
                          ),
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          validator: (v) {
                            final text = (v ?? '').trim();
                            if (text.isEmpty) {
                              return _t(
                                nl: 'Vul je telefoonnummer in',
                                en: 'Enter your phone number',
                                fr: 'Saisissez votre numéro de téléphone',
                                es: 'Introduce tu número de teléfono',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _field(
                          label: _t(
                            nl: 'E-mailadres',
                            en: 'Email address',
                            fr: 'Adresse e-mail',
                            es: 'Correo electrónico',
                          ),
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            final text = (v ?? '').trim();
                            if (text.isEmpty) {
                              return _t(
                                nl: 'Vul je e-mail in',
                                en: 'Enter your email',
                                fr: 'Saisissez votre e-mail',
                                es: 'Introduce tu correo',
                              );
                            }
                            if (!text.contains('@') || !text.contains('.')) {
                              return _t(
                                nl: 'Vul een geldig e-mailadres in',
                                en: 'Enter a valid email address',
                                fr: 'Saisissez une adresse e-mail valide',
                                es: 'Introduce un correo electrónico válido',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _field(
                          label: _t(
                            nl: 'Bedrijfsnaam (optioneel)',
                            en: 'Company name (optional)',
                            fr: 'Nom de l’entreprise (facultatif)',
                            es: 'Nombre de la empresa (opcional)',
                          ),
                          controller: _companyNameCtrl,
                        ),
                        const SizedBox(height: 12),
                        _field(
                          label: _t(
                            nl: 'BTW-nummer (optioneel)',
                            en: 'VAT number (optional)',
                            fr: 'Numéro de TVA (facultatif)',
                            es: 'Número de IVA (opcional)',
                          ),
                          controller: _vatNumberCtrl,
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _saving ? null : _saveAndContinue,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE5B641),
                            foregroundColor: Colors.black,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _saving
                                ? _t(
                                    nl: 'Opslaan...',
                                    en: 'Saving...',
                                    fr: 'Enregistrement...',
                                    es: 'Guardando...',
                                  )
                                : _t(
                                    nl: 'Opslaan en doorgaan',
                                    en: 'Save and continue',
                                    fr: 'Enregistrer et continuer',
                                    es: 'Guardar y continuar',
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: _saving ? null : _goToCustomerHome,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFE5B641),
                            side: const BorderSide(
                              color: Color(0xFFE5B641),
                              width: 1.2,
                            ),
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _t(
                              nl: 'Later invullen',
                              en: 'Fill in later',
                              fr: 'Compléter plus tard',
                              es: 'Completar más tarde',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CustomerProfileEditPage extends StatefulWidget {
  const CustomerProfileEditPage({super.key});

  @override
  State<CustomerProfileEditPage> createState() =>
      _CustomerProfileEditPageState();
}

class _CustomerProfileEditPageState extends State<CustomerProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _companyNameCtrl = TextEditingController();
  final _vatNumberCtrl = TextEditingController();
  bool _saving = false;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfile());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _companyNameCtrl.dispose();
    _vatNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await CustomerProfileStore.instance.load();
    if (!mounted || profile == null) return;
    _nameCtrl.text = profile.name;
    _phoneCtrl.text = profile.phone;
    _emailCtrl.text = profile.email;
    _companyNameCtrl.text = profile.companyName;
    _vatNumberCtrl.text = profile.vatNumber;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await CustomerProfileStore.instance.save(
      name: _nameCtrl.text,
      phone: _phoneCtrl.text,
      email: _emailCtrl.text,
      companyName: _companyNameCtrl.text,
      vatNumber: _vatNumberCtrl.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Gegevens opgeslagen.',
            en: 'Details saved.',
            fr: 'Informations enregistrées.',
            es: 'Datos guardados.',
          ),
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF141B2F),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: kFluxidiBlack,
        appBar: AppBar(
          backgroundColor: kFluxidiBlack,
          elevation: 0,
          title: Text(
            _t(
              nl: 'Mijn gegevens',
              en: 'My details',
              fr: 'Mes informations',
              es: 'Mis datos',
            ),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121A2E),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFE5B641).withOpacity(0.3),
                    ),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _t(
                            nl: 'Beheer je gegevens voor snelle boekingen en facturatie.',
                            en: 'Manage your details for faster bookings and billing.',
                            fr: 'Gérez vos informations pour des réservations et une facturation plus rapides.',
                            es: 'Gestiona tus datos para reservas y facturación más rápidas.',
                          ),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.82),
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _field(
                          label: _t(
                            nl: 'Naam',
                            en: 'Name',
                            fr: 'Nom',
                            es: 'Nombre',
                          ),
                          controller: _nameCtrl,
                          validator: (v) {
                            final text = (v ?? '').trim();
                            if (text.isEmpty) {
                              return _t(
                                nl: 'Vul je naam in',
                                en: 'Enter your name',
                                fr: 'Saisissez votre nom',
                                es: 'Introduce tu nombre',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _field(
                          label: _t(
                            nl: 'Telefoonnummer',
                            en: 'Phone number',
                            fr: 'Numéro de téléphone',
                            es: 'Número de teléfono',
                          ),
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          validator: (v) {
                            final text = (v ?? '').trim();
                            if (text.isEmpty) {
                              return _t(
                                nl: 'Vul je telefoonnummer in',
                                en: 'Enter your phone number',
                                fr: 'Saisissez votre numéro de téléphone',
                                es: 'Introduce tu número de teléfono',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _field(
                          label: _t(
                            nl: 'E-mailadres',
                            en: 'Email address',
                            fr: 'Adresse e-mail',
                            es: 'Correo electrónico',
                          ),
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            final text = (v ?? '').trim();
                            if (text.isEmpty) {
                              return _t(
                                nl: 'Vul je e-mail in',
                                en: 'Enter your email',
                                fr: 'Saisissez votre e-mail',
                                es: 'Introduce tu correo',
                              );
                            }
                            if (!text.contains('@') || !text.contains('.')) {
                              return _t(
                                nl: 'Vul een geldig e-mailadres in',
                                en: 'Enter a valid email address',
                                fr: 'Saisissez une adresse e-mail valide',
                                es: 'Introduce un correo electrónico válido',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _field(
                          label: _t(
                            nl: 'Bedrijfsnaam (optioneel)',
                            en: 'Company name (optional)',
                            fr: 'Nom de l’entreprise (facultatif)',
                            es: 'Nombre de la empresa (opcional)',
                          ),
                          controller: _companyNameCtrl,
                        ),
                        const SizedBox(height: 12),
                        _field(
                          label: _t(
                            nl: 'BTW-nummer (optioneel)',
                            en: 'VAT number (optional)',
                            fr: 'Numéro de TVA (facultatif)',
                            es: 'Número de IVA (opcional)',
                          ),
                          controller: _vatNumberCtrl,
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE5B641),
                            foregroundColor: Colors.black,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _saving
                                ? _t(
                                    nl: 'Opslaan...',
                                    en: 'Saving...',
                                    fr: 'Enregistrement...',
                                    es: 'Guardando...',
                                  )
                                : _t(
                                    nl: 'Opslaan',
                                    en: 'Save',
                                    fr: 'Enregistrer',
                                    es: 'Guardar',
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BusinessHomePage extends StatelessWidget {
  const BusinessHomePage({super.key});

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1020),
          title: const Text('FLUXIDI'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                _t(
                  nl: 'Bedrijf',
                  en: 'Business',
                  fr: 'Entreprise',
                  es: 'Empresa',
                ),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _t(
                  nl: 'Beheer je bedrijf, voertuigen en boekingen.',
                  en: 'Manage your company, vehicles, and bookings.',
                  fr: 'Gerez votre entreprise, vos vehicules et vos reservations.',
                  es: 'Gestiona tu empresa, vehiculos y reservas.',
                ),
                style: TextStyle(color: Colors.white.withOpacity(0.72)),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<CompanyProfile?>(
                valueListenable: companyProfileNotifier,
                builder: (context, profile, _) {
                  if (profile == null) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        color: const Color(0xFF141B2F),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.companyName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${_t(nl: 'Bedrijfs-ID:', en: 'Company ID:', fr: 'ID entreprise :', es: 'ID de empresa:')} ${profile.companyId}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${_t(nl: 'Contact:', en: 'Contact:', fr: 'Contact :', es: 'Contacto:')} ${profile.email}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(
                                          0xFFE5B641,
                                        ),
                                        side: const BorderSide(
                                          color: Color(0xFFE5B641),
                                        ),
                                      ),
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                const CompanyProfileEditPage(),
                                          ),
                                        );
                                      },
                                      child: Text(
                                        _t(
                                          nl: 'Mijn bedrijfsgegevens',
                                          en: 'Company details',
                                          fr: 'Mes informations entreprise',
                                          es: 'Datos de empresa',
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () async {
                                        await CompanySessionStore.instance
                                            .clearLocalCompanyState();
                                        if (!context.mounted) return;
                                        Navigator.of(
                                          context,
                                        ).pushAndRemoveUntil(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                const RoleEntryPage(),
                                          ),
                                          (route) => false,
                                        );
                                      },
                                      child: Text(
                                        _t(
                                          nl: 'Ander bedrijf',
                                          en: 'Switch company',
                                          fr: 'Changer entreprise',
                                          es: 'Cambiar empresa',
                                        ),
                                        style: TextStyle(
                                          color: Colors.redAccent.shade100,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                },
              ),
              Card(
                color: const Color(0xFF141B2F),
                child: ListTile(
                  leading: const Icon(Icons.calculate_outlined),
                  title: Text(
                    appConfig.strings.calculatorTitle.of(
                      appConfig.currentLanguage,
                    ),
                  ),
                  subtitle: Text(kCalculatorMenuSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CalculatorPage(
                          bookingBaseUrl: kBookingBaseUrl,
                          mapboxToken: kMapboxToken,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Card(
                color: const Color(0xFF141B2F),
                child: ListTile(
                  leading: const Icon(Icons.business_center_outlined),
                  title: Text(kDrawerBusinessSettingsLabel),
                  subtitle: Text(kDrawerBusinessSettingsSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const BusinessSettingsPage(),
                      ),
                    );
                  },
                ),
              ),
              Card(
                color: const Color(0xFF141B2F),
                child: ListTile(
                  leading: const Icon(Icons.directions_car_filled_outlined),
                  title: Text(kDrawerVehiclesLabel),
                  subtitle: Text(kDrawerVehiclesSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const VehicleManagementPage(),
                      ),
                    );
                  },
                ),
              ),
              Card(
                color: const Color(0xFF141B2F),
                child: ListTile(
                  leading: const Icon(Icons.local_taxi_outlined),
                  title: Text(
                    _t(
                      nl: 'Open chauffeurweergave',
                      en: 'Open driver view',
                      fr: 'Ouvrir la vue chauffeur',
                      es: 'Abrir vista de conductor',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final previousRole = appRoleNotifier.value;
                    setAppRole(AppRole.driver);
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DriverHomePage()),
                    );
                    if (context.mounted) {
                      setAppRole(previousRole);
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              const FluxidiBackToStartButton(),
            ],
          ),
        ),
      ),
    );
  }
}

class FluxidiBackToStartButton extends StatelessWidget {
  const FluxidiBackToStartButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const RoleEntryPage()),
            (route) => false,
          );
        },
        icon: const Icon(Icons.home_outlined),
        label: Text(
          _tr(
            nl: 'Terug naar startpagina',
            en: 'Back to start page',
            fr: 'Retour à la page de départ',
            es: 'Volver a la página de inicio',
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFE5B641),
          backgroundColor: const Color(0xFF10182C),
          side: const BorderSide(color: Color(0xFFE5B641), width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        ),
      ),
    );
  }
}

class CustomerHomePage extends StatelessWidget {
  const CustomerHomePage({super.key});

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  void _openCalculator(BuildContext context, {required bool scheduledIntent}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CalculatorPage(
          bookingBaseUrl: kBookingBaseUrl,
          mapboxToken: kMapboxToken,
          onGoToStartPage: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const RoleEntryPage()),
              (route) => false,
            );
          },
        ),
      ),
    );
    if (scheduledIntent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Plan rit opent nu de boekingsflow (scheduled intent volgt).',
              en: 'Scheduled ride currently opens the booking flow (scheduled intent pending).',
              fr: 'La course planifiee ouvre actuellement le flux de reservation (option planifiee a venir).',
              es: 'El viaje programado abre actualmente el flujo de reserva (intencion programada pendiente).',
            ),
          ),
        ),
      );
    }
  }

  void _openPlaceholder(
    BuildContext context,
    String title,
    String description,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xFF0B1020),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0B1020),
            title: Text(title),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.82),
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _entryCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      color: const Color(0xFF141B2F),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Icon(icon, color: const Color(0xFFE5B641)),
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.white.withOpacity(0.74)),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1020),
          title: const Text('FLUXIDI'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                _t(nl: 'Klant', en: 'Customer', fr: 'Client', es: 'Cliente'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _t(
                  nl: 'Kies hoe je jouw rit wil starten.',
                  en: 'Choose how you want to start your ride.',
                  fr: 'Choisissez comment demarrer votre course.',
                  es: 'Elige como quieres iniciar tu viaje.',
                ),
                style: TextStyle(color: Colors.white.withOpacity(0.76)),
              ),
              const SizedBox(height: 14),
              _entryCard(
                context: context,
                icon: Icons.flash_on_outlined,
                title: _t(
                  nl: 'Bereken hier en boek direct',
                  en: 'Calculate and book directly',
                  fr: 'Calculer et reserver directement',
                  es: 'Calcula y reserva directamente',
                ),
                subtitle: _t(
                  nl: 'Bereken je rit en plaats direct je boeking',
                  en: 'Calculate your ride and place your booking right away',
                  fr: 'Calculez votre trajet et effectuez votre reservation immediatement',
                  es: 'Calcula tu viaje y realiza tu reserva de inmediato',
                ),
                onTap: () => _openCalculator(context, scheduledIntent: false),
              ),
              _entryCard(
                context: context,
                icon: Icons.account_circle_outlined,
                title: _t(
                  nl: 'Mijn gegevens',
                  en: 'My details',
                  fr: 'Mes informations',
                  es: 'Mis datos',
                ),
                subtitle: _t(
                  nl: 'Bekijk of wijzig je klant- en facturatiegegevens.',
                  en: 'View or edit your customer and billing details.',
                  fr: 'Consultez ou modifiez vos informations client et de facturation.',
                  es: 'Consulta o modifica tus datos de cliente y facturación.',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CustomerProfileEditPage(),
                  ),
                ),
              ),
              _entryCard(
                context: context,
                icon: Icons.search_outlined,
                title: _t(
                  nl: 'Mijn boekingen',
                  en: 'My bookings',
                  fr: 'Mes reservations',
                  es: 'Mis reservas',
                ),
                subtitle: _t(
                  nl: 'Bekijk automatisch je gemaakte boekingen op dit toestel.',
                  en: 'Automatically view bookings created on this device.',
                  fr: 'Consultez automatiquement les reservations de cet appareil.',
                  es: 'Consulta automaticamente las reservas de este dispositivo.',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CustomerSavedBookingsPage(),
                  ),
                ),
              ),
              _entryCard(
                context: context,
                icon: Icons.local_taxi_outlined,
                title: _t(
                  nl: "Taxi's in de buurt",
                  en: 'Taxis nearby',
                  fr: 'Taxis a proximite',
                  es: 'Taxis cercanos',
                ),
                subtitle: _t(
                  nl: 'Binnenkort zie je hier actieve partners in jouw regio.',
                  en: 'You will soon see active partners in your region here.',
                  fr: 'Vous verrez bientot ici les partenaires actifs de votre region.',
                  es: 'Pronto veras aqui socios activos en tu region.',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NearbyPartnersPage()),
                ),
              ),
              _entryCard(
                context: context,
                icon: Icons.app_registration_outlined,
                title: _t(
                  nl: 'Registreer je regio',
                  en: 'Register your region',
                  fr: 'Enregistrez votre region',
                  es: 'Registra tu region',
                ),
                subtitle: _t(
                  nl: 'Geef je regio door en help taxi bedrijven naar jouw omgeving te brengen',
                  en: 'Register your region for future coverage',
                  fr: 'Enregistrez votre region pour une couverture future',
                  es: 'Registra tu region para cobertura futura',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CustomerRegionRegistrationPage(),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const FluxidiBackToStartButton(),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomerSavedBookingsPage extends StatefulWidget {
  const CustomerSavedBookingsPage({super.key});

  @override
  State<CustomerSavedBookingsPage> createState() =>
      _CustomerSavedBookingsPageState();
}

class _CustomerSavedBookingsPageState extends State<CustomerSavedBookingsPage> {
  bool _loading = true;
  String? _error;
  List<CustomerSavedBooking> _bookings = const <CustomerSavedBooking>[];

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void initState() {
    super.initState();
    unawaited(_loadLocal());
  }

  Future<void> _loadLocal() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await CustomerBookingStore.instance.loadAll();
      if (!mounted) return;
      setState(() {
        _bookings = items;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _t(
          nl: 'Laden mislukt.',
          en: 'Loading failed.',
          fr: 'Chargement echoue.',
          es: 'Error al cargar.',
        );
      });
    }
  }

  String _formatPickup(String iso) {
    if (iso.trim().isEmpty) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    String two(int n) => n.toString().padLeft(2, '0');
    final local = dt.toLocal();
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String _formatPrice(CustomerSavedBooking booking) {
    final amount = booking.price;
    if (amount == null) return '-';
    final currency = booking.currency.toUpperCase().trim();
    final symbol = currency.isEmpty || currency == 'EUR' ? '€' : '$currency ';
    return '$symbol${amount.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _paymentLabel(CustomerSavedBooking booking) {
    final p = booking.paymentStatus.toLowerCase().trim();
    if (p == 'paid' || p == 'confirmed' || p == 'completed' || p == 'success') {
      return _t(nl: 'Betaald', en: 'Paid', fr: 'Paye', es: 'Pagado');
    }
    if (p == 'pending' || p == 'unpaid' || p == 'pay_in_car') {
      return _t(
        nl: 'Te betalen in de wagen',
        en: 'To pay in the vehicle',
        fr: 'A payer dans le vehicule',
        es: 'A pagar en el vehiculo',
      );
    }
    return p.isEmpty ? '-' : p;
  }

  String _bookingStatusLabel(CustomerSavedBooking booking) {
    final status = booking.bookingStatus.toUpperCase().trim();
    if (status == 'PENDING') {
      return _t(
        nl: 'In behandeling',
        en: 'Pending',
        fr: 'En cours',
        es: 'Pendiente',
      );
    }
    if (status == 'CONFIRMED') {
      return _t(
        nl: 'Bevestigd',
        en: 'Confirmed',
        fr: 'Confirmee',
        es: 'Confirmada',
      );
    }
    if (status == 'COMPLETED') {
      return _t(
        nl: 'Voltooid',
        en: 'Completed',
        fr: 'Terminee',
        es: 'Finalizada',
      );
    }
    if (status == 'CANCELLED') {
      return _t(
        nl: 'Geannuleerd',
        en: 'Cancelled',
        fr: 'Annulee',
        es: 'Cancelada',
      );
    }
    return status.isEmpty ? '-' : status;
  }

  Future<void> _openSavedBooking(CustomerSavedBooking booking) async {
    final id = booking.bookingId.trim();
    if (id.isEmpty) return;
    try {
      final uri = Uri.parse(
        '$kBookingBaseUrl/bookings/${Uri.encodeComponent(id)}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, dynamic> && decoded['ok'] == true) {
          final view = CustomerBookingView.fromResponse(id, decoded);
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CustomerBookingDetailPage(
                bookingId: id,
                initialView: view,
                startsFromLocalCache: false,
              ),
            ),
          );
          return;
        }
      }
    } catch (_) {
      // fall back to local-safe minimal view
    }

    final fallback = StoredCustomerBooking(
      bookingId: id,
      publicBookingId: booking.publicReference.trim().isNotEmpty
          ? booking.publicReference.trim()
          : id,
      customerName: '',
      customerPhone: '',
      customerEmail: '',
      from: booking.from,
      to: booking.to,
      pickupIso: booking.pickupIso,
      price: booking.price,
      currency: booking.currency,
      paymentStatus: booking.paymentStatus,
      status: booking.bookingStatus,
      createdAt: booking.createdAt,
      updatedAt: booking.createdAt,
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerBookingDetailPage(
          bookingId: id,
          initialView: CustomerBookingView.fromStored(fallback),
          startsFromLocalCache: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1020),
          title: Text(
            _t(
              nl: 'Mijn boekingen',
              en: 'My bookings',
              fr: 'Mes reservations',
              es: 'Mis reservas',
            ),
          ),
          actions: [
            IconButton(
              tooltip: _t(
                nl: 'Vernieuwen',
                en: 'Refresh',
                fr: 'Actualiser',
                es: 'Actualizar',
              ),
              onPressed: _loadLocal,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.4)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFFFB4B4)),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_bookings.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141B2F),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _t(
                      nl: 'Nog geen boekingen op dit toestel.',
                      en: 'No bookings on this device yet.',
                      fr: 'Aucune réservation sur cet appareil pour le moment.',
                      es: 'Aún no hay reservas en este dispositivo.',
                    ),
                    style: const TextStyle(color: Colors.white70),
                  ),
                )
              else
                ..._bookings.map(
                  (booking) => Card(
                    color: const Color(0xFF141B2F),
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _openSavedBooking(booking),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${booking.from.trim().isEmpty ? '-' : booking.from} → ${booking.to.trim().isEmpty ? '-' : booking.to}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${_t(nl: 'Ophaal', en: 'Pickup', fr: 'Prise en charge', es: 'Recogida')}: ${_formatPickup(booking.pickupIso)}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.82),
                              ),
                            ),
                            Text(
                              '${_t(nl: 'Prijs', en: 'Price', fr: 'Prix', es: 'Precio')}: ${_formatPrice(booking)}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.82),
                              ),
                            ),
                            Text(
                              '${_t(nl: 'Betaalstatus', en: 'Payment status', fr: 'Statut de paiement', es: 'Estado de pago')}: ${_paymentLabel(booking)}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.82),
                              ),
                            ),
                            Text(
                              '${_t(nl: 'Boekingsstatus', en: 'Booking status', fr: 'Statut de réservation', es: 'Estado de la reserva')}: ${_bookingStatusLabel(booking)}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.82),
                              ),
                            ),
                            Text(
                              '${_t(nl: 'Referentie', en: 'Reference', fr: 'Référence', es: 'Referencia')}: ${(booking.publicReference.trim().isNotEmpty ? booking.publicReference.trim() : booking.bookingId.trim())}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.82),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.search_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CustomerBookingLookupPage(),
                    ),
                  ),
                  label: Text(
                    _t(
                      nl: 'Boeking handmatig zoeken',
                      en: 'Find booking manually',
                      fr: 'Rechercher une réservation manuellement',
                      es: 'Buscar reserva manualmente',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomerBookingsPage extends StatefulWidget {
  const CustomerBookingsPage({super.key});

  @override
  State<CustomerBookingsPage> createState() => _CustomerBookingsPageState();
}

class _CustomerBookingsPageState extends State<CustomerBookingsPage> {
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  DateTime? _lastUpdated;
  List<StoredCustomerBooking> _bookings = const <StoredCustomerBooking>[];

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  Future<void> _loadLocal() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await CustomerBookingsStore.instance.loadAll();
      if (!mounted) return;
      setState(() {
        _bookings = items;
        _loading = false;
        _lastUpdated = DateTime.now();
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _t(
          nl: 'Laden mislukt.',
          en: 'Loading failed.',
          fr: 'Chargement echoue.',
          es: 'Error al cargar.',
        );
      });
      debugPrint('[CUSTOMER_BOOKINGS][LOAD_SCREEN_ERROR] $err');
    }
  }

  Future<void> _refreshAuthoritative() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final snapshot = await CustomerBookingsStore.instance.loadAll();
      for (final item in snapshot) {
        final id = item.canonicalBookingId.trim();
        if (id.isEmpty) continue;
        try {
          final uri = Uri.parse(
            '$kBookingBaseUrl/bookings/${Uri.encodeComponent(id)}',
          );
          final res = await http.get(uri).timeout(const Duration(seconds: 12));
          if (res.statusCode != 200) continue;
          final decoded = jsonDecode(utf8.decode(res.bodyBytes));
          if (decoded is! Map<String, dynamic> || decoded['ok'] != true)
            continue;
          final stored = StoredCustomerBooking.fromAuthoritativeResponse(
            bookingId: id,
            response: decoded,
            fallback: item,
          );
          await CustomerBookingsStore.instance.upsert(stored);
        } catch (_) {
          // Keep refresh resilient: skip individual booking failures.
        }
      }
      final refreshed = await CustomerBookingsStore.instance.loadAll();
      if (!mounted) return;
      setState(() {
        _bookings = refreshed;
        _refreshing = false;
        _lastUpdated = DateTime.now();
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _error = _t(
          nl: 'Vernieuwen mislukt.',
          en: 'Refresh failed.',
          fr: "Echec de l'actualisation.",
          es: 'Error al actualizar.',
        );
      });
      debugPrint('[CUSTOMER_BOOKINGS][REFRESH_ERROR] $err');
    }
  }

  String _formatPickup(String iso) {
    if (iso.trim().isEmpty) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String _formatPrice(StoredCustomerBooking booking) {
    final amount = booking.price;
    if (amount == null) return '-';
    final currency = booking.currency.toUpperCase().trim();
    final symbol = currency.isEmpty || currency == 'EUR' ? '€' : '$currency ';
    return '$symbol${amount.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _statusLabel(StoredCustomerBooking booking) {
    final status = booking.status.toUpperCase();
    if (status == 'PENDING') {
      return _t(
        nl: 'In behandeling',
        en: 'Pending',
        fr: 'En cours',
        es: 'Pendiente',
      );
    }
    if (status == 'CONFIRMED') {
      return _t(
        nl: 'Bevestigd',
        en: 'Confirmed',
        fr: 'Confirmee',
        es: 'Confirmada',
      );
    }
    if (status == 'COMPLETED') {
      return _t(
        nl: 'Voltooid',
        en: 'Completed',
        fr: 'Terminee',
        es: 'Finalizada',
      );
    }
    if (status == 'CANCELLED') {
      return _t(
        nl: 'Geannuleerd',
        en: 'Cancelled',
        fr: 'Annulee',
        es: 'Cancelada',
      );
    }
    return status.isEmpty ? '-' : status;
  }

  String _paymentLabel(StoredCustomerBooking booking) {
    final p = booking.paymentStatus.toLowerCase().trim();
    if (p == 'paid' || p == 'confirmed' || p == 'success' || p == 'completed') {
      return _t(nl: 'Betaald', en: 'Paid', fr: 'Paye', es: 'Pagado');
    }
    if (p == 'unpaid' || p == 'pending' || p == 'pay_in_car') {
      return _t(
        nl: 'Te betalen in de wagen',
        en: 'To pay in the vehicle',
        fr: 'A payer dans le vehicule',
        es: 'A pagar en el vehiculo',
      );
    }
    return _t(
      nl: 'Te betalen in de wagen',
      en: 'To pay in the vehicle',
      fr: 'A payer dans le vehicule',
      es: 'A pagar en el vehiculo',
    );
  }

  String _formatLastUpdated() {
    final value = _lastUpdated;
    if (value == null) return '-';
    String two(int n) => n.toString().padLeft(2, '0');
    final local = value.toLocal();
    return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _openDetails(StoredCustomerBooking booking) async {
    final id = booking.canonicalBookingId.trim();
    if (id.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerBookingDetailPage(
          bookingId: id,
          initialView: CustomerBookingView.fromStored(booking),
          startsFromLocalCache: true,
        ),
      ),
    );
    await _loadLocal();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1020),
          title: Text(
            _t(
              nl: 'Mijn boekingen',
              en: 'My bookings',
              fr: 'Mes reservations',
              es: 'Mis reservas',
            ),
          ),
          actions: [
            IconButton(
              tooltip: _t(
                nl: 'Vernieuwen',
                en: 'Refresh',
                fr: 'Actualiser',
                es: 'Actualizar',
              ),
              onPressed: _refreshing ? null : _refreshAuthoritative,
              icon: _refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refreshAuthoritative,
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Text(
                  '${_t(nl: 'Laatst bijgewerkt', en: 'Last updated', fr: 'Derniere mise a jour', es: 'Ultima actualizacion')}: ${_formatLastUpdated()}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.4)),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFFFB4B4)),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_bookings.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141B2F),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _t(
                        nl: 'Geen boekingen gevonden.',
                        en: 'No bookings found.',
                        fr: 'Aucune reservation trouvee.',
                        es: 'No se encontraron reservas.',
                      ),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  )
                else
                  ..._bookings.map(
                    (booking) => Card(
                      color: const Color(0xFF141B2F),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t(
                                nl: 'Route',
                                en: 'Route',
                                fr: 'Itineraire',
                                es: 'Ruta',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_t(nl: 'Ophaaladres', en: 'Pickup', fr: 'Prise en charge', es: 'Recogida')}: ${booking.from.isEmpty ? '-' : booking.from}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.86),
                              ),
                              softWrap: true,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_t(nl: 'Bestemming', en: 'Destination', fr: 'Destination', es: 'Destino')}: ${booking.to.isEmpty ? '-' : booking.to}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.86),
                              ),
                              softWrap: true,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_t(nl: 'Geplande ophaal', en: 'Scheduled pickup', fr: 'Prise en charge prevue', es: 'Recogida programada')}: ${_formatPickup(booking.pickupIso)}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                            Text(
                              '${_t(nl: 'Status', en: 'Status', fr: 'Statut', es: 'Estado')}: ${_statusLabel(booking)}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                            Text(
                              '${_t(nl: 'Betaalstatus', en: 'Payment status', fr: 'Statut de paiement', es: 'Estado de pago')}: ${_paymentLabel(booking)}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_t(nl: 'Prijs', en: 'Price', fr: 'Prix', es: 'Precio')}: ',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    _formatPrice(booking),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton(
                                onPressed: () => _openDetails(booking),
                                child: Text(
                                  _t(
                                    nl: 'Boeking bekijken',
                                    en: 'View booking',
                                    fr: 'Voir la reservation',
                                    es: 'Ver reserva',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.search_outlined),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CustomerBookingLookupPage(),
                        ),
                      );
                      await _loadLocal();
                    },
                    label: Text(
                      _t(
                        nl: 'Andere boeking opzoeken',
                        en: 'Look up another booking',
                        fr: 'Rechercher une autre reservation',
                        es: 'Buscar otra reserva',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Customer-facing booking lookup screen.
///
/// Lets a customer enter a booking reference (and optionally phone/email for
/// validation) and retrieves authoritative booking details via
/// `GET /bookings/{id}`. Read-only — does not touch payment, pricing, booking
/// creation or driver flows.
class CustomerBookingLookupPage extends StatefulWidget {
  const CustomerBookingLookupPage({super.key});

  @override
  State<CustomerBookingLookupPage> createState() =>
      _CustomerBookingLookupPageState();
}

class _CustomerBookingLookupPageState extends State<CustomerBookingLookupPage> {
  final _formKey = GlobalKey<FormState>();
  final _bookingIdCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void dispose() {
    _bookingIdCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  String _normalizePhone(String v) {
    final digits = StringBuffer();
    for (final ch in v.codeUnits) {
      if (ch >= 0x30 && ch <= 0x39) digits.writeCharCode(ch);
    }
    final out = digits.toString();
    if (out.length >= 7) {
      return out.substring(out.length - 7);
    }
    return out;
  }

  bool _matchesContact(CustomerBookingView view, String contact) {
    final c = contact.trim();
    if (c.isEmpty) return true;
    if (c.contains('@')) {
      final email = view.customerEmail.toLowerCase();
      return email.isNotEmpty && c.toLowerCase() == email;
    }
    final cNorm = _normalizePhone(c);
    final pNorm = _normalizePhone(view.customerPhone);
    if (cNorm.isEmpty || pNorm.isEmpty) return false;
    return pNorm.endsWith(cNorm) || cNorm.endsWith(pNorm);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final bookingId = _bookingIdCtrl.text.trim();
    final contact = _contactCtrl.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final uri = Uri.parse(
        '$kBookingBaseUrl/bookings/${Uri.encodeComponent(bookingId)}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = _t(
            nl: 'Boeking niet gevonden. Controleer de referentie.',
            en: 'Booking not found. Please check your reference.',
            fr: 'Reservation introuvable. Verifiez votre reference.',
            es: 'Reserva no encontrada. Verifica tu referencia.',
          );
        });
        return;
      }
      final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = _t(
            nl: 'Boeking niet gevonden. Controleer de referentie.',
            en: 'Booking not found. Please check your reference.',
            fr: 'Reservation introuvable. Verifiez votre reference.',
            es: 'Reserva no encontrada. Verifica tu referencia.',
          );
        });
        return;
      }
      final view = CustomerBookingView.fromResponse(bookingId, decoded);
      if (contact.isNotEmpty && !_matchesContact(view, contact)) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = _t(
            nl: 'Gegevens komen niet overeen met deze boeking.',
            en: 'Details do not match this booking.',
            fr: 'Les coordonnees ne correspondent pas a cette reservation.',
            es: 'Los datos no coinciden con esta reserva.',
          );
        });
        return;
      }
      final stored = StoredCustomerBooking.fromAuthoritativeResponse(
        bookingId: bookingId,
        response: decoded,
      );
      await CustomerBookingsStore.instance.upsert(stored);
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CustomerBookingDetailPage(
            bookingId: bookingId,
            initialView: view,
            startsFromLocalCache: false,
          ),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      debugPrint(
        '[CUSTOMER_LOOKUP][ERROR] bookingId=${_bookingIdCtrl.text.trim()} error=$err',
      );
      setState(() {
        _busy = false;
        _error = _t(
          nl: 'Verbinding mislukt. Probeer het opnieuw.',
          en: 'Connection failed. Please try again.',
          fr: 'Connexion echouee. Veuillez reessayer.',
          es: 'Conexion fallida. Intentalo de nuevo.',
        );
      });
    }
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    String? hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF141B2F),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1020),
          title: Text(
            _t(
              nl: 'Controleer of volg je boeking',
              en: 'Check or follow your booking',
              fr: 'Verifier ou suivre votre reservation',
              es: 'Consulta o sigue tu reserva',
            ),
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _t(
                    nl: 'Vul je boekingsreferentie in om je boeking terug te vinden.',
                    en: 'Enter your booking reference to look up your booking.',
                    fr: 'Entrez votre reference pour retrouver la reservation.',
                    es: 'Introduce tu referencia para encontrar tu reserva.',
                  ),
                  style: TextStyle(color: Colors.white.withOpacity(0.78)),
                ),
                const SizedBox(height: 14),
                _field(
                  label: _t(
                    nl: 'Boekingsreferentie',
                    en: 'Booking reference',
                    fr: 'Reference de reservation',
                    es: 'Referencia de reserva',
                  ),
                  controller: _bookingIdCtrl,
                  hintText: 'bv. 2026-04-538473',
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) {
                      return _t(
                        nl: 'Voer je boekingsreferentie in',
                        en: 'Enter your booking reference',
                        fr: 'Entrez votre reference',
                        es: 'Introduce tu referencia',
                      );
                    }
                    if (s.length < 4) {
                      return _t(
                        nl: 'Referentie lijkt te kort',
                        en: 'Reference looks too short',
                        fr: 'Reference trop courte',
                        es: 'La referencia es muy corta',
                      );
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _field(
                  label: _t(
                    nl: 'E-mail of telefoon (optioneel)',
                    en: 'Email or phone (optional)',
                    fr: 'E-mail ou telephone (optionnel)',
                    es: 'Email o telefono (opcional)',
                  ),
                  controller: _contactCtrl,
                  hintText: _t(
                    nl: 'Extra controle op je gegevens',
                    en: 'Extra check against your details',
                    fr: 'Verification supplementaire',
                    es: 'Verificacion adicional',
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.4)),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFFFB4B4)),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: const Icon(Icons.search),
                  label: Text(
                    _busy
                        ? _t(
                            nl: 'Zoeken...',
                            en: 'Searching...',
                            fr: 'Recherche...',
                            es: 'Buscando...',
                          )
                        : _t(
                            nl: 'Zoek mijn boeking',
                            en: 'Find my booking',
                            fr: 'Trouver ma reservation',
                            es: 'Buscar mi reserva',
                          ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE5B641),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Read-only customer-safe view extracted from the authoritative booking
/// record returned by `GET /bookings/{id}`. Driver/admin/internal fields
/// (raw tokens, vehicle assignments, internal IDs) are intentionally not
/// surfaced.
class CustomerBookingView {
  CustomerBookingView({
    required this.bookingId,
    required this.lifecycleStatus,
    required this.booking,
    required this.record,
    required this.source,
  });

  final String bookingId;
  final String lifecycleStatus;
  final Map<String, dynamic> booking;
  final Map<String, dynamic> record;
  final Map<String, dynamic> source;

  factory CustomerBookingView.fromResponse(
    String bookingId,
    Map<String, dynamic> response,
  ) {
    final rawRecord = response['record'];
    final record = (rawRecord is Map)
        ? Map<String, dynamic>.from(rawRecord)
        : <String, dynamic>{};
    final rawBooking = record['booking'];
    final booking = (rawBooking is Map)
        ? Map<String, dynamic>.from(rawBooking)
        : <String, dynamic>{};
    final lifecycle =
        (response['status']?.toString().trim() ??
                record['status']?.toString().trim() ??
                '')
            .toUpperCase();
    return CustomerBookingView(
      bookingId: bookingId,
      lifecycleStatus: lifecycle,
      booking: booking,
      record: record,
      source: response,
    );
  }

  factory CustomerBookingView.fromStored(StoredCustomerBooking stored) {
    final booking = <String, dynamic>{
      'from': stored.from,
      'to': stored.to,
      'pickup_iso': stored.pickupIso,
      'customer_name': stored.customerName,
      'customer_phone': stored.customerPhone,
      'customer_email': stored.customerEmail,
      'price_incl_vat': stored.price,
      'currency': stored.currency,
      'service': stored.service,
      'tier': stored.tier,
      'pax': stored.pax,
      'bags': stored.bags,
      'payment_status': stored.paymentStatus,
      'company_name': stored.companyName,
      'vat_number': stored.vatNumber,
      'invoice_email': stored.invoiceEmail,
      'invoice_address': stored.invoiceAddress,
      'business_customer': stored.businessDetected,
      'invoice_requested': stored.invoiceRequested,
      'quote': stored.quote,
    };
    final record = <String, dynamic>{
      'status': stored.status,
      'payment_status': stored.paymentStatus,
      'booking': booking,
      'payload': <String, dynamic>{
        'from': stored.from,
        'to': stored.to,
        'pickup_iso': stored.pickupIso,
        'service': stored.service,
        'tier': stored.tier,
        'pax': stored.pax,
        'bags': stored.bags,
      },
    };
    final source = <String, dynamic>{
      'record': record,
      'booking': booking,
      'quote': stored.quote,
      'payload': record['payload'],
    };
    return CustomerBookingView(
      bookingId: stored.canonicalBookingId,
      lifecycleStatus: stored.status.toUpperCase(),
      booking: booking,
      record: record,
      source: source,
    );
  }

  bool _isMeaningful(String value) {
    final s = value.trim().toLowerCase();
    if (s.isEmpty) return false;
    if (s == '-' || s == 'null' || s == 'undefined') return false;
    return true;
  }

  String _firstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (_isMeaningful(s)) return s;
    }
    return '';
  }

  dynamic _valueAtPath(String path) {
    dynamic current = source;
    for (final segment in path.split('.')) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }

  String _firstPathValue(List<String> paths) {
    for (final path in paths) {
      final raw = _valueAtPath(path);
      final s = raw?.toString().trim() ?? '';
      if (_isMeaningful(s)) return s;
    }
    return '';
  }

  double? _firstPathNum(List<String> paths) {
    for (final path in paths) {
      final raw = _valueAtPath(path);
      if (raw is num) return raw.toDouble();
      final s = raw?.toString().trim() ?? '';
      if (!_isMeaningful(s)) continue;
      final parsed = double.tryParse(s.replaceAll(',', '.'));
      if (parsed != null) return parsed;
    }
    return null;
  }

  bool _toBool(dynamic value) {
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'true' || text == '1' || text == 'yes' || text == 'ja';
  }

  bool _firstPathBool(List<String> paths) {
    for (final path in paths) {
      final raw = _valueAtPath(path);
      if (raw == null) continue;
      return _toBool(raw);
    }
    return false;
  }

  String _preferNonEmptyText(String authoritative, String localFallback) {
    if (_isMeaningful(authoritative)) return authoritative;
    if (_isMeaningful(localFallback)) return localFallback;
    return '';
  }

  CustomerBookingView mergedWithExisting(CustomerBookingView existing) {
    final mergedBooking = <String, dynamic>{...existing.booking, ...booking};
    final mergedRecord = <String, dynamic>{...existing.record, ...record};
    final mergedSource = <String, dynamic>{...existing.source, ...source};

    final mergedFrom = _preferNonEmptyText(fromAddress, existing.fromAddress);
    final mergedTo = _preferNonEmptyText(toAddress, existing.toAddress);
    final mergedPickupIso = _preferNonEmptyText(pickupIso, existing.pickupIso);
    final mergedName = _preferNonEmptyText(customerName, existing.customerName);
    final mergedPhone = _preferNonEmptyText(
      customerPhone,
      existing.customerPhone,
    );
    final mergedEmail = _preferNonEmptyText(
      customerEmail,
      existing.customerEmail,
    );
    final mergedService = _preferNonEmptyText(service, existing.service);
    final mergedTier = _preferNonEmptyText(tier, existing.tier);
    final mergedPax = _preferNonEmptyText(pax, existing.pax);
    final mergedBags = _preferNonEmptyText(bags, existing.bags);
    final mergedCurrency = _preferNonEmptyText(currency, existing.currency);
    final mergedPaymentStatus = _preferNonEmptyText(
      rawPaymentStatus,
      existing.rawPaymentStatus,
    );
    final mergedLifecycleStatus = _preferNonEmptyText(
      lifecycleStatus,
      existing.lifecycleStatus,
    );
    final mergedPrice = totalAmount ?? existing.totalAmount;

    if (_isMeaningful(mergedFrom)) {
      mergedSource['from'] = mergedFrom;
      mergedBooking['from'] = mergedFrom;
      mergedRecord['from'] = mergedFrom;
    }
    if (_isMeaningful(mergedTo)) {
      mergedSource['to'] = mergedTo;
      mergedBooking['to'] = mergedTo;
      mergedRecord['to'] = mergedTo;
    }
    if (_isMeaningful(mergedPickupIso)) {
      mergedBooking['pickup_iso'] = mergedPickupIso;
      mergedRecord['pickup_iso'] = mergedPickupIso;
    }
    if (_isMeaningful(mergedName)) mergedBooking['customer_name'] = mergedName;
    if (_isMeaningful(mergedPhone))
      mergedBooking['customer_phone'] = mergedPhone;
    if (_isMeaningful(mergedEmail))
      mergedBooking['customer_email'] = mergedEmail;
    if (_isMeaningful(mergedService)) mergedBooking['service'] = mergedService;
    if (_isMeaningful(mergedTier)) mergedBooking['tier'] = mergedTier;
    if (_isMeaningful(mergedPax)) mergedBooking['pax'] = mergedPax;
    if (_isMeaningful(mergedBags)) mergedBooking['bags'] = mergedBags;
    if (_isMeaningful(mergedCurrency))
      mergedBooking['currency'] = mergedCurrency;
    if (_isMeaningful(mergedPaymentStatus)) {
      mergedBooking['payment_status'] = mergedPaymentStatus;
      mergedRecord['payment_status'] = mergedPaymentStatus;
    }
    if (_isMeaningful(mergedLifecycleStatus)) {
      mergedRecord['status'] = mergedLifecycleStatus;
    }
    if (mergedPrice != null) {
      mergedBooking['price_incl_vat'] = mergedPrice;
      mergedRecord['amount'] = mergedPrice;
      mergedSource['price_incl_vat'] = mergedPrice;
    }

    mergedRecord['booking'] = mergedBooking;
    mergedSource['record'] = mergedRecord;
    mergedSource['booking'] = mergedBooking;

    return CustomerBookingView(
      bookingId: _preferNonEmptyText(bookingId, existing.bookingId),
      lifecycleStatus: mergedLifecycleStatus,
      booking: mergedBooking,
      record: mergedRecord,
      source: mergedSource,
    );
  }

  String get fromAddress => _firstNonEmpty([
    _firstPathValue(const <String>[
      'from',
      'pickup',
      'pickup_address',
      'pickupAddress',
      'origin',
      'booking.from',
      'booking.pickup',
      'booking.pickup_address',
      'booking.pickupAddress',
      'record.from',
      'record.booking.from',
      'record.booking.pickup',
      'record.booking.pickup_address',
      'record.booking_details.from',
      'record.booking_details.pickup_address',
      'data.record.booking.from',
      'data.record.booking_details.from',
      'payload.from',
      'payload.pickup_address',
      'quote.inputs.from',
    ]),
  ]);
  String get toAddress => _firstNonEmpty([
    _firstPathValue(const <String>[
      'to',
      'destination',
      'destination_address',
      'destinationAddress',
      'dropoff',
      'dropoff_address',
      'booking.to',
      'booking.destination',
      'booking.destination_address',
      'record.to',
      'record.booking.to',
      'record.booking.destination',
      'record.booking.destination_address',
      'record.booking_details.to',
      'record.booking_details.destination_address',
      'data.record.booking.to',
      'data.record.booking_details.to',
      'payload.to',
      'payload.destination_address',
      'quote.inputs.to',
    ]),
  ]);
  String get pickupIso => _firstNonEmpty([
    booking['pickupStartIso'],
    booking['pickup_iso'],
    booking['pickup_at'],
    booking['pickupAt'],
    record['pickup_iso'],
  ]);
  String get customerName => _firstNonEmpty([
    booking['customer_name'],
    booking['name'],
    record['customer_name'],
  ]);
  String get customerPhone => _firstNonEmpty([
    booking['customer_phone'],
    booking['phone'],
    booking['customer_phone_e164'],
  ]);
  String get customerEmail => _firstNonEmpty([
    booking['customer_email'],
    booking['email'],
  ]).toLowerCase();
  String get service => _firstNonEmpty([
    _firstPathValue(const <String>[
      'service',
      'extra_service',
      'extra_service_key',
      'booking.service',
      'booking.extra_service',
      'record.booking.service',
      'record.booking.extra_service',
      'payload.service',
      'quote.inputs.service',
    ]),
  ]);
  String get tier => _firstNonEmpty([
    _firstPathValue(const <String>[
      'tier',
      'booking.tier',
      'record.booking.tier',
      'record.booking_details.tier',
      'payload.tier',
      'quote.inputs.tier',
    ]),
  ]);
  String get pax => _firstNonEmpty([
    _firstPathValue(const <String>[
      'pax',
      'passengers',
      'booking.pax',
      'booking.passengers',
      'record.booking.pax',
      'record.booking_details.pax',
      'payload.pax',
      'quote.inputs.pax',
    ]),
  ]);
  String get bags => _firstNonEmpty([
    _firstPathValue(const <String>[
      'bags',
      'booking.bags',
      'record.booking.bags',
      'record.booking_details.bags',
      'payload.bags',
      'quote.inputs.bags',
    ]),
  ]);
  String get currency => _firstNonEmpty([
    _firstPathValue(const <String>[
      'currency',
      'booking.currency',
      'record.currency',
      'record.booking.currency',
      'record.booking_details.currency',
      'quote.currency',
      'payload.currency',
    ]),
    'EUR',
  ]);
  double? get totalAmount {
    return _firstPathNum(const <String>[
      'price',
      'total',
      'amount',
      'final_total',
      'total_price',
      'price_incl_vat',
      'priceInclVat',
      'booking.price',
      'booking.total',
      'booking.amount',
      'booking.final_total',
      'booking.total_price',
      'booking.price_incl_vat',
      'record.price',
      'record.total',
      'record.amount',
      'record.final_total',
      'record.total_price',
      'record.price_incl_vat',
      'record.booking.price',
      'record.booking.total',
      'record.booking.amount',
      'record.booking.final_total',
      'record.booking.total_price',
      'record.booking_details.price',
      'record.booking_details.total',
      'record.booking_details.amount',
      'record.booking_details.final_total',
      'record.booking_details.total_price',
      'record.booking_details.price_incl_vat',
      'quote.price_incl_vat',
      'quote.priceInclVat',
      'quote.total_price',
      'quote.total',
      'payload.price',
      'payload.total',
      'payload.amount',
      'payload.final_total',
      'payload.total_price',
      'payload.price_incl_vat',
      'payload.quote.price_incl_vat',
    ]);
  }

  String get companyName =>
      _firstNonEmpty([booking['company_name'], booking['company']]);
  String get vatNumber =>
      _firstNonEmpty([booking['vat_number'], booking['vat']]);
  String get invoiceEmail => _firstNonEmpty([
    _firstPathValue(const <String>[
      'invoice_email',
      'invoiceEmail',
      'booking.invoice_email',
      'booking.invoiceEmail',
      'record.invoice_email',
      'record.invoiceEmail',
      'record.booking.invoice_email',
      'record.booking.invoiceEmail',
      'record.booking_details.invoice_email',
      'record.booking_details.invoiceEmail',
      'customer_email',
      'customerEmail',
      'email',
      'custEmail',
      'booking.customer_email',
      'booking.customerEmail',
      'booking.email',
      'booking.custEmail',
      'record.booking.customer_email',
      'record.booking.customerEmail',
      'record.booking.email',
      'record.booking.custEmail',
      'payload.customer_email',
      'payload.customerEmail',
      'payload.email',
      'payload.custEmail',
    ]),
  ]);
  String get invoiceAddress => _firstNonEmpty([
    _firstPathValue(const <String>[
      'invoice_address',
      'invoiceAddress',
      'billing_address',
      'billingAddress',
      'company_address',
      'companyAddress',
      'booking.invoice_address',
      'booking.invoiceAddress',
      'booking.billing_address',
      'booking.billingAddress',
      'booking.company_address',
      'booking.companyAddress',
      'record.invoice_address',
      'record.invoiceAddress',
      'record.billing_address',
      'record.billingAddress',
      'record.company_address',
      'record.companyAddress',
      'record.booking.invoice_address',
      'record.booking.invoiceAddress',
      'record.booking.billing_address',
      'record.booking.billingAddress',
      'record.booking.company_address',
      'record.booking.companyAddress',
    ]),
  ]);
  String get invoiceUrl => _firstNonEmpty([
    _firstPathValue(const <String>[
      'invoice_url',
      'invoiceUrl',
      'invoice_pdf_url',
      'invoicePdfUrl',
      'invoice_download_url',
      'invoiceDownloadUrl',
      'booking.invoice_url',
      'booking.invoiceUrl',
      'booking.invoice_pdf_url',
      'booking.invoicePdfUrl',
      'booking.invoice_download_url',
      'booking.invoiceDownloadUrl',
      'record.invoice_url',
      'record.invoiceUrl',
      'record.invoice_pdf_url',
      'record.invoicePdfUrl',
      'record.invoice_download_url',
      'record.invoiceDownloadUrl',
      'record.booking.invoice_url',
      'record.booking.invoiceUrl',
      'record.booking.invoice_pdf_url',
      'record.booking.invoicePdfUrl',
      'record.booking.invoice_download_url',
      'record.booking.invoiceDownloadUrl',
    ]),
  ]);
  bool get invoiceEmailAvailable => _firstPathBool(const <String>[
    'invoice_email_available',
    'invoiceEmailAvailable',
    'booking.invoice_email_available',
    'booking.invoiceEmailAvailable',
    'record.invoice_email_available',
    'record.invoiceEmailAvailable',
    'record.booking.invoice_email_available',
    'record.booking.invoiceEmailAvailable',
  ]);
  bool get businessCustomer {
    if (vatNumber.isNotEmpty || companyName.isNotEmpty) return true;
    final flag = booking['business_customer'] ?? booking['is_business'];
    if (flag is bool) return flag;
    if (flag is String) {
      final v = flag.toLowerCase().trim();
      return v == 'true' || v == 'yes' || v == 'ja' || v == '1';
    }
    return false;
  }

  String get rawPaymentStatus {
    final candidates = <dynamic>[
      record['payment_status'],
      record['paymentStatus'],
      booking['payment_status'],
      booking['paymentStatus'],
      _firstPathValue(const <String>[
        'payment_status',
        'paymentStatus',
        'record.booking.payment_status',
        'record.booking.paymentStatus',
        'record.booking_details.payment_status',
        'record.booking_details.paymentStatus',
      ]),
    ];
    for (final v in candidates) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s.toLowerCase();
    }
    return '';
  }

  String get paymentMethod {
    return _firstNonEmpty([
      _firstPathValue(const <String>[
        'payment_method',
        'paymentMethod',
        'booking.payment_method',
        'booking.paymentMethod',
        'record.payment_method',
        'record.paymentMethod',
        'record.booking.payment_method',
        'record.booking.paymentMethod',
        'record.booking_details.payment_method',
        'record.booking_details.paymentMethod',
      ]),
    ]).toLowerCase();
  }

  bool get _methodImpliesPaid {
    const inCarPaidMethods = <String>{'cash', 'bancontact', 'qr', 'card'};
    return inCarPaidMethods.contains(paymentMethod);
  }

  bool get isPaid {
    final s = rawPaymentStatus;
    return s == 'paid' ||
        s == 'confirmed' ||
        s == 'completed' ||
        s == 'success' ||
        _methodImpliesPaid;
  }

  String get extraOptions {
    final direct = _firstPathValue(const <String>[
      'extras',
      'extra_service',
      'extra_service_key',
      'premium_options',
      'selected_options',
      'booking.extras',
      'booking.extra_service',
      'booking.extra_service_key',
      'booking.premium_options',
      'booking.selected_options',
      'record.booking.extras',
      'record.booking.extra_service',
      'record.booking.extra_service_key',
      'record.booking.premium_options',
      'record.booking.selected_options',
      'payload.extras',
      'payload.extra_service',
      'payload.extra_service_key',
      'payload.premium_options',
      'payload.selected_options',
      'quote.inputs.extras',
      'quote.inputs.extra_service',
      'quote.inputs.extra_service_key',
    ]);
    if (direct.isNotEmpty) return direct;

    String normalizeList(dynamic raw) {
      if (raw is! List) return '';
      final values = raw
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => _isMeaningful(e))
          .toList(growable: false);
      if (values.isEmpty) return '';
      return values.join(', ');
    }

    final listValue = normalizeList(_valueAtPath('extras'));
    if (listValue.isNotEmpty) return listValue;
    final bookingListValue = normalizeList(_valueAtPath('booking.extras'));
    if (bookingListValue.isNotEmpty) return bookingListValue;
    final payloadListValue = normalizeList(_valueAtPath('payload.extras'));
    if (payloadListValue.isNotEmpty) return payloadListValue;
    return '';
  }
}

/// Customer-facing booking detail screen. Read-only; pull-to-refresh re-fetches
/// the same `GET /bookings/{id}` endpoint. Does not expose driver/admin data
/// or modify any backend state.
class CustomerBookingDetailPage extends StatefulWidget {
  const CustomerBookingDetailPage({
    super.key,
    required this.bookingId,
    required this.initialView,
    this.startsFromLocalCache = false,
  });

  final String bookingId;
  final CustomerBookingView initialView;
  final bool startsFromLocalCache;

  @override
  State<CustomerBookingDetailPage> createState() =>
      _CustomerBookingDetailPageState();
}

class _CustomerBookingDetailPageState extends State<CustomerBookingDetailPage> {
  late CustomerBookingView _view = widget.initialView;
  bool _refreshing = false;
  String? _refreshError;
  late bool _usingLocalCache = widget.startsFromLocalCache;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _refreshError = null;
    });
    try {
      final uri = Uri.parse(
        '$kBookingBaseUrl/bookings/${Uri.encodeComponent(widget.bookingId)}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, dynamic> && decoded['ok'] == true) {
          final authoritativeView = CustomerBookingView.fromResponse(
            widget.bookingId,
            decoded,
          );
          final view = authoritativeView.mergedWithExisting(_view);
          final localFallback = StoredCustomerBooking(
            bookingId: _view.bookingId,
            publicBookingId: _view.bookingId,
            customerName: _view.customerName,
            customerPhone: _view.customerPhone,
            customerEmail: _view.customerEmail,
            from: _view.fromAddress,
            to: _view.toAddress,
            pickupIso: _view.pickupIso,
            price: _view.totalAmount,
            currency: _view.currency,
            service: _view.service,
            tier: _view.tier,
            pax: _view.pax,
            bags: _view.bags,
            paymentStatus: _view.rawPaymentStatus,
            status: _view.lifecycleStatus,
            createdAt: DateTime.now().toIso8601String(),
            updatedAt: DateTime.now().toIso8601String(),
          );
          final stored = StoredCustomerBooking.fromAuthoritativeResponse(
            bookingId: widget.bookingId,
            response: decoded,
            fallback: localFallback,
          );
          await CustomerBookingsStore.instance.upsert(stored);
          if (!mounted) return;
          setState(() {
            _view = view;
            _usingLocalCache = false;
            _refreshing = false;
          });
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _usingLocalCache = true;
        _refreshError = _t(
          nl: 'Vernieuwen mislukt.',
          en: 'Refresh failed.',
          fr: "Echec de l'actualisation.",
          es: 'Error al actualizar.',
        );
      });
    } catch (err) {
      if (!mounted) return;
      debugPrint(
        '[CUSTOMER_DETAIL][REFRESH_ERROR] bookingId=${widget.bookingId} error=$err',
      );
      setState(() {
        _refreshing = false;
        _usingLocalCache = true;
        _refreshError = _t(
          nl: 'Verbinding mislukt. Probeer het opnieuw.',
          en: 'Connection failed. Please try again.',
          fr: 'Connexion echouee. Veuillez reessayer.',
          es: 'Conexion fallida. Intentalo de nuevo.',
        );
      });
    }
  }

  String _formatPickup(String iso) {
    if (iso.isEmpty) return '-';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final local = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String _formatPrice(double? amount, String currency) {
    if (amount == null) return '-';
    final cur = currency.toUpperCase();
    final symbol = cur.isEmpty || cur == 'EUR' ? '€' : '$cur ';
    final formatted = amount.toStringAsFixed(2).replaceAll('.', ',');
    return '$symbol$formatted';
  }

  String _notFilled() => _t(
    nl: 'Nog niet ingevuld',
    en: 'Not filled in yet',
    fr: 'Pas encore renseigne',
    es: 'Aun no completado',
  );

  Future<void> _openExternalUrl(BuildContext context, String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Kon link niet openen.',
              en: 'Could not open link.',
              fr: "Impossible d'ouvrir le lien.",
              es: 'No se pudo abrir el enlace.',
            ),
          ),
        ),
      );
    }
  }

  _TripHistoryItem _asTripHistoryItem() {
    final bookingDetails = <String, dynamic>{
      ..._view.source,
      'booking_id': _view.bookingId,
      'customer_name': _view.customerName,
      'customer_phone': _view.customerPhone,
      'customer_email': _view.customerEmail,
      'from': _view.fromAddress,
      'to': _view.toAddress,
      'service_type': _view.service,
      'tier': _view.tier,
      'passengers': _view.pax,
      'luggage_count': _view.bags,
      'booking_total_eur': _view.totalAmount,
      'currency': _view.currency,
      'payment_status': _view.rawPaymentStatus,
      'payment_method': _view.paymentMethod,
      'company_name': _view.companyName,
      'vat_number': _view.vatNumber,
      'invoice_email': _view.invoiceEmail,
      'invoice_address': _view.invoiceAddress,
      'extras': _view.extraOptions,
      'scheduled_pickup_at': _view.pickupIso,
      'booking': <String, dynamic>{
        'bookingId': _view.bookingId,
        'customer_name': _view.customerName,
        'customer_phone': _view.customerPhone,
        'customer_email': _view.customerEmail,
        'from': _view.fromAddress,
        'to': _view.toAddress,
        'service_type': _view.service,
        'tier': _view.tier,
        'payment_status': _view.rawPaymentStatus,
      },
    };

    return _TripHistoryItem.fromJson(<String, dynamic>{
      'trip_id': _view.bookingId,
      'booking_id': _view.bookingId,
      'kind': 'planned',
      'status': _view.lifecycleStatus,
      'started_at': _view.pickupIso,
      'stopped_at': _view.pickupIso,
      'origin': _view.fromAddress,
      'destination': _view.toAddress,
      'wait_seconds_total': 0,
      'total_eur': _view.totalAmount,
      'currency': _view.currency,
      'booking_details': bookingDetails,
    });
  }

  Future<void> _openReceiptAction(
    BuildContext context,
    _ReceiptQuickAction action,
  ) async {
    final item = _asTripHistoryItem();
    switch (action) {
      case _ReceiptQuickAction.viewPdf:
        await _ReceiptPdfActionRunner.previewPdf(context: context, item: item);
        break;
      case _ReceiptQuickAction.sharePdf:
        await _ReceiptPdfActionRunner.sharePdf(context: context, item: item);
        break;
      case _ReceiptQuickAction.whatsappPdf:
        await _ReceiptPdfActionRunner.sharePdfViaWhatsApp(
          context: context,
          item: item,
        );
        break;
      case _ReceiptQuickAction.emailPdf:
        await _ReceiptPdfActionRunner.sharePdfViaEmail(
          context: context,
          item: item,
        );
        break;
      case _ReceiptQuickAction.printPdf:
        await _ReceiptPdfActionRunner.printPdf(context: context, item: item);
        break;
    }
  }

  String _lifecycleLabel(String s) {
    switch (s) {
      case 'COMPLETED':
        return _t(
          nl: 'Voltooid',
          en: 'Completed',
          fr: 'Terminee',
          es: 'Finalizada',
        );
      case 'CANCELLED':
        return _t(
          nl: 'Geannuleerd',
          en: 'Cancelled',
          fr: 'Annulee',
          es: 'Cancelada',
        );
      case 'PENDING':
        return _t(
          nl: 'In behandeling',
          en: 'Pending',
          fr: 'En cours',
          es: 'Pendiente',
        );
      case 'CONFIRMED':
        return _t(
          nl: 'Bevestigd',
          en: 'Confirmed',
          fr: 'Confirmee',
          es: 'Confirmada',
        );
      default:
        return s.isEmpty ? '-' : s;
    }
  }

  String _tokenLabel(String value) {
    final text = value.trim();
    if (text.isEmpty) return '-';
    final normalized = text.replaceAll('_', ' ').replaceAll('-', ' ');
    return normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) => part.length == 1
              ? part.toUpperCase()
              : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _serviceLabel(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return '-';
    if (value == 'passenger' || value == 'personenvervoer') {
      return _t(
        nl: 'Personenvervoer',
        en: 'Passenger transport',
        fr: 'Transport de passagers',
        es: 'Transporte de pasajeros',
      );
    }
    if (value == 'business' || value == 'zakelijk') {
      return _t(
        nl: 'Zakelijke rit',
        en: 'Business ride',
        fr: "Course d'affaires",
        es: 'Viaje de negocios',
      );
    }
    if (value == 'airport' || value == 'luchthaven') {
      return _t(
        nl: 'Luchthavenvervoer',
        en: 'Airport transfer',
        fr: 'Transfert aeroport',
        es: 'Traslado al aeropuerto',
      );
    }
    return _tokenLabel(raw);
  }

  String _tierLabel(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return '-';
    if (value == 'comfort')
      return _t(nl: 'Comfort', en: 'Comfort', fr: 'Confort', es: 'Confort');
    if (value == 'private')
      return _t(nl: 'Private', en: 'Private', fr: 'Prive', es: 'Privado');
    if (value == 'premium')
      return _t(nl: 'Premium', en: 'Premium', fr: 'Premium', es: 'Premium');
    return _tokenLabel(raw);
  }

  Widget _section({required String title, required List<Widget> children}) {
    return Card(
      color: const Color(0xFF141B2F),
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: Color(0xFFE5B641),
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kv(
    String label,
    String value, {
    bool stacked = false,
    String? emptyText,
  }) {
    final v = value.trim().isEmpty ? (emptyText ?? '-') : value.trim();
    if (stacked) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7))),
            const SizedBox(height: 4),
            Text(v, style: const TextStyle(color: Colors.white)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) {
        final v = _view;
        final paid = v.isPaid;
        final business = v.businessCustomer;
        final invoiceEmail = v.invoiceEmail.trim().isEmpty
            ? _notFilled()
            : v.invoiceEmail.trim();
        final invoiceAddress = v.invoiceAddress.trim().isEmpty
            ? _notFilled()
            : v.invoiceAddress.trim();
        final invoiceFieldsExist =
            v.companyName.isNotEmpty ||
            v.vatNumber.isNotEmpty ||
            v.invoiceEmail.isNotEmpty ||
            v.invoiceAddress.isNotEmpty;
        final showInvoiceSection = business || invoiceFieldsExist;

        return Scaffold(
          backgroundColor: const Color(0xFF0B1020),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0B1020),
            title: Text(
              _t(
                nl: 'Boekingsdetail',
                en: 'Booking detail',
                fr: 'Detail de reservation',
                es: 'Detalle de reserva',
              ),
            ),
            actions: [
              IconButton(
                tooltip: _t(
                  nl: 'Vernieuwen',
                  en: 'Refresh',
                  fr: 'Actualiser',
                  es: 'Actualizar',
                ),
                onPressed: _refreshing ? null : _refresh,
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (_refreshError != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.4)),
                      ),
                      child: Text(
                        _refreshError!,
                        style: const TextStyle(color: Color(0xFFFFB4B4)),
                      ),
                    ),
                  if (_usingLocalCache)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2410),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5B641)),
                      ),
                      child: Text(
                        _t(
                          nl: 'Je ziet lokale gegevens. Vernieuwen voor de laatste status.',
                          en: 'Showing local data. Refresh for the latest status.',
                          fr: 'Donnees locales affichees. Actualisez pour le statut le plus recent.',
                          es: 'Mostrando datos locales. Actualiza para ver el estado mas reciente.',
                        ),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: paid
                          ? const Color(0xFF11331F)
                          : const Color(0xFF2A2410),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: paid
                            ? const Color(0xFF34D29A)
                            : const Color(0xFFE5B641),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          paid
                              ? Icons.verified_outlined
                              : Icons.payments_outlined,
                          color: paid
                              ? const Color(0xFF34D29A)
                              : const Color(0xFFE5B641),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                paid
                                    ? _t(
                                        nl: 'Betaald',
                                        en: 'Paid',
                                        fr: 'Paye',
                                        es: 'Pagado',
                                      )
                                    : _t(
                                        nl: 'Te betalen in de wagen',
                                        en: 'To pay in the vehicle',
                                        fr: 'A payer dans le vehicule',
                                        es: 'A pagar en el vehiculo',
                                      ),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                paid
                                    ? _t(
                                        nl: 'Je betaling is bevestigd.',
                                        en: 'Your payment has been confirmed.',
                                        fr: 'Votre paiement est confirme.',
                                        es: 'Tu pago esta confirmado.',
                                      )
                                    : _t(
                                        nl: 'Voldoe het bedrag bij de chauffeur.',
                                        en: 'Pay the driver during your ride.',
                                        fr: 'Reglez le chauffeur pendant la course.',
                                        es: 'Paga al conductor durante el viaje.',
                                      ),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _section(
                    title: _t(
                      nl: 'Boeking',
                      en: 'Booking',
                      fr: 'Reservation',
                      es: 'Reserva',
                    ),
                    children: [
                      _kv(
                        _t(
                          nl: 'Boeking ID',
                          en: 'Booking ID',
                          fr: 'ID reservation',
                          es: 'ID reserva',
                        ),
                        v.bookingId,
                      ),
                      _kv(
                        _t(
                          nl: 'Status',
                          en: 'Status',
                          fr: 'Statut',
                          es: 'Estado',
                        ),
                        _lifecycleLabel(v.lifecycleStatus),
                      ),
                      _kv(
                        _t(
                          nl: 'Betaalstatus',
                          en: 'Payment status',
                          fr: 'Statut de paiement',
                          es: 'Estado de pago',
                        ),
                        paid
                            ? _t(
                                nl: 'Betaald',
                                en: 'Paid',
                                fr: 'Paye',
                                es: 'Pagado',
                              )
                            : _t(
                                nl: 'Te betalen in de wagen',
                                en: 'To pay in the vehicle',
                                fr: 'A payer dans le vehicule',
                                es: 'A pagar en el vehiculo',
                              ),
                      ),
                    ],
                  ),
                  _section(
                    title: _t(
                      nl: 'Route',
                      en: 'Route',
                      fr: 'Itineraire',
                      es: 'Ruta',
                    ),
                    children: [
                      _kv(
                        _t(
                          nl: 'Ophaaladres',
                          en: 'Pickup',
                          fr: 'Prise en charge',
                          es: 'Recogida',
                        ),
                        v.fromAddress,
                        stacked: true,
                      ),
                      _kv(
                        _t(
                          nl: 'Bestemming',
                          en: 'Destination',
                          fr: 'Destination',
                          es: 'Destino',
                        ),
                        v.toAddress,
                        stacked: true,
                      ),
                      _kv(
                        _t(
                          nl: 'Geplande ophaal',
                          en: 'Scheduled pickup',
                          fr: 'Prise en charge prevue',
                          es: 'Recogida programada',
                        ),
                        _formatPickup(v.pickupIso),
                      ),
                    ],
                  ),
                  _section(
                    title: _t(
                      nl: 'Klantgegevens',
                      en: 'Customer',
                      fr: 'Client',
                      es: 'Cliente',
                    ),
                    children: [
                      _kv(
                        _t(nl: 'Naam', en: 'Name', fr: 'Nom', es: 'Nombre'),
                        v.customerName,
                      ),
                      _kv(
                        _t(
                          nl: 'Telefoon',
                          en: 'Phone',
                          fr: 'Telephone',
                          es: 'Telefono',
                        ),
                        v.customerPhone,
                      ),
                      _kv(
                        _t(
                          nl: 'E-mail',
                          en: 'Email',
                          fr: 'E-mail',
                          es: 'Email',
                        ),
                        v.customerEmail,
                        stacked: true,
                      ),
                    ],
                  ),
                  _section(
                    title: _t(
                      nl: 'Rit details',
                      en: 'Ride details',
                      fr: 'Details de course',
                      es: 'Detalles del viaje',
                    ),
                    children: [
                      _kv(
                        _t(
                          nl: 'Service',
                          en: 'Service',
                          fr: 'Service',
                          es: 'Servicio',
                        ),
                        _serviceLabel(v.service),
                      ),
                      _kv(
                        _t(
                          nl: 'Tier',
                          en: 'Tier',
                          fr: 'Categorie',
                          es: 'Categoria',
                        ),
                        _tierLabel(v.tier),
                      ),
                      _kv(
                        _t(
                          nl: 'Passagiers',
                          en: 'Passengers',
                          fr: 'Passagers',
                          es: 'Pasajeros',
                        ),
                        v.pax,
                      ),
                      _kv(
                        _t(
                          nl: 'Bagage',
                          en: 'Bags',
                          fr: 'Bagages',
                          es: 'Equipaje',
                        ),
                        v.bags,
                      ),
                      _kv(
                        _t(
                          nl: 'Extra opties',
                          en: 'Extra options',
                          fr: 'Options supplementaires',
                          es: 'Opciones extra',
                        ),
                        v.extraOptions.isEmpty
                            ? _t(
                                nl: 'Geen extra opties',
                                en: 'No extra options',
                                fr: 'Aucune option supplementaire',
                                es: 'Sin opciones extra',
                              )
                            : _tokenLabel(v.extraOptions),
                      ),
                    ],
                  ),
                  _section(
                    title: _t(
                      nl: 'Prijs',
                      en: 'Price',
                      fr: 'Prix',
                      es: 'Precio',
                    ),
                    children: [
                      _kv(
                        _t(nl: 'Totaal', en: 'Total', fr: 'Total', es: 'Total'),
                        _formatPrice(v.totalAmount, v.currency),
                      ),
                    ],
                  ),
                  if (showInvoiceSection)
                    _section(
                      title: _t(
                        nl: 'Zakelijk / Factuur',
                        en: 'Business / Invoice',
                        fr: 'Professionnel / Facture',
                        es: 'Empresa / Factura',
                      ),
                      children: [
                        _kv(
                          _t(
                            nl: 'Zakelijke klant',
                            en: 'Business customer',
                            fr: 'Client professionnel',
                            es: 'Cliente empresa',
                          ),
                          business
                              ? _t(nl: 'Ja', en: 'Yes', fr: 'Oui', es: 'Si')
                              : _t(nl: 'Nee', en: 'No', fr: 'Non', es: 'No'),
                        ),
                        _kv(
                          _t(
                            nl: 'Bedrijfsnaam',
                            en: 'Company name',
                            fr: "Nom de l'entreprise",
                            es: 'Empresa',
                          ),
                          v.companyName,
                          stacked: true,
                        ),
                        _kv(
                          _t(
                            nl: 'BTW-nummer',
                            en: 'VAT number',
                            fr: 'Numero de TVA',
                            es: 'NIF/IVA',
                          ),
                          v.vatNumber,
                          stacked: true,
                        ),
                        _kv(
                          _t(
                            nl: 'Factuur e-mail',
                            en: 'Invoice email',
                            fr: 'E-mail facture',
                            es: 'Email de factura',
                          ),
                          invoiceEmail,
                          stacked: true,
                          emptyText: _notFilled(),
                        ),
                        _kv(
                          _t(
                            nl: 'Factuuradres',
                            en: 'Invoice address',
                            fr: 'Adresse de facturation',
                            es: 'Direccion de factura',
                          ),
                          invoiceAddress,
                          stacked: true,
                          emptyText: _notFilled(),
                        ),
                        const SizedBox(height: 8),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _openReceiptAction(
                                context,
                                _ReceiptQuickAction.viewPdf,
                              ),
                              icon: const Icon(Icons.visibility_outlined),
                              label: Text(
                                _t(
                                  nl: 'Bekijk PDF',
                                  en: 'View PDF',
                                  fr: 'Voir PDF',
                                  es: 'Ver PDF',
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _openReceiptAction(
                                context,
                                _ReceiptQuickAction.sharePdf,
                              ),
                              icon: const Icon(Icons.download_outlined),
                              label: Text(
                                _t(
                                  nl: 'Deel PDF',
                                  en: 'Share PDF',
                                  fr: 'Partager PDF',
                                  es: 'Compartir PDF',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

final List<Map<String, dynamic>> _customerRegionLeadInbox =
    <Map<String, dynamic>>[];

class CustomerRegionRegistrationPage extends StatefulWidget {
  const CustomerRegionRegistrationPage({super.key});

  @override
  State<CustomerRegionRegistrationPage> createState() =>
      _CustomerRegionRegistrationPageState();
}

class _CustomerRegionRegistrationPageState
    extends State<CustomerRegionRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _postalCodeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _wantsUpdates = true;
  bool _submitting = false;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _postalCodeCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  String? _required(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) {
      return _t(
        nl: 'Dit veld is verplicht',
        en: 'This field is required',
        fr: 'Ce champ est obligatoire',
        es: 'Este campo es obligatorio',
      );
    }
    return null;
  }

  String? _emailValidator(String? value) {
    final requiredError = _required(value);
    if (requiredError != null) return requiredError;
    final v = value!.trim();
    if (!v.contains('@') || !v.contains('.')) {
      return _t(
        nl: 'Voer een geldig e-mailadres in',
        en: 'Enter a valid email address',
        fr: 'Entrez une adresse e-mail valide',
        es: 'Introduce un correo electronico valido',
      );
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    // Temporary safe local capture until backend lead endpoint is introduced.
    _customerRegionLeadInbox.add(<String, dynamic>{
      'first_name': _firstNameCtrl.text.trim(),
      'last_name': _lastNameCtrl.text.trim(),
      'postal_code': _postalCodeCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'notify_updates': _wantsUpdates,
      'created_at': DateTime.now().toIso8601String(),
    });

    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Bedankt! We hebben je regio geregistreerd.',
            en: 'Thank you! We have registered your region.',
            fr: 'Merci ! Nous avons enregistre votre region.',
            es: 'Gracias. Hemos registrado tu region.',
          ),
        ),
      ),
    );
    Navigator.pop(context);
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    String? hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF141B2F),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1020),
          title: Text(
            _t(
              nl: 'Registreer je regio',
              en: 'Register your region',
              fr: 'Enregistrez votre region',
              es: 'Registra tu region',
            ),
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _t(
                    nl: 'Laat je gegevens achter zodat we je kunnen informeren wanneer Fluxidi actief wordt in jouw regio.',
                    en: 'Leave your details so we can inform you when Fluxidi becomes active in your region.',
                    fr: 'Laissez vos coordonnees afin que nous puissions vous informer lorsque Fluxidi sera actif dans votre region.',
                    es: 'Deja tus datos para que podamos avisarte cuando Fluxidi este activo en tu region.',
                  ),
                  style: TextStyle(color: Colors.white.withOpacity(0.78)),
                ),
                const SizedBox(height: 14),
                _field(
                  label: _t(
                    nl: 'Voornaam',
                    en: 'First name',
                    fr: 'Prenom',
                    es: 'Nombre',
                  ),
                  controller: _firstNameCtrl,
                  validator: _required,
                ),
                const SizedBox(height: 12),
                _field(
                  label: _t(
                    nl: 'Naam',
                    en: 'Last name',
                    fr: 'Nom',
                    es: 'Apellido',
                  ),
                  controller: _lastNameCtrl,
                  validator: _required,
                ),
                const SizedBox(height: 12),
                _field(
                  label: _t(
                    nl: 'Postcode',
                    en: 'Postal code',
                    fr: 'Code postal',
                    es: 'Codigo postal',
                  ),
                  controller: _postalCodeCtrl,
                  validator: _required,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                _field(
                  label: _t(
                    nl: 'E-mail',
                    en: 'Email',
                    fr: 'E-mail',
                    es: 'Correo electronico',
                  ),
                  controller: _emailCtrl,
                  validator: _emailValidator,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                _field(
                  label: _t(
                    nl: 'Telefoon (optioneel)',
                    en: 'Phone (optional)',
                    fr: 'Telephone (optionnel)',
                    es: 'Telefono (opcional)',
                  ),
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _wantsUpdates,
                  onChanged: (v) => setState(() => _wantsUpdates = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFFE5B641),
                  title: Text(
                    _t(
                      nl: 'Hou me op de hoogte wanneer Fluxidi beschikbaar is in mijn regio',
                      en: 'Keep me updated when Fluxidi is available in my region',
                      fr: 'Tenez-moi informe lorsque Fluxidi est disponible dans ma region',
                      es: 'Mantenme informado cuando Fluxidi este disponible en mi region',
                    ),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _submitting
                          ? _t(
                              nl: 'Bezig...',
                              en: 'Sending...',
                              fr: 'Envoi...',
                              es: 'Enviando...',
                            )
                          : _t(
                              nl: 'Verzenden',
                              en: 'Send',
                              fr: 'Envoyer',
                              es: 'Enviar',
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    _t(
                      nl: 'Terug naar klantenpagina',
                      en: 'Back to customer page',
                      fr: 'Retour a la page client',
                      es: 'Volver a la pagina de cliente',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NearbyPartnersPage extends StatefulWidget {
  const NearbyPartnersPage({super.key});

  @override
  State<NearbyPartnersPage> createState() => _NearbyPartnersPageState();
}

class _NearbyPartnersPageState extends State<NearbyPartnersPage> {
  final TextEditingController _postalCodeCtrl = TextEditingController();
  bool _searching = false;
  bool _searched = false;
  String _normalizedPostcode = '';
  List<Map<String, dynamic>> _partners = const <Map<String, dynamic>>[];

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void dispose() {
    _postalCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchPartners() async {
    final raw = _postalCodeCtrl.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Vul eerst een postcode in.',
              en: 'Enter a postal code first.',
              fr: 'Entrez d abord un code postal.',
              es: 'Introduce primero un codigo postal.',
            ),
          ),
        ),
      );
      return;
    }
    final postcode = raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    setState(() {
      _searching = true;
      _searched = false;
      _normalizedPostcode = postcode;
      _partners = const <Map<String, dynamic>>[];
    });
    try {
      final uri = Uri.parse(
        '$kBookingBaseUrl/partners/nearby?postcode=${Uri.encodeQueryComponent(postcode)}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final decoded = jsonDecode(res.body);
      final partnersRaw =
          decoded is Map<String, dynamic> && decoded['partners'] is List
          ? (decoded['partners'] as List)
                .whereType<Map<String, dynamic>>()
                .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searched = true;
        _partners = partnersRaw;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searched = true;
        _partners = const <Map<String, dynamic>>[];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Zoeken van partners is momenteel niet beschikbaar.',
              en: 'Partner search is currently unavailable.',
              fr: 'La recherche de partenaires est actuellement indisponible.',
              es: 'La busqueda de socios no esta disponible actualmente.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1020),
          title: Text(
            _t(
              nl: "Taxi's in de buurt",
              en: 'Taxis nearby',
              fr: 'Taxis a proximite',
              es: 'Taxis cercanos',
            ),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                _t(
                  nl: 'Zoek actieve Fluxidi-partners in jouw regio op basis van postcode.',
                  en: 'Search active Fluxidi partners in your area by postal code.',
                  fr: 'Recherchez des partenaires Fluxidi actifs dans votre region par code postal.',
                  es: 'Busca socios activos de Fluxidi en tu zona por codigo postal.',
                ),
                style: TextStyle(color: Colors.white.withOpacity(0.78)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _postalCodeCtrl,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _searchPartners(),
                decoration: InputDecoration(
                  labelText: _t(
                    nl: 'Postcode',
                    en: 'Postal code',
                    fr: 'Code postal',
                    es: 'Codigo postal',
                  ),
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintText: _t(
                    nl: 'Bijv. 2000',
                    en: 'e.g. 2000',
                    fr: 'ex. 2000',
                    es: 'ej. 2000',
                  ),
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF141B2F),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _searching ? null : _searchPartners,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _searching
                        ? _t(
                            nl: 'Zoeken...',
                            en: 'Searching...',
                            fr: 'Recherche...',
                            es: 'Buscando...',
                          )
                        : _t(
                            nl: 'Zoek actieve partners',
                            en: 'Search active partners',
                            fr: 'Rechercher des partenaires actifs',
                            es: 'Buscar socios activos',
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF141B2F),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: !_searched
                    ? Text(
                        _t(
                          nl: 'Voer je postcode in om te controleren welke partners actief zijn.',
                          en: 'Enter your postal code to check which partners are active.',
                          fr: 'Saisissez votre code postal pour verifier quels partenaires sont actifs.',
                          es: 'Ingresa tu codigo postal para verificar que socios estan activos.',
                        ),
                        style: TextStyle(color: Colors.white.withOpacity(0.75)),
                      )
                    : _partners.isNotEmpty
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t(
                              nl: 'Actieve partners in $_normalizedPostcode',
                              en: 'Active partners in $_normalizedPostcode',
                              fr: 'Partenaires actifs dans $_normalizedPostcode',
                              es: 'Socios activos en $_normalizedPostcode',
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ..._partners.map((p) {
                            final company = (p['company_name'] ?? '')
                                .toString()
                                .trim();
                            final partnerId = (p['partner_id'] ?? '')
                                .toString()
                                .trim();
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F1628),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.business_outlined,
                                    color: Color(0xFFE5B641),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          company.isEmpty ? partnerId : company,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (partnerId.isNotEmpty)
                                          Text(
                                            partnerId,
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                0.58,
                                              ),
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t(
                              nl: 'Voor postcode $_normalizedPostcode hebben we nog geen actieve partners gevonden.',
                              en: 'No active partners found yet for postal code $_normalizedPostcode.',
                              fr: 'Aucun partenaire actif trouve pour le code postal $_normalizedPostcode.',
                              es: 'Aun no se encontraron socios activos para el codigo postal $_normalizedPostcode.',
                            ),
                            style: const TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const CustomerRegionRegistrationPage(),
                                ),
                              );
                            },
                            child: Text(
                              _t(
                                nl: 'Registreer je regio',
                                en: 'Register your region',
                                fr: 'Enregistrez votre region',
                                es: 'Registra tu region',
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FluxidiFrame extends StatelessWidget {
  final Widget child;
  const FluxidiFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Hard Frame A: a visible yellow HUD border that *contains* the whole UI.
    // Target: visually ~2–3mm on phone screens.
    return Container(
      color: kFluxidiBlack,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: kFluxidiBlack,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: kFluxidiYellow.withOpacity(0.98),
                width: 3.0,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 18,
                  spreadRadius: 2,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: kFluxidiBlack,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: kFluxidiYellow.withOpacity(0.55),
                    width: 1.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BookingItem {
  final String bookingId;
  final String? pickupIso;
  final String? from;
  final String? to;
  final String? tier;
  final int? pax;
  final int? bags;
  final String? status;
  final num? price; // optional
  final String? currency; // optional
  final Map<String, dynamic> details;

  // Tracking API (fluxidi-tracking-api)
  final String? sessionId;
  final String? createdAtIso;
  final double? lastLat;
  final double? lastLon;
  final String? lastPingTs;
  final num? lastSpeed;
  final num? lastHeading;

  BookingItem({
    required this.bookingId,
    this.sessionId,
    this.pickupIso,
    this.from,
    this.to,
    this.tier,
    this.pax,
    this.bags,
    this.status,
    this.price,
    this.currency,
    this.details = const <String, dynamic>{},
    this.createdAtIso,
    this.lastLat,
    this.lastLon,
    this.lastPingTs,
    this.lastSpeed,
    this.lastHeading,
  });

  String get shortId {
    if (bookingId.length <= 12) return bookingId;
    return '${bookingId.substring(0, 4)}…${bookingId.substring(bookingId.length - 4)}';
  }

  static String? _extractPlaceLabel(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      final s = v.trim();
      return s.isEmpty ? null : s;
    }
    if (v is Map<String, dynamic>) {
      // Common shapes: {address: "..."} or {label:"..."} or {text:"..."} etc.
      const keys = [
        'address',
        'label',
        'text',
        'name',
        'formatted',
        'display',
        'place_name',
        'full_address',
      ];
      for (final k in keys) {
        final vv = v[k];
        if (vv is String && vv.trim().isNotEmpty) return vv.trim();
      }

      // Sometimes nested like {pickup:{address:"..."}} already handled upstream,
      // but also allow {location:{address:"..."}} style.
      for (final nestedKey in ['location', 'place', 'geo', 'data']) {
        final nested = v[nestedKey];
        if (nested is Map<String, dynamic>) {
          for (final k in keys) {
            final vv = nested[k];
            if (vv is String && vv.trim().isNotEmpty) return vv.trim();
          }
        }
      }
    }
    return null;
  }

  BookingItem copyWith({
    String? bookingId,
    String? pickupIso,
    String? from,
    String? to,
    String? tier,
    int? pax,
    int? bags,
    String? status,
    num? price,
    String? currency,
    Map<String, dynamic>? details,
    String? sessionId,
    String? createdAtIso,
    double? lastLat,
    double? lastLon,
    String? lastPingTs,
    num? lastSpeed,
    num? lastHeading,
  }) {
    return BookingItem(
      bookingId: bookingId ?? this.bookingId,
      pickupIso: pickupIso ?? this.pickupIso,
      from: from ?? this.from,
      to: to ?? this.to,
      tier: tier ?? this.tier,
      pax: pax ?? this.pax,
      bags: bags ?? this.bags,
      status: status ?? this.status,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      details: details ?? this.details,
      sessionId: sessionId ?? this.sessionId,
      createdAtIso: createdAtIso ?? this.createdAtIso,
      lastLat: lastLat ?? this.lastLat,
      lastLon: lastLon ?? this.lastLon,
      lastPingTs: lastPingTs ?? this.lastPingTs,
      lastSpeed: lastSpeed ?? this.lastSpeed,
      lastHeading: lastHeading ?? this.lastHeading,
    );
  }

  factory BookingItem.fromJson(Map<String, dynamic> j) {
    // Support both booking-api payloads and tracking-api payloads.
    final lastPing = (j['last_ping'] is Map<String, dynamic>)
        ? (j['last_ping'] as Map<String, dynamic>)
        : null;

    String? pickLabel = _extractPlaceLabel(j['pickup'] ?? j['from']);
    String? dropLabel = _extractPlaceLabel(j['dropoff'] ?? j['to']);

    // Extra common field names across versions/backends
    pickLabel ??= _extractPlaceLabel(
      j['pickup_address'] ?? j['pickup_label'] ?? j['from_address'],
    );
    dropLabel ??= _extractPlaceLabel(
      j['dropoff_address'] ?? j['dropoff_label'] ?? j['to_address'],
    );

    // If backend already provides plain strings, prefer those
    final fromStr = (j['from'] is String) ? (j['from'] as String) : null;
    final toStr = (j['to'] is String) ? (j['to'] as String) : null;

    return BookingItem(
      bookingId: (j['booking_id'] ?? j['id'] ?? '').toString(),
      pickupIso: j['pickup_iso']?.toString(),
      from: (fromStr?.trim().isNotEmpty ?? false)
          ? fromStr!.trim()
          : (pickLabel?.trim().isNotEmpty ?? false ? pickLabel!.trim() : null),
      to: (toStr?.trim().isNotEmpty ?? false)
          ? toStr!.trim()
          : (dropLabel?.trim().isNotEmpty ?? false ? dropLabel!.trim() : null),
      tier: j['tier']?.toString(),
      pax: _toIntOrNull(
        j['pax'] ??
            j['passengers'] ??
            j['persons'] ??
            j['pax_count'] ??
            j['paxCount'],
      ),
      bags: _toIntOrNull(
        j['bags'] ?? j['luggage'] ?? j['bags_count'] ?? j['bagsCount'],
      ),
      status: (j['status'] ?? j['stage'])?.toString(),
      price: _toNumOrNull(
        j['price'] ??
            j['total_price'] ??
            j['total'] ??
            j['amount'] ??
            j['eur'] ??
            ((j['quote'] is Map) ? (j['quote'] as Map)['price'] : null) ??
            ((j['quote'] is Map) ? (j['quote'] as Map)['total_price'] : null) ??
            ((j['quote'] is Map) ? (j['quote'] as Map)['total'] : null) ??
            ((j['quote'] is Map) ? (j['quote'] as Map)['amount'] : null) ??
            ((j['quote'] is Map) ? (j['quote'] as Map)['eur'] : null) ??
            (((j['quote'] is Map) && ((j['quote'] as Map)['pricing'] is Map))
                ? ((j['quote'] as Map)['pricing'] as Map)['price_incl_vat']
                : null) ??
            (((j['quote'] is Map) && ((j['quote'] as Map)['pricing'] is Map))
                ? ((j['quote'] as Map)['pricing'] as Map)['total_price']
                : null) ??
            (((j['quote'] is Map) && ((j['quote'] as Map)['pricing'] is Map))
                ? ((j['quote'] as Map)['pricing'] as Map)['total']
                : null) ??
            (((j['quote'] is Map) && ((j['quote'] as Map)['pricing'] is Map))
                ? ((j['quote'] as Map)['pricing'] as Map)['price']
                : null) ??
            (((j['quote'] is Map) && ((j['quote'] as Map)['pricing'] is Map))
                ? ((j['quote'] as Map)['pricing'] as Map)['amount']
                : null) ??
            (((j['quote'] is Map) && ((j['quote'] as Map)['pricing'] is Map))
                ? ((j['quote'] as Map)['pricing'] as Map)['eur']
                : null),
      ),
      currency: (j['currency'] ?? 'EUR')?.toString(),
      details: Map<String, dynamic>.from(j),
      sessionId: j['session_id']?.toString(),
      createdAtIso: j['created_at']?.toString(),
      lastLat: _toDoubleOrNull(lastPing?['lat']),
      lastLon: _toDoubleOrNull(lastPing?['lon']),
      lastPingTs: lastPing?['ts']?.toString(),
      lastSpeed: _toNumOrNull(lastPing?['speed']),
      lastHeading: _toNumOrNull(lastPing?['heading']),
    );
  }

  static int? _toIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  static num? _toNumOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  static double? _toDoubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

enum _CameraMode { overview, follow }

enum _RideRoutePhase { toPickup, trip }

enum MapThemeMode { light, dark }

class _PlaceSuggestion {
  final String label;
  final double? lon;
  final double? lat;
  const _PlaceSuggestion({required this.label, this.lon, this.lat});
}

class _DirectRideDestinationResult {
  final String label;
  final double? lon;
  final double? lat;

  const _DirectRideDestinationResult({required this.label, this.lon, this.lat});
}

class _TripHistoryItem {
  final String tripId;
  final String kind;
  final String? bookingId;
  final String driverId;
  final String? vehicleId;
  final String? startedAt;
  final String? stoppedAt;
  final String origin;
  final String destination;
  final double? kmTotal;
  final int waitSecondsTotal;
  final double? totalEur;
  final String status;
  final String currency;
  final Map<String, dynamic> bookingDetails;
  final Map<String, dynamic> rawSource;
  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;

  const _TripHistoryItem({
    required this.tripId,
    required this.kind,
    required this.bookingId,
    required this.driverId,
    required this.vehicleId,
    required this.startedAt,
    required this.stoppedAt,
    required this.origin,
    required this.destination,
    required this.kmTotal,
    required this.waitSecondsTotal,
    required this.totalEur,
    required this.status,
    required this.currency,
    required this.bookingDetails,
    required this.rawSource,
    required this.customerName,
    required this.customerPhone,
    required this.customerEmail,
  });

  factory _TripHistoryItem.fromJson(Map<String, dynamic> json) {
    final origin = json['origin'];
    final destination = json['destination'];
    final originLabel = origin is Map ? origin['label']?.toString() : null;
    final label = destination is Map ? destination['label']?.toString() : null;
    final bookingDetails = json['booking_details'] is Map
        ? Map<String, dynamic>.from(json['booking_details'] as Map)
        : <String, dynamic>{};
    final rawSource = Map<String, dynamic>.from(json);
    void copyRootDetail(String rootKey, String detailKey) {
      final value = json[rootKey];
      if (value == null) return;
      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') return;
      bookingDetails.putIfAbsent(detailKey, () => value);
    }

    copyRootDetail('payment_status', 'payment_status');
    copyRootDetail('paymentStatus', 'paymentStatus');
    copyRootDetail('paid_at', 'paid_at');
    copyRootDetail('paidAt', 'paidAt');
    copyRootDetail('payment_provider', 'payment_provider');
    copyRootDetail('paymentProvider', 'paymentProvider');
    copyRootDetail('payment_id', 'payment_id');
    copyRootDetail('paymentId', 'paymentId');
    final customerName = _resolveScalarLabel(json, const <String>[
      'customer.name',
      'customer_name',
      'customerName',
      'custName',
      'name',
      'booking.customer.name',
      'booking.customer_name',
      'booking.customerName',
      'booking.custName',
      'booking.name',
      'record.customer_name',
      'record.booking.customer_name',
      'record.booking.customerName',
      'record.booking.custName',
      'payload.customer_name',
      'payload.booking.customer_name',
      'booking_details.customer_name',
      'booking_details.customerName',
      'booking_details.custName',
    ]);
    final customerPhone = _resolveScalarLabel(json, const <String>[
      'customer.phone',
      'customer_phone',
      'customerPhone',
      'custPhone',
      'phone',
      'tel',
      'mobile',
      'booking.customer.phone',
      'booking.customer_phone',
      'booking.customerPhone',
      'booking.custPhone',
      'booking.phone',
      'record.customer_phone',
      'record.booking.customer_phone',
      'record.booking.customerPhone',
      'record.booking.custPhone',
      'payload.customer_phone',
      'payload.booking.customer_phone',
      'booking_details.customer_phone',
      'booking_details.customerPhone',
      'booking_details.custPhone',
      'booking_details.phone',
      'booking_details.tel',
      'booking_details.mobile',
    ]);
    final customerEmail = _resolveEmailLabel(json, const <String>[
      'customer.email',
      'customer_email',
      'customerEmail',
      'custEmail',
      'email',
      'invoiceEmail',
      'invoice_email',
      'booking.customer.email',
      'booking.customer_email',
      'booking.customerEmail',
      'booking.custEmail',
      'booking.email',
      'record.customer_email',
      'record.booking.customer_email',
      'record.booking.customerEmail',
      'record.booking.custEmail',
      'payload.customer_email',
      'payload.booking.customer_email',
      'booking_details.customer_email',
      'booking_details.customerEmail',
      'booking_details.custEmail',
      'booking_details.email',
      'booking_details.invoice_email',
      'booking_details.invoiceEmail',
    ]);
    final fromResolved = _resolveRouteLabel(json, const <String>[
      'from',
      'pickup',
      'pickup_address',
      'pickupAddress',
      'pickupLocation',
      'pickup_location',
      'origin',
      'start_address',
      'startAddress',
      'booking.from',
      'booking.pickup',
      'booking.pickup_address',
      'booking.pickupAddress',
      'record.from',
      'record.booking.from',
      'record.booking.pickup',
      'payload.from',
      'payload.booking.from',
      'quote.inputs.from',
      'booking_details.from',
      'booking_details.pickup',
      'booking_details.pickup_address',
      'booking_details.pickupAddress',
    ]);
    final toResolved = _resolveRouteLabel(json, const <String>[
      'to',
      'destination',
      'destination_address',
      'destinationAddress',
      'dropoff',
      'dropoff_address',
      'dropoffAddress',
      'end_address',
      'endAddress',
      'booking.to',
      'booking.destination',
      'booking.destination_address',
      'booking.destinationAddress',
      'record.to',
      'record.booking.to',
      'record.booking.destination',
      'payload.to',
      'payload.booking.to',
      'quote.inputs.to',
      'booking_details.to',
      'booking_details.destination',
      'booking_details.destination_address',
      'booking_details.destinationAddress',
    ]);
    double? asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse((value ?? '').toString().replaceAll(',', '.'));
    }

    int asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.round();
      return int.tryParse((value ?? '').toString()) ?? 0;
    }

    return _TripHistoryItem(
      tripId: (json['trip_id'] ?? '').toString(),
      kind: (json['kind'] ?? 'direct').toString(),
      bookingId: json['booking_id']?.toString(),
      driverId: (json['driver_id'] ?? '').toString(),
      vehicleId: json['vehicle_id']?.toString(),
      startedAt: json['started_at']?.toString(),
      stoppedAt: json['stopped_at']?.toString(),
      origin:
          fromResolved.value ??
          _placeLabel(origin, originLabel ?? _receiptText('currentLocation')),
      destination:
          toResolved.value ??
          ((label == null || label.trim().isEmpty) ? '—' : label.trim()),
      kmTotal: asDouble(json['km_total']),
      waitSecondsTotal: asInt(json['wait_seconds_total']),
      totalEur: asDouble(json['total_eur']),
      status: (json['status'] ?? '—').toString(),
      currency: (json['currency'] ?? 'EUR').toString(),
      bookingDetails: bookingDetails,
      rawSource: rawSource,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
    );
  }

  static String _placeLabel(dynamic value, String fallback) {
    if (value is Map) {
      final label = value['label']?.toString().trim();
      if (label != null && label.isNotEmpty) return label;
      final lat = value['lat'];
      final lon = value['lon'];
      if (lat != null && lon != null) return '$lat, $lon';
    }
    return fallback;
  }

  static ({String? value, String? key}) _resolveRouteLabel(
    Map<String, dynamic> root,
    List<String> paths,
  ) {
    for (final path in paths) {
      final value = _pathValue(root, path);
      final label = _extractRouteLabel(value);
      if (label != null && label.isNotEmpty) {
        return (value: label, key: path);
      }
    }
    return (value: null, key: null);
  }

  static String? _resolveScalarLabel(
    Map<String, dynamic> root,
    List<String> paths,
  ) {
    for (final path in paths) {
      final value = _pathValue(root, path);
      final text = _cleanText(value);
      if (text != null) return text;
    }
    return null;
  }

  static String? _resolveEmailLabel(
    Map<String, dynamic> root,
    List<String> paths,
  ) {
    for (final path in paths) {
      final value = _pathValue(root, path);
      final text = _cleanText(value);
      if (text == null) continue;
      if (_looksLikeEmail(text)) return text;
    }
    return null;
  }

  static String? _cleanText(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text == '—' || text.toLowerCase() == 'null')
      return null;
    return text;
  }

  static bool _looksLikeEmail(String value) {
    final at = value.indexOf('@');
    if (at <= 0 || at >= value.length - 1) return false;
    final dotAfterAt = value.indexOf('.', at + 1);
    if (dotAfterAt <= at + 1 || dotAfterAt >= value.length - 1) return false;
    return !value.contains(RegExp(r'\s'));
  }

  static dynamic _pathValue(Map<String, dynamic> root, String path) {
    dynamic current = root;
    for (final segment in path.split('.')) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }

  static String? _extractRouteLabel(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty || text == '—') return null;
      return text;
    }
    if (value is Map) {
      final label = value['label']?.toString().trim();
      if (label != null && label.isNotEmpty && label != '—') return label;
    }
    final fallback = value.toString().trim();
    if (fallback.isEmpty || fallback == '—') return null;
    return fallback;
  }

  bool get isCompletedForReceipt {
    final s = status.toLowerCase().trim();
    return s == 'stopped' || s == 'completed';
  }

  String get receiptNumber {
    if (tripId.length <= 10) return tripId;
    return '${tripId.substring(0, 6)}-${tripId.substring(tripId.length - 4)}';
  }

  String get kindLabel {
    return _localizedRideKind(kind);
  }

  String? detail(String key) {
    final value = bookingDetails[key];
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class _DirectRideDestinationDialog extends StatefulWidget {
  final String initialText;
  final Future<List<_PlaceSuggestion>> Function(String query) search;

  const _DirectRideDestinationDialog({
    required this.initialText,
    required this.search,
  });

  @override
  State<_DirectRideDestinationDialog> createState() =>
      _DirectRideDestinationDialogState();
}

class _DirectRideDestinationDialogState
    extends State<_DirectRideDestinationDialog> {
  late final TextEditingController _controller;
  Timer? _debounce;
  List<_PlaceSuggestion> _suggestions = <_PlaceSuggestion>[];
  _PlaceSuggestion? _selected;
  bool _loading = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _selected = null;
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 3) {
      setState(() {
        _loading = false;
        _searched = false;
        _suggestions = <_PlaceSuggestion>[];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() {
        _loading = true;
        _searched = true;
      });
      final results = await widget.search(q);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _suggestions = results;
      });
    });
  }

  void _pick(_PlaceSuggestion suggestion) {
    setState(() {
      _selected = suggestion;
      _controller.text = suggestion.label;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      _suggestions = <_PlaceSuggestion>[];
      _searched = false;
    });
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final selected = _selected;
    Navigator.of(context).pop(
      _DirectRideDestinationResult(
        label: selected?.label ?? text,
        lon: selected?.lon,
        lat: selected?.lat,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _tr(
          nl: 'Straatrit',
          en: 'Direct ride',
          fr: 'Course directe',
          es: 'Viaje directo',
        ),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: _tr(
                  nl: 'Bestemming',
                  en: 'Destination',
                  fr: 'Destination',
                  es: 'Destino',
                ),
                hintText: _tr(
                  nl: 'Typ minstens 3 tekens',
                  en: 'Type at least 3 characters',
                  fr: 'Tapez au moins 3 caracteres',
                  es: 'Escribe al menos 3 caracteres',
                ),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              onChanged: _onChanged,
              onSubmitted: (_) => _submit(),
            ),
            if (_suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 10),
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0F1C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x44FFD54A)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0x22FFFFFF)),
                  itemBuilder: (context, index) {
                    final suggestion = _suggestions[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        suggestion.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _pick(suggestion),
                    );
                  },
                ),
              )
            else if (_searched && !_loading)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _tr(
                      nl: 'Geen adres gevonden',
                      en: 'No address found',
                      fr: 'Aucune adresse trouvee',
                      es: 'No se encontro direccion',
                    ),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.70),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            _tr(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
          ),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(
            _tr(
              nl: 'Doorgaan',
              en: 'Continue',
              fr: 'Continuer',
              es: 'Continuar',
            ),
          ),
        ),
      ],
    );
  }
}

class _LonLat {
  final double lon;
  final double lat;
  const _LonLat(this.lon, this.lat);
}

class _NavStep {
  final double lat;
  final double lon;
  final String instruction;
  final String street;
  final String type;
  final String modifier;
  final double distanceAlongRouteM;
  final double? distanceM;
  final int? durationSec;

  const _NavStep({
    required this.lat,
    required this.lon,
    required this.instruction,
    required this.street,
    required this.type,
    required this.modifier,
    required this.distanceAlongRouteM,
    this.distanceM,
    this.durationSec,
  });
}

class _RouteSnap {
  final _LonLat point;
  final double distanceFromRouteM;
  final double distanceAlongRouteM;
  final int segmentIndex;
  final double segmentT;

  const _RouteSnap({
    required this.point,
    required this.distanceFromRouteM,
    required this.distanceAlongRouteM,
    required this.segmentIndex,
    required this.segmentT,
  });
}

class _UnauthorizedMapbox implements Exception {
  final String where;
  _UnauthorizedMapbox(this.where);

  @override
  String toString() => 'Mapbox unauthorized ($where)';
}

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key});

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage>
    with TickerProviderStateMixin {
  String? _lastPaymentConfirmationSnackbarId;
  DateTime? _trackingStartedAt; // tracking start timestamp
  bool _isStartingTrip = false; // UX: start button state
  Timer? _meterTicker;
  DateTime? _lastMeterDebugAt;

  // Manual (GPS-style) mode when no booking is active
  final TextEditingController _manualFromCtrl = TextEditingController();
  final TextEditingController _manualToCtrl = TextEditingController();
  // --- Manual A→B autocomplete (Mapbox Geocoding) ---
  final FocusNode _fromFocus = FocusNode();
  final FocusNode _toFocus = FocusNode();
  Timer? _fromDebounce;
  Timer? _toDebounce;
  List<_PlaceSuggestion> _fromSuggestions = <_PlaceSuggestion>[];
  List<_PlaceSuggestion> _toSuggestions = <_PlaceSuggestion>[];
  mb.Point? _manualFromPoint;
  mb.Point? _manualToPoint;

  // Ride mode (driving vs waiting)
  bool _isWaiting = false;
  DateTime? _waitStartedAt;
  Duration _waitElapsed = Duration.zero;

  // Pricing (UI-only fallback; worker remains source of truth)
  static const double _fallbackStartFee = 3.0;
  static const double _fallbackPerKm =
      1.50; // placeholder until worker streams live rates
  static const double _fallbackWaitPerMin =
      40.0 / 60.0; // €40/h = €0.666.../min

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  List<BookingItem> _bookings = [];
  bool _loadingBookings = true;
  String? _bookingsError;
  final Set<String> _bookingActionInFlight = <String>{};
  final Map<String, String> _bookingStatusOverrides = <String, String>{};
  final Set<String> _deletedBookingIds = <String>{};
  final ValueNotifier<int> _bookingsUiVersion = ValueNotifier<int>(0);

  Timer? _bookingPollTimer; // auto-refresh bookings
  Future<void>? _bookingsRefreshInFlight;
  DateTime? _lastBookingsRefreshAt;
  DateTime? _lastStatusTriggeredRefreshAt;
  DateTime? _lastManualRefreshAt;
  bool _bookingsHubVisible = false;
  int? _activeBookingPollIntervalMs;
  static const Duration _bookingsPollIntervalFastList = Duration(seconds: 9);
  static const Duration _bookingsPollIntervalSafeLive = Duration(seconds: 25);
  static const Duration _bookingsMinRefreshIntervalFastList = Duration(
    seconds: 8,
  );
  static const Duration _bookingsMinRefreshIntervalSafeLive = Duration(
    seconds: 20,
  );
  static const Duration _manualRefreshCooldown = Duration(seconds: 4);
  static const Duration _statusRefreshCooldown = Duration(seconds: 8);
  int _activeBookingRefreshTimerCount = 0;

  // Boot splash (logo on dark background + loader)
  bool _bootSplashVisible = true;

  bool _showBootSplash = true; // alias for older/other UI refs
  bool _bootMinElapsed = false;
  bool _bootFirstLoadDone = false;
  DateTime? _bootStartedAt;

  // Active trip state
  String? _activeTripId;
  String? _activeDirectTripId;
  BookingItem? _activeBooking;
  bool _directRideActive = false;
  String? _directRideDestinationText;
  _LonLat? _directRideDestinationPoint;

  // Location tracking
  StreamSubscription<geo.Position>? _posSub;
  int _activeGeolocatorSubscriptionCount = 0;
  geo.Position? _lastPos;
  geo.Position? _startPos;
  double _kmDriven = 0.0;

  // Ping status
  String _lastPing = '—';
  int _pingCount = 0;

  // Map controller
  mb.MapboxMap? _map;
  mb.PointAnnotationManager? _driverPointManager;
  mb.PointAnnotationManager? _pinsPointManager;
  mb.PolylineAnnotationManager? _routeLineManager;
  String _activeMapStyleUri = '';

  mb.PointAnnotation? _driverMarker;
  mb.PointAnnotation? _pickupPin;
  mb.PointAnnotation? _dropoffPin;
  mb.PolylineAnnotation? _routeLineOutline;
  mb.PolylineAnnotation? _routeLine;
  String _driverMarkerIcon = 'triangle-15';
  late final Widget _stableMapWidget;
  String? _pendingMapStyleUri;
  DateTime? _lastMapWidgetBuildLogAt;
  DateTime? _lastDriverBuildLogAt;

  // Splash animations (premium boot feel)
  late final AnimationController _splashAnimCtrl;
  late final Animation<double> _splashPulse;

  // Active HUD pulse (only meaningful when tracking)
  late final AnimationController _activePulseCtrl;
  late final Animation<double> _activePulse;
  // UI/Camera
  bool _followCar = false;
  _CameraMode _cameraMode = _CameraMode.overview;
  MapThemeMode? _mapThemeOverride;
  bool _navigationWakelockEnabled = false;
  bool _hasSwitchedToFollow = false;
  double _lastKnownBearing = 0.0;
  bool _allowOverviewCamera = false;
  DateTime? _lastFollowCameraAt;
  bool _followCameraInFlight = false;

  // Route stats
  List<_LonLat> _routeCoords = [];
  double? _routeKm;
  int? _routeDurationSec;
  String _lastPinsDrawSignature = '';
  DateTime? _lastPinsDrawAt;
  String _lastRouteDrawSignature = '';
  DateTime? _lastRouteDrawAt;
  static const Duration _routeDrawDebounce = Duration(seconds: 2);
  _RideRoutePhase _routePhase = _RideRoutePhase.trip;
  List<_NavStep> _routeSteps = const <_NavStep>[];
  int _nextStepIndex = 0;
  String? _nextNavInstruction;
  String? _nextNavStreet;
  double? _nextNavDistanceM;
  String? _nextNavType;
  String? _nextNavModifier;
  bool _navStepsLoading = false;
  double _uiArrowBearing = 0.0;
  _RouteSnap? _lastRouteSnap;
  bool _offRouteLikely = false;
  int _offRouteHitCount = 0;
  int _routeCleanupEpoch = 0;
  int _mapRedrawCountThisMinute = 0;
  int _routeRedrawCountThisMinute = 0;
  Timer? _renderDebugWindowTimer;

  void _resetNavProgressState({bool clearRoute = false}) {
    if (clearRoute) {
      _routeCoords = [];
      _routeKm = null;
      _routeDurationSec = null;
    }
    _routeSteps = const <_NavStep>[];
    _nextStepIndex = 0;
    _nextNavInstruction = null;
    _nextNavStreet = null;
    _nextNavDistanceM = null;
    _nextNavType = null;
    _nextNavModifier = null;
    _lastRouteSnap = null;
    _offRouteHitCount = 0;
    _offRouteLikely = false;
  }

  bool _isRouteTaskStillValid({
    required int epoch,
    String? expectedBookingId,
    bool requireDirectRide = false,
  }) {
    if (epoch != _routeCleanupEpoch) return false;
    if (requireDirectRide && !_directRideActive) return false;
    if (expectedBookingId != null) {
      final activeId = _activeBooking?.bookingId;
      if (activeId == null || activeId != expectedBookingId) return false;
    }
    return true;
  }

  Future<void> _clearActiveRouteAndNavigationState({
    required String reason,
    String? bookingId,
    bool clearActiveSelection = true,
  }) async {
    final activeBookingId = _activeBooking?.bookingId;
    final hasPolylineBefore = _routeLine != null || _routeLineOutline != null;
    final routeCoordsBefore = _routeCoords.length;
    final navStepsBefore = _routeSteps.length;
    if (!clearActiveSelection &&
        !hasPolylineBefore &&
        routeCoordsBefore == 0 &&
        navStepsBefore == 0) {
      return;
    }

    try {
      if (_routeLineManager != null) {
        if (_routeLineOutline != null) {
          await _routeLineManager!.delete(_routeLineOutline!);
        }
        if (_routeLine != null) {
          await _routeLineManager!.delete(_routeLine!);
        }
      }
      _routeLineOutline = null;
      _routeLine = null;

      if (_pinsPointManager != null) {
        if (_pickupPin != null) {
          await _pinsPointManager!.delete(_pickupPin!);
        }
        if (_dropoffPin != null) {
          await _pinsPointManager!.delete(_dropoffPin!);
        }
      }
      _pickupPin = null;
      _dropoffPin = null;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _routeCleanupEpoch++;
      _resetNavProgressState(clearRoute: true);
      _routePhase = _RideRoutePhase.trip;
      _navStepsLoading = false;
      _cameraMode = _CameraMode.overview;
      _hasSwitchedToFollow = false;
      _followCar = false;
      _allowOverviewCamera = false;
      if (clearActiveSelection) {
        _activeTripId = null;
        _activeDirectTripId = null;
        _activeBooking = null;
        _directRideActive = false;
        _directRideDestinationText = null;
        _directRideDestinationPoint = null;
        _lastPing = '—';
        _pingCount = 0;
        _kmDriven = 0.0;
        _trackingStartedAt = null;
        _isWaiting = false;
        _waitStartedAt = null;
        _waitElapsed = Duration.zero;
      }
    });
    _setNavigationWakelock(false);
    await _applyMapStyleForMode();
    if (!_liveRideActive) {
      _startBookingPolling(reason: 'route_state_cleared');
    }
  }

  bool _isClosedRideStatus(String? rawStatus) {
    final s = (rawStatus ?? '').trim().toUpperCase();
    return s == 'COMPLETED' || s == 'CANCELLED' || s == 'DELETED';
  }

  String? _effectiveStatusFor(BookingItem b) {
    return _bookingStatusOverrides[b.bookingId] ?? b.status;
  }

  List<BookingItem> get _visibleBookings => _bookings
      .where((b) => !_deletedBookingIds.contains(b.bookingId))
      .where((b) => !_isClosedRideStatus(_effectiveStatusFor(b)))
      .toList();

  void _markBookingsUiDirty() {
    _bookingsUiVersion.value = _bookingsUiVersion.value + 1;
  }

  bool get _mapSupported => !kIsWindows && !kIsWeb;
  bool get kIsWindows => !kIsWeb && Platform.isWindows;
  bool _isAssetRef(String v) => v.trim().toLowerCase().startsWith('assets/');

  void _setNavigationWakelock(bool enabled) {
    if (_navigationWakelockEnabled == enabled) return;
    _navigationWakelockEnabled = enabled;
    final op = enabled ? WakelockPlus.enable() : WakelockPlus.disable();
    unawaited(
      op.catchError((Object e, StackTrace st) {
        debugPrint('[WAKELOCK][WARN] enabled=$enabled error=$e');
      }),
    );
  }

  void _onAppLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Widget _tenantLogo({
    required double height,
    BoxFit fit = BoxFit.contain,
    Widget? fallback,
  }) {
    return ValueListenableBuilder<BusinessSettingsState>(
      valueListenable: businessSettingsNotifier,
      builder: (context, s, _) {
        final ref = s.logoAssetPath.trim().isNotEmpty
            ? s.logoAssetPath.trim()
            : kFluxidiLogoAsset;
        if (_isAssetRef(ref)) {
          return Image.asset(
            ref,
            height: height,
            fit: fit,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) =>
                fallback ??
                Text(
                  kCompanyName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
          );
        }
        if (kIsWeb) {
          return Image.network(
            ref,
            height: height,
            fit: fit,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) =>
                fallback ??
                const Icon(Icons.local_taxi, size: 72, color: Colors.white70),
          );
        }
        return Image.file(
          File(ref),
          height: height,
          fit: fit,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) =>
              fallback ??
              const Icon(Icons.local_taxi, size: 72, color: Colors.white70),
        );
      },
    );
  }

  // ===============================
  // JSON helpers (local)
  // ===============================
  dynamic _getNested(dynamic root, List<String> path) {
    dynamic cur = root;
    for (final k in path) {
      if (cur is Map && cur.containsKey(k)) {
        cur = cur[k];
      } else {
        return null;
      }
    }
    return cur;
  }

  int? _toIntOrNullLocal(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  // Best-effort: hydrate missing booking fields via Tracking API Worker /track/booking (GET).
  // This endpoint exists on fluxidi-tracking-api (V2):
  //   GET /track/booking?booking_id=TEST-001
  // and returns pickup/dropoff + session status + last ping.
  Future<void> _hydrateActiveBookingDetails(String bookingId) async {
    try {
      final uri = Uri.parse(
        '$kWorkerBaseUrl$kGetBookingPath?booking_id=${Uri.encodeComponent(bookingId)}',
      );
      final res = await http
          .get(uri, headers: _headers(admin: true))
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['ok'] != true) return;

      // Tracking API returns flat fields
      final pickup = decoded['pickup']?.toString();
      final dropoff = decoded['dropoff']?.toString();
      final sessionId = decoded['session_id']?.toString();
      final status = decoded['status']?.toString();

      if (!mounted) return;

      setState(() {
        if (_activeBooking != null && _activeBooking!.bookingId == bookingId) {
          _activeBooking = _activeBooking!.copyWith(
            from: pickup ?? _activeBooking!.from,
            to: dropoff ?? _activeBooking!.to,
            sessionId: sessionId ?? _activeBooking!.sessionId,
            status: status ?? _activeBooking!.status,
            details: <String, dynamic>{
              ..._activeBooking!.details,
              'tracking_booking': decoded,
            },
          );
        }

        final idx = _bookings.indexWhere((x) => x.bookingId == bookingId);
        if (idx >= 0) {
          _bookings[idx] = _bookings[idx].copyWith(
            from: pickup ?? _bookings[idx].from,
            to: dropoff ?? _bookings[idx].to,
            sessionId: sessionId ?? _bookings[idx].sessionId,
            status: status ?? _bookings[idx].status,
            details: <String, dynamic>{
              ..._bookings[idx].details,
              'tracking_booking': decoded,
            },
          );
        }
      });
    } catch (_) {
      // silent best-effort
    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint('[MAP][HOSTING_MODE] mode=HC textureView=true');
    _stableMapWidget = mb.MapWidget(
      key: const ValueKey('mapbox_map'),
      onMapCreated: _onMapCreated,
      textureView: true,
      androidHostingMode: mb.AndroidPlatformViewHostingMode.HC,
      styleUri: 'mapbox://styles/mapbox/streets-v12',
      cameraOptions: mb.CameraOptions(
        center: _mbPoint(3.62, 50.78),
        zoom: 12.0,
      ),
    );
    appLanguageNotifier.addListener(_onAppLanguageChanged);
    fluxidiPendingPaymentNotifier.addListener(_onPendingPaymentStatusChanged);

    _splashAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _splashPulse = CurvedAnimation(
      parent: _splashAnimCtrl,
      curve: Curves.easeInOut,
    );

    _activePulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
    _activePulse = CurvedAnimation(
      parent: _activePulseCtrl,
      curve: Curves.easeInOut,
    );

    _bootStartedAt = DateTime.now();
    // Minimum splash duration so it feels intentional (not a flicker)
    // Christophe wants it to linger a bit longer for a more premium feel.
    Timer(const Duration(milliseconds: 8000), () {
      if (!mounted) return;
      _bootMinElapsed = true;
      _maybeHideBootSplash();
    });
    _refreshBookings(trigger: 'init_boot');
    _startBookingPolling(reason: 'init');
    _renderDebugWindowTimer?.cancel();
    _renderDebugWindowTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      debugPrint(
        '[RIDES][DEBUG_COUNTERS][MINUTE] bookingTimers=$_activeBookingRefreshTimerCount geolocatorSubs=$_activeGeolocatorSubscriptionCount mapRedrawPerMin=$_mapRedrawCountThisMinute routeRedrawPerMin=$_routeRedrawCountThisMinute',
      );
      _mapRedrawCountThisMinute = 0;
      _routeRedrawCountThisMinute = 0;
    });
  }

  // ---------------------------------------------------------------------------
  // Mollie return-to-app + payment finalization fallback
  // ---------------------------------------------------------------------------
  // The deep-link listener, lifecycle observer, and /pay/status reconciliation
  // now live in `PaymentReturnCoordinator` (lib/payment_return.dart) and are
  // started once from main(), so they don't depend on this State being mounted.
  void _onPendingPaymentStatusChanged() {
    final pending = fluxidiPendingPaymentNotifier.value;
    if (!mounted || pending == null) return;
    if (pending.status != FluxidiPaymentStatus.confirmed) return;
    if (_lastPaymentConfirmationSnackbarId == pending.paymentBookingId) return;
    _lastPaymentConfirmationSnackbarId = pending.paymentBookingId;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            nl: 'Betaling bevestigd. Je boeking is bevestigd.',
            en: 'Payment confirmed. Your booking is confirmed.',
            fr: 'Paiement confirme. Votre reservation est confirmee.',
            es: 'Pago confirmado. Tu reserva esta confirmada.',
          ),
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Preload the splash logo so we don't hit the errorBuilder fallback on first frame.
    // If the asset path is wrong, Flutter will throw during precache and we'll still fall back.
    unawaited(
      precacheImage(AssetImage(kFluxidiLogoAsset), context).catchError((_) {}),
    );
  }

  @override
  void dispose() {
    debugPrint('[MAP][DISPOSE] mounted=$mounted style=$_activeMapStyleUri');
    _setNavigationWakelock(false);
    appLanguageNotifier.removeListener(_onAppLanguageChanged);
    fluxidiPendingPaymentNotifier.removeListener(
      _onPendingPaymentStatusChanged,
    );
    _bookingsUiVersion.dispose();
    _splashAnimCtrl.dispose();
    _activePulseCtrl.dispose();
    _stopMeterTicker();
    _stopTrackingInternal();
    _stopBookingPolling(reason: 'dispose');
    _renderDebugWindowTimer?.cancel();
    _renderDebugWindowTimer = null;
    _manualFromCtrl.dispose();
    _manualToCtrl.dispose();
    _directRideDestinationText = null;
    _directRideDestinationPoint = null;
    _fromDebounce?.cancel();
    _toDebounce?.cancel();
    _fromFocus.dispose();
    _toFocus.dispose();
    super.dispose();
  }

  Map<String, String> _headers({bool admin = false}) {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (admin && kAdminToken.trim().isNotEmpty) {
      h['x-admin-token'] = kAdminToken.trim();
    }
    return h;
  }

  void _startBookingPolling({required String reason}) {
    if (_liveRideActive) {
      _stopBookingPolling(reason: 'tracking_started');
      return;
    }
    final fastListMode = _bookingsHubVisible && !_liveRideActive;
    final interval = fastListMode
        ? _bookingsPollIntervalFastList
        : _bookingsPollIntervalSafeLive;
    final mode = fastListMode ? 'fast_list' : 'safe_live';
    if (_bookingPollTimer != null &&
        _activeBookingPollIntervalMs == interval.inMilliseconds) {
      return;
    }
    _bookingPollTimer?.cancel();
    debugPrint(
      '[RIDES][POLL][MODE] mode=$mode intervalMs=${interval.inMilliseconds}',
    );
    _bookingPollTimer = Timer.periodic(interval, (_) {
      if (!mounted) return;
      if (_liveRideActive) return;
      _refreshBookings(trigger: 'periodic_poll');
    });
    _activeBookingRefreshTimerCount = 1;
    _activeBookingPollIntervalMs = interval.inMilliseconds;
    debugPrint(
      '[RIDES][POLL][START] reason=$reason activeTimers=$_activeBookingRefreshTimerCount',
    );
  }

  void _stopBookingPolling({required String reason}) {
    if (_bookingPollTimer == null) return;
    _bookingPollTimer?.cancel();
    _bookingPollTimer = null;
    _activeBookingRefreshTimerCount = 0;
    _activeBookingPollIntervalMs = null;
    debugPrint(
      '[RIDES][POLL][STOP] reason=$reason activeTimers=$_activeBookingRefreshTimerCount',
    );
  }

  Future<void> _refreshBookings({
    bool force = false,
    String trigger = 'unknown',
  }) async {
    if (!mounted) return;
    if (_bookingsRefreshInFlight != null) {
      debugPrint('[RIDES][REFRESH][SKIP] reason=in_flight trigger=$trigger');
      return _bookingsRefreshInFlight!;
    }
    final now = DateTime.now();
    final isManualTrigger =
        trigger == 'drawer_manual' || trigger == 'list_manual';
    if (force && isManualTrigger && _lastManualRefreshAt != null) {
      final elapsed = now.difference(_lastManualRefreshAt!);
      if (elapsed < _manualRefreshCooldown) {
        debugPrint(
          '[RIDES][REFRESH][SKIP] reason=manual_cooldown trigger=$trigger elapsedMs=${elapsed.inMilliseconds}',
        );
        return;
      }
    }
    if (force && isManualTrigger) {
      _lastManualRefreshAt = now;
    }

    final fastListMode = _bookingsHubVisible && !_liveRideActive;
    final minInterval = fastListMode
        ? _bookingsMinRefreshIntervalFastList
        : _bookingsMinRefreshIntervalSafeLive;
    final minIntervalReason = fastListMode
        ? 'min_interval_fast_list'
        : 'min_interval_safe_live';
    if (!force && _lastBookingsRefreshAt != null) {
      final elapsed = now.difference(_lastBookingsRefreshAt!);
      if (elapsed < minInterval) {
        debugPrint(
          '[RIDES][REFRESH][SKIP] reason=$minIntervalReason trigger=$trigger elapsedMs=${elapsed.inMilliseconds}',
        );
        return;
      }
    }
    if (force &&
        trigger == 'status_change' &&
        _lastStatusTriggeredRefreshAt != null) {
      final elapsed = now.difference(_lastStatusTriggeredRefreshAt!);
      if (elapsed < _statusRefreshCooldown) {
        debugPrint(
          '[RIDES][REFRESH][SKIP] reason=status_cooldown trigger=$trigger elapsedMs=${elapsed.inMilliseconds}',
        );
        return;
      }
    }
    if (force && trigger == 'status_change') {
      _lastStatusTriggeredRefreshAt = now;
    }
    _lastBookingsRefreshAt = now;
    final task = _performRefreshBookings(trigger: trigger);
    _bookingsRefreshInFlight = task;
    try {
      await task;
    } finally {
      _bookingsRefreshInFlight = null;
    }
  }

  Future<void> _performRefreshBookings({required String trigger}) async {
    if (!mounted) return;
    setState(() {
      _loadingBookings = true;
      _bookingsError = null;
    });
    _markBookingsUiDirty();

    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final primaryUri = Uri.parse(
        '$kBookingBaseUrl$kListBookingsPath?limit=50&t=$ts',
      );
      debugPrint('[RIDES][REFRESH][REQ] trigger=$trigger GET $primaryUri');
      final res = await http.get(primaryUri, headers: _headers(admin: true));
      debugPrint(
        '[RIDES][REFRESH][RES] code=${res.statusCode} body=${res.body}',
      );

      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid response');
      }

      // Worker variants:
      // - tracking-api V2: { ok, count, bookings:[...] }
      // - booking-worker tracking bridge: { ok, items:[...] }
      final raw =
          (decoded['bookings'] as List<dynamic>? ??
          decoded['items'] as List<dynamic>? ??
          const []);
      final prevStatusById = <String, String?>{
        for (final b in _bookings) b.bookingId: _effectiveStatusFor(b),
      };
      final items = raw.whereType<Map<String, dynamic>>().map((j) {
        final parsed = BookingItem.fromJson(j);
        final apiStatus = parsed.status?.trim();
        final mergedStatus = (apiStatus != null && apiStatus.isNotEmpty)
            ? apiStatus
            : (prevStatusById[parsed.bookingId] ??
                  _bookingStatusOverrides[parsed.bookingId]);
        return mergedStatus == null
            ? parsed
            : parsed.copyWith(status: mergedStatus);
      }).toList();

      final apiReturnedIds = items.map((e) => e.bookingId).toSet();
      _deletedBookingIds.removeWhere((id) => !apiReturnedIds.contains(id));
      for (final b in items) {
        final apiStatus = b.status?.trim();
        if (apiStatus != null && apiStatus.isNotEmpty) {
          _bookingStatusOverrides[b.bookingId] = apiStatus;
        }
      }

      final parsedStatuses = items
          .map(
            (b) =>
                '${b.shortId}:${(_effectiveStatusFor(b) ?? 'null').toUpperCase()}',
          )
          .join(', ');
      final visibleStatuses = items
          .where((b) => !_deletedBookingIds.contains(b.bookingId))
          .where((b) => !_isClosedRideStatus(_effectiveStatusFor(b)))
          .map(
            (b) =>
                '${b.shortId}:${(_effectiveStatusFor(b) ?? 'null').toUpperCase()}',
          )
          .join(', ');
      final visibleCount = items
          .where((b) => !_deletedBookingIds.contains(b.bookingId))
          .where((b) => !_isClosedRideStatus(_effectiveStatusFor(b)))
          .length;
      debugPrint(
        '[RIDES][REFRESH][PARSED] total=${items.length} visible=$visibleCount all=[$parsedStatuses] visibleOnly=[$visibleStatuses]',
      );

      if (!mounted) return;
      setState(() {
        _bookings = items;
        _loadingBookings = false;
      });
      _markBookingsUiDirty();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bookingsError = e.toString();
        _loadingBookings = false;
      });
      _markBookingsUiDirty();
    } finally {
      _markBootFirstLoadDone();
    }
  }

  /// Open a booking in "ride preview" mode:
  /// - show route in OVERVIEW
  /// - do NOT create a trip_id yet
  /// - driver presses START on the map to begin tracking + streetview/follow cam
  Future<void> _goToRide(BookingItem b) async {
    try {
      // We are typically called from the Bookings Hub page.
      // UX: return to the main map/cockpit immediately.
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }

      if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
        Navigator.of(context).pop();
      }

      setState(() {
        _activeBooking = b;
        _activeTripId = null;
        _activeDirectTripId = null;
        _directRideActive = false;
        _directRideDestinationText = null;
        _directRideDestinationPoint = null;
        _isStartingTrip = false;
        _routePhase = _RideRoutePhase.toPickup;

        _kmDriven = 0.0;
        _pingCount = 0;
        _lastPing = '—';

        _resetNavProgressState(clearRoute: true);

        _cameraMode = _CameraMode.overview;
        _hasSwitchedToFollow = false;
        _followCar = false;
        _allowOverviewCamera = true;

        _isWaiting = false;
        _waitStartedAt = null;
        _waitElapsed = Duration.zero;

        _trackingStartedAt = null;
      });
      _setNavigationWakelock(true);
      await _applyMapStyleForMode();

      await _hydrateActiveBookingDetails(b.bookingId);
      await _hydrateActiveBookingPrice(b.bookingId);
      await _ensureLocationPermission();
      if (_lastPos == null) {
        try {
          final pos = await geo.Geolocator.getCurrentPosition(
            desiredAccuracy: geo.LocationAccuracy.best,
          );
          if (mounted) {
            setState(() => _lastPos = pos);
          } else {
            _lastPos = pos;
          }
        } catch (_) {
          // best-effort: fallback route logic below remains safe
        }
      }

      // Start location stream for map + marker (pings are guarded by _activeTripId).
      _startTrackingInternal();

      final bb = _activeBooking ?? b;
      await _buildOverviewRoute(bb);

      // Stay in overview mode after opening a booking.
      // Driver explicitly presses START to begin an active tracking session & follow-cam.

      if (mounted) setState(() => _isStartingTrip = false);
    } catch (e) {
      _toast('Open ride failed: $e');
    }
  }

  void _clearActiveSelection() {
    _stopTrackingInternal();
    unawaited(
      _clearActiveRouteAndNavigationState(
        reason: 'manual_clear_selection',
        bookingId: _activeBooking?.bookingId,
        clearActiveSelection: true,
      ),
    );
  }

  Future<void> _startTrip(BookingItem b) async {
    try {
      if (mounted) setState(() => _isStartingTrip = true);

      // UX rule: Start in Drawer → Drawer closes → Map becomes primary focus
      if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
        Navigator.of(context).pop();
      }
      final uri = Uri.parse('$kWorkerBaseUrl$kStartTripPath');
      final payload = {
        'booking_id': b.bookingId,
        // Optional context (helps debugging / future UI)
        'pickup': (b.from ?? '').toString(),
        'dropoff': (b.to ?? '').toString(),
      };

      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }

      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final sessionId = (j['session_id'] ?? j['sessionId'] ?? '').toString();
      if (sessionId.isEmpty)
        throw Exception('No session_id returned by Worker.');

      setState(() {
        _activeTripId = sessionId;
        _activeDirectTripId = null;
        _activeBooking = b;
        _directRideActive = false;
        _directRideDestinationText = null;
        _directRideDestinationPoint = null;
        _routePhase = _RideRoutePhase.trip;
        _kmDriven = 0.0;
        _trackingStartedAt = DateTime.now();
        _pingCount = 0;
        _lastPing = '—';

        _resetNavProgressState(clearRoute: true);

        _cameraMode = _CameraMode.follow;
        _hasSwitchedToFollow = true;
        _followCar = true;
        _allowOverviewCamera = false;

        _isWaiting = false;
        _waitStartedAt = null;
        _waitElapsed = Duration.zero;
      });
      _setNavigationWakelock(true);
      await _applyMapStyleForMode();

      // Fetch canonical booking details (incl. fixed price) for display
      await _hydrateActiveBookingDetails(b.bookingId);
      await _hydrateActiveBookingPrice(b.bookingId);

      await _ensureLocationPermission();

      _startTrackingInternal();
      _startMeterTicker();
      await _forceFollowCameraNow(caller: 'start_trip');
      final bb = _activeBooking ?? b;
      await _buildNavRouteToDestination(bb);
    } catch (e) {
      if (mounted) setState(() => _isStartingTrip = false);
      _toast('Start failed: $e');
    }
  }

  Future<void> _hydrateActiveBookingPrice(String bookingId) async {
    // Pricing is owned by the BOOKING Worker (not the tracking Worker).
    // If the booking isn't known there yet (e.g. TEST-xxx created only in tracking),
    // we just skip without breaking tracking.
    try {
      final uri = Uri.parse('$kBookingBaseUrl$kTrackingBookingPath');
      final res = await http
          .post(
            uri,
            headers: _headers(admin: true),
            body: jsonEncode({'booking_id': bookingId}),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return;

      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['ok'] != true) return;

      bool isEmptyHydrationValue(dynamic value) {
        if (value == null) return true;
        if (value is String) return value.trim().isEmpty;
        if (value is Map) return value.isEmpty;
        if (value is Iterable) return value.isEmpty;
        return false;
      }

      Map<String, dynamic> mergeNonEmptyDetails(
        Map<String, dynamic> existing,
        Map<String, dynamic> incoming,
      ) {
        final next = <String, dynamic>{...existing};
        for (final entry in incoming.entries) {
          final incomingValue = entry.value;
          if (isEmptyHydrationValue(incomingValue)) continue;
          final existingValue = next[entry.key];
          if (existingValue is Map && incomingValue is Map) {
            next[entry.key] = mergeNonEmptyDetails(
              Map<String, dynamic>.from(existingValue),
              Map<String, dynamic>.from(incomingValue),
            );
          } else {
            next[entry.key] = incomingValue;
          }
        }
        return next;
      }

      if (!mounted) return;
      setState(() {
        if (_activeBooking != null && _activeBooking!.bookingId == bookingId) {
          _activeBooking = _activeBooking!.copyWith(
            details: mergeNonEmptyDetails(_activeBooking!.details, j),
          );
        }
      });

      final record = (j['record'] is Map)
          ? (j['record'] as Map).cast<String, dynamic>()
          : null;
      final quoteSource = j['quote'] ?? record?['quote'];
      final quote = (quoteSource is Map)
          ? quoteSource.cast<String, dynamic>()
          : null;
      final pricing = (quote != null && quote['pricing'] is Map)
          ? (quote['pricing'] as Map).cast<String, dynamic>()
          : null;

      num? _pickNum(dynamic v) {
        if (v is num) return v;
        if (v is String) return num.tryParse(v.replaceAll(',', '.'));
        return null;
      }

      // Booking worker /quote shapes we've used across versions:
      // pricing: { price_incl_vat | total_price | total | amount | eur | price }
      // quote:   { price | total | total_price | amount | eur }
      final dynamic pMap = pricing;
      final num? price = (pMap is Map<String, dynamic>)
          ? (_pickNum(pMap['price_incl_vat']) ??
                _pickNum(pMap['total_price']) ??
                _pickNum(pMap['total']) ??
                _pickNum(pMap['price']) ??
                _pickNum(pMap['amount']) ??
                _pickNum(pMap['eur']))
          : null;

      final num? fallbackFromQuote =
          _pickNum(quote?['price']) ??
          _pickNum(quote?['total_price']) ??
          _pickNum(quote?['total']) ??
          _pickNum(quote?['amount']) ??
          _pickNum(quote?['eur']);

      final num? resolved = price ?? fallbackFromQuote;
      if (resolved == null) return;

      if (!mounted) return;
      setState(() {
        if (_activeBooking != null && _activeBooking!.bookingId == bookingId) {
          _activeBooking = _activeBooking!.copyWith(
            price: resolved,
            currency: 'EUR',
          );
        }
      });
    } catch (_) {
      // silent
    }
  }

  Future<void> _setBookingStatus(BookingItem b, String status) async {
    if (!mounted) return;
    final bookingId = b.bookingId;
    setState(() => _bookingActionInFlight.add(bookingId));
    _markBookingsUiDirty();
    try {
      final uri = Uri.parse(
        '$kBookingBaseUrl$kUpdateBookingStatusPath/${Uri.encodeComponent(bookingId)}/status',
      );
      final payload = {'booking_id': bookingId, 'status': status};
      debugPrint(
        '[RIDES][STATUS][REQ] url=$uri payload=${jsonEncode(payload)}',
      );
      var statusPersistedOnWorker = false;
      try {
        final res = await http
            .post(
              uri,
              headers: _headers(admin: true),
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 12));
        debugPrint(
          '[RIDES][STATUS][RES] code=${res.statusCode} body=${res.body}',
        );
        dynamic decoded;
        try {
          decoded = jsonDecode(res.body);
        } catch (_) {
          decoded = null;
        }
        final ok = decoded is Map ? decoded['ok'] == true : false;
        if (res.statusCode == 200 && ok) {
          statusPersistedOnWorker = true;
        } else {
          throw Exception('HTTP ${res.statusCode}: ${res.body}');
        }
      } catch (e) {
        // Keep safe compatibility with worker versions that don't expose this endpoint.
        debugPrint('[RIDES][STATUS][WARN] fallback-local-only reason=$e');
      }

      if (!mounted) return;
      setState(() {
        _bookingStatusOverrides[bookingId] = status;
        final idx = _bookings.indexWhere((x) => x.bookingId == bookingId);
        if (idx >= 0) {
          _bookings[idx] = _bookings[idx].copyWith(status: status);
        }
        if (_activeBooking?.bookingId == bookingId) {
          _activeBooking = _activeBooking!.copyWith(status: status);
        }
      });
      final normalizedStatus = status.trim().toUpperCase();
      final shouldRouteCleanup =
          _activeBooking?.bookingId == bookingId &&
          !_liveRideActive &&
          (normalizedStatus == 'COMPLETED' ||
              normalizedStatus == 'CANCELLED' ||
              normalizedStatus == 'DELETED');
      if (shouldRouteCleanup) {
        _stopTrackingInternal();
        _stopMeterTicker();
        await _clearActiveRouteAndNavigationState(
          reason: normalizedStatus.toLowerCase(),
          bookingId: bookingId,
          clearActiveSelection: true,
        );
      }
      _markBookingsUiDirty();
      _toast('✅ $status: ${b.shortId}');
      if (!statusPersistedOnWorker) {
        // Fallback for tracking-worker variants that have no status endpoint:
        // removing from tracking index makes closed rides persistently disappear
        // from the "available rides" source after app restart.
        await _archiveClosedRideByDelete(bookingId: bookingId, status: status);
      }
      await _debugFetchBookingSnapshot(
        bookingId: bookingId,
        contextLabel: 'STATUS_AFTER_WRITE',
      );
      await _refreshBookings(force: true, trigger: 'status_change');
    } catch (e) {
      _toast('❌ Status update failed: $e');
    } finally {
      if (!mounted) return;
      setState(() => _bookingActionInFlight.remove(bookingId));
      _markBookingsUiDirty();
    }
  }

  Future<void> _deleteBooking(BookingItem b) async {
    if (!mounted) return;
    final bookingId = b.bookingId;
    setState(() => _bookingActionInFlight.add(bookingId));
    _markBookingsUiDirty();
    try {
      final uri = Uri.parse(
        '$kBookingBaseUrl$kDeleteBookingPath/${Uri.encodeComponent(bookingId)}/delete',
      );
      final payload = {'booking_id': bookingId};
      debugPrint(
        '[RIDES][DELETE][REQ] url=$uri payload=${jsonEncode(payload)}',
      );

      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));
      debugPrint(
        '[RIDES][DELETE][RES] code=${res.statusCode} body=${res.body}',
      );

      final j = jsonDecode(res.body);
      if (res.statusCode != 200 || (j is Map && j['ok'] != true)) {
        throw Exception('Worker error: ${res.statusCode} ${res.body}');
      }

      if (!mounted) return;
      setState(() {
        _deletedBookingIds.add(bookingId);
        _bookingStatusOverrides[bookingId] = 'DELETED';
        _bookings.removeWhere((x) => x.bookingId == bookingId);
      });
      if (_activeBooking?.bookingId == bookingId) {
        _stopTrackingInternal();
        _stopMeterTicker();
        await _clearActiveRouteAndNavigationState(
          reason: 'delete',
          bookingId: bookingId,
          clearActiveSelection: true,
        );
      }
      if (!_liveRideActive) _setNavigationWakelock(false);
      _markBookingsUiDirty();
      _toast('🗑️ Verwijderd: ${b.shortId}');
      await _debugFetchBookingSnapshot(
        bookingId: bookingId,
        contextLabel: 'DELETE_AFTER_WRITE',
      );
      await _refreshBookings(force: true, trigger: 'delete_action');
    } catch (e) {
      _toast('❌ Delete failed: $e');
    } finally {
      if (!mounted) return;
      setState(() => _bookingActionInFlight.remove(bookingId));
      _markBookingsUiDirty();
    }
  }

  Future<void> _confirmDelete(BookingItem b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rit verwijderen?'),
        content: Text(
          'This will remove the booking from the list (KV).\n\nID: ${b.bookingId}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, delete'),
          ),
        ],
      ),
    );
    if (ok == true) await _deleteBooking(b);
  }

  Future<void> _archiveClosedRideByDelete({
    required String bookingId,
    required String status,
  }) async {
    try {
      final uri = Uri.parse(
        '$kBookingBaseUrl$kDeleteBookingPath/${Uri.encodeComponent(bookingId)}/delete',
      );
      final payload = {'booking_id': bookingId};
      debugPrint(
        '[RIDES][STATUS->DELETE][REQ] status=$status url=$uri payload=${jsonEncode(payload)}',
      );
      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));
      debugPrint(
        '[RIDES][STATUS->DELETE][RES] code=${res.statusCode} body=${res.body}',
      );
      dynamic decoded;
      try {
        decoded = jsonDecode(res.body);
      } catch (_) {
        decoded = null;
      }
      final ok = decoded is Map ? decoded['ok'] == true : false;
      if (res.statusCode == 200 && ok) {
        if (!mounted) return;
        setState(() {
          _deletedBookingIds.add(bookingId);
          _bookingStatusOverrides[bookingId] = 'DELETED';
          _bookings.removeWhere((x) => x.bookingId == bookingId);
        });
        _markBookingsUiDirty();
      }
    } catch (e) {
      debugPrint('[RIDES][STATUS->DELETE][WARN] $e');
    }
  }

  Future<void> _debugFetchBookingSnapshot({
    required String bookingId,
    required String contextLabel,
  }) async {
    try {
      final uri = Uri.parse(
        '$kBookingBaseUrl/bookings/${Uri.encodeComponent(bookingId)}',
      );
      final res = await http
          .get(uri, headers: _headers(admin: true))
          .timeout(const Duration(seconds: 12));
      debugPrint(
        '[RIDES][$contextLabel][SNAPSHOT] url=$uri code=${res.statusCode} body=${res.body}',
      );
    } catch (e) {
      debugPrint('[RIDES][$contextLabel][SNAPSHOT][WARN] $e');
    }
  }

  Future<Map<String, dynamic>> _fetchPaymentFieldsForHistory(
    String bookingId,
  ) async {
    Map<String, dynamic> asMap(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    List<dynamic> asList(dynamic value) => value is List ? value : const [];
    String? text(dynamic value) {
      final s = value?.toString().trim();
      if (s == null || s.isEmpty || s.toLowerCase() == 'null') return null;
      return s;
    }

    Map<String, dynamic> parsePayment(dynamic rootRaw) {
      final root = asMap(rootRaw);
      final data = asMap(root['data']);
      final record = asMap(root['record']);
      final booking = asMap(root['booking']);
      final dataRecord = asMap(data['record']);
      final dataBooking = asMap(data['booking']);
      final recordBooking = asMap(record['booking']);
      final dataRecordBooking = asMap(dataRecord['booking']);

      final paymentStatus = text(
        root['payment_status'] ??
            root['paymentStatus'] ??
            record['payment_status'] ??
            record['paymentStatus'] ??
            recordBooking['payment_status'] ??
            recordBooking['paymentStatus'] ??
            booking['payment_status'] ??
            booking['paymentStatus'] ??
            data['payment_status'] ??
            data['paymentStatus'] ??
            dataRecord['payment_status'] ??
            dataRecord['paymentStatus'] ??
            dataBooking['payment_status'] ??
            dataBooking['paymentStatus'] ??
            dataRecordBooking['payment_status'] ??
            dataRecordBooking['paymentStatus'],
      );
      final paidAt = text(
        root['paid_at'] ??
            root['paidAt'] ??
            record['paid_at'] ??
            record['paidAt'] ??
            booking['paid_at'] ??
            booking['paidAt'] ??
            data['paid_at'] ??
            data['paidAt'] ??
            dataRecord['paid_at'] ??
            dataRecord['paidAt'] ??
            dataBooking['paid_at'] ??
            dataBooking['paidAt'],
      );
      final paymentProvider = text(
        root['payment_provider'] ??
            root['paymentProvider'] ??
            record['payment_provider'] ??
            record['paymentProvider'] ??
            booking['payment_provider'] ??
            booking['paymentProvider'] ??
            data['payment_provider'] ??
            data['paymentProvider'] ??
            dataRecord['payment_provider'] ??
            dataRecord['paymentProvider'] ??
            dataBooking['payment_provider'] ??
            dataBooking['paymentProvider'],
      );
      final paymentId = text(
        root['payment_id'] ??
            root['paymentId'] ??
            record['payment_id'] ??
            record['paymentId'] ??
            booking['payment_id'] ??
            booking['paymentId'] ??
            data['payment_id'] ??
            data['paymentId'] ??
            dataRecord['payment_id'] ??
            dataRecord['paymentId'] ??
            dataBooking['payment_id'] ??
            dataBooking['paymentId'],
      );

      return <String, dynamic>{
        if (paymentStatus != null) ...{
          'payment_status': paymentStatus,
          'paymentStatus': paymentStatus,
        },
        if (paidAt != null) ...{'paid_at': paidAt, 'paidAt': paidAt},
        if (paymentProvider != null) ...{
          'payment_provider': paymentProvider,
          'paymentProvider': paymentProvider,
        },
        if (paymentId != null) ...{
          'payment_id': paymentId,
          'paymentId': paymentId,
        },
      };
    }

    Future<Map<String, dynamic>> fetchAndParse(Uri uri) async {
      final res = await http
          .get(uri, headers: _headers(admin: true))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode < 200 || res.statusCode >= 300)
        return <String, dynamic>{};
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return <String, dynamic>{};

      final root = Map<String, dynamic>.from(decoded);
      var parsed = parsePayment(root);
      if (parsed['payment_status'] != null) return parsed;

      // Fallback shape: /bookings?limit=... returns a list under items/data/items.
      final candidateLists = <List<dynamic>>[
        asList(root['items']),
        asList(asMap(root['data'])['items']),
        asList(root['bookings']),
        asList(asMap(root['data'])['bookings']),
      ];
      for (final list in candidateLists) {
        for (final raw in list) {
          final item = asMap(raw);
          final itemBookingId = text(
            item['booking_id'] ?? item['bookingId'] ?? item['id'],
          );
          if (itemBookingId == null || itemBookingId.trim() != bookingId)
            continue;
          parsed = parsePayment(item);
          if (parsed.isNotEmpty) return parsed;
        }
      }
      return <String, dynamic>{};
    }

    try {
      final byId = Uri.parse(
        '$kBookingBaseUrl/bookings/${Uri.encodeComponent(bookingId)}',
      );
      final parsedById = await fetchAndParse(byId);
      if (parsedById.isNotEmpty) return parsedById;
    } catch (_) {}

    try {
      final listUrl = Uri.parse(
        '$kBookingBaseUrl/bookings?limit=200&t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final parsedList = await fetchAndParse(listUrl);
      if (parsedList.isNotEmpty) return parsedList;
    } catch (_) {}

    return <String, dynamic>{};
  }

  void _enterWaitMode() {
    if (!_liveRideActive) return;
    if (_isWaiting) return;
    setState(() {
      _isWaiting = true;
      _waitStartedAt = DateTime.now();
    });
    debugPrint(
      '[METER][WAIT_START] km=${_kmDriven.toStringAsFixed(3)} waitSec=${_effectiveWaitElapsed.inSeconds} total=${_liveMeterTotalEur.toStringAsFixed(2)}',
    );
    _startMeterTicker();
    unawaited(
      _sendDirectTripWaitEvent(
        path: kDirectTripWaitStartPath,
        logLabel: 'WAIT_START',
        timestampKey: 'client_wait_started_at',
      ),
    );
  }

  void _exitWaitMode() {
    if (!_liveRideActive) return;
    if (!_isWaiting) return;
    final started = _waitStartedAt;
    setState(() {
      _isWaiting = false;
      _waitStartedAt = null;
      if (started != null) {
        _waitElapsed += DateTime.now().difference(started);
      }
    });
    debugPrint(
      '[METER][WAIT_RESUME] km=${_kmDriven.toStringAsFixed(3)} waitSec=${_effectiveWaitElapsed.inSeconds} total=${_liveMeterTotalEur.toStringAsFixed(2)}',
    );
    _startMeterTicker();
    unawaited(
      _sendDirectTripWaitEvent(
        path: kDirectTripWaitEndPath,
        logLabel: 'WAIT_END',
        timestampKey: 'client_wait_ended_at',
      ),
    );
  }

  void _startMeterTicker() {
    _meterTicker?.cancel();
    if (!_liveRideActive) return;
    _meterTicker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_liveRideActive) {
        _meterTicker?.cancel();
        _meterTicker = null;
        return;
      }
      _debugLiveMeter(reason: 'ticker');
      setState(() {});
    });
  }

  void _stopMeterTicker() {
    _meterTicker?.cancel();
    _meterTicker = null;
  }

  Duration get _effectiveWaitElapsed {
    if (_isWaiting && _waitStartedAt != null) {
      return _waitElapsed + DateTime.now().difference(_waitStartedAt!);
    }
    return _waitElapsed;
  }

  bool get _liveRideActive => _activeTripId != null || _directRideActive;
  bool get _directRideDraft =>
      !_directRideActive &&
      _activeTripId == null &&
      _activeBooking == null &&
      (_directRideDestinationText ?? '').trim().isNotEmpty;

  double? get _fixedBookingPriceEur {
    final b = _activeBooking;
    if (b == null) return null;
    final p = b.price;
    if (p is num) return p.toDouble();
    return null;
  }

  double get _liveMeterTotalEur {
    final km = _kmDriven;
    final waitMin = _effectiveWaitElapsed.inMilliseconds / 60000.0;
    return _fallbackStartFee +
        (km * _fallbackPerKm) +
        (waitMin * _fallbackWaitPerMin);
  }

  void _debugLiveMeter({required String reason}) {
    final now = DateTime.now();
    final last = _lastMeterDebugAt;
    if (last != null && now.difference(last).inSeconds < 5) return;
    _lastMeterDebugAt = now;
    final waitMin = _effectiveWaitElapsed.inMilliseconds / 60000.0;
    final kmCost = _kmDriven * _fallbackPerKm;
    final waitCost = waitMin * _fallbackWaitPerMin;
    final total = _fallbackStartFee + kmCost + waitCost;
    debugPrint(
      '[METER][$reason] waiting=$_isWaiting km=${_kmDriven.toStringAsFixed(3)} kmCost=${kmCost.toStringAsFixed(2)} waitSec=${_effectiveWaitElapsed.inSeconds} waitCost=${waitCost.toStringAsFixed(2)} total=${total.toStringAsFixed(2)}',
    );
  }

  /// Price text shown in the cockpit:
  /// - Booking selected: show fixed price if known, otherwise "€ —" (never show live meter for bookings)
  /// - No booking selected: show the live meter total
  String get _displayTotalText {
    if (_liveRideActive) {
      final live = _liveMeterTotalEur;
      return '€ ${live.toStringAsFixed(2)}';
    }
    final fixed = _fixedBookingPriceEur;
    if (_activeBooking != null) {
      if (fixed != null && fixed > 0) return '€ ${fixed.toStringAsFixed(2)}';
      return '€ —';
    }
    final live = _liveMeterTotalEur;
    return '€ ${live.toStringAsFixed(2)}';
  }

  String get _cockpitPriceText =>
      _displayTotalText.replaceFirst('€', '').trim();

  Future<void> _sendDirectTripWaitEvent({
    required String path,
    required String logLabel,
    required String timestampKey,
  }) async {
    final tripId = _activeDirectTripId;
    if (!_directRideActive || tripId == null || tripId.trim().isEmpty) return;
    try {
      final payload = <String, dynamic>{
        'trip_id': tripId,
        timestampKey: DateTime.now().toUtc().toIso8601String(),
      };
      final res = await http
          .post(
            Uri.parse('$kWorkerBaseUrl$path'),
            headers: _headers(admin: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      debugPrint('[DIRECT_TRIP][$logLabel][OK] trip_id=$tripId');
    } catch (e) {
      debugPrint('[DIRECT_TRIP][$logLabel][WARN] local wait only: $e');
    }
  }

  String _directRideVehicleId() {
    for (final vehicle in vehiclesNotifier.value) {
      if (vehicle.isActive &&
          vehicle.driverId == kDriverId &&
          vehicle.id.trim().isNotEmpty) {
        return vehicle.id.trim();
      }
    }
    for (final vehicle in vehiclesNotifier.value) {
      if (vehicle.isActive && vehicle.id.trim().isNotEmpty) {
        return vehicle.id.trim();
      }
    }
    if (vehiclesNotifier.value.isNotEmpty) {
      final firstId = vehiclesNotifier.value.first.id.trim();
      if (firstId.isNotEmpty) return firstId;
    }
    return 'vh_1';
  }

  Map<String, dynamic> _currentOriginPayload(geo.Position? pos) {
    if (pos == null) {
      return <String, dynamic>{'label': _receiptText('currentLocation')};
    }
    return <String, dynamic>{
      'label':
          '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}',
      'lat': pos.latitude,
      'lon': pos.longitude,
    };
  }

  Map<String, dynamic> _plannedBookingDetailsPayload(BookingItem booking) {
    Map<String, dynamic> asMap(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    List<dynamic> asList(dynamic value) => value is List ? value : const [];
    String? text(dynamic value) {
      final s = value?.toString().trim();
      return s == null || s.isEmpty ? null : s;
    }

    num? number(dynamic value) {
      if (value is num) return value;
      if (value is String) return num.tryParse(value.replaceAll(',', '.'));
      return null;
    }

    dynamic pick(List<List<String>> paths) {
      for (final path in paths) {
        dynamic current = booking.details;
        for (final key in path) {
          if (current is Map && current.containsKey(key)) {
            current = current[key];
          } else {
            current = null;
            break;
          }
        }
        if (current != null) return current;
      }
      return null;
    }

    final bookingMap = asMap(booking.details['booking']);
    final detailMap = booking.details;
    final quote = asMap(booking.details['quote']);
    final record = asMap(booking.details['record']);
    final recordPayload = asMap(record['payload']);
    final payloadQuote = asMap(recordPayload['quote']);
    if (quote.isEmpty && payloadQuote.isNotEmpty) {
      quote.addAll(payloadQuote);
    }
    final inputs = asMap(quote['inputs']);
    final pricing = asMap(quote['pricing']);
    final pricingMain = asMap(quote['pricing_main'] ?? quote['pricingMain']);
    final pricingReturn = asMap(
      quote['pricing_return'] ?? quote['pricingReturn'],
    );
    final returnInfo = asMap(quote['return']);
    final tracking = asMap(booking.details['tracking_booking']);
    final payload = recordPayload;
    final customer = asMap(payload['customer']);
    final bookingCustomer = asMap(bookingMap['customer']);
    final payloadBooking = asMap(payload['booking']);
    final payloadBookingCustomer = asMap(payloadBooking['customer']);
    final customerName = text(
      bookingMap['custName'] ??
          bookingMap['customer_name'] ??
          bookingMap['customerName'] ??
          bookingMap['name'] ??
          bookingCustomer['name'] ??
          bookingCustomer['full_name'] ??
          detailMap['customer_name'] ??
          detailMap['customerName'] ??
          detailMap['name'] ??
          payload['name'] ??
          payload['customer_name'] ??
          payload['customerName'] ??
          payloadBooking['customer_name'] ??
          payloadBooking['customerName'] ??
          payloadBooking['name'] ??
          payloadBookingCustomer['name'] ??
          payloadBookingCustomer['full_name'] ??
          customer['name'] ??
          customer['full_name'] ??
          pick([
            ['customer', 'name'],
            ['booking', 'customer', 'name'],
            ['record', 'payload', 'customer', 'name'],
            ['record', 'payload', 'booking', 'customer', 'name'],
          ]),
    );
    final customerPhone = text(
      bookingMap['custPhone'] ??
          bookingMap['customer_phone'] ??
          bookingMap['customerPhone'] ??
          bookingMap['phone'] ??
          bookingMap['tel'] ??
          bookingMap['mobile'] ??
          bookingCustomer['phone'] ??
          bookingCustomer['tel'] ??
          bookingCustomer['mobile'] ??
          detailMap['customer_phone'] ??
          detailMap['customerPhone'] ??
          detailMap['phone'] ??
          detailMap['tel'] ??
          detailMap['mobile'] ??
          payload['phone'] ??
          payload['customer_phone'] ??
          payload['customerPhone'] ??
          payload['tel'] ??
          payload['mobile'] ??
          payloadBooking['customer_phone'] ??
          payloadBooking['customerPhone'] ??
          payloadBooking['phone'] ??
          payloadBooking['tel'] ??
          payloadBooking['mobile'] ??
          payloadBookingCustomer['phone'] ??
          payloadBookingCustomer['tel'] ??
          payloadBookingCustomer['mobile'] ??
          customer['phone'] ??
          customer['tel'] ??
          customer['mobile'] ??
          pick([
            ['customer', 'phone'],
            ['booking', 'customer', 'phone'],
            ['record', 'payload', 'customer', 'phone'],
            ['record', 'payload', 'booking', 'customer', 'phone'],
          ]),
    );
    final customerEmail = text(
      bookingMap['custEmail'] ??
          bookingMap['customer_email'] ??
          bookingMap['customerEmail'] ??
          bookingMap['email'] ??
          bookingCustomer['email'] ??
          detailMap['customer_email'] ??
          detailMap['customerEmail'] ??
          detailMap['email'] ??
          payload['email'] ??
          payload['customer_email'] ??
          payload['customerEmail'] ??
          payloadBooking['customer_email'] ??
          payloadBooking['customerEmail'] ??
          payloadBooking['email'] ??
          payloadBookingCustomer['email'] ??
          customer['email'] ??
          pick([
            ['customer', 'email'],
            ['booking', 'customer', 'email'],
            ['record', 'payload', 'customer', 'email'],
            ['record', 'payload', 'booking', 'customer', 'email'],
          ]),
    );
    final customerCountry = text(
      bookingMap['customer_country'] ??
          bookingMap['customerCountry'] ??
          bookingMap['country'] ??
          bookingMap['countryCode'] ??
          bookingMap['country_iso'] ??
          bookingMap['countryIso'] ??
          detailMap['customer_country'] ??
          detailMap['customerCountry'] ??
          detailMap['country'] ??
          detailMap['countryCode'] ??
          detailMap['country_iso'] ??
          detailMap['countryIso'] ??
          payload['customer_country'] ??
          payload['customerCountry'] ??
          payload['country'] ??
          payload['countryCode'] ??
          payload['country_iso'] ??
          payload['countryIso'] ??
          payload['locale'] ??
          payload['language'] ??
          customer['country'] ??
          customer['countryCode'] ??
          customer['countryIso'],
    );
    final phoneCountryCode = text(
      bookingMap['phone_country_code'] ??
          bookingMap['phoneCountryCode'] ??
          detailMap['phone_country_code'] ??
          detailMap['phoneCountryCode'] ??
          payload['phone_country_code'] ??
          payload['phoneCountryCode'] ??
          customer['phone_country_code'] ??
          customer['phoneCountryCode'],
    );
    final dialCode = text(
      bookingMap['dial_code'] ??
          bookingMap['dialCode'] ??
          detailMap['dial_code'] ??
          detailMap['dialCode'] ??
          payload['dial_code'] ??
          payload['dialCode'] ??
          customer['dial_code'] ??
          customer['dialCode'],
    );

    final pickupAddress =
        text(booking.from) ??
        text(quote['from']) ??
        text(inputs['from']) ??
        text(bookingMap['from']) ??
        text(tracking['pickup']);
    final destinationAddress =
        text(booking.to) ??
        text(quote['to']) ??
        text(inputs['to']) ??
        text(bookingMap['to']) ??
        text(tracking['dropoff']);
    final service =
        text(bookingMap['service']) ??
        text(inputs['service']) ??
        text(
          pick([
            ['service'],
          ]),
        );
    final tier =
        text(booking.tier) ?? text(bookingMap['tier']) ?? text(inputs['tier']);
    final scheduledPickup =
        text(booking.pickupIso) ??
        text(bookingMap['pickupStartIso']) ??
        text(bookingMap['pickup_iso']) ??
        text(inputs['pickup_iso']);
    final totalPackage =
        number(bookingMap['price_incl_vat']) ??
        number(pricing['price_incl_vat']) ??
        number(pricing['total_price_incl_vat']) ??
        number(quote['total_price_incl_vat']) ??
        number(quote['price_incl_vat']) ??
        booking.price;
    final segmentPrice = booking.bookingId.endsWith('-R')
        ? (number(bookingMap['price_incl_vat_return']) ??
              number(pricingReturn['price_incl_vat']) ??
              number(returnInfo['price_incl_vat']) ??
              number(asMap(returnInfo['pricing'])['price_incl_vat']))
        : (number(bookingMap['price_incl_vat_main']) ??
              number(pricingMain['price_incl_vat']) ??
              number(quote['price_incl_vat']));
    final returnPickup =
        text(bookingMap['returnPickupIso']) ??
        text(inputs['return_pickup_iso']) ??
        text(
          pick([
            ['return_pickup_iso'],
          ]),
        );
    final returnFrom =
        text(bookingMap['return_from']) ??
        text(inputs['return_from']) ??
        text(returnInfo['from']);
    final returnTo =
        text(bookingMap['return_to']) ??
        text(inputs['return_to']) ??
        text(returnInfo['to']);
    final hasReturnInfo =
        returnPickup != null ||
        returnFrom != null ||
        returnTo != null ||
        returnInfo['enabled'] == true ||
        pricingReturn.isNotEmpty;
    final paymentStatus = text(
      bookingMap['payment_status'] ??
          bookingMap['paymentStatus'] ??
          detailMap['payment_status'] ??
          detailMap['paymentStatus'] ??
          payload['payment_status'] ??
          payload['paymentStatus'] ??
          pick([
            ['payment_status'],
            ['paymentStatus'],
            ['booking', 'payment_status'],
            ['booking', 'paymentStatus'],
          ]),
    );
    final paidAt = text(
      bookingMap['paid_at'] ??
          bookingMap['paidAt'] ??
          detailMap['paid_at'] ??
          detailMap['paidAt'] ??
          payload['paid_at'] ??
          payload['paidAt'],
    );
    final paymentProvider = text(
      bookingMap['payment_provider'] ??
          bookingMap['paymentProvider'] ??
          detailMap['payment_provider'] ??
          detailMap['paymentProvider'] ??
          payload['payment_provider'] ??
          payload['paymentProvider'],
    );
    final paymentId = text(
      bookingMap['payment_id'] ??
          bookingMap['paymentId'] ??
          detailMap['payment_id'] ??
          detailMap['paymentId'] ??
          payload['payment_id'] ??
          payload['paymentId'],
    );

    List<Map<String, dynamic>> normalizeSegments(dynamic raw) {
      final result = <Map<String, dynamic>>[];
      for (final value in asList(raw)) {
        if (value is! Map) continue;
        final segment = Map<String, dynamic>.from(value);
        final from = text(
          segment['from'] ??
              segment['origin'] ??
              segment['start'] ??
              segment['start_address'],
        );
        final to = text(
          segment['to'] ??
              segment['destination'] ??
              segment['end'] ??
              segment['end_address'],
        );
        result.add(<String, dynamic>{
          if (from != null) 'from': from,
          if (to != null) 'to': to,
          if (number(segment['distance_km'] ?? segment['km']) != null)
            'distance_km': number(segment['distance_km'] ?? segment['km']),
          if (number(segment['duration_min'] ?? segment['minutes']) != null)
            'duration_min': number(
              segment['duration_min'] ?? segment['minutes'],
            ),
        });
      }
      return result;
    }

    final routeSegments = normalizeSegments(
      quote['route_segments'] ??
          quote['legs'] ??
          bookingMap['route_segments'] ??
          bookingMap['legs'],
    );
    if (routeSegments.isEmpty &&
        pickupAddress != null &&
        destinationAddress != null) {
      final distance = number(
        quote['distance_km'] ?? bookingMap['distance_km'],
      );
      final duration = number(
        quote['duration_min'] ?? bookingMap['duration_route_min'],
      );
      if (distance != null || duration != null) {
        routeSegments.add(<String, dynamic>{
          'from': pickupAddress,
          'to': destinationAddress,
          if (distance != null) 'distance_km': distance,
          if (duration != null) 'duration_min': duration,
        });
      }
    }
    if (hasReturnInfo) {
      final returnDistance = number(
        returnInfo['distance_km'] ?? bookingMap['return_distance_km'],
      );
      final returnDuration = number(
        returnInfo['duration_min'] ?? bookingMap['return_duration_min'],
      );
      if (returnFrom != null ||
          returnTo != null ||
          returnDistance != null ||
          returnDuration != null) {
        routeSegments.add(<String, dynamic>{
          if (returnFrom != null) 'from': returnFrom,
          if (returnTo != null) 'to': returnTo,
          if (returnDistance != null) 'distance_km': returnDistance,
          if (returnDuration != null) 'duration_min': returnDuration,
          'kind': 'return',
        });
      }
    }

    return <String, dynamic>{
      if (pickupAddress != null) 'pickup_address': pickupAddress,
      if (destinationAddress != null) 'destination_address': destinationAddress,
      if (scheduledPickup != null) 'scheduled_pickup_at': scheduledPickup,
      if (booking.bookingId.endsWith('-R')) 'subtype': 'Retourrit',
      if (!booking.bookingId.endsWith('-R') && hasReturnInfo)
        'subtype': 'Heenrit',
      if (customerName != null) 'customer_name': customerName,
      if (customerPhone != null) 'customer_phone': customerPhone,
      if (customerEmail != null) 'customer_email': customerEmail,
      if (customerName != null ||
          customerPhone != null ||
          customerEmail != null)
        'customer': <String, dynamic>{
          if (customerName != null) 'name': customerName,
          if (customerPhone != null) 'phone': customerPhone,
          if (customerEmail != null) 'email': customerEmail,
        },
      if (customerCountry != null) 'customer_country': customerCountry,
      if (phoneCountryCode != null) 'phone_country_code': phoneCountryCode,
      if (dialCode != null) 'dial_code': dialCode,
      if (service != null) 'service_type': service,
      if (tier != null) 'tier': tier,
      if (number(booking.pax ?? bookingMap['pax'] ?? inputs['pax']) != null)
        'passengers': number(booking.pax ?? bookingMap['pax'] ?? inputs['pax']),
      if (number(booking.bags ?? bookingMap['bags'] ?? inputs['bags']) != null)
        'luggage_count': number(
          booking.bags ?? bookingMap['bags'] ?? inputs['bags'],
        ),
      if (number(bookingMap['wait_min'] ?? inputs['wait_min']) != null)
        'booked_wait_minutes': number(
          bookingMap['wait_min'] ?? inputs['wait_min'],
        ),
      if ((booking.status ?? '').trim().isNotEmpty)
        'booking_status': booking.status!.trim(),
      if (paymentStatus != null) ...{
        'payment_status': paymentStatus,
        'paymentStatus': paymentStatus,
      },
      if (paidAt != null) ...{'paid_at': paidAt, 'paidAt': paidAt},
      if (paymentProvider != null) ...{
        'payment_provider': paymentProvider,
        'paymentProvider': paymentProvider,
      },
      if (paymentId != null) ...{
        'payment_id': paymentId,
        'paymentId': paymentId,
      },
      if (totalPackage != null) 'booking_total_eur': totalPackage,
      if (segmentPrice != null) 'segment_price_eur': segmentPrice,
      if (bookingMap['price_incl_vat_main'] != null ||
          pricingMain['price_incl_vat'] != null)
        'outbound_price_eur': number(
          bookingMap['price_incl_vat_main'] ?? pricingMain['price_incl_vat'],
        ),
      if (bookingMap['price_incl_vat_return'] != null ||
          pricingReturn['price_incl_vat'] != null)
        'return_price_eur': number(
          bookingMap['price_incl_vat_return'] ??
              pricingReturn['price_incl_vat'],
        ),
      if (returnPickup != null) 'return_scheduled_pickup_at': returnPickup,
      if (returnFrom != null || returnTo != null)
        'return_route': [returnFrom, returnTo].whereType<String>().join(' → '),
      if (routeSegments.isNotEmpty) 'route_segments': routeSegments,
      if (asList(
        bookingMap['stops'] ?? inputs['stops'] ?? quote['stops'],
      ).isNotEmpty)
        'stops': asList(
          bookingMap['stops'] ?? inputs['stops'] ?? quote['stops'],
        ).join(' → '),
      if (text(
            bookingMap['extra_service_label'] ?? inputs['extra_service_label'],
          ) !=
          null)
        'extras': text(
          bookingMap['extra_service_label'] ?? inputs['extra_service_label'],
        ),
      if (text(
            bookingMap['message'] ??
                payload['message'] ??
                customer['message'] ??
                pick([
                  ['customer', 'message'],
                ]),
          ) !=
          null)
        'notes': text(
          bookingMap['message'] ??
              payload['message'] ??
              customer['message'] ??
              pick([
                ['customer', 'message'],
              ]),
        ),
      if ((booking.currency ?? '').trim().isNotEmpty)
        'currency': booking.currency!.trim(),
    };
  }

  Future<void> _startDirectTripSessionOnWorker({
    required String destination,
  }) async {
    try {
      final point = _directRideDestinationPoint;
      final destinationPayload = <String, dynamic>{
        'label': destination,
        if (point != null) 'lat': point.lat,
        if (point != null) 'lon': point.lon,
      };
      final payload = <String, dynamic>{
        'tenant_id': kTenantId,
        'driver_id': kDriverId,
        'vehicle_id': _directRideVehicleId(),
        'origin': _currentOriginPayload(_lastPos),
        'destination': destinationPayload,
        'pricing_snapshot': <String, dynamic>{
          'start_fee': _fallbackStartFee,
          'per_km': _fallbackPerKm,
          'wait_per_min': _fallbackWaitPerMin,
          'currency': kDefaultCurrency,
        },
        'client_started_at': (_trackingStartedAt ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
      };
      final res = await http
          .post(
            Uri.parse('$kWorkerBaseUrl$kStartDirectTripPath'),
            headers: _headers(admin: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['ok'] != true) {
        throw Exception('Invalid direct trip start response: ${res.body}');
      }
      final tripId = (decoded['trip_id'] ?? '').toString().trim();
      if (tripId.isEmpty) throw Exception('No trip_id returned');
      if (!mounted || !_directRideActive) return;
      setState(() => _activeDirectTripId = tripId);
      debugPrint('[DIRECT_TRIP][START][OK] trip_id=$tripId');
    } catch (e) {
      debugPrint('[DIRECT_TRIP][START][WARN] local-only direct ride: $e');
    }
  }

  Future<double?> _stopDirectTripSessionOnWorker({
    required String tripId,
    required double kmTotal,
    required int waitSecondsTotal,
  }) async {
    try {
      final payload = <String, dynamic>{
        'trip_id': tripId,
        'km_total': kmTotal,
        'wait_seconds_total': waitSecondsTotal,
        'client_stopped_at': DateTime.now().toUtc().toIso8601String(),
      };
      final res = await http
          .post(
            Uri.parse('$kWorkerBaseUrl$kStopDirectTripPath'),
            headers: _headers(admin: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['ok'] != true) {
        throw Exception('Invalid direct trip stop response: ${res.body}');
      }
      final totals = decoded['totals'];
      final total = totals is Map ? totals['total_eur'] : null;
      if (total is num) return total.toDouble();
      return double.tryParse((total ?? '').toString().replaceAll(',', '.'));
    } catch (e) {
      debugPrint('[DIRECT_TRIP][STOP][WARN] using local total: $e');
      return null;
    }
  }

  Future<void> _recordPlannedTripStopOnWorker({
    required BookingItem booking,
    required double kmTotal,
    required int waitSecondsTotal,
    required DateTime? startedAt,
    required DateTime stoppedAt,
  }) async {
    try {
      final bookingDetails = _plannedBookingDetailsPayload(booking);
      final authoritativePayment = await _fetchPaymentFieldsForHistory(
        booking.bookingId,
      );
      if (authoritativePayment.isNotEmpty) {
        bookingDetails.addAll(authoritativePayment);
        final existingBooking = bookingDetails['booking'];
        if (existingBooking is Map) {
          final mergedBooking = Map<String, dynamic>.from(existingBooking);
          if (authoritativePayment['payment_status'] != null) {
            mergedBooking['payment_status'] =
                authoritativePayment['payment_status'];
            mergedBooking['paymentStatus'] =
                authoritativePayment['payment_status'];
          }
          if (authoritativePayment['paid_at'] != null) {
            mergedBooking['paid_at'] = authoritativePayment['paid_at'];
            mergedBooking['paidAt'] = authoritativePayment['paid_at'];
          }
          if (authoritativePayment['payment_provider'] != null) {
            mergedBooking['payment_provider'] =
                authoritativePayment['payment_provider'];
            mergedBooking['paymentProvider'] =
                authoritativePayment['payment_provider'];
          }
          if (authoritativePayment['payment_id'] != null) {
            mergedBooking['payment_id'] = authoritativePayment['payment_id'];
            mergedBooking['paymentId'] = authoritativePayment['payment_id'];
          }
          bookingDetails['booking'] = mergedBooking;
        }
      }
      final price =
          booking.price ??
          BookingItem._toNumOrNull(bookingDetails['booking_total_eur']);
      final payload = <String, dynamic>{
        'booking_id': booking.bookingId,
        'tenant_id': kTenantId,
        'driver_id': kDriverId,
        'vehicle_id': _directRideVehicleId(),
        'origin': <String, dynamic>{
          'label': (booking.from ?? _receiptText('currentLocation')).toString(),
        },
        'destination': <String, dynamic>{
          'label': (booking.to ?? booking.from ?? booking.shortId).toString(),
        },
        'booking_details': bookingDetails,
        if (startedAt != null)
          'started_at': startedAt.toUtc().toIso8601String(),
        'stopped_at': stoppedAt.toUtc().toIso8601String(),
        'km_total': kmTotal,
        'wait_seconds_total': waitSecondsTotal,
        if (price != null) 'total_eur': price.toDouble(),
        'currency': booking.currency ?? kDefaultCurrency,
        if (bookingDetails['payment_status'] != null)
          'payment_status': bookingDetails['payment_status'],
        if (bookingDetails['paymentStatus'] != null)
          'paymentStatus': bookingDetails['paymentStatus'],
        if (bookingDetails['paid_at'] != null)
          'paid_at': bookingDetails['paid_at'],
        if (bookingDetails['paidAt'] != null)
          'paidAt': bookingDetails['paidAt'],
        if (bookingDetails['payment_provider'] != null)
          'payment_provider': bookingDetails['payment_provider'],
        if (bookingDetails['paymentProvider'] != null)
          'paymentProvider': bookingDetails['paymentProvider'],
        if (bookingDetails['payment_id'] != null)
          'payment_id': bookingDetails['payment_id'],
        if (bookingDetails['paymentId'] != null)
          'paymentId': bookingDetails['paymentId'],
      };
      final res = await http
          .post(
            Uri.parse('$kWorkerBaseUrl$kRecordPlannedTripStopPath'),
            headers: _headers(admin: true),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      debugPrint('[PLANNED_TRIP][HISTORY][OK] booking=${booking.bookingId}');
    } catch (e) {
      debugPrint(
        '[PLANNED_TRIP][HISTORY][WARN] booking=${booking.bookingId} reason=$e',
      );
    }
  }

  Future<void> _stopTrip() async {
    final trip = _activeTripId;
    if (trip == null && !_directRideActive) return;
    final stoppedBooking = _activeBooking;
    final wasDirectRide = _directRideActive;
    final directTripId = _activeDirectTripId;
    final finalTotal = _liveMeterTotalEur;
    final stoppedAt = DateTime.now();
    final startedAt = _trackingStartedAt;
    final kmAtStop = _kmDriven;
    var plannedSessionStopOk = false;

    if (_isWaiting && _waitStartedAt != null) {
      final started = _waitStartedAt!;
      _waitElapsed += DateTime.now().difference(started);
      _waitStartedAt = null;
      _isWaiting = false;
    }

    if (trip != null) {
      try {
        final uri = Uri.parse('$kWorkerBaseUrl$kStopTripPath');
        final payload = {'session_id': trip, 'driver_id': kDriverId};
        final res = await http
            .post(
              uri,
              headers: _headers(admin: true),
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 10));
        plannedSessionStopOk = res.statusCode == 200;
      } catch (_) {}
    }

    if (!wasDirectRide && stoppedBooking != null && plannedSessionStopOk) {
      await _recordPlannedTripStopOnWorker(
        booking: stoppedBooking,
        kmTotal: kmAtStop,
        waitSecondsTotal: _effectiveWaitElapsed.inSeconds,
        startedAt: startedAt,
        stoppedAt: stoppedAt,
      );
    }

    double? serverDirectTotal;
    if (wasDirectRide &&
        directTripId != null &&
        directTripId.trim().isNotEmpty) {
      serverDirectTotal = await _stopDirectTripSessionOnWorker(
        tripId: directTripId,
        kmTotal: _kmDriven,
        waitSecondsTotal: _effectiveWaitElapsed.inSeconds,
      );
    }

    _stopMeterTicker();
    _stopTrackingInternal();

    if (stoppedBooking != null) {
      await _completeStoppedBooking(stoppedBooking);
    }
    await _clearActiveRouteAndNavigationState(
      reason: 'stop',
      bookingId: stoppedBooking?.bookingId,
      clearActiveSelection: true,
    );
    if (wasDirectRide) {
      final shownTotal = serverDirectTotal ?? finalTotal;
      _toast('Straatrit afgerond: € ${shownTotal.toStringAsFixed(2)}');
    }
  }

  Future<void> _completeStoppedBooking(BookingItem b) async {
    final bookingId = b.bookingId;
    try {
      await _setBookingStatus(b, 'COMPLETED');
    } catch (e) {
      debugPrint('[RIDES][STOP_COMPLETE][WARN] $e');
    }
    if (!mounted) return;
    setState(() {
      _bookingStatusOverrides[bookingId] = 'COMPLETED';
      _bookings.removeWhere((x) => x.bookingId == bookingId);
      _deletedBookingIds.add(bookingId);
    });
    _markBookingsUiDirty();
  }

  Future<void> _ensureLocationPermission() async {
    final enabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      _toast('Location is disabled on the phone.');
      return;
    }

    geo.LocationPermission perm = await geo.Geolocator.checkPermission();
    if (perm == geo.LocationPermission.denied) {
      perm = await geo.Geolocator.requestPermission();
    }
    if (perm == geo.LocationPermission.denied ||
        perm == geo.LocationPermission.deniedForever) {
      _toast('Location permission denied.');
      return;
    }
  }

  void _startTrackingInternal() {
    if (_posSub != null) {
      debugPrint(
        '[RIDES][TRACKING][SKIP_START] reason=already_active geolocatorSubs=$_activeGeolocatorSubscriptionCount',
      );
      return;
    }
    _stopBookingPolling(reason: 'tracking_started');

    const settings = geo.LocationSettings(
      accuracy: geo.LocationAccuracy.bestForNavigation,
      distanceFilter: 3,
    );

    _posSub = geo.Geolocator.getPositionStream(locationSettings: settings).listen((
      pos,
    ) async {
      final prev = _lastPos;
      _lastPos = pos;
      _startPos ??= pos;

      if (prev != null) {
        final meters = geo.Geolocator.distanceBetween(
          prev.latitude,
          prev.longitude,
          pos.latitude,
          pos.longitude,
        );
        if (meters.isFinite && meters > 0) {
          // Only count driven distance once the trip is actually started.
          if (_liveRideActive && !_isWaiting) {
            if (mounted) setState(() => _kmDriven += meters / 1000.0);
          } else if (_liveRideActive && _isWaiting) {
            debugPrint(
              '[METER][WAIT_DISTANCE_SKIPPED] meters=${meters.toStringAsFixed(1)} km=${_kmDriven.toStringAsFixed(3)}',
            );
          }
        }

        if (_liveRideActive && !_hasSwitchedToFollow && _startPos != null) {
          final movedFromStart = geo.Geolocator.distanceBetween(
            _startPos!.latitude,
            _startPos!.longitude,
            pos.latitude,
            pos.longitude,
          );
          final speedKmh = (pos.speed.isFinite ? (pos.speed * 3.6) : 0.0);
          if (speedKmh >= 3.0 || movedFromStart >= 25.0) {
            _hasSwitchedToFollow = true;
            _cameraMode = _CameraMode.follow;
          }
        }

        final movementBearing = _bearingFromPoints(
          prev.latitude,
          prev.longitude,
          pos.latitude,
          pos.longitude,
        );
        if (movementBearing != null) {
          _lastKnownBearing = movementBearing;
        }
      }

      if (pos.heading.isFinite && pos.heading >= 0) {
        _lastKnownBearing = pos.heading;
      }

      _updateRouteSnapState(pos);

      if (_mapSupported && _map != null && _driverPointManager != null) {
        await _updateDriverMarker(pos);
        if (_cameraMode == _CameraMode.follow) {
          await _followCameraTesla(pos);
        }
      }
      final uiBearing = _cameraBearingFor(pos);
      if (mounted && _cameraMode == _CameraMode.follow) {
        setState(() => _uiArrowBearing = uiBearing);
      } else {
        _uiArrowBearing = uiBearing;
      }
      _updateNextNavInstruction(pos);

      await _sendPing(pos);
    });
    _activeGeolocatorSubscriptionCount = 1;
    debugPrint(
      '[RIDES][TRACKING][START] geolocatorSubs=$_activeGeolocatorSubscriptionCount',
    );
  }

  void _stopTrackingInternal() {
    if (_posSub == null) return;
    _posSub?.cancel();
    _posSub = null;
    _activeGeolocatorSubscriptionCount = 0;
    debugPrint(
      '[RIDES][TRACKING][STOP] geolocatorSubs=$_activeGeolocatorSubscriptionCount',
    );
    _startPos = null;
    _lastFollowCameraAt = null;
    _followCameraInFlight = false;
    if (!_liveRideActive) {
      _startBookingPolling(reason: 'tracking_stopped');
    }
  }

  /// ===============================
  /// HUD COMPUTED TEXTS (single source of truth)
  /// ===============================

  bool get _isTracking => _liveRideActive && _posSub != null;

  String get _etaText {
    // Countdown style ETA (remaining), used both in preview and in active trip.
    final total = _routeDurationSec;
    if (total == null || total <= 0) return '';

    // When tracking, subtract progress (based on km fraction). When previewing, show total.
    int remainingSec;
    if (_isTracking) {
      remainingSec = _timeRemainingSeconds ?? total;
    } else {
      // Not tracking yet (preview)
      remainingSec = total;
    }

    remainingSec = math.max(0, remainingSec);
    if (remainingSec < 60) return '<1 min';

    final minutes = (remainingSec / 60).ceil();
    if (minutes < 60) return '$minutes min';

    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  String get _kmRemainingText {
    // Show in preview as soon as we have a route.

    final remaining = _kmRemaining;
    if (remaining == null) return '';
    if (remaining < 0.05) return '0.0';
    return remaining.toStringAsFixed(1);
  }

  String get _timeRemainingText {
    if (!_isTracking) return '';
    final sec = _timeRemainingSeconds;
    if (sec == null) return '';
    final minutes = (sec / 60.0).round();
    if (minutes <= 0) return '0m';
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h}h ${m}m';
  }

  double? get _kmRemaining {
    final rk = _routeKm;
    if (rk == null) return null;

    // ✅ Countdown starts only once we actually move (Google Maps style).
    // Before movement, keep the full route distance as "remaining".
    if (_isTracking && !_hasSwitchedToFollow) return rk;

    final v = rk - _kmDriven;
    return v < 0 ? 0 : v;
  }

  int? get _timeRemainingSeconds {
    final total = _routeDurationSec;
    final rk = _routeKm;
    if (total == null || rk == null) return null;

    // ✅ Countdown starts only once we actually move (Google Maps style).
    if (_isTracking && !_hasSwitchedToFollow) return total;

    if (rk <= 0.01) return total;
    final fracDriven = (_kmDriven / rk).clamp(0.0, 1.0);
    final remaining = (total * (1.0 - fracDriven)).round();
    return remaining < 0 ? 0 : remaining;
  }

  /// Map HUD actions
  Future<void> _stopTracking() async {
    // Stop UI + pings immediately (best UX)
    _stopTrackingInternal();

    // Try to notify Worker (best-effort)
    try {
      await _stopTrip();
    } catch (_) {
      // ignore
    }

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openNavigation() async {
    // NAV always forces follow mode for live street-level navigation.
    if (_map == null) return;

    setState(() {
      _cameraMode = _CameraMode.follow;
      _hasSwitchedToFollow = true;
      _followCar = true;
      _allowOverviewCamera = false;
    });
    _setNavigationWakelock(true);
    await _applyMapStyleForMode();
    await _forceFollowCameraNow(caller: 'nav_button');
    final b = _activeBooking;
    if (b != null && _activeTripId == null) {
      await _buildNavRouteToPickup(b);
    } else if (b != null && _activeTripId != null) {
      await _buildNavRouteToDestination(b);
    } else if ((_directRideDestinationText ?? '').trim().isNotEmpty) {
      await _buildDirectRouteToDestination(_directRideDestinationText!.trim());
    }
  }

  Future<void> _openDirectRideEntry() async {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    final destination = await showDialog<_DirectRideDestinationResult>(
      context: context,
      builder: (_) => _DirectRideDestinationDialog(
        initialText: _directRideDestinationText ?? '',
        search: _fetchPlaceSuggestions,
      ),
    );
    if (!mounted || destination == null || destination.label.trim().isEmpty)
      return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final selectedPoint = (destination.lon != null && destination.lat != null)
        ? _LonLat(destination.lon!, destination.lat!)
        : null;

    setState(() {
      _activeBooking = null;
      _activeTripId = null;
      _activeDirectTripId = null;
      _directRideActive = false;
      _directRideDestinationText = destination.label.trim();
      _directRideDestinationPoint = selectedPoint;
      _kmDriven = 0.0;
      _resetNavProgressState(clearRoute: true);
      _routePhase = _RideRoutePhase.trip;
      _cameraMode = _CameraMode.overview;
      _hasSwitchedToFollow = false;
      _followCar = false;
      _allowOverviewCamera = false;
      _isWaiting = false;
      _waitStartedAt = null;
      _waitElapsed = Duration.zero;
      _trackingStartedAt = null;
    });
    _toast('Straatrit klaar. Druk START om te rijden.');
  }

  Future<void> _startDirectRide() async {
    final destination = (_directRideDestinationText ?? '').trim();
    if (destination.isEmpty) {
      await _openDirectRideEntry();
      return;
    }
    await _ensureLocationPermission();
    var pos = _lastPos;
    if (pos == null) {
      try {
        pos = await geo.Geolocator.getCurrentPosition(
          desiredAccuracy: geo.LocationAccuracy.best,
        );
        _lastPos = pos;
      } catch (_) {
        pos = null;
      }
    }
    if (pos == null) {
      _toast('GPS-locatie nog niet beschikbaar');
      return;
    }

    setState(() {
      _directRideActive = true;
      _activeTripId = null;
      _activeDirectTripId = null;
      _activeBooking = null;
      _cameraMode = _CameraMode.follow;
      _hasSwitchedToFollow = true;
      _followCar = true;
      _allowOverviewCamera = false;
      _kmDriven = 0.0;
      _trackingStartedAt = DateTime.now();
      _isWaiting = false;
      _waitStartedAt = null;
      _waitElapsed = Duration.zero;
    });
    _setNavigationWakelock(true);
    await _applyMapStyleForMode();
    _startTrackingInternal();
    _startMeterTicker();
    unawaited(_startDirectTripSessionOnWorker(destination: destination));
    await _forceFollowCameraNow(caller: 'direct_ride_start');
    await _buildDirectRouteToDestination(destination);
  }

  void _handleCockpitStart() {
    final b = _activeBooking;
    if (b != null) {
      _startTrip(b);
      return;
    }
    if (_directRideDraft || _directRideActive) {
      _startDirectRide();
      return;
    }
    _toast('Kies eerst een rit of start een straatrit.');
  }

  Future<void> _sendPing(geo.Position pos) async {
    final trip = _activeTripId;
    if (trip == null) return;

    try {
      final uri = Uri.parse('$kWorkerBaseUrl$kPingPath');
      final payload = {
        'session_id': trip,
        'driver_id': kDriverId,
        'lat': pos.latitude,
        'lon': pos.longitude,
        'speed': (pos.speed.isFinite ? (pos.speed * 3.6) : 0.0),
        'heading': (pos.heading.isFinite ? pos.heading : 0.0),
        'accuracy_m': pos.accuracy,
        'ts': DateTime.now().toIso8601String(),
      };

      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      setState(() {
        _pingCount += 1;
        _lastPing = (res.statusCode == 200) ? 'OK' : 'HTTP ${res.statusCode}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _lastPing = 'ERR');
    }
  }

  Future<void> _onMapCreated(mb.MapboxMap mapboxMap) async {
    debugPrint('[MAP][CREATED] style=$_activeMapStyleUri');
    _map = mapboxMap;
    await _applyMapStyleForMode();
    await _recreateAnnotationManagers();

    final pos = _lastPos;
    if (pos != null) {
      await _updateDriverMarker(
        pos,
        moveCamera: _cameraMode != _CameraMode.follow,
      );
      if (_cameraMode == _CameraMode.follow) {
        await _followCameraTesla(pos, force: true);
      }
    }
  }

  Future<void> _recreateAnnotationManagers() async {
    if (_map == null) return;
    _routeLineManager = await _map!.annotations
        .createPolylineAnnotationManager();
    _pinsPointManager = await _map!.annotations.createPointAnnotationManager();
    _driverPointManager = await _map!.annotations
        .createPointAnnotationManager();
  }

  MapThemeMode _effectiveMapThemeFor(_CameraMode mode) {
    return _mapThemeOverride ??
        (mode == _CameraMode.follow ? MapThemeMode.light : MapThemeMode.dark);
  }

  String _styleForTheme(MapThemeMode theme) {
    return theme == MapThemeMode.light
        ? 'mapbox://styles/mapbox/streets-v12'
        : 'mapbox://styles/mapbox/navigation-night-v1';
  }

  String _styleForMode(_CameraMode mode) {
    return _styleForTheme(_effectiveMapThemeFor(mode));
  }

  Future<void> _applyMapStyleForMode() async {
    if (_map == null) return;
    final theme = _effectiveMapThemeFor(_cameraMode);
    final target = _styleForMode(_cameraMode);
    debugPrint(
      '[MAP][STYLE_REQ] theme=${theme == MapThemeMode.light ? 'light' : 'dark'} target=$target active=$_activeMapStyleUri pending=${_pendingMapStyleUri ?? ''}',
    );
    if (_activeMapStyleUri == target) {
      debugPrint('[MAP][STYLE_SKIP] reason=already_active target=$target');
      return;
    }
    if (_pendingMapStyleUri == target) {
      debugPrint('[MAP][STYLE_SKIP] reason=in_flight target=$target');
      return;
    }
    _pendingMapStyleUri = target;
    try {
      debugPrint(
        '[MAP_THEME] selected=${theme == MapThemeMode.light ? 'light' : 'dark'} style=$target',
      );
      await _map!.style.setStyleURI(target);
      _activeMapStyleUri = target;
      _mapRedrawCountThisMinute += 1;
      await _recreateAnnotationManagers();
      _driverMarker = null;
      _pickupPin = null;
      _dropoffPin = null;
      _routeLine = null;
      _routeLineOutline = null;
      if (_routeCoords.length >= 2) {
        await _drawRouteLine(_routeCoords);
        await _drawPins(_routeCoords.first, _routeCoords.last);
      }
      if (_lastPos != null) {
        await _updateDriverMarker(_lastPos!);
      }
      debugPrint(
        '[MAP_THEME] redraw route=${_routeCoords.length >= 2} marker=${_lastPos != null} pins=${_routeCoords.length >= 2}',
      );
      debugPrint('[MAP][STYLE_DONE] target=$target');
    } catch (e) {
      debugPrint('[MAP][STYLE_SKIP] reason=error target=$target error=$e');
    } finally {
      if (_pendingMapStyleUri == target) {
        _pendingMapStyleUri = null;
      }
    }
  }

  Future<void> _setMapTheme(MapThemeMode theme) async {
    if (!mounted) return;
    setState(() => _mapThemeOverride = theme);
    await _applyMapStyleForMode();
  }

  mb.Point _mbPoint(double lon, double lat) =>
      mb.Point(coordinates: mb.Position(lon, lat));

  double _metersBetween(_LonLat a, _LonLat b) {
    return geo.Geolocator.distanceBetween(a.lat, a.lon, b.lat, b.lon);
  }

  double _snapThresholdFor(geo.Position pos) {
    final accuracy = pos.accuracy.isFinite && pos.accuracy > 0
        ? pos.accuracy
        : 20.0;
    return math.max(35.0, math.min(90.0, accuracy * 1.8));
  }

  bool _canSnapToRoute(geo.Position pos, _RouteSnap? snap) {
    if (snap == null) return false;
    return snap.distanceFromRouteM <= _snapThresholdFor(pos);
  }

  _RouteSnap? _snapToRouteOn(List<_LonLat> routeCoords, _LonLat raw) {
    if (routeCoords.length < 2) return null;
    final refLatRad = raw.lat * math.pi / 180.0;
    const metersPerDegLat = 111320.0;
    final metersPerDegLon = math.max(
      1.0,
      metersPerDegLat * math.cos(refLatRad),
    );

    var bestDistance = double.infinity;
    var bestAlong = 0.0;
    var bestSegment = 0;
    var bestT = 0.0;
    _LonLat? bestPoint;
    var cumulative = 0.0;

    for (var i = 0; i < routeCoords.length - 1; i++) {
      final a = routeCoords[i];
      final b = routeCoords[i + 1];
      final ax = (a.lon - raw.lon) * metersPerDegLon;
      final ay = (a.lat - raw.lat) * metersPerDegLat;
      final bx = (b.lon - raw.lon) * metersPerDegLon;
      final by = (b.lat - raw.lat) * metersPerDegLat;
      final vx = bx - ax;
      final vy = by - ay;
      final len2 = vx * vx + vy * vy;
      final t = len2 <= 0 ? 0.0 : ((-ax * vx - ay * vy) / len2).clamp(0.0, 1.0);
      final px = ax + vx * t;
      final py = ay + vy * t;
      final approxDistance = math.sqrt(px * px + py * py);
      final segmentMeters = _metersBetween(a, b);
      if (approxDistance < bestDistance) {
        bestDistance = approxDistance;
        bestAlong = cumulative + segmentMeters * t;
        bestSegment = i;
        bestT = t;
        bestPoint = _LonLat(
          a.lon + (b.lon - a.lon) * t,
          a.lat + (b.lat - a.lat) * t,
        );
      }
      cumulative += segmentMeters;
    }

    final point = bestPoint;
    if (point == null || !bestDistance.isFinite) return null;
    return _RouteSnap(
      point: point,
      distanceFromRouteM: bestDistance,
      distanceAlongRouteM: bestAlong,
      segmentIndex: bestSegment,
      segmentT: bestT,
    );
  }

  _RouteSnap? _snapToRoute(_LonLat raw) => _snapToRouteOn(_routeCoords, raw);

  double _distanceAlongRouteFor(_LonLat point) {
    return _snapToRoute(point)?.distanceAlongRouteM ?? 0.0;
  }

  double _distanceAlongRouteForCoords(
    List<_LonLat> routeCoords,
    _LonLat point,
  ) {
    return _snapToRouteOn(routeCoords, point)?.distanceAlongRouteM ?? 0.0;
  }

  void _updateRouteSnapState(geo.Position pos) {
    final snap = _snapToRoute(_LonLat(pos.longitude, pos.latitude));
    _lastRouteSnap = snap;
    if (snap == null) return;

    final offRouteThreshold = math.max(70.0, _snapThresholdFor(pos) + 25.0);
    if (snap.distanceFromRouteM > offRouteThreshold) {
      _offRouteHitCount += 1;
    } else {
      _offRouteHitCount = 0;
    }
    final offRoute = _offRouteHitCount >= 3;
    if (offRoute != _offRouteLikely) {
      _offRouteLikely = offRoute;
    }
  }

  _LonLat _displayRoutePointFor(geo.Position pos) {
    final snap =
        _lastRouteSnap ?? _snapToRoute(_LonLat(pos.longitude, pos.latitude));
    if (_canSnapToRoute(pos, snap)) return snap!.point;
    return _LonLat(pos.longitude, pos.latitude);
  }

  double? _routeBearingAtSnap(_RouteSnap? snap) {
    if (snap == null || _routeCoords.length < 2) return null;
    final i = snap.segmentIndex.clamp(0, _routeCoords.length - 2);
    final a = _routeCoords[i];
    final b = _routeCoords[i + 1];
    return _bearingFromPoints(a.lat, a.lon, b.lat, b.lon);
  }

  Future<void> _updateDriverMarker(
    geo.Position pos, {
    bool moveCamera = false,
  }) async {
    final mgr = _driverPointManager;
    if (mgr == null) return;

    final displayPoint = _displayRoutePointFor(pos);
    final p = _mbPoint(displayPoint.lon, displayPoint.lat);
    final bearingData = _driverBearingFor(pos);
    final markerBearing =
        _routeBearingAtSnap(_lastRouteSnap) ?? bearingData.bearing;

    if (_driverMarker == null) {
      try {
        _driverMarkerIcon = 'triangle-15';
        _driverMarker = await mgr.create(
          mb.PointAnnotationOptions(
            geometry: p,
            iconImage: _driverMarkerIcon,
            iconColor: 0xFFFFD21F,
            iconSize: 1.5,
            iconRotate: markerBearing,
          ),
        );
      } catch (_) {
        _driverMarkerIcon = 'marker-15';
        _driverMarker = await mgr.create(
          mb.PointAnnotationOptions(
            geometry: p,
            iconImage: _driverMarkerIcon,
            iconColor: 0xFFFFD21F,
            iconSize: 1.7,
            iconRotate: markerBearing,
          ),
        );
      }
    } else {
      _driverMarker!.geometry = p;
      _driverMarker!.iconRotate = markerBearing;
      await mgr.update(_driverMarker!);
    }

    if (moveCamera && _cameraMode != _CameraMode.follow) {
      await _map?.flyTo(
        mb.CameraOptions(center: p, zoom: 13.5),
        mb.MapAnimationOptions(duration: 700),
      );
    }
  }

  Future<void> _followCameraTesla(
    geo.Position pos, {
    bool force = false,
  }) async {
    final now = DateTime.now();
    final last = _lastFollowCameraAt;
    if (!force && last != null && now.difference(last).inMilliseconds < 750) {
      return;
    }
    if (!force && _followCameraInFlight) return;
    _lastFollowCameraAt = now;
    _followCameraInFlight = true;
    final displayPoint = _displayRoutePointFor(pos);
    final p = _mbPoint(displayPoint.lon, displayPoint.lat);
    final heading =
        _routeBearingAtSnap(_lastRouteSnap) ?? _cameraBearingFor(pos);

    try {
      await _map?.flyTo(
        mb.CameraOptions(
          center: p,
          zoom: 18.8,
          bearing: heading,
          pitch: 68.0,
          padding: mb.MbxEdgeInsets(
            top: MediaQuery.of(context).padding.top + 120,
            left: 24,
            bottom: MediaQuery.of(context).padding.bottom + 260,
            right: 24,
          ),
        ),
        mb.MapAnimationOptions(duration: 500),
      );
    } finally {
      _followCameraInFlight = false;
    }
  }

  void _updateNextNavInstruction(geo.Position pos) {
    if (_routeSteps.isEmpty) {
      if (_nextNavInstruction != null ||
          _nextNavStreet != null ||
          _nextNavDistanceM != null ||
          _nextNavType != null ||
          _nextNavModifier != null) {
        if (mounted) {
          setState(() {
            _nextNavInstruction = null;
            _nextNavStreet = null;
            _nextNavDistanceM = null;
            _nextNavType = null;
            _nextNavModifier = null;
          });
        } else {
          _nextNavInstruction = null;
          _nextNavStreet = null;
          _nextNavDistanceM = null;
          _nextNavType = null;
          _nextNavModifier = null;
        }
      }
      return;
    }

    final snap =
        _lastRouteSnap ?? _snapToRoute(_LonLat(pos.longitude, pos.latitude));
    final progressM = _canSnapToRoute(pos, snap)
        ? snap!.distanceAlongRouteM
        : null;
    while (_nextStepIndex < _routeSteps.length - 1) {
      final current = _routeSteps[_nextStepIndex];
      final straightLineM = geo.Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        current.lat,
        current.lon,
      );
      final passedByRouteProgress =
          progressM != null && progressM >= current.distanceAlongRouteM + 18.0;
      if (straightLineM <= 32 || passedByRouteProgress) {
        _nextStepIndex += 1;
      } else {
        break;
      }
    }

    final step = _routeSteps[_nextStepIndex];
    final distanceM = progressM == null
        ? geo.Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            step.lat,
            step.lon,
          )
        : math.max(0.0, step.distanceAlongRouteM - progressM);

    if (!mounted) {
      _nextNavInstruction = step.instruction;
      _nextNavStreet = step.street;
      _nextNavDistanceM = distanceM;
      _nextNavType = step.type;
      _nextNavModifier = step.modifier;
      return;
    }

    setState(() {
      _nextNavInstruction = step.instruction;
      _nextNavStreet = step.street;
      _nextNavDistanceM = distanceM;
      _nextNavType = step.type;
      _nextNavModifier = step.modifier;
    });
  }

  Future<void> _buildNavRouteToPickup(BookingItem b) async {
    final epoch = _routeCleanupEpoch;
    final expectedBookingId = b.bookingId;
    if (!_isRouteTaskStillValid(
      epoch: epoch,
      expectedBookingId: expectedBookingId,
    )) {
      return;
    }
    if (_lastPos == null) return;
    final pickupText = (b.from ?? '').trim();
    if (pickupText.isEmpty) return;
    if (mounted) {
      setState(() {
        _routePhase = _RideRoutePhase.toPickup;
        _navStepsLoading = true;
      });
    } else {
      _routePhase = _RideRoutePhase.toPickup;
      _navStepsLoading = true;
    }
    debugPrint('[NAV_PHASE] toPickup');
    try {
      final fromLL = _LonLat(_lastPos!.longitude, _lastPos!.latitude);
      final toLL = await _geocodeOne(pickupText);
      final route = await _directionsRoute(fromLL, toLL);
      final coords = route.$1;
      if (coords.length < 2) return;
      if (!_isRouteTaskStillValid(
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      )) {
        return;
      }
      if (mounted) {
        setState(() {
          _routeCoords = coords;
          _routeKm = route.$2 / 1000.0;
          _routeDurationSec = route.$3;
        });
      } else {
        _routeCoords = coords;
        _routeKm = route.$2 / 1000.0;
        _routeDurationSec = route.$3;
      }
      if (_lastPos != null) {
        _updateRouteSnapState(_lastPos!);
        _updateNextNavInstruction(_lastPos!);
      }
      await _drawPins(fromLL, toLL);
      await _drawRouteLine(coords);
    } catch (_) {
      // Keep previous route if pickup route fetch fails.
    } finally {
      if (_isRouteTaskStillValid(
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      )) {
        if (mounted) {
          setState(() => _navStepsLoading = false);
        } else {
          _navStepsLoading = false;
        }
      }
    }
  }

  Future<void> _buildNavRouteToDestination(BookingItem b) async {
    final epoch = _routeCleanupEpoch;
    final expectedBookingId = b.bookingId;
    if (!_isRouteTaskStillValid(
      epoch: epoch,
      expectedBookingId: expectedBookingId,
    )) {
      return;
    }
    if (_lastPos == null) return;
    final dropoffText = (b.to ?? '').trim();
    if (dropoffText.isEmpty) return;
    if (mounted) {
      setState(() {
        _routePhase = _RideRoutePhase.trip;
        _navStepsLoading = true;
      });
    } else {
      _routePhase = _RideRoutePhase.trip;
      _navStepsLoading = true;
    }
    debugPrint('[NAV_PHASE] trip');
    try {
      final fromLL = _LonLat(_lastPos!.longitude, _lastPos!.latitude);
      final toLL = await _geocodeOne(dropoffText);
      final route = await _directionsRoute(fromLL, toLL);
      final coords = route.$1;
      if (coords.length < 2) return;
      if (!_isRouteTaskStillValid(
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      )) {
        return;
      }
      if (mounted) {
        setState(() {
          _routeCoords = coords;
          _routeKm = route.$2 / 1000.0;
          _routeDurationSec = route.$3;
        });
      } else {
        _routeCoords = coords;
        _routeKm = route.$2 / 1000.0;
        _routeDurationSec = route.$3;
      }
      if (_lastPos != null) {
        _updateRouteSnapState(_lastPos!);
        _updateNextNavInstruction(_lastPos!);
      }
      await _drawPins(fromLL, toLL);
      await _drawRouteLine(coords);
    } catch (_) {
      // Keep previous route if destination route fetch fails.
    } finally {
      if (_isRouteTaskStillValid(
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      )) {
        if (mounted) {
          setState(() => _navStepsLoading = false);
        } else {
          _navStepsLoading = false;
        }
      }
    }
  }

  Future<void> _buildDirectRouteToDestination(String destinationText) async {
    final epoch = _routeCleanupEpoch;
    if (!_isRouteTaskStillValid(epoch: epoch, requireDirectRide: true)) {
      return;
    }
    if (_lastPos == null) return;
    final dropoffText = destinationText.trim();
    if (dropoffText.isEmpty) return;
    if (mounted) {
      setState(() {
        _routePhase = _RideRoutePhase.trip;
        _navStepsLoading = true;
      });
    } else {
      _routePhase = _RideRoutePhase.trip;
      _navStepsLoading = true;
    }
    debugPrint('[NAV_PHASE] direct_trip');
    try {
      final fromLL = _LonLat(_lastPos!.longitude, _lastPos!.latitude);
      final toLL =
          _directRideDestinationPoint ?? await _geocodeOne(dropoffText);
      final route = await _directionsRoute(fromLL, toLL);
      final coords = route.$1;
      if (coords.length < 2) return;
      if (!_isRouteTaskStillValid(epoch: epoch, requireDirectRide: true)) {
        return;
      }
      if (mounted) {
        setState(() {
          _routeCoords = coords;
          _routeKm = route.$2 / 1000.0;
          _routeDurationSec = route.$3;
        });
      } else {
        _routeCoords = coords;
        _routeKm = route.$2 / 1000.0;
        _routeDurationSec = route.$3;
      }
      if (_lastPos != null) {
        _updateRouteSnapState(_lastPos!);
        _updateNextNavInstruction(_lastPos!);
      }
      await _drawPins(fromLL, toLL);
      await _drawRouteLine(coords);
    } catch (e) {
      _toast('Straatrit route mislukt: $e');
    } finally {
      if (_isRouteTaskStillValid(epoch: epoch, requireDirectRide: true)) {
        if (mounted) {
          setState(() => _navStepsLoading = false);
        } else {
          _navStepsLoading = false;
        }
      }
    }
  }

  Future<void> _forceFollowCameraNow({required String caller}) async {
    geo.Position? pos = _lastPos;
    if (pos == null) {
      try {
        pos = await geo.Geolocator.getCurrentPosition(
          desiredAccuracy: geo.LocationAccuracy.best,
        );
        _lastPos = pos;
      } catch (_) {
        pos = null;
      }
    }

    if (pos == null) {
      _toast('GPS-locatie nog niet beschikbaar');
      return;
    }
    await _followCameraTesla(pos, force: true);
  }

  double _cameraBearingFor(geo.Position pos) {
    if (pos.heading.isFinite && pos.heading >= 0) return pos.heading;
    if (_lastKnownBearing.isFinite) return _lastKnownBearing;
    return 0.0;
  }

  ({double bearing, String source}) _driverBearingFor(geo.Position pos) {
    if (pos.heading.isFinite && pos.heading >= 0) {
      return (bearing: pos.heading, source: 'gps_heading');
    }
    if (_lastKnownBearing.isFinite) {
      return (bearing: _lastKnownBearing, source: 'movement_or_last');
    }
    return (bearing: 0.0, source: 'default_0');
  }

  double? _bearingFromPoints(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const degToRad = math.pi / 180.0;
    const radToDeg = 180.0 / math.pi;
    final dLon = (lon2 - lon1) * degToRad;
    final y = math.sin(dLon) * math.cos(lat2 * degToRad);
    final x =
        math.cos(lat1 * degToRad) * math.sin(lat2 * degToRad) -
        math.sin(lat1 * degToRad) * math.cos(lat2 * degToRad) * math.cos(dLon);
    if (!x.isFinite || !y.isFinite) return null;
    final brng = math.atan2(y, x) * radToDeg;
    return (brng + 360.0) % 360.0;
  }

  Future<geo.Position?> _fetchCurrentPositionForRecenter() async {
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[GPS][RECENTER][SERVICE_DISABLED]');
      _toast(
        _tr(
          nl: 'Locatieservice staat uit. Zet GPS aan om te centreren.',
          en: 'Location service is disabled. Enable GPS to recenter.',
          fr: 'Le service de localisation est desactive. Activez le GPS pour recentrer.',
          es: 'El servicio de ubicacion esta desactivado. Activa el GPS para recentrar.',
        ),
      );
      return null;
    }

    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    if (permission == geo.LocationPermission.denied ||
        permission == geo.LocationPermission.deniedForever) {
      debugPrint('[GPS][RECENTER][PERMISSION_DENIED]');
      _toast(
        _tr(
          nl: 'Geen locatiepermissie. Geef toegang om te centreren.',
          en: 'Location permission denied. Grant access to recenter.',
          fr: 'Permission de localisation refusee. Autorisez-la pour recentrer.',
          es: 'Permiso de ubicacion denegado. Concedelo para recentrar.',
        ),
      );
      return null;
    }

    debugPrint('[GPS][RECENTER][FETCH_START]');
    try {
      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.best,
      ).timeout(const Duration(seconds: 10));
      debugPrint(
        '[GPS][RECENTER][FETCH_OK] lat=${pos.latitude.toStringAsFixed(6)} lng=${pos.longitude.toStringAsFixed(6)}',
      );
      return pos;
    } catch (e) {
      debugPrint('[GPS][RECENTER][ERROR] $e');
      _toast(
        _tr(
          nl: 'GPS-positie ophalen mislukt. Probeer opnieuw.',
          en: 'Failed to get GPS position. Please try again.',
          fr: 'Impossible de recuperer la position GPS. Reessayez.',
          es: 'No se pudo obtener la posicion GPS. Intentalo de nuevo.',
        ),
      );
      return null;
    }
  }

  Future<void> _centerOnMe() async {
    debugPrint('[GPS][RECENTER][TAP]');
    geo.Position? pos = _lastPos;
    if (pos != null) {
      debugPrint('[GPS][RECENTER][CACHE_HIT]');
    } else {
      pos = await _fetchCurrentPositionForRecenter();
      if (pos == null) return;
      _lastPos = pos;
    }

    if (_mapSupported && _map != null && _driverPointManager != null) {
      await _updateDriverMarker(pos, moveCamera: false);
    }

    // If NAV is enabled and a trip is active, use navigation follow camera.
    if (_cameraMode == _CameraMode.follow && _liveRideActive) {
      await _followCameraTesla(pos, force: true);
      return;
    }

    final p = _mbPoint(pos.longitude, pos.latitude);
    await _map?.flyTo(
      mb.CameraOptions(center: p, zoom: 13.5),
      mb.MapAnimationOptions(duration: 650),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // -------------------------------
  // ROUTE (Overview -> Follow)
  // -------------------------------

  Future<void> _buildOverviewRoute(BookingItem b) async {
    final epoch = _routeCleanupEpoch;
    final expectedBookingId = b.bookingId;
    if (!_isRouteTaskStillValid(
      epoch: epoch,
      expectedBookingId: expectedBookingId,
    )) {
      return;
    }
    if (!_mapSupported || _map == null) return;
    if ((b.from ?? '').isEmpty || (b.to ?? '').isEmpty) return;

    try {
      final pickupText = (b.from ?? '').trim();
      final dropoffText = (b.to ?? '').trim();
      // Preview must always represent booked ride path: pickup -> destination.
      // Never use current GPS here.
      try {
        if (_routeLineManager != null && _routeLineOutline != null) {
          await _routeLineManager!.delete(_routeLineOutline!);
        }
        if (_routeLineManager != null && _routeLine != null) {
          await _routeLineManager!.delete(_routeLine!);
        }
        _routeLineOutline = null;
        _routeLine = null;
        if (_pinsPointManager != null) {
          if (_pickupPin != null) await _pinsPointManager!.delete(_pickupPin!);
          if (_dropoffPin != null)
            await _pinsPointManager!.delete(_dropoffPin!);
        }
        _pickupPin = null;
        _dropoffPin = null;
      } catch (_) {}

      // Prefer server-side routing (Worker) so the app never needs to call Mapbox Directions directly.
      await _tryWorkerRouteFallback(
        fromText: pickupText,
        toText: dropoffText,
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      );
      if (_routeCoords.length >= 2) return;

      // Fallback: direct Mapbox REST (dev only). If MAPBOX_TOKEN isn't provided, we stop here.
      if (kMapboxToken.trim().isEmpty) {
        await _tryWorkerRouteFallback(
          fromText: pickupText,
          toText: dropoffText,
          epoch: epoch,
          expectedBookingId: expectedBookingId,
        );
        return;
      }

      final fromLL = await _geocodeOne(pickupText);
      final toLL = await _geocodeOne(dropoffText);

      final route = await _directionsRoute(fromLL, toLL);
      final coords = route.$1;
      final distanceMeters = route.$2;
      final durationSec = route.$3;

      if (coords.length < 2) return;
      if (!_isRouteTaskStillValid(
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      )) {
        return;
      }

      setState(() {
        _routeCoords = coords;
        _routeKm = distanceMeters / 1000.0;
        _routeDurationSec = durationSec;
        _routePhase = _RideRoutePhase.trip;
      });
      await _drawPins(fromLL, toLL);
      await _drawRouteLine(coords);
      final allowFit =
          _allowOverviewCamera &&
          _cameraMode == _CameraMode.overview &&
          _activeTripId == null;
      if (allowFit) {
        await _fitBoundsToRoute(coords);
      }
    } on _UnauthorizedMapbox catch (_) {
      _toast('Mapbox REST token refused (401) — using Worker route instead.');
      await _tryWorkerRouteFallback(
        fromText: b.from!,
        toText: b.to!,
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      );
    } catch (e) {
      _toast('Route overview failed: $e');
      await _tryWorkerRouteFallback(
        fromText: b.from!,
        toText: b.to!,
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      );
    }
  }

  Future<void> _tryWorkerRouteFallback({
    required String fromText,
    required String toText,
    required int epoch,
    required String expectedBookingId,
  }) async {
    try {
      final uri = Uri.parse('$kWorkerBaseUrl$kWorkerRoutePath');
      final payload = {'from': fromText, 'to': toText};

      final res = await http
          .post(uri, headers: _headers(admin: true), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 404) {
        _toast(
          'Route via Worker not available yet (404). Implement $kWorkerRoutePath to avoid exposing Mapbox token.',
        );
        return;
      }

      if (res.statusCode != 200) {
        throw Exception('Worker route HTTP ${res.statusCode}: ${res.body}');
      }

      final j = jsonDecode(res.body) as Map<String, dynamic>;

      final coordsAny =
          (j['coords'] ?? j['coordinates'] ?? j['route_coords'] ?? j['points']);
      List<dynamic> raw;
      if (coordsAny is List) {
        raw = coordsAny;
      } else if (j['geometry'] is Map<String, dynamic>) {
        raw = (j['geometry']['coordinates'] as List<dynamic>? ?? []);
      } else {
        raw = const [];
      }

      final out = <_LonLat>[];
      for (final c in raw) {
        if (c is List && c.length >= 2) {
          out.add(_LonLat((c[0] as num).toDouble(), (c[1] as num).toDouble()));
        }
      }

      if (out.length < 2) return;
      if (!_isRouteTaskStillValid(
        epoch: epoch,
        expectedBookingId: expectedBookingId,
      )) {
        return;
      }

      final dist =
          (j['distance_m'] ?? j['distanceMeters'] ?? j['distance'] ?? 0) as num;
      final dur =
          (j['duration_s'] ?? j['durationSec'] ?? j['duration'] ?? 0) as num;

      final fromLL = out.first;
      final toLL = out.last;

      setState(() {
        _routeCoords = out;
        _routeKm = dist.toDouble() / 1000.0;
        _routeDurationSec = dur.toInt();
        _routePhase = _RideRoutePhase.trip;
      });
      await _drawPins(fromLL, toLL);
      await _drawRouteLine(out);
      final allowFit =
          _allowOverviewCamera &&
          _cameraMode == _CameraMode.overview &&
          _activeTripId == null;
      if (allowFit) {
        await _fitBoundsToRoute(out);
      }
    } catch (e) {
      _toast('Worker route failed: $e');
    }
  }

  Future<_LonLat> _geocodeOne(String query) async {
    final q = Uri.encodeComponent(query);
    final uri = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/$q.json'
      '?access_token=$kMapboxToken&limit=1&country=BE&language=nl',
    );

    final res = await http.get(uri).timeout(const Duration(seconds: 12));

    if (res.statusCode == 401) throw _UnauthorizedMapbox('geocoding');
    if (res.statusCode != 200) {
      throw Exception('Geocode HTTP ${res.statusCode}');
    }

    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final feats = (j['features'] as List<dynamic>? ?? []);
    if (feats.isEmpty) throw Exception('No geocode result for "$query"');
    final center =
        (feats.first as Map<String, dynamic>)['center'] as List<dynamic>;
    final lon = (center[0] as num).toDouble();
    final lat = (center[1] as num).toDouble();
    return _LonLat(lon, lat);
  }

  Future<(List<_LonLat>, double, int)> _directionsRoute(
    _LonLat from,
    _LonLat to,
  ) async {
    final coords = '${from.lon},${from.lat};${to.lon},${to.lat}';
    final lang = _mapboxDirectionsLanguageCode();
    final uri = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/driving/$coords'
      '?alternatives=false&geometries=geojson&overview=full&steps=true'
      '&language=$lang'
      '&access_token=$kMapboxToken',
    );

    final res = await http.get(uri).timeout(const Duration(seconds: 15));

    if (res.statusCode == 401) throw _UnauthorizedMapbox('directions');
    if (res.statusCode != 200) {
      throw Exception('Directions HTTP ${res.statusCode}');
    }

    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final routes = (j['routes'] as List<dynamic>? ?? []);
    if (routes.isEmpty) throw Exception('No route returned.');
    final r0 = routes.first as Map<String, dynamic>;
    final distance = (r0['distance'] as num?)?.toDouble() ?? 0.0;
    final duration = (r0['duration'] as num?)?.toInt() ?? 0;
    final geom = (r0['geometry'] as Map<String, dynamic>?) ?? {};
    final line = (geom['coordinates'] as List<dynamic>? ?? []);
    final out = <_LonLat>[];
    for (final c in line) {
      final pair = c as List<dynamic>;
      out.add(
        _LonLat((pair[0] as num).toDouble(), (pair[1] as num).toDouble()),
      );
    }
    final navSteps = <_NavStep>[];
    final legs = (r0['legs'] as List<dynamic>? ?? const <dynamic>[]);
    for (final legAny in legs) {
      final leg = (legAny is Map<String, dynamic>)
          ? legAny
          : <String, dynamic>{};
      final steps = (leg['steps'] as List<dynamic>? ?? const <dynamic>[]);
      for (final stepAny in steps) {
        final step = (stepAny is Map<String, dynamic>)
            ? stepAny
            : <String, dynamic>{};
        final maneuver = (step['maneuver'] is Map<String, dynamic>)
            ? (step['maneuver'] as Map<String, dynamic>)
            : <String, dynamic>{};
        final loc =
            (maneuver['location'] as List<dynamic>? ?? const <dynamic>[]);
        if (loc.length < 2) continue;
        final lon = (loc[0] as num?)?.toDouble();
        final lat = (loc[1] as num?)?.toDouble();
        if (lat == null || lon == null) continue;
        final rawInstruction = (maneuver['instruction'] ?? '')
            .toString()
            .trim();
        final instruction = _localizeNavInstructionMvp(rawInstruction);
        final street = (step['name'] ?? '').toString().trim();
        final type = (maneuver['type'] ?? '').toString().trim();
        final modifier = (maneuver['modifier'] ?? '').toString().trim();
        final stepDistance = (step['distance'] as num?)?.toDouble();
        final stepDuration = (step['duration'] as num?)?.toInt();
        if (instruction.isEmpty && street.isEmpty) continue;
        navSteps.add(
          _NavStep(
            lat: lat,
            lon: lon,
            instruction: instruction,
            street: street,
            type: type,
            modifier: modifier,
            distanceAlongRouteM: _distanceAlongRouteForCoords(
              out,
              _LonLat(lon, lat),
            ),
            distanceM: stepDistance,
            durationSec: stepDuration,
          ),
        );
      }
    }
    _routeSteps = navSteps;
    _nextStepIndex = 0;
    if (navSteps.isNotEmpty) {
      _nextNavInstruction = navSteps.first.instruction;
      _nextNavStreet = navSteps.first.street;
      _nextNavDistanceM = null;
      _nextNavType = navSteps.first.type;
      _nextNavModifier = navSteps.first.modifier;
    } else {
      _nextNavInstruction = null;
      _nextNavStreet = null;
      _nextNavDistanceM = null;
      _nextNavType = null;
      _nextNavModifier = null;
    }
    debugPrint('[NAV_STEPS] count=${navSteps.length}');
    return (out, distance, duration);
  }

  String _mapboxDirectionsLanguageCode() {
    final lang = appConfig.currentLanguage;
    if (lang == AppLanguage.fr) return 'fr';
    if (lang == AppLanguage.es) return 'es';
    if (lang == AppLanguage.en) return 'en';
    return 'nl';
  }

  String _localizeNavInstructionMvp(String raw) {
    if (raw.isEmpty) return raw;
    final lang = appConfig.currentLanguage;
    if (lang == AppLanguage.en) return raw;
    final lower = raw.toLowerCase();

    if (lower.contains('your destination is on the left')) {
      return _tr(
        nl: 'Je bestemming bevindt zich links',
        en: 'Your destination is on the left',
        fr: 'Votre destination se trouve sur la gauche',
        es: 'Tu destino está a la izquierda',
      );
    }
    if (lower.contains('your destination is on the right')) {
      return _tr(
        nl: 'Je bestemming bevindt zich rechts',
        en: 'Your destination is on the right',
        fr: 'Votre destination se trouve sur la droite',
        es: 'Tu destino está a la derecha',
      );
    }
    if (lower.startsWith('turn left') || lower.contains(' turn left')) {
      return _tr(
        nl: 'Sla linksaf',
        en: 'Turn left',
        fr: 'Tournez à gauche',
        es: 'Gira a la izquierda',
      );
    }
    if (lower.startsWith('turn right') || lower.contains(' turn right')) {
      return _tr(
        nl: 'Sla rechtsaf',
        en: 'Turn right',
        fr: 'Tournez à droite',
        es: 'Gira a la derecha',
      );
    }
    if (lower.startsWith('continue') || lower.contains(' continue')) {
      return _tr(
        nl: 'Rijd rechtdoor',
        en: 'Continue',
        fr: 'Continuez',
        es: 'Continúa',
      );
    }
    return raw;
  }

  String _navDistanceText(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000.0).toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  bool _navTypeIsArrival(String? type) {
    final t = (type ?? '').toLowerCase();
    return t.contains('arrive') || t.contains('destination');
  }

  bool _navTypeIsRoundabout(String? type) {
    final t = (type ?? '').toLowerCase();
    return t.contains('roundabout') || t.contains('rotary');
  }

  String _shortNavAction(String instruction, String? type, String? modifier) {
    if (_navTypeIsArrival(type)) {
      return _tr(
        nl: 'bestemming bereikt',
        en: 'destination reached',
        fr: 'destination atteinte',
        es: 'destino alcanzado',
      );
    }
    if (_navTypeIsRoundabout(type)) {
      return _tr(
        nl: 'neem de rotonde',
        en: 'take the roundabout',
        fr: 'prenez le rond-point',
        es: 'toma la rotonda',
      );
    }
    final mod = (modifier ?? '').toLowerCase();
    if (mod.contains('slight left')) {
      return _tr(
        nl: 'flauw linksaf',
        en: 'slight left',
        fr: 'légèrement à gauche',
        es: 'ligeramente a la izquierda',
      );
    }
    if (mod.contains('slight right')) {
      return _tr(
        nl: 'flauw rechtsaf',
        en: 'slight right',
        fr: 'légèrement à droite',
        es: 'ligeramente a la derecha',
      );
    }
    if (mod.contains('left')) {
      return _tr(
        nl: 'linksaf',
        en: 'turn left',
        fr: 'tournez à gauche',
        es: 'gira a la izquierda',
      );
    }
    if (mod.contains('right')) {
      return _tr(
        nl: 'rechtsaf',
        en: 'turn right',
        fr: 'tournez à droite',
        es: 'gira a la derecha',
      );
    }
    if (mod.contains('straight') || mod.contains('forward')) {
      return _tr(
        nl: 'rechtdoor',
        en: 'continue straight',
        fr: 'continuez tout droit',
        es: 'sigue recto',
      );
    }

    final lower = instruction.toLowerCase();
    if (lower.contains('links') ||
        lower.contains('left') ||
        lower.contains('gauche')) {
      return _tr(
        nl: 'linksaf',
        en: 'turn left',
        fr: 'tournez à gauche',
        es: 'gira a la izquierda',
      );
    }
    if (lower.contains('rechts') ||
        lower.contains('right') ||
        lower.contains('droite')) {
      return _tr(
        nl: 'rechtsaf',
        en: 'turn right',
        fr: 'tournez à droite',
        es: 'gira a la derecha',
      );
    }
    if (lower.contains('rotonde') ||
        lower.contains('roundabout') ||
        lower.contains('rond-point')) {
      return _tr(
        nl: 'neem de rotonde',
        en: 'take the roundabout',
        fr: 'prenez le rond-point',
        es: 'toma la rotonda',
      );
    }
    if (lower.contains('rechtdoor') ||
        lower.contains('continue') ||
        lower.contains('straight')) {
      return _tr(
        nl: 'rechtdoor',
        en: 'continue straight',
        fr: 'continuez tout droit',
        es: 'sigue recto',
      );
    }
    return instruction;
  }

  IconData _maneuverIconData(
    String? type,
    String? modifier,
    String instruction,
  ) {
    if (_navTypeIsArrival(type)) return Icons.flag_rounded;
    if (_navTypeIsRoundabout(type)) return Icons.roundabout_right_rounded;
    final combined = '${modifier ?? ''} $instruction'.toLowerCase();
    if (combined.contains('slight left')) return Icons.turn_slight_left_rounded;
    if (combined.contains('slight right'))
      return Icons.turn_slight_right_rounded;
    if (combined.contains('left') ||
        combined.contains('links') ||
        combined.contains('gauche')) {
      return Icons.turn_left_rounded;
    }
    if (combined.contains('right') ||
        combined.contains('rechts') ||
        combined.contains('droite')) {
      return Icons.turn_right_rounded;
    }
    if ((type ?? '').toLowerCase().contains('exit') ||
        combined.contains('exit') ||
        combined.contains('afrit')) {
      return Icons.call_split_rounded;
    }
    return Icons.straight_rounded;
  }

  Future<void> _drawPins(_LonLat pickup, _LonLat dropoff) async {
    final mgr = _pinsPointManager;
    if (mgr == null) return;
    final now = DateTime.now();
    final signature =
        '${pickup.lon.toStringAsFixed(5)},${pickup.lat.toStringAsFixed(5)}|${dropoff.lon.toStringAsFixed(5)},${dropoff.lat.toStringAsFixed(5)}';
    final lastPinsAt = _lastPinsDrawAt;
    if (signature == _lastPinsDrawSignature &&
        lastPinsAt != null &&
        now.difference(lastPinsAt) < _routeDrawDebounce) {
      return;
    }
    _lastPinsDrawSignature = signature;
    _lastPinsDrawAt = now;

    try {
      if (_pickupPin != null) await mgr.delete(_pickupPin!);
      if (_dropoffPin != null) await mgr.delete(_dropoffPin!);
    } catch (_) {}

    _pickupPin = await mgr.create(
      mb.PointAnnotationOptions(
        geometry: _mbPoint(pickup.lon, pickup.lat),
        iconSize: 1.1,
      ),
    );

    _dropoffPin = await mgr.create(
      mb.PointAnnotationOptions(
        geometry: _mbPoint(dropoff.lon, dropoff.lat),
        iconSize: 1.1,
      ),
    );
  }

  Future<void> _drawRouteLine(List<_LonLat> coords) async {
    final mgr = _routeLineManager;
    if (mgr == null) return;
    if (coords.length < 2) return;
    final first = coords.first;
    final last = coords.last;
    final now = DateTime.now();
    final signature =
        '${coords.length}:${first.lon.toStringAsFixed(5)},${first.lat.toStringAsFixed(5)}>${last.lon.toStringAsFixed(5)},${last.lat.toStringAsFixed(5)}';
    final lastRouteAt = _lastRouteDrawAt;
    if (signature == _lastRouteDrawSignature &&
        lastRouteAt != null &&
        now.difference(lastRouteAt) < _routeDrawDebounce) {
      return;
    }
    _lastRouteDrawSignature = signature;
    _lastRouteDrawAt = now;
    _routeRedrawCountThisMinute += 1;

    try {
      if (_routeLineOutline != null) await mgr.delete(_routeLineOutline!);
      if (_routeLine != null) await mgr.delete(_routeLine!);
    } catch (_) {}

    final geometry = mb.LineString(
      coordinates: coords.map((c) => mb.Position(c.lon, c.lat)).toList(),
    );

    // Dark underlay for contrast on light/dark roads.
    _routeLineOutline = await mgr.create(
      mb.PolylineAnnotationOptions(
        geometry: geometry,
        lineWidth: 15.0,
        lineOpacity: 0.62,
        lineColor: 0xCC0B1220,
      ),
    );

    // Bright active route shown above the outline.
    _routeLine = await mgr.create(
      mb.PolylineAnnotationOptions(
        geometry: geometry,
        lineWidth: 11.0,
        lineOpacity: 0.98,
        lineColor: 0xFF2D8CFF,
      ),
    );
  }

  Future<void> _fitBoundsToRoute(List<_LonLat> coords) async {
    final skip =
        _cameraMode == _CameraMode.follow ||
        _activeTripId != null ||
        !_allowOverviewCamera;
    if (_map == null || coords.isEmpty) return;
    if (skip) return;

    double minLon = coords.first.lon, maxLon = coords.first.lon;
    double minLat = coords.first.lat, maxLat = coords.first.lat;
    for (final c in coords) {
      if (c.lon < minLon) minLon = c.lon;
      if (c.lon > maxLon) maxLon = c.lon;
      if (c.lat < minLat) minLat = c.lat;
      if (c.lat > maxLat) maxLat = c.lat;
    }

    final topPad = MediaQuery.of(context).padding.top + 86;
    final bottomPad = MediaQuery.of(context).padding.bottom + 210;

    try {
      final cam = await _map!.cameraForCoordinateBounds(
        mb.CoordinateBounds(
          southwest: _mbPoint(minLon, minLat),
          northeast: _mbPoint(maxLon, maxLat),
          infiniteBounds: false,
        ),
        mb.MbxEdgeInsets(top: topPad, left: 40, bottom: bottomPad, right: 40),
        null,
        null,
        null,
        null,
      );
      await _map!.flyTo(cam, mb.MapAnimationOptions(duration: 900));
    } catch (_) {
      final center = _mbPoint((minLon + maxLon) / 2, (minLat + maxLat) / 2);
      await _map!.flyTo(
        mb.CameraOptions(center: center, zoom: 12.5),
        mb.MapAnimationOptions(duration: 900),
      );
    }
  }

  void _markBootFirstLoadDone() {
    if (_bootFirstLoadDone) return;
    _bootFirstLoadDone = true;
    _maybeHideBootSplash();
  }

  void _maybeHideBootSplash() {
    if (!_bootSplashVisible) return;
    if (!_bootMinElapsed) return;
    if (!_bootFirstLoadDone) return;
    if (!mounted) return;
    setState(() {
      _bootSplashVisible = false;
      _showBootSplash = false;
    });
  }

  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.55)),
      filled: true,
      fillColor: Colors.black.withOpacity(0.35),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: kGlow, width: 1.2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Future<List<_PlaceSuggestion>> _fetchPlaceSuggestions(String query) async {
    final q = query.trim();
    if (q.isEmpty || kMapboxToken.trim().isEmpty) return <_PlaceSuggestion>[];
    final encoded = Uri.encodeComponent(q);
    final uri = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/$encoded.json'
      '?autocomplete=true&limit=6&country=be&language=nl&access_token=$kMapboxToken',
    );
    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) return <_PlaceSuggestion>[];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final feats = (data['features'] as List<dynamic>? ?? const <dynamic>[]);
      final out = <_PlaceSuggestion>[];
      for (final f in feats) {
        final m = f as Map<String, dynamic>;
        final label = (m['place_name'] as String?) ?? '';
        final center = (m['center'] as List<dynamic>?);
        if (label.trim().isEmpty) continue;
        double? lon;
        double? lat;
        if (center != null && center.length >= 2) {
          lon = (center[0] as num?)?.toDouble();
          lat = (center[1] as num?)?.toDouble();
        }
        out.add(_PlaceSuggestion(label: label, lon: lon, lat: lat));
      }
      return out;
    } catch (_) {
      return <_PlaceSuggestion>[];
    }
  }

  void _onFromChanged(String v) {
    _fromDebounce?.cancel();
    _fromDebounce = Timer(const Duration(milliseconds: 220), () async {
      final list = await _fetchPlaceSuggestions(v);
      if (!mounted) return;
      setState(() => _fromSuggestions = list);
    });
  }

  void _onToChanged(String v) {
    _toDebounce?.cancel();
    _toDebounce = Timer(const Duration(milliseconds: 220), () async {
      final list = await _fetchPlaceSuggestions(v);
      if (!mounted) return;
      setState(() => _toSuggestions = list);
    });
  }

  Future<void> _useCurrentLocationAsFrom() async {
    try {
      final perm = await geo.Geolocator.checkPermission();
      if (perm == geo.LocationPermission.denied ||
          perm == geo.LocationPermission.deniedForever) {
        final req = await geo.Geolocator.requestPermission();
        if (req == geo.LocationPermission.denied ||
            req == geo.LocationPermission.deniedForever)
          return;
      }
      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.best,
      );
      _manualFromPoint = mb.Point(
        coordinates: mb.Position(pos.longitude, pos.latitude),
      );
      _manualFromCtrl.text = 'Mijn locatie';
      setState(() {
        _fromSuggestions = <_PlaceSuggestion>[];
      });
    } catch (_) {}
  }

  Widget _suggestionList({
    required List<_PlaceSuggestion> items,
    required void Function(_PlaceSuggestion) onPick,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F1C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x44FFD54A)),
      ),
      constraints: const BoxConstraints(maxHeight: 220),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        shrinkWrap: true,
        itemCount: items.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Color(0x22000000)),
        itemBuilder: (_, i) {
          final s = items[i];
          return ListTile(
            dense: true,
            title: Text(
              s.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white),
            ),
            onTap: () => onPick(s),
          );
        },
      ),
    );
  }

  Future<void> _startManualTrip() async {
    final from = _manualFromCtrl.text.trim();
    final to = _manualToCtrl.text.trim();
    if (from.isEmpty || to.isEmpty) {
      _toast('Vul zowel "Van" als "Naar" in.');
      return;
    }

    final id = 'MANUAL-${DateTime.now().millisecondsSinceEpoch}';
    final b = BookingItem(
      bookingId: id,
      from: from,
      to: to,
      pickupIso: DateTime.now().toUtc().toIso8601String(),
      status: 'manual',
      currency: 'EUR',
    );

    await _startTrip(b);
  }

  Widget _buildBrandBar(bool tripActive) {
    // Robust top bar: larger logo + stronger presence.
    // Pulse only when a trip is active (cockpit mode).
    final pulse = tripActive ? (0.70 + 0.30 * _activePulse.value) : 0.0;

    return AnimatedBuilder(
      animation: _activePulse,
      builder: (context, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 68,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: kFluxidiPanel.withOpacity(0.88),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
                boxShadow: [
                  BoxShadow(
                    color: kFluxidiYellowSoft.withOpacity(
                      tripActive ? 0.55 * pulse : 0.20,
                    ),
                    blurRadius: tripActive ? (28 * pulse) : 18,
                    spreadRadius: tripActive ? (2 * pulse) : 1,
                  ),
                ],
              ),
              child: Row(
                children: [
                  _GlowIconButton(
                    icon: Icons.menu,
                    tooltip: 'Menu',
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  const SizedBox(width: 10),
                  // Pulsing logo capsule (only on active trip)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: Colors.black.withOpacity(0.18),
                      border: Border.all(
                        color: const Color(0xFFFFD36A).withOpacity(
                          tripActive ? (0.30 + 0.25 * pulse) : 0.18,
                        ),
                      ),
                      boxShadow: tripActive
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0x66F5C400,
                                ).withOpacity(0.55 * pulse),
                                blurRadius: 26 * pulse,
                                spreadRadius: 2 * pulse,
                              ),
                            ]
                          : const [],
                    ),
                    child: Transform.scale(
                      scale: tripActive ? (1.00 + 0.05 * pulse) : 1.0,
                      child: _tenantLogo(
                        height: 40,
                        fallback: Text(
                          kCompanyName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tripActive ? 'Rit actief' : 'Driver console',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.92),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: tripActive
                          ? const Color(0xFF4CD964)
                          : Colors.white38,
                      shape: BoxShape.circle,
                      boxShadow: tripActive
                          ? [
                              BoxShadow(
                                color: const Color(0x554CD964).withOpacity(0.7),
                                blurRadius: 14,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// ===============================
  /// Fluxidi Cockpit UI (Design v1)
  /// ===============================

  /// Top status strip: branding + single dot (no extra text)
  Widget _buildStatusStrip(int state) {
    final bool active = state != 0;
    final media = MediaQuery.of(context);
    final bool compactNavHeader =
        media.orientation == Orientation.portrait &&
        _cameraMode == _CameraMode.follow;
    final dotColor = (state == 2)
        ? Colors.greenAccent
        : (state == 1)
        ? Colors.amberAccent
        : Colors.redAccent;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: compactNavHeader ? 118 : 140,
          padding: EdgeInsets.symmetric(horizontal: compactNavHeader ? 10 : 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(compactNavHeader ? 0.30 : 0.22),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Row(
            children: [
              // Hamburger (everyone understands this)
              IconButton(
                tooltip: 'Menu',
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                icon: Icon(
                  Icons.menu_rounded,
                  color: Colors.white.withOpacity(0.88),
                  size: compactNavHeader ? 28 : 32,
                ),
              ),

              // Center logo (bigger, cockpit-style)
              Expanded(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _activePulseCtrl,
                    builder: (_, __) {
                      final pulse = active
                          ? (0.98 + 0.04 * _activePulse.value)
                          : 1.0;
                      return Transform.scale(
                        scale: compactNavHeader
                            ? (pulse * 1.28)
                            : (pulse * 1.6),
                        child: _tenantLogo(
                          height: compactNavHeader ? 68 : 92,
                          fallback: const Icon(
                            Icons.local_taxi,
                            size: 32,
                            color: Colors.white70,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Single status dot (pulses only when active)
              AnimatedBuilder(
                animation: _activePulseCtrl,
                builder: (_, __) {
                  final pulse = active
                      ? (0.75 + 0.25 * _activePulse.value)
                      : 1.0;
                  return Transform.scale(
                    scale: compactNavHeader ? (pulse * 1.2) : (pulse * 1.6),
                    child: Container(
                      width: compactNavHeader ? 11 : 14,
                      height: compactNavHeader ? 11 : 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor.withOpacity(active ? 1.0 : 0.9),
                        boxShadow: [
                          BoxShadow(
                            color: dotColor.withOpacity(active ? 0.55 : 0.35),
                            blurRadius: active ? 18 : 10,
                            spreadRadius: active ? 2 : 1,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              SizedBox(width: compactNavHeader ? 6 : 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom glass HUD (map remains primary)
  Widget _buildCockpitHud({required bool liveActive}) {
    final b = _activeBooking;
    final from = (b?.from ?? '').trim();
    final to = (b?.to ?? '').trim();

    final routeText = [
      if (from.isNotEmpty) 'A: $from',
      if (to.isNotEmpty) 'B: $to',
    ].join('  ->  ');

    // Fallback if destination is missing
    final hasB = to.isNotEmpty;
    final routeTextSafe = hasB
        ? routeText
        : (routeText.isNotEmpty ? (routeText + '  ->  B: —') : 'B: —');

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.18),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Route ticker (only route, no labels/icons beyond A/B)
                if (routeText.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      color: Colors.white.withOpacity(0.06),
                      child: Center(
                        child: RouteMarquee(
                          key: const ValueKey('route_marquee'),
                          text: routeTextSafe,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            letterSpacing: 0.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Price orb + mode (fixed/live) — minimal, cockpit-style
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withOpacity(0.18),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.12),
                          ),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 18,
                              spreadRadius: 1,
                              color:
                                  (liveActive
                                          ? Colors.greenAccent
                                          : Colors.amberAccent)
                                      .withOpacity(0.12),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            liveActive ? '●' : '◐',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: liveActive
                                  ? Colors.greenAccent
                                  : Colors.amberAccent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                // Primary action
                Center(
                  child: SizedBox(
                    width: 220,
                    height: 56,
                    child: FilledButton(
                      style:
                          FilledButton.styleFrom(
                            backgroundColor: liveActive
                                ? Colors.redAccent.withOpacity(0.95)
                                : const Color(0xFF1B7F3A),
                            shape: const StadiumBorder(),
                            elevation: 0,
                          ).copyWith(
                            side: MaterialStateProperty.all(
                              BorderSide(
                                color: liveActive
                                    ? Colors.redAccent.withOpacity(0.95)
                                    : kFluxidiYellow.withOpacity(0.95),
                                width: 1.2,
                              ),
                            ),
                            overlayColor: MaterialStateProperty.all(
                              kFluxidiYellowSoft,
                            ),
                          ),
                      onPressed: () async {
                        if (liveActive) {
                          await _stopTripSafely();
                        } else {
                          final b = _activeBooking;
                          if (b == null) return;
                          await _startTrip(b);
                        }
                      },
                      child: Text(
                        liveActive ? 'STOP' : 'START',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dial({
    required String label,
    required String value,
    required bool big,
  }) {
    final size = big ? 92.0 : 78.0;
    final valueStyle = TextStyle(
      color: Colors.white,
      fontSize: big ? 26 : 18,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.3,
    );

    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.06),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withOpacity(0.06),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, textAlign: TextAlign.center, style: valueStyle),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Active trip elapsed time
  Duration get _activeElapsed {
    final started = _trackingStartedAt;
    if (started == null) return Duration.zero;
    final now = DateTime.now();
    final d = now.difference(started);
    if (d.isNegative) return Duration.zero;
    return d;
  }

  String get _etaString {
    // ETA as countdown (remaining time), not clock-time.
    final totalSec = _routeDurationSec;
    if (totalSec == null || totalSec <= 0) return '—';

    final elapsed = _activeElapsed.inSeconds;
    final remaining = math.max(0, totalSec - elapsed);

    if (remaining < 60) return '<1 min';

    final minutes = (remaining / 60).ceil();
    if (minutes < 60) return '$minutes min';

    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  Future<void> _stopTripSafely() async {
    // Keep existing stop logic if present
    await _stopTrip();
  }

  String _formatHms(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildBootSplashOverlay() {
    final pulse = _splashPulse.value;

    // Premium boot overlay: subtle golden aura + animated ring + logo shimmer.
    return IgnorePointer(
      ignoring: true,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 280),
        opacity: _showBootSplash ? 1 : 0,
        child: Container(
          color: const Color(0xFF070709),
          child: Stack(
            children: [
              // Background aura
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.25),
                      radius: 0.95,
                      colors: [
                        const Color(
                          0x33FFD36A,
                        ).withOpacity(0.35 + 0.15 * pulse),
                        const Color(0x00070709),
                      ],
                    ),
                  ),
                ),
              ),

              // Center brand
              Center(
                child: AnimatedBuilder(
                  animation: _splashAnimCtrl,
                  builder: (context, _) {
                    final p = _splashPulse.value;
                    final ringAlpha = (0.22 + 0.18 * p).clamp(0.0, 1.0);
                    final glowAlpha = (0.45 + 0.30 * p).clamp(0.0, 1.0);
                    final scale = 0.985 + 0.025 * p;

                    return Transform.scale(
                      scale: scale,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 280,
                            height: 280,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Outer animated ring
                                Container(
                                  width: 268,
                                  height: 268,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Color.fromRGBO(
                                        255,
                                        211,
                                        106,
                                        ringAlpha,
                                      ),
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color.fromRGBO(
                                          255,
                                          211,
                                          106,
                                          glowAlpha,
                                        ),
                                        blurRadius: 28 + 18 * p,
                                        spreadRadius: 2 + 2 * p,
                                      ),
                                    ],
                                  ),
                                ),

                                // Inner soft ring
                                Container(
                                  width: 214,
                                  height: 214,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Color.fromRGBO(
                                        255,
                                        211,
                                        106,
                                        (ringAlpha * 0.55).clamp(0.0, 1.0),
                                      ),
                                      width: 1,
                                    ),
                                  ),
                                ),

                                // Logo + shimmer mask
                                ShaderMask(
                                  shaderCallback: (rect) {
                                    // Shimmer sweeps horizontally across the logo
                                    final t = _splashAnimCtrl.value; // 0..1
                                    final start = -0.6 + 1.6 * t;
                                    return LinearGradient(
                                      begin: Alignment(start, 0),
                                      end: Alignment(start + 0.8, 0),
                                      colors: const [
                                        Color(0x66FFFFFF),
                                        Color(0xFFFFFFFF),
                                        Color(0x66FFFFFF),
                                      ],
                                      stops: const [0.0, 0.5, 1.0],
                                    ).createShader(rect);
                                  },
                                  blendMode: BlendMode.srcATop,
                                  child: SizedBox(
                                    width: 210,
                                    height: 210,
                                    child: _tenantLogo(
                                      height: 210,
                                      fallback: const Text(
                                        'FLUXIDI',
                                        style: TextStyle(
                                          color: Color(0xFFFFD36A),
                                          fontSize: 32,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            kCompanyName,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Driver • Live Tracking',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.78),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 18),
                          // Minimal loading hint
                          SizedBox(
                            width: 120,
                            child: LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: const Color(0x22FFFFFF),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color.fromRGBO(
                                  255,
                                  211,
                                  106,
                                  (0.75 + 0.20 * p).clamp(0.0, 1.0),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ButtonStyle _ghostButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: BorderSide(color: kFluxidiYellow.withOpacity(0.85), width: 1.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ).copyWith(overlayColor: MaterialStateProperty.all(kFluxidiYellowSoft));
  }

  ButtonStyle _startButtonStyle() {
    return FilledButton.styleFrom(
      backgroundColor: Colors.black.withOpacity(0.55),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    ).copyWith(
      side: MaterialStateProperty.all(
        BorderSide(color: kFluxidiYellow.withOpacity(0.95), width: 1.2),
      ),
      shadowColor: MaterialStateProperty.all(kFluxidiYellowSoft),
      elevation: MaterialStateProperty.all(0),
      overlayColor: MaterialStateProperty.all(kFluxidiYellowSoft),
    );
  }

  String _rideStatusLabel(String rawStatus) {
    final s = rawStatus.trim().toUpperCase();
    if (s.isEmpty || s == 'PENDING') return kRideStatusPendingLabel;
    if (s == 'COMPLETED') return kRideActionCompletedLabel;
    if (s == 'CANCELLED') return kRideActionCancelledLabel;
    return rawStatus.trim();
  }

  // -------------------------------
  // UI helpers for stats
  // -------------------------------

  int? _remainingSec() {
    final remainingKm = (_routeKm != null)
        ? (_routeKm! - _kmDriven).clamp(0.0, 999999.0)
        : null;
    if (_routeDurationSec == null ||
        _routeKm == null ||
        _routeKm! <= 0 ||
        remainingKm == null)
      return null;
    final ratio = (remainingKm / _routeKm!).clamp(0.0, 1.0);
    return (_routeDurationSec! * ratio).round();
  }

  String _fmtDur(int? sec) {
    if (sec == null) return '—';
    final m = (sec / 60).round();
    if (m < 60) return '$m min';
    final h = (m / 60).floor();
    final mm = m % 60;
    return '${h}u ${mm}m';
  }

  String _fmtRemainingKm() {
    final remainingKm = (_routeKm != null)
        ? (_routeKm! - _kmDriven).clamp(0.0, 999999.0)
        : null;
    if (remainingKm == null) return '—';
    return remainingKm.toStringAsFixed(1);
  }

  String _fmtPrice() {
    final b = _activeBooking;
    if (b?.price == null) return '—';
    return b!.price!.toStringAsFixed(2);
  }

  String _fmtMoney(num amount, String currency) {
    // Keep it simple & predictable (no locale surprises)
    final value = amount.toDouble().toStringAsFixed(2);
    final cur = currency.toUpperCase();
    if (cur == 'EUR' || cur == 'EURO' || cur == '€') return '€ $value';
    if (cur.length <= 3) return '$cur $value';
    return '$value';
  }

  // -------------------------------
  // UI
  // -------------------------------

  Widget _buildHintPanel() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF081126).withOpacity(0.78),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFFFD36A).withOpacity(0.22),
              width: 1.1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFFFD36A)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _hintPanelText(),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.72),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openDirectRideEntry,
                  icon: const Icon(Icons.local_taxi_outlined, size: 18),
                  label: Text(
                    _tr(
                      nl: 'Straatrit starten',
                      en: 'Start direct ride',
                      fr: 'Demarrer une course directe',
                      es: 'Iniciar viaje directo',
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFD36A),
                    side: BorderSide(
                      color: const Color(0xFFFFD36A).withOpacity(0.70),
                      width: 1.1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 11,
                      horizontal: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTurnInstructionBanner({required bool compact}) {
    final dist = _nextNavDistanceM ?? 0.0;
    final instruction = (_nextNavInstruction ?? '').trim();
    final street = (_nextNavStreet ?? '').trim();
    final action = _shortNavAction(instruction, _nextNavType, _nextNavModifier);
    final line1 = _navTypeIsArrival(_nextNavType)
        ? action
        : _tr(
            nl: 'Over ${_navDistanceText(dist)} $action',
            en: 'In ${_navDistanceText(dist)} $action',
            fr: 'Dans ${_navDistanceText(dist)} $action',
            es: 'En ${_navDistanceText(dist)} $action',
          );
    final icon = _maneuverIconData(_nextNavType, _nextNavModifier, instruction);

    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 16 : 18),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: compact ? 8 : 12,
          sigmaY: compact ? 8 : 12,
        ),
        child: Container(
          constraints: BoxConstraints(maxHeight: compact ? 72 : 86),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF07142D).withOpacity(0.88),
            borderRadius: BorderRadius.circular(compact ? 16 : 18),
            border: Border.all(color: const Color(0x662D8CFF), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.30),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 46 : 58,
                height: compact ? 46 : 58,
                decoration: BoxDecoration(
                  color: const Color(0xFF2D8CFF),
                  borderRadius: BorderRadius.circular(compact ? 14 : 16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.80),
                    width: 1.5,
                  ),
                ),
                child: Icon(icon, size: compact ? 32 : 40, color: Colors.white),
              ),
              SizedBox(width: compact ? 10 : 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 17 : 21,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.05,
                      ),
                    ),
                    if (street.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        street,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 11 : 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withOpacity(0.74),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavLoadingBanner({required bool compact}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 10 : 12),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: compact ? 8 : 10,
          sigmaY: compact ? 8 : 10,
        ),
        child: Container(
          constraints: BoxConstraints(maxHeight: compact ? 50 : 56),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 5 : 6,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1733).withOpacity(0.78),
            borderRadius: BorderRadius.circular(compact ? 10 : 12),
            border: Border.all(color: const Color(0x332D8CFF)),
          ),
          child: Text(
            'Route-instructies worden geladen...',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              color: Colors.white.withOpacity(0.92),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoNavInstructionsBanner({required bool compact}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 10 : 12),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: compact ? 8 : 10,
          sigmaY: compact ? 8 : 10,
        ),
        child: Container(
          constraints: BoxConstraints(maxHeight: compact ? 50 : 56),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 5 : 6,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1733).withOpacity(0.78),
            borderRadius: BorderRadius.circular(compact ? 10 : 12),
            border: Border.all(color: const Color(0x33FF8A80)),
          ),
          child: Text(
            'Geen route-instructies beschikbaar',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              color: Colors.white.withOpacity(0.92),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecenterButton() {
    return Tooltip(
      message: kCenterOnMeLabel,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _centerOnMe,
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF07142D).withOpacity(0.88),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFFFD36A).withOpacity(0.55),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.30),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.my_location,
                  color: Color(0xFFFFD36A),
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _hintPanelText() {
    final lang = appConfig.currentLanguage;
    if (lang == AppLanguage.en) {
      return 'Open menu -> Bookings to choose a ride and start it to drive.';
    }
    if (lang == AppLanguage.fr) {
      return 'Ouvrez le menu -> Courses pour choisir une course et la demarrer.';
    }
    if (lang == AppLanguage.es) {
      return 'Abre el menu -> Reservas para elegir un viaje e iniciarlo.';
    }
    return 'Open menu -> Ritten om een rit te kiezen en start hem om te rijden.';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final lastBuildLog = _lastDriverBuildLogAt;
    if (lastBuildLog == null || now.difference(lastBuildLog).inSeconds >= 5) {
      _lastDriverBuildLogAt = now;
      debugPrint(
        '[DRIVER][BUILD] live=$_liveRideActive mode=$_cameraMode loadingBookings=$_loadingBookings',
      );
    }
    final bool liveActive = _liveRideActive;
    final bool hasSelection = _activeBooking != null;
    final bool hasDirectDraft = _directRideDraft;
    final int state = liveActive
        ? 2
        : ((hasSelection || hasDirectDraft) ? 1 : 0);
    final bool showCockpit = liveActive || hasSelection || hasDirectDraft;
    final screenH = MediaQuery.of(context).size.height;
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final bool collapseTopBarInLandscapeNav =
        isLandscape && _cameraMode == _CameraMode.follow;
    final double arrowBottom = isLandscape ? 106.0 : 152.0;
    final double navBannerTop =
        MediaQuery.of(context).padding.top +
        (isLandscape ? 8 : (_cameraMode == _CameraMode.follow ? 128 : 74));
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          // Map always at the back.
          Positioned.fill(child: _buildMapLayer()),

          // Top status / header (Fluxidi strip).
          if (!collapseTopBarInLandscapeNav)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 12,
              right: 12,
              child: _buildStatusStrip(state),
            ),
          if (collapseTopBarInLandscapeNav)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 10,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.26),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.14)),
                    ),
                    child: IconButton(
                      tooltip: 'Menu',
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                      icon: const Icon(Icons.menu_rounded, size: 22),
                    ),
                  ),
                ),
              ),
            ),
          if (_cameraMode == _CameraMode.follow && _nextNavInstruction != null)
            Positioned(
              top: navBannerTop,
              left: isLandscape ? 62 : 12,
              right: isLandscape ? 12 : 12,
              child: _buildTurnInstructionBanner(compact: isLandscape),
            ),
          if (_cameraMode == _CameraMode.follow &&
              _nextNavInstruction == null &&
              _navStepsLoading)
            Positioned(
              top: navBannerTop,
              left: isLandscape ? 62 : 12,
              right: isLandscape ? 12 : 12,
              child: _buildNavLoadingBanner(compact: isLandscape),
            ),
          if (_cameraMode == _CameraMode.follow &&
              !_navStepsLoading &&
              _routeSteps.isEmpty)
            Positioned(
              top: navBannerTop,
              left: isLandscape ? 62 : 12,
              right: isLandscape ? 12 : 12,
              child: _buildNoNavInstructionsBanner(compact: isLandscape),
            ),
          if (_cameraMode == _CameraMode.follow)
            Positioned(
              left: 0,
              right: 0,
              bottom: arrowBottom,
              child: IgnorePointer(
                child: Center(
                  child: Transform.rotate(
                    angle: _uiArrowBearing * math.pi / 180.0,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D8CFF).withOpacity(0.96),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.92),
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.42),
                            blurRadius: 14,
                            spreadRadius: 1.0,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.navigation,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_mapSupported)
            Positioned(
              right: 14,
              bottom: isLandscape ? 112 : (showCockpit ? 188 : 150),
              child: _buildRecenterButton(),
            ),

          // Bottom overlay layer (cockpit / idle / hint).
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeOut,
              child: isLandscape
                  ? SafeArea(
                      key: ValueKey<String>(
                        'landscape_${showCockpit ? 'cockpit' : 'hint'}',
                      ),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: 10,
                            right: 10,
                            bottom:
                                MediaQuery.of(context).viewInsets.bottom + 4,
                          ),
                          child: showCockpit
                              ? SizedBox(
                                  width: double.infinity,
                                  child: CockpitWidget(
                                    etaText: _etaText,
                                    kmText: _kmRemainingText,
                                    priceText: _cockpitPriceText,
                                    tripStarted: _liveRideActive,
                                    isWaiting: _isWaiting,
                                    navActive:
                                        _cameraMode == _CameraMode.follow,
                                    onNav: _openNavigation,
                                    onStart: _handleCockpitStart,
                                    onStop: _stopTrip,
                                    onWait: _enterWaitMode,
                                    onGo: _exitWaitMode,
                                  ),
                                )
                              : ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: math.min(
                                      420,
                                      MediaQuery.of(context).size.width * 0.5,
                                    ),
                                  ),
                                  child: _buildHintPanel(),
                                ),
                        ),
                      ),
                    )
                  : SafeArea(
                      key: ValueKey<String>(
                        'portrait_${showCockpit ? 'cockpit' : 'hint'}',
                      ),
                      minimum: const EdgeInsets.only(bottom: 6),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: 12,
                            right: 12,
                            bottom:
                                MediaQuery.of(context).viewInsets.bottom + 6,
                          ),
                          child: showCockpit
                              ? CockpitWidget(
                                  etaText: _etaText,
                                  kmText: _kmRemainingText,
                                  priceText: _cockpitPriceText,
                                  tripStarted: _liveRideActive,
                                  isWaiting: _isWaiting,
                                  navActive: _cameraMode == _CameraMode.follow,
                                  onNav: _openNavigation,
                                  onStart: _handleCockpitStart,
                                  onStop: _stopTrip,
                                  onWait: _enterWaitMode,
                                  onGo: _exitWaitMode,
                                )
                              : _buildHintPanel(),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapLayer() {
    final now = DateTime.now();
    final lastBuildLog = _lastMapWidgetBuildLogAt;
    if (lastBuildLog == null || now.difference(lastBuildLog).inSeconds >= 5) {
      _lastMapWidgetBuildLogAt = now;
      debugPrint(
        '[MAP][WIDGET_BUILD] mapSupported=$_mapSupported hasMap=${_map != null}',
      );
    }
    if (kIsWindows) {
      return _mapPlaceholder(
        title: 'Map unavailable on Windows',
        subtitle: 'Run on Android to see the live map.',
      );
    }

    if (kIsWeb) {
      return _mapPlaceholder(
        title: 'Map unavailable on Web',
        subtitle: 'Run on Android to see the live map.',
      );
    }

    return _stableMapWidget;
  }

  Widget _mapPlaceholder({required String title, required String subtitle}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          radius: 1.2,
          colors: [Color(0xFF141B2F), Color(0xFF070A10)],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            margin: const EdgeInsets.all(18),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF141B2F),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(subtitle, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopStatus(bool active) {
    if (!active) return const SizedBox.shrink();

    final eta = _fmtDur(_remainingSec());
    final km = _fmtRemainingKm();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2F).withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 10, color: Color(0xFF4CD964)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tracking actief • Ping: $_lastPing • ETA: $eta • KM: $km',
              style: const TextStyle(fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFED6A5A).withOpacity(0.28),
              foregroundColor: const Color(0xFFFFB4AA),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: _stopTrip,
            child: Text(kStopShortLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingsSheet(double screenH) {
    final padding = MediaQuery.of(context).padding.bottom;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 14,
        bottom: 14 + padding,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2F).withOpacity(0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(blurRadius: 18, spreadRadius: 2, color: Colors.black54),
          BoxShadow(blurRadius: 26, spreadRadius: 1, color: kFluxidiYellowSoft),
        ],
      ),
      child: _buildBookingsList(screenH),
    );
  }

  Widget _buildBookingsList(double screenH) {
    final visibleBookings = _visibleBookings;
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                kAvailableBookingsTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            OutlinedButton.icon(
              style: _ghostButtonStyle(),
              onPressed: _loadingBookings ? null : _refreshBookings,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(kRefreshShortLabel),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_loadingBookings)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_bookingsError != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Error: $_bookingsError',
              style: const TextStyle(color: Colors.redAccent),
            ),
          )
        else if (visibleBookings.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(kBookingsEmptyLabel),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: visibleBookings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _bookingCard(visibleBookings[i]),
            ),
          ),
      ],
    );
  }

  Widget _bookingCard(BookingItem b) {
    final dt = _formatPickup(b.pickupIso);
    final actionBusy = _bookingActionInFlight.contains(b.bookingId);

    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 380;
        final tight = c.maxWidth < 340;
        final actionHeight = narrow ? 44.0 : 42.0;
        final statusText = _rideStatusLabel(
          (_effectiveStatusFor(b) ?? 'PENDING'),
        );

        return Container(
          padding: EdgeInsets.all(tight ? 12 : 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2240),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kFluxidiYellow.withOpacity(0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (narrow) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill(icon: Icons.schedule, text: dt),
                    _pill(
                      icon: Icons.timelapse,
                      text: statusText,
                      borderColor: const Color(0xFFB07A2A),
                      textColor: const Color(0xFFE7B46A),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: actionHeight,
                  child: FilledButton(
                    style: _startButtonStyle().copyWith(
                      padding: MaterialStateProperty.all(
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      ),
                    ),
                    onPressed: () => _goToRide(b),
                    child: Text(
                      kRideGoToRideLabel,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _pill(icon: Icons.schedule, text: dt),
                          _pill(
                            icon: Icons.timelapse,
                            text: statusText,
                            borderColor: const Color(0xFFB07A2A),
                            textColor: const Color(0xFFE7B46A),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: actionHeight,
                      child: FilledButton(
                        style: _startButtonStyle().copyWith(
                          padding: MaterialStateProperty.all(
                            const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                          ),
                        ),
                        onPressed: () => _goToRide(b),
                        child: Text(
                          kRideGoToRideLabel,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              _line(
                icon: Icons.radio_button_checked,
                title: kPickupLabel,
                value: b.from ?? '—',
                maxLines: narrow ? 2 : 3,
              ),
              const SizedBox(height: 6),
              _line(
                icon: Icons.place,
                title: kDropoffLabel,
                value: b.to ?? '—',
                maxLines: narrow ? 2 : 3,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _pill(text: (b.tier ?? 'premium').toUpperCase()),
                  _pill(text: '${b.pax ?? 0} pax'),
                  _pill(text: '${b.bags ?? 0} bags'),
                  _pill(text: 'ID: ${b.shortId}', textColor: Colors.white70),
                  if (b.price != null)
                    _pill(text: _fmtMoney(b.price!, b.currency ?? 'EUR')),
                ],
              ),
              const SizedBox(height: 10),
              if (narrow) ...[
                SizedBox(
                  width: double.infinity,
                  height: actionHeight,
                  child: OutlinedButton.icon(
                    style: _ghostButtonStyle(),
                    onPressed: actionBusy
                        ? null
                        : () => _setBookingStatus(b, 'COMPLETED'),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(
                      kRideActionCompletedLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: actionHeight,
                        child: OutlinedButton.icon(
                          style: _ghostButtonStyle(),
                          onPressed: actionBusy
                              ? null
                              : () => _setBookingStatus(b, 'CANCELLED'),
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: Text(
                            kRideActionCancelledLabel,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: actionHeight,
                      width: actionHeight + 2,
                      child: IconButton(
                        onPressed: actionBusy ? null : () => _confirmDelete(b),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: kRideDeleteLabel,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: actionHeight,
                        child: OutlinedButton.icon(
                          style: _ghostButtonStyle(),
                          onPressed: actionBusy
                              ? null
                              : () => _setBookingStatus(b, 'COMPLETED'),
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 18,
                          ),
                          label: Text(kRideActionCompletedLabel),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: actionHeight,
                        child: OutlinedButton.icon(
                          style: _ghostButtonStyle(),
                          onPressed: actionBusy
                              ? null
                              : () => _setBookingStatus(b, 'CANCELLED'),
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: Text(kRideActionCancelledLabel),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: actionHeight,
                      width: actionHeight + 2,
                      child: IconButton(
                        onPressed: actionBusy ? null : () => _confirmDelete(b),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: kRideDeleteLabel,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCockpitWidget() {
    // ✅ Minimal cockpit (driving only):
    // - Big ETA + KM remaining (countdown starts when we move)
    // - Bottom controls: NAV | START/STOP | WACHT/GA
    final eta = _etaText.isNotEmpty ? _etaText : '—';
    final km = _kmRemainingText.isNotEmpty ? _kmRemainingText : '—';

    final bool tripStarted = _activeTripId != null;
    final bool waiting = _isWaiting;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0B1733).withOpacity(0.78),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: kGlow.withOpacity(tripStarted ? 0.50 : 0.22),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: kGlow.withOpacity(tripStarted ? 0.18 : 0.10),
                    blurRadius: tripStarted ? 16 : 10,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // === Big numbers ===
                  Row(
                    children: [
                      Expanded(
                        child: _bigMetric(label: 'ETA', value: eta),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _bigMetric(label: 'KM', value: km, suffix: 'km'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // === Controls ===
                  Row(
                    children: [
                      Expanded(
                        child: _cockpitButton(
                          label: 'NAV',
                          icon: Icons.navigation,
                          onTap: _openNavigation,
                          enabled: _routeCoords.isNotEmpty,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _cockpitButton(
                          label: tripStarted ? 'STOP' : 'START',
                          icon: tripStarted
                              ? Icons.stop_circle_outlined
                              : Icons.play_circle_outline,
                          onTap: () {
                            final b = _activeBooking;
                            if (!tripStarted) {
                              if (b == null) {
                                _toast('Kies eerst een rit in Ritten.');
                                return;
                              }
                              _startTrip(b);
                            } else {
                              _stopTrip();
                            }
                          },
                          emphasis: true,
                          enabled: (tripStarted || _activeBooking != null),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _cockpitButton(
                          label: waiting ? 'GA' : 'WACHT',
                          icon: waiting ? Icons.play_arrow : Icons.pause,
                          onTap: () {
                            if (!tripStarted) {
                              _toast('Start eerst de rit.');
                              return;
                            }
                            if (waiting) {
                              _exitWaitMode();
                            } else {
                              _enterWaitMode();
                            }
                          },
                          enabled: tripStarted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bigMetric({
    required String label,
    required String value,
    String? suffix,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withOpacity(0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.70),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    suffix,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.70),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _cockpitButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool enabled = true,
    bool emphasis = false,
  }) {
    final baseOpacity = enabled ? 1.0 : 0.45;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: enabled ? onTap : null,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withOpacity(emphasis ? 0.10 : 0.06),
          border: Border.all(
            color: kGlow.withOpacity(
              emphasis ? 0.55 * baseOpacity : 0.28 * baseOpacity,
            ),
            width: 1.1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: Colors.white.withOpacity(baseOpacity)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: Colors.white.withOpacity(baseOpacity),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialGauge({
    required String label,
    required String value,
    required IconData icon,
    required bool highlight,
  }) {
    return AnimatedBuilder(
      animation: _activePulse,
      builder: (context, _) {
        final t = highlight ? (0.55 + 0.45 * _activePulse.value) : 0.0;

        return Container(
          height: 86,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: const Color(0xFF0B1733).withOpacity(0.55),
            border: Border.all(
              color: const Color(0xFFFFD36A).withOpacity(0.20 + 0.18 * t),
              width: 1.0,
            ),
            boxShadow: [
              if (highlight)
                BoxShadow(
                  color: const Color(0x66F5C400).withOpacity(0.10 * t),
                  blurRadius: 22 * t,
                  spreadRadius: 1 * t,
                ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Round dial
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.18),
                    border: Border.all(
                      color: const Color(
                        0xFFFFD36A,
                      ).withOpacity(0.22 + 0.22 * t),
                      width: 1.0,
                    ),
                    boxShadow: [
                      if (highlight)
                        BoxShadow(
                          color: const Color(0x66F5C400).withOpacity(0.18 * t),
                          blurRadius: 18 * t,
                          spreadRadius: 1 * t,
                        ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 16,
                        color: const Color(0xFFFFD36A).withOpacity(0.92),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Label (right side)
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.62),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dialAction({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedBuilder(
        animation: _activePulse,
        builder: (context, _) {
          final t = (0.65 + 0.35 * _activePulse.value);
          return Container(
            height: 86,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: filled
                  ? const Color(0xFF3B2230)
                  : const Color(0xFF0B1733).withOpacity(0.45),
              border: Border.all(
                color: filled
                    ? const Color(0xFFFFA7C0).withOpacity(0.50 + 0.25 * t)
                    : const Color(0xFFFFD36A).withOpacity(0.26 + 0.14 * t),
                width: 1.2,
              ),
              boxShadow: filled
                  ? [
                      BoxShadow(
                        color: const Color(0x66FFA7C0).withOpacity(0.16 * t),
                        blurRadius: 18 * t,
                        spreadRadius: 1 * t,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: const Color(0x66F5C400).withOpacity(0.10 * t),
                        blurRadius: 18 * t,
                        spreadRadius: 1 * t,
                      ),
                    ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: filled
                      ? const Color(0xFFFFA7C0)
                      : const Color(0xFFFFD36A),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _cockpitGauge({
    required String label,
    required String value,
    required IconData icon,
    required bool highlight,
  }) {
    return AnimatedBuilder(
      animation: _activePulse,
      builder: (context, child) {
        final t = highlight ? (0.55 + 0.45 * _activePulse.value) : 0.0;
        return Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: const Color(0xFF0B1733).withOpacity(0.65),
            border: Border.all(
              color: const Color(0xFFFFD36A).withOpacity(0.22 + 0.18 * t),
              width: 1.0,
            ),
            boxShadow: [
              if (highlight)
                BoxShadow(
                  color: const Color(0xFFFFD36A).withOpacity(0.10 * t),
                  blurRadius: 18 * t,
                  spreadRadius: 1 * t,
                ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: const Color(0xFFFFD36A).withOpacity(0.9),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _cockpitAction({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: filled
              ? const Color(0xFF3B2230)
              : const Color(0xFF0B1733).withOpacity(0.55),
          border: Border.all(
            color: filled
                ? const Color(0xFFFFA7C0).withOpacity(0.55)
                : const Color(0xFFFFD36A).withOpacity(0.28),
            width: 1.1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: filled ? const Color(0xFFFFA7C0) : const Color(0xFFFFD36A),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.95),
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tinyStat(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$k: ',
            style: TextStyle(
              color: Colors.white.withOpacity(0.70),
              fontSize: 12,
            ),
          ),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildActiveDetailsSheet() {
    final b = _activeBooking;

    return DraggableScrollableSheet(
      // ✅ smaller collapsed size so it doesn't hide the values
      initialChildSize: 0.10,
      minChildSize: 0.10,
      // ✅ lower max so it doesn't dominate
      maxChildSize: 0.56,
      builder: (context, controller) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF141B2F).withOpacity(0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: Colors.white12),
            boxShadow: const [
              BoxShadow(blurRadius: 18, spreadRadius: 2, color: Colors.black54),
            ],
          ),
          child: ListView(
            controller: controller,
            padding: EdgeInsets.only(
              left: 14,
              right: 14,
              top: 10,
              bottom: 18 + MediaQuery.of(context).padding.bottom + 50,
            ),
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                kActiveRideTitle,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              if (b != null) ...[
                _line(
                  icon: Icons.confirmation_number,
                  title: 'Trip ID',
                  value: _activeTripId ?? '—',
                  maxLines: 1,
                ),
                const SizedBox(height: 8),
                _line(
                  icon: Icons.radio_button_checked,
                  title: kPickupLabel,
                  value: b.from ?? '—',
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                _line(
                  icon: Icons.place,
                  title: kDropoffLabel,
                  value: b.to ?? '—',
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill(text: (b.tier ?? 'premium').toUpperCase()),
                    _pill(text: '${b.pax ?? 0} pax'),
                    _pill(text: '${b.bags ?? 0} bags'),
                    _pill(
                      text: 'Pings: $_pingCount',
                      textColor: Colors.white70,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFED6A5A).withOpacity(0.30),
                    foregroundColor: const Color(0xFFFFB4AA),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: _stopTrip,
                  child: const Text(
                    'Stop rit',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pill({
    IconData? icon,
    required String text,
    Color? borderColor,
    Color? textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor ?? Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: (textColor ?? Colors.white70)),
            const SizedBox(width: 6),
          ],
          Text(text, style: TextStyle(color: textColor ?? Colors.white)),
        ],
      ),
    );
  }

  Widget _line({
    required IconData icon,
    required String title,
    required String value,
    int maxLines = 2,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.white70),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                // ✅ FIX: w650 doesn't exist -> w600
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatPickup(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(dt.day)}-${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  bool _canAccessDriverOpsScreens() {
    final role = appRoleNotifier.value;
    return role == AppRole.driver ||
        role == AppRole.dispatcher ||
        role == AppRole.companyAdmin;
  }

  bool _canAccessCustomerBookingScreens() {
    final role = appRoleNotifier.value;
    return role == AppRole.customer ||
        role == AppRole.driver ||
        role == AppRole.companyAdmin;
  }

  bool _canAccessAdminManagementScreens() {
    return appRoleNotifier.value == AppRole.companyAdmin;
  }

  void _denyRoleAccess() {
    _toast('Geen toegang voor jouw rol.');
  }

  void _openBookingsHub() async {
    if (!_canAccessDriverOpsScreens()) {
      Navigator.pop(context);
      _denyRoleAccess();
      return;
    }
    // Close drawer first for a clean transition.
    Navigator.pop(context);
    if (mounted) {
      setState(() => _bookingsHubVisible = true);
    } else {
      _bookingsHubVisible = true;
    }
    _startBookingPolling(reason: 'bookings_hub_open');
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _BookingsHubPage(
          title: kBookingsTitle,
          buildList: (h) => _buildBookingsList(h),
          onRefresh: () =>
              _refreshBookings(force: true, trigger: 'list_manual'),
          repaintListenable: _bookingsUiVersion,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _bookingsHubVisible = false);
    _startBookingPolling(reason: 'bookings_hub_closed');
  }

  void _openLiveRide() async {
    if (!_canAccessDriverOpsScreens()) {
      Navigator.pop(context);
      _denyRoleAccess();
      return;
    }
    // Close drawer first for a clean transition.
    Navigator.pop(context);

    if (!_liveRideActive) {
      _toast('Geen actieve rit. Start een rit vanuit Ritten.');
      return;
    }

    // Bring driver focus back to the cockpit/map.
    try {
      setState(() {
        _cameraMode = _CameraMode.follow;
        _followCar = true;
        _hasSwitchedToFollow = true;
        _allowOverviewCamera = false;
      });
      await _applyMapStyleForMode();
      await _forceFollowCameraNow(caller: 'open_live_ride');
    } catch (_) {
      // Never crash the UI from a camera move.
    }
  }

  void _openTripHistory() {
    if (!_canAccessDriverOpsScreens()) {
      Navigator.pop(context);
      _denyRoleAccess();
      return;
    }
    Navigator.pop(context);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _TripHistoryPage(
          workerBaseUrl: kWorkerBaseUrl,
          tenantId: kTenantId,
          driverId: kDriverId,
          headers: _headers(admin: true),
        ),
      ),
    );
  }

  void _openCalculator() {
    if (!_canAccessCustomerBookingScreens()) {
      Navigator.pop(context);
      _denyRoleAccess();
      return;
    }
    // Close drawer first for a clean transition.
    Navigator.pop(context);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => CalculatorPage(
          bookingBaseUrl: kBookingBaseUrl,
          mapboxToken: kMapboxToken,
        ),
      ),
    );
  }

  void _openBusinessSettings() {
    if (!_canAccessAdminManagementScreens()) {
      Navigator.pop(context);
      _denyRoleAccess();
      return;
    }
    Navigator.pop(context);
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (ctx) => const BusinessSettingsPage()));
  }

  void _openVehicles() {
    if (!_canAccessAdminManagementScreens()) {
      Navigator.pop(context);
      _denyRoleAccess();
      return;
    }
    Navigator.pop(context);
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (ctx) => const VehicleManagementPage()));
  }

  Drawer _buildDrawer() {
    final role = appRoleNotifier.value;
    final isCustomer = role == AppRole.customer;
    final isDriver = role == AppRole.driver;
    final isCompanyAdmin = role == AppRole.companyAdmin;
    final isDispatcher = role == AppRole.dispatcher;
    final canSeeDriverOps = isDriver || isDispatcher || isCompanyAdmin;
    final canSeeAdminManagement = isCompanyAdmin;
    final canSeeCustomerBooking = isCustomer || isDriver || isCompanyAdmin;

    return Drawer(
      backgroundColor: const Color(0xFF141B2F),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Text(
              'Fluxidi Driver',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              kDrawerLanguageLabel,
              style: TextStyle(
                color: Colors.white.withOpacity(0.80),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: currentLanguageCode,
              items: const [
                DropdownMenuItem(value: 'nl', child: Text('Nederlands')),
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'fr', child: Text('Francais')),
                DropdownMenuItem(value: 'es', child: Text('Espanol')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setAppLanguageByCode(v);
                setState(() {});
              },
              dropdownColor: const Color(0xFF111111),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF0B0B0B),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x22FFFFFF)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x22FFFFFF)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text(
              _tr(
                nl: 'Kaartmodus',
                en: 'Map mode',
                fr: 'Mode de carte',
                es: 'Modo de mapa',
              ),
              style: TextStyle(
                color: Colors.white.withOpacity(0.80),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<MapThemeMode>(
              value: _effectiveMapThemeFor(_cameraMode),
              items: [
                DropdownMenuItem(
                  value: MapThemeMode.light,
                  child: Text(
                    _tr(nl: 'Licht', en: 'Light', fr: 'Clair', es: 'Claro'),
                  ),
                ),
                DropdownMenuItem(
                  value: MapThemeMode.dark,
                  child: Text(
                    _tr(nl: 'Donker', en: 'Dark', fr: 'Sombre', es: 'Oscuro'),
                  ),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                _setMapTheme(v);
              },
              dropdownColor: const Color(0xFF111111),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF0B0B0B),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x22FFFFFF)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x22FFFFFF)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),
            ValueListenableBuilder<ActiveDriverSession?>(
              valueListenable: activeDriverSessionNotifier,
              builder: (context, session, _) {
                if (!(isDriver && session != null)) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.swap_horiz_rounded),
                    title: Text(
                      _tr(
                        nl: 'Andere chauffeur',
                        en: 'Switch driver',
                        fr: 'Changer de chauffeur',
                        es: 'Cambiar conductor',
                      ),
                    ),
                    subtitle: Text(
                      _tr(
                        nl: 'Afmelden en opnieuw inloggen met een ander ID.',
                        en: 'Sign out and log in with a different ID.',
                        fr: 'Se déconnecter et se reconnecter avec un autre ID.',
                        es: 'Cerrar sesión e iniciar con otro ID.',
                      ),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.65),
                        fontSize: 12,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await DriverSessionStore.instance.clear();
                      if (!context.mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => const ChauffeurLoginPage(),
                        ),
                        (route) => false,
                      );
                    },
                  ),
                );
              },
            ),
            // === Menu: Bookings hub ===
            if (canSeeDriverOps)
              ListTile(
                leading: const Icon(Icons.list_alt),
                title: Text(kBookingsTitle),
                subtitle: Text(
                  kBookingsMenuSubtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openBookingsHub,
              ),

            // === Menu: Live rit ===
            if (canSeeDriverOps)
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: Text(kLiveRideTitle),
                subtitle: Text(
                  kLiveRideMenuSubtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openLiveRide,
              ),

            if (canSeeDriverOps)
              ListTile(
                leading: const Icon(Icons.local_taxi_outlined),
                title: Text(
                  _tr(
                    nl: 'Straatrit',
                    en: 'Direct ride',
                    fr: 'Course directe',
                    es: 'Viaje directo',
                  ),
                ),
                subtitle: Text(
                  _tr(
                    nl: 'Start een rit zonder voorafgaande boeking',
                    en: 'Start a ride without a planned booking',
                    fr: 'Demarrer une course sans reservation',
                    es: 'Iniciar un viaje sin reserva',
                  ),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openDirectRideEntry,
              ),

            if (canSeeDriverOps)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(
                  _tr(
                    nl: 'Ritten historiek',
                    en: 'Ride history',
                    fr: 'Historique des courses',
                    es: 'Historial de viajes',
                  ),
                ),
                subtitle: Text(
                  _tr(
                    nl: 'Bekijk afgeronde straatritten',
                    en: 'View completed direct rides',
                    fr: 'Voir les courses directes terminees',
                    es: 'Ver viajes directos completados',
                  ),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openTripHistory,
              ),

            // === Menu: Calculator ===
            if (canSeeCustomerBooking)
              ListTile(
                leading: const Icon(Icons.calculate_outlined),
                title: Text(
                  appConfig.strings.calculatorTitle.of(
                    appConfig.defaultLanguage,
                  ),
                ),
                subtitle: Text(
                  kCalculatorMenuSubtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openCalculator,
              ),
            if (canSeeAdminManagement)
              ListTile(
                leading: const Icon(Icons.business_center_outlined),
                title: Text(kDrawerBusinessSettingsLabel),
                subtitle: Text(
                  kDrawerBusinessSettingsSubtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openBusinessSettings,
              ),
            if (canSeeAdminManagement)
              ListTile(
                leading: const Icon(Icons.directions_car_filled_outlined),
                title: Text(kDrawerVehiclesLabel),
                subtitle: Text(
                  kDrawerVehiclesSubtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openVehicles,
              ),

            // === Menu: Actieve rit (alleen zichtbaar wanneer een rit actief is) ===
            if (canSeeDriverOps && _liveRideActive)
              ListTile(
                leading: const Icon(Icons.directions_car),
                title: Text(kActiveRideTitle),
                subtitle: Text(
                  kActiveRideMenuSubtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openLiveRide,
              ),

            const SizedBox(height: 8),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),
            if (canSeeDriverOps)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text(kRefreshBookingsLabel),
                onTap: () {
                  Navigator.pop(context);
                  _refreshBookings(force: true, trigger: 'drawer_manual');
                },
              ),
            if (canSeeDriverOps)
              ListTile(
                leading: const Icon(Icons.my_location),
                title: Text(kCenterOnMeLabel),
                onTap: () async {
                  Navigator.pop(context);
                  await _centerOnMe();
                },
              ),
            if (canSeeDriverOps) const SizedBox(height: 8),
            if (canSeeDriverOps) const FluxidiBackToStartButton(),
          ],
        ),
      ),
    );
  }
}

/// Small icon button with Fluxidi yellow glow.
///
/// Used in the brand bar (menu icon, etc.). Keeps hit-area large for in-car use.

/// Full-screen Bookings Hub opened from the drawer.
/// Keeps the map screen clean: operations live here.
class _TripHistoryPage extends StatefulWidget {
  final String workerBaseUrl;
  final String tenantId;
  final String driverId;
  final Map<String, String> headers;

  const _TripHistoryPage({
    required this.workerBaseUrl,
    required this.tenantId,
    required this.driverId,
    required this.headers,
  });

  @override
  State<_TripHistoryPage> createState() => _TripHistoryPageState();
}

class _TripHistoryPageState extends State<_TripHistoryPage> {
  late Future<List<_TripHistoryItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<_TripHistoryItem>> _fetch() async {
    final uri = Uri.parse(
      '${widget.workerBaseUrl}$kTripsHistoryPath'
      '?tenant_id=${Uri.encodeQueryComponent(widget.tenantId)}'
      '&driver_id=${Uri.encodeQueryComponent(widget.driverId)}'
      '&limit=100',
    );
    final res = await http
        .get(uri, headers: widget.headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map || decoded['ok'] != true) {
      throw Exception('Ongeldig antwoord van Worker');
    }
    final trips = decoded['trips'];
    if (trips is! List) return <_TripHistoryItem>[];
    final items = trips
        .whereType<Map>()
        .map((e) => _TripHistoryItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.tripId.trim().isNotEmpty)
        .toList(growable: false);
    return items;
  }

  void _refresh() {
    setState(() {
      _future = _fetch();
    });
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(dt.day)}-${two(dt.month)}-${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  String _formatWait(int seconds) {
    if (seconds <= 0) return '0 min';
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    if (min <= 0) return '${sec}s';
    if (sec == 0) return '$min min';
    return '$min min ${sec}s';
  }

  void _openReceipt(_TripHistoryItem item) {
    if (!item.isCompletedForReceipt) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('receiptUnavailable'))),
      );
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => _RideReceiptPage(item: item)));
  }

  Future<void> _archiveTrip(_TripHistoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_receiptText('archiveTripTitle')),
        content: Text(_receiptText('archiveTripBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_receiptText('archiveTripCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_receiptText('archiveTripConfirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final res = await http
          .post(
            Uri.parse('${widget.workerBaseUrl}$kTripsArchivePath'),
            headers: widget.headers,
            body: jsonEncode({
              'tenant_id': widget.tenantId,
              'driver_id': widget.driverId,
              'trip_id': item.tripId,
              'archived': true,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final decoded = jsonDecode(res.body);
      if (res.statusCode != 200 || decoded is! Map || decoded['ok'] != true) {
        throw Exception('archive_failed');
      }
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('archiveTripSuccess'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('archiveTripFailed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1020),
          elevation: 0,
          title: Text(_receiptText('tripHistoryTitle')),
          actions: [
            IconButton(
              tooltip: _receiptText('refresh'),
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: FutureBuilder<List<_TripHistoryItem>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '${_receiptText('historyLoadFailed')}\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              );
            }
            final items = snapshot.data ?? const <_TripHistoryItem>[];
            if (items.isEmpty) {
              return Center(
                child: Text(
                  _receiptText('historyEmpty'),
                  style: const TextStyle(color: Colors.white70),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                final km = item.kmTotal == null
                    ? '—'
                    : '${item.kmTotal!.toStringAsFixed(1)} km';
                final total = item.totalEur == null
                    ? '€ —'
                    : '€ ${item.totalEur!.toStringAsFixed(2)}';
                return Card(
                  color: const Color(0xFF141B2F),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _openReceipt(item),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 4, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            leading: const Icon(
                              Icons.local_taxi_outlined,
                              color: Colors.white70,
                            ),
                            title: Text(
                              item.destination,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${item.kindLabel} • ${_formatDate(item.startedAt)}\n$km • ${_receiptText('waitingCompact')} ${_formatWait(item.waitSecondsTotal)} • ${_localizedRideStatus(item.status)}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  height: 1.35,
                                ),
                              ),
                            ),
                            trailing: Text(
                              total,
                              style: const TextStyle(
                                color: Color(0xFFFFD400),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            contentPadding: const EdgeInsets.only(left: 16),
                            isThreeLine: true,
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _archiveTrip(item),
                                  icon: const Icon(
                                    Icons.archive_outlined,
                                    size: 18,
                                  ),
                                  label: Text(_receiptText('archiveTripLabel')),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white70,
                                    side: const BorderSide(
                                      color: Colors.white24,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                                FilledButton.icon(
                                  onPressed: () => _openReceipt(item),
                                  icon: const Icon(
                                    Icons.receipt_long,
                                    size: 18,
                                  ),
                                  label: Text(_receiptText('receiptTitle')),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFFFD400),
                                    foregroundColor: const Color(0xFF101010),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _RideReceiptPage extends StatelessWidget {
  final _TripHistoryItem item;
  final _ReceiptQuickAction? initialAction;
  final bool autoPopAfterInitialAction;
  final bool showReceiptUi;

  const _RideReceiptPage({
    required this.item,
    this.initialAction,
    this.autoPopAfterInitialAction = false,
    this.showReceiptUi = true,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => _RideReceiptBody(
        item: item,
        initialAction: initialAction,
        autoPopAfterInitialAction: autoPopAfterInitialAction,
        showReceiptUi: showReceiptUi,
      ),
    );
  }
}

class _RideReceiptBody extends StatefulWidget {
  final _TripHistoryItem item;
  final _ReceiptQuickAction? initialAction;
  final bool autoPopAfterInitialAction;
  final bool showReceiptUi;

  const _RideReceiptBody({
    required this.item,
    this.initialAction,
    this.autoPopAfterInitialAction = false,
    this.showReceiptUi = true,
  });

  @override
  State<_RideReceiptBody> createState() => _RideReceiptBodyState();
}

enum _ReceiptPaymentStatus { pending, sent, paid }

enum _ReceiptQuickAction { viewPdf, sharePdf, whatsappPdf, emailPdf, printPdf }

class _ReceiptPdfBundle {
  final Uint8List bytes;
  final File file;

  const _ReceiptPdfBundle({required this.bytes, required this.file});
}

class _ReceiptPdfActionRunner {
  static Future<void> previewPdf({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final bundle = await _buildReceiptPdfBundle(context: context, item: item);
    if (bundle == null) {
      await _fallbackCopyText(context: context, item: item);
      return;
    }
    debugPrint('[PDF][ACTION][CUSTOMER_DIRECT_VIEW] hasPdf=true');
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ReceiptPdfPreviewPage(
          title: _receiptText('viewPdf'),
          bytes: bundle.bytes,
        ),
      ),
    );
  }

  static Future<void> sharePdf({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final bundle = await _buildReceiptPdfBundle(context: context, item: item);
    if (bundle == null) {
      await _fallbackCopyText(context: context, item: item);
      return;
    }
    debugPrint('[PDF][ACTION][CUSTOMER_DIRECT_SHARE] hasPdf=true');
    debugPrint('[PDF][ACTION][PDF_SHARE] hasPdf=true');
    await Share.shareXFiles(
      <XFile>[XFile(bundle.file.path)],
      text: _receiptCustomerMessage(item),
      subject: _receiptText('receiptEmailSubject'),
    );
  }

  static Future<void> sharePdfViaWhatsApp({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final bundle = await _buildReceiptPdfBundle(context: context, item: item);
    if (bundle == null) {
      await _fallbackWhatsAppText(context: context, item: item);
      return;
    }
    final contact = _resolvePdfContact(item);
    final phone = _normalizePhoneForWhatsApp(
      contact.phoneRaw,
      countryContext: _customerCountryContext(item),
    );
    final phoneFound = phone != null;
    const packageTarget = 'share_sheet';
    debugPrint(
      '[PDF][ACTION][WHATSAPP_PDF] phoneFound=$phoneFound hasPdf=true packageTarget=$packageTarget',
    );

    if (phoneFound && context.mounted) {
      await Clipboard.setData(ClipboardData(text: phone));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Klantnummer gekopieerd. Kies WhatsApp en selecteer of plak de klant om de PDF te sturen.',
              en: 'Customer number copied. Choose WhatsApp and select or paste the customer to send the PDF.',
              fr: 'Numéro client copié. Choisissez WhatsApp puis sélectionnez ou collez le client pour envoyer le PDF.',
              es: 'Número del cliente copiado. Elija WhatsApp y seleccione o pegue el cliente para enviar el PDF.',
            ),
          ),
        ),
      );
    }

    final message = _tr(
      nl: 'Beste klant, in bijlage vindt u uw betaalbewijs/ritbon (PDF).',
      en: 'Dear customer, your ride receipt PDF is attached.',
      fr: 'Cher client, votre reçu de course PDF est en pièce jointe.',
      es: 'Estimado cliente, su comprobante de viaje en PDF está adjunto.',
    );

    try {
      await Share.shareXFiles(
        <XFile>[XFile(bundle.file.path)],
        text: message,
        subject: _receiptText('whatsappPdf'),
      );
    } catch (_) {
      await _fallbackWhatsAppText(context: context, item: item);
    }
  }

  static Future<void> sharePdfViaEmail({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final contact = _resolvePdfContact(item);
    final recipient = (contact.email ?? '').trim();
    final bundle = await _buildReceiptPdfBundle(context: context, item: item);
    if (bundle == null) {
      await _fallbackEmailText(context: context, item: item);
      return;
    }
    final serverResult = await _sendReceiptEmailViaWorker(
      item: item,
      language: _currentLanguageCode(),
      source: 'flutter_receipt_button',
    );
    final serverStatus = (serverResult['status'] ?? '').toString();
    final serverOk = serverResult['ok'] == true;
    if (!context.mounted) return;
    if (serverOk && serverStatus == 'sent') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'E-mail verzonden naar klant.',
              en: 'Email sent to customer.',
              fr: 'E-mail envoye au client.',
              es: 'Correo enviado al cliente.',
            ),
          ),
        ),
      );
      return;
    }
    if (serverOk && serverStatus == 'already_sent') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Factuur werd al verzonden.',
              en: 'Invoice was already sent.',
              fr: 'La facture a deja ete envoyee.',
              es: 'La factura ya fue enviada.',
            ),
          ),
        ),
      );
      return;
    }
    if (serverStatus == 'missing_email') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Geen klantmail gevonden.',
              en: 'No customer email found.',
              fr: 'Aucun e-mail client trouve.',
              es: 'No se encontro correo del cliente.',
            ),
          ),
        ),
      );
      return;
    }
    if (!serverOk || serverStatus == 'skipped' || serverStatus == 'error') {
      debugPrint(
        '[PDF][ACTION][EMAIL_PDF] emailFound=${recipient.isNotEmpty} hasPdf=true composer=server_failed status=$serverStatus',
      );
      await _showEmailFallbackOptions(
        context: context,
        bundle: bundle,
        recipient: recipient,
        item: item,
      );
      return;
    }
    final shortBody = _tr(
      nl: 'Beste klant, in bijlage vindt u uw betaalbewijs/ritbon (PDF).',
      en: 'Dear customer, your ride receipt PDF is attached.',
      fr: 'Cher client, votre reçu de course PDF est en pièce jointe.',
      es: 'Estimado cliente, su comprobante de viaje en PDF está adjunto.',
    );
    if (recipient.isNotEmpty &&
        !kIsWeb &&
        (Platform.isAndroid || Platform.isIOS)) {
      try {
        final email = Email(
          recipients: <String>[recipient],
          subject: _receiptText('receiptEmailSubject'),
          body: shortBody,
          attachmentPaths: <String>[bundle.file.path],
          isHTML: false,
        );
        await FlutterEmailSender.send(email);
        debugPrint(
          '[PDF][ACTION][EMAIL_PDF] emailFound=true hasPdf=true composer=native',
        );
        return;
      } catch (_) {
        // Fall through to share-sheet fallback.
      }
    }
    debugPrint(
      '[PDF][ACTION][EMAIL_PDF] emailFound=${recipient.isNotEmpty} hasPdf=true composer=share_fallback',
    );
    await Share.shareXFiles(
      <XFile>[XFile(bundle.file.path)],
      text: shortBody,
      subject: _receiptText('receiptEmailSubject'),
    );
    if (!context.mounted) return;
    if (recipient.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: recipient));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'E-mailadres gekopieerd. Deel de PDF nu via de gekozen mail-app.',
              en: 'Email copied. Share the PDF now via the selected mail app.',
              fr: 'E-mail copié. Partagez maintenant le PDF via l’application e-mail choisie.',
              es: 'Correo copiado. Comparta ahora el PDF mediante la app de correo elegida.',
            ),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('noCustomerContact'))),
      );
    }
  }

  static Future<void> printPdf({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final bundle = await _buildReceiptPdfBundle(context: context, item: item);
    if (bundle == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_receiptText('printLater'))));
      return;
    }
    await Printing.layoutPdf(onLayout: (_) async => bundle.bytes);
  }

  static Future<void> _fallbackCopyText({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    await Clipboard.setData(ClipboardData(text: _receiptCustomerMessage(item)));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_receiptText('receiptCopied'))));
  }

  static Future<void> _fallbackWhatsAppText({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final contact = _resolvePdfContact(item);
    final phone = _normalizePhoneForWhatsApp(
      contact.phoneRaw,
      countryContext: _customerCountryContext(item),
    );
    debugPrint(
      '[PDF][ACTION][WHATSAPP_TEXT] phoneFound=${phone != null} source=${contact.source}',
    );
    if (phone == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('noValidWhatsappPhone'))),
      );
      return;
    }
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.https('wa.me', '/$digits', <String, String>{
      'text': _tr(
        nl: 'Beste klant, uw betaalbewijs/ritbon is klaar. Ik stuur de PDF zo meteen door.',
        en: 'Dear customer, your ride receipt is ready. I will send the PDF shortly.',
        fr: 'Cher client, votre reçu de course est prêt. Je vais envoyer le PDF dans un instant.',
        es: 'Estimado cliente, su comprobante de viaje está listo. Enviaré el PDF en un momento.',
      ),
    });
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('whatsappOpenFailed'))),
      );
    }
  }

  static Future<void> _fallbackEmailText({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final contact = _resolvePdfContact(item);
    final recipient = (contact.email ?? '').trim();
    final encodedSubject = Uri.encodeComponent(
      _receiptText('receiptEmailSubject'),
    );
    final encodedBody = Uri.encodeComponent(_receiptCustomerMessage(item));
    final uri = Uri.parse(
      recipient.isNotEmpty
          ? 'mailto:${Uri.encodeComponent(recipient)}?subject=$encodedSubject&body=$encodedBody'
          : 'mailto:?subject=$encodedSubject&body=$encodedBody',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_receiptText('emailOpenFailed'))));
    }
  }

  static Future<Map<String, dynamic>> _sendReceiptEmailViaWorker({
    required _TripHistoryItem item,
    required String language,
    required String source,
  }) async {
    final bookingId = (item.bookingId ?? '').trim();
    if (bookingId.isEmpty) {
      return <String, dynamic>{
        'ok': false,
        'status': 'error',
        'message': 'Missing booking id',
      };
    }
    final uri = Uri.parse(
      '$kBookingBaseUrl/bookings/${Uri.encodeComponent(bookingId)}/receipt/email',
    );
    final payload = <String, dynamic>{
      'manual': true,
      'language': _normalizeLanguageCode(language),
      'source': source,
    };
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ..._adminHeaders(),
    };
    try {
      final res = await http
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(res.body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{
        'ok': false,
        'status': 'error',
        'message': 'Unexpected server response',
      };
    } catch (err) {
      return <String, dynamic>{
        'ok': false,
        'status': 'error',
        'message': err.toString(),
      };
    }
  }

  static Future<void> _showEmailFallbackOptions({
    required BuildContext context,
    required _ReceiptPdfBundle bundle,
    required String recipient,
    required _TripHistoryItem item,
  }) async {
    if (!context.mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: Text(
                _tr(
                  nl: 'Open mail-app',
                  en: 'Open mail app',
                  fr: 'Ouvrir app e-mail',
                  es: 'Abrir app de correo',
                ),
              ),
              onTap: () => Navigator.of(sheetContext).pop('open_mail'),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(
                _tr(
                  nl: 'Deel PDF',
                  en: 'Share PDF',
                  fr: 'Partager le PDF',
                  es: 'Compartir PDF',
                ),
              ),
              onTap: () => Navigator.of(sheetContext).pop('share_pdf'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'open_mail') {
      await _openMailComposerFallback(
        context: context,
        bundle: bundle,
        recipient: recipient,
        item: item,
      );
      return;
    }
    await _sharePdfFallback(
      context: context,
      bundle: bundle,
      recipient: recipient,
      item: item,
    );
  }

  static Future<void> _openMailComposerFallback({
    required BuildContext context,
    required _ReceiptPdfBundle bundle,
    required String recipient,
    required _TripHistoryItem item,
  }) async {
    final shortBody = _tr(
      nl: 'Beste klant, in bijlage vindt u uw betaalbewijs/ritbon (PDF).',
      en: 'Dear customer, your ride receipt PDF is attached.',
      fr: 'Cher client, votre reçu de course PDF est en pièce jointe.',
      es: 'Estimado cliente, su comprobante de viaje en PDF está adjunto.',
    );
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final email = Email(
          recipients: recipient.isNotEmpty
              ? <String>[recipient]
              : const <String>[],
          subject: _receiptText('receiptEmailSubject'),
          body: shortBody,
          attachmentPaths: <String>[bundle.file.path],
          isHTML: false,
        );
        await FlutterEmailSender.send(email);
        debugPrint(
          '[PDF][ACTION][EMAIL_PDF] emailFound=${recipient.isNotEmpty} hasPdf=true composer=native',
        );
        return;
      } catch (_) {
        // Fall through to share fallback.
      }
    }
    await _sharePdfFallback(
      context: context,
      bundle: bundle,
      recipient: recipient,
      item: item,
    );
  }

  static Future<void> _sharePdfFallback({
    required BuildContext context,
    required _ReceiptPdfBundle bundle,
    required String recipient,
    required _TripHistoryItem item,
  }) async {
    final shortBody = _tr(
      nl: 'Beste klant, in bijlage vindt u uw betaalbewijs/ritbon (PDF).',
      en: 'Dear customer, your ride receipt PDF is attached.',
      fr: 'Cher client, votre reçu de course PDF est en pièce jointe.',
      es: 'Estimado cliente, su comprobante de viaje en PDF está adjunto.',
    );
    debugPrint(
      '[PDF][ACTION][EMAIL_PDF] emailFound=${recipient.isNotEmpty} hasPdf=true composer=share_fallback',
    );
    await Share.shareXFiles(
      <XFile>[XFile(bundle.file.path)],
      text: shortBody,
      subject: _receiptText('receiptEmailSubject'),
    );
    if (!context.mounted) return;
    if (recipient.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: recipient));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'E-mailadres gekopieerd. Deel de PDF nu via de gekozen mail-app.',
              en: 'Email copied. Share the PDF now via the selected mail app.',
              fr: 'E-mail copie. Partagez maintenant le PDF via l app e-mail choisie.',
              es: 'Correo copiado. Comparta ahora el PDF mediante la app de correo elegida.',
            ),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('noCustomerContact'))),
      );
    }
  }

  static String _normalizeLanguageCode(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'nl' ||
        normalized == 'en' ||
        normalized == 'fr' ||
        normalized == 'es') {
      return normalized;
    }
    return 'nl';
  }

  static String _currentLanguageCode() {
    switch (appConfig.currentLanguage) {
      case AppLanguage.en:
        return 'en';
      case AppLanguage.fr:
        return 'fr';
      case AppLanguage.es:
        return 'es';
      case AppLanguage.nl:
        return 'nl';
    }
  }

  static Future<_ReceiptPdfBundle?> _buildReceiptPdfBundle({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    try {
      final contact = _resolvePdfContact(item);
      final keyList = contact.keys.join(',');
      debugPrint(
        '[PDF][CONTACT] emailFound=${contact.email != null} phoneFound=${contact.phoneRaw != null} source=${contact.source} keys=$keyList',
      );
      final route = _resolveRoute(item);
      debugPrint(
        '[PDF][ROUTE] fromFound=${route.from != _receiptText('currentLocation')} toFound=${route.to != '-'} source=${route.source}',
      );

      final seller = await _buildSellerProfile();
      final logoBytes = await _loadReceiptLogoBytes(seller['logoPath']);
      final doc = pw.Document();
      final baseFont = await PdfGoogleFonts.notoSansRegular();
      final boldFont = await PdfGoogleFonts.notoSansBold();
      final amounts = _resolvedReceiptAmounts(item);
      final paymentMethod = _localizedPaymentMethodValue(
        _firstPathText(item, const [
          ['payment_method'],
          ['paymentMethod'],
          ['booking', 'payment_method'],
          ['booking', 'paymentMethod'],
        ]),
      );
      final paymentSource = _localizedPaymentSourceValue(
        _firstPathText(item, const [
          ['payment_source'],
          ['paymentSource'],
          ['booking', 'payment_source'],
          ['booking', 'paymentSource'],
        ]),
      );
      final rideDateText =
          _firstPathText(item, const [
                ['scheduled_pickup_at'],
                ['booking', 'scheduled_pickup_at'],
              ]) !=
              null
          ? _formatDate(
              _firstPathText(item, const [
                ['scheduled_pickup_at'],
                ['booking', 'scheduled_pickup_at'],
              ]),
            )
          : _formatDate(item.startedAt);
      final serviceText = _displayServiceToken(
        _firstPathText(item, const [
          ['service_type'],
          ['booking', 'service_type'],
        ]),
      );
      final tierText = _displayTierToken(
        _firstPathText(item, const [
          ['tier'],
          ['booking', 'tier'],
        ]),
      );
      final durationText =
          _minutesText(
            _firstPathDouble(item, 'duration_route_min') ??
                _firstPathDouble(item, 'route_minutes'),
          ) ??
          _receiptText('notAvailable');
      final documentTitle = _isBusinessDocument(item)
          ? _receiptText('invoiceLabel')
          : _receiptText('paymentReceiptLabel');
      final footerText = seller['footer']?.trim().isNotEmpty == true
          ? seller['footer']!.trim()
          : _receiptText('pdfFooterDefault');

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (pw.Context pdfContext) => [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (logoBytes != null)
                  pw.Container(
                    width: 82,
                    height: 82,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                    ),
                    child: pw.Image(
                      pw.MemoryImage(logoBytes),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        seller['companyName'] ?? kCompanyName,
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          font: boldFont,
                        ),
                        textAlign: pw.TextAlign.right,
                      ),
                      if ((seller['legalName'] ?? '').trim().isNotEmpty &&
                          seller['legalName'] != seller['companyName'])
                        pw.Text(
                          seller['legalName']!,
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['address'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          seller['address']!,
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['vatNumber'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyVat')}: ${seller['vatNumber']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['phone'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyPhone')}: ${seller['phone']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['email'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyEmail')}: ${seller['email']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['website'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyWebsite')}: ${seller['website']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              documentTitle,
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                font: boldFont,
              ),
            ),
            pw.SizedBox(height: 10),
            _pdfInfoRow(_receiptText('reference'), _customerReference(item)),
            _pdfInfoRow(_receiptText('date'), rideDateText),
            _pdfInfoRow(_receiptText('type'), item.kindLabel),
            _pdfInfoRow(_receiptText('service'), serviceText),
            _pdfInfoRow(_receiptText('tier'), tierText),
            _pdfInfoRow(_receiptText('from'), route.from),
            _pdfInfoRow(_receiptText('to'), route.to),
            _pdfInfoRow(_receiptText('distance'), _kmText(item)),
            _pdfInfoRow(_receiptText('duration'), durationText),
            pw.SizedBox(height: 12),
            pw.Text(
              _receiptText('customerDetails'),
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                font: boldFont,
              ),
            ),
            pw.SizedBox(height: 6),
            _pdfInfoRow(
              _receiptText('customerName'),
              contact.name ?? _receiptText('notAvailable'),
            ),
            _pdfInfoRow(
              _receiptText('customerEmail'),
              contact.email ?? _receiptText('notAvailable'),
            ),
            _pdfInfoRow(
              _receiptText('customerPhone'),
              contact.phoneRaw ?? _receiptText('notAvailable'),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              _receiptText('paymentActions'),
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                font: boldFont,
              ),
            ),
            pw.SizedBox(height: 6),
            _pdfInfoRow(
              _receiptText('paymentStatus'),
              _paymentStatusText(item),
            ),
            _pdfInfoRow(_receiptText('paymentMethod'), paymentMethod),
            _pdfInfoRow(_receiptText('paymentSource'), paymentSource),
            pw.Divider(color: PdfColors.grey400),
            _pdfInfoRow(
              _receiptText('subtotalExVat'),
              '€ ${amounts.subtotal.toStringAsFixed(2)}',
            ),
            _pdfInfoRow(
              '${_receiptText('vatAmount')} (${(amounts.vatRate * 100).toStringAsFixed(0)}%)',
              '€ ${amounts.vatAmount.toStringAsFixed(2)}',
            ),
            _pdfInfoRow(
              _receiptText('total'),
              '€ ${amounts.total.toStringAsFixed(2)}',
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              footerText,
              style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
            ),
          ],
          theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
        ),
      );

      final bytes = await doc.save();
      final tempDir = await getTemporaryDirectory();
      final receiptsDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}fluxidi_receipts',
      );
      if (!await receiptsDir.exists()) {
        await receiptsDir.create(recursive: true);
      }
      final fileName = _sanitizeFilePart(_customerReference(item));
      final file = File(
        '${receiptsDir.path}${Platform.pathSeparator}$fileName.pdf',
      );
      await file.writeAsBytes(bytes, flush: true);
      return _ReceiptPdfBundle(bytes: bytes, file: file);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('pdfGenerationFailed'))),
        );
      }
      return null;
    }
  }

  static ({String from, String to, String source}) _resolveRoute(
    _TripHistoryItem item,
  ) {
    bool isPlaceholder(String? value) {
      final text = value?.trim();
      if (text == null || text.isEmpty) return true;
      if (text == '-' || text == '—') return true;
      return text.toLowerCase() ==
          _receiptText('currentLocation').toLowerCase();
    }

    String? pickLabel(List<List<String>> paths) {
      for (final path in paths) {
        final text = _cleanContactText(_detailAt(item, path));
        if (!isPlaceholder(text)) return text;
      }
      return null;
    }

    final normalizedFrom = isPlaceholder(item.origin)
        ? null
        : item.origin.trim();
    final normalizedTo = isPlaceholder(item.destination)
        ? null
        : item.destination.trim();
    final rawFrom = pickLabel(const [
      ['from'],
      ['pickup'],
      ['pickup_address'],
      ['pickupAddress'],
      ['pickupLocation'],
      ['pickup_location'],
      ['origin'],
      ['start_address'],
      ['startAddress'],
      ['booking', 'from'],
      ['booking', 'pickup'],
      ['booking', 'pickup_address'],
      ['booking', 'pickupAddress'],
      ['record', 'from'],
      ['record', 'booking', 'from'],
      ['record', 'booking', 'pickup'],
      ['payload', 'from'],
      ['payload', 'booking', 'from'],
      ['quote', 'inputs', 'from'],
    ]);
    final rawTo = pickLabel(const [
      ['to'],
      ['destination'],
      ['destination_address'],
      ['destinationAddress'],
      ['dropoff'],
      ['dropoff_address'],
      ['dropoffAddress'],
      ['end_address'],
      ['endAddress'],
      ['booking', 'to'],
      ['booking', 'destination'],
      ['booking', 'destination_address'],
      ['booking', 'destinationAddress'],
      ['record', 'to'],
      ['record', 'booking', 'to'],
      ['record', 'booking', 'destination'],
      ['payload', 'to'],
      ['payload', 'booking', 'to'],
      ['quote', 'inputs', 'to'],
    ]);
    final from = normalizedFrom ?? rawFrom ?? _receiptText('currentLocation');
    final to = normalizedTo ?? rawTo ?? '-';
    final source = (normalizedFrom != null || normalizedTo != null)
        ? 'normalized'
        : ((rawFrom != null || rawTo != null) ? 'raw' : 'fallback');
    return (from: from, to: to, source: source);
  }

  static _ResolvedPdfContact _resolvePdfContact(_TripHistoryItem item) {
    String? pick(
      List<List<String>> paths,
      List<String> usedKeys, {
      bool email = false,
    }) {
      for (final path in paths) {
        final text = _cleanContactText(_detailAt(item, path));
        if (text == null || text.isEmpty) continue;
        final normalized = email ? _validEmail(text) : text;
        if (normalized == null || normalized.isEmpty) continue;
        usedKeys.add(path.join('.'));
        return normalized;
      }
      return null;
    }

    final keys = <String>[];
    final normalizedName = _cleanContactText(item.customerName);
    final normalizedPhone = _cleanContactText(item.customerPhone);
    final normalizedEmail = _validEmail(item.customerEmail);
    if (normalizedName != null) keys.add('normalized.customerName');
    if (normalizedPhone != null) keys.add('normalized.customerPhone');
    if (normalizedEmail != null) keys.add('normalized.customerEmail');
    final hasNormalized =
        normalizedName != null ||
        normalizedPhone != null ||
        normalizedEmail != null;
    if (hasNormalized) {
      return _ResolvedPdfContact(
        name: normalizedName,
        phoneRaw: normalizedPhone,
        email: normalizedEmail,
        keys: keys,
        source: 'normalized',
      );
    }

    final name = pick(const [
      ['customer', 'name'],
      ['customer_name'],
      ['customerName'],
      ['custName'],
      ['name'],
      ['booking', 'customer', 'name'],
      ['booking', 'customer_name'],
      ['booking', 'customerName'],
      ['booking', 'custName'],
      ['booking', 'name'],
      ['record', 'customer_name'],
      ['record', 'booking', 'customer_name'],
      ['record', 'booking', 'customerName'],
      ['payload', 'customer_name'],
      ['payload', 'booking', 'customer_name'],
      ['record', 'payload', 'customer_name'],
      ['record', 'payload', 'customerName'],
      ['record', 'payload', 'custName'],
      ['record', 'payload', 'name'],
      ['record', 'payload', 'booking', 'customer_name'],
      ['record', 'payload', 'booking', 'customerName'],
      ['record', 'payload', 'booking', 'custName'],
      ['record', 'payload', 'booking', 'name'],
    ], keys);

    final phoneRaw = pick(const [
      ['customer', 'phone'],
      ['customer_phone'],
      ['customerPhone'],
      ['custPhone'],
      ['phone'],
      ['tel'],
      ['mobile'],
      ['booking', 'customer', 'phone'],
      ['booking', 'customer_phone'],
      ['booking', 'customerPhone'],
      ['booking', 'custPhone'],
      ['booking', 'phone'],
      ['booking', 'tel'],
      ['booking', 'mobile'],
      ['record', 'customer_phone'],
      ['record', 'booking', 'customer_phone'],
      ['record', 'booking', 'customerPhone'],
      ['record', 'booking', 'custPhone'],
      ['payload', 'customer_phone'],
      ['payload', 'booking', 'customer_phone'],
      ['record', 'payload', 'customer_phone'],
      ['record', 'payload', 'customerPhone'],
      ['record', 'payload', 'custPhone'],
      ['record', 'payload', 'phone'],
      ['record', 'payload', 'tel'],
      ['record', 'payload', 'mobile'],
      ['record', 'payload', 'booking', 'customer_phone'],
      ['record', 'payload', 'booking', 'customerPhone'],
      ['record', 'payload', 'booking', 'custPhone'],
      ['record', 'payload', 'booking', 'phone'],
    ], keys);

    final email = pick(
      const [
        ['customer', 'email'],
        ['customer_email'],
        ['customerEmail'],
        ['custEmail'],
        ['email'],
        ['invoice_email'],
        ['invoiceEmail'],
        ['booking', 'customer', 'email'],
        ['booking', 'customer_email'],
        ['booking', 'customerEmail'],
        ['booking', 'custEmail'],
        ['booking', 'email'],
        ['booking', 'invoice_email'],
        ['booking', 'invoiceEmail'],
        ['record', 'customer_email'],
        ['record', 'booking', 'customer_email'],
        ['record', 'booking', 'customerEmail'],
        ['record', 'booking', 'custEmail'],
        ['payload', 'customer_email'],
        ['payload', 'booking', 'customer_email'],
        ['record', 'payload', 'customer_email'],
        ['record', 'payload', 'customerEmail'],
        ['record', 'payload', 'custEmail'],
        ['record', 'payload', 'email'],
        ['record', 'payload', 'invoice_email'],
        ['record', 'payload', 'invoiceEmail'],
        ['record', 'payload', 'booking', 'customer_email'],
        ['record', 'payload', 'booking', 'customerEmail'],
        ['record', 'payload', 'booking', 'custEmail'],
        ['record', 'payload', 'booking', 'email'],
        ['record', 'payload', 'booking', 'invoice_email'],
        ['record', 'payload', 'booking', 'invoiceEmail'],
      ],
      keys,
      email: true,
    );

    final hasRaw = name != null || phoneRaw != null || email != null;
    return _ResolvedPdfContact(
      name: name,
      phoneRaw: phoneRaw,
      email: email,
      keys: keys,
      source: hasRaw ? 'raw' : 'none',
    );
  }

  static String? _customerCountryContext(_TripHistoryItem item) {
    final value = _firstPathText(item, const [
      ['phone_country_code'],
      ['phoneCountryCode'],
      ['dial_code'],
      ['dialCode'],
      ['customer_country'],
      ['customerCountry'],
      ['country'],
      ['countryCode'],
      ['country_iso'],
      ['countryIso'],
      ['locale'],
      ['language'],
    ]);
    if (value != null && value.trim().isNotEmpty) return value;
    if (kTenantId.toLowerCase().trim() == 'fluxidi') return 'BE';
    return null;
  }

  static dynamic _detailAt(_TripHistoryItem item, List<String> path) {
    dynamic current = item.bookingDetails;
    for (final key in path) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        current = null;
        break;
      }
    }
    if (current != null) return current;
    current = item.rawSource;
    for (final key in path) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  static String? _cleanContactText(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  static String? _firstPathText(
    _TripHistoryItem item,
    List<List<String>> paths,
  ) {
    for (final path in paths) {
      final text = _cleanContactText(_detailAt(item, path));
      if (text != null) return text;
    }
    return null;
  }

  static String? _validEmail(String? value) {
    final email = value?.trim();
    if (email == null || email.isEmpty) return null;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return null;
    return email;
  }

  static String? _normalizePhoneForWhatsApp(
    String? raw, {
    String? countryContext,
  }) {
    final input = raw?.trim();
    if (input == null || input.isEmpty) return null;
    var cleaned = input.replaceAll(RegExp(r'[\s\-\(\)\/\.]'), '');
    if (cleaned.startsWith('00')) cleaned = '+${cleaned.substring(2)}';
    if (cleaned.startsWith('+')) {
      final digits = cleaned.substring(1).replaceAll(RegExp(r'\D'), '');
      if (digits.length < 8 || digits.length > 15) return null;
      return '+$digits';
    }
    final digits = cleaned.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) return null;

    final context = countryContext?.toUpperCase().trim() ?? '';
    if ((context == 'BE' || context == 'BELGIUM' || context.isEmpty) &&
        digits.startsWith('0') &&
        digits.length >= 9) {
      final national = digits.replaceFirst(RegExp(r'^0+'), '');
      if (national.isEmpty) return null;
      return '+32$national';
    }
    return null;
  }

  static String _formatDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(dt.day)}-${two(dt.month)}-${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  static double? _detailDouble(_TripHistoryItem item, String key) {
    final value = item.bookingDetails[key];
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.'));
  }

  static double? _firstPathDouble(_TripHistoryItem item, String key) {
    final direct = _detailDouble(item, key);
    if (direct != null) return direct;
    final text = _firstPathText(item, <List<String>>[
      <String>[key],
      <String>['booking', key],
    ]);
    if (text == null) return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  static double? _receiptTotalAmount(_TripHistoryItem item) {
    if (item.kind.toLowerCase().trim() == 'planned') {
      return _detailDouble(item, 'booking_total_eur') ?? item.totalEur;
    }
    return item.totalEur;
  }

  static String _moneyText(double? value) {
    if (value == null) return _receiptText('notAvailable');
    return '€ ${value.toStringAsFixed(2)}';
  }

  static String _totalText(_TripHistoryItem item) =>
      _moneyText(_receiptTotalAmount(item));

  static String _kmText(_TripHistoryItem item) {
    final km = item.kmTotal;
    if (km == null) return _receiptText('notAvailable');
    return '${km.toStringAsFixed(2)} km';
  }

  static String? _minutesText(double? value) {
    if (value == null) return null;
    return '${value.round()} min';
  }

  static bool _isBusinessDocument(_TripHistoryItem item) {
    final invoiceRequested = _toBoolFlag(
      _firstPathText(item, const [
        ['invoice_requested'],
        ['invoiceRequested'],
        ['booking', 'invoice_requested'],
        ['booking', 'invoiceRequested'],
        ['record', 'booking', 'invoice_requested'],
        ['record', 'booking', 'invoiceRequested'],
      ]),
    );
    final customerCompany = _firstPathText(item, const [
      ['company_name'],
      ['companyName'],
      ['customer_company'],
      ['customerCompany'],
      ['booking', 'company_name'],
      ['booking', 'companyName'],
      ['record', 'booking', 'company_name'],
      ['record', 'booking', 'companyName'],
    ]);
    final customerVat = _firstPathText(item, const [
      ['vat_number'],
      ['vatNumber'],
      ['customer_vat'],
      ['customerVat'],
      ['booking', 'vat_number'],
      ['booking', 'vatNumber'],
      ['record', 'booking', 'vat_number'],
      ['record', 'booking', 'vatNumber'],
    ]);
    return invoiceRequested ||
        (customerCompany != null && customerCompany.trim().isNotEmpty) ||
        (customerVat != null && customerVat.trim().isNotEmpty);
  }

  static bool _toBoolFlag(String? value) {
    final normalized = value?.toLowerCase().trim() ?? '';
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'ja';
  }

  static ({double subtotal, double vatAmount, double total, double vatRate})
  _resolvedReceiptAmounts(_TripHistoryItem item) {
    final settingsVatRate = businessSettingsNotifier.value.pricingVatRate;
    final vatRateCandidates = <double?>[
      _detailDouble(item, 'vat_rate'),
      _detailDouble(item, 'vatRate'),
      _detailDouble(item, 'booking_vat_rate'),
      _detailDouble(item, 'bookingVatRate'),
    ];
    double vatRate = settingsVatRate.clamp(0.0, 1.0);
    for (final candidate in vatRateCandidates) {
      if (candidate == null || !candidate.isFinite) continue;
      if (candidate > 1.0) {
        vatRate = candidate / 100.0;
        break;
      }
      if (candidate >= 0.0) {
        vatRate = candidate;
        break;
      }
    }
    final total =
        _receiptTotalAmount(item) ??
        _detailDouble(item, 'total') ??
        _detailDouble(item, 'booking_total_eur') ??
        0.0;
    final subtotalCandidate =
        _detailDouble(item, 'subtotal_ex_vat') ??
        _detailDouble(item, 'subtotalExVat') ??
        _detailDouble(item, 'price_ex_vat') ??
        _detailDouble(item, 'priceExVat');
    final vatAmountCandidate =
        _detailDouble(item, 'vat_amount') ??
        _detailDouble(item, 'vatAmount') ??
        _detailDouble(item, 'price_vat') ??
        _detailDouble(item, 'priceVat');

    final subtotal =
        subtotalCandidate ?? (vatRate > 0 ? (total / (1.0 + vatRate)) : total);
    final vatAmount = vatAmountCandidate ?? (total - subtotal);
    return (
      subtotal: subtotal.isFinite ? subtotal : 0.0,
      vatAmount: vatAmount.isFinite ? vatAmount : 0.0,
      total: total.isFinite ? total : 0.0,
      vatRate: vatRate.isFinite ? vatRate : 0.0,
    );
  }

  static String _customerReference(_TripHistoryItem item) {
    final direct = _firstPathText(item, const [
      ['public_reference'],
      ['publicReference'],
      ['receipt_reference'],
      ['receiptReference'],
      ['booking', 'public_reference'],
      ['booking', 'publicReference'],
      ['booking', 'receipt_reference'],
      ['booking', 'receiptReference'],
      ['booking', 'bookingId'],
      ['booking_id'],
      ['bookingId'],
      ['id'],
    ]);
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();
    final bookingId = (item.bookingId ?? '').trim();
    if (bookingId.isNotEmpty) return bookingId;
    final receiptNumber = item.receiptNumber.trim();
    return receiptNumber.isNotEmpty ? receiptNumber : '—';
  }

  static String _localizedPaymentMethodValue(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return _receiptText('notAvailable');
    final normalized = value
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    switch (normalized) {
      case 'cash':
        return _tr(nl: 'Cash', en: 'Cash', fr: 'Espèces', es: 'Efectivo');
      case 'bancontact':
        return _tr(
          nl: 'Bancontact',
          en: 'Bancontact',
          fr: 'Bancontact',
          es: 'Bancontact',
        );
      case 'card':
        return _tr(nl: 'Kaart', en: 'Card', fr: 'Carte', es: 'Tarjeta');
      case 'qr':
      case 'qr_code':
        return _tr(
          nl: 'QR-code',
          en: 'QR code',
          fr: 'Code QR',
          es: 'Código QR',
        );
      case 'mollie':
        return _tr(
          nl: 'Online betaling',
          en: 'Online payment',
          fr: 'Paiement en ligne',
          es: 'Pago en línea',
        );
      default:
        return _titleCaseToken(value);
    }
  }

  static String _localizedPaymentSourceValue(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return _receiptText('notAvailable');
    final normalized = value
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    switch (normalized) {
      case 'in_car':
        return _tr(
          nl: 'In de wagen',
          en: 'In vehicle',
          fr: 'Dans le véhicule',
          es: 'En el vehículo',
        );
      case 'payment_link':
        return _tr(
          nl: 'Betaallink',
          en: 'Payment link',
          fr: 'Lien de paiement',
          es: 'Enlace de pago',
        );
      case 'mollie':
        return _tr(
          nl: 'Online betaling',
          en: 'Online payment',
          fr: 'Paiement en ligne',
          es: 'Pago en línea',
        );
      default:
        return _titleCaseToken(value);
    }
  }

  static String _displayServiceToken(String? value) {
    final raw = value?.trim() ?? '';
    final normalized = raw.toLowerCase().replaceAll('-', '_').trim();
    if (normalized == 'passenger' ||
        normalized == 'personenvervoer' ||
        normalized == 'passenger_transport') {
      return _receiptText('passengerTransport');
    }
    if (normalized == 'airport' ||
        normalized == 'airport_transfer' ||
        normalized == 'luchthaven') {
      return _receiptText('airportTransfer');
    }
    return _titleCaseToken(raw);
  }

  static String _displayTierToken(String? value) {
    final raw = value?.trim() ?? '';
    final normalized = raw.toLowerCase().replaceAll('-', '_').trim();
    if (normalized == 'comfort') return _receiptText('tierComfort');
    if (normalized == 'private') return _receiptText('tierPrivate');
    if (normalized == 'premium') return _receiptText('tierPremium');
    return _titleCaseToken(raw);
  }

  static String _paymentStatusText(_TripHistoryItem item) {
    final raw = _firstPathText(item, const [
      ['payment_status'],
      ['paymentStatus'],
      ['booking', 'payment_status'],
      ['booking', 'paymentStatus'],
      ['record', 'payment_status'],
      ['record', 'paymentStatus'],
      ['record', 'booking', 'payment_status'],
      ['record', 'booking', 'paymentStatus'],
      ['mollie', 'status'],
      ['record', 'mollie', 'status'],
    ])?.toLowerCase().trim();
    if (raw == 'paid' || raw == 'settled' || raw == 'confirmed') {
      return _receiptText('paid');
    }
    if (raw == 'open' || raw == 'pending' || raw == 'authorized') {
      return _receiptText('paymentSent');
    }
    return _receiptText('unpaid');
  }

  static String _receiptCustomerMessage(_TripHistoryItem item) {
    final route = _resolveRoute(item);
    final lines = <String>[
      '${_receiptText('receiptFrom')} $kCompanyName',
      '${_receiptText('type')}: ${item.kindLabel}',
      '${_receiptText('reference')}: ${_customerReference(item)}',
      '${_receiptText('from')}: ${route.from}',
      '${_receiptText('to')}: ${route.to}',
      if (_firstPathText(item, const [
            ['scheduled_pickup_at'],
            ['booking', 'scheduled_pickup_at'],
          ]) !=
          null)
        '${_receiptText('scheduledPickup')}: ${_formatDate(_firstPathText(item, const [
          ['scheduled_pickup_at'],
          ['booking', 'scheduled_pickup_at'],
        ]))}',
      if (item.startedAt?.trim().isNotEmpty ?? false)
        '${_receiptText('startTime')}: ${_formatDate(item.startedAt)}',
      if (item.stoppedAt?.trim().isNotEmpty ?? false)
        '${_receiptText('endTime')}: ${_formatDate(item.stoppedAt)}',
      '${_receiptText('distance')}: ${_kmText(item)}',
      '${_receiptText('total')}: ${_totalText(item)}',
      '${_receiptText('paymentStatus')}: ${_paymentStatusText(item)}',
      '',
      _receiptText('thanksRide'),
    ];
    return lines.join('\n');
  }

  static String _sanitizeFilePart(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return cleaned.isEmpty ? 'receipt' : cleaned;
  }

  static String _titleCaseToken(String value) {
    final normalized = value.trim().replaceAll('_', ' ').replaceAll('-', ' ');
    if (normalized.isEmpty) return '—';
    return normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) => part.length == 1
              ? part.toUpperCase()
              : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  static pw.Widget _pdfInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 140,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }

  static Future<Uint8List?> _loadReceiptLogoBytes(String? preferredPath) async {
    final candidates = <String>[
      if (preferredPath != null && preferredPath.trim().isNotEmpty)
        preferredPath.trim(),
      kFluxidiLogoAsset,
    ];
    for (final candidate in candidates) {
      try {
        if (candidate.startsWith('assets/')) {
          final data = await rootBundle.load(candidate);
          return data.buffer.asUint8List();
        }
        final f = File(candidate);
        if (await f.exists()) {
          return await f.readAsBytes();
        }
      } catch (_) {
        // Ignore and try next candidate.
      }
    }
    return null;
  }

  static Future<Map<String, String>> _buildSellerProfile() async {
    final settings = businessSettingsNotifier.value;
    BackendBusinessProfile? backendProfile;
    try {
      backendProfile = await fetchBackendBusinessProfile();
    } catch (_) {
      backendProfile = null;
    }
    final profile = backendProfile ?? BackendBusinessProfile.defaults();
    final postcodeCity = [
      profile.postcode.trim(),
      profile.city.trim(),
    ].where((e) => e.isNotEmpty).join(' ');
    final address = [
      profile.address.trim().isNotEmpty
          ? profile.address.trim()
          : settings.address.trim(),
      if (postcodeCity.isNotEmpty) postcodeCity,
      if (profile.country.trim().isNotEmpty) profile.country.trim(),
    ].where((e) => e.isNotEmpty).join('\n');

    final companyName = profile.companyName.trim().isNotEmpty
        ? profile.companyName.trim()
        : settings.companyName.trim().isNotEmpty
        ? settings.companyName.trim()
        : kCompanyName;
    final legalName = profile.legalName.trim().isNotEmpty
        ? profile.legalName.trim()
        : companyName;
    final profileJson = profile.toJson();
    String localizedFooterFromProfile(AppLanguage lang) {
      final localized = switch (lang) {
        AppLanguage.en =>
          (profileJson['invoiceReceiptFooterTextEn'] ?? '').toString().trim(),
        AppLanguage.fr =>
          (profileJson['invoiceReceiptFooterTextFr'] ?? '').toString().trim(),
        AppLanguage.es =>
          (profileJson['invoiceReceiptFooterTextEs'] ?? '').toString().trim(),
        _ =>
          (profileJson['invoiceReceiptFooterTextNl'] ?? '').toString().trim(),
      };
      return localized;
    }

    final hasAnyLocalizedFooter =
        (profileJson['invoiceReceiptFooterTextNl'] ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        (profileJson['invoiceReceiptFooterTextEn'] ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        (profileJson['invoiceReceiptFooterTextFr'] ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        (profileJson['invoiceReceiptFooterTextEs'] ?? '')
            .toString()
            .trim()
            .isNotEmpty;
    final appLang = appConfig.currentLanguage;
    final localizedFooter = localizedFooterFromProfile(appLang);
    final legacyFooter = profile.invoiceReceiptFooterText.trim();
    final footerText = localizedFooter.isNotEmpty
        ? localizedFooter
        : (legacyFooter.isNotEmpty &&
              (appLang == AppLanguage.nl || !hasAnyLocalizedFooter))
        ? legacyFooter
        : _receiptText('pdfFooterDefault');

    return <String, String>{
      'companyName': companyName,
      'legalName': legalName,
      'address': address,
      'vatNumber': profile.vatNumber.trim().isNotEmpty
          ? profile.vatNumber.trim()
          : settings.vatCompanyNumber.trim(),
      'phone': profile.phone.trim().isNotEmpty
          ? profile.phone.trim()
          : settings.supportPhone.trim(),
      'email': profile.email.trim().isNotEmpty
          ? profile.email.trim()
          : settings.supportEmail.trim(),
      'website': profile.website.trim(),
      'footer': footerText,
      'logoPath': settings.logoAssetPath.trim(),
    };
  }
}

class _ResolvedPdfContact {
  final String? name;
  final String? phoneRaw;
  final String? email;
  final List<String> keys;
  final String source;

  const _ResolvedPdfContact({
    required this.name,
    required this.phoneRaw,
    required this.email,
    required this.keys,
    required this.source,
  });
}

class _RideReceiptBodyState extends State<_RideReceiptBody> {
  _ReceiptPaymentStatus _paymentStatus = _ReceiptPaymentStatus.pending;

  _TripHistoryItem get item => widget.item;

  @override
  void initState() {
    super.initState();
    _paymentStatus = _initialPaymentStatus();
    unawaited(_resolveReceiptPaymentStatus());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final action = widget.initialAction;
      if (action != null) {
        unawaited(_runInitialAction(context, action));
      }
    });
  }

  Future<void> _runInitialAction(
    BuildContext context,
    _ReceiptQuickAction action,
  ) async {
    try {
      switch (action) {
        case _ReceiptQuickAction.viewPdf:
          await _viewReceiptPdf(context);
          break;
        case _ReceiptQuickAction.sharePdf:
          await _shareReceiptPdf(context);
          break;
        case _ReceiptQuickAction.whatsappPdf:
          await _shareReceiptPdfViaWhatsApp(context);
          break;
        case _ReceiptQuickAction.emailPdf:
          await _shareReceiptPdfViaEmail(context);
          break;
        case _ReceiptQuickAction.printPdf:
          await _printReceiptPdf(context);
          break;
      }
    } finally {
      if (widget.autoPopAfterInitialAction && context.mounted) {
        Navigator.of(context).maybePop();
      }
    }
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(dt.day)}-${two(dt.month)}-${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  String _formatWait(int seconds) {
    if (seconds <= 0) return '0 min';
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    if (min <= 0) return '${sec}s';
    if (sec == 0) return '$min min';
    return '$min min ${sec}s';
  }

  bool get _isPlannedReceipt => item.kind.toLowerCase().trim() == 'planned';

  String? _detailText(String key) {
    final text = item.detail(key);
    return text == null || text == 'null' ? null : text;
  }

  _ReceiptPaymentStatus _initialPaymentStatus() {
    final raw = _firstDetailPathText(const [
      ['payment_status'],
      ['paymentStatus'],
      ['booking', 'payment_status'],
      ['booking', 'paymentStatus'],
      ['record', 'payment_status'],
      ['record', 'paymentStatus'],
      ['record', 'booking', 'payment_status'],
      ['record', 'booking', 'paymentStatus'],
      ['mollie', 'status'],
      ['record', 'mollie', 'status'],
    ])?.toLowerCase().trim();
    if (raw == 'paid' || raw == 'settled' || raw == 'confirmed') {
      return _ReceiptPaymentStatus.paid;
    }
    if (raw == 'open' || raw == 'pending' || raw == 'authorized') {
      return _ReceiptPaymentStatus.sent;
    }
    return _ReceiptPaymentStatus.pending;
  }

  _ReceiptPaymentStatus _paymentStatusFromRaw(String? raw) {
    final normalized = raw?.toLowerCase().trim();
    if (normalized == 'paid' ||
        normalized == 'settled' ||
        normalized == 'confirmed') {
      return _ReceiptPaymentStatus.paid;
    }
    if (normalized == 'open' ||
        normalized == 'pending' ||
        normalized == 'authorized') {
      return _ReceiptPaymentStatus.sent;
    }
    return _ReceiptPaymentStatus.pending;
  }

  String? _mapText(Map<String, dynamic> map, String key) {
    final value = map[key];
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text.toLowerCase() == 'null')
      return null;
    return text;
  }

  String? _historyTopLevelPaymentStatus() {
    return _mapText(item.bookingDetails, 'payment_status') ??
        _mapText(item.bookingDetails, 'paymentStatus');
  }

  String? _historyNestedPaymentStatus() {
    return _firstDetailPathText(const [
      ['booking', 'payment_status'],
      ['booking', 'paymentStatus'],
      ['booking_details', 'payment_status'],
      ['booking_details', 'paymentStatus'],
      ['record', 'payment_status'],
      ['record', 'paymentStatus'],
      ['record', 'booking', 'payment_status'],
      ['record', 'booking', 'paymentStatus'],
      ['mollie', 'status'],
      ['record', 'mollie', 'status'],
    ]);
  }

  void _mergePaymentFieldsIntoReceiptDetails(Map<String, dynamic> fields) {
    for (final entry in fields.entries) {
      final value = entry.value?.toString().trim();
      if (value == null || value.isEmpty || value.toLowerCase() == 'null')
        continue;
      item.bookingDetails[entry.key] = entry.value;
    }
    final bookingMap = item.bookingDetails['booking'];
    if (bookingMap is Map) {
      final mutableBooking = Map<String, dynamic>.from(bookingMap);
      if (fields['payment_status'] != null)
        mutableBooking['payment_status'] = fields['payment_status'];
      if (fields['paymentStatus'] != null)
        mutableBooking['paymentStatus'] = fields['paymentStatus'];
      if (fields['paid_at'] != null)
        mutableBooking['paid_at'] = fields['paid_at'];
      if (fields['paidAt'] != null) mutableBooking['paidAt'] = fields['paidAt'];
      if (fields['payment_provider'] != null)
        mutableBooking['payment_provider'] = fields['payment_provider'];
      if (fields['paymentProvider'] != null)
        mutableBooking['paymentProvider'] = fields['paymentProvider'];
      if (fields['payment_id'] != null)
        mutableBooking['payment_id'] = fields['payment_id'];
      if (fields['paymentId'] != null)
        mutableBooking['paymentId'] = fields['paymentId'];
      if (fields['payment_method'] != null)
        mutableBooking['payment_method'] = fields['payment_method'];
      if (fields['paymentMethod'] != null)
        mutableBooking['paymentMethod'] = fields['paymentMethod'];
      if (fields['payment_source'] != null)
        mutableBooking['payment_source'] = fields['payment_source'];
      if (fields['paymentSource'] != null)
        mutableBooking['paymentSource'] = fields['paymentSource'];
      item.bookingDetails['booking'] = mutableBooking;
    }
  }

  Map<String, dynamic>? _extractAuthoritativePaymentFields(
    Map<String, dynamic> root,
  ) {
    Map<String, dynamic> asMap(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    String? text(dynamic value) {
      final s = value?.toString().trim();
      if (s == null || s.isEmpty || s.toLowerCase() == 'null') return null;
      return s;
    }

    final data = asMap(root['data']);
    final record = asMap(root['record']);
    final booking = asMap(root['booking']);
    final recordBooking = asMap(record['booking']);
    final dataRecord = asMap(data['record']);
    final dataBooking = asMap(data['booking']);
    final dataRecordBooking = asMap(dataRecord['booking']);

    String? firstHit(String snake, String camel, Map<String, dynamic> map) {
      final hit = text(map[snake] ?? map[camel]);
      return hit;
    }

    final paymentStatus =
        firstHit('payment_status', 'paymentStatus', root) ??
        firstHit('payment_status', 'paymentStatus', record) ??
        firstHit('payment_status', 'paymentStatus', recordBooking) ??
        firstHit('payment_status', 'paymentStatus', booking) ??
        firstHit('payment_status', 'paymentStatus', data) ??
        firstHit('payment_status', 'paymentStatus', dataRecord) ??
        firstHit('payment_status', 'paymentStatus', dataBooking) ??
        firstHit('payment_status', 'paymentStatus', dataRecordBooking);
    final paidAt = text(
      root['paid_at'] ??
          root['paidAt'] ??
          record['paid_at'] ??
          record['paidAt'] ??
          recordBooking['paid_at'] ??
          recordBooking['paidAt'] ??
          booking['paid_at'] ??
          booking['paidAt'] ??
          data['paid_at'] ??
          data['paidAt'] ??
          dataRecord['paid_at'] ??
          dataRecord['paidAt'] ??
          dataBooking['paid_at'] ??
          dataBooking['paidAt'] ??
          dataRecordBooking['paid_at'] ??
          dataRecordBooking['paidAt'],
    );
    final paymentProvider = text(
      root['payment_provider'] ??
          root['paymentProvider'] ??
          record['payment_provider'] ??
          record['paymentProvider'] ??
          booking['payment_provider'] ??
          booking['paymentProvider'] ??
          data['payment_provider'] ??
          data['paymentProvider'] ??
          dataRecord['payment_provider'] ??
          dataRecord['paymentProvider'] ??
          dataBooking['payment_provider'] ??
          dataBooking['paymentProvider'],
    );
    final paymentId = text(
      root['payment_id'] ??
          root['paymentId'] ??
          record['payment_id'] ??
          record['paymentId'] ??
          booking['payment_id'] ??
          booking['paymentId'] ??
          data['payment_id'] ??
          data['paymentId'] ??
          dataRecord['payment_id'] ??
          dataRecord['paymentId'] ??
          dataBooking['payment_id'] ??
          dataBooking['paymentId'],
    );
    final paymentMethod = text(
      root['payment_method'] ??
          root['paymentMethod'] ??
          record['payment_method'] ??
          record['paymentMethod'] ??
          booking['payment_method'] ??
          booking['paymentMethod'] ??
          data['payment_method'] ??
          data['paymentMethod'] ??
          dataRecord['payment_method'] ??
          dataRecord['paymentMethod'] ??
          dataBooking['payment_method'] ??
          dataBooking['paymentMethod'],
    );
    final paymentSource = text(
      root['payment_source'] ??
          root['paymentSource'] ??
          record['payment_source'] ??
          record['paymentSource'] ??
          booking['payment_source'] ??
          booking['paymentSource'] ??
          data['payment_source'] ??
          data['paymentSource'] ??
          dataRecord['payment_source'] ??
          dataRecord['paymentSource'] ??
          dataBooking['payment_source'] ??
          dataBooking['paymentSource'],
    );

    if (paymentStatus == null &&
        paidAt == null &&
        paymentProvider == null &&
        paymentId == null &&
        paymentMethod == null &&
        paymentSource == null) {
      return null;
    }
    return <String, dynamic>{
      if (paymentStatus != null) ...{
        'payment_status': paymentStatus,
        'paymentStatus': paymentStatus,
      },
      if (paidAt != null) ...{'paid_at': paidAt, 'paidAt': paidAt},
      if (paymentProvider != null) ...{
        'payment_provider': paymentProvider,
        'paymentProvider': paymentProvider,
      },
      if (paymentId != null) ...{
        'payment_id': paymentId,
        'paymentId': paymentId,
      },
      if (paymentMethod != null) ...{
        'payment_method': paymentMethod,
        'paymentMethod': paymentMethod,
      },
      if (paymentSource != null) ...{
        'payment_source': paymentSource,
        'paymentSource': paymentSource,
      },
    };
  }

  String? _paymentMethodFromDetails() {
    return _firstDetailPathText(const [
      ['payment_method'],
      ['paymentMethod'],
      ['booking', 'payment_method'],
      ['booking', 'paymentMethod'],
      ['booking_details', 'payment_method'],
      ['booking_details', 'paymentMethod'],
      ['record', 'payment_method'],
      ['record', 'paymentMethod'],
      ['record', 'booking', 'payment_method'],
      ['record', 'booking', 'paymentMethod'],
    ])?.toLowerCase().trim();
  }

  String? _paymentSourceFromDetails() {
    return _firstDetailPathText(const [
      ['payment_source'],
      ['paymentSource'],
      ['booking', 'payment_source'],
      ['booking', 'paymentSource'],
      ['record', 'payment_source'],
      ['record', 'paymentSource'],
      ['record', 'booking', 'payment_source'],
      ['record', 'booking', 'paymentSource'],
    ])?.toLowerCase().trim();
  }

  bool _methodImpliesPaid(String? method) {
    final m = method?.toLowerCase().trim() ?? '';
    return m == 'cash' || m == 'bancontact' || m == 'qr' || m == 'card';
  }

  Future<Map<String, dynamic>?> _fetchAuthoritativePaymentFields(
    String bookingId,
  ) async {
    Map<String, dynamic> asMap(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    List<dynamic> asList(dynamic value) => value is List ? value : const [];
    try {
      final uri = Uri.parse(
        '$kBookingBaseUrl/bookings/${Uri.encodeComponent(bookingId)}',
      );
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (kAdminToken.trim().isNotEmpty) {
        headers['x-admin-token'] = kAdminToken.trim();
      }
      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));
      Map<String, dynamic>? parsed;
      dynamic decoded;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        decoded = jsonDecode(res.body);
        if (decoded is Map) {
          final root = Map<String, dynamic>.from(decoded);
          parsed = _extractAuthoritativePaymentFields(root);
          if (parsed == null || parsed.isEmpty) {
            for (final list in <List<dynamic>>[
              asList(root['items']),
              asList(asMap(root['data'])['items']),
              asList(root['bookings']),
              asList(asMap(root['data'])['bookings']),
            ]) {
              for (final raw in list) {
                final entry = asMap(raw);
                final entryBookingId =
                    (entry['booking_id'] ??
                            entry['bookingId'] ??
                            entry['id'] ??
                            '')
                        .toString()
                        .trim();
                if (entryBookingId != bookingId) continue;
                parsed = _extractAuthoritativePaymentFields(entry);
                if (parsed != null && parsed.isNotEmpty) break;
              }
              if (parsed != null && parsed.isNotEmpty) break;
            }
          }
        }
      }
      if (parsed != null && parsed.isNotEmpty) return parsed;

      final listUri = Uri.parse(
        '$kBookingBaseUrl/bookings?limit=200&t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final listRes = await http
          .get(listUri, headers: headers)
          .timeout(const Duration(seconds: 12));
      Map<String, dynamic>? listParsed;
      if (listRes.statusCode >= 200 && listRes.statusCode < 300) {
        final listDecoded = jsonDecode(listRes.body);
        if (listDecoded is Map) {
          final root = Map<String, dynamic>.from(listDecoded);
          for (final list in <List<dynamic>>[
            asList(root['items']),
            asList(asMap(root['data'])['items']),
            asList(root['bookings']),
            asList(asMap(root['data'])['bookings']),
          ]) {
            for (final raw in list) {
              final entry = asMap(raw);
              final entryBookingId =
                  (entry['booking_id'] ??
                          entry['bookingId'] ??
                          entry['id'] ??
                          '')
                      .toString()
                      .trim();
              if (entryBookingId != bookingId) continue;
              listParsed = _extractAuthoritativePaymentFields(entry);
              if (listParsed != null && listParsed.isNotEmpty) break;
            }
            if (listParsed != null && listParsed.isNotEmpty) break;
          }
        }
      }
      if (listParsed != null && listParsed.isNotEmpty) return listParsed;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _resolveReceiptPaymentStatus() async {
    final bookingId = (item.bookingId ?? '').trim();
    final historyPaymentStatus = _historyTopLevelPaymentStatus();
    final nestedPaymentStatus = _historyNestedPaymentStatus();

    String? authoritativePaymentStatus;
    String? authoritativePaymentMethod;
    if (bookingId.isNotEmpty) {
      final fields = await _fetchAuthoritativePaymentFields(bookingId);
      if (fields != null && fields.isNotEmpty) {
        _mergePaymentFieldsIntoReceiptDetails(fields);
        authoritativePaymentStatus =
            _mapText(fields, 'payment_status') ??
            _mapText(fields, 'paymentStatus');
        authoritativePaymentMethod =
            _mapText(fields, 'payment_method') ??
            _mapText(fields, 'paymentMethod');
      }
    }

    String? resolved = authoritativePaymentStatus;
    if (resolved != null && resolved.isNotEmpty) {
    } else if (historyPaymentStatus != null &&
        historyPaymentStatus.isNotEmpty) {
      resolved = historyPaymentStatus;
    } else if (nestedPaymentStatus != null && nestedPaymentStatus.isNotEmpty) {
      resolved = nestedPaymentStatus;
    }

    final methodFromDetails =
        authoritativePaymentMethod ?? _paymentMethodFromDetails();
    final sourceFromDetails = _paymentSourceFromDetails();
    final markAsPaidFromMethod =
        _methodImpliesPaid(methodFromDetails) &&
        (sourceFromDetails == null ||
            sourceFromDetails.isEmpty ||
            sourceFromDetails == 'in_car');
    if (!mounted) return;
    setState(() {
      final fromStatus = _paymentStatusFromRaw(resolved);
      _paymentStatus =
          markAsPaidFromMethod && fromStatus != _ReceiptPaymentStatus.paid
          ? _ReceiptPaymentStatus.paid
          : fromStatus;
    });
  }

  String? _cleanContactText(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  dynamic _detailAt(List<String> path) {
    dynamic current = item.bookingDetails;
    for (final key in path) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        current = null;
        break;
      }
    }
    if (current != null) return current;
    return _rawAt(path);
  }

  dynamic _rawAt(List<String> path) {
    dynamic current = item.rawSource;
    for (final key in path) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  String? _firstDetailPathText(List<List<String>> paths) {
    for (final path in paths) {
      final text = _cleanContactText(_detailAt(path));
      if (text != null) return text;
    }
    return null;
  }

  String? _firstDetailText(List<String> keys) {
    for (final key in keys) {
      final text = _detailText(key);
      if (text != null) return text;
    }
    return null;
  }

  double? _detailDouble(String key) {
    final value = item.bookingDetails[key];
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.'));
  }

  double? _receiptTotalAmount() {
    if (_isPlannedReceipt) {
      return _detailDouble('booking_total_eur') ?? item.totalEur;
    }
    return item.totalEur;
  }

  String _moneyText(double? value) {
    if (value == null) return _receiptText('notAvailable');
    return '€ ${value.toStringAsFixed(2)}';
  }

  String _totalText() {
    return _moneyText(_receiptTotalAmount());
  }

  String _kmText() {
    final km = item.kmTotal;
    if (km == null) return _receiptText('notAvailable');
    return '${km.toStringAsFixed(2)} km';
  }

  bool _isPlaceholderRouteLabel(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return true;
    if (text == '-' || text == '—') return true;
    return text.toLowerCase() == _receiptText('currentLocation').toLowerCase();
  }

  ({String from, String to}) _resolvedRouteForPdf() {
    final normalizedFrom = _isPlaceholderRouteLabel(item.origin)
        ? null
        : item.origin.trim();
    final normalizedTo = _isPlaceholderRouteLabel(item.destination)
        ? null
        : item.destination.trim();

    String? pickLabel(List<List<String>> paths) {
      for (final path in paths) {
        final text = _cleanContactText(_detailAt(path));
        if (!_isPlaceholderRouteLabel(text)) return text;
      }
      return null;
    }

    final rawFrom = pickLabel(const [
      ['from'],
      ['pickup'],
      ['pickup_address'],
      ['pickupAddress'],
      ['pickupLocation'],
      ['pickup_location'],
      ['origin'],
      ['start_address'],
      ['startAddress'],
      ['booking', 'from'],
      ['booking', 'pickup'],
      ['booking', 'pickup_address'],
      ['booking', 'pickupAddress'],
      ['record', 'from'],
      ['record', 'booking', 'from'],
      ['record', 'booking', 'pickup'],
      ['payload', 'from'],
      ['payload', 'booking', 'from'],
      ['quote', 'inputs', 'from'],
    ]);
    final rawTo = pickLabel(const [
      ['to'],
      ['destination'],
      ['destination_address'],
      ['destinationAddress'],
      ['dropoff'],
      ['dropoff_address'],
      ['dropoffAddress'],
      ['end_address'],
      ['endAddress'],
      ['booking', 'to'],
      ['booking', 'destination'],
      ['booking', 'destination_address'],
      ['booking', 'destinationAddress'],
      ['record', 'to'],
      ['record', 'booking', 'to'],
      ['record', 'booking', 'destination'],
      ['payload', 'to'],
      ['payload', 'booking', 'to'],
      ['quote', 'inputs', 'to'],
    ]);

    final from = normalizedFrom ?? rawFrom ?? _receiptText('currentLocation');
    final to = normalizedTo ?? rawTo ?? '-';
    final source = (normalizedFrom != null || normalizedTo != null)
        ? 'normalized'
        : ((rawFrom != null || rawTo != null) ? 'raw' : 'fallback');
    debugPrint(
      '[PDF][ROUTE] fromFound=${from != _receiptText('currentLocation')} toFound=${to != '-'} source=$source',
    );
    return (from: from, to: to);
  }

  ({
    String? name,
    String? phoneRaw,
    String? email,
    List<String> keys,
    String source,
  })
  _resolvePdfContact() {
    String? pick(
      List<List<String>> paths,
      List<String> usedKeys, {
      bool email = false,
    }) {
      for (final path in paths) {
        final text = _cleanContactText(_detailAt(path));
        if (text == null || text.isEmpty) continue;
        final normalized = email ? _validEmail(text) : text;
        if (normalized == null || normalized.isEmpty) continue;
        usedKeys.add(path.join('.'));
        return normalized;
      }
      return null;
    }

    final keys = <String>[];
    final normalizedName = _cleanContactText(item.customerName);
    final normalizedPhone = _cleanContactText(item.customerPhone);
    final normalizedEmail = _validEmail(item.customerEmail);
    if (normalizedName != null) keys.add('normalized.customerName');
    if (normalizedPhone != null) keys.add('normalized.customerPhone');
    if (normalizedEmail != null) keys.add('normalized.customerEmail');

    final hasNormalized =
        normalizedName != null ||
        normalizedPhone != null ||
        normalizedEmail != null;
    if (hasNormalized) {
      return (
        name: normalizedName,
        phoneRaw: normalizedPhone,
        email: normalizedEmail,
        keys: keys,
        source: 'normalized',
      );
    }

    final name = pick(const [
      ['customer', 'name'],
      ['customer_name'],
      ['customerName'],
      ['custName'],
      ['name'],
      ['booking', 'customer', 'name'],
      ['booking', 'customer_name'],
      ['booking', 'customerName'],
      ['booking', 'custName'],
      ['booking', 'name'],
      ['record', 'customer_name'],
      ['record', 'booking', 'customer_name'],
      ['record', 'booking', 'customerName'],
      ['payload', 'customer_name'],
      ['payload', 'booking', 'customer_name'],
      ['record', 'payload', 'customer_name'],
      ['record', 'payload', 'customerName'],
      ['record', 'payload', 'custName'],
      ['record', 'payload', 'name'],
      ['record', 'payload', 'booking', 'customer_name'],
      ['record', 'payload', 'booking', 'customerName'],
      ['record', 'payload', 'booking', 'custName'],
      ['record', 'payload', 'booking', 'name'],
    ], keys);

    final phoneRaw = pick(const [
      ['customer', 'phone'],
      ['customer_phone'],
      ['customerPhone'],
      ['custPhone'],
      ['phone'],
      ['tel'],
      ['mobile'],
      ['booking', 'customer', 'phone'],
      ['booking', 'customer_phone'],
      ['booking', 'customerPhone'],
      ['booking', 'custPhone'],
      ['booking', 'phone'],
      ['booking', 'tel'],
      ['booking', 'mobile'],
      ['record', 'customer_phone'],
      ['record', 'booking', 'customer_phone'],
      ['record', 'booking', 'customerPhone'],
      ['record', 'booking', 'custPhone'],
      ['payload', 'customer_phone'],
      ['payload', 'booking', 'customer_phone'],
      ['record', 'payload', 'customer_phone'],
      ['record', 'payload', 'customerPhone'],
      ['record', 'payload', 'custPhone'],
      ['record', 'payload', 'phone'],
      ['record', 'payload', 'tel'],
      ['record', 'payload', 'mobile'],
      ['record', 'payload', 'booking', 'customer_phone'],
      ['record', 'payload', 'booking', 'customerPhone'],
      ['record', 'payload', 'booking', 'custPhone'],
      ['record', 'payload', 'booking', 'phone'],
    ], keys);

    final email = pick(
      const [
        ['customer', 'email'],
        ['customer_email'],
        ['customerEmail'],
        ['custEmail'],
        ['email'],
        ['invoice_email'],
        ['invoiceEmail'],
        ['booking', 'customer', 'email'],
        ['booking', 'customer_email'],
        ['booking', 'customerEmail'],
        ['booking', 'custEmail'],
        ['booking', 'email'],
        ['booking', 'invoice_email'],
        ['booking', 'invoiceEmail'],
        ['record', 'customer_email'],
        ['record', 'booking', 'customer_email'],
        ['record', 'booking', 'customerEmail'],
        ['record', 'booking', 'custEmail'],
        ['payload', 'customer_email'],
        ['payload', 'booking', 'customer_email'],
        ['record', 'payload', 'customer_email'],
        ['record', 'payload', 'customerEmail'],
        ['record', 'payload', 'custEmail'],
        ['record', 'payload', 'email'],
        ['record', 'payload', 'invoice_email'],
        ['record', 'payload', 'invoiceEmail'],
        ['record', 'payload', 'booking', 'customer_email'],
        ['record', 'payload', 'booking', 'customerEmail'],
        ['record', 'payload', 'booking', 'custEmail'],
        ['record', 'payload', 'booking', 'email'],
        ['record', 'payload', 'booking', 'invoice_email'],
        ['record', 'payload', 'booking', 'invoiceEmail'],
      ],
      keys,
      email: true,
    );

    final hasRaw = name != null || phoneRaw != null || email != null;
    return (
      name: name,
      phoneRaw: phoneRaw,
      email: email,
      keys: keys,
      source: hasRaw ? 'raw' : 'none',
    );
  }

  void _logPdfContactResolution() {
    final resolved = _resolvePdfContact();
    final keyList = resolved.keys.join(',');
    debugPrint(
      '[PDF][CONTACT] emailFound=${resolved.email != null} phoneFound=${resolved.phoneRaw != null} source=${resolved.source} keys=$keyList',
    );
  }

  String? get _customerName => _resolvePdfContact().name;

  String? get _customerPhoneRaw => _resolvePdfContact().phoneRaw;

  String? get _customerEmail => _resolvePdfContact().email;

  String? get _customerCountryContext =>
      _firstDetailText([
        'phone_country_code',
        'phoneCountryCode',
        'dial_code',
        'dialCode',
        'customer_country',
        'customerCountry',
        'country',
        'countryCode',
        'country_iso',
        'countryIso',
        'locale',
        'language',
      ]) ??
      _tenantDefaultCountryIso();

  String? _tenantDefaultCountryIso() {
    // Tenant-level fallback only. Future white-label tenants should move this into tenant config.
    if (kTenantId.toLowerCase().trim() == 'fluxidi') return 'BE';
    return null;
  }

  String? get _customerPhoneE164 => _normalizePhoneForWhatsApp(
    _customerPhoneRaw,
    countryContext: _customerCountryContext,
  );

  bool get _hasAnyRawCustomerContact =>
      (_customerName?.trim().isNotEmpty ?? false) ||
      (_customerPhoneRaw?.trim().isNotEmpty ?? false) ||
      (_customerEmail?.trim().isNotEmpty ?? false);

  String _maskEmailForLog(String? value) {
    final email = value?.trim();
    if (email == null || email.isEmpty) return '-';
    final at = email.indexOf('@');
    if (at <= 0) return '***';
    final first = email.substring(0, 1);
    return '$first***${email.substring(at)}';
  }

  String _maskPhoneForLog(String? value) {
    final digits = value?.replaceAll(RegExp(r'\D'), '') ?? '';
    if (digits.isEmpty) return '-';
    final suffix = digits.length <= 2
        ? digits
        : digits.substring(digits.length - 2);
    return '***$suffix';
  }

  void _debugReceiptContactState(String label, {String? emailOverride}) {
    if (!kDebugMode) return;
    debugPrint(
      '[RITBON][CONTACT][$label] '
      'nameFound=${_customerName != null} '
      'emailFound=${(emailOverride ?? _customerEmail) != null} '
      'phoneFound=${_customerPhoneE164 != null} '
      'keys=${item.bookingDetails.keys.where((key) => key.toLowerCase().contains('customer') || key.toLowerCase().contains('phone') || key.toLowerCase().contains('email')).join(',')}',
    );
  }

  String? _validEmail(String? value) {
    final email = value?.trim();
    if (email == null || email.isEmpty) return null;
    final at = email.indexOf('@');
    if (at <= 0 || at >= email.length - 1) return null;
    final dotAfterAt = email.indexOf('.', at + 1);
    if (dotAfterAt <= at + 1 || dotAfterAt >= email.length - 1) return null;
    if (email.contains(RegExp(r'\s'))) return null;
    return email;
  }

  // MVP E.164-like normalizer. Replace/enhance with libphonenumber-style validation later.
  String? _normalizePhoneForWhatsApp(String? raw, {String? countryContext}) {
    final input = raw?.trim();
    if (input == null || input.isEmpty) return null;
    var cleaned = input.replaceAll(RegExp(r'[\s\-\(\)\/\.]'), '');
    if (cleaned.startsWith('00')) cleaned = '+${cleaned.substring(2)}';
    if (cleaned.startsWith('+')) {
      final digits = cleaned.substring(1).replaceAll(RegExp(r'\D'), '');
      if (digits.length < 8 || digits.length > 15) return null;
      return '+$digits';
    }

    final digits = cleaned.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) return null;
    final iso = _countryIsoFromContext(countryContext);
    if (iso == null) return null;
    final dial = _dialCodeForIso(iso);
    if (dial == null) return null;

    String? national;
    switch (iso) {
      case 'BE':
      case 'NL':
      case 'FR':
      case 'DE':
      case 'GB':
      case 'CH':
      case 'AT':
      case 'IE':
        if (!digits.startsWith('0')) return null;
        national = digits.replaceFirst(RegExp(r'^0+'), '');
        break;
      case 'ES':
        if (digits.length != 9 || digits.startsWith('0')) return null;
        national = digits;
        break;
      case 'US':
      case 'CA':
        if (digits.length != 10) return null;
        national = digits;
        break;
      case 'LU':
        if (digits.length < 6 || digits.length > 9) return null;
        national = digits.replaceFirst(RegExp(r'^0+'), '');
        break;
      case 'IT':
      case 'PT':
        if (digits.length < 8 || digits.length > 10) return null;
        national = digits.replaceFirst(RegExp(r'^0+'), '');
        break;
      default:
        return null;
    }
    final normalized = '$dial$national';
    final normalizedDigits = normalized.replaceAll(RegExp(r'\D'), '');
    if (normalizedDigits.length < 8 || normalizedDigits.length > 15)
      return null;
    return normalized;
  }

  String? _countryIsoFromContext(String? context) {
    final raw = context?.trim();
    if (raw == null || raw.isEmpty) return null;
    final lower = raw.toLowerCase();
    if (lower.startsWith('+')) return _isoFromDialCode(lower);
    if (RegExp(r'^\d+$').hasMatch(lower)) return _isoFromDialCode('+$lower');
    final localePart = lower.contains('_') || lower.contains('-')
        ? lower.split(RegExp(r'[_-]')).last
        : lower;
    final c = localePart
        .replaceAll('ë', 'e')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ï', 'i')
        .replaceAll('ä', 'a')
        .replaceAll('ö', 'o')
        .replaceAll('ü', 'u')
        .replaceAll('ç', 'c')
        .trim();
    const aliases = <String, String>{
      'be': 'BE',
      'belgium': 'BE',
      'belgie': 'BE',
      'belgique': 'BE',
      'belgien': 'BE',
      'nl': 'NL',
      'netherlands': 'NL',
      'nederland': 'NL',
      'pays bas': 'NL',
      'fr': 'FR',
      'france': 'FR',
      'frankrijk': 'FR',
      'es': 'ES',
      'spain': 'ES',
      'spanje': 'ES',
      'espagne': 'ES',
      'espana': 'ES',
      'us': 'US',
      'usa': 'US',
      'united states': 'US',
      'america': 'US',
      'ca': 'CA',
      'canada': 'CA',
      'gb': 'GB',
      'uk': 'GB',
      'united kingdom': 'GB',
      'great britain': 'GB',
      'de': 'DE',
      'germany': 'DE',
      'duitsland': 'DE',
      'allemagne': 'DE',
      'deutschland': 'DE',
      'lu': 'LU',
      'luxembourg': 'LU',
      'luxemburg': 'LU',
      'it': 'IT',
      'italy': 'IT',
      'italie': 'IT',
      'italia': 'IT',
      'pt': 'PT',
      'portugal': 'PT',
      'ch': 'CH',
      'switzerland': 'CH',
      'suisse': 'CH',
      'zwitserland': 'CH',
      'at': 'AT',
      'austria': 'AT',
      'oostenrijk': 'AT',
      'autriche': 'AT',
      'ie': 'IE',
      'ireland': 'IE',
    };
    return aliases[c] ?? aliases[lower];
  }

  String? _isoFromDialCode(String dial) {
    const map = <String, String>{
      '+32': 'BE',
      '+31': 'NL',
      '+33': 'FR',
      '+34': 'ES',
      '+1': 'US',
      '+44': 'GB',
      '+49': 'DE',
      '+352': 'LU',
      '+39': 'IT',
      '+351': 'PT',
      '+41': 'CH',
      '+43': 'AT',
      '+353': 'IE',
    };
    return map[dial];
  }

  String? _dialCodeForIso(String iso) {
    const map = <String, String>{
      'BE': '+32',
      'NL': '+31',
      'FR': '+33',
      'ES': '+34',
      'US': '+1',
      'CA': '+1',
      'GB': '+44',
      'DE': '+49',
      'LU': '+352',
      'IT': '+39',
      'PT': '+351',
      'CH': '+41',
      'AT': '+43',
      'IE': '+353',
    };
    return map[iso];
  }

  String? _displayToken(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    final normalized = text.replaceAll('_', ' ').replaceAll('-', ' ');
    return normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) => part.length == 1
              ? part.toUpperCase()
              : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _displayServiceToken(String? value) {
    final raw = value?.trim() ?? '';
    final normalized = raw
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_')
        .trim();
    if (normalized == 'passenger' ||
        normalized == 'personenvervoer' ||
        normalized == 'passenger_transport') {
      return _receiptText('passengerTransport');
    }
    if (normalized == 'business' || normalized == 'zakelijk') {
      return _receiptText('businessRide');
    }
    if (normalized == 'airport' ||
        normalized == 'luchthaven' ||
        normalized == 'airport_transfer') {
      return _receiptText('airportTransfer');
    }
    return _displayToken(value) ?? '—';
  }

  String _displayTierToken(String? value) {
    final raw = value?.trim() ?? '';
    final normalized = raw.toLowerCase().replaceAll('-', '_').trim();
    if (normalized == 'comfort') return _receiptText('tierComfort');
    if (normalized == 'private') return _receiptText('tierPrivate');
    if (normalized == 'premium') return _receiptText('tierPremium');
    return _displayToken(value) ?? '—';
  }

  String? _displayExtraValue(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      final token = _displayToken(raw);
      return token == null || token == '—' ? null : token;
    }
    if (raw is List) {
      final values = raw
          .map(_displayExtraValue)
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .toList(growable: false);
      if (values.isEmpty) return null;
      return values.join(', ');
    }
    if (raw is Map) {
      final values = <String>[];
      raw.forEach((key, value) {
        final include =
            value == true ||
            value == 1 ||
            value?.toString().toLowerCase().trim() == 'true' ||
            value?.toString().trim() == '1';
        if (!include) return;
        final label = _displayToken(key.toString());
        if (label != null && label != '—') values.add(label);
      });
      if (values.isEmpty) return null;
      return values.join(', ');
    }
    return null;
  }

  String? _plannedExtrasText() {
    const paths = <List<String>>[
      ['extras'],
      ['extra_service'],
      ['extra_service_key'],
      ['selected_options'],
      ['premium_options'],
      ['booking', 'extras'],
      ['booking', 'extra_service'],
      ['booking', 'extra_service_key'],
      ['booking', 'selected_options'],
      ['booking', 'premium_options'],
      ['record', 'payload', 'extras'],
      ['record', 'payload', 'extra_service'],
      ['record', 'payload', 'extra_service_key'],
      ['record', 'payload', 'selected_options'],
      ['record', 'payload', 'premium_options'],
      ['record', 'payload', 'booking', 'extras'],
      ['record', 'payload', 'booking', 'extra_service'],
      ['record', 'payload', 'booking', 'extra_service_key'],
      ['record', 'payload', 'booking', 'selected_options'],
      ['record', 'payload', 'booking', 'premium_options'],
    ];
    for (final path in paths) {
      final text = _displayExtraValue(_detailAt(path));
      if (text != null && text.trim().isNotEmpty) return text;
    }
    return null;
  }

  bool _sameMoney(double? a, double? b) {
    if (a == null || b == null) return false;
    return (a - b).abs() < 0.005;
  }

  bool get _hasReturnPriceSplit {
    final outbound = _detailDouble('outbound_price_eur');
    final ret = _detailDouble('return_price_eur');
    return outbound != null &&
        ret != null &&
        ret > 0 &&
        !_sameMoney(outbound, ret);
  }

  bool get _hasReturnBookingInfo =>
      _detailText('return_scheduled_pickup_at') != null ||
      _detailText('return_route') != null ||
      _hasReturnPriceSplit ||
      (item.bookingId ?? '').endsWith('-R');

  List<Widget> _plannedPriceRows() {
    final package = _detailDouble('booking_total_eur');
    final segment = _detailDouble('segment_price_eur');
    final outbound = _detailDouble('outbound_price_eur');
    final ret = _detailDouble('return_price_eur');
    final rows = <Widget>[];

    if (_hasReturnBookingInfo && (outbound != null || ret != null)) {
      if (package != null &&
          !_sameMoney(package, outbound) &&
          !_sameMoney(package, ret)) {
        rows.add(
          _receiptRow(_receiptText('packagePrice'), _moneyText(package)),
        );
      }
      if (outbound != null) {
        rows.add(
          _receiptRow(_receiptText('outboundPrice'), _moneyText(outbound)),
        );
      }
      if (ret != null && !_sameMoney(ret, outbound)) {
        rows.add(_receiptRow(_receiptText('returnPrice'), _moneyText(ret)));
      }
      if (segment != null &&
          !_sameMoney(segment, package) &&
          !_sameMoney(segment, outbound) &&
          !_sameMoney(segment, ret)) {
        rows.add(_receiptRow(_receiptText('ridePrice'), _moneyText(segment)));
      }
      return rows;
    }

    final single = segment ?? outbound ?? package;
    if (single != null) {
      rows.add(_receiptRow(_receiptText('fixedPrice'), _moneyText(single)));
    }
    return rows;
  }

  String _shareText() {
    return _receiptCustomerMessage();
  }

  String get _customerReference {
    final direct = _firstDetailPathText(const [
      ['public_reference'],
      ['publicReference'],
      ['receipt_reference'],
      ['receiptReference'],
      ['booking', 'public_reference'],
      ['booking', 'publicReference'],
      ['booking', 'receipt_reference'],
      ['booking', 'receiptReference'],
      ['booking', 'bookingId'],
      ['booking_id'],
      ['bookingId'],
      ['id'],
    ]);
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();
    final bookingId = (item.bookingId ?? '').trim();
    if (bookingId.isNotEmpty) return bookingId;
    final receiptNumber = item.receiptNumber.trim();
    return receiptNumber.isNotEmpty ? receiptNumber : '—';
  }

  String _localizedPaymentMethodValue(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return _receiptText('notAvailable');
    final normalized = value
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    switch (normalized) {
      case 'cash':
        return _tr(nl: 'Cash', en: 'Cash', fr: 'Espèces', es: 'Efectivo');
      case 'bancontact':
        return _tr(
          nl: 'Bancontact',
          en: 'Bancontact',
          fr: 'Bancontact',
          es: 'Bancontact',
        );
      case 'card':
        return _tr(nl: 'Kaart', en: 'Card', fr: 'Carte', es: 'Tarjeta');
      case 'qr':
      case 'qr_code':
        return _tr(
          nl: 'QR-code',
          en: 'QR code',
          fr: 'Code QR',
          es: 'Código QR',
        );
      case 'mollie':
        return _tr(
          nl: 'Online betaling',
          en: 'Online payment',
          fr: 'Paiement en ligne',
          es: 'Pago en línea',
        );
      default:
        return _displayToken(value) ?? value.replaceAll('_', ' ');
    }
  }

  String _localizedPaymentSourceValue(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return _receiptText('notAvailable');
    final normalized = value
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    switch (normalized) {
      case 'in_car':
        return _tr(
          nl: 'In de wagen',
          en: 'In vehicle',
          fr: 'Dans le véhicule',
          es: 'En el vehículo',
        );
      case 'payment_link':
        return _tr(
          nl: 'Betaallink',
          en: 'Payment link',
          fr: 'Lien de paiement',
          es: 'Enlace de pago',
        );
      case 'mollie':
        return _tr(
          nl: 'Online betaling',
          en: 'Online payment',
          fr: 'Paiement en ligne',
          es: 'Pago en línea',
        );
      default:
        return _displayToken(value) ?? value.replaceAll('_', ' ');
    }
  }

  String _receiptCustomerMessage() {
    final route = _resolvedRouteForPdf();
    final lines = <String>[
      '${_receiptText('receiptFrom')} $kCompanyName',
      '${_receiptText('type')}: ${item.kindLabel}',
      '${_receiptText('reference')}: $_customerReference',
      '${_receiptText('from')}: ${route.from}',
      '${_receiptText('to')}: ${route.to}',
      if (_detailText('scheduled_pickup_at') != null)
        '${_receiptText('scheduledPickup')}: ${_formatDate(_detailText('scheduled_pickup_at'))}',
      if (item.startedAt?.trim().isNotEmpty ?? false)
        '${_receiptText('startTime')}: ${_formatDate(item.startedAt)}',
      if (item.stoppedAt?.trim().isNotEmpty ?? false)
        '${_receiptText('endTime')}: ${_formatDate(item.stoppedAt)}',
      '${_receiptText('distance')}: ${_kmText()}',
      '${_receiptText('total')}: ${_totalText()}',
      '${_receiptText('paymentStatus')}: ${_paymentStatusText()}',
      '',
      _receiptText('thanksRide'),
    ];
    return lines.join('\n');
  }

  String _paymentStatusText() {
    switch (_paymentStatus) {
      case _ReceiptPaymentStatus.pending:
        return _receiptText('unpaid');
      case _ReceiptPaymentStatus.sent:
        return _receiptText('paymentSent');
      case _ReceiptPaymentStatus.paid:
        return _receiptText('paid');
    }
  }

  String _paymentLink() {
    final amount = _receiptTotalAmount() ?? 0.0;
    return Uri(
      scheme: 'fluxidi',
      host: 'pay',
      queryParameters: <String, String>{
        'ref': _customerReference,
        'amount': amount.toStringAsFixed(2),
        'currency': item.currency,
        'memo':
            '$kCompanyName ${_receiptText('receiptTitle')} $_customerReference',
      },
    ).toString();
  }

  void _markPaymentRequestSent() {
    if (_paymentStatus == _ReceiptPaymentStatus.pending) {
      setState(() => _paymentStatus = _ReceiptPaymentStatus.sent);
    }
  }

  Future<void> _copyPaymentLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _paymentLink()));
    _markPaymentRequestSent();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_receiptText('paymentLinkCopied'))));
  }

  Future<void> _openWhatsApp(
    BuildContext context, {
    required String phoneE164,
    required String message,
  }) async {
    final digits = phoneE164.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.https('wa.me', '/$digits', <String, String>{
      'text': message,
    });
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('whatsappOpenFailed'))),
      );
    }
  }

  Future<void> _openEmail(
    BuildContext context, {
    required String email,
    required String subject,
    required String body,
  }) async {
    final recipient = email.trim();
    final encodedSubject = Uri.encodeComponent(subject);
    final encodedBody = Uri.encodeComponent(body);
    final uri = Uri.parse(
      recipient.isNotEmpty
          ? 'mailto:${Uri.encodeComponent(recipient)}?subject=$encodedSubject&body=$encodedBody'
          : 'mailto:?subject=$encodedSubject&body=$encodedBody',
    );
    _debugReceiptContactState(
      'email_open',
      emailOverride: recipient.isNotEmpty ? recipient : null,
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_receiptText('emailOpenFailed'))));
    }
  }

  Future<void> _sendReceiptWhatsApp(BuildContext context) async {
    final phone = _customerPhoneE164;
    final contactSource = _resolvePdfContact().source;
    debugPrint(
      '[PDF][ACTION][WHATSAPP_TEXT] phoneFound=${phone != null} source=$contactSource',
    );
    if (phone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('noValidWhatsappPhone'))),
      );
      return;
    }
    final message = _tr(
      nl: 'Beste klant, uw betaalbewijs/ritbon is klaar. Ik stuur de PDF zo meteen door.',
      en: 'Dear customer, your ride receipt is ready. I will send the PDF shortly.',
      fr: 'Cher client, votre reçu de course est prêt. Je vais envoyer le PDF dans un instant.',
      es: 'Estimado cliente, su comprobante de viaje está listo. Enviaré el PDF en un momento.',
    );
    await _openWhatsApp(context, phoneE164: phone, message: message);
  }

  Future<void> _emailReceiptGeneric(BuildContext context) async {
    await _openEmail(
      context,
      email: _customerEmail ?? '',
      subject: _receiptText('receiptEmailSubject'),
      body: _receiptCustomerMessage(),
    );
  }

  bool _toBoolFlag(String? value) {
    final normalized = value?.toLowerCase().trim() ?? '';
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'ja';
  }

  bool get _isBusinessDocument {
    final invoiceRequested = _toBoolFlag(
      _firstDetailPathText(const [
        ['invoice_requested'],
        ['invoiceRequested'],
        ['booking', 'invoice_requested'],
        ['booking', 'invoiceRequested'],
        ['record', 'booking', 'invoice_requested'],
        ['record', 'booking', 'invoiceRequested'],
      ]),
    );
    final customerCompany = _firstDetailPathText(const [
      ['company_name'],
      ['companyName'],
      ['customer_company'],
      ['customerCompany'],
      ['booking', 'company_name'],
      ['booking', 'companyName'],
      ['record', 'booking', 'company_name'],
      ['record', 'booking', 'companyName'],
    ]);
    final customerVat = _firstDetailPathText(const [
      ['vat_number'],
      ['vatNumber'],
      ['customer_vat'],
      ['customerVat'],
      ['booking', 'vat_number'],
      ['booking', 'vatNumber'],
      ['record', 'booking', 'vat_number'],
      ['record', 'booking', 'vatNumber'],
    ]);
    return invoiceRequested ||
        (customerCompany != null && customerCompany.trim().isNotEmpty) ||
        (customerVat != null && customerVat.trim().isNotEmpty);
  }

  double _resolvedVatRate() {
    final settingsVatRate = businessSettingsNotifier.value.pricingVatRate;
    final candidates = <double?>[
      _detailDouble('vat_rate'),
      _detailDouble('vatRate'),
      _detailDouble('booking_vat_rate'),
      _detailDouble('bookingVatRate'),
    ];
    for (final candidate in candidates) {
      if (candidate == null || !candidate.isFinite) continue;
      if (candidate > 1.0) return candidate / 100.0;
      if (candidate >= 0.0) return candidate;
    }
    return settingsVatRate.clamp(0.0, 1.0);
  }

  ({double subtotal, double vatAmount, double total, double vatRate})
  _resolvedReceiptAmounts() {
    final vatRate = _resolvedVatRate();
    final total =
        _receiptTotalAmount() ??
        _detailDouble('total') ??
        _detailDouble('booking_total_eur') ??
        0.0;
    final subtotalCandidate =
        _detailDouble('subtotal_ex_vat') ??
        _detailDouble('subtotalExVat') ??
        _detailDouble('price_ex_vat') ??
        _detailDouble('priceExVat');
    final vatAmountCandidate =
        _detailDouble('vat_amount') ??
        _detailDouble('vatAmount') ??
        _detailDouble('price_vat') ??
        _detailDouble('priceVat');

    final subtotal =
        subtotalCandidate ?? (vatRate > 0 ? (total / (1.0 + vatRate)) : total);
    final vatAmount = vatAmountCandidate ?? (total - subtotal);
    return (
      subtotal: subtotal.isFinite ? subtotal : 0.0,
      vatAmount: vatAmount.isFinite ? vatAmount : 0.0,
      total: total.isFinite ? total : 0.0,
      vatRate: vatRate.isFinite ? vatRate : 0.0,
    );
  }

  String _sanitizeFilePart(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return cleaned.isEmpty ? 'receipt' : cleaned;
  }

  Future<Uint8List?> _loadReceiptLogoBytes(String? preferredPath) async {
    final candidates = <String>[
      if (preferredPath != null && preferredPath.trim().isNotEmpty)
        preferredPath.trim(),
      kFluxidiLogoAsset,
    ];
    for (final candidate in candidates) {
      try {
        if (candidate.startsWith('assets/')) {
          final data = await rootBundle.load(candidate);
          return data.buffer.asUint8List();
        }
        final f = File(candidate);
        if (await f.exists()) {
          return await f.readAsBytes();
        }
      } catch (_) {
        // Ignore and try next candidate.
      }
    }
    return null;
  }

  Future<Map<String, String>> _buildSellerProfile() async {
    final settings = businessSettingsNotifier.value;
    BackendBusinessProfile? backendProfile;
    try {
      backendProfile = await fetchBackendBusinessProfile();
    } catch (_) {
      backendProfile = null;
    }

    final profile = backendProfile ?? BackendBusinessProfile.defaults();
    final postcodeCity = [
      profile.postcode.trim(),
      profile.city.trim(),
    ].where((e) => e.isNotEmpty).join(' ');
    final address = [
      profile.address.trim().isNotEmpty
          ? profile.address.trim()
          : settings.address.trim(),
      if (postcodeCity.isNotEmpty) postcodeCity,
      if (profile.country.trim().isNotEmpty) profile.country.trim(),
    ].where((e) => e.isNotEmpty).join('\n');

    final companyName = profile.companyName.trim().isNotEmpty
        ? profile.companyName.trim()
        : settings.companyName.trim().isNotEmpty
        ? settings.companyName.trim()
        : kCompanyName;
    final legalName = profile.legalName.trim().isNotEmpty
        ? profile.legalName.trim()
        : companyName;
    final profileJson = profile.toJson();
    String localizedFooterFromProfile(AppLanguage lang) {
      final localized = switch (lang) {
        AppLanguage.en =>
          (profileJson['invoiceReceiptFooterTextEn'] ?? '').toString().trim(),
        AppLanguage.fr =>
          (profileJson['invoiceReceiptFooterTextFr'] ?? '').toString().trim(),
        AppLanguage.es =>
          (profileJson['invoiceReceiptFooterTextEs'] ?? '').toString().trim(),
        _ =>
          (profileJson['invoiceReceiptFooterTextNl'] ?? '').toString().trim(),
      };
      return localized;
    }

    final hasAnyLocalizedFooter =
        (profileJson['invoiceReceiptFooterTextNl'] ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        (profileJson['invoiceReceiptFooterTextEn'] ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        (profileJson['invoiceReceiptFooterTextFr'] ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        (profileJson['invoiceReceiptFooterTextEs'] ?? '')
            .toString()
            .trim()
            .isNotEmpty;
    final appLang = appConfig.currentLanguage;
    final localizedFooter = localizedFooterFromProfile(appLang);
    final legacyFooter = profile.invoiceReceiptFooterText.trim();
    final footerText = localizedFooter.isNotEmpty
        ? localizedFooter
        : (legacyFooter.isNotEmpty &&
              (appLang == AppLanguage.nl || !hasAnyLocalizedFooter))
        ? legacyFooter
        : _receiptText('pdfFooterDefault');

    return <String, String>{
      'companyName': companyName,
      'legalName': legalName,
      'address': address,
      'vatNumber': profile.vatNumber.trim().isNotEmpty
          ? profile.vatNumber.trim()
          : settings.vatCompanyNumber.trim(),
      'phone': profile.phone.trim().isNotEmpty
          ? profile.phone.trim()
          : settings.supportPhone.trim(),
      'email': profile.email.trim().isNotEmpty
          ? profile.email.trim()
          : settings.supportEmail.trim(),
      'website': profile.website.trim(),
      'footer': footerText,
      'logoPath': settings.logoAssetPath.trim(),
    };
  }

  pw.Widget _pdfInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 140,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }

  Future<_ReceiptPdfBundle?> _buildReceiptPdfBundle(
    BuildContext context,
  ) async {
    try {
      _logPdfContactResolution();
      final route = _resolvedRouteForPdf();
      final seller = await _buildSellerProfile();
      final logoBytes = await _loadReceiptLogoBytes(seller['logoPath']);
      final doc = pw.Document();
      final baseFont = await PdfGoogleFonts.notoSansRegular();
      final boldFont = await PdfGoogleFonts.notoSansBold();
      final amounts = _resolvedReceiptAmounts();
      final paymentMethod = _localizedPaymentMethodValue(
        _paymentMethodFromDetails(),
      );
      final paymentSource = _localizedPaymentSourceValue(
        _paymentSourceFromDetails(),
      );
      final rideDateText = _detailText('scheduled_pickup_at') != null
          ? _formatDate(_detailText('scheduled_pickup_at'))
          : _formatDate(item.startedAt);
      final serviceText = _displayServiceToken(_detailText('service_type'));
      final tierText = _displayTierToken(_detailText('tier'));
      final durationText =
          _minutesText('duration_route_min') ??
          _minutesText('route_minutes') ??
          _receiptText('notAvailable');
      final documentTitle = _isBusinessDocument
          ? _receiptText('invoiceLabel')
          : _receiptText('paymentReceiptLabel');
      final footerText = seller['footer']?.trim().isNotEmpty == true
          ? seller['footer']!.trim()
          : _receiptText('pdfFooterDefault');

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (pw.Context pdfContext) => [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (logoBytes != null)
                  pw.Container(
                    width: 82,
                    height: 82,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                    ),
                    child: pw.Image(
                      pw.MemoryImage(logoBytes),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        seller['companyName'] ?? kCompanyName,
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          font: boldFont,
                        ),
                        textAlign: pw.TextAlign.right,
                      ),
                      if ((seller['legalName'] ?? '').trim().isNotEmpty &&
                          seller['legalName'] != seller['companyName'])
                        pw.Text(
                          seller['legalName']!,
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['address'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          seller['address']!,
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['vatNumber'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyVat')}: ${seller['vatNumber']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['phone'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyPhone')}: ${seller['phone']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['email'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyEmail')}: ${seller['email']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['website'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyWebsite')}: ${seller['website']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              documentTitle,
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                font: boldFont,
              ),
            ),
            pw.SizedBox(height: 10),
            _pdfInfoRow(_receiptText('reference'), _customerReference),
            _pdfInfoRow(_receiptText('date'), rideDateText),
            _pdfInfoRow(_receiptText('type'), item.kindLabel),
            _pdfInfoRow(_receiptText('service'), serviceText),
            _pdfInfoRow(_receiptText('tier'), tierText),
            _pdfInfoRow(_receiptText('from'), route.from),
            _pdfInfoRow(_receiptText('to'), route.to),
            _pdfInfoRow(_receiptText('distance'), _kmText()),
            _pdfInfoRow(_receiptText('duration'), durationText),
            pw.SizedBox(height: 12),
            pw.Text(
              _receiptText('customerDetails'),
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                font: boldFont,
              ),
            ),
            pw.SizedBox(height: 6),
            _pdfInfoRow(
              _receiptText('customerName'),
              _customerName ?? _receiptText('notAvailable'),
            ),
            _pdfInfoRow(
              _receiptText('customerEmail'),
              _customerEmail ?? _receiptText('notAvailable'),
            ),
            _pdfInfoRow(
              _receiptText('customerPhone'),
              _customerPhoneRaw ?? _receiptText('notAvailable'),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              _receiptText('paymentActions'),
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                font: boldFont,
              ),
            ),
            pw.SizedBox(height: 6),
            _pdfInfoRow(_receiptText('paymentStatus'), _paymentStatusText()),
            _pdfInfoRow(_receiptText('paymentMethod'), paymentMethod),
            _pdfInfoRow(_receiptText('paymentSource'), paymentSource),
            pw.Divider(color: PdfColors.grey400),
            _pdfInfoRow(
              _receiptText('subtotalExVat'),
              '€ ${amounts.subtotal.toStringAsFixed(2)}',
            ),
            _pdfInfoRow(
              '${_receiptText('vatAmount')} (${(amounts.vatRate * 100).toStringAsFixed(0)}%)',
              '€ ${amounts.vatAmount.toStringAsFixed(2)}',
            ),
            _pdfInfoRow(
              _receiptText('total'),
              '€ ${amounts.total.toStringAsFixed(2)}',
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              footerText,
              style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
            ),
          ],
          theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
        ),
      );

      final bytes = await doc.save();
      final tempDir = await getTemporaryDirectory();
      final receiptsDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}fluxidi_receipts',
      );
      if (!await receiptsDir.exists()) {
        await receiptsDir.create(recursive: true);
      }
      final fileName = _sanitizeFilePart(_customerReference);
      final file = File(
        '${receiptsDir.path}${Platform.pathSeparator}$fileName.pdf',
      );
      await file.writeAsBytes(bytes, flush: true);
      return _ReceiptPdfBundle(bytes: bytes, file: file);
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('pdfGenerationFailed'))),
        );
      }
      return null;
    }
  }

  Future<void> _viewReceiptPdf(BuildContext context) async {
    final bundle = await _buildReceiptPdfBundle(context);
    if (bundle == null) {
      if (!mounted) return;
      await _shareReceipt(this.context);
      return;
    }
    if (!widget.showReceiptUi) {
      debugPrint('[PDF][ACTION][CUSTOMER_DIRECT_VIEW] hasPdf=true');
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ReceiptPdfPreviewPage(
          title: _receiptText('viewPdf'),
          bytes: bundle.bytes,
        ),
      ),
    );
  }

  Future<void> _shareReceiptPdf(BuildContext context) async {
    final bundle = await _buildReceiptPdfBundle(context);
    if (bundle == null) {
      if (!mounted) return;
      await _shareReceipt(this.context);
      return;
    }
    if (!widget.showReceiptUi) {
      debugPrint('[PDF][ACTION][CUSTOMER_DIRECT_SHARE] hasPdf=true');
    }
    debugPrint('[PDF][ACTION][PDF_SHARE] hasPdf=true');
    await Share.shareXFiles(
      <XFile>[XFile(bundle.file.path)],
      text: _receiptCustomerMessage(),
      subject: _receiptText('receiptEmailSubject'),
    );
  }

  Future<void> _shareReceiptPdfViaWhatsApp(BuildContext context) async {
    final bundle = await _buildReceiptPdfBundle(context);
    if (bundle == null) {
      if (!mounted) return;
      await _sendReceiptWhatsApp(this.context);
      return;
    }
    final phone = _customerPhoneE164;
    final phoneFound = phone != null;
    const packageTarget = 'share_sheet';
    debugPrint(
      '[PDF][ACTION][WHATSAPP_PDF] phoneFound=$phoneFound hasPdf=true packageTarget=$packageTarget',
    );

    if (phoneFound && context.mounted) {
      await Clipboard.setData(ClipboardData(text: phone));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Klantnummer gekopieerd. Kies WhatsApp en selecteer of plak de klant om de PDF te sturen.',
              en: 'Customer number copied. Choose WhatsApp and select or paste the customer to send the PDF.',
              fr: 'Numéro client copié. Choisissez WhatsApp puis sélectionnez ou collez le client pour envoyer le PDF.',
              es: 'Número del cliente copiado. Elija WhatsApp y seleccione o pegue el cliente para enviar el PDF.',
            ),
          ),
        ),
      );
    }

    final message = _tr(
      nl: 'Beste klant, in bijlage vindt u uw betaalbewijs/ritbon (PDF).',
      en: 'Dear customer, your ride receipt PDF is attached.',
      fr: 'Cher client, votre reçu de course PDF est en pièce jointe.',
      es: 'Estimado cliente, su comprobante de viaje en PDF está adjunto.',
    );

    try {
      await Share.shareXFiles(
        <XFile>[XFile(bundle.file.path)],
        text: message,
        subject: _receiptText('whatsappPdf'),
      );
    } catch (_) {
      if (!mounted) return;
      await _sendReceiptWhatsApp(this.context);
    }
  }

  Future<void> _shareReceiptPdfViaEmail(BuildContext context) async {
    await _ReceiptPdfActionRunner.sharePdfViaEmail(
      context: context,
      item: item,
    );
  }

  Future<void> _printReceiptPdf(BuildContext context) async {
    final bundle = await _buildReceiptPdfBundle(context);
    if (bundle == null) {
      if (!mounted) return;
      _printReceiptPlaceholder(this.context);
      return;
    }
    await Printing.layoutPdf(onLayout: (_) async => bundle.bytes);
  }

  void _showPaymentLink(BuildContext context) {
    _markPaymentRequestSent();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_receiptText('paymentLink')),
        content: SelectableText(_paymentLink()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(_receiptText('close')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _copyPaymentLink(context);
            },
            child: Text(_receiptText('copy')),
          ),
        ],
      ),
    );
  }

  void _showPaymentQr(BuildContext context) {
    _markPaymentRequestSent();
    final link = _paymentLink();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_receiptText('qrPayment')),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: link,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 12),
              Text(
                _totalText(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                link,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(_receiptText('close')),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _persistInCarPayment(context: context, method: 'qr');
            },
            child: Text(_receiptText('confirmQrPaid')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _copyPaymentLink(context);
            },
            child: Text(_receiptText('copyLink')),
          ),
        ],
      ),
    );
  }

  void _togglePaidDemo(BuildContext context) {
    setState(() {
      _paymentStatus = _paymentStatus == _ReceiptPaymentStatus.paid
          ? _ReceiptPaymentStatus.sent
          : _ReceiptPaymentStatus.paid;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${_receiptText('paymentStatus')}: ${_paymentStatusText()}',
        ),
      ),
    );
  }

  Future<void> _persistInCarPayment({
    required BuildContext context,
    required String method,
  }) async {
    final bookingId = (item.bookingId ?? '').trim();
    if (bookingId.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_receiptText('bookingIdMissing'))));
      return;
    }

    final amount = _receiptTotalAmount();
    final normalizedMethod = method.toLowerCase().trim();
    final payload = <String, dynamic>{
      'booking_id': bookingId,
      'payment_status': 'paid',
      'payment_method': normalizedMethod,
      'payment_source': 'in_car',
      'currency': item.currency.trim().isEmpty
          ? 'EUR'
          : item.currency.trim().toUpperCase(),
      'paid_by_driver_id': kDriverId,
      'paid_at': DateTime.now().toUtc().toIso8601String(),
      if (amount != null) 'amount': amount,
    };
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (kAdminToken.trim().isNotEmpty) {
      headers['x-admin-token'] = kAdminToken.trim();
    }

    try {
      final uri = Uri.parse(
        '$kBookingBaseUrl/bookings/${Uri.encodeComponent(bookingId)}/payment',
      );
      final res = await http
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final root = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      final extracted =
          _extractAuthoritativePaymentFields(root) ?? <String, dynamic>{};
      extracted['payment_status'] = 'paid';
      extracted['paymentStatus'] = 'paid';
      extracted['payment_method'] = normalizedMethod;
      extracted['paymentMethod'] = normalizedMethod;
      extracted['payment_source'] = 'in_car';
      extracted['paymentSource'] = 'in_car';
      _mergePaymentFieldsIntoReceiptDetails(extracted);

      if (mounted) {
        setState(() => _paymentStatus = _ReceiptPaymentStatus.paid);
      }

      final paymentBookingId = _firstDetailPathText(const [
        ['payment_booking_id'],
        ['paymentBookingId'],
        ['booking', 'payment_booking_id'],
        ['booking', 'paymentBookingId'],
        ['record', 'payment_booking_id'],
        ['record', 'paymentBookingId'],
        ['record', 'booking', 'payment_booking_id'],
        ['record', 'booking', 'paymentBookingId'],
      ]);
      await CustomerBookingsStore.instance.markPaid(
        bookingId: bookingId,
        paymentBookingId: paymentBookingId,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('paymentMarkedPaid'))),
      );
    } catch (err) {
      debugPrint(
        '[RECEIPT][PAYMENT_MARK_FAILED] bookingId=$bookingId method=$method err=$err',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('paymentMarkFailed'))),
      );
    }
  }

  Future<void> _shareReceipt(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _shareText()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_receiptText('receiptCopied'))));
  }

  void _comingSoon(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label ${_receiptText('comingSoon')}')),
    );
  }

  void _printReceiptPlaceholder(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_receiptText('printLater'))));
  }

  Widget _receiptRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
              softWrap: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 7,
            child: Text(
              value,
              textAlign: TextAlign.right,
              softWrap: true,
              style: TextStyle(
                color: highlight ? const Color(0xFFFFD400) : Colors.white,
                fontWeight: highlight ? FontWeight.w900 : FontWeight.w700,
                fontSize: highlight ? 18 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionalReceiptRow(String label, String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return _receiptRow(label, text);
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFFFD400),
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  String? _minutesText(String key) {
    final value = _detailDouble(key);
    if (value == null) return null;
    final rounded = value.round();
    return '$rounded min';
  }

  String? _plannedSubtype() {
    final explicit = _detailText('subtype');
    if (explicit != null) return _localizedRideSubtype(explicit);
    if ((item.bookingId ?? '').endsWith('-R'))
      return _receiptText('returnRide');
    if (_detailText('return_scheduled_pickup_at') != null ||
        _detailText('return_route') != null) {
      return _receiptText('outboundRide');
    }
    return null;
  }

  String? _routeSegmentsText() {
    final raw = item.bookingDetails['route_segments'];
    if (raw is! List || raw.isEmpty) return null;
    final lines = <String>[];
    for (var i = 0; i < raw.length; i++) {
      final segment = raw[i];
      if (segment is! Map) continue;
      final from = segment['from']?.toString().trim();
      final to = segment['to']?.toString().trim();
      final distance = _segmentNumber(segment['distance_km']);
      final duration = _segmentNumber(segment['duration_min']);
      final parts = <String>[
        if (from != null && from.isNotEmpty) from,
        if (to != null && to.isNotEmpty) '→ $to',
      ];
      final meta = <String>[
        if (distance != null) '${distance.toStringAsFixed(1)} km',
        if (duration != null) '${duration.round()} min',
      ].join(', ');
      final route = parts.isEmpty
          ? '${_receiptText('route')} ${i + 1}'
          : parts.join(' ');
      lines.add('${i + 1}. $route${meta.isEmpty ? '' : ': $meta'}');
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  double? _segmentNumber(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.'));
  }

  Widget _paymentSection(BuildContext context) {
    final receiptTotal = _receiptTotalAmount();
    final alreadyPaid = _paymentStatus == _ReceiptPaymentStatus.paid;
    final canRequestPayment =
        !alreadyPaid && receiptTotal != null && receiptTotal > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2F),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _receiptText('paymentActions'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          _receiptRow(_receiptText('paymentStatus'), _paymentStatusText()),
          _receiptRow(_receiptText('amount'), _totalText(), highlight: true),
          const SizedBox(height: 10),
          if (!alreadyPaid) ...[
            FilledButton.icon(
              onPressed: canRequestPayment
                  ? () => _showPaymentQr(context)
                  : null,
              icon: const Icon(Icons.qr_code_2),
              label: Text(_receiptText('payByQr')),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: canRequestPayment
                  ? () => _persistInCarPayment(context: context, method: 'cash')
                  : null,
              icon: const Icon(Icons.payments_outlined),
              label: Text(_receiptText('cashReceived')),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: canRequestPayment
                  ? () => _persistInCarPayment(
                      context: context,
                      method: 'bancontact',
                    )
                  : null,
              icon: const Icon(Icons.credit_card),
              label: Text(_receiptText('paidByCardTerminal')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _receiptActionsSection(BuildContext context) {
    final hasEmail = (_customerEmail ?? '').trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2F),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _receiptText('receiptActions'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => _viewReceiptPdf(context),
            icon: const Icon(Icons.visibility_outlined),
            label: Text(_receiptText('viewPdf')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _shareReceiptPdf(context),
            icon: const Icon(Icons.share_outlined),
            label: Text(_receiptText('sharePdf')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _shareReceiptPdfViaWhatsApp(context),
            icon: const Icon(Icons.chat_outlined),
            label: Text(_receiptText('whatsappPdf')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: hasEmail
                ? () => _shareReceiptPdfViaEmail(context)
                : null,
            icon: const Icon(Icons.email_outlined),
            label: Text(_receiptText('emailPdf')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _printReceiptPdf(context),
            icon: const Icon(Icons.print_outlined),
            label: Text(_receiptText('printReceipt')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showReceiptUi) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                _receiptText('pdfReady'),
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1020),
        elevation: 0,
        title: Text(_receiptText('receiptTitle')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF141B2F),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Image.asset(
                        kFluxidiLogoAsset,
                        width: 46,
                        height: 46,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.local_taxi,
                          color: Color(0xFFFFD400),
                          size: 38,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Fluxidi',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              _receiptText('rideReceipt'),
                              style: const TextStyle(color: Colors.white60),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _receiptRow(
                    _receiptText('receiptNumber'),
                    item.receiptNumber,
                  ),
                  _receiptRow(_receiptText('type'), item.kindLabel),
                  _optionalReceiptRow(
                    _receiptText('subtype'),
                    _plannedSubtype(),
                  ),
                  _receiptRow(
                    _receiptText('startTime'),
                    _formatDate(item.startedAt),
                  ),
                  _receiptRow(
                    _receiptText('endTime'),
                    _formatDate(item.stoppedAt),
                  ),
                  _receiptRow(_receiptText('from'), item.origin),
                  _receiptRow(_receiptText('to'), item.destination),
                  _receiptRow(_receiptText('distance'), _kmText()),
                  _receiptRow(
                    _receiptText('actualWaitingTime'),
                    _formatWait(item.waitSecondsTotal),
                  ),
                  _receiptRow(
                    _receiptText('total'),
                    _totalText(),
                    highlight: true,
                  ),
                  if (_hasAnyRawCustomerContact) ...[
                    _sectionTitle(_receiptText('customerDetails')),
                    _optionalReceiptRow(
                      _receiptText('customerName'),
                      _customerName,
                    ),
                    _optionalReceiptRow(
                      _receiptText('customerPhone'),
                      _customerPhoneRaw,
                    ),
                    _optionalReceiptRow(
                      _receiptText('customerEmail'),
                      _customerEmail,
                    ),
                  ],
                  if (_isPlannedReceipt) ...[
                    _sectionTitle(_receiptText('plannedBookingDetails')),
                    _optionalReceiptRow(
                      _receiptText('scheduledPickup'),
                      _detailText('scheduled_pickup_at') == null
                          ? null
                          : _formatDate(_detailText('scheduled_pickup_at')),
                    ),
                    _optionalReceiptRow(
                      _receiptText('service'),
                      _displayServiceToken(_detailText('service_type')),
                    ),
                    _optionalReceiptRow(
                      _receiptText('tier'),
                      _displayTierToken(_detailText('tier')),
                    ),
                    _optionalReceiptRow(
                      _receiptText('passengers'),
                      _detailText('passengers'),
                    ),
                    _optionalReceiptRow(
                      _receiptText('bags'),
                      _detailText('luggage_count'),
                    ),
                    _optionalReceiptRow(
                      _receiptText('bookedWaitingTime'),
                      _minutesText('booked_wait_minutes'),
                    ),
                    _optionalReceiptRow(
                      _receiptText('extraStops'),
                      _detailText('stops'),
                    ),
                    _receiptRow(
                      _receiptText('extras'),
                      _plannedExtrasText() ??
                          _tr(
                            nl: 'Geen extra opties',
                            en: 'No extra options',
                            fr: 'Aucune option supplementaire',
                            es: 'Sin opciones extra',
                          ),
                    ),
                    _optionalReceiptRow(
                      _receiptText('notes'),
                      _detailText('notes'),
                    ),
                    _sectionTitle(_receiptText('routeAndPrices')),
                    _optionalReceiptRow(
                      _receiptText('routeDetails'),
                      _routeSegmentsText(),
                    ),
                    ..._plannedPriceRows(),
                    _optionalReceiptRow(
                      _receiptText('returnPlanned'),
                      _detailText('return_scheduled_pickup_at') == null
                          ? null
                          : _formatDate(
                              _detailText('return_scheduled_pickup_at'),
                            ),
                    ),
                    _optionalReceiptRow(
                      _receiptText('returnRoute'),
                      _detailText('return_route'),
                    ),
                  ],
                  _sectionTitle(_receiptText('statusPaymentSection')),
                  _receiptRow(
                    _receiptText('rideStatus'),
                    _localizedRideStatus(item.status),
                  ),
                  _receiptRow(
                    _receiptText('paymentStatus'),
                    _paymentStatusText(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _paymentSection(context),
            const SizedBox(height: 16),
            _receiptActionsSection(context),
          ],
        ),
      ),
    );
  }
}

class _ReceiptPdfPreviewPage extends StatefulWidget {
  final String title;
  final Uint8List bytes;

  const _ReceiptPdfPreviewPage({required this.title, required this.bytes});

  @override
  State<_ReceiptPdfPreviewPage> createState() => _ReceiptPdfPreviewPageState();
}

class _ReceiptPdfPreviewPageState extends State<_ReceiptPdfPreviewPage> {
  late final Future<List<Uint8List>> _pagesFuture = _renderPages();

  Future<List<Uint8List>> _renderPages() async {
    final pages = <Uint8List>[];
    await for (final page in Printing.raster(widget.bytes, dpi: 200)) {
      pages.add(await page.toPng());
    }
    return pages;
  }

  Future<void> _sharePdf() async {
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}receipt-preview.pdf',
    );
    await file.writeAsBytes(widget.bytes, flush: true);
    await Share.shareXFiles(<XFile>[XFile(file.path)], subject: widget.title);
  }

  Future<void> _printPdf() async {
    await Printing.layoutPdf(onLayout: (_) async => widget.bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: _receiptText('sharePdf'),
            onPressed: _sharePdf,
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: _receiptText('printReceipt'),
            onPressed: _printPdf,
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
      body: FutureBuilder<List<Uint8List>>(
        future: _pagesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final pages = snapshot.data ?? const <Uint8List>[];
          if (pages.isEmpty) {
            return Center(child: Text(_receiptText('pdfGenerationFailed')));
          }
          return PageView.builder(
            itemCount: pages.length,
            itemBuilder: (context, index) {
              final page = pages[index];
              return Container(
                color: const Color(0xFF101010),
                alignment: Alignment.center,
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 6.0,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(8),
                    child: Image.memory(
                      page,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _BookingsHubPage extends StatelessWidget {
  final String title;
  final Widget Function(double screenH) buildList;
  final VoidCallback onRefresh;
  final ValueListenable<int> repaintListenable;

  const _BookingsHubPage({
    required this.title,
    required this.buildList,
    required this.onRefresh,
    required this.repaintListenable,
  });

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1020),
        elevation: 0,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Vernieuw',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF141B2F).withOpacity(0.94),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white12),
              ),
              padding: const EdgeInsets.all(14),
              child: ValueListenableBuilder<int>(
                valueListenable: repaintListenable,
                builder: (_, __, ___) => buildList(h),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  const _GlowIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;

    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: disabled
                ? Colors.white.withOpacity(0.04)
                : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
            boxShadow: disabled
                ? const []
                : [
                    BoxShadow(
                      color: kFluxidiYellowSoft,
                      blurRadius: 18,
                      spreadRadius: 0.5,
                    ),
                  ],
          ),
          child: Icon(
            icon,
            size: 20,
            color: disabled
                ? Colors.white.withOpacity(0.35)
                : Colors.white.withOpacity(0.90),
          ),
        ),
      ),
    );

    if ((tooltip ?? '').isEmpty) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}
