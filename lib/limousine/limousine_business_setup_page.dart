// LIMOUSINE-MARKETPLACE-P2D4C1B — full-page Limousine-instellingen.
// Reuses the committed offer contract, fleet classification and pricing API.
// Does not invent a second vehicle schema or booking engine.

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../business_theme_palette.dart';
import '../business_theme_store.dart';
import '../vehicle_management_page.dart';
import 'limousine_business_setup.dart';
import 'limousine_business_setup_labels.dart';
import 'limousine_offer_editor.dart';
import 'limousine_offers.dart';
import 'limousine_p2d4c1a_ux.dart';

typedef LimousinePricingLoader = Future<Map<String, dynamic>> Function();
typedef LimousinePricingSaver =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> section);

class LimousineBusinessSetupPage extends StatefulWidget {
  const LimousineBusinessSetupPage({
    super.key,
    this.loadPricing,
    this.savePricing,
    this.vehicles,
    this.knownClassIds,
    this.language,
    this.backgroundColor,
    this.entryEnabled = false,
    this.companyName = '',
    this.onConfigureVehicle,
  });

  final LimousinePricingLoader? loadPricing;
  final LimousinePricingSaver? savePricing;
  final List<VehicleProfile>? vehicles;
  final List<String>? knownClassIds;
  final AppLanguage? language;
  final Color? backgroundColor;
  final bool entryEnabled;
  final String companyName;
  final VoidCallback? onConfigureVehicle;

  @override
  State<LimousineBusinessSetupPage> createState() =>
      _LimousineBusinessSetupPageState();
}

class _LimousineBusinessSetupPageState
    extends State<LimousineBusinessSetupPage> {
  final _scroll = ScrollController();
  final _sectionKeys = <LimousineBusinessSetupSection, GlobalKey>{
    for (final section in LimousineBusinessSetupSection.values)
      section: GlobalKey(),
  };
  final _hourlyKey = GlobalKey();
  final _advancedKey = GlobalKey();

  late List<VehicleProfile> _vehicles;
  final List<Map<String, dynamic>> _offers = <Map<String, dynamic>>[];
  late final LimousineLocalizedField _publicTitle;
  late final LimousineLocalizedField _publicDescription;

  bool _sectionEnabled = false;
  String _currency = 'EUR';
  int _revision = 0;
  bool _dirty = false;
  bool _saving = false;
  bool _loading = false;
  bool _advancedOpen = false;
  int _editEpoch = 0;
  int _saveEpoch = 0;
  String? _status;
  String? _error;
  String _publicLang = 'nl';
  LimousineBusinessSetupPreviewTab _previewTab =
      LimousineBusinessSetupPreviewTab.limousine;

  AppLanguage get _lang => widget.language ?? appLanguageNotifier.value;
  String _t(LocalizedText text) => text.of(_lang);

  List<String> get _knownClasses =>
      widget.knownClassIds ??
      appConfig.enabledLimousineServiceClasses
          .map((item) => item.id)
          .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _vehicles = List<VehicleProfile>.from(
      widget.vehicles ?? vehiclesNotifier.value,
    );
    _publicTitle = LimousineLocalizedField(const <String, String>{});
    _publicDescription = LimousineLocalizedField(const <String, String>{});
    _publicLang = switch (_lang) {
      AppLanguage.en => 'en',
      AppLanguage.fr => 'fr',
      AppLanguage.es => 'es',
      _ => 'nl',
    };
    if (widget.vehicles == null) {
      vehiclesNotifier.addListener(_onVehicles);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void dispose() {
    if (widget.vehicles == null) {
      vehiclesNotifier.removeListener(_onVehicles);
    }
    _scroll.dispose();
    _publicTitle.dispose();
    _publicDescription.dispose();
    super.dispose();
  }

  void _onVehicles() {
    if (!mounted || widget.vehicles != null) return;
    setState(() {
      _vehicles = List<VehicleProfile>.from(vehiclesNotifier.value);
    });
  }

  void _markDirty() {
    _editEpoch += 1;
    if (!_dirty) {
      setState(() => _dirty = true);
    } else {
      setState(() {});
    }
    _status = null;
  }

  LimousineUxTokens get _tokens {
    if (widget.backgroundColor != null) {
      return LimousineUxTokens.fromSurface(background: widget.backgroundColor!);
    }
    final palette = paletteForBusinessTheme(businessThemeNotifier.value);
    return LimousineUxTokens.fromSurface(
      background: palette.background,
      gold: palette.accent,
    );
  }

  LimousineBusinessSetupReadiness get _readiness {
    return limousineBusinessSetupReadiness(
      vehicles: _vehicles,
      offers: _offers,
      publicTitle: _publicTitle.toJson(),
      publicDescription: _publicDescription.toJson(),
      knownClassIds: _knownClasses,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader = widget.loadPricing ?? () => fetchAdminLimousinePricing();
      final data = await loader();
      if (!mounted) return;
      final section = (data['limousine'] is Map)
          ? Map<String, dynamic>.from(data['limousine'] as Map)
          : <String, dynamic>{};
      final offers = (section['offers'] is List)
          ? (section['offers'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _offers
          ..clear()
          ..addAll(offers);
        _sectionEnabled = section['enabled'] == true;
        _currency = limousineCurrencyOf(section['currency']).isEmpty
            ? 'EUR'
            : limousineCurrencyOf(section['currency']);
        _revision = int.tryParse('${section['source_revision'] ?? 0}') ?? 0;
        _dirty = false;
        _seedPublicText();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = limousineFriendlyCompanyError(error, language: _lang);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _seedPublicText() {
    if (_offers.isEmpty) return;
    final first = _offers.first;
    final title = limousineLocalizedOf(first['title']);
    final description = limousineLocalizedOf(first['description']);
    for (final lang in const ['nl', 'en', 'fr', 'es']) {
      if (_publicTitle.controllers[lang]!.text.trim().isEmpty) {
        _publicTitle.controllers[lang]!.text = title[lang] ?? '';
      }
      if (_publicDescription.controllers[lang]!.text.trim().isEmpty) {
        _publicDescription.controllers[lang]!.text = description[lang] ?? '';
      }
    }
  }

  Future<void> _persist({required bool publish}) async {
    if (_saving) return;
    if (publish &&
        !limousineBusinessSetupPublishAllowed(
          saving: false,
          readiness: _readiness,
        )) {
      setState(() {
        _error = _t(kLimousineRequestIncompleteHint);
      });
      return;
    }
    if (!publish &&
        !limousineBusinessSetupDraftSaveAllowed(dirty: _dirty, saving: false)) {
      return;
    }
    final startedAt = _editEpoch;
    final saveId = ++_saveEpoch;
    _saving = true;
    setState(() {
      _error = null;
      _status = null;
    });
    try {
      _applyPublicTextToOffers();
      final offers = publish
          ? limousinePreparePublishOffers(
              _offers,
              vehicles: _vehicles,
              knownClassIds: _knownClasses,
            )
          : limousinePrepareDraftOffers(_offers);
      final payload = <String, dynamic>{
        'enabled': publish ? true : _sectionEnabled,
        'currency': _currency,
        'source_revision': _revision,
        'offers': offers,
      };
      final saver =
          widget.savePricing ?? (section) => saveAdminLimousinePricing(section);
      final data = await saver(payload);
      if (!mounted || saveId != _saveEpoch) return;
      if (startedAt != _editEpoch) {
        setState(() {
          _saving = false;
          _status = _t(kLimousineBusinessSetupUnsaved);
        });
        return;
      }
      final section = (data['limousine'] is Map)
          ? Map<String, dynamic>.from(data['limousine'] as Map)
          : <String, dynamic>{};
      setState(() {
        _offers
          ..clear()
          ..addAll(offers.map((offer) => Map<String, dynamic>.from(offer)));
        _revision =
            int.tryParse('${section['source_revision'] ?? _revision}') ??
            _revision;
        _sectionEnabled = publish ? true : _sectionEnabled;
        _dirty = false;
        _status = publish
            ? (widget.entryEnabled
                  ? _t(kLimousineBusinessSetupPublishedLocal)
                  : _t(kLimousineBusinessSetupTestMessage))
            : _t(kLimousineBusinessSetupDraftSaved);
      });
    } catch (error) {
      if (!mounted || saveId != _saveEpoch) return;
      setState(() {
        _error = limousineFriendlyCompanyError(error, language: _lang);
        _status = null;
      });
    } finally {
      if (mounted && saveId == _saveEpoch) {
        setState(() => _saving = false);
      }
    }
  }

  void _applyPublicTextToOffers() {
    final title = _publicTitle.toJson();
    final description = _publicDescription.toJson();
    for (var i = 0; i < _offers.length; i++) {
      final offer = Map<String, dynamic>.from(_offers[i]);
      final existingTitle = limousineLocalizedOf(offer['title']);
      final existingDescription = limousineLocalizedOf(offer['description']);
      offer['title'] = <String, String>{
        for (final lang in const ['nl', 'en', 'fr', 'es'])
          lang: (existingTitle[lang] ?? '').trim().isEmpty
              ? (title[lang] ?? '')
              : existingTitle[lang]!,
      };
      offer['description'] = <String, String>{
        for (final lang in const ['nl', 'en', 'fr', 'es'])
          lang: (existingDescription[lang] ?? '').trim().isEmpty
              ? (description[lang] ?? '')
              : existingDescription[lang]!,
      };
      _offers[i] = offer;
    }
  }

  Future<void> _editOffer({int? index, String? presentation}) async {
    final existing = index == null
        ? limousineSimpleOfferDraft(
            presentation:
                presentation ?? LimousinePricePresentation.quoteRequired,
            currency: _currency,
            serviceClassId: _knownClasses.isEmpty ? '' : _knownClasses.first,
            title: _publicTitle.toJson(),
            description: _publicDescription.toJson(),
            hourlyEnabled:
                presentation == LimousineJourneyTypeId.hourlyPackage ||
                presentation == 'hourly',
          )
        : Map<String, dynamic>.from(_offers[index]);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => LimousineOfferEditorDialog(
        initialOffer: existing,
        vehicles: limousineSetupLimousineVehicles(_vehicles),
        currency: _currency,
        language: _lang,
        backgroundColor: _tokens.background,
        allowIncompleteDraft: true,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _offers.add(result);
      } else {
        _offers[index] = result;
      }
    });
    _markDirty();
  }

  void _upsertSimpleOffer(String presentation, {bool hourly = false}) {
    final index = _offers.indexWhere((offer) {
      if (hourly) return _mapEnabled(offer['hourly']);
      return limousineOfferToken(offer['price_presentation']) == presentation;
    });
    if (index >= 0) {
      unawaited(_editOffer(index: index));
      return;
    }
    setState(() {
      _offers.add(
        limousineSimpleOfferDraft(
          presentation: presentation,
          currency: _currency,
          serviceClassId: _knownClasses.isEmpty ? '' : _knownClasses.first,
          title: _publicTitle.toJson(),
          description: _publicDescription.toJson(),
          hourlyEnabled: hourly,
          displayAmountCents:
              presentation == LimousinePricePresentation.fromPrice
              ? 25000
              : null,
        ),
      );
    });
    _markDirty();
  }

  bool _mapEnabled(Object? raw) => raw is Map && raw['enabled'] == true;

  void _setVehicleLimousine(VehicleProfile vehicle, bool enabled) {
    final classId = enabled
        ? (limousineOfferToken(vehicle.serviceClassId).isEmpty
              ? (_knownClasses.isEmpty ? '' : _knownClasses.first)
              : vehicle.serviceClassId)
        : '';
    final updated = vehicle.copyWith(
      serviceCategory: enabled ? 'limousine' : '',
      serviceClassId: classId,
    );
    _replaceVehicle(updated);
  }

  void _setVehicleClass(VehicleProfile vehicle, String classId) {
    _replaceVehicle(
      vehicle.copyWith(serviceCategory: 'limousine', serviceClassId: classId),
    );
  }

  void _replaceVehicle(VehicleProfile updated) {
    setState(() {
      _vehicles = _vehicles
          .map((vehicle) => vehicle.id == updated.id ? updated : vehicle)
          .toList(growable: false);
    });
    if (widget.vehicles == null) {
      updateVehicle(updated.id, updated);
    }
    _markDirty();
  }

  Future<void> _openVehicleSetup() async {
    final custom = widget.onConfigureVehicle;
    if (custom != null) {
      custom();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const VehicleManagementPage()),
    );
    if (!mounted) return;
    _onVehicles();
  }

  void _scrollTo(LimousineBusinessSetupSection section) {
    final key = _sectionKeys[section];
    final context = key?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 280),
      alignment: 0.08,
    );
  }

  void _scrollToKey(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 280),
      alignment: 0.08,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _tokens;
    final tablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    return Theme(
      data: limousineUxThemeData(tokens),
      child: Scaffold(
        key: kLimousineBusinessSetupPageKey,
        backgroundColor: tokens.background,
        appBar: AppBar(
          backgroundColor: tokens.surface,
          foregroundColor: tokens.onSurface,
          title: Text(_t(kLimousineBusinessSetupTitle)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                key: kLimousineBusinessSetupTestBadgeKey,
                avatar: Icon(
                  Icons.science_outlined,
                  color: tokens.gold,
                  size: 16,
                ),
                label: Text(_t(kLimousineBusinessSetupTestBadge)),
                side: BorderSide(color: tokens.gold),
                backgroundColor: tokens.surfaceAlt,
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: KeyedSubtree(
            key: tablet
                ? kLimousineBusinessSetupTabletLayoutKey
                : kLimousineBusinessSetupPhoneLayoutKey,
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: limousineBusinessSetupContentWidth(
                          MediaQuery.sizeOf(context).width,
                        ),
                      ),
                      child: SingleChildScrollView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _hero(tokens),
                            const SizedBox(height: 16),
                            _sectionCard(
                              tokens,
                              section: LimousineBusinessSetupSection.vehicles,
                              index: 1,
                              hint: _t(kLimousineBusinessSetupVehiclesHint),
                              child: _vehiclesBody(tokens),
                            ),
                            const SizedBox(height: 16),
                            _sectionCard(
                              tokens,
                              section: LimousineBusinessSetupSection.offers,
                              index: 2,
                              child: _offersBody(tokens),
                            ),
                            const SizedBox(height: 16),
                            _sectionCard(
                              tokens,
                              section: LimousineBusinessSetupSection.publicText,
                              index: 3,
                              child: _publicBody(tokens, tablet),
                            ),
                            const SizedBox(height: 16),
                            _sectionCard(
                              tokens,
                              section: LimousineBusinessSetupSection.review,
                              index: 4,
                              child: _reviewBody(tokens),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                _footer(tokens),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hero(LimousineUxTokens tokens) {
    final readiness = _readiness;
    return Container(
      key: kLimousineBusinessSetupHeroKey,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.gold.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: tokens.gold, width: 2),
                ),
                child: Icon(Icons.directions_car_filled, color: tokens.gold),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      limousineBusinessSetupProfilePercent(
                        readiness.progress,
                        _lang,
                      ),
                      style: TextStyle(
                        color: tokens.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _t(
                        limousineBusinessSetupProgressCopy(readiness.progress),
                      ),
                      style: TextStyle(color: tokens.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: readiness.progress,
              minHeight: 8,
              color: tokens.gold,
              backgroundColor: tokens.border,
            ),
          ),
          if (_dirty)
            Padding(
              key: kLimousineBusinessSetupDirtyKey,
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _t(kLimousineBusinessSetupUnsaved),
                style: TextStyle(
                  color: tokens.gold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionCard(
    LimousineUxTokens tokens, {
    required LimousineBusinessSetupSection section,
    required int index,
    required Widget child,
    String? hint,
  }) {
    return Container(
      key: _sectionKeys[section],
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.gold.withOpacity(0.28)),
      ),
      child: Column(
        key: limousineBusinessSetupSectionKey(section),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: tokens.gold,
                foregroundColor: tokens.isDark
                    ? const Color(0xFF14110C)
                    : const Color(0xFF1A1408),
                child: Text(
                  '$index',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _t(limousineBusinessSetupSectionLabel(section)),
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint, style: TextStyle(color: tokens.muted, fontSize: 12.5)),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _vehiclesBody(LimousineUxTokens tokens) {
    return Column(
      key: kLimousineBusinessSetupVehiclesKey,
      children: [
        for (final vehicle in _vehicles) _vehicleRow(tokens, vehicle),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _openVehicleSetup,
          icon: const Icon(Icons.chevron_right),
          label: Text(_t(kLimousineBusinessSetupConfigureVehicle)),
        ),
      ],
    );
  }

  Widget _vehicleRow(LimousineUxTokens tokens, VehicleProfile vehicle) {
    final flags = limousineVehicleServiceFlags(vehicle);
    return Container(
      key: limousineBusinessSetupVehicleKey(vehicle.id),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            vehicle.vehicleName.isEmpty
                ? vehicle.brandModel
                : vehicle.vehicleName,
            style: TextStyle(
              color: tokens.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (flags.taxi) _badge(tokens, _t(kLimousineBusinessSetupTaxi)),
              if (flags.limousine)
                _badge(tokens, _t(kLimousineBusinessSetupLimousine)),
              Text(
                '${vehicle.passengerCapacity} · ${vehicle.luggageCapacity}',
                style: TextStyle(color: tokens.muted, fontSize: 12),
              ),
            ],
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: flags.limousine,
            activeColor: tokens.gold,
            title: Text(_t(kLimousineBusinessSetupLimousine)),
            onChanged: (value) => _setVehicleLimousine(vehicle, value == true),
          ),
          if (flags.limousine && _knownClasses.isNotEmpty)
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: _knownClasses.contains(vehicle.serviceClassId)
                  ? vehicle.serviceClassId
                  : _knownClasses.first,
              items: [
                for (final id in _knownClasses)
                  DropdownMenuItem<String>(
                    value: id,
                    child: Text(
                      limousineServiceClassLabel(id, _lang),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) _setVehicleClass(vehicle, value);
              },
            ),
        ],
      ),
    );
  }

  Widget _badge(LimousineUxTokens tokens, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tokens.gold.withOpacity(0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.gold.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tokens.gold,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _offersBody(LimousineUxTokens tokens) {
    return Column(
      key: kLimousineBusinessSetupOffersKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _simpleCard(
              tokens,
              presentation: LimousinePricePresentation.quoteRequired,
              title: _t(kLimousineBusinessSetupQuoteCard),
              hint: _t(kLimousineBusinessSetupQuoteHint),
              icon: Icons.description_outlined,
            ),
            _simpleCard(
              tokens,
              presentation: LimousinePricePresentation.fromPrice,
              title: _t(kLimousineBusinessSetupFromCard),
              hint: '€ 250',
              icon: Icons.sell_outlined,
            ),
            _simpleCard(
              tokens,
              presentation: LimousinePricePresentation.exactFixed,
              title: _t(kLimousineBusinessSetupFixedCard),
              hint: _t(kLimousineBusinessSetupFixedCard),
              icon: Icons.price_check_outlined,
            ),
            _simpleCard(
              tokens,
              presentation: LimousineJourneyTypeId.hourlyPackage,
              title: _t(kLimousineBusinessSetupHourlyCard),
              hint: _t(kLimousineBusinessSetupHourlyCard),
              icon: Icons.schedule_outlined,
              hourly: true,
            ),
          ],
        ),
        if (_hourlyErrors().isNotEmpty)
          Padding(
            key: _hourlyKey,
            padding: const EdgeInsets.only(top: 8),
            child: InkWell(
              onTap: () {
                setState(() => _advancedOpen = true);
                _scrollToKey(_hourlyKey);
              },
              child: Text(
                _hourlyErrors()
                    .map((code) => limousineOfferErrorLabel(code, _lang))
                    .join('\n'),
                style: TextStyle(color: tokens.danger, fontSize: 12.5),
              ),
            ),
          ),
        const SizedBox(height: 8),
        ExpansionTile(
          key: kLimousineBusinessSetupAdvancedKey,
          initiallyExpanded: _advancedOpen,
          onExpansionChanged: (open) => setState(() => _advancedOpen = open),
          title: Text(_t(kLimousineBusinessSetupAdvanced)),
          children: [
            KeyedSubtree(
              key: _advancedKey,
              child: Column(
                children: [
                  for (var i = 0; i < _offers.length; i++)
                    ListTile(
                      title: Text(
                        limousineLocalizedFor(
                              _offers[i]['title'],
                              _lang,
                            ).isEmpty
                            ? '${_offers[i]['offer_id']}'
                            : limousineLocalizedFor(_offers[i]['title'], _lang),
                      ),
                      subtitle: Text(
                        limousinePresentationLabel(
                          limousineOfferToken(_offers[i]['price_presentation']),
                          _lang,
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: _saving ? null : () => _editOffer(index: i),
                        child: Text(_t(kLimousineBusinessSetupEdit)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _saving ? null : () => _editOffer(),
            icon: const Icon(Icons.add),
            label: Text(_t(kLimousineBusinessSetupAddOffer)),
          ),
        ),
      ],
    );
  }

  List<String> _hourlyErrors() {
    final errors = <String>{};
    for (final offer in _offers) {
      if (!_mapEnabled(offer['hourly'])) continue;
      errors.addAll(
        limousineBusinessSetupOfferErrors(
          offer,
          vehicles: _vehicles,
          knownClassIds: _knownClasses,
        ).where(
          (code) =>
              code == LimousineOfferError.hourlyIncomplete ||
              code == LimousineOfferError.hourlyMissingMinimumDuration,
        ),
      );
    }
    return errors.toList(growable: false);
  }

  Widget _simpleCard(
    LimousineUxTokens tokens, {
    required String presentation,
    required String title,
    required String hint,
    required IconData icon,
    bool hourly = false,
  }) {
    final exists = _offers.any((offer) {
      if (hourly) return _mapEnabled(offer['hourly']);
      return limousineOfferToken(offer['price_presentation']) == presentation;
    });
    return SizedBox(
      width: 220,
      child: Material(
        key: limousineBusinessSetupOfferCardKey(presentation),
        color: tokens.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _upsertSimpleOffer(presentation, hourly: hourly),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: tokens.gold),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(hint, style: TextStyle(color: tokens.muted, fontSize: 12)),
                if (exists)
                  TextButton(
                    onPressed: () =>
                        _upsertSimpleOffer(presentation, hourly: hourly),
                    child: Text(_t(kLimousineBusinessSetupEdit)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _publicBody(LimousineUxTokens tokens, bool tablet) {
    final editor = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final lang in const ['nl', 'en', 'fr', 'es'])
              ChoiceChip(
                key: limousineBusinessSetupPublicLangKey(lang),
                label: Text(lang.toUpperCase()),
                selected: _publicLang == lang,
                onSelected: (_) => setState(() => _publicLang = lang),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          key: kLimousineBusinessSetupPublicTitleKey,
          controller: _publicTitle.controllers[_publicLang],
          decoration: InputDecoration(
            labelText: _t(kLimousineBusinessSetupTitleField),
          ),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 10),
        TextField(
          key: kLimousineBusinessSetupPublicDescriptionKey,
          controller: _publicDescription.controllers[_publicLang],
          minLines: 3,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: _t(kLimousineBusinessSetupDescriptionField),
          ),
          onChanged: (_) => _markDirty(),
        ),
      ],
    );
    final preview = _preview(tokens);
    if (!tablet) {
      return Column(
        key: kLimousineBusinessSetupPublicKey,
        children: [editor, const SizedBox(height: 12), preview],
      );
    }
    return Row(
      key: kLimousineBusinessSetupPublicKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: editor),
        const SizedBox(width: 16),
        Expanded(child: preview),
      ],
    );
  }

  Widget _preview(LimousineUxTokens tokens) {
    final safeOffers = widget.entryEnabled
        ? limousineSafeSetupPreviewOffers(
            offers: _offers,
            vehicles: _vehicles,
            knownClassIds: _knownClasses,
            sectionEnabled: _sectionEnabled,
          )
        : const <Map<String, dynamic>>[];
    final taxiVehicles = limousineSetupTaxiVehicles(_vehicles);
    final limousineVehicles = limousineSetupLimousineVehicles(_vehicles);
    return Container(
      key: kLimousineBusinessSetupPreviewKey,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.companyName.isEmpty
                ? _publicTitle.controllers[_publicLang]!.text
                : widget.companyName,
            style: TextStyle(
              color: tokens.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _t(kLimousineBusinessSetupPreviewHint),
            style: TextStyle(color: tokens.muted, fontSize: 11.5),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (final tab in LimousineBusinessSetupPreviewTab.values)
                ChoiceChip(
                  key: limousineBusinessSetupPreviewTabKey(tab),
                  label: Text(
                    tab == LimousineBusinessSetupPreviewTab.taxi
                        ? _t(kLimousineBusinessSetupTaxi)
                        : tab == LimousineBusinessSetupPreviewTab.airport
                        ? _t(kLimousineBusinessSetupAirport)
                        : _t(kLimousineBusinessSetupLimousine),
                  ),
                  selected: _previewTab == tab,
                  onSelected: (_) => setState(() => _previewTab = tab),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_previewTab == LimousineBusinessSetupPreviewTab.taxi)
            ...taxiVehicles.map(
              (vehicle) => Text(
                vehicle.vehicleName.isEmpty
                    ? vehicle.brandModel
                    : vehicle.vehicleName,
                style: TextStyle(color: tokens.onSurface),
              ),
            ),
          if (_previewTab == LimousineBusinessSetupPreviewTab.airport)
            Text(
              _t(kLimousineBusinessSetupAirport),
              style: TextStyle(color: tokens.muted),
            ),
          if (_previewTab == LimousineBusinessSetupPreviewTab.limousine) ...[
            ...limousineVehicles.map(
              (vehicle) => Text(
                vehicle.vehicleName.isEmpty
                    ? vehicle.brandModel
                    : vehicle.vehicleName,
                style: TextStyle(color: tokens.onSurface),
              ),
            ),
            ...safeOffers.map(
              (offer) => Text(
                limousineLocalizedFor(offer['title'], _lang),
                style: TextStyle(color: tokens.muted, fontSize: 12.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reviewBody(LimousineUxTokens tokens) {
    final readiness = _readiness;
    return Column(
      key: kLimousineBusinessSetupReviewKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in readiness.items)
          ListTile(
            key: limousineBusinessSetupChecklistKey(item.code),
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              item.complete ? Icons.check_circle : Icons.circle_outlined,
              color: item.complete ? const Color(0xFF34D29A) : tokens.muted,
            ),
            title: Text(_t(limousineBusinessSetupChecklistLabel(item.code))),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _scrollTo(item.section),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.warning_amber_rounded, color: tokens.gold),
          title: Text(_t(kLimousineBusinessSetupTestMessage)),
          subtitle: Text(_t(kLimousineBusinessSetupTestHint)),
        ),
        if (_status != null)
          Text(
            _status!,
            key: kLimousineBusinessSetupStatusKey,
            style: const TextStyle(color: Color(0xFF34D29A)),
          ),
        if (_error != null)
          Text(
            _error!,
            key: kLimousineBusinessSetupErrorKey,
            style: TextStyle(color: tokens.danger),
          ),
        if (_loading)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(color: tokens.gold),
          ),
      ],
    );
  }

  Widget _footer(LimousineUxTokens tokens) {
    final draftOk = limousineBusinessSetupDraftSaveAllowed(
      dirty: _dirty,
      saving: _saving,
    );
    final publishOk = limousineBusinessSetupPublishAllowed(
      saving: _saving,
      readiness: _readiness,
    );
    return Material(
      key: kLimousineBusinessSetupFooterKey,
      color: tokens.surface,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: kLimousineBusinessSetupDraftSaveKey,
                onPressed: draftOk ? () => _persist(publish: false) : null,
                icon: const Icon(Icons.save_outlined),
                label: Text(_t(kLimousineBusinessSetupDraftSave)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: kLimousineBusinessSetupPublishKey,
                onPressed: publishOk ? () => _persist(publish: true) : null,
                icon: const Icon(Icons.rocket_launch_outlined),
                label: Text(_t(kLimousineBusinessSetupPublish)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void openLimousineBusinessSetup(
  BuildContext context, {
  AppLanguage? language,
  Color? backgroundColor,
  String companyName = '',
  bool entryEnabled = false,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LimousineBusinessSetupPage(
        language: language,
        backgroundColor: backgroundColor,
        companyName: companyName,
        entryEnabled: entryEnabled,
      ),
    ),
  );
}
