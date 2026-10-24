import 'package:fluxidi_tracking/customer_booking/official_address_lookup.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../app_strings.dart';
import '../limousine/limousine_address_field.dart';
import '../limousine/limousine_address_lookup.dart';
import 'company_address_field.dart';

Map<String, dynamic> taxiMarioMissionTariffDraft() {
  Map<String, dynamic> band(num min, num? max, Map<String, dynamic> price) => {
    'min_km': min,
    'max_km': max,
    'min_inclusive': true,
    'max_inclusive': false,
    ...price,
  };
  return {
    'version': 1,
    'enabled': false,
    'depot': null,
    'local_municipality': 'Sint-Niklaas',
    'local_minimum_applies': true,
    'price_rounding': 'nearest_euro',
    'default_vehicle_category': 'car',
    'quote_only_month_days': ['12-24', '12-25', '12-31', '01-01'],
    'minimum_per_minute_eur': 1,
    'waiting_per_minute_eur': 1,
    'categories': {
      'car': {
        'vehicle_ids': <String>[],
        'local_start_eur': 7.5,
        'local_per_km_eur': 2.5,
        'bands': [
          band(0, 95, {'start_eur': 7.5, 'per_km_eur': 1.25}),
          band(95, 125, {'fixed_eur': 125}),
          band(125, 195, {'start_eur': 0, 'per_km_eur': 1}),
          band(195, 217, {'fixed_eur': 195}),
          band(217, null, {'start_eur': 0, 'per_km_eur': .9}),
        ],
      },
      'minibus': {
        'vehicle_ids': <String>[],
        'local_start_eur': 7.5,
        'local_per_km_eur': 2.7,
        'bands': [
          band(0, 95, {'start_eur': 7.5, 'per_km_eur': 1.35}),
          band(95, 125, {'fixed_eur': 135}),
          band(125, 195, {'start_eur': 0, 'per_km_eur': 1.1}),
          band(195, 215, {'fixed_eur': 215}),
          band(215, null, {'start_eur': 0, 'per_km_eur': 1}),
        ],
      },
    },
  };
}

class CompanyMissionTariffPage extends StatefulWidget {
  const CompanyMissionTariffPage({
    super.key,
    required this.companyName,
    required this.language,
    required this.vehicleLabels,
    this.value,
    this.lookup,
  });
  final String companyName;
  final AppLanguage language;
  final Map<String, String> vehicleLabels;
  final Map<String, dynamic>? value;
  final LimousinePlaceLookup? lookup;
  @override
  State<CompanyMissionTariffPage> createState() =>
      _CompanyMissionTariffPageState();
}

class _CompanyMissionTariffPageState extends State<CompanyMissionTariffPage> {
  final _form = GlobalKey<FormState>();
  late Map<String, dynamic> _draft;
  late LimousineAddressFieldController _depot;
  String? _error;
  int _revision = 0;
  Map<String, dynamic> get _categories =>
      _draft['categories'] as Map<String, dynamic>;
  @override
  void initState() {
    super.initState();
    _draft = widget.value == null
        ? {
            'version': 1,
            'enabled': false,
            'depot': null,
            'local_municipality': '',
            'default_vehicle_category': 'car',
            'quote_only_month_days': <String>[],
            'minimum_per_minute_eur': 0,
            'waiting_per_minute_eur': 0,
            'categories': {
              for (final kind in ['car', 'minibus'])
                kind: {
                  'vehicle_ids': <String>[],
                  'local_start_eur': 0,
                  'local_per_km_eur': 0,
                  'bands': <dynamic>[],
                },
            },
          }
        : Map<String, dynamic>.from(
            jsonDecode(jsonEncode(widget.value)) as Map,
          );
    _depot = LimousineAddressFieldController(
      lookup: widget.lookup ?? OfficialAddressLookup(),
      fieldId: 'mission_depot',
      language: widget.language.name,
    );
    final saved = _draft['depot'];
    if (saved is Map && saved['lat'] is num && saved['lng'] is num) {
      final label = (saved['label'] as String?) ?? 'Opgeslagen vertrekpunt';
      _depot.acceptCopy(
        LimousineAddressValue(
          displayText: label,
          canonicalLabel: label,
          lat: (saved['lat'] as num).toDouble(),
          lon: (saved['lng'] as num).toDouble(),
          acceptance: LimousineAddressAcceptance.selected,
        ),
      );
    }
  }

  @override
  void dispose() {
    _depot.dispose();
    super.dispose();
  }

  Widget _number(
    Map<String, dynamic> target,
    String key,
    String label, {
    bool optional = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: TextFormField(
      key: ValueKey('mission_${identityHashCode(target)}_${key}_$_revision'),
      initialValue: target[key]?.toString() ?? '',
      decoration: InputDecoration(labelText: label),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (text) {
        final raw = (text ?? '').trim();
        if (optional && raw.isEmpty) return null;
        final n = double.tryParse(raw.replaceAll(',', '.'));
        return n == null || !n.isFinite || n < 0 || n > 100000
            ? 'Vul een geldig positief bedrag of getal in.'
            : null;
      },
      onChanged: (text) =>
          target[key] = double.tryParse(text.trim().replaceAll(',', '.')),
    ),
  );
  void _apply() {
    if (!_form.currentState!.validate()) return;
    if (!_depot.value.hasCoordinates) {
      setState(
        () => _error = 'Kies het vaste vertrekpunt uit de adresvoorstellen.',
      );
      return;
    }
    if (_categories.values.any((c) => (c['bands'] as List).isEmpty)) {
      setState(
        () => _error =
            'Voeg voor elke voertuigcategorie minstens één staffel toe.',
      );
      return;
    }
    _draft['depot'] = {
      'lat': _depot.value.lat,
      'lng': _depot.value.lon,
      'label': _depot.value.displayText,
    };
    Navigator.of(
      context,
    ).pop(Map<String, dynamic>.from(jsonDecode(jsonEncode(_draft)) as Map));
  }

  Widget _category(String kind, String title) {
    final category = _categories[kind] as Map<String, dynamic>;
    final bands = category['bands'] as List;
    return ExpansionTile(
      title: Text(title),
      initiallyExpanded: true,
      children: [
        _number(category, 'local_start_eur', 'Lokaal startgeld (€)'),
        _number(category, 'local_per_km_eur', 'Lokale prijs per km (€)'),
        for (var i = 0; i < bands.length; i++)
          _band(kind, i, bands[i] as Map<String, dynamic>),
        TextButton.icon(
          onPressed: () => setState(
            () => bands.add(<String, dynamic>{
              'min_km': 0,
              'max_km': null,
              'min_inclusive': true,
              'max_inclusive': false,
              'start_eur': 0,
              'per_km_eur': 0,
            }),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Staffel toevoegen'),
        ),
      ],
    );
  }

  Widget _band(String kind, int index, Map<String, dynamic> band) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text('Staffel ${index + 1}')),
              IconButton(
                tooltip: 'Staffel verwijderen',
                onPressed: () => setState(() {
                  (_categories[kind]['bands'] as List).removeAt(index);
                  _revision++;
                }),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          _number(
            band,
            'min_km',
            'Vanaf totale opdrachtkilometers',
            optional: true,
          ),
          CheckboxListTile(
            title: const Text('Ondergrens inbegrepen'),
            value: band['min_inclusive'] == true,
            onChanged: (v) => setState(() => band['min_inclusive'] = v == true),
          ),
          _number(
            band,
            'max_km',
            'Tot totale opdrachtkilometers (leeg = onbeperkt)',
            optional: true,
          ),
          CheckboxListTile(
            title: const Text('Bovengrens inbegrepen'),
            value: band['max_inclusive'] == true,
            onChanged: (v) => setState(() => band['max_inclusive'] = v == true),
          ),
          SwitchListTile(
            title: const Text('Vaste prijs voor deze staffel'),
            value: band.containsKey('fixed_eur'),
            onChanged: (fixed) => setState(() {
              if (fixed) {
                band.remove('start_eur');
                band.remove('per_km_eur');
                band['fixed_eur'] = 0;
              } else {
                band.remove('fixed_eur');
                band['start_eur'] = 0;
                band['per_km_eur'] = 0;
              }
              _revision++;
            }),
          ),
          if (band.containsKey('fixed_eur'))
            _number(band, 'fixed_eur', 'Vaste prijs (€)')
          else ...[
            _number(band, 'start_eur', 'Startgeld (€)'),
            _number(band, 'per_km_eur', 'Prijs per km (€)'),
          ],
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tarief volledige opdracht')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.companyName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Deze instellingen gelden alleen voor dit bedrijf. De lege heen- en terugrit tellen mee. Vaste luchthavenprijzen blijven apart.',
          ),
          const SizedBox(height: 12),
          if (widget.companyName
              .toLowerCase()
              .replaceAll(' ', '')
              .contains('taximario'))
            TextButton(
              key: const Key('mission_mario_template'),
              onPressed: () => setState(() {
                final depot = _draft['depot'];
                final rounding = _draft['price_rounding'];
                final vehicles = {
                  for (final kind in _categories.keys)
                    kind: List<String>.from(
                      _categories[kind]['vehicle_ids'] as List? ?? [],
                    ),
                };
                _draft = taxiMarioMissionTariffDraft();
                _draft['depot'] = depot;
                if (rounding != null) _draft['price_rounding'] = rounding;
                for (final entry in vehicles.entries) {
                  _categories[entry.key]['vehicle_ids'] = entry.value;
                }
                _revision++;
              }),
              child: const Text('Doorgegeven Taxi Mario-staffels invullen'),
            ),
          SwitchListTile(
            title: const Text('Eigen opdrachttarief gebruiken'),
            subtitle: const Text(
              'De centrale moet deze berekening ook beschikbaar hebben gemaakt.',
            ),
            value: _draft['enabled'] == true,
            onChanged: (v) => setState(() => _draft['enabled'] = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('mission_price_rounding_$_revision'),
            initialValue: _draft['price_rounding']?.toString() ?? 'cent',
            decoration: const InputDecoration(labelText: 'Ritprijs afronden'),
            items: const [
              DropdownMenuItem(value: 'cent', child: Text('Op eurocenten')),
              DropdownMenuItem(
                value: 'nearest_euro',
                child: Text('Dichtstbijzijnde hele euro'),
              ),
            ],
            onChanged: (v) => setState(() => _draft['price_rounding'] = v),
          ),
          const SizedBox(height: 12),
          CompanyAddressField(
            controller: _depot,
            label: 'Vast vertrek- en terugkeerpunt',
            language: widget.language,
            inputKey: const Key('mission_depot'),
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey('mission_city_$_revision'),
            initialValue: _draft['local_municipality']?.toString() ?? '',
            decoration: const InputDecoration(
              labelText: 'Gemeente voor lokale meterritten',
            ),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Vul de gemeente in.' : null,
            onChanged: (v) => _draft['local_municipality'] = v.trim(),
          ),
          const Text(
            'Vertrek én bestemming in deze gemeente: lokaal startgeld, kilometers met de klant en wachttijd.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('mission_local_minimum_$_revision'),
            initialValue:
                _draft['local_minimum_applies']?.toString() ?? 'unknown',
            decoration: const InputDecoration(
              labelText: 'Uurminimum ook bij lokale meterritten?',
            ),
            items: const [
              DropdownMenuItem(
                value: 'unknown',
                child: Text('Nog te bevestigen — prijs op aanvraag'),
              ),
              DropdownMenuItem(value: 'true', child: Text('Ja')),
              DropdownMenuItem(value: 'false', child: Text('Nee')),
            ],
            onChanged: (v) => setState(() {
              if (v == 'unknown') {
                _draft.remove('local_minimum_applies');
              } else {
                _draft['local_minimum_applies'] = v == 'true';
              }
            }),
          ),
          _number(
            _draft,
            'minimum_per_minute_eur',
            'Minimum per minuut volledige opdracht (€)',
          ),
          _number(
            _draft,
            'waiting_per_minute_eur',
            'Lokale wachttijd per minuut (€)',
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey('mission_days_$_revision'),
            initialValue: (_draft['quote_only_month_days'] as List)
                .map((d) {
                  final p = d.toString().split('-');
                  return '${p[1]}/${p[0]}';
                })
                .join(', '),
            decoration: const InputDecoration(
              labelText: 'Prijs op aanvraag op (dd/mm, gescheiden door komma)',
            ),
            validator: (v) {
              for (final d
                  in (v ?? '').split(',').where((s) => s.trim().isNotEmpty)) {
                final p = d.trim().split('/');
                if (p.length != 2) return 'Gebruik dd/mm.';
                final day = int.tryParse(p[0]), month = int.tryParse(p[1]);
                if (day == null || month == null) return 'Ongeldige datum.';
                final date = DateTime(2000, month, day);
                if (date.day != day || date.month != month)
                  return 'Ongeldige datum.';
              }
              return null;
            },
            onChanged: (v) => _draft['quote_only_month_days'] = v
                .split(',')
                .where((s) => s.trim().isNotEmpty)
                .map((s) {
                  final p = s.trim().split('/');
                  return p.length == 2
                      ? '${p[1].padLeft(2, '0')}-${p[0].padLeft(2, '0')}'
                      : s;
                })
                .toList(),
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _draft['default_vehicle_category'] as String?,
            decoration: const InputDecoration(
              labelText: 'Categorie wanneer nog geen wagen gekozen is',
            ),
            items: [
              if (_categories.containsKey('car'))
                const DropdownMenuItem(
                  value: 'car',
                  child: Text('Personenwagen'),
                ),
              if (_categories.containsKey('minibus'))
                const DropdownMenuItem(
                  value: 'minibus',
                  child: Text('Minibus'),
                ),
            ],
            onChanged: (v) => _draft['default_vehicle_category'] = v,
          ),
          for (final vehicle in widget.vehicleLabels.entries)
            DropdownButtonFormField<String>(
              key: ValueKey('mission_vehicle_${vehicle.key}_$_revision'),
              initialValue: _categories.keys.firstWhere(
                (k) => (_categories[k]['vehicle_ids'] as List? ?? []).contains(
                  vehicle.key,
                ),
                orElse: () => '',
              ),
              decoration: InputDecoration(
                labelText: vehicle.value,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 20,
                ),
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Nog niet ingedeeld — prijs op aanvraag'),
                ),
                if (_categories.containsKey('car'))
                  const DropdownMenuItem(
                    value: 'car',
                    child: Text('Personenwagen'),
                  ),
                if (_categories.containsKey('minibus'))
                  const DropdownMenuItem(
                    value: 'minibus',
                    child: Text('Minibus'),
                  ),
              ],
              onChanged: (v) => setState(() {
                for (final c in _categories.values) {
                  (c['vehicle_ids'] as List? ?? (c['vehicle_ids'] = <String>[]))
                      .remove(vehicle.key);
                }
                if (v != null && v.isNotEmpty)
                  (_categories[v]['vehicle_ids'] as List).add(vehicle.key);
              }),
            ),
          if (_categories.containsKey('car')) _category('car', 'Personenwagen'),
          if (_categories.containsKey('minibus'))
            _category('minibus', 'Minibus'),
          const Text(
            'Bij overlappende kilometergrenzen blijft de prijs op aanvraag. Deze tarieven omvatten geen automatische nacht-, weekend-, bagage- of andere toeslagen.',
          ),
          const Text(
            'Direct betalen: tarieven inclusief btw. Achteraf betalen op factuur: alleen na toestemming van de centrale, tarieven exclusief btw.',
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            key: const Key('mission_apply'),
            onPressed: _apply,
            child: const Text('Toepassen in instellingen'),
          ),
          const Text(
            'Sla daarna de bedrijfsinstellingen op om de wijziging te bewaren.',
          ),
        ],
      ),
    ),
  );
}
