import 'package:flutter/material.dart';
import '../app_strings.dart';
import 'operational_route_labels.dart';

class OperationalRouteSummary extends StatelessWidget {
  const OperationalRouteSummary({
    super.key,
    required this.address,
    required this.expectedEnd,
    required this.language,
    this.stops = const [],
  });
  final String address;
  final DateTime expectedEnd;
  final AppLanguage language;
  final List<String> stops;
  @override
  Widget build(BuildContext context) {
    final local = expectedEnd.toLocal(),
        labels = MaterialLocalizations.of(context);
    final time = labels.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: true,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        key: const Key('operational_route_summary'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stops.isNotEmpty)
            Text(
              '${kOperationalStops.of(language)}: ${stops.join(' → ')}',
              key: const Key('operational_route_stops'),
            ),
          Text(
            '${kOperationalRouteChanged.of(language)}: $address',
            key: const Key('operational_route_destination'),
          ),
          Text(
            '${kOperationalRouteEnd.of(language)}: ${labels.formatMediumDate(local)} $time',
            key: const Key('operational_route_end'),
          ),
        ],
      ),
    );
  }
}
