import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/ride/operational_route_summary.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/customer_booking/customer_live_tracking.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'customer_tracking_maplibre.dart';

class CustomerLiveTrackingPanel extends StatelessWidget {
  const CustomerLiveTrackingPanel({
    super.key,
    required this.view,
    required this.language,
    required this.palette,
    this.mapToken = '',
    this.mapBuilder,
    this.mapMode,
  });

  final CustomerLiveTrackingView view;
  final AppLanguage language;
  final CustomerThemePalette palette;
  final String mapToken;
  final CustomerTrackingMapBuilder? mapBuilder;
  final CustomerTrackingMapMode? mapMode;

  @override
  Widget build(BuildContext context) {
    if (view.availability == CustomerLiveTrackingAvailability.idle ||
        view.availability == CustomerLiveTrackingAvailability.unavailable) {
      return const SizedBox.shrink();
    }
    final snapshot = view.snapshot;
    final phase = _phaseLabel(snapshot.phase, language);
    final feed = _feedLabel(snapshot.phase, snapshot.feed, language);
    final eta = view.showEta;
    final mapData = CustomerTrackingMapData.fromView(view,
        mapMode ?? (palette.isDark ? CustomerTrackingMapMode.dark : CustomerTrackingMapMode.light));
    return Container(
      key: kCustomerLiveTrackingPanelKey,
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceAlt.withOpacity(palette.isDark ? 0.95 : 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.gold.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            phase,
            key: kCustomerLiveTrackingPhaseKey,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (view.driverName.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              view.driverName.trim(),
              style: TextStyle(color: palette.textPrimary),
            ),
          ],
          if (snapshot.vehicleLabel.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              snapshot.vehicleLabel.trim(),
              style: TextStyle(color: palette.textMuted),
            ),
          ],
          if (snapshot.operationalRouteMetadata.isNotEmpty && snapshot.phase == CustomerLivePhase.inProgress)
            OperationalRouteSummary(address:snapshot.operationalRouteMetadata['destination_address'] as String,
              expectedEnd:DateTime.parse(snapshot.operationalRouteMetadata['expected_end_iso'] as String), language:language),
          if (feed != null) ...[
            const SizedBox(height: 6),
            Text(
              feed,
              key: kCustomerLiveTrackingFeedKey,
              style: TextStyle(color: palette.textMuted),
            ),
          ],
          if (eta != null) ...[
            const SizedBox(height: 6),
            Text(
              _etaLabel(eta, language),
              key: kCustomerLiveTrackingEtaKey,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (mapData != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              key: kCustomerLiveTrackingMapKey,
              borderRadius: BorderRadius.circular(10),
              child: mapBuilder?.call(mapData) ?? CustomerTrackingMapLibre(data:mapData),
            ),
          ],
        ],
      ),
    );
  }
}

String _phaseLabel(CustomerLivePhase phase, AppLanguage language) {
  switch (phase) {
    case CustomerLivePhase.assigned:
      return const LocalizedText(
        nl: 'Chauffeur toegewezen',
        en: 'Driver assigned',
        fr: 'Chauffeur assigné',
        es: 'Conductor asignado',
        de: 'Fahrer zugewiesen',
      ).of(language);
    case CustomerLivePhase.enRoutePickup:
      return const LocalizedText(
        nl: 'Onderweg naar het ophaaladres',
        en: 'On the way to pickup',
        fr: 'En route vers la prise en charge',
        es: 'De camino a la recogida',
        de: 'Unterwegs zur Abholung',
      ).of(language);
    case CustomerLivePhase.inProgress:
      return const LocalizedText(
        nl: 'Onderweg naar de bestemming',
        en: 'On the way to the destination',
        fr: 'En route vers la destination',
        es: 'De camino al destino',
        de: 'Unterwegs zum Ziel',
      ).of(language);
    case CustomerLivePhase.stopped:
      return const LocalizedText(
        nl: 'Rit gestopt',
        en: 'Ride stopped',
        fr: 'Course arrêtée',
        es: 'Viaje detenido',
        de: 'Fahrt gestoppt',
      ).of(language);
    case CustomerLivePhase.completed:
      return const LocalizedText(
        nl: 'Rit voltooid',
        en: 'Ride completed',
        fr: 'Course terminée',
        es: 'Viaje completado',
        de: 'Fahrt abgeschlossen',
      ).of(language);
    case CustomerLivePhase.cancelled:
      return const LocalizedText(
        nl: 'Rit geannuleerd',
        en: 'Ride cancelled',
        fr: 'Course annulée',
        es: 'Viaje cancelado',
        de: 'Fahrt storniert',
      ).of(language);
    case CustomerLivePhase.expired:
      return const LocalizedText(
        nl: 'Live positie gestopt',
        en: 'Live position ended',
        fr: 'Position en direct arrêtée',
        es: 'Posición en vivo finalizada',
        de: 'Live-Position beendet',
      ).of(language);
    case CustomerLivePhase.unassigned:
    case CustomerLivePhase.unknown:
      return const LocalizedText(
        nl: 'Geen live rit',
        en: 'No live ride',
        fr: 'Pas de course en direct',
        es: 'Sin viaje en vivo',
        de: 'Keine Live-Fahrt',
      ).of(language);
  }
}

String? _feedLabel(
  CustomerLivePhase phase,
  CustomerLiveFeedHealth feed,
  AppLanguage language,
) {
  if (phase == CustomerLivePhase.assigned) return null;
  switch (feed) {
    case CustomerLiveFeedHealth.missing:
      return const LocalizedText(
        nl: 'Positie nog niet beschikbaar',
        en: 'Position not available yet',
        fr: 'Position pas encore disponible',
        es: 'Posición aún no disponible',
        de: 'Position noch nicht verfügbar',
      ).of(language);
    case CustomerLiveFeedHealth.stale:
      return const LocalizedText(
        nl: 'Positie is niet recent',
        en: 'Position is not recent',
        fr: 'La position n’est pas récente',
        es: 'La posición no es reciente',
        de: 'Position ist nicht aktuell',
      ).of(language);
    case CustomerLiveFeedHealth.closed:
      return const LocalizedText(
        nl: 'Live positie gestopt',
        en: 'Live position ended',
        fr: 'Position en direct arrêtée',
        es: 'Posición en vivo finalizada',
        de: 'Live-Position beendet',
      ).of(language);
    case CustomerLiveFeedHealth.live:
    case CustomerLiveFeedHealth.unknown:
      return null;
  }
}

String _etaLabel(CustomerLiveEta eta, AppLanguage language) {
  final minutes = (eta.durationSeconds / 60).ceil();
  final shown = minutes < 1 ? 1 : minutes;
  if (eta.target == 'destination') {
    return const LocalizedText(
      nl: 'Aankomst bestemming over {minutes} min',
      en: 'Arrival at destination in {minutes} min',
      fr: 'Arrivée à destination dans {minutes} min',
      es: 'Llegada al destino en {minutes} min',
      de: 'Ankunft am Ziel in {minutes} Min.',
    ).of(language).replaceAll('{minutes}', '$shown');
  }
  return const LocalizedText(
    nl: 'Aankomst ophaal over {minutes} min',
    en: 'Arrival at pickup in {minutes} min',
    fr: 'Arrivée à la prise en charge dans {minutes} min',
    es: 'Llegada a la recogida en {minutes} min',
    de: 'Ankunft an der Abholung in {minutes} Min.',
  ).of(language).replaceAll('{minutes}', '$shown');
}
