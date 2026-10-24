import 'package:fluxidi_tracking/app_strings.dart';

/// Presentation of an already authorised server projection. This object never
/// authorises eligibility, pricing, a booking or an assignment on the client.
class CustomerReliableChoiceEstimate {
  const CustomerReliableChoiceEstimate({required this.vehicleId, required this.scheduled,
    required this.validUntilMs, required this.revision, this.seconds, this.distanceMeters, this.rangeMinimumSeconds, this.rangeMaximumSeconds});
  final String vehicleId, revision;
  final bool scheduled;
  final int validUntilMs;
  final double? seconds, distanceMeters, rangeMinimumSeconds, rangeMaximumSeconds;

  static CustomerReliableChoiceEstimate? parse(dynamic raw, {required String vehicleId, int? nowMs}) {
    if (raw is! Map || raw['schema'] != 'fluxidi-reliable-choice-v1' || raw['estimate'] != true ||
        raw['vehicle_id'] != vehicleId || vehicleId.isEmpty || raw['evidence_revision'] is! String ||
        (raw['evidence_revision'] as String).isEmpty || raw['valid_until_ms'] is! int ||
        raw['valid_until_ms'] <= (nowMs ?? DateTime.now().millisecondsSinceEpoch)) return null;
    final scheduled = raw['status'] == 'available_for_selected_time';
    if (!scheduled && raw['status'] != 'estimated_availability') return null;
    final sec = raw['pickup_eta_seconds'], distance = raw['pickup_distance_meters'];
    if (scheduled ? sec != null || distance != null :
        sec is! num || !sec.isFinite || sec < 0 || distance is! num || !distance.isFinite || distance < 0) return null;
    final range = raw['pickup_eta_range_seconds'];
    if (range != null && (scheduled || range is! List || range.length != 2 ||
        range[0] is! num || !(range[0] as num).isFinite || range[0] < 0 ||
        range[1] is! num || !(range[1] as num).isFinite || range[1] < range[0] ||
        sec is! num || sec < range[0] || sec > range[1])) return null;
    return CustomerReliableChoiceEstimate(vehicleId: vehicleId, scheduled: scheduled,
      validUntilMs: raw['valid_until_ms'], revision: raw['evidence_revision'],
      seconds: (sec as num?)?.toDouble(), distanceMeters: (distance as num?)?.toDouble(),
      rangeMinimumSeconds: range == null ? null : (range[0] as num).toDouble(),
      rangeMaximumSeconds: range == null ? null : (range[1] as num).toDouble());
  }

  String etaLabel(AppLanguage language) {
    if (scheduled) return const LocalizedText(nl: 'Beschikbaar voor gekozen tijdstip', en: 'Available for selected time',
      fr: 'Disponible à l’heure choisie', es: 'Disponible a la hora elegida', de: 'Zum gewählten Zeitpunkt verfügbar').of(language);
    if (rangeMinimumSeconds != null && rangeMaximumSeconds != null) {
      final lower = (rangeMinimumSeconds! / 60).floor().clamp(1, 999);
      final upper = (rangeMaximumSeconds! / 60).ceil().clamp(lower, 999);
      return lower == upper ? '± $lower min' : '± $lower–$upper min';
    }
    final minutes = ((seconds ?? 0) / 60).ceil().clamp(1, 999);
    return '± $minutes min';
  }

  String? distanceLabel(AppLanguage language) {
    if (scheduled) return null;
    var km = ((distanceMeters ?? 0) / 1000).toStringAsFixed(1);
    if ([AppLanguage.nl, AppLanguage.fr, AppLanguage.es, AppLanguage.de].contains(language)) km = km.replaceAll('.', ',');
    return LocalizedText(nl: '$km km van jou', en: '$km km away',
      fr: '$km km de vous', es: '$km km de ti', de: '$km km entfernt').of(language);
  }
}

String customerReliableChoiceStatus(String state, AppLanguage language) {
  return switch (state) {
    'waiting_driver_confirmation' => const LocalizedText(nl: 'Wachten op bevestiging van chauffeur', en: 'Waiting for driver confirmation',
      fr: 'En attente de confirmation du chauffeur', es: 'Esperando confirmación del conductor', de: 'Warten auf Fahrerbestätigung').of(language),
    'finding_next_vehicle' => const LocalizedText(nl: 'We zoeken de volgende beschikbare wagen', en: 'Finding the next available vehicle',
      fr: 'Recherche du prochain véhicule disponible', es: 'Buscando el siguiente vehículo disponible', de: 'Nächstes verfügbares Fahrzeug wird gesucht').of(language),
    'dispatcher_review' => const LocalizedText(nl: 'Je rit wordt door de dispatch bekeken', en: 'Dispatch is reviewing your trip',
      fr: 'La centrale examine votre course', es: 'La central está revisando tu viaje', de: 'Die Zentrale prüft deine Fahrt').of(language),
    'live_tracking' => const LocalizedText(nl:'Chauffeur onderweg',en:'Driver on the way',fr:'Chauffeur en route',es:'Conductor en camino',de:'Fahrer unterwegs').of(language),
    'cancelled' => const LocalizedText(nl:'Rit geannuleerd',en:'Trip cancelled',fr:'Course annulée',es:'Viaje cancelado',de:'Fahrt storniert').of(language),
    'stopped' => const LocalizedText(nl:'Tracking gestopt',en:'Tracking stopped',fr:'Suivi arrêté',es:'Seguimiento detenido',de:'Tracking beendet').of(language),
    'driver_confirmed' => const LocalizedText(nl: 'Chauffeur bevestigd · ETA geschat', en: 'Driver confirmed · ETA estimated',
      fr: 'Chauffeur confirmé · arrivée estimée', es: 'Conductor confirmado · llegada estimada', de: 'Fahrer bestätigt · Ankunft geschätzt').of(language),
    _ => const LocalizedText(nl: 'Beschikbaarheid te bevestigen', en: 'Availability to be confirmed',
      fr: 'Disponibilité à confirmer', es: 'Disponibilidad por confirmar', de: 'Verfügbarkeit zu bestätigen').of(language),
  };
}
