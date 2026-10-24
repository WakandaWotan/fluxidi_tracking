import 'package:flutter/material.dart';
import '../app_strings.dart';

const kPickupTimingAttention = LocalizedText(
  nl: 'Ophaaltijd verstreken. Controleer de klant en chauffeur; bevestig een nieuw tijdstip of sluit de rit expliciet af.',
  en: 'Pickup time has passed. Check with the customer and driver; agree a new time or explicitly close the ride.',
  fr: 'L’heure de prise en charge est dépassée. Contactez le client et le chauffeur ; convenez d’une nouvelle heure ou clôturez explicitement la course.',
  es: 'La hora de recogida ha pasado. Consulta al cliente y conductor; acuerda otra hora o cierra el viaje explícitamente.',
  de: 'Die Abholzeit ist verstrichen. Kontaktieren Sie Kunde und Fahrer; vereinbaren Sie eine neue Zeit oder schließen Sie die Fahrt ausdrücklich ab.',
);

bool hasPickupTimingAttention(
  Map<String, dynamic> record, {
  String legType = '',
  DateTime? now,
}) {
  if (const [
    'COMPLETED',
    'CANCELLED',
    'CANCELED',
    'NO_SHOW',
    'STOPPED',
    'REJECTED',
  ].contains('${record['status'] ?? ''}'.toUpperCase()))
    return false;
  final raw = record['dispatch_timing_attention'];
  if (raw is! Map ||
      raw['reason'] != 'pickup_overdue' ||
      raw['leg_types'] is! List ||
      raw['scheduled_pickups'] is! Map)
    return false;
  final legs = record['operational_legs'] is List
      ? record['operational_legs'] as List
      : const [];
  for (final type in raw['leg_types'] as List) {
    if (!const ['outbound', 'return'].contains(type) ||
        legType.isNotEmpty && legType != type)
      continue;
    final source =
        legs
            .whereType<Map>()
            .where((leg) => leg['leg_type'] == type)
            .firstOrNull ??
        record;
    final status = '${source['status'] ?? ''}'.toUpperCase(),
        phase = '${source['customer_tracking_phase'] ?? ''}';
    if (const [
          'COMPLETED',
          'CANCELLED',
          'NO_SHOW',
          'STOPPED',
          'IN_PROGRESS',
        ].contains(status) ||
        const [
          'in_progress',
          'completed',
          'cancelled',
          'stopped',
        ].contains(phase) ||
        source['trip'] is Map && (source['trip'] as Map)['started_at'] != null)
      continue;
    final pickup =
        source['pickup_iso'] ??
        (type == 'return' ? record['return_pickup_iso'] : record['pickup_iso']);
    final date = DateTime.tryParse('$pickup');
    if (date != null &&
        !date.isAfter(now ?? DateTime.now()) &&
        (raw['scheduled_pickups'] as Map)[type] == pickup)
      return true;
  }
  return false;
}

class PickupTimingAttentionBanner extends StatelessWidget {
  const PickupTimingAttentionBanner({
    super.key,
    required this.record,
    required this.language,
    this.legType = '',
    this.now,
  });
  final Map<String, dynamic> record;
  final AppLanguage language;
  final String legType;
  final DateTime? now;
  @override
  Widget build(BuildContext context) =>
      hasPickupTimingAttention(record, legType: legType, now: now)
      ? Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            kPickupTimingAttention.of(language),
            key: const Key('pickup_timing_attention'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        )
      : const SizedBox.shrink();
}
