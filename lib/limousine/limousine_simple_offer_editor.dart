// Mode-specific Limousine offer editors. They write the existing offer DTO
// and hide fields that do not belong to the selected pricing mode.

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import 'limousine_business_setup.dart';
import 'limousine_business_setup_labels.dart';
import 'limousine_customer_discovery_labels.dart';
import 'limousine_offer_binding.dart';
import 'limousine_offers.dart';
import 'limousine_p2d4c1a_ux.dart';

int? _centsFromText(String raw) => limousineCentsFromMajorUnitText(raw);

String _textFromCents(int? cents) => limousineMajorUnitTextFromCents(cents);

int? _intFromText(String raw) => limousineMinutesOf(raw);

class LimousineSimpleOfferEditor extends StatefulWidget {
  const LimousineSimpleOfferEditor({
    super.key,
    required this.initialOffer,
    required this.mode,
    required this.vehicles,
    required this.knownClassIds,
    required this.currency,
    required this.language,
    required this.tokens,
    this.primaryLang = 'nl',
  });

  final Map<String, dynamic> initialOffer;
  final LimousineSimpleOfferMode mode;
  final List<VehicleProfile> vehicles;
  final List<String> knownClassIds;
  final String currency;
  final AppLanguage language;
  final LimousineUxTokens tokens;
  final String primaryLang;

  @override
  State<LimousineSimpleOfferEditor> createState() =>
      _LimousineSimpleOfferEditorState();
}

class _LimousineSimpleOfferEditorState
    extends State<LimousineSimpleOfferEditor> {
  late bool _enabled;
  late bool _published;
  late bool _appliesToAll;
  late bool _featured;
  late bool _legacyUnbound;
  late Set<String> _vehicleIds;
  late String _targetType;
  late String _vehicleId;
  late String _serviceClassId;
  late final TextEditingController _sortOrder;
  late Set<String> _journeyTypes;
  late final TextEditingController _amount;
  late final TextEditingController _title;
  late final TextEditingController _terms;
  late final TextEditingController _pickup;
  late final TextEditingController _dropoff;
  late final TextEditingController _firstHour;
  late final TextEditingController _extraHour;
  late final TextEditingController _minDuration;
  late final TextEditingController _packageDuration;
  late final TextEditingController _packageAmount;
  late final TextEditingController _includedHours;
  String? _fieldError;
  Map<String, String> _fieldErrors = const <String, String>{};

  String _t(LocalizedText text) => text.of(widget.language);

  bool get _unresolvedMissingVehicle {
    if (_appliesToAll || _vehicleIds.isNotEmpty) return false;
    return limousineOfferMissingLinkedIds(
      offer: widget.initialOffer,
      vehicles: widget.vehicles,
    ).isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    final offer = widget.initialOffer;
    final hourly = (offer['hourly'] is Map)
        ? Map<String, dynamic>.from(offer['hourly'] as Map)
        : <String, dynamic>{};
    final scope = limousineOfferScopeOf(offer);
    _enabled = offer['enabled'] != false;
    _published = offer['published'] == true;
    _appliesToAll = scope.appliesToAllSelected;
    _featured = scope.featured;
    _legacyUnbound = scope.legacyUnbound;
    final knownIds = <String>{
      for (final vehicle in widget.vehicles) vehicle.id.trim(),
    };
    _vehicleIds = {
      for (final id in scope.vehicleIds)
        if (knownIds.contains(id)) id,
    };
    _targetType = limousineOfferToken(offer['target_type']).isEmpty
        ? LimousineOfferTarget.serviceClass
        : limousineOfferToken(offer['target_type']);
    _vehicleId = _vehicleIds.isEmpty ? '' : _vehicleIds.first;
    _sortOrder = TextEditingController(text: '${scope.sortOrder}');
    _serviceClassId = limousineOfferToken(offer['service_class_id']);
    if (_serviceClassId.isEmpty && widget.knownClassIds.isNotEmpty) {
      _serviceClassId = widget.knownClassIds.first;
    }
    _journeyTypes = <String>{
      ...((offer['journey_types'] as List?) ?? const <dynamic>[])
          .map(limousineOfferToken)
          .where((item) => item.isNotEmpty),
    };
    _amount = TextEditingController(
      text: _textFromCents(limousineCentsOf(offer['display_amount_cents'])),
    );
    _title = TextEditingController(
      text: (limousineLocalizedOf(offer['title'])[widget.primaryLang] ?? ''),
    );
    _terms = TextEditingController(
      text:
          (limousineLocalizedOf(offer['description'])[widget.primaryLang] ??
          ''),
    );
    _pickup = TextEditingController(
      text: (offer['pickup_label'] ?? '').toString(),
    );
    _dropoff = TextEditingController(
      text: (offer['dropoff_label'] ?? '').toString(),
    );
    _firstHour = TextEditingController(
      text: _textFromCents(limousineCentsOf(hourly['first_hour_cents'])),
    );
    _extraHour = TextEditingController(
      text: _textFromCents(limousineCentsOf(hourly['additional_hour_cents'])),
    );
    final minimumMinutes = limousineMinutesOf(
      hourly['minimum_duration_minutes'],
    );
    _minDuration = TextEditingController(
      text: minimumMinutes == null ? '' : '$minimumMinutes',
    );
    final packageMinutes = limousineMinutesOf(
      hourly['package_duration_minutes'],
    );
    _packageDuration = TextEditingController(
      text: packageMinutes == null ? '' : '$packageMinutes',
    );
    _packageAmount = TextEditingController(
      text: _textFromCents(limousineCentsOf(hourly['package_amount_cents'])),
    );
    _includedHours = TextEditingController(
      text: '${hourly['included_hours'] ?? ''}',
    );
    _fieldErrors = limousineBusinessSetupOfferValidation(
      offer,
      mode: widget.mode,
      vehicles: widget.vehicles,
      knownClassIds: widget.knownClassIds,
    ).fieldErrors;
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    _terms.dispose();
    _pickup.dispose();
    _dropoff.dispose();
    _firstHour.dispose();
    _extraHour.dispose();
    _minDuration.dispose();
    _packageDuration.dispose();
    _packageAmount.dispose();
    _includedHours.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  LocalizedText get _modeTitle {
    switch (widget.mode) {
      case LimousineSimpleOfferMode.quote:
        return kLimousineBusinessSetupQuoteCard;
      case LimousineSimpleOfferMode.fromPrice:
        return kLimousineBusinessSetupFromCard;
      case LimousineSimpleOfferMode.fixed:
        return kLimousineBusinessSetupFixedCard;
      case LimousineSimpleOfferMode.hourly:
        return kLimousineBusinessSetupHourlyCard;
      case LimousineSimpleOfferMode.package:
        return kLimousineBusinessSetupPackageCard;
    }
  }

  LimousineSimpleOfferDraft _draftFromControllers() {
    return LimousineSimpleOfferDraft(
      mode: widget.mode,
      enabled: _enabled,
      published: _published,
      amountCents: _centsFromText(_amount.text),
      currency: widget.currency,
      targetType: _targetType,
      vehicleId: _appliesToAll || _vehicleIds.isEmpty ? '' : _vehicleIds.first,
      serviceClassId: _serviceClassId,
      journeyTypes: _journeyTypes.toList(growable: false),
      primaryLang: widget.primaryLang,
      title: _title.text,
      terms: _terms.text,
      pickupLabel: _pickup.text,
      dropoffLabel: _dropoff.text,
      firstHourCents: _centsFromText(_firstHour.text),
      additionalHourCents: _centsFromText(_extraHour.text),
      minimumDurationMinutes: _intFromText(_minDuration.text),
      packageDurationMinutes: _intFromText(_packageDuration.text),
      packageAmountCents: _centsFromText(_packageAmount.text),
      includedHours: _intFromText(_includedHours.text),
      appliesToAllSelected: _appliesToAll,
      vehicleIds: _vehicleIds.toList(growable: false),
      featured: _featured,
      sortOrder: _intFromText(_sortOrder.text) ?? 0,
    );
  }

  String? _errorFor(String field) {
    final code = _fieldErrors[field];
    if (code == null) return null;
    return limousineOfferErrorLabel(code, widget.language);
  }

  void _submit() {
    final draft = _draftFromControllers();
    final next = limousineApplySimpleOfferEdits(widget.initialOffer, draft);
    final validation = limousineBusinessSetupOfferValidation(
      next,
      mode: widget.mode,
      vehicles: widget.vehicles,
      knownClassIds: widget.knownClassIds,
    );
    _fieldErrors = validation.fieldErrors;
    if (_enabled) {
      final errors = limousineBusinessSetupOfferErrors(
        next,
        mode: widget.mode,
        vehicles: widget.vehicles,
        knownClassIds: widget.knownClassIds,
      );
      final blocking = errors.where((code) {
        if (code == LimousineOfferError.unknownVehicle ||
            code == LimousineOfferError.unknownTarget ||
            code == LimousineOfferError.vehicleNotLimousine ||
            code == LimousineOfferError.unknownServiceClass) {
          return true;
        }
        if (widget.mode == LimousineSimpleOfferMode.fromPrice) {
          return code == LimousineOfferError.missingDisplayAmount;
        }
        return false;
      }).toList();
      if (blocking.isNotEmpty) {
        setState(() {
          _fieldError = limousineOfferErrorLabel(
            blocking.first,
            widget.language,
          );
        });
        return;
      }
    }
    Navigator.of(context).pop(next);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    return Theme(
      data: limousineUxThemeData(tokens),
      child: Dialog(
        key: kLimousineSimpleOfferEditorKey,
        backgroundColor: tokens.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _t(_modeTitle),
                    style: TextStyle(
                      color: tokens.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SwitchListTile(
                          key: kLimousineSimpleOfferEnabledKey,
                          contentPadding: EdgeInsets.zero,
                          value: _enabled,
                          activeColor: tokens.gold,
                          title: Text(_t(kLimousineBusinessSetupAvailable)),
                          onChanged: (value) =>
                              setState(() => _enabled = value),
                        ),
                        if (widget.mode != LimousineSimpleOfferMode.quote)
                          SwitchListTile(
                            key: kLimousineSimpleOfferPublishedKey,
                            contentPadding: EdgeInsets.zero,
                            value: _published,
                            activeColor: tokens.gold,
                            title: Text(
                              _t(kLimousineBusinessSetupPublishedStatus),
                            ),
                            onChanged: (value) =>
                                setState(() => _published = value),
                          ),
                        if (widget.mode == LimousineSimpleOfferMode.fixed)
                          TextField(
                            key: kLimousineSimpleOfferNameKey,
                            controller: _title,
                            decoration: InputDecoration(
                              labelText: _t(kLimousineBusinessSetupTitleField),
                            ),
                          ),
                        if (widget.mode == LimousineSimpleOfferMode.quote)
                          TextField(
                            controller: _terms,
                            minLines: 2,
                            maxLines: 4,
                            decoration: InputDecoration(
                              labelText: _t(kLimousineBusinessSetupTerms),
                            ),
                          ),
                        if (widget.mode == LimousineSimpleOfferMode.fromPrice ||
                            widget.mode == LimousineSimpleOfferMode.fixed) ...[
                          const SizedBox(height: 8),
                          TextField(
                            key: kLimousineSimpleOfferAmountKey,
                            controller: _amount,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: _t(kLimousineBusinessSetupAmount),
                              errorText: _errorFor('amount') ?? _fieldError,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_t(kLimousineBusinessSetupCurrency)}: ${widget.currency}',
                            style: TextStyle(color: tokens.muted),
                          ),
                        ],
                        if (widget.mode == LimousineSimpleOfferMode.fixed) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _pickup,
                            decoration: InputDecoration(
                              labelText: _t(kLimousineBusinessSetupPickup),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _dropoff,
                            decoration: InputDecoration(
                              labelText: _t(kLimousineBusinessSetupDropoff),
                            ),
                          ),
                        ],
                        if (widget.mode == LimousineSimpleOfferMode.hourly ||
                            widget.mode ==
                                LimousineSimpleOfferMode.package) ...[
                          TextField(
                            key: kLimousineSimpleOfferFirstHourKey,
                            controller: _firstHour,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: _t(kLimousineBusinessSetupFirstHour),
                              errorText: _errorFor('first_hour'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            key: kLimousineSimpleOfferExtraHourKey,
                            controller: _extraHour,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: _t(kLimousineBusinessSetupExtraHour),
                              errorText: _errorFor('additional_hour'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            key: kLimousineSimpleOfferMinDurationKey,
                            controller: _minDuration,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: _t(kLimousineBusinessSetupMinDuration),
                              errorText: _errorFor('min_duration'),
                            ),
                          ),
                          if (widget.mode ==
                              LimousineSimpleOfferMode.package) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _packageDuration,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: _t(
                                  kLimousineBusinessSetupPackageDuration,
                                ),
                                errorText: _errorFor('package_duration'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _packageAmount,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: _t(
                                  kLimousineBusinessSetupPackageAmount,
                                ),
                                errorText: _errorFor('package_amount'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _includedHours,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: _t(
                                  kLimousineBusinessSetupIncludedHours,
                                ),
                              ),
                            ),
                          ],
                        ],
                        const SizedBox(height: 12),
                        Text(
                          _t(kLimousineBusinessSetupOfferForVehicles),
                          style: TextStyle(
                            color: tokens.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_unresolvedMissingVehicle) ...[
                          const SizedBox(height: 6),
                          Text(
                            key: kLimousineSimpleOfferMissingVehicleKey,
                            _t(kLimousineBusinessSetupOfferMissingVehicle),
                            style: TextStyle(
                              color: tokens.danger,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                        if (_legacyUnbound) ...[
                          const SizedBox(height: 6),
                          Text(
                            _t(kLimousineBusinessSetupOfferLegacyAll),
                            style: TextStyle(
                              color: tokens.muted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                        FilterChip(
                          key: kLimousineSimpleOfferScopeAllKey,
                          label: Text(
                            _t(kLimousineBusinessSetupOfferAllSelected),
                          ),
                          selected: _appliesToAll,
                          onSelected: (selected) => setState(() {
                            _appliesToAll = selected;
                            if (selected) {
                              _vehicleIds.clear();
                              _vehicleId = '';
                            }
                          }),
                        ),
                        const SizedBox(height: 8),
                        KeyedSubtree(
                          key: kLimousineSimpleOfferVehiclePickerKey,
                          child: Column(
                            children: [
                              for (final vehicle in widget.vehicles)
                                CheckboxListTile(
                                  key: limousineSimpleOfferVehicleTileKey(
                                    vehicle.id,
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                  value:
                                      _appliesToAll ||
                                      _vehicleIds.contains(vehicle.id),
                                  onChanged: (value) => setState(() {
                                    _appliesToAll = false;
                                    if (value == true) {
                                      _vehicleIds.add(vehicle.id);
                                      _vehicleId = vehicle.id;
                                    } else {
                                      _vehicleIds.remove(vehicle.id);
                                      _vehicleId = _vehicleIds.isEmpty
                                          ? ''
                                          : _vehicleIds.first;
                                    }
                                  }),
                                  title: Text(
                                    vehicle.vehicleName.isEmpty
                                        ? vehicle.brandModel
                                        : vehicle.vehicleName,
                                  ),
                                  subtitle: Text(
                                    [
                                      if (vehicle.serviceClassId.isNotEmpty)
                                        limousineServiceClassLabel(
                                          vehicle.serviceClassId,
                                          widget.language,
                                        ),
                                      '${vehicle.passengerCapacity} ${kLimousineDiscoveryPassengers.of(widget.language)}',
                                    ].join(' · '),
                                  ),
                                  secondary: SizedBox(
                                    width: 56,
                                    height: 40,
                                    child:
                                        vehicle.publicPhotoUrl != null &&
                                            vehicle.publicPhotoUrl!.startsWith(
                                              'https://',
                                            )
                                        ? Image.network(
                                            vehicle.publicPhotoUrl!,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(
                                                  Icons.directions_car,
                                                ),
                                          )
                                        : const Icon(Icons.directions_car),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (!_unresolvedMissingVehicle &&
                            limousineOfferInactiveLinkedIds(
                              offer: widget.initialOffer,
                              vehicles: widget.vehicles,
                            ).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              _t(kLimousineBusinessSetupOfferInactiveLink),
                              style: TextStyle(
                                color: tokens.danger,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        SwitchListTile(
                          key: kLimousineSimpleOfferFeaturedKey,
                          contentPadding: EdgeInsets.zero,
                          value: _featured,
                          activeColor: tokens.gold,
                          title: Text(_t(kLimousineBusinessSetupOfferFeatured)),
                          onChanged: (value) =>
                              setState(() => _featured = value),
                        ),
                        TextField(
                          controller: _sortOrder,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: _t(
                              kLimousineBusinessSetupOfferSortOrder,
                            ),
                          ),
                        ),
                        if (widget.mode != LimousineSimpleOfferMode.hourly &&
                            widget.mode !=
                                LimousineSimpleOfferMode.package) ...[
                          const SizedBox(height: 12),
                          Text(
                            _t(kLimousineBusinessSetupJourneyTypes),
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
                              for (final type in LimousineJourneyTypeId.all)
                                FilterChip(
                                  label: Text(
                                    limousineJourneyTypeLabel(
                                      type,
                                      widget.language,
                                    ),
                                  ),
                                  selected: _journeyTypes.contains(type),
                                  onSelected: (selected) => setState(() {
                                    if (selected) {
                                      _journeyTypes.add(type);
                                    } else {
                                      _journeyTypes.remove(type);
                                    }
                                  }),
                                ),
                            ],
                          ),
                        ],
                        if (_fieldError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _fieldError!,
                              style: TextStyle(color: tokens.danger),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _submit,
                    child: Text(_t(kLimousineBusinessSetupSave)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
