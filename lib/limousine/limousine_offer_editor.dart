// LIMOUSINE-MARKETPLACE-P2B2C — complete offer authoring dialog.
//
// Owns every sub-editor for one `pricing:v1.limousine.offers[]` entry:
// target, presentation, journey types, fixed journey rules, hourly hire and
// packages, limousine distance/time, included services, paid extras,
// mobilisation and publication — plus an explicit NL/EN/FR/ES matrix for all
// customer-facing text.
//
// Money is authored in major units and stored as integer cents. IDs are stable.
// Pricing is never configured per driver, and the private operating-base
// address stays private (clearly marked, never published).

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import 'limousine_offers.dart';

const List<String> _kLangs = <String>['nl', 'en', 'fr', 'es'];

int? _centsFromText(String raw) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null) return null;
  return (value * 100).round();
}

String _textFromCents(int? cents) =>
    cents == null ? '' : (cents / 100).toStringAsFixed(2);

int? _msFromDate(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  return parsed?.millisecondsSinceEpoch;
}

String _dateFromMs(Object? ms) {
  final value = int.tryParse('${ms ?? ''}');
  if (value == null || value <= 0) return '';
  return DateTime.fromMillisecondsSinceEpoch(
    value,
  ).toIso8601String().split('T').first;
}

Map<String, dynamic> _mapOf(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _listOf(Object? raw) {
  if (raw is! List) return <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

/// A localized NL/EN/FR/ES text block. Each language is edited and stored
/// independently — writing one language never overwrites another.
class LimousineLocalizedField {
  LimousineLocalizedField(Object? initial)
    : controllers = <String, TextEditingController>{
        for (final lang in _kLangs)
          lang: TextEditingController(
            text: (limousineLocalizedOf(initial)[lang] ?? ''),
          ),
      };

  final Map<String, TextEditingController> controllers;

  Map<String, String> toJson() => <String, String>{
    for (final lang in _kLangs) lang: controllers[lang]!.text.trim(),
  };

  bool get isEmpty => controllers.values.every((c) => c.text.trim().isEmpty);

  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
  }
}

class LimousineOfferEditorDialog extends StatefulWidget {
  const LimousineOfferEditorDialog({
    super.key,
    required this.initialOffer,
    required this.vehicles,
    required this.currency,
    required this.language,
    this.backgroundColor,
  });

  final Map<String, dynamic> initialOffer;
  final List<VehicleProfile> vehicles;
  final String currency;
  final AppLanguage language;
  final Color? backgroundColor;

  @override
  State<LimousineOfferEditorDialog> createState() =>
      _LimousineOfferEditorDialogState();
}

class _LimousineOfferEditorDialogState
    extends State<LimousineOfferEditorDialog> {
  late Map<String, dynamic> _base;

  late String _offerId;
  late bool _enabled;
  late bool _published;
  late String _targetType;
  late String _vehicleId;
  late String _serviceClassId;
  late String _presentation;
  late Set<String> _journeyTypes;

  late LimousineLocalizedField _title;
  late LimousineLocalizedField _description;
  late LimousineLocalizedField _importantInfo;
  late TextEditingController _displayAmount;

  late List<Map<String, dynamic>> _fixedRules;

  late bool _hourlyEnabled;
  late TextEditingController _firstHour;
  late TextEditingController _additionalHour;
  late TextEditingController _minDuration;
  late TextEditingController _maxDuration;
  late TextEditingController _includedHours;
  late TextEditingController _packageDuration;
  late TextEditingController _packageAmount;
  late TextEditingController _excessHour;

  late bool _dtEnabled;
  late TextEditingController _dtBase;
  late TextEditingController _dtPerKm;
  late TextEditingController _dtPerMinute;
  late TextEditingController _dtMinimum;
  late TextEditingController _dtVatRate;

  late String _mobMethod;
  late bool _mobOutbound;
  late bool _mobReturn;
  late TextEditingController _mobIncludedKm;
  late TextEditingController _mobIncludedMinutes;
  late TextEditingController _mobFee;
  late LimousineLocalizedField _mobDisclosure;
  late TextEditingController _mobBaseAddress;

  late List<_IncludedServiceDraft> _includedServices;
  late List<_PaidExtraDraft> _paidExtras;

  AppLanguage get _lang => widget.language;

  @override
  void initState() {
    super.initState();
    _base = Map<String, dynamic>.from(widget.initialOffer);

    final existingId = (_base['offer_id'] ?? '').toString().trim();
    _offerId = existingId.isEmpty
        ? 'offer_${DateTime.now().millisecondsSinceEpoch}'
        : existingId;
    _enabled = _base.containsKey('enabled') ? _base['enabled'] == true : true;
    _published = _base['published'] == true;
    _targetType = limousineOfferToken(_base['target_type']).isEmpty
        ? LimousineOfferTarget.serviceClass
        : limousineOfferToken(_base['target_type']);
    _vehicleId = (_base['vehicle_id'] ?? '').toString();
    _serviceClassId = limousineOfferToken(_base['service_class_id']);
    _presentation = limousineOfferToken(_base['price_presentation']).isEmpty
        ? LimousinePricePresentation.quoteRequired
        : limousineOfferToken(_base['price_presentation']);
    _journeyTypes = <String>{
      ...((_base['journey_types'] as List?) ?? const [])
          .map(limousineOfferToken)
          .where((t) => t.isNotEmpty),
    };

    _title = LimousineLocalizedField(_base['title']);
    _description = LimousineLocalizedField(_base['description']);
    _importantInfo = LimousineLocalizedField(_base['important_information']);
    _displayAmount = TextEditingController(
      text: _textFromCents(limousineCentsOf(_base['display_amount_cents'])),
    );

    _fixedRules = _listOf(_base['fixed_rules']);

    final hourly = _mapOf(_base['hourly']);
    _hourlyEnabled = hourly['enabled'] == true;
    _firstHour = TextEditingController(
      text: _textFromCents(limousineCentsOf(hourly['first_hour_cents'])),
    );
    _additionalHour = TextEditingController(
      text: _textFromCents(limousineCentsOf(hourly['additional_hour_cents'])),
    );
    _minDuration = TextEditingController(
      text: '${hourly['minimum_duration_minutes'] ?? ''}',
    );
    _maxDuration = TextEditingController(
      text: '${hourly['maximum_duration_minutes'] ?? ''}',
    );
    _includedHours = TextEditingController(
      text: '${hourly['included_hours'] ?? ''}',
    );
    _packageDuration = TextEditingController(
      text: '${hourly['package_duration_minutes'] ?? ''}',
    );
    _packageAmount = TextEditingController(
      text: _textFromCents(limousineCentsOf(hourly['package_amount_cents'])),
    );
    _excessHour = TextEditingController(
      text: _textFromCents(limousineCentsOf(hourly['excess_hour_cents'])),
    );

    final dt = _mapOf(_base['distance_time']);
    _dtEnabled = dt['enabled'] == true;
    _dtBase = TextEditingController(
      text: _textFromCents(limousineCentsOf(dt['base_incl_vat_cents'])),
    );
    _dtPerKm = TextEditingController(
      text: _textFromCents(limousineCentsOf(dt['per_km_incl_vat_cents'])),
    );
    _dtPerMinute = TextEditingController(
      text: _textFromCents(limousineCentsOf(dt['per_minute_incl_vat_cents'])),
    );
    _dtMinimum = TextEditingController(
      text: _textFromCents(limousineCentsOf(dt['minimum_incl_vat_cents'])),
    );
    _dtVatRate = TextEditingController(text: '${dt['vat_rate'] ?? ''}');

    final mob = _mapOf(_base['mobilisation']);
    _mobMethod = limousineOfferToken(mob['method']).isEmpty
        ? LimousineMobilisationMethod.included
        : limousineOfferToken(mob['method']);
    _mobOutbound = mob['outbound_charged'] == true;
    _mobReturn = mob['return_charged'] == true;
    _mobIncludedKm = TextEditingController(
      text: '${mob['included_distance_km'] ?? ''}',
    );
    _mobIncludedMinutes = TextEditingController(
      text: '${mob['included_minutes'] ?? ''}',
    );
    _mobFee = TextEditingController(
      text: _textFromCents(limousineCentsOf(mob['fee_cents'])),
    );
    _mobDisclosure = LimousineLocalizedField(mob['disclosure']);
    _mobBaseAddress = TextEditingController(
      text: (mob['operating_base_address'] ?? '').toString(),
    );

    _includedServices = _listOf(_base['included_services'])
        .map(_IncludedServiceDraft.fromJson)
        .toList();
    _paidExtras = _listOf(
      _base['paid_extras'],
    ).map(_PaidExtraDraft.fromJson).toList();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _importantInfo.dispose();
    _mobDisclosure.dispose();
    for (final c in [
      _displayAmount,
      _firstHour,
      _additionalHour,
      _minDuration,
      _maxDuration,
      _includedHours,
      _packageDuration,
      _packageAmount,
      _excessHour,
      _dtBase,
      _dtPerKm,
      _dtPerMinute,
      _dtMinimum,
      _dtVatRate,
      _mobIncludedKm,
      _mobIncludedMinutes,
      _mobFee,
      _mobBaseAddress,
    ]) {
      c.dispose();
    }
    for (final s in _includedServices) {
      s.dispose();
    }
    for (final e in _paidExtras) {
      e.dispose();
    }
    super.dispose();
  }

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (_lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.en:
      case AppLanguage.de:
        return en;
    }
  }

  /// Builds the offer JSON. Unknown/unedited keys from the original record are
  /// preserved so a future field is never silently dropped.
  Map<String, dynamic> buildOffer() {
    final vehicleClass = _targetType == LimousineOfferTarget.vehicle
        ? limousineOfferToken(
            widget.vehicles
                .where((v) => v.id == _vehicleId)
                .map((v) => v.serviceClassId)
                .join(),
          )
        : _serviceClassId;
    return <String, dynamic>{
      ..._base,
      'offer_id': _offerId,
      'enabled': _enabled,
      'published': _published,
      'target_type': _targetType,
      if (_targetType == LimousineOfferTarget.vehicle) 'vehicle_id': _vehicleId,
      'service_class_id': vehicleClass,
      'price_presentation': _presentation,
      'currency': widget.currency,
      'journey_types': _journeyTypes.toList(growable: false),
      'title': _title.toJson(),
      'description': _description.toJson(),
      'important_information': _importantInfo.toJson(),
      'display_amount_cents': _centsFromText(_displayAmount.text),
      'fixed_rules': _fixedRules,
      'hourly': <String, dynamic>{
        ..._mapOf(_base['hourly']),
        'enabled': _hourlyEnabled,
        'first_hour_cents': _centsFromText(_firstHour.text),
        'additional_hour_cents': _centsFromText(_additionalHour.text),
        'minimum_duration_minutes': int.tryParse(_minDuration.text.trim()),
        'maximum_duration_minutes': int.tryParse(_maxDuration.text.trim()),
        'included_hours': int.tryParse(_includedHours.text.trim()),
        'package_duration_minutes': int.tryParse(_packageDuration.text.trim()),
        'package_amount_cents': _centsFromText(_packageAmount.text),
        'excess_hour_cents': _centsFromText(_excessHour.text),
        'currency': widget.currency,
      },
      'distance_time': <String, dynamic>{
        ..._mapOf(_base['distance_time']),
        'enabled': _dtEnabled,
        'base_incl_vat_cents': _centsFromText(_dtBase.text),
        'per_km_incl_vat_cents': _centsFromText(_dtPerKm.text),
        'per_minute_incl_vat_cents': _centsFromText(_dtPerMinute.text),
        'minimum_incl_vat_cents': _centsFromText(_dtMinimum.text),
        'vat_rate': double.tryParse(_dtVatRate.text.trim().replaceAll(',', '.')),
        'currency': widget.currency,
      },
      'mobilisation': <String, dynamic>{
        ..._mapOf(_base['mobilisation']),
        'method': _mobMethod,
        'outbound_charged': _mobOutbound,
        'return_charged': _mobReturn,
        'included_distance_km': double.tryParse(
          _mobIncludedKm.text.trim().replaceAll(',', '.'),
        ),
        'included_minutes': int.tryParse(_mobIncludedMinutes.text.trim()),
        'fee_cents': _centsFromText(_mobFee.text),
        'currency': widget.currency,
        'disclosure': _mobDisclosure.toJson(),
        // PRIVATE operational data — never published.
        'operating_base_address': _mobBaseAddress.text.trim(),
      },
      'included_services': _includedServices
          .map((s) => s.toJson())
          .toList(growable: false),
      'paid_extras': _paidExtras.map((e) => e.toJson()).toList(growable: false),
    };
  }

  Widget _sectionHeader(String label) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
  );

  Widget _localizedMatrix(String label, LimousineLocalizedField field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        ..._kLangs.map(
          (lang) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: TextField(
              controller: field.controllers[lang],
              decoration: InputDecoration(
                isDense: true,
                labelText: lang.toUpperCase(),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
      ],
    );
  }

  Widget _money(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        isDense: true,
        labelText: '$label (${widget.currency})',
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {}),
    ),
  );

  Widget _number(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: TextField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {}),
    ),
  );

  Widget _fixedRulesEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._fixedRules.asMap().entries.map((entry) {
          final i = entry.key;
          final rule = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (rule['rule_id'] ?? '').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Switch(
                        value: rule['enabled'] == true,
                        onChanged: (v) =>
                            setState(() => _fixedRules[i]['enabled'] = v),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () =>
                            setState(() => _fixedRules.removeAt(i)),
                      ),
                    ],
                  ),
                  DropdownButtonFormField<String>(
                    value: LimousineJourneyTypeId.all.contains(
                          limousineOfferToken(rule['journey_type']),
                        )
                        ? limousineOfferToken(rule['journey_type'])
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: _t(
                        nl: 'Rittype',
                        en: 'Journey type',
                        fr: 'Type de trajet',
                        es: 'Tipo de trayecto',
                      ),
                    ),
                    items: LimousineJourneyTypeId.all
                        .map(
                          (j) => DropdownMenuItem(
                            value: j,
                            child: Text(limousineJourneyTypeLabel(j, _lang)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (v) =>
                        setState(() => _fixedRules[i]['journey_type'] = v),
                  ),
                  const SizedBox(height: 6),
                  if (limousineOfferToken(rule['journey_type']) ==
                      LimousineJourneyTypeId.airportTransfer) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: (rule['airport_iata'] ?? '').toString(),
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'IATA',
                            ),
                            onChanged: (v) => setState(
                              () => _fixedRules[i]['airport_iata'] =
                                  v.trim().toUpperCase(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: ['to_airport', 'from_airport', 'both']
                                    .contains(
                                      limousineOfferToken(rule['direction']),
                                    )
                                ? limousineOfferToken(rule['direction'])
                                : null,
                            isExpanded: true,
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: _t(
                                nl: 'Richting',
                                en: 'Direction',
                                fr: 'Direction',
                                es: 'Dirección',
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'to_airport',
                                child: Text('to_airport'),
                              ),
                              DropdownMenuItem(
                                value: 'from_airport',
                                child: Text('from_airport'),
                              ),
                              DropdownMenuItem(
                                value: 'both',
                                child: Text('both'),
                              ),
                            ],
                            onChanged: (v) => setState(
                              () => _fixedRules[i]['direction'] = v,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  DropdownButtonFormField<String>(
                    value: const ['none', 'postcode', 'city', 'country', 'radius']
                            .contains(limousineOfferToken(rule['zone_type']))
                        ? limousineOfferToken(rule['zone_type'])
                        : 'none',
                    isExpanded: true,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: _t(
                        nl: 'Zone',
                        en: 'Zone',
                        fr: 'Zone',
                        es: 'Zona',
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('none')),
                      DropdownMenuItem(
                        value: 'postcode',
                        child: Text('postcode'),
                      ),
                      DropdownMenuItem(value: 'city', child: Text('city')),
                      DropdownMenuItem(value: 'country', child: Text('country')),
                      DropdownMenuItem(value: 'radius', child: Text('radius')),
                    ],
                    onChanged: (v) =>
                        setState(() => _fixedRules[i]['zone_type'] = v),
                  ),
                  const SizedBox(height: 6),
                  if (limousineOfferToken(rule['zone_type']) == 'radius') ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: '${rule['zone_center_lat'] ?? ''}',
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'lat',
                            ),
                            onChanged: (v) => setState(
                              () => _fixedRules[i]['zone_center_lat'] =
                                  double.tryParse(v.trim()),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: '${rule['zone_center_lng'] ?? ''}',
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'lng',
                            ),
                            onChanged: (v) => setState(
                              () => _fixedRules[i]['zone_center_lng'] =
                                  double.tryParse(v.trim()),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: '${rule['radius_km'] ?? ''}',
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'km',
                            ),
                            onChanged: (v) => setState(
                              () => _fixedRules[i]['radius_km'] =
                                  double.tryParse(v.trim()),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ] else if (limousineOfferToken(rule['zone_type']) != 'none') ...[
                    TextFormField(
                      initialValue: (rule['zone_value'] ?? '').toString(),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: _t(
                          nl: 'Zonewaarde',
                          en: 'Zone value',
                          fr: 'Valeur de zone',
                          es: 'Valor de zona',
                        ),
                      ),
                      onChanged: (v) => setState(
                        () => _fixedRules[i]['zone_value'] =
                            v.trim().toUpperCase(),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  TextFormField(
                    initialValue: _textFromCents(
                      limousineCentsOf(rule['amount_cents']),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText:
                          '${_t(nl: 'Bedrag incl. btw', en: 'Amount incl. VAT', fr: 'Montant TTC', es: 'Importe con IVA')} (${widget.currency})',
                    ),
                    onChanged: (v) => setState(() {
                      _fixedRules[i]['amount_cents'] = _centsFromText(v);
                      _fixedRules[i]['currency'] = widget.currency;
                    }),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: _dateFromMs(rule['active_from_ms']),
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: _t(
                              nl: 'Geldig vanaf',
                              en: 'Valid from',
                              fr: 'Valide à partir de',
                              es: 'Válido desde',
                            ),
                            hintText: 'YYYY-MM-DD',
                          ),
                          onChanged: (v) => setState(
                            () => _fixedRules[i]['active_from_ms'] =
                                _msFromDate(v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          initialValue: _dateFromMs(rule['active_until_ms']),
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: _t(
                              nl: 'Geldig tot',
                              en: 'Valid until',
                              fr: 'Valide jusqu’à',
                              es: 'Válido hasta',
                            ),
                            hintText: 'YYYY-MM-DD',
                          ),
                          onChanged: (v) => setState(
                            () => _fixedRules[i]['active_until_ms'] =
                                _msFromDate(v),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _fixedRules.add(<String, dynamic>{
              'rule_id': 'rule_${DateTime.now().millisecondsSinceEpoch}',
              'enabled': true,
              'journey_type': LimousineJourneyTypeId.pointToPoint,
              'zone_type': 'none',
              'currency': widget.currency,
            });
          }),
          icon: const Icon(Icons.add, size: 16),
          label: Text(
            _t(
              nl: 'Vaste rit toevoegen',
              en: 'Add fixed journey',
              fr: 'Ajouter un trajet fixe',
              es: 'Añadir trayecto fijo',
            ),
          ),
        ),
      ],
    );
  }

  Widget _includedServicesEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._includedServices.asMap().entries.map((entry) {
          final i = entry.key;
          final draft = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(draft.itemId)),
                      Switch(
                        value: draft.active,
                        onChanged: (v) => setState(() => draft.active = v),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => setState(() {
                          _includedServices.removeAt(i).dispose();
                        }),
                      ),
                    ],
                  ),
                  _localizedMatrix(
                    _t(
                      nl: 'Label',
                      en: 'Label',
                      fr: 'Libellé',
                      es: 'Etiqueta',
                    ),
                    draft.label,
                  ),
                ],
              ),
            ),
          );
        }),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _includedServices.add(
              _IncludedServiceDraft.empty(
                'inc_${DateTime.now().millisecondsSinceEpoch}',
              ),
            );
          }),
          icon: const Icon(Icons.add, size: 16),
          label: Text(
            _t(
              nl: 'Inbegrepen dienst toevoegen',
              en: 'Add included service',
              fr: 'Ajouter un service inclus',
              es: 'Añadir servicio incluido',
            ),
          ),
        ),
      ],
    );
  }

  Widget _paidExtrasEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._paidExtras.asMap().entries.map((entry) {
          final i = entry.key;
          final draft = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(draft.extraId)),
                      Switch(
                        value: draft.active,
                        onChanged: (v) => setState(() => draft.active = v),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => setState(() {
                          _paidExtras.removeAt(i).dispose();
                        }),
                      ),
                    ],
                  ),
                  _localizedMatrix(
                    _t(
                      nl: 'Label',
                      en: 'Label',
                      fr: 'Libellé',
                      es: 'Etiqueta',
                    ),
                    draft.label,
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: draft.quoteRequired,
                    title: Text(
                      _t(
                        nl: 'Offerte op aanvraag',
                        en: 'Quote required',
                        fr: 'Devis requis',
                        es: 'Presupuesto requerido',
                      ),
                    ),
                    onChanged: (v) =>
                        setState(() => draft.quoteRequired = v == true),
                  ),
                  if (!draft.quoteRequired)
                    TextField(
                      controller: draft.amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText:
                            '${_t(nl: 'Bedrag', en: 'Amount', fr: 'Montant', es: 'Importe')} (${widget.currency})',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: draft.public,
                    title: Text(
                      _t(
                        nl: 'Publiek tonen',
                        en: 'Show publicly',
                        fr: 'Afficher publiquement',
                        es: 'Mostrar públicamente',
                      ),
                    ),
                    onChanged: (v) => setState(() => draft.public = v == true),
                  ),
                ],
              ),
            ),
          );
        }),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _paidExtras.add(
              _PaidExtraDraft.empty(
                'extra_${DateTime.now().millisecondsSinceEpoch}',
                widget.currency,
              ),
            );
          }),
          icon: const Icon(Icons.add, size: 16),
          label: Text(
            _t(
              nl: 'Betalende extra toevoegen',
              en: 'Add paid extra',
              fr: 'Ajouter une option payante',
              es: 'Añadir extra de pago',
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = buildOffer();
    final errors = validateLimousineOffer(
      draft,
      vehicles: widget.vehicles,
      knownClassIds: appConfig.enabledLimousineServiceClasses
          .map((o) => o.id)
          .toList(growable: false),
      readiness: true,
    ).errors;
    final modes = limousineOfferSupportedPricingModes(draft);

    return AlertDialog(
      backgroundColor: widget.backgroundColor,
      scrollable: true,
      title: Text(
        _t(
          nl: 'Limousineaanbod',
          en: 'Limousine offer',
          fr: 'Offre limousine',
          es: 'Oferta de limusina',
        ),
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              _t(
                nl: 'Publieke tekst (alle talen)',
                en: 'Public text (all languages)',
                fr: 'Texte public (toutes les langues)',
                es: 'Texto público (todos los idiomas)',
              ),
            ),
            _localizedMatrix(
              _t(nl: 'Titel', en: 'Title', fr: 'Titre', es: 'Título'),
              _title,
            ),
            _localizedMatrix(
              _t(
                nl: 'Omschrijving',
                en: 'Description',
                fr: 'Description',
                es: 'Descripción',
              ),
              _description,
            ),
            _localizedMatrix(
              _t(
                nl: 'Belangrijke info',
                en: 'Important information',
                fr: 'Informations importantes',
                es: 'Información importante',
              ),
              _importantInfo,
            ),

            _sectionHeader(
              _t(
                nl: 'Aanbod voor',
                en: 'Offer target',
                fr: 'Cible de l’offre',
                es: 'Destino de la oferta',
              ),
            ),
            DropdownButtonFormField<String>(
              value: _targetType,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: [
                DropdownMenuItem(
                  value: LimousineOfferTarget.serviceClass,
                  child: Text(
                    _t(
                      nl: 'Serviceklasse',
                      en: 'Service class',
                      fr: 'Classe de service',
                      es: 'Clase de servicio',
                    ),
                  ),
                ),
                DropdownMenuItem(
                  value: LimousineOfferTarget.vehicle,
                  child: Text(
                    _t(
                      nl: 'Exact voertuig (heeft voorrang)',
                      en: 'Exact vehicle (takes precedence)',
                      fr: 'Véhicule exact (prioritaire)',
                      es: 'Vehículo exacto (tiene prioridad)',
                    ),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _targetType = v ?? _targetType),
            ),
            const SizedBox(height: 6),
            if (_targetType == LimousineOfferTarget.vehicle)
              DropdownButtonFormField<String>(
                value: widget.vehicles.any((v) => v.id == _vehicleId)
                    ? _vehicleId
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: _t(
                    nl: 'Voertuig',
                    en: 'Vehicle',
                    fr: 'Véhicule',
                    es: 'Vehículo',
                  ),
                ),
                items: widget.vehicles
                    .map(
                      (v) => DropdownMenuItem(
                        value: v.id,
                        child: Text(
                          '${v.vehicleName} · ${v.brandModel}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (v) => setState(() => _vehicleId = v ?? ''),
              )
            else
              DropdownButtonFormField<String>(
                value: isKnownActiveLimousineServiceClassId(_serviceClassId)
                    ? _serviceClassId
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: _t(
                    nl: 'Limousineklasse',
                    en: 'Limousine class',
                    fr: 'Classe de limousine',
                    es: 'Clase de limusina',
                  ),
                ),
                items: appConfig.enabledLimousineServiceClasses
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(c.labelFor(_lang)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (v) => setState(() => _serviceClassId = v ?? ''),
              ),

            _sectionHeader(
              _t(
                nl: 'Prijsweergave',
                en: 'Price presentation',
                fr: 'Présentation du prix',
                es: 'Presentación del precio',
              ),
            ),
            DropdownButtonFormField<String>(
              value: _presentation,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: LimousinePricePresentation.all
                  .map(
                    (p) => DropdownMenuItem(
                      value: p,
                      child: Text(limousinePresentationLabel(p, _lang)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (v) => setState(() => _presentation = v ?? _presentation),
            ),
            const SizedBox(height: 6),
            _money(
              _displayAmount,
              _t(
                nl: 'Getoond bedrag',
                en: 'Display amount',
                fr: 'Montant affiché',
                es: 'Importe mostrado',
              ),
            ),
            Text(
              '${_t(nl: 'Berekeningswijze', en: 'Pricing modes', fr: 'Modes de calcul', es: 'Modos de cálculo')}: ${modes.join(', ')}',
              style: const TextStyle(fontSize: 11.5),
            ),

            _sectionHeader(
              _t(
                nl: 'Van toepassing op',
                en: 'Applicable journey types',
                fr: 'Types de trajet applicables',
                es: 'Tipos de trayecto aplicables',
              ),
            ),
            Wrap(
              spacing: 6,
              children: LimousineJourneyTypeId.all
                  .map(
                    (j) => FilterChip(
                      label: Text(limousineJourneyTypeLabel(j, _lang)),
                      selected: _journeyTypes.contains(j),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _journeyTypes.add(j);
                        } else {
                          _journeyTypes.remove(j);
                        }
                      }),
                    ),
                  )
                  .toList(growable: false),
            ),

            _sectionHeader(
              _t(
                nl: 'Vaste ritten',
                en: 'Fixed journeys',
                fr: 'Trajets fixes',
                es: 'Trayectos fijos',
              ),
            ),
            _fixedRulesEditor(),

            _sectionHeader(
              _t(
                nl: 'Uurhuur en pakketten',
                en: 'Hourly hire and packages',
                fr: 'Location horaire et forfaits',
                es: 'Alquiler por horas y paquetes',
              ),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _hourlyEnabled,
              title: Text(
                _t(
                  nl: 'Uurhuur met chauffeur',
                  en: 'Chauffeur-driven hourly hire',
                  fr: 'Location horaire avec chauffeur',
                  es: 'Alquiler por horas con chófer',
                ),
              ),
              onChanged: (v) => setState(() => _hourlyEnabled = v),
            ),
            if (_hourlyEnabled) ...[
              _money(
                _firstHour,
                _t(
                  nl: 'Eerste uur',
                  en: 'First hour',
                  fr: 'Première heure',
                  es: 'Primera hora',
                ),
              ),
              _money(
                _additionalHour,
                _t(
                  nl: 'Bijkomend uur',
                  en: 'Additional hour',
                  fr: 'Heure supplémentaire',
                  es: 'Hora adicional',
                ),
              ),
              _number(
                _minDuration,
                _t(
                  nl: 'Minimumduur (min)',
                  en: 'Minimum duration (min)',
                  fr: 'Durée minimale (min)',
                  es: 'Duración mínima (min)',
                ),
              ),
              _number(
                _maxDuration,
                _t(
                  nl: 'Maximumduur (min)',
                  en: 'Maximum duration (min)',
                  fr: 'Durée maximale (min)',
                  es: 'Duración máxima (min)',
                ),
              ),
              _number(
                _includedHours,
                _t(
                  nl: 'Inbegrepen uren',
                  en: 'Included hours',
                  fr: 'Heures incluses',
                  es: 'Horas incluidas',
                ),
              ),
              _number(
                _packageDuration,
                _t(
                  nl: 'Pakketduur (min)',
                  en: 'Package duration (min)',
                  fr: 'Durée du forfait (min)',
                  es: 'Duración del paquete (min)',
                ),
              ),
              _money(
                _packageAmount,
                _t(
                  nl: 'Pakketprijs',
                  en: 'Package amount',
                  fr: 'Montant du forfait',
                  es: 'Importe del paquete',
                ),
              ),
              _money(
                _excessHour,
                _t(
                  nl: 'Extra uur buiten pakket',
                  en: 'Excess hour',
                  fr: 'Heure excédentaire',
                  es: 'Hora excedente',
                ),
              ),
            ],

            _sectionHeader(
              _t(
                nl: 'Afstand/tijd (limousine)',
                en: 'Distance/time (limousine)',
                fr: 'Distance/temps (limousine)',
                es: 'Distancia/tiempo (limusina)',
              ),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _dtEnabled,
              title: Text(
                _t(
                  nl: 'Afstand/tijd gebruiken',
                  en: 'Use distance/time',
                  fr: 'Utiliser distance/temps',
                  es: 'Usar distancia/tiempo',
                ),
              ),
              onChanged: (v) => setState(() => _dtEnabled = v),
            ),
            if (_dtEnabled) ...[
              _money(
                _dtBase,
                _t(nl: 'Basis', en: 'Base', fr: 'Base', es: 'Base'),
              ),
              _money(
                _dtPerKm,
                _t(
                  nl: 'Per kilometer',
                  en: 'Per kilometre',
                  fr: 'Par kilomètre',
                  es: 'Por kilómetro',
                ),
              ),
              _money(
                _dtPerMinute,
                _t(
                  nl: 'Per minuut',
                  en: 'Per minute',
                  fr: 'Par minute',
                  es: 'Por minuto',
                ),
              ),
              _money(
                _dtMinimum,
                _t(
                  nl: 'Minimum',
                  en: 'Minimum',
                  fr: 'Minimum',
                  es: 'Mínimo',
                ),
              ),
              _number(
                _dtVatRate,
                _t(
                  nl: 'Btw-tarief (bv. 0.06)',
                  en: 'VAT rate (e.g. 0.06)',
                  fr: 'Taux de TVA (p.ex. 0.06)',
                  es: 'Tipo de IVA (p.ej. 0.06)',
                ),
              ),
            ],

            _sectionHeader(
              _t(
                nl: 'Voorrijden',
                en: 'Mobilisation',
                fr: 'Acheminement',
                es: 'Movilización',
              ),
            ),
            DropdownButtonFormField<String>(
              value: _mobMethod,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: LimousineMobilisationMethod.all
                  .map(
                    (m) => DropdownMenuItem(
                      value: m,
                      child: Text(limousineMobilisationLabel(m, _lang)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (v) => setState(() => _mobMethod = v ?? _mobMethod),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _mobOutbound,
              title: Text(
                _t(
                  nl: 'Heenrit aanrekenen',
                  en: 'Charge outbound',
                  fr: 'Facturer l’aller',
                  es: 'Cobrar ida',
                ),
              ),
              onChanged: (v) => setState(() => _mobOutbound = v == true),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _mobReturn,
              title: Text(
                _t(
                  nl: 'Terugrit aanrekenen',
                  en: 'Charge return',
                  fr: 'Facturer le retour',
                  es: 'Cobrar vuelta',
                ),
              ),
              onChanged: (v) => setState(() => _mobReturn = v == true),
            ),
            _number(
              _mobIncludedKm,
              _t(
                nl: 'Inbegrepen km',
                en: 'Included km',
                fr: 'Km inclus',
                es: 'Km incluidos',
              ),
            ),
            _number(
              _mobIncludedMinutes,
              _t(
                nl: 'Inbegrepen minuten',
                en: 'Included minutes',
                fr: 'Minutes incluses',
                es: 'Minutos incluidos',
              ),
            ),
            if (_mobMethod == LimousineMobilisationMethod.fixedFee)
              _money(
                _mobFee,
                _t(
                  nl: 'Vaste voorrijkost',
                  en: 'Fixed mobilisation fee',
                  fr: 'Frais fixes',
                  es: 'Tarifa fija',
                ),
              ),
            _localizedMatrix(
              _t(
                nl: 'Publieke uitleg voorrijden',
                en: 'Public mobilisation disclosure',
                fr: 'Mention publique d’acheminement',
                es: 'Aviso público de movilización',
              ),
              _mobDisclosure,
            ),
            TextField(
              controller: _mobBaseAddress,
              decoration: InputDecoration(
                isDense: true,
                labelText: _t(
                  nl: 'Standplaats (privé)',
                  en: 'Operating base (private)',
                  fr: 'Base d’exploitation (privée)',
                  es: 'Base operativa (privada)',
                ),
                helperText: _t(
                  nl: 'Nooit gepubliceerd. Alleen voor jouw berekening.',
                  en: 'Never published. Used only for your own calculation.',
                  fr: 'Jamais publiée. Uniquement pour votre calcul.',
                  es: 'Nunca se publica. Solo para tu cálculo.',
                ),
              ),
            ),

            _sectionHeader(
              _t(
                nl: 'Inbegrepen diensten',
                en: 'Included services',
                fr: 'Services inclus',
                es: 'Servicios incluidos',
              ),
            ),
            _includedServicesEditor(),

            _sectionHeader(
              _t(
                nl: 'Betalende extra’s',
                en: 'Paid optional extras',
                fr: 'Options payantes',
                es: 'Extras de pago',
              ),
            ),
            _paidExtrasEditor(),

            _sectionHeader(
              _t(
                nl: 'Publicatie',
                en: 'Publication',
                fr: 'Publication',
                es: 'Publicación',
              ),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              title: Text(
                _t(nl: 'Actief', en: 'Active', fr: 'Actif', es: 'Activo'),
              ),
              onChanged: (v) => setState(() => _enabled = v),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _published,
              title: Text(
                _t(
                  nl: 'Publiceren',
                  en: 'Publish',
                  fr: 'Publier',
                  es: 'Publicar',
                ),
              ),
              onChanged: (v) => setState(() => _published = v),
            ),

            if (errors.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...errors.map(
                (code) => Text(
                  '• ${limousineOfferErrorLabel(code, _lang)}',
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            _t(
              nl: 'Annuleren',
              en: 'Cancel',
              fr: 'Annuler',
              es: 'Cancelar',
            ),
          ),
        ),
        FilledButton(
          onPressed: errors.isEmpty
              ? () => Navigator.of(context).pop(buildOffer())
              : null,
          child: Text(
            _t(
              nl: 'Bewaren',
              en: 'Save',
              fr: 'Enregistrer',
              es: 'Guardar',
            ),
          ),
        ),
      ],
    );
  }
}

class _IncludedServiceDraft {
  _IncludedServiceDraft({
    required this.itemId,
    required this.label,
    required this.active,
  });

  factory _IncludedServiceDraft.fromJson(Map<String, dynamic> json) =>
      _IncludedServiceDraft(
        itemId: (json['item_id'] ?? '').toString(),
        label: LimousineLocalizedField(json['label']),
        active: json['active'] != false,
      );

  factory _IncludedServiceDraft.empty(String id) => _IncludedServiceDraft(
    itemId: id,
    label: LimousineLocalizedField(null),
    active: true,
  );

  final String itemId;
  final LimousineLocalizedField label;
  bool active;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'item_id': itemId,
    'label': label.toJson(),
    'active': active,
  };

  void dispose() => label.dispose();
}

class _PaidExtraDraft {
  _PaidExtraDraft({
    required this.extraId,
    required this.label,
    required this.amount,
    required this.quoteRequired,
    required this.currency,
    required this.active,
    required this.public,
  });

  factory _PaidExtraDraft.fromJson(Map<String, dynamic> json) => _PaidExtraDraft(
    extraId: (json['extra_id'] ?? '').toString(),
    label: LimousineLocalizedField(json['label']),
    amount: TextEditingController(
      text: _textFromCents(limousineCentsOf(json['amount_cents'])),
    ),
    quoteRequired: json['quote_required'] == true,
    currency: (json['currency'] ?? 'EUR').toString(),
    active: json['active'] != false,
    public: json['public'] != false,
  );

  factory _PaidExtraDraft.empty(String id, String currency) => _PaidExtraDraft(
    extraId: id,
    label: LimousineLocalizedField(null),
    amount: TextEditingController(),
    quoteRequired: false,
    currency: currency,
    active: true,
    public: true,
  );

  final String extraId;
  final LimousineLocalizedField label;
  final TextEditingController amount;
  bool quoteRequired;
  final String currency;
  bool active;
  bool public;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'extra_id': extraId,
    'label': label.toJson(),
    'quote_required': quoteRequired,
    if (!quoteRequired) 'amount_cents': _centsFromText(amount.text),
    'currency': currency,
    'active': active,
    'public': public,
  };

  void dispose() {
    label.dispose();
    amount.dispose();
  }
}
