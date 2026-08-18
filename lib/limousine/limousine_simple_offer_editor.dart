// Mode-specific Limousine offer editors. They write the existing offer DTO
// and hide fields that do not belong to the selected pricing mode.

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import 'limousine_business_setup.dart';
import 'limousine_business_setup_labels.dart';
import 'limousine_offers.dart';
import 'limousine_p2d4c1a_ux.dart';

int? _centsFromText(String raw) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null) return null;
  return (value * 100).round();
}

String _textFromCents(int? cents) =>
    cents == null ? '' : (cents / 100).toStringAsFixed(2);

int? _intFromText(String raw) => int.tryParse(raw.trim());

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
  late String _targetType;
  late String _vehicleId;
  late String _serviceClassId;
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

  String _t(LocalizedText text) => text.of(widget.language);

  @override
  void initState() {
    super.initState();
    final offer = widget.initialOffer;
    final hourly = (offer['hourly'] is Map)
        ? Map<String, dynamic>.from(offer['hourly'] as Map)
        : <String, dynamic>{};
    _enabled = offer['enabled'] != false;
    _published = offer['published'] == true;
    _targetType = limousineOfferToken(offer['target_type']).isEmpty
        ? LimousineOfferTarget.serviceClass
        : limousineOfferToken(offer['target_type']);
    _vehicleId = (offer['vehicle_id'] ?? '').toString();
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
    _minDuration = TextEditingController(
      text: '${hourly['minimum_duration_minutes'] ?? ''}',
    );
    _packageDuration = TextEditingController(
      text: '${hourly['package_duration_minutes'] ?? ''}',
    );
    _packageAmount = TextEditingController(
      text: _textFromCents(limousineCentsOf(hourly['package_amount_cents'])),
    );
    _includedHours = TextEditingController(
      text: '${hourly['included_hours'] ?? ''}',
    );
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
    }
  }

  void _submit() {
    final draft = LimousineSimpleOfferDraft(
      mode: widget.mode,
      enabled: _enabled,
      published: _published,
      amountCents: _centsFromText(_amount.text),
      currency: widget.currency,
      targetType: _targetType,
      vehicleId: _vehicleId,
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
    );
    final next = limousineApplySimpleOfferEdits(widget.initialOffer, draft);
    if (_enabled) {
      final errors = limousineBusinessSetupOfferErrors(
        next,
        vehicles: widget.vehicles,
        knownClassIds: widget.knownClassIds,
      );
      final blocking = errors.where((code) {
        if (widget.mode == LimousineSimpleOfferMode.quote) {
          return code == LimousineOfferError.unknownServiceClass ||
              code == LimousineOfferError.unknownVehicle ||
              code == LimousineOfferError.vehicleNotLimousine;
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
                              errorText: _fieldError,
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
                        if (widget.mode == LimousineSimpleOfferMode.hourly) ...[
                          TextField(
                            key: kLimousineSimpleOfferFirstHourKey,
                            controller: _firstHour,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: _t(kLimousineBusinessSetupFirstHour),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _extraHour,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: _t(kLimousineBusinessSetupExtraHour),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _minDuration,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: _t(kLimousineBusinessSetupMinDuration),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _packageDuration,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: _t(
                                kLimousineBusinessSetupPackageDuration,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _packageAmount,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: _t(
                                kLimousineBusinessSetupPackageAmount,
                              ),
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
                        const SizedBox(height: 12),
                        Text(
                          _t(kLimousineBusinessSetupTarget),
                          style: TextStyle(
                            color: tokens.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: Text(_t(kLimousineBusinessSetupClass)),
                              selected:
                                  _targetType ==
                                  LimousineOfferTarget.serviceClass,
                              onSelected: (_) => setState(() {
                                _targetType = LimousineOfferTarget.serviceClass;
                              }),
                            ),
                            ChoiceChip(
                              label: Text(_t(kLimousineBusinessSetupVehicle)),
                              selected:
                                  _targetType == LimousineOfferTarget.vehicle,
                              onSelected: (_) => setState(() {
                                _targetType = LimousineOfferTarget.vehicle;
                                if (_vehicleId.isEmpty &&
                                    widget.vehicles.isNotEmpty) {
                                  _vehicleId = widget.vehicles.first.id;
                                }
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_targetType == LimousineOfferTarget.serviceClass &&
                            widget.knownClassIds.isNotEmpty)
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            value:
                                widget.knownClassIds.contains(_serviceClassId)
                                ? _serviceClassId
                                : widget.knownClassIds.first,
                            items: [
                              for (final id in widget.knownClassIds)
                                DropdownMenuItem<String>(
                                  value: id,
                                  child: Text(
                                    limousineServiceClassLabel(
                                      id,
                                      widget.language,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _serviceClassId = value);
                              }
                            },
                          ),
                        if (_targetType == LimousineOfferTarget.vehicle &&
                            widget.vehicles.isNotEmpty)
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            value:
                                widget.vehicles.any((v) => v.id == _vehicleId)
                                ? _vehicleId
                                : widget.vehicles.first.id,
                            items: [
                              for (final vehicle in widget.vehicles)
                                DropdownMenuItem<String>(
                                  value: vehicle.id,
                                  child: Text(
                                    vehicle.vehicleName.isEmpty
                                        ? vehicle.brandModel
                                        : vehicle.vehicleName,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _vehicleId = value);
                              }
                            },
                          ),
                        if (widget.mode != LimousineSimpleOfferMode.hourly) ...[
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
                        if (_fieldError != null &&
                            widget.mode == LimousineSimpleOfferMode.quote)
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
