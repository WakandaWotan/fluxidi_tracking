// COMPANY-CUSTOMER-OPS-P0 — existing /admin/business/profile on Windows.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_locale_options.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_ops_api.dart';
import 'package:fluxidi_tracking/company/company_ops_identity.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';
import 'package:image_picker/image_picker.dart';

const Key kCompanySettingsPageKey = Key('company_settings_page');
const Key kCompanySettingsNameKey = Key('company_settings_name');
const Key kCompanySettingsSaveKey = Key('company_settings_save');
const Key kCompanySettingsLogoKey = Key('company_settings_logo');

class CompanySettingsPage extends StatefulWidget {
  const CompanySettingsPage({
    super.key,
    this.language,
    this.profileLoader,
    this.profileSaver,
    this.onSaved,
  });

  final AppLanguage? language;
  final Future<Map<String, dynamic>> Function()? profileLoader;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> profile)?
      profileSaver;
  final VoidCallback? onSaved;

  @override
  State<CompanySettingsPage> createState() => _CompanySettingsPageState();
}

class _CompanySettingsPageState extends State<CompanySettingsPage> {
  final _name = TextEditingController();
  final _legal = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _logoUrl = TextEditingController();
  String _country = 'BE';
  Map<String, dynamic> _profile = const <String, dynamic>{};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  AppLanguage get _lang => widget.language ?? appLanguageNotifier.value;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _legal.dispose();
    _phone.dispose();
    _email.dispose();
    _logoUrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await (widget.profileLoader ??
          fetchCompanyOpsBusinessProfile)();
      if (!mounted) return;
      _apply(profile);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Bedrijfsprofiel laden mislukt.';
        _loading = false;
      });
    }
  }

  void _apply(Map<String, dynamic> profile) {
    _profile = profile;
    _name.text = _text(profile, const ['companyName', 'company_name', 'trading_name']);
    _legal.text = _text(profile, const ['legalName', 'legal_name']);
    _phone.text = _text(profile, const ['phone']);
    _email.text = _text(profile, const ['email', 'companyEmail', 'company_email']);
    _logoUrl.text = _text(profile, const ['publicLogoUrl', 'public_logo_url']);
    final country = _text(profile, const ['country']);
    setState(() {
      _country = country.isEmpty ? 'BE' : country;
      _loading = false;
    });
  }

  Future<void> _pickLogo() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) return;
      final url = await uploadCompanyOpsPartnerMedia(
        mediaType: 'company_logo',
        bytes: bytes,
        filename: picked.name.isEmpty ? 'logo.png' : picked.name,
        contentType: picked.mimeType,
      );
      if (!mounted) return;
      setState(() => _logoUrl.text = url);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is CompanyCustomerException
            ? error.code
            : 'Logo uploaden mislukt.';
      });
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Bedrijfsnaam is verplicht.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final next = Map<String, dynamic>.from(_profile)
        ..['companyName'] = name
        ..['company_name'] = name
        ..['trading_name'] = name
        ..['legalName'] = _legal.text.trim()
        ..['legal_name'] = _legal.text.trim()
        ..['phone'] = _phone.text.trim()
        ..['email'] = _email.text.trim()
        ..['country'] = _country
        ..['publicLogoUrl'] = _logoUrl.text.trim()
        ..['public_logo_url'] = _logoUrl.text.trim();
      final saved = await (widget.profileSaver ?? saveCompanyOpsBusinessProfile)(
        next,
      );
      if (!mounted) return;
      _apply(saved);
      final session = companyOpsLocalSessionNotifier.value;
      if (session != null) {
        companyOpsIdentityNotifier.value = identityFromBusinessProfile(
          generation: companyOpsContextGeneration,
          companyId: session.companyId,
          profile: saved,
        );
      }
      widget.onSaved?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Bewaren mislukt.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompanyOpsThemedSurface(
      child: Scaffold(
        key: kCompanySettingsPageKey,
        appBar: AppBar(title: const Text('Instellingen')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : CompanyOpsBoundedForm(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextFormField(
                      key: kCompanySettingsNameKey,
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Bedrijfsnaam *',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _legal,
                      decoration: const InputDecoration(
                        labelText: 'Juridische naam',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Telefoon'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'E-mail'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: kCompanyCustomerCallingCodeOptions.any(
                        (item) => item.countryCode == _country,
                      )
                          ? _country
                          : 'BE',
                      decoration: const InputDecoration(labelText: 'Land'),
                      items: [
                        for (final item in kCompanyCustomerCallingCodeOptions)
                          DropdownMenuItem<String>(
                            value: item.countryCode,
                            child: Text(
                              '${item.label.of(_lang)} (${item.countryCode})',
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _country = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_logoUrl.text.trim().isNotEmpty)
                      Image.network(
                        key: kCompanySettingsLogoKey,
                        _logoUrl.text.trim(),
                        height: 72,
                        errorBuilder: (_, __, ___) => const Text('Logo niet geladen'),
                      ),
                    OutlinedButton(
                      onPressed: _saving ? null : _pickLogo,
                      child: const Text('Logo kiezen'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      key: kCompanySettingsSaveKey,
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Bewaren…' : 'Bewaren'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Huisstijl gebruikt de bestaande Brand Signature-paletten. '
                      'Publicatie van het partnerprofiel blijft dezelfde Worker-route.',
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

String _text(Map<String, dynamic> profile, List<String> keys) {
  for (final key in keys) {
    final value = profile[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}
