import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer.dart';

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
  });
  final DriverRideOffer offer;
  final int nowMs;
  final void Function(String) onDecision;
  final bool busy;
  final String? pendingAction, error;
  final String language;
  String text(String nl, String en, String fr, String es) => switch (language) {
    'en' => en,
    'fr' => fr,
    'es' => es,
    _ => nl,
  };
  @override
  Widget build(BuildContext context) {
    final remaining = offer.secondsRemaining(nowMs);
    final enabled = !busy && remaining > 0;
    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.local_taxi, size: 44),
                      Text(
                        text(
                          'NIEUWE RITAANVRAAG',
                          'NEW RIDE REQUEST',
                          'NOUVELLE DEMANDE',
                          'NUEVA SOLICITUD',
                        ),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (offer.requestedVehicleLabel != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${text('Gevraagd voertuig/type', 'Requested vehicle/type', 'Véhicule/type demandé', 'Vehículo/tipo solicitado')}: ${offer.requestedVehicleLabel}',
                        ),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        text('Ophalen', 'Pickup', 'Départ', 'Recogida'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        offer.pickup.isEmpty
                            ? text(
                                'Adres nog niet beschikbaar',
                                'Address unavailable',
                                'Adresse indisponible',
                                'Dirección no disponible',
                              )
                            : offer.pickup,
                      ),
                      if (offer.pickupTime != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${text('Ophaaltijd', 'Pickup time', 'Heure de départ', 'Hora de recogida')}: ${_pickupTime(offer.pickupTime!)}',
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        text(
                          'Bestemming',
                          'Destination',
                          'Destination',
                          'Destino',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        offer.destination.isEmpty
                            ? text(
                                'Adres nog niet beschikbaar',
                                'Address unavailable',
                                'Adresse indisponible',
                                'Dirección no disponible',
                              )
                            : offer.destination,
                      ),
                      for (final stop in offer.stops)
                        Text(
                          '${text('Tussenstop', 'Stop', 'Étape', 'Parada')}: $stop',
                        ),
                      if (offer.returnInfo?['enabled'] == true)
                        Text(
                          '${text('Retour', 'Return', 'Retour', 'Regreso')}: ${offer.returnInfo?['pickup_time'] ?? ''} ${offer.returnInfo?['pickup'] ?? ''} → ${offer.returnInfo?['destination'] ?? ''}',
                        ),
                      if (offer.requirements != null)
                        Text(
                          '${offer.requirements?['passengers'] ?? ''} ${text('passagiers', 'passengers', 'passagers', 'pasajeros')} · ${offer.requirements?['luggage'] ?? ''} ${text('koffers', 'bags', 'bagages', 'maletas')} · ${(offer.requirements?['capabilities'] as List? ?? []).join(', ')}',
                        ),
                      const SizedBox(height: 16),
                      Text(
                        offer.price == null
                            ? text(
                                'Prijs nog niet bevestigd',
                                'Price unconfirmed',
                                'Prix non confirmé',
                                'Precio sin confirmar',
                              )
                            : '€${offer.price!.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          remaining > 0
                              ? '$remaining s'
                              : text(
                                  'Reactietijd verstreken',
                                  'Response time expired',
                                  'Délai expiré',
                                  'Tiempo agotado',
                                ),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      if (error != null)
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        key: const ValueKey('accept_ride'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(64),
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
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const ValueKey('decline_ride'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(64),
                        ),
                        onPressed: enabled && pendingAction != 'accept'
                            ? () => onDecision('decline')
                            : null,
                        icon: const Icon(Icons.cancel_outlined),
                        label: Text(
                          text(
                            'Rit weigeren',
                            'Decline ride',
                            'Refuser la course',
                            'Rechazar viaje',
                          ),
                        ),
                      ),
                      if (busy)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _pickupTime(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }
}
