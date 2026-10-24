import 'package:flutter/material.dart';
import 'driver_ride_offer.dart';
import 'driver_ride_offer_presentation.dart';

class DriverRideOfferPanel extends StatelessWidget {
  const DriverRideOfferPanel({
    super.key,
    required this.offer,
    required this.nowMs,
    required this.onDecision,
    this.busy = false,
    this.pendingAction,
    this.error,
    this.language = 'nl',
    this.vehiclePresentation = const DriverRideOfferVehiclePresentation(),
  });
  final DriverRideOffer offer;
  final int nowMs;
  final void Function(String) onDecision;
  final bool busy;
  final String? pendingAction, error;
  final String language;
  final DriverRideOfferVehiclePresentation vehiclePresentation;
  String text(String nl, String en, String fr, String es) => switch (language) {
    'en' => en,
    'fr' => fr,
    'es' => es,
    _ => nl,
  };

  String people(int count) => text(
    '$count ${count == 1 ? 'persoon' : 'personen'}',
    '$count ${count == 1 ? 'person' : 'people'}',
    '$count ${count == 1 ? 'personne' : 'personnes'}',
    '$count ${count == 1 ? 'persona' : 'personas'}',
  );

  int? positiveCount(Object? value) =>
      value is num &&
          value.isFinite &&
          value > 0 &&
          value == value.roundToDouble()
      ? value.toInt()
      : null;

  @override
  Widget build(BuildContext context) {
    final remaining = offer.secondsRemaining(nowMs);
    final enabled = !busy && remaining > 0;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final name = vehiclePresentation.name?.trim() ?? '';
    final vehicleName =
        name.isEmpty ||
            name == offer.vehicleId ||
            driverOfferDisplayIsTechnicalId(name)
        ? text('Voertuig', 'Vehicle', 'Véhicule', 'Vehículo')
        : name;
    final capacity = vehiclePresentation.capacity;
    final passengers = positiveCount(offer.requirements?['passengers']);
    final bags = positiveCount(offer.requirements?['luggage']);
    final capabilities = offer.requirements?['capabilities'];
    final priceConfirmed =
        offer.price != null && offer.price!.isFinite && offer.price! >= 0;
    final amount = offer.price?.toStringAsFixed(2);
    final priceText = priceConfirmed
        ? offer.price == 0
              ? text(
                  'Kosteloze rit',
                  'No ride charge',
                  'Course gratuite',
                  'Viaje gratuito',
                )
              : '€ ${language == 'en' ? amount : amount!.replaceAll('.', ',')}'
        : text(
            'Prijs nog niet bevestigd',
            'Price not yet confirmed',
            'Prix non encore confirmé',
            'Precio aún no confirmado',
          );

    Widget section(IconData icon, String title, List<Widget> content) =>
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 12),
                child: Icon(icon, size: 22, color: colors.primary),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...content,
                  ],
                ),
              ),
            ],
          ),
        );
    Text address(String value, Key key) => Text(
      value.isEmpty
          ? text(
              'Adres nog niet beschikbaar',
              'Address unavailable',
              'Adresse indisponible',
              'Dirección no disponible',
            )
          : value,
      key: key,
      softWrap: true,
      style: theme.textTheme.bodyLarge,
    );

    return Material(
      color: Colors.black87,
      child: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 600,
                maxHeight: constraints.maxHeight.clamp(0, 720),
              ),
              child: Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: colors.primary.withValues(alpha: .45),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        key: const ValueKey('ride_offer_content'),
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.local_taxi_outlined,
                                  size: 28,
                                  color: colors.primary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    text(
                                      'Nieuwe ritaanvraag',
                                      'New ride request',
                                      'Nouvelle demande',
                                      'Nueva solicitud',
                                    ),
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$vehicleName${capacity != null && capacity > 0 ? ' · ${people(capacity)}' : ''}',
                              key: const ValueKey('offer_vehicle'),
                              style: theme.textTheme.bodyLarge,
                            ),
                            if (passengers != null ||
                                bags != null ||
                                capabilities is List && capabilities.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 4,
                                  children: [
                                    if (passengers != null)
                                      Text(people(passengers)),
                                    if (bags != null)
                                      Text(
                                        text(
                                          '$bags ${bags == 1 ? 'koffer' : 'koffers'}',
                                          '$bags ${bags == 1 ? 'bag' : 'bags'}',
                                          '$bags ${bags == 1 ? 'bagage' : 'bagages'}',
                                          '$bags ${bags == 1 ? 'maleta' : 'maletas'}',
                                        ),
                                      ),
                                    if (capabilities is List)
                                      for (final capability in capabilities)
                                        if (capability is String &&
                                            capability.trim().isNotEmpty &&
                                            !driverOfferDisplayIsTechnicalId(
                                              capability,
                                            ))
                                          Text(_capability(capability)),
                                  ],
                                ),
                              ),
                            section(
                              Icons.trip_origin,
                              text('Ophalen', 'Pickup', 'Départ', 'Recogida'),
                              [
                                if (offer.pickupTime != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      _pickupTime(offer.pickupTime!),
                                      key: const ValueKey('offer_pickup_time'),
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                address(
                                  offer.pickup,
                                  const ValueKey('offer_pickup'),
                                ),
                              ],
                            ),
                            section(
                              Icons.location_on_outlined,
                              text(
                                'Bestemming',
                                'Destination',
                                'Destination',
                                'Destino',
                              ),
                              [
                                address(
                                  offer.destination,
                                  const ValueKey('offer_destination'),
                                ),
                              ],
                            ),
                            for (final stop in offer.stops)
                              section(
                                Icons.more_horiz,
                                text('Tussenstop', 'Stop', 'Étape', 'Parada'),
                                [address(stop, ValueKey('stop_$stop'))],
                              ),
                            if (offer.returnInfo?['enabled'] == true)
                              section(
                                Icons.u_turn_left,
                                text('Retour', 'Return', 'Retour', 'Regreso'),
                                [
                                  Text(
                                    '${offer.returnInfo?['pickup_time'] ?? ''} ${offer.returnInfo?['pickup'] ?? ''} → ${offer.returnInfo?['destination'] ?? ''}',
                                    softWrap: true,
                                  ),
                                ],
                              ),
                            section(
                              Icons.payments_outlined,
                              text(
                                'Ritprijs',
                                'Ride price',
                                'Prix de la course',
                                'Precio del viaje',
                              ),
                              [
                                Text(
                                  priceText,
                                  key: const ValueKey('offer_price'),
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (priceConfirmed)
                                  Text(
                                    text(
                                      'Inclusief btw',
                                      'VAT included',
                                      'TVA comprise',
                                      'IVA incluido',
                                    ),
                                    style: theme.textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              remaining > 0
                                  ? '${text('Beslistijd', 'Decision time', 'Délai de réponse', 'Tiempo de decisión')} · $remaining s'
                                  : text(
                                      'Reactietijd verstreken',
                                      'Response time expired',
                                      'Délai expiré',
                                      'Tiempo agotado',
                                    ),
                              key: const ValueKey('offer_deadline'),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                error!,
                                style: TextStyle(color: colors.error),
                              ),
                            ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            key: const ValueKey('accept_ride'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                            ),
                            onPressed: enabled && pendingAction != 'decline'
                                ? () => onDecision('accept')
                                : null,
                            icon: const Icon(Icons.check_circle_outline),
                            label: Text(
                              text(
                                'Rit accepteren',
                                'Accept ride',
                                'Accepter la course',
                                'Aceptar viaje',
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: const ValueKey('decline_ride'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            onPressed: enabled && pendingAction != 'accept'
                                ? () => onDecision('decline')
                                : null,
                            icon: const Icon(Icons.cancel_outlined),
                            label: Text(
                              text(
                                'Weigeren',
                                'Decline',
                                'Refuser',
                                'Rechazar',
                              ),
                            ),
                          ),
                          if (busy)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: LinearProgressIndicator(),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _capability(String value) => switch (value.trim()) {
    'wheelchair' || 'wheelchair_accessible' => text(
      'Rolstoeltoegankelijk',
      'Wheelchair accessible',
      'Accessible en fauteuil',
      'Accesible en silla de ruedas',
    ),
    'child_seat' => text(
      'Kinderzitje',
      'Child seat',
      'Siège enfant',
      'Silla infantil',
    ),
    'pets' ||
    'pet_friendly' => text('Huisdieren', 'Pets', 'Animaux', 'Mascotas'),
    _ => value.trim().replaceAll('_', ' '),
  };

  String _pickupTime(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }
}
