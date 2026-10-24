import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_vehicle_cards.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_vehicle_offers.dart';
import 'package:fluxidi_tracking/customer_booking/customer_reliable_choice.dart';

// Separate offline R&D entrypoint. No backend URL, payment, booking, routing or
// tracking request. The ordinary application's entrypoint remains unchanged.
void main() => runApp(const P12ReliableChoicePreview());
class P12ReliableChoicePreview extends StatefulWidget {
  const P12ReliableChoicePreview({super.key});
  @override
  State<P12ReliableChoicePreview> createState() => _PreviewState();
}
class _PreviewState extends State<P12ReliableChoicePreview> {
  String? selected;
  bool scheduled = false;
  @override
  Widget build(BuildContext context) {
    final offers = <CustomerBookingVehicleOffer>[
      for (final row in [('demo-vito', 'Mercedes Vito', 300, 1100, 8), ('demo-corolla', 'Toyota Corolla', 420, 4000, 4), ('demo-vito-2', 'Mercedes Vito', 540, 5800, 8)])
        CustomerBookingVehicleOffer(vehicle: {'vehicle_id': row.$1, 'name': row.$2, 'passenger_capacity': row.$5, 'luggage_capacity': 4,
          'reliable_choice_v1': {'schema': 'fluxidi-reliable-choice-v1', 'vehicle_id': row.$1, 'estimate': true,
            'evidence_revision': 'offline-demo-only', 'valid_until_ms': DateTime.now().millisecondsSinceEpoch + 15000,
            'status': scheduled ? 'available_for_selected_time' : 'estimated_availability',
            'pickup_eta_seconds': scheduled ? null : row.$3, 'pickup_distance_meters': scheduled ? null : row.$4}},
          available: true, passengerSeats: row.$5, baggageCapacity: 4),
    ];
    return MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData.dark(), home: Scaffold(
      appBar: AppBar(title: const Text('P12 · lokale R&D-demo')),
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Synthetisch voorbeeld · geen boeking of live verbinding'),
        SwitchListTile(title: const Text('Geplande rit'), value: scheduled, onChanged: (v) => setState(() { scheduled = v; })),
        CustomerBookingVehiclePhotoCardGrid(offers: offers, language: AppLanguage.nl, selectedVehicleId: selected,
          reliableChoiceOnly: true, onSelected: (offer) => setState(() { selected = offer.vehicleId; })),
        const SizedBox(height: 16),
        if (selected != null) Text(customerReliableChoiceStatus('waiting_driver_confirmation', AppLanguage.nl)),
      ]))),
    ));
  }
}
