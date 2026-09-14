import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/airport/airport_selector.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_address_field.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_fixed_price_breakdown.dart';
import 'package:fluxidi_tracking/company/company_fixed_price_labels.dart';
import 'package:fluxidi_tracking/company/company_fixed_price_place.dart';
import 'package:fluxidi_tracking/company/company_ops_api.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

class CompanyFixedPricesPage extends StatefulWidget {
  const CompanyFixedPricesPage({
    super.key,
    this.language,
    this.catalog = CompanyFixedPricesCatalog.city,
    this.loader,
    this.saver,
    this.previewer,
  });

  final AppLanguage? language;
  final CompanyFixedPricesCatalog catalog;
  final Future<Map<String, dynamic>> Function()? loader;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> document)?
      saver;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> payload)?
      previewer;

  @override
  State<CompanyFixedPricesPage> createState() => _CompanyFixedPricesPageState();
}

class _CompanyFixedPricesPageState extends State<CompanyFixedPricesPage> {
  Map<String, dynamic> _doc = <String, dynamic>{
    'fallback': 'calculator',
    'rules': <dynamic>[],
  };
  bool _loading = true;
  bool _saving = false;
  bool _unsaved = false;
  String? _error;
  String? _previewText;
  late bool _previewDestIsAirport;
  String _previewAirportCountry = 'BE';
  String _previewAirportIata = 'BRU';
  late final LimousinePlaceLookup _previewLookup;
  late final LimousineAddressFieldController _previewFromAddress;
  late final LimousineAddressFieldController _previewToAddress;

  AppLanguage get _lang => widget.language ?? appLanguageNotifier.value;

  bool get _isAirportCatalog =>
      widget.catalog == CompanyFixedPricesCatalog.airport;

  List<Map<String, dynamic>> get _allRules {
    final raw = _doc['rules'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<Map<String, dynamic>> get _visibleRules =>
      companyFixedPriceRulesForCatalog(_allRules, widget.catalog);

  @override
  void initState() {
    super.initState();
    _previewDestIsAirport = _isAirportCatalog;
    _previewLookup = LimousinePlaceLookup(country: '');
    _previewFromAddress = LimousineAddressFieldController(
      lookup: _previewLookup,
      fieldId: 'fixed_preview_from_${widget.catalog.name}',
      language: _lang.name,
    );
    _previewToAddress = LimousineAddressFieldController(
      lookup: _previewLookup,
      fieldId: 'fixed_preview_to_${widget.catalog.name}',
      language: _lang.name,
    );
    _load();
  }

  @override
  void dispose() {
    _previewFromAddress.dispose();
    _previewToAddress.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await (widget.loader ?? fetchCompanyFixedPrices)();
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _unsaved = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Vaste prijzen laden mislukt.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = widget.saver != null
          ? await widget.saver!(_doc)
          : await saveCompanyFixedPrices(
              _doc,
              view: widget.catalog.name,
            );
      if (!mounted) return;
      setState(() {
        _doc = saved;
        _unsaved = false;
        _saving = false;
      });
    } on CompanyCustomerException catch (error) {
      if (!mounted) return;
      if (error.code == 'stale_fixed_prices') {
        await _load();
        if (!mounted) return;
        setState(() {
          _error = kCompanyFixedPricesStale.of(_lang);
          _saving = false;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = 'Bewaren mislukt.';
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Bewaren mislukt.';
        _saving = false;
      });
    }
  }

  Future<void> _preview() async {
    try {
      final from = _previewFromAddress.value;
      final to = _previewToAddress.value;
      final airport = airportByIata(_previewAirportIata);
      final destText = _previewDestIsAirport
          ? (airport?.formattedAddress ?? _previewAirportIata)
          : to.displayText.trim();
      if (from.displayText.trim().isEmpty || destText.isEmpty) {
        setState(() => _previewText = 'Vul vertrek en bestemming in.');
        return;
      }
      final result = await (widget.previewer ?? previewCompanyFixedPrice)(
        <String, dynamic>{
          'from': from.displayText.trim(),
          'to': destText,
          'from_city': companyFixedPriceLocality(from.displayText),
          'to_city': _previewDestIsAirport
              ? destText
              : companyFixedPriceLocality(to.displayText),
          if (companyFixedPricePostcode(from.displayText) != null)
            'from_postcode': companyFixedPricePostcode(from.displayText),
          if (!_previewDestIsAirport &&
              companyFixedPricePostcode(to.displayText) != null)
            'to_postcode': companyFixedPricePostcode(to.displayText),
          if (from.lat != null) 'pickup_lat': from.lat,
          if (from.lon != null) 'pickup_lng': from.lon,
          if (!_previewDestIsAirport && to.lat != null) 'dropoff_lat': to.lat,
          if (!_previewDestIsAirport && to.lon != null) 'dropoff_lng': to.lon,
          if (_previewDestIsAirport) 'airport_iata': _previewAirportIata,
          if (_previewDestIsAirport) 'airport_direction': 'to_airport',
        },
      );
      if (!mounted) return;
      final snapshot = result['snapshot'];
      if (result['matched'] == true && snapshot is Map) {
        final surcharges = snapshot['surcharges'];
        setState(() {
          _previewText =
              'Toegepast: ${snapshot['name']} · €${snapshot['total_incl_vat']} incl. btw'
              '${surcharges is List && surcharges.isNotEmpty ? ' · extra buiten het gebied' : ''}';
        });
      } else {
        final needs = _needsMoreDetail(result);
        setState(() {
          _previewText = needs ??
              (result['request_quote_required'] == true
                  ? 'Geen passende prijs. Terugval: offerte aanvragen.'
                  : 'Geen passende prijs. Terugval: bestaande calculator.');
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _previewText = 'Deze route testen is mislukt.');
    }
  }

  String? _needsMoreDetail(Map<String, dynamic> result) {
    final lines = companyFixedPriceClarificationLines(
      companyFixedPriceNeedsMoreDetail(result),
      language: _lang,
    );
    if (lines.isEmpty) return null;
    return lines.join('\n');
  }

  void _upsertRule(Map<String, dynamic> rule, {String? ruleId}) {
    final next = List<dynamic>.from(_doc['rules'] as List? ?? <dynamic>[]);
    final id = ruleId ?? rule['rule_id']?.toString();
    final index = id == null
        ? -1
        : next.indexWhere((item) =>
            item is Map && item['rule_id']?.toString() == id);
    if (index >= 0) {
      next[index] = rule;
    } else {
      next.add(rule);
    }
    setState(() {
      _doc = Map<String, dynamic>.from(_doc)..['rules'] = next;
      _unsaved = true;
    });
  }

  Future<void> _edit({Map<String, dynamic>? existing}) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute<Map<String, dynamic>>(
        builder: (_) => _CompanyFixedPriceEditorPage(
          language: _lang,
          catalog: widget.catalog,
          initial: existing,
        ),
      ),
    );
    if (result == null) return;
    _upsertRule(result, ruleId: existing?['rule_id']?.toString());
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final title = _isAirportCatalog
        ? kCompanyFixedPricesAirports.of(_lang)
        : kCompanyFixedPricesCities.of(_lang);
    return CompanyOpsThemedSurface(
      child: Scaffold(
        key: kCompanyFixedPricesPageKey,
        appBar: AppBar(title: Text(title)),
        bottomNavigationBar: _loading
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton(
                    key: kCompanyFixedPricesSaveKey,
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Bewaren…' : 'Bewaren'),
                  ),
                ),
              ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : CompanyOpsBoundedForm(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      _isAirportCatalog
                          ? kCompanyFixedPricesAirportsSubtitle.of(_lang)
                          : kCompanyFixedPricesCitiesSubtitle.of(_lang),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      kCompanyFixedPricesMyList.of(_lang),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: kCompanyFixedPricesAddKey,
                      onPressed: () => _edit(),
                      icon: const Icon(Icons.add),
                      label: Text(kCompanyFixedPricesAdd.of(_lang)),
                    ),
                    const SizedBox(height: 8),
                    if (_visibleRules.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _isAirportCatalog
                              ? 'Nog geen luchthaventarieven.'
                              : 'Nog geen dorps- of stadstarieven.',
                        ),
                      ),
                    for (final rule in _visibleRules)
                      Card(
                        margin: const EdgeInsets.only(top: 8),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  rule['name']?.toString() ?? 'Vaste prijs',
                                ),
                                subtitle: Text(
                                  companyFixedPriceRuleSummary(rule),
                                  softWrap: true,
                                ),
                                value: rule['enabled'] != false,
                                onChanged: (enabled) {
                                  _upsertRule(
                                    Map<String, dynamic>.from(rule)
                                      ..['enabled'] = enabled,
                                    ruleId: rule['rule_id']?.toString(),
                                  );
                                },
                              ),
                              SwitchListTile(
                                key: companyFixedPricePublicVisibleKey(
                                  rule['rule_id']?.toString() ?? '',
                                ),
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  kCompanyFixedPricesPublicVisible.of(_lang),
                                ),
                                subtitle: Text(
                                  kCompanyFixedPricesPublicVisibleHint.of(
                                    _lang,
                                  ),
                                  softWrap: true,
                                ),
                                value: rule['public_visible'] == true,
                                onChanged: (visible) {
                                  _upsertRule(
                                    Map<String, dynamic>.from(rule)
                                      ..['public_visible'] = visible,
                                    ruleId: rule['rule_id']?.toString(),
                                  );
                                },
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: () => _edit(existing: rule),
                                  child: Text(kCompanyFixedPricesEdit.of(_lang)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue:
                          (_doc['fallback']?.toString() ?? 'calculator') ==
                                  'request_quote'
                              ? 'request_quote'
                              : 'calculator',
                      decoration: InputDecoration(
                        labelText: kCompanyFixedPricesFallbackWhen.of(_lang),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'calculator',
                          child: Text(
                            kCompanyFixedPricesFallbackCalculator.of(_lang),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'request_quote',
                          child: Text(
                            kCompanyFixedPricesFallbackQuote.of(_lang),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _doc = Map<String, dynamic>.from(_doc)
                            ..['fallback'] = value;
                          _unsaved = true;
                        });
                      },
                    ),
                    const SizedBox(height: 24),
                    Text(
                      kCompanyFixedPricesTestTitle.of(_lang),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(kCompanyFixedPricesTestHint.of(_lang)),
                    if (_unsaved) ...[
                      const SizedBox(height: 8),
                      Text(
                        key: kCompanyFixedPricesUnsavedKey,
                        kCompanyFixedPricesUnsaved.of(_lang),
                        softWrap: true,
                      ),
                    ],
                    CompanyAddressField(
                      controller: _previewFromAddress,
                      label: 'Vertrek',
                      language: _lang,
                      inputKey: kCompanyFixedPricesPreviewFromKey,
                    ),
                    if (_isAirportCatalog)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          kCompanyFixedPricesPreviewAirport.of(_lang),
                        ),
                        value: _previewDestIsAirport,
                        onChanged: (value) =>
                            setState(() => _previewDestIsAirport = value),
                      ),
                    if (_previewDestIsAirport)
                      AirportCountryAirportSelector(
                        language: _lang,
                        countryCode: _previewAirportCountry,
                        airportIata: _previewAirportIata,
                        onCountryChanged: (code) =>
                            setState(() => _previewAirportCountry = code),
                        onAirportChanged: (airport) => setState(() {
                          _previewAirportIata = airport.iata;
                          _previewAirportCountry = airport.countryCode;
                        }),
                      )
                    else
                      CompanyAddressField(
                        controller: _previewToAddress,
                        label: 'Bestemming',
                        language: _lang,
                        inputKey: kCompanyFixedPricesPreviewToKey,
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      key: kCompanyFixedPricesPreviewKey,
                      onPressed: _preview,
                      child: Text(kCompanyFixedPricesPreview.of(_lang)),
                    ),
                    if (_previewText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        key: kCompanyFixedPricesPreviewTextKey,
                        _previewText!,
                        softWrap: true,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }
}

class _CompanyFixedPriceEditorPage extends StatefulWidget {
  const _CompanyFixedPriceEditorPage({
    required this.language,
    required this.catalog,
    this.initial,
  });

  final AppLanguage language;
  final CompanyFixedPricesCatalog catalog;
  final Map<String, dynamic>? initial;

  @override
  State<_CompanyFixedPriceEditorPage> createState() =>
      _CompanyFixedPriceEditorPageState();
}

class _CompanyFixedPriceEditorPageState
    extends State<_CompanyFixedPriceEditorPage> {
  static const double _kFieldGap = 16;
  static const double _kAfterHelperGap = 24;
  static const double _kSectionGap = 28;
  static const double _kBottomScrollGap = 72;

  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _priority;
  late final TextEditingController _extraPerKm;
  late final TextEditingController _includedKm;
  late final TextEditingController _zoneSurcharge;
  late final TextEditingController _radiusKm;
  late final TextEditingController _paxMin;
  late final TextEditingController _paxMax;
  late final TextEditingController _includesNote;
  late final LimousinePlaceLookup _lookup;
  late final LimousineAddressFieldController _originAddress;
  late final LimousineAddressFieldController _destAddress;
  String _priceCovers = 'ride';
  bool _includeWait = false;
  bool _includeBags = false;
  bool _includeExtras = false;
  String _direction = 'one_way';
  String _originType = 'city';
  String _destType = 'city';
  String _overflow = 'no_match';
  String _measure = 'radius';
  String _from = 'boundary';
  String _airportCountry = 'BE';
  String _airportIata = 'BRU';
  String _tier = '';
  String? _formError;
  String? _nameError;
  String? _amountError;

  bool get _isAirportCatalog =>
      widget.catalog == CompanyFixedPricesCatalog.airport;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial ?? const <String, dynamic>{};
    final origin = initial['origin'] is Map
        ? Map<String, dynamic>.from(initial['origin'] as Map)
        : <String, dynamic>{};
    final dest = initial['destination'] is Map
        ? Map<String, dynamic>.from(initial['destination'] as Map)
        : <String, dynamic>{};
    _name = TextEditingController(text: initial['name']?.toString() ?? '');
    _amount = TextEditingController(
      text: initial['price_incl_vat']?.toString() ?? '',
    );
    _priority = TextEditingController(
      text: initial['priority'] == null || initial['priority'] == 0
          ? ''
          : initial['priority'].toString(),
    );
    _lookup = LimousinePlaceLookup(country: '');
    _originAddress = LimousineAddressFieldController(
      lookup: _lookup,
      fieldId: 'fixed_origin',
      language: widget.language.name,
    );
    _destAddress = LimousineAddressFieldController(
      lookup: _lookup,
      fieldId: 'fixed_dest',
      language: widget.language.name,
    );
    if (_isAirportCatalog) {
      _originType = companyFixedPriceUiPlaceType(
        origin['type']?.toString() ?? 'city',
      );
      if (_originType == 'airport') _originType = 'city';
      _destType = 'airport';
      final rawDirection = initial['direction']?.toString() ?? 'to_airport';
      _direction = (rawDirection == 'from_airport' || rawDirection == 'both')
          ? rawDirection
          : 'to_airport';
      _airportIata =
          (dest['airport_iata'] ??
                  origin['airport_iata'] ??
                  initial['airport_iata'] ??
                  'BRU')
              .toString();
      final airport = airportByIata(_airportIata);
      _airportCountry = airport?.countryCode ?? 'BE';
    } else {
      _originType = companyFixedPriceUiPlaceType(
        origin['type']?.toString() ?? 'city',
      );
      _destType = companyFixedPriceUiPlaceType(
        dest['type']?.toString() ?? 'city',
      );
      if (_originType == 'airport') _originType = 'city';
      if (_destType == 'airport') _destType = 'city';
      _direction = initial['direction']?.toString() == 'both'
          ? 'both'
          : 'one_way';
    }
    final originSeed =
        origin['label']?.toString() ?? origin['value']?.toString() ?? '';
    final destSeed =
        dest['label']?.toString() ?? dest['value']?.toString() ?? '';
    if (originSeed.isNotEmpty) {
      _originAddress.seedText(originSeed, acceptApprovedDraft: true);
    }
    if (destSeed.isNotEmpty && _destType != 'airport') {
      _destAddress.seedText(destSeed, acceptApprovedDraft: true);
    }
    _overflow = initial['overflow_mode']?.toString() ?? 'no_match';
    _measure = initial['overflow_measure']?.toString() ?? 'radius';
    _from = initial['overflow_from']?.toString() ?? 'boundary';
    _extraPerKm = TextEditingController(
      text: initial['extra_per_km']?.toString() ?? '',
    );
    _includedKm = TextEditingController(
      text: initial['included_km']?.toString() ?? '',
    );
    _zoneSurcharge = TextEditingController(
      text: initial['overflow_surcharge']?.toString() ?? '',
    );
    _radiusKm = TextEditingController(
      text: (origin['radius_km'] ?? dest['radius_km'] ?? initial['radius_km'])
              ?.toString() ??
          '',
    );
    _tier = initial['tier']?.toString() ?? '';
    _priceCovers = initial['price_covers']?.toString() == 'full_assignment'
        ? 'full_assignment'
        : 'ride';
    _paxMin = TextEditingController(text: initial['pax_min']?.toString() ?? '1');
    _paxMax = TextEditingController(text: initial['pax_max']?.toString() ?? '8');
    final includes = initial['includes'] is Map
        ? Map<String, dynamic>.from(initial['includes'] as Map)
        : const <String, dynamic>{};
    _includeWait = includes['wait'] == true;
    _includeBags = includes['bags'] == true;
    _includeExtras = includes['extras'] == true;
    _includesNote = TextEditingController(
      text: includes['note']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _priority.dispose();
    _extraPerKm.dispose();
    _includedKm.dispose();
    _zoneSurcharge.dispose();
    _radiusKm.dispose();
    _paxMin.dispose();
    _paxMax.dispose();
    _includesNote.dispose();
    _originAddress.dispose();
    _destAddress.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _place({
    required String type,
    required LimousineAddressFieldController address,
  }) {
    if (type == 'airport') {
      final airport = airportByIata(_airportIata);
      if (airport == null && _airportIata.trim().length < 3) return null;
      return <String, dynamic>{
        'type': 'airport',
        'airport_iata': _airportIata,
        'label': airport?.formattedAddress ?? _airportIata,
        'lat': airport?.latitude,
        'lng': airport?.longitude,
      };
    }
    final text = address.value.displayText.trim();
    if (text.isEmpty) return null;
    final radius = double.tryParse(_radiusKm.text.replaceAll(',', '.').trim());
    if (radius != null && radius > 0) {
      final lat = address.value.lat;
      final lng = address.value.lon;
      if (lat == null || lng == null) return null;
      return <String, dynamic>{
        'type': 'radius',
        'label': companyFixedPriceLocality(text),
        'lat': lat,
        'lng': lng,
        'radius_km': radius,
      };
    }
    if (type == 'postcode') {
      final postcode = companyFixedPricePostcode(text);
      if (postcode != null) {
        return <String, dynamic>{
          'type': 'postcode',
          'value': postcode,
          'label': text,
        };
      }
      return <String, dynamic>{
        'type': 'zone',
        'value': companyFixedPriceLocality(text),
        'label': text,
      };
    }
    return <String, dynamic>{
      'type': 'city',
      'value': companyFixedPriceLocality(text),
      'label': text,
    };
  }

  void _submit() {
    final amount = double.tryParse(_amount.text.replaceAll(',', '.').trim());
    final origin = _place(type: _originType, address: _originAddress);
    final destination = _place(type: _destType, address: _destAddress);
    if (_name.text.trim().isEmpty || amount == null || amount <= 0) {
      setState(() {
        _nameError = _name.text.trim().isEmpty ? 'Vul een naam in.' : null;
        _amountError = amount == null || amount <= 0
            ? 'Vul een vast bedrag in.'
            : null;
        _formError = 'Vul een naam en een vast bedrag in.';
      });
      return;
    }
    if (origin == null || destination == null) {
      setState(() {
        _nameError = null;
        _amountError = null;
        _formError = _radiusKm.text.trim().isNotEmpty
            ? 'Kies de plaats in de zoeklijst als u een inbegrepen gebied gebruikt.'
            : 'Kies een vertrekgebied en een bestemming.';
      });
      return;
    }
    final initial = widget.initial ?? const <String, dynamic>{};
    final kind = _isAirportCatalog ? 'airport' : 'city_pair';
    var direction = _direction;
    if (_isAirportCatalog && direction == 'one_way') {
      direction = _destType == 'airport' ? 'to_airport' : 'from_airport';
    }
    Navigator.of(context).pop(<String, dynamic>{
      ...initial,
      'name': _name.text.trim(),
      'rule_id':
          initial['rule_id'] ?? 'fx_${DateTime.now().millisecondsSinceEpoch}',
      'enabled': initial['enabled'] != false,
      'kind': kind,
      'direction': direction,
      'priority': int.tryParse(_priority.text.trim()) ?? 0,
      'rule_version': ((initial['rule_version'] as num?)?.toInt() ?? 0) + 1,
      'price_incl_vat': amount,
      'currency': 'EUR',
      'tier': _tier,
      'origin': origin,
      'destination': destination,
      if (_isAirportCatalog) 'airport_iata': _airportIata,
      'overflow_mode': _overflow,
      'overflow_measure': _measure,
      'overflow_from': _from,
      'extra_per_km': double.tryParse(_extraPerKm.text.replaceAll(',', '.')),
      'included_km': double.tryParse(_includedKm.text.replaceAll(',', '.')),
      'overflow_surcharge': double.tryParse(
        _zoneSurcharge.text.replaceAll(',', '.'),
      ),
      'price_covers': _priceCovers,
      'pax_min': int.tryParse(_paxMin.text.trim()) ?? 1,
      'pax_max': int.tryParse(_paxMax.text.trim()) ?? 8,
      'includes': <String, dynamic>{
        'wait': _includeWait,
        'bags': _includeBags,
        'extras': _includeExtras,
        if (_includesNote.text.trim().isNotEmpty)
          'note': _includesNote.text.trim(),
      },
    });
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? helper,
    String? error,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 8,
      errorText: error,
      errorMaxLines: 4,
    );
  }

  Widget _placeTypeField({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    required bool allowAirport,
  }) {
    return DropdownButtonFormField<String>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: _fieldDecoration(label: label),
      items: [
        DropdownMenuItem(
          value: 'city',
          child: Text(kCompanyFixedPricesPlaceCity.of(widget.language)),
        ),
        DropdownMenuItem(
          value: 'postcode',
          child: Text(kCompanyFixedPricesPlacePostcode.of(widget.language)),
        ),
        if (allowAirport)
          DropdownMenuItem(
            value: 'airport',
            child: Text(kCompanyFixedPricesPlaceAirport.of(widget.language)),
          ),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final errorStyle = TextStyle(
      color: Theme.of(context).colorScheme.error,
    );
    return CompanyOpsThemedSurface(
      child: Scaffold(
        key: kCompanyFixedPriceEditorKey,
        appBar: AppBar(
          title: Text(kCompanyFixedPricesEditorTitle.of(widget.language)),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              key: kCompanyFixedPriceEditorSaveKey,
              onPressed: _submit,
              child: const Text('Bewaren'),
            ),
          ),
        ),
        body: CompanyOpsBoundedForm(
          child: ListView(
            key: kCompanyFixedPriceEditorScrollKey,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, _kBottomScrollGap),
            children: [
              TextField(
                controller: _name,
                decoration: _fieldDecoration(
                  label: kCompanyFixedPricesName.of(widget.language),
                  error: _nameError,
                ),
              ),
              const SizedBox(height: _kSectionGap),
              _placeTypeField(
                label: kCompanyFixedPricesOrigin.of(widget.language),
                value: _originType,
                allowAirport: false,
                onChanged: (value) => setState(() => _originType = value),
              ),
              if (_originType != 'airport') ...[
                const SizedBox(height: _kFieldGap),
                CompanyAddressField(
                  controller: _originAddress,
                  label: kCompanyFixedPricesSearchPlace.of(widget.language),
                  language: widget.language,
                ),
              ],
              const SizedBox(height: _kSectionGap),
              if (_isAirportCatalog) ...[
                Text(
                  kCompanyFixedPricesDestination.of(widget.language),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                AirportCountryAirportSelector(
                  language: widget.language,
                  countryCode: _airportCountry,
                  airportIata: _airportIata,
                  onCountryChanged: (code) =>
                      setState(() => _airportCountry = code),
                  onAirportChanged: (airport) => setState(() {
                    _airportIata = airport.iata;
                    _airportCountry = airport.countryCode;
                    _destType = 'airport';
                  }),
                ),
              ] else ...[
                _placeTypeField(
                  label: kCompanyFixedPricesDestination.of(widget.language),
                  value: _destType,
                  allowAirport: false,
                  onChanged: (value) => setState(() => _destType = value),
                ),
                const SizedBox(height: _kFieldGap),
                CompanyAddressField(
                  controller: _destAddress,
                  label: kCompanyFixedPricesSearchPlace.of(widget.language),
                  language: widget.language,
                ),
              ],
              const SizedBox(height: _kSectionGap),
              DropdownButtonFormField<String>(
                key: ValueKey('direction-$_direction-$_isAirportCatalog'),
                initialValue: _direction,
                isExpanded: true,
                decoration: _fieldDecoration(label: 'Geldig voor'),
                items: [
                  if (_isAirportCatalog) ...const [
                    DropdownMenuItem(
                      value: 'to_airport',
                      child: Text('Naar de luchthaven'),
                    ),
                    DropdownMenuItem(
                      value: 'from_airport',
                      child: Text('Vanaf de luchthaven'),
                    ),
                    DropdownMenuItem(
                      value: 'both',
                      child: Text('Beide richtingen'),
                    ),
                  ] else ...const [
                    DropdownMenuItem(
                      value: 'one_way',
                      child: Text('Eén richting'),
                    ),
                    DropdownMenuItem(
                      value: 'both',
                      child: Text('Beide richtingen'),
                    ),
                  ],
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _direction = value);
                },
              ),
              const SizedBox(height: _kFieldGap),
              TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                decoration: _fieldDecoration(
                  label: kCompanyFixedPricesAmount.of(widget.language),
                  error: _amountError,
                ),
              ),
              const SizedBox(height: _kFieldGap),
              DropdownButtonFormField<String>(
                initialValue: 'EUR',
                isExpanded: true,
                decoration: _fieldDecoration(
                  label: kCompanyFixedPricesCurrency.of(widget.language),
                ),
                items: const [
                  DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                ],
                onChanged: (_) {},
              ),
              const SizedBox(height: _kFieldGap),
              DropdownButtonFormField<String>(
                initialValue: 'incl',
                isExpanded: true,
                decoration: _fieldDecoration(
                  label: kCompanyFixedPricesVat.of(widget.language),
                  helper: kCompanyFixedPricesVatHint.of(widget.language),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'incl',
                    child: Text(kCompanyFixedPricesVatIncl.of(widget.language)),
                  ),
                ],
                onChanged: (_) {},
              ),
              const SizedBox(height: _kAfterHelperGap),
              TextField(
                controller: _priority,
                keyboardType: TextInputType.number,
                decoration: _fieldDecoration(
                  label: kCompanyFixedPricesPriority.of(widget.language),
                  helper: kCompanyFixedPricesPriorityHint.of(widget.language),
                ),
              ),
              const SizedBox(height: _kAfterHelperGap),
              DropdownButtonFormField<String>(
                initialValue: _priceCovers,
                isExpanded: true,
                decoration: _fieldDecoration(label: 'Prijs geldt voor'),
                items: const [
                  DropdownMenuItem(
                    value: 'ride',
                    child: Text('Eén ritdeel'),
                  ),
                  DropdownMenuItem(
                    value: 'full_assignment',
                    child: Text('Volledige heen-/terugopdracht'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _priceCovers = value);
                },
              ),
              const SizedBox(height: _kSectionGap),
              Text(
                kCompanyFixedPricesIncludedArea.of(widget.language),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(kCompanyFixedPricesIncludedAreaHint.of(widget.language)),
              const SizedBox(height: _kFieldGap),
              TextField(
                controller: _radiusKm,
                keyboardType: TextInputType.number,
                decoration: _fieldDecoration(
                  label: 'Inbegrepen afstand in km (optioneel)',
                ),
              ),
              const SizedBox(height: _kFieldGap),
              DropdownButtonFormField<String>(
                initialValue: _overflow,
                isExpanded: true,
                decoration: _fieldDecoration(label: 'Buiten het gebied'),
                items: const [
                  DropdownMenuItem(
                    value: 'no_match',
                    child: Text('Geen vaste prijs'),
                  ),
                  DropdownMenuItem(
                    value: 'extra_km',
                    child: Text('Toeslag per extra km'),
                  ),
                  DropdownMenuItem(
                    value: 'zone_surcharge',
                    child: Text('Vaste meerprijs voor het buitengebied'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _overflow = value);
                },
              ),
              if (_overflow == 'extra_km') ...[
                const SizedBox(height: _kFieldGap),
                DropdownButtonFormField<String>(
                  initialValue: _measure,
                  isExpanded: true,
                  decoration: _fieldDecoration(label: 'Afstand meten als'),
                  items: const [
                    DropdownMenuItem(
                      value: 'radius',
                      child: Text('Hemelsbreed vanaf de gekozen plaats'),
                    ),
                    DropdownMenuItem(
                      value: 'road',
                      child: Text('Wegafstand'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _measure = value);
                  },
                ),
                const SizedBox(height: _kFieldGap),
                DropdownButtonFormField<String>(
                  initialValue: _from,
                  isExpanded: true,
                  decoration: _fieldDecoration(
                    label: 'Betalende kilometers vanaf',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'boundary',
                      child: Text('Gebiedsgrens'),
                    ),
                    DropdownMenuItem(value: 'center', child: Text('Kern')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _from = value);
                  },
                ),
                const SizedBox(height: _kFieldGap),
                TextField(
                  controller: _extraPerKm,
                  decoration: _fieldDecoration(label: 'Toeslag per extra km'),
                ),
                if (_measure == 'road') ...[
                  const SizedBox(height: _kFieldGap),
                  TextField(
                    controller: _includedKm,
                    decoration: _fieldDecoration(
                      label: 'Inbegrepen wegkilometers',
                    ),
                  ),
                ],
              ],
              if (_overflow == 'zone_surcharge') ...[
                const SizedBox(height: _kFieldGap),
                TextField(
                  controller: _zoneSurcharge,
                  decoration: _fieldDecoration(
                    label: 'Vaste meerprijs buiten het gebied',
                  ),
                ),
              ],
              const SizedBox(height: _kFieldGap),
              TextField(
                controller: _paxMin,
                keyboardType: TextInputType.number,
                decoration: _fieldDecoration(label: 'Min. passagiers'),
              ),
              const SizedBox(height: _kFieldGap),
              TextField(
                controller: _paxMax,
                keyboardType: TextInputType.number,
                decoration: _fieldDecoration(label: 'Max. passagiers'),
              ),
              const SizedBox(height: _kFieldGap),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Wachten inbegrepen'),
                value: _includeWait,
                onChanged: (value) => setState(() => _includeWait = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Bagage inbegrepen'),
                value: _includeBags,
                onChanged: (value) => setState(() => _includeBags = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Extra’s inbegrepen'),
                value: _includeExtras,
                onChanged: (value) => setState(() => _includeExtras = value),
              ),
              const SizedBox(height: _kFieldGap),
              TextField(
                controller: _includesNote,
                decoration: _fieldDecoration(
                  label: 'Wat is verder inbegrepen',
                ),
              ),
              const SizedBox(height: _kFieldGap),
              DropdownButtonFormField<String>(
                initialValue: _tier,
                isExpanded: true,
                decoration: _fieldDecoration(label: 'Voertuigklasse'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('Alle klassen')),
                  DropdownMenuItem(value: 'comfort', child: Text('Comfort')),
                  DropdownMenuItem(value: 'private', child: Text('Private')),
                  DropdownMenuItem(value: 'premium', child: Text('Premium')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _tier = value);
                },
              ),
              if (_formError != null) ...[
                const SizedBox(height: _kFieldGap),
                Text(_formError!, style: errorStyle),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
