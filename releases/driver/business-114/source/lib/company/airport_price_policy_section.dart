import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/airport_price_policy.dart';
import 'package:fluxidi_tracking/company/company_fixed_price_labels.dart';

class AirportPricePolicySection extends StatefulWidget {
  const AirportPricePolicySection({
    super.key,
    required this.language,
    required this.loader,
    required this.saver,
  });

  final AppLanguage language;
  final Future<Map<String, dynamic>> Function() loader;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> profile)
      saver;

  @override
  State<AirportPricePolicySection> createState() =>
      _AirportPricePolicySectionState();
}

class _AirportPricePolicySectionState extends State<AirportPricePolicySection> {
  final _lead = TextEditingController();
  Map<String, dynamic> _stored = <String, dynamic>{};
  bool _loading = true;
  bool _saving = false;
  bool _autoCalc = true;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _lead.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _status = null;
    });
    try {
      final profile = await widget.loader();
      if (!mounted) return;
      _apply(profile);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = kAirportPricePolicyLoadFailed.of(widget.language);
        _status = null;
      });
    }
  }

  void _apply(Map<String, dynamic> profile) {
    final view = readAirportPricePolicy(profile);
    _stored = Map<String, dynamic>.from(profile);
    _autoCalc = view.autoCalcEnabled;
    _lead.text = view.minLeadText;
    _rememberProfile(profile);
    setState(() {
      _loading = false;
      _error = null;
    });
  }

  void _rememberProfile(Map<String, dynamic> saved) {
    final cached = localBackendBusinessProfileNotifier.value;
    if (cached == null) return;
    final merged = <String, dynamic>{...cached.toJson(), ...saved};
    localBackendBusinessProfileNotifier.value =
        BackendBusinessProfile.fromJson(merged);
  }

  Future<void> _save() async {
    final write = buildAirportPricePolicyProfile(
      stored: _stored,
      autoCalcEnabled: _autoCalc,
      leadText: _lead.text,
    );
    if (write.invalidLead) {
      setState(() {
        _error = kAirportMinLeadInvalid.of(widget.language);
        _status = null;
      });
      return;
    }
    if (write.unchanged || write.profile == null) return;
    setState(() {
      _saving = true;
      _error = null;
      _status = null;
    });
    try {
      final saved = await widget.saver(write.profile!);
      if (!mounted) return;
      _apply(saved);
      setState(() {
        _status = kAirportPricePolicySaved.of(widget.language);
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = kAirportPricePolicySaveFailed.of(widget.language);
        _status = null;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.language;
    return RepaintBoundary(
      key: kAirportPricePolicyCardKey,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: _loading
              ? const SizedBox(
                  height: 72,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      key: kAirportAutoCalcSwitchKey,
                      contentPadding: EdgeInsets.zero,
                      title: Text(kAirportAutoCalcTitle.of(lang)),
                      subtitle: Text(
                        kAirportAutoCalcHelp.of(lang),
                        softWrap: true,
                      ),
                      value: _autoCalc,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() {
                                _autoCalc = value;
                                _status = null;
                              }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      kAirportMinLeadTitle.of(lang),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      kAirportMinLeadHelp.of(lang),
                      softWrap: true,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: kAirportMinLeadFieldKey,
                      controller: _lead,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9.,]'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: kAirportMinLeadTitle.of(lang),
                        helperText: kAirportMinLeadHint.of(lang),
                        helperMaxLines: 3,
                        suffixText: 'u',
                      ),
                      onChanged: (_) {
                        if (_status != null) setState(() => _status = null);
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        key: kAirportPricePolicyErrorKey,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (_status != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _status!,
                        key: kAirportPricePolicyStatusKey,
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: kAirportPricePolicySaveKey,
                        onPressed: _saving ? null : _save,
                        child: Text(
                          _saving
                              ? kAirportPricePolicySaving.of(lang)
                              : kAirportPricePolicySave.of(lang),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
