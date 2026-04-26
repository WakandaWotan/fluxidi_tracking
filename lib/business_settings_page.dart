import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:image_picker/image_picker.dart';

class BusinessSettingsPage extends StatefulWidget {
  const BusinessSettingsPage({super.key});

  @override
  State<BusinessSettingsPage> createState() => _BusinessSettingsPageState();
}

class _BusinessSettingsPageState extends State<BusinessSettingsPage> {
  final _companyCtrl = TextEditingController();
  final _supportEmailCtrl = TextEditingController();
  final _supportPhoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _vatCtrl = TextEditingController();
  final _logoPathCtrl = TextEditingController();
  final _logoAdvancedCtrl = TextEditingController();
  final _senderCtrl = TextEditingController();
  final _replyToCtrl = TextEditingController();
  final _whatsAppCtrl = TextEditingController();
  final _baseFareCtrl = TextEditingController();
  final _perKmCtrl = TextEditingController();
  final _perMinCtrl = TextEditingController();
  final _minimumFareCtrl = TextEditingController();
  final _waitPerMinCtrl = TextEditingController();
  final _returnFeeCtrl = TextEditingController();
  final _fuelSurchargeCtrl = TextEditingController();
  final _vatRatePricingCtrl = TextEditingController();
  final _bagFeeCtrl = TextEditingController();
  final _stopFeeCtrl = TextEditingController();
  final _tierComfortFeeCtrl = TextEditingController();
  final _tierPrivateFeeCtrl = TextEditingController();
  final _tierPremiumFeeCtrl = TextEditingController();
  final _nightSurchargeCtrl = TextEditingController();
  final _weekendSurchargeCtrl = TextEditingController();
  final _surchargeCapCtrl = TextEditingController();

  late AppLanguage _defaultLanguage;
  late String _defaultCurrency;
  late String _taxLabel;
  bool _use24Hour = true;
  bool _pricingReturnEnabled = true;
  late String _pricingVatMode;
  bool _showAdvancedLogoPath = false;
  final ImagePicker _imagePicker = ImagePicker();
  Set<String> _serviceIds = <String>{};
  Set<String> _tierIds = <String>{};
  Set<String> _extraIds = <String>{};

  AppLanguage get _lang => appConfig.currentLanguage;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (_lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
    }
  }

  @override
  void initState() {
    super.initState();
    _hydrateFromSettings(businessSettingsNotifier.value);
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _supportEmailCtrl.dispose();
    _supportPhoneCtrl.dispose();
    _addressCtrl.dispose();
    _vatCtrl.dispose();
    _logoPathCtrl.dispose();
    _logoAdvancedCtrl.dispose();
    _senderCtrl.dispose();
    _replyToCtrl.dispose();
    _whatsAppCtrl.dispose();
    _baseFareCtrl.dispose();
    _perKmCtrl.dispose();
    _perMinCtrl.dispose();
    _minimumFareCtrl.dispose();
    _waitPerMinCtrl.dispose();
    _returnFeeCtrl.dispose();
    _fuelSurchargeCtrl.dispose();
    _vatRatePricingCtrl.dispose();
    _bagFeeCtrl.dispose();
    _stopFeeCtrl.dispose();
    _tierComfortFeeCtrl.dispose();
    _tierPrivateFeeCtrl.dispose();
    _tierPremiumFeeCtrl.dispose();
    _nightSurchargeCtrl.dispose();
    _weekendSurchargeCtrl.dispose();
    _surchargeCapCtrl.dispose();
    super.dispose();
  }

  void _hydrateFromSettings(BusinessSettingsState s) {
    _companyCtrl.text = s.companyName;
    _supportEmailCtrl.text = s.supportEmail;
    _supportPhoneCtrl.text = s.supportPhone;
    _addressCtrl.text = s.address;
    _vatCtrl.text = s.vatCompanyNumber;
    _logoPathCtrl.text = s.logoAssetPath;
    _logoAdvancedCtrl.text = s.logoAssetPath;
    _senderCtrl.text = s.bookingSender;
    _replyToCtrl.text = s.bookingReplyTo;
    _whatsAppCtrl.text = s.whatsappNumber;
    _baseFareCtrl.text = s.pricingBaseFare.toStringAsFixed(2);
    _perKmCtrl.text = s.pricingPerKm.toStringAsFixed(2);
    _perMinCtrl.text = s.pricingPerMinute.toStringAsFixed(2);
    _minimumFareCtrl.text = s.pricingMinimumFare.toStringAsFixed(2);
    _waitPerMinCtrl.text = s.pricingWaitPerMinute.toStringAsFixed(2);
    _returnFeeCtrl.text = s.pricingReturnFee.toStringAsFixed(2);
    _fuelSurchargeCtrl.text = s.pricingFuelSurcharge.toStringAsFixed(2);
    _vatRatePricingCtrl.text = s.pricingVatRate.toStringAsFixed(2);
    _bagFeeCtrl.text = s.pricingBagFeeEach.toStringAsFixed(2);
    _stopFeeCtrl.text = s.pricingStopFeeEach.toStringAsFixed(2);
    _tierComfortFeeCtrl.text = s.pricingTierFeeComfort.toStringAsFixed(2);
    _tierPrivateFeeCtrl.text = s.pricingTierFeePrivate.toStringAsFixed(2);
    _tierPremiumFeeCtrl.text = s.pricingTierFeePremium.toStringAsFixed(2);
    _nightSurchargeCtrl.text = s.pricingNightSurchargeRate.toStringAsFixed(2);
    _weekendSurchargeCtrl.text = s.pricingWeekendSurchargeRate.toStringAsFixed(2);
    _surchargeCapCtrl.text = s.pricingSurchargeCapRate.toStringAsFixed(2);
    _defaultLanguage = s.defaultLanguage;
    _defaultCurrency = s.defaultCurrency;
    _taxLabel = s.taxLabel;
    _use24Hour = s.use24HourTime;
    _pricingReturnEnabled = s.pricingReturnEnabled;
    _pricingVatMode = s.pricingVatMode;
    _serviceIds = Set<String>.from(s.enabledServiceIds);
    _tierIds = Set<String>.from(s.enabledTierIds);
    _extraIds = Set<String>.from(s.enabledExtraOptionIds);
  }

  double _toMoney(String raw, double fallback) {
    final parsed = double.tryParse(raw.replaceAll(',', '.').trim());
    if (parsed == null || !parsed.isFinite) return fallback;
    if (parsed < 0) return 0;
    return parsed;
  }

  void _save() {
    final current = businessSettingsNotifier.value;
    updateBusinessSettings(
      current.copyWith(
        companyName: _companyCtrl.text.trim(),
        supportEmail: _supportEmailCtrl.text.trim(),
        supportPhone: _supportPhoneCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        vatCompanyNumber: _vatCtrl.text.trim(),
        logoAssetPath: _logoPathCtrl.text.trim(),
        defaultLanguage: _defaultLanguage,
        defaultCurrency: _defaultCurrency,
        taxLabel: _taxLabel,
        use24HourTime: _use24Hour,
        enabledServiceIds: _serviceIds,
        enabledTierIds: _tierIds,
        enabledExtraOptionIds: _extraIds,
        bookingSender: _senderCtrl.text.trim(),
        bookingReplyTo: _replyToCtrl.text.trim(),
        whatsappNumber: _whatsAppCtrl.text.trim(),
        pricingBaseFare: _toMoney(_baseFareCtrl.text, current.pricingBaseFare),
        pricingPerKm: _toMoney(_perKmCtrl.text, current.pricingPerKm),
        pricingPerMinute: _toMoney(_perMinCtrl.text, current.pricingPerMinute),
        pricingMinimumFare: _toMoney(_minimumFareCtrl.text, current.pricingMinimumFare),
        pricingWaitPerMinute: _toMoney(_waitPerMinCtrl.text, current.pricingWaitPerMinute),
        pricingReturnEnabled: _pricingReturnEnabled,
        pricingReturnFee: _toMoney(_returnFeeCtrl.text, current.pricingReturnFee),
        pricingFuelSurcharge: _toMoney(_fuelSurchargeCtrl.text, current.pricingFuelSurcharge),
        pricingVatRate: _toMoney(_vatRatePricingCtrl.text, current.pricingVatRate),
        pricingVatMode: _pricingVatMode,
        pricingBagFeeEach: _toMoney(_bagFeeCtrl.text, current.pricingBagFeeEach),
        pricingStopFeeEach: _toMoney(_stopFeeCtrl.text, current.pricingStopFeeEach),
        pricingTierFeeComfort:
            _toMoney(_tierComfortFeeCtrl.text, current.pricingTierFeeComfort),
        pricingTierFeePrivate:
            _toMoney(_tierPrivateFeeCtrl.text, current.pricingTierFeePrivate),
        pricingTierFeePremium:
            _toMoney(_tierPremiumFeeCtrl.text, current.pricingTierFeePremium),
        pricingNightSurchargeRate: _toMoney(
          _nightSurchargeCtrl.text,
          current.pricingNightSurchargeRate,
        ),
        pricingWeekendSurchargeRate: _toMoney(
          _weekendSurchargeCtrl.text,
          current.pricingWeekendSurchargeRate,
        ),
        pricingSurchargeCapRate: _toMoney(
          _surchargeCapCtrl.text,
          current.pricingSurchargeCapRate,
        ),
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t(nl: 'Instellingen bijgewerkt (runtime).', en: 'Settings updated (runtime).', fr: 'Parametres mis a jour (runtime).', es: 'Configuracion actualizada (runtime).'))),
    );
  }

  bool _isAssetRef(String value) => value.trim().toLowerCase().startsWith('assets/');

  Future<void> _pickLogoImage() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );
      if (picked == null) return;
      _setLogoRef(picked.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Kon geen logo selecteren.',
              en: 'Could not select logo.',
              fr: 'Impossible de selectionner le logo.',
              es: 'No se pudo seleccionar el logo.',
            ),
          ),
        ),
      );
    }
  }

  void _setLogoRef(String ref) {
    setState(() {
      _logoPathCtrl.text = ref;
      _logoAdvancedCtrl.text = ref;
    });
  }

  Future<void> _openLogoActions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141B2F),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: Text(_t(nl: 'Upload logo', en: 'Upload logo', fr: 'Televerser logo', es: 'Subir logo')),
                  subtitle: Text(_t(nl: 'Placeholder voor echte upload', en: 'Placeholder for real upload', fr: 'Placeholder pour upload reel', es: 'Placeholder para carga real')),
                  onTap: () {
                    Navigator.pop(ctx);
                    _setLogoRef('assets/fluxidi/fluxidi_logo.png');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(_t(nl: 'Kies standaard logo', en: 'Choose default logo', fr: 'Choisir logo par defaut', es: 'Elegir logo predeterminado')),
                  onTap: () {
                    Navigator.pop(ctx);
                    _setLogoRef('assets/fluxidi/fluxidi_logo.png');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: Text(_t(nl: 'Gebruik voorbeeldreferentie', en: 'Use sample reference', fr: 'Utiliser reference exemple', es: 'Usar referencia de ejemplo')),
                  onTap: () {
                    Navigator.pop(ctx);
                    _setLogoRef('camera://logo-placeholder');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _logoPreviewBlock() {
    final logoRef = _logoPathCtrl.text.trim();
    final hasRef = logoRef.isNotEmpty;
    final isAsset = _isAssetRef(logoRef);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _pickLogoImage,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF0B0B0B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: isAsset
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.asset(
                      logoRef,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => _logoPlaceholder(),
                    ),
                  )
                : (hasRef
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: kIsWeb
                            ? Image.network(
                                logoRef,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => _logoPlaceholder(),
                              )
                            : Image.file(
                                File(logoRef),
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => _logoPlaceholder(),
                              ),
                      )
                    : _logoPlaceholder()),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _pickLogoImage,
              icon: const Icon(Icons.upload_file),
              label: Text(_t(nl: 'Upload logo', en: 'Upload logo', fr: 'Televerser logo', es: 'Subir logo')),
            ),
            OutlinedButton.icon(
              onPressed: _pickLogoImage,
              icon: const Icon(Icons.edit_outlined),
              label: Text(_t(nl: 'Logo wijzigen', en: 'Change logo', fr: 'Modifier logo', es: 'Cambiar logo')),
            ),
            OutlinedButton.icon(
              onPressed: () => _setLogoRef(''),
              icon: const Icon(Icons.delete_outline),
              label: Text(_t(nl: 'Logo verwijderen', en: 'Remove logo', fr: 'Supprimer logo', es: 'Quitar logo')),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () => setState(() => _showAdvancedLogoPath = !_showAdvancedLogoPath),
          icon: Icon(_showAdvancedLogoPath ? Icons.expand_less : Icons.expand_more),
          label: Text(_t(nl: 'Geavanceerd: handmatige referentie', en: 'Advanced: manual reference', fr: 'Avance: reference manuelle', es: 'Avanzado: referencia manual')),
        ),
        if (_showAdvancedLogoPath)
          _txt(
            _logoAdvancedCtrl,
            _t(nl: 'Logo pad/referentie', en: 'Logo path/reference', fr: 'Chemin/reference logo', es: 'Ruta/referencia logo'),
            onChanged: (v) => _setLogoRef(v),
          ),
      ],
    );
  }

  Widget _logoPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_outlined, size: 28, color: Colors.white54),
          const SizedBox(height: 6),
          Text(
            _t(nl: 'Geen logo preview', en: 'No logo preview', fr: 'Pas de preview logo', es: 'Sin vista previa de logo'),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _txt(TextEditingController ctrl, String label, {ValueChanged<String>? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: const Color(0xFF0B0B0B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0x22FFFFFF)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0x22FFFFFF)),
          ),
        ),
      ),
    );
  }

  Widget _optionsChecklist({
    required List<AppOption> options,
    required Set<String> selected,
    required void Function(Set<String>) onChanged,
  }) {
    return Column(
      children: options.map((o) {
        final isOn = selected.contains(o.id);
        return CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: isOn,
          onChanged: (v) {
            final next = Set<String>.from(selected);
            if (v == true) {
              next.add(o.id);
            } else {
              next.remove(o.id);
            }
            onChanged(next);
          },
          title: Text(o.labelFor(_lang)),
          subtitle: Text(o.payloadValue, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        );
      }).toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1020),
          title: Text(_t(
            nl: 'Bedrijfsinstellingen',
            en: 'Business settings',
            fr: 'Parametres entreprise',
            es: 'Configuracion de empresa',
          )),
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _card(
              title: _t(nl: 'Bedrijfsprofiel', en: 'Business profile', fr: 'Profil entreprise', es: 'Perfil empresarial'),
              child: Column(
                children: [
                  _txt(_companyCtrl, _t(nl: 'Bedrijfsnaam', en: 'Company name', fr: 'Nom de l entreprise', es: 'Nombre de la empresa')),
                  _txt(_supportEmailCtrl, _t(nl: 'Support e-mail', en: 'Support email', fr: 'E-mail support', es: 'Correo de soporte')),
                  _txt(_supportPhoneCtrl, _t(nl: 'Support telefoon', en: 'Support phone', fr: 'Telephone support', es: 'Telefono de soporte')),
                  _txt(_addressCtrl, _t(nl: 'Adres', en: 'Address', fr: 'Adresse', es: 'Direccion')),
                  _txt(_vatCtrl, _t(nl: 'BTW/ondernemingsnummer', en: 'VAT/company number', fr: 'Numero TVA/entreprise', es: 'Numero de IVA/empresa')),
                  _logoPreviewBlock(),
                ],
              ),
            ),
            _card(
              title: _t(nl: 'Branding / regio defaults', en: 'Branding / region defaults', fr: 'Branding / defaults region', es: 'Branding / valores regionales'),
              child: Column(
                children: [
                  DropdownButtonFormField<AppLanguage>(
                    value: _defaultLanguage,
                    items: const [
                      DropdownMenuItem(value: AppLanguage.nl, child: Text('Nederlands')),
                      DropdownMenuItem(value: AppLanguage.en, child: Text('English')),
                      DropdownMenuItem(value: AppLanguage.fr, child: Text('Français')),
                      DropdownMenuItem(value: AppLanguage.es, child: Text('Español')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _defaultLanguage = v);
                    },
                    decoration: InputDecoration(
                      labelText: _t(nl: 'Standaard taal', en: 'Default language', fr: 'Langue par defaut', es: 'Idioma predeterminado'),
                      filled: true,
                      fillColor: const Color(0xFF0B0B0B),
                    ),
                    dropdownColor: const Color(0xFF111111),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _defaultCurrency,
                    items: const ['EUR', 'USD', 'GBP', 'CHF']
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(growable: false),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _defaultCurrency = v);
                    },
                    decoration: InputDecoration(
                      labelText: _t(nl: 'Standaard valuta', en: 'Default currency', fr: 'Devise par defaut', es: 'Moneda predeterminada'),
                      filled: true,
                      fillColor: const Color(0xFF0B0B0B),
                    ),
                    dropdownColor: const Color(0xFF111111),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _taxLabel,
                    items: const ['BTW', 'VAT', 'TVA', 'IVA', 'GST', 'Tax']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(growable: false),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _taxLabel = v);
                    },
                    decoration: InputDecoration(
                      labelText: _t(nl: 'Belastinglabel', en: 'Tax label', fr: 'Libelle taxe', es: 'Etiqueta de impuesto'),
                      filled: true,
                      fillColor: const Color(0xFF0B0B0B),
                    ),
                    dropdownColor: const Color(0xFF111111),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _use24Hour,
                    onChanged: (v) => setState(() => _use24Hour = v),
                    title: Text(_t(nl: 'Gebruik 24-uurs notatie', en: 'Use 24-hour time', fr: 'Utiliser format 24h', es: 'Usar formato 24 horas')),
                  ),
                ],
              ),
            ),
            _card(
              title: _t(nl: 'Service setup', en: 'Service setup', fr: 'Configuration des services', es: 'Configuracion de servicios'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_t(nl: 'Ingeschakelde services', en: 'Enabled services', fr: 'Services actifs', es: 'Servicios habilitados')),
                  _optionsChecklist(
                    options: appConfig.enabledServices,
                    selected: _serviceIds,
                    onChanged: (next) => setState(() => _serviceIds = next),
                  ),
                  const SizedBox(height: 6),
                  Text(_t(nl: 'Ingeschakelde tiers', en: 'Enabled tiers', fr: 'Categories actives', es: 'Categorias habilitadas')),
                  _optionsChecklist(
                    options: appConfig.enabledTiers,
                    selected: _tierIds,
                    onChanged: (next) => setState(() => _tierIds = next),
                  ),
                  const SizedBox(height: 6),
                  Text(_t(nl: 'Ingeschakelde extra opties', en: 'Enabled extra options', fr: 'Options extra actives', es: 'Opciones extra habilitadas')),
                  _optionsChecklist(
                    options: appConfig.enabledExtraOptions,
                    selected: _extraIds,
                    onChanged: (next) => setState(() => _extraIds = next),
                  ),
                ],
              ),
            ),
            _card(
              title: _t(nl: 'Pricing engine', en: 'Pricing engine', fr: 'Moteur tarifaire', es: 'Motor de precios'),
              child: Column(
                children: [
                  _txt(_baseFareCtrl, _t(nl: 'Basistarief', en: 'Base fare', fr: 'Tarif de base', es: 'Tarifa base')),
                  _txt(_perKmCtrl, _t(nl: 'Prijs per km', en: 'Price per km', fr: 'Prix par km', es: 'Precio por km')),
                  _txt(_perMinCtrl, _t(nl: 'Prijs per minuut', en: 'Price per minute', fr: 'Prix par minute', es: 'Precio por minuto')),
                  _txt(_minimumFareCtrl, _t(nl: 'Minimumtarief', en: 'Minimum fare', fr: 'Tarif minimum', es: 'Tarifa minima')),
                  _txt(_waitPerMinCtrl, _t(nl: 'Wachttarief per minuut', en: 'Waiting price per minute', fr: 'Tarif d attente par minute', es: 'Tarifa de espera por minuto')),
                  _txt(_vatRatePricingCtrl, _t(nl: 'BTW/VAT tarief (0-1)', en: 'VAT rate (0-1)', fr: 'Taux TVA (0-1)', es: 'Tasa IVA (0-1)')),
                  DropdownButtonFormField<String>(
                    value: _pricingVatMode,
                    items: const [
                      DropdownMenuItem(value: 'excl', child: Text('Excl VAT')),
                      DropdownMenuItem(value: 'incl', child: Text('Incl VAT')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _pricingVatMode = v);
                    },
                    decoration: InputDecoration(
                      labelText: _t(nl: 'BTW modus', en: 'VAT mode', fr: 'Mode TVA', es: 'Modo IVA'),
                      filled: true,
                      fillColor: const Color(0xFF0B0B0B),
                    ),
                    dropdownColor: const Color(0xFF111111),
                  ),
                  _txt(_bagFeeCtrl, _t(nl: 'Bagagekost per stuk', en: 'Bag fee each', fr: 'Frais bagage par piece', es: 'Tarifa por equipaje')),
                  _txt(_stopFeeCtrl, _t(nl: 'Stopkost per stop', en: 'Stop fee each', fr: 'Frais par arret', es: 'Tarifa por parada')),
                  _txt(_tierComfortFeeCtrl, _t(nl: 'Tier fee comfort', en: 'Tier fee comfort', fr: 'Frais niveau confort', es: 'Tarifa nivel comfort')),
                  _txt(_tierPrivateFeeCtrl, _t(nl: 'Tier fee private', en: 'Tier fee private', fr: 'Frais niveau prive', es: 'Tarifa nivel private')),
                  _txt(_tierPremiumFeeCtrl, _t(nl: 'Tier fee premium', en: 'Tier fee premium', fr: 'Frais niveau premium', es: 'Tarifa nivel premium')),
                  _txt(_nightSurchargeCtrl, _t(nl: 'Nachttoeslag (0-1)', en: 'Night surcharge (0-1)', fr: 'Surcharge nuit (0-1)', es: 'Recargo nocturno (0-1)')),
                  _txt(_weekendSurchargeCtrl, _t(nl: 'Weekendtoeslag (0-1)', en: 'Weekend surcharge (0-1)', fr: 'Surcharge weekend (0-1)', es: 'Recargo fin de semana (0-1)')),
                  _txt(_surchargeCapCtrl, _t(nl: 'Toeslag plafond (0-1)', en: 'Surcharge cap (0-1)', fr: 'Plafond surcharge (0-1)', es: 'Tope de recargo (0-1)')),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _pricingReturnEnabled,
                    onChanged: (v) => setState(() => _pricingReturnEnabled = v),
                    title: Text(_t(
                      nl: 'Retourritten inschakelen',
                      en: 'Enable return trips',
                      fr: 'Activer les trajets retour',
                      es: 'Activar viajes de regreso',
                    )),
                  ),
                  _txt(_returnFeeCtrl, _t(nl: 'Retourtoeslag', en: 'Return fee', fr: 'Supplement retour', es: 'Recargo de regreso')),
                  _txt(_fuelSurchargeCtrl, _t(nl: 'Brandstoftoeslag', en: 'Fuel surcharge', fr: 'Supplement carburant', es: 'Recargo de combustible')),
                ],
              ),
            ),
            _card(
              title: _t(nl: 'Communicatie defaults', en: 'Communication defaults', fr: 'Parametres communication', es: 'Valores de comunicacion'),
              child: Column(
                children: [
                  _txt(_senderCtrl, _t(nl: 'Booking afzender (placeholder)', en: 'Booking sender (placeholder)', fr: 'Expediteur booking (placeholder)', es: 'Remitente booking (placeholder)')),
                  _txt(_replyToCtrl, _t(nl: 'Reply-to (placeholder)', en: 'Reply-to (placeholder)', fr: 'Reply-to (placeholder)', es: 'Reply-to (placeholder)')),
                  _txt(_whatsAppCtrl, _t(nl: 'WhatsApp nummer (placeholder)', en: 'WhatsApp number (placeholder)', fr: 'Numero WhatsApp (placeholder)', es: 'Numero de WhatsApp (placeholder)')),
                ],
              ),
            ),
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(_t(nl: 'Instellingen opslaan', en: 'Save settings', fr: 'Enregistrer', es: 'Guardar configuracion')),
            ),
          ],
        ),
      ),
    );
  }
}
