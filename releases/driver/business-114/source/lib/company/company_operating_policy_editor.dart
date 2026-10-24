import 'package:flutter/material.dart';
import 'company_operating_policy.dart';

class CompanyOperatingPolicyEditor extends StatelessWidget {
  const CompanyOperatingPolicyEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.vehicleLabels = const {},
  });
  final CompanyOperatingPolicy value;
  final ValueChanged<CompanyOperatingPolicy> onChanged;
  final Map<String, String> vehicleLabels;
  @override
  Widget build(BuildContext context) {
    Widget choice(
      String field,
      String label,
      String selected,
      Map<String, String> options,
      ValueChanged<String> change,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: ValueKey('operating_$field'),
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: options.entries
            .map(
              (row) => DropdownMenuItem(value: row.key, child: Text(row.value)),
            )
            .toList(),
        onChanged: (next) {
          if (next != null) change(next);
        },
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Werkwijze voor chauffeurs en voertuigen',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Kies hoe jouw bedrijf chauffeurs, voertuigen en ritaanvragen afhandelt. Sla de instellingen op met Alles opslaan en publiceren.',
        ),
        const SizedBox(height: 12),
        choice(
          'device_binding',
          'Toestel koppelen aan',
          value.deviceBinding,
          {
            'existing': 'Huidige chauffeurkoppeling',
            'vehicle': 'Voertuig met wisselende chauffeur',
          },
          (v) => onChanged(value.copyWith(deviceBinding: v)),
        ),
        choice(
          'availability_source',
          'Beschikbaarheid',
          value.availabilitySource,
          {
            'existing': 'Volgens uurrooster (bestaande werking)',
            'manual_duty': 'Volgens actieve voertuigdienst',
          },
          (v) => onChanged(value.copyWith(availabilitySource: v)),
        ),
        if (value.availabilitySource == 'manual_duty') ...[
          const Text(
            'Uurroosters blijven bewaard, maar bepalen in deze werkwijze geen beschikbaarheid. Alleen een bemande wagen met een actieve dienst en verbonden app kan een oproeprit ontvangen.',
          ),
          const SizedBox(height: 12),
        ],
        choice(
          'scheduled_dispatch',
          'Vooraf geboekte ritten',
          value.scheduledDispatch,
          {
            'existing': 'Huidige afhandeling',
            'manager_first': 'Eerst naar centrale',
          },
          (v) => onChanged(value.copyWith(scheduledDispatch: v)),
        ),
        choice(
          'immediate_dispatch',
          'Directe aanvragen',
          value.immediateDispatch,
          {
            'existing': 'Huidige afhandeling',
            'manager_first': 'Centrale wijst toe',
            'driver_offer': 'Aanbieden aan beschikbare chauffeur',
            'primary_vehicle_first': 'Boven prijsgrens eerst naar hoofdwagen',
            'manager_above_threshold': 'Boven prijsgrens naar bedrijfsleider voor toewijzing',
          },
          (v) => onChanged(value.copyWith(immediateDispatch: v)),
        ),
        if (value.immediateDispatch == 'manager_above_threshold') const Text('Boven de prijsgrens beoordeelt de bedrijfsleider de rit en wijst daarna chauffeur en voertuig toe. De klant krijgt hierdoor geen voorkeur voor de wagen van de bedrijfsleider.'),
        if (['primary_vehicle_first', 'manager_above_threshold'].contains(value.immediateDispatch)) ...[
          if (value.immediateDispatch == 'primary_vehicle_first') choice(
            'primary_vehicle_id',
            'Hoofdwagen voor eerste beoordeling',
            value.primaryVehicleId ?? '',
            {
              '': 'Kies een bestaande wagen',
              ...vehicleLabels,
              if (value.primaryVehicleId != null &&
                  !vehicleLabels.containsKey(value.primaryVehicleId))
                value.primaryVehicleId!: 'Gekozen hoofdwagen',
            },
            (id) {
              if (id.isNotEmpty)
                onChanged(value.copyWith(primaryVehicleId: id));
            },
          ),
          TextFormField(
            key: const ValueKey('operating_primary_price'),
            initialValue: value.primaryReviewAboveCents == null
                ? ''
                : (value.primaryReviewAboveCents! / 100).toStringAsFixed(2),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Eerst beoordelen bij ritprijs boven (€)',
            ),
            onChanged: (raw) {
              final match = RegExp(
                r'^(\d+)(?:[.,](\d{1,2}))?$',
              ).firstMatch(raw.trim());
              final cents = match == null
                  ? null
                  : int.tryParse(match.group(1)!) == null
                  ? null
                  : int.parse(match.group(1)!) * 100 +
                        int.parse((match.group(2) ?? '').padRight(2, '0'));
              onChanged(
                CompanyOperatingPolicy(
                  deviceBinding: value.deviceBinding,
                  availabilitySource: value.availabilitySource,
                  scheduledDispatch: value.scheduledDispatch,
                  immediateDispatch: value.immediateDispatch,
                  offerResponseSeconds: value.offerResponseSeconds,
                  unansweredOffer: value.unansweredOffer,
                  primaryVehicleId: value.primaryVehicleId,
                  primaryReviewAboveCents: cents,
                ),
              );
            },
          ),
          const Text(
            'De grens is strikt: een rit die precies dit bedrag kost gaat rechtstreeks naar de gewone verdeling.',
          ),
          const SizedBox(height: 12),
        ],
        if ([
          'driver_offer',
          'primary_vehicle_first',
          'manager_above_threshold',
        ].contains(value.immediateDispatch)) ...[
          TextFormField(
            key: const ValueKey('operating_offer_seconds'),
            initialValue: value.offerResponseSeconds?.toString() ?? '',
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Reactietijd in seconden',
            ),
            onChanged: (raw) {
              final seconds = int.tryParse(raw.trim());
              onChanged(
                value.copyWith(
                  offerResponseSeconds: seconds,
                  clearOfferResponseSeconds: seconds == null,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          choice(
            'unanswered_offer',
            'Geen reactie',
            value.unansweredOffer ?? '',
            {
              '': 'Kies afhandeling',
              'central': 'Naar centrale',
              'next_vehicle': 'Volgende beschikbare wagen proberen',
            },
            (v) => onChanged(
              CompanyOperatingPolicy(
                deviceBinding: value.deviceBinding,
                availabilitySource: value.availabilitySource,
                scheduledDispatch: value.scheduledDispatch,
                immediateDispatch: value.immediateDispatch,
                offerResponseSeconds: value.offerResponseSeconds,
                unansweredOffer: v.isEmpty ? null : v,
                primaryVehicleId: value.primaryVehicleId,
                primaryReviewAboveCents: value.primaryReviewAboveCents,
              ),
            ),
          ),
          if (value.validationError != null)
            const Text(
              'Vul een positieve reactietijd in en kies de afhandeling bij geen reactie.',
            ),
        ],
      ],
    );
  }
}
