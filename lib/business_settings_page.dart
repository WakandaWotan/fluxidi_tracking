import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

enum _SetupStatus { complete, attention, incomplete, comingSoon }

class _SetupItem {
  const _SetupItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.status,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final _SetupStatus status;
}

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
  final _backendCompanyNameCtrl = TextEditingController();
  final _backendLegalNameCtrl = TextEditingController();
  final _backendVatNumberCtrl = TextEditingController();
  final _backendRegistrationCtrl = TextEditingController();
  final _backendAddressCtrl = TextEditingController();
  final _backendPostcodeCtrl = TextEditingController();
  final _backendCityCtrl = TextEditingController();
  final _backendCountryCtrl = TextEditingController();
  final _backendPhoneCtrl = TextEditingController();
  final _backendEmailCtrl = TextEditingController();
  final _backendWebsiteCtrl = TextEditingController();
  final _backendBookingEmailCtrl = TextEditingController();
  final _backendInvoiceEmailCtrl = TextEditingController();
  final _backendIbanCtrl = TextEditingController();
  final _backendPaymentPrefixCtrl = TextEditingController();
  final _backendFooterCtrl = TextEditingController();
  final _backendVatRateCtrl = TextEditingController();
  final _backendVatLabelNlCtrl = TextEditingController();
  final _backendVatLabelEnCtrl = TextEditingController();
  final _backendVatLabelFrCtrl = TextEditingController();
  final _backendVatLabelEsCtrl = TextEditingController();

  late AppLanguage _defaultLanguage;
  late String _defaultCurrency;
  late String _taxLabel;
  bool _use24Hour = true;
  bool _pricingReturnEnabled = true;
  late String _pricingVatMode;
  bool _backendVatEnabled = true;
  String _backendVatDisplayMode = 'excl';
  bool _backendProfilesLoading = false;
  bool _backendBusinessSaving = false;
  bool _backendTaxSaving = false;
  bool _googleCalendarLoading = false;
  bool _googleCalendarReconnectLoading = false;
  String? _backendProfilesError;
  String? _backendProfilesStatus;
  String? _googleCalendarStatusError;
  Map<String, dynamic>? _googleCalendarStatus;
  bool _showAdvancedLogoPath = false;
  final ImagePicker _imagePicker = ImagePicker();
  Set<String> _serviceIds = <String>{};
  Set<String> _tierIds = <String>{};
  Set<String> _extraIds = <String>{};
  final Set<String> _expandedSections = <String>{};

  void _onLogoSanitizationListeners() {
    _syncLocalTenantLogoFromNotifier();
  }

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
    companyProfileNotifier.addListener(_onLogoSanitizationListeners);
    businessSettingsNotifier.addListener(_onLogoSanitizationListeners);
    _hydrateFromSettings(businessSettingsNotifier.value);
    // Prefer locally cached "Officiële bedrijfsgegevens" so user-entered values
    // survive app restarts even when the backend is offline. Falls back to the
    // existing defaults+local-CompanyProfile preview when no cache exists yet.
    final cachedBackendProfile = localBackendBusinessProfileNotifier.value;
    _hydrateBackendBusinessProfile(
      cachedBackendProfile ??
          mergeLocalIntoBackendPreview(
            BackendBusinessProfile.defaults(),
            companyProfileNotifier.value,
          ),
    );
    // Prefer locally cached "BTW-instellingen" so a user's saved VAT rate /
    // mode / labels survive app restarts and offline launches. Falls back to
    // BackendTaxProfile.defaults() when no cache exists yet.
    _hydrateBackendTaxProfile(
      localBackendTaxProfileNotifier.value ?? BackendTaxProfile.defaults(),
    );
    _mergeLocalIntoGeneralControllersIfEligible();
    _loadBackendProfiles();
    _loadGoogleCalendarStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncLocalTenantLogoFromNotifier();
      _maybeNormalizeStoredLogoInNotifier();
    });
  }

  @override
  void dispose() {
    companyProfileNotifier.removeListener(_onLogoSanitizationListeners);
    businessSettingsNotifier.removeListener(_onLogoSanitizationListeners);
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
    _backendCompanyNameCtrl.dispose();
    _backendLegalNameCtrl.dispose();
    _backendVatNumberCtrl.dispose();
    _backendRegistrationCtrl.dispose();
    _backendAddressCtrl.dispose();
    _backendPostcodeCtrl.dispose();
    _backendCityCtrl.dispose();
    _backendCountryCtrl.dispose();
    _backendPhoneCtrl.dispose();
    _backendEmailCtrl.dispose();
    _backendWebsiteCtrl.dispose();
    _backendBookingEmailCtrl.dispose();
    _backendInvoiceEmailCtrl.dispose();
    _backendIbanCtrl.dispose();
    _backendPaymentPrefixCtrl.dispose();
    _backendFooterCtrl.dispose();
    _backendVatRateCtrl.dispose();
    _backendVatLabelNlCtrl.dispose();
    _backendVatLabelEnCtrl.dispose();
    _backendVatLabelFrCtrl.dispose();
    _backendVatLabelEsCtrl.dispose();
    super.dispose();
  }

  void _hydrateFromSettings(BusinessSettingsState s) {
    _companyCtrl.text = s.companyName;
    _supportEmailCtrl.text = s.supportEmail;
    _supportPhoneCtrl.text = s.supportPhone;
    _addressCtrl.text = s.address;
    _vatCtrl.text = s.vatCompanyNumber;
    final logoForUi = _storedLogoPathForLocalTenant(s.logoAssetPath);
    _logoPathCtrl.text = logoForUi;
    _logoAdvancedCtrl.text = logoForUi;
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
    _weekendSurchargeCtrl.text = s.pricingWeekendSurchargeRate.toStringAsFixed(
      2,
    );
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

  void _hydrateBackendBusinessProfile(BackendBusinessProfile p) {
    _backendCompanyNameCtrl.text = p.companyName;
    _backendLegalNameCtrl.text = p.legalName;
    _backendVatNumberCtrl.text = p.vatNumber;
    _backendRegistrationCtrl.text = p.companyRegistrationNumber;
    _backendAddressCtrl.text = p.address;
    _backendPostcodeCtrl.text = p.postcode;
    _backendCityCtrl.text = p.city;
    _backendCountryCtrl.text = p.country;
    _backendPhoneCtrl.text = p.phone;
    _backendEmailCtrl.text = p.email;
    _backendWebsiteCtrl.text = p.website;
    _backendBookingEmailCtrl.text = p.bookingEmail;
    _backendInvoiceEmailCtrl.text = p.invoiceEmail;
    _backendIbanCtrl.text = p.iban;
    _backendPaymentPrefixCtrl.text = p.paymentReferencePrefix;
    _backendFooterCtrl.text = p.invoiceReceiptFooterText;
  }

  void _hydrateBackendTaxProfile(BackendTaxProfile p) {
    _backendVatEnabled = p.vatEnabled;
    final pct = (p.vatRate * 100).clamp(0.0, 100.0);
    _backendVatRateCtrl.text = pct == pct.roundToDouble()
        ? pct.toStringAsFixed(0)
        : pct.toStringAsFixed(2);
    _backendVatDisplayMode = p.vatDisplayMode;
    _backendVatLabelNlCtrl.text = p.vatLabels['nl'] ?? 'BTW';
    _backendVatLabelEnCtrl.text = p.vatLabels['en'] ?? 'VAT';
    _backendVatLabelFrCtrl.text = p.vatLabels['fr'] ?? 'TVA';
    _backendVatLabelEsCtrl.text = p.vatLabels['es'] ?? 'IVA';
    final vat = resolveActiveVatConfig(
      settings: businessSettingsNotifier.value,
      taxProfile: p,
    );
    _vatRatePricingCtrl.text = vat.vatRate.toStringAsFixed(2);
    _pricingVatMode = vat.vatMode;
  }

  void _mergeLocalIntoGeneralControllersIfEligible() {
    final local = companyProfileNotifier.value;
    if (local == null) return;
    final appCompany = appConfig.companyName.trim();
    final appEmail = appConfig.supportEmail.trim();
    final appPhone = appConfig.supportPhone.trim();

    void replaceIfEmptyOrAppDefault(
      TextEditingController ctrl,
      String val,
      String appDefault,
    ) {
      final t = ctrl.text.trim();
      final v = val.trim();
      if (v.isEmpty) return;
      final ad = appDefault.trim();
      if (t.isEmpty || t == ad) ctrl.text = v;
    }

    replaceIfEmptyOrAppDefault(_companyCtrl, local.companyName, appCompany);
    final supportFill = local.supportEmail.trim().isNotEmpty
        ? local.supportEmail.trim()
        : primaryContactEmailFromCompany(local);
    replaceIfEmptyOrAppDefault(_supportEmailCtrl, supportFill, appEmail);
    replaceIfEmptyOrAppDefault(_supportPhoneCtrl, local.phone, appPhone);
    replaceIfEmptyOrAppDefault(_vatCtrl, local.vatNumber, '');

    final addrCombined = <String>[
      if (local.addressLine.trim().isNotEmpty) local.addressLine.trim(),
      if (local.postalCode.trim().isNotEmpty || local.city.trim().isNotEmpty)
        '${local.postalCode.trim()} ${local.city.trim()}'.trim(),
      if (local.countryCode.trim().isNotEmpty) local.countryCode.trim(),
    ].join('\n');
    if (_addressCtrl.text.trim().isEmpty && addrCombined.trim().isNotEmpty) {
      _addressCtrl.text = addrCombined;
    }

    final booking = local.bookingEmail.trim().isNotEmpty
        ? local.bookingEmail.trim()
        : '';
    final bookingFill = booking.isNotEmpty
        ? booking
        : primaryContactEmailFromCompany(local);
    replaceIfEmptyOrAppDefault(_senderCtrl, bookingFill, appEmail);

    final reply = local.notificationEmail.trim().isNotEmpty
        ? local.notificationEmail.trim()
        : '';
    final replyFill = reply.isNotEmpty
        ? reply
        : primaryContactEmailFromCompany(local);
    replaceIfEmptyOrAppDefault(_replyToCtrl, replyFill, appEmail);
  }

  /// True when [value] looks "meaningful" (not empty after trim).
  static bool _backendFieldHasValue(String value) => value.trim().isNotEmpty;

  /// Non-destructive field-by-field merge of [server] over [local].
  ///
  /// For every [BackendBusinessProfile] field we keep the [local] (form/cached)
  /// value when [server] returns an empty/whitespace value; otherwise we use
  /// the server value. This prevents an empty/default backend response from
  /// erasing fields the user already typed and saved locally.
  BackendBusinessProfile _mergeBackendBusinessProfile({
    required BackendBusinessProfile local,
    required BackendBusinessProfile server,
  }) {
    String pick(String localValue, String serverValue) =>
        _backendFieldHasValue(serverValue) ? serverValue : localValue;
    return BackendBusinessProfile(
      companyName: pick(local.companyName, server.companyName),
      legalName: pick(local.legalName, server.legalName),
      vatNumber: pick(local.vatNumber, server.vatNumber),
      companyRegistrationNumber: pick(
        local.companyRegistrationNumber,
        server.companyRegistrationNumber,
      ),
      address: pick(local.address, server.address),
      postcode: pick(local.postcode, server.postcode),
      city: pick(local.city, server.city),
      country: pick(local.country, server.country),
      phone: pick(local.phone, server.phone),
      email: pick(local.email, server.email),
      website: pick(local.website, server.website),
      bookingEmail: pick(local.bookingEmail, server.bookingEmail),
      invoiceEmail: pick(local.invoiceEmail, server.invoiceEmail),
      iban: pick(local.iban, server.iban),
      paymentReferencePrefix: pick(
        local.paymentReferencePrefix,
        server.paymentReferencePrefix,
      ),
      invoiceReceiptFooterText: pick(
        local.invoiceReceiptFooterText,
        server.invoiceReceiptFooterText,
      ),
    );
  }

  Future<void> _loadBackendProfiles() async {
    setState(() {
      _backendProfilesLoading = true;
      _backendProfilesError = null;
      _backendProfilesStatus = null;
    });
    try {
      final scope = _activeSettingsScope();
      final results = await Future.wait<dynamic>([
        fetchBackendBusinessProfile(
          tenantId: scope.tenantId,
          companyId: scope.companyId,
        ),
        fetchBackendTaxProfile(
          tenantId: scope.tenantId,
          companyId: scope.companyId,
        ),
      ]);
      if (!mounted) return;
      final rawBiz = results[0] as BackendBusinessProfile;
      final rawTax = results[1] as BackendTaxProfile;
      // Merge server response over the locally cached profile so empty server
      // fields do not wipe non-empty user-saved values.
      final cached = localBackendBusinessProfileNotifier.value;
      final localBase =
          cached ??
          mergeLocalIntoBackendPreview(
            BackendBusinessProfile.defaults(),
            companyProfileNotifier.value,
          );
      final merged = _mergeBackendBusinessProfile(
        local: localBase,
        server: rawBiz,
      );
      // Prefer the locally cached BTW profile when present so backend defaults
      // never silently overwrite the user's saved VAT rate / mode / labels.
      // Only adopt the backend tax profile when no cache exists yet.
      final cachedTax = localBackendTaxProfileNotifier.value;
      final taxForUi = cachedTax ?? rawTax;
      setState(() {
        _hydrateBackendBusinessProfile(merged);
        _hydrateBackendTaxProfile(taxForUi);
        _mergeLocalIntoGeneralControllersIfEligible();
        _backendProfilesStatus = _t(
          nl: 'Instellingen geladen.',
          en: 'Settings loaded.',
          fr: 'Parametres charges.',
          es: 'Configuracion cargada.',
        );
      });
      // Refresh local caches with the merged/initial results, best-effort.
      unawaited(updateLocalBackendBusinessProfileCache(merged));
      if (cachedTax == null) {
        unawaited(updateLocalBackendTaxProfileCache(rawTax));
      }
    } catch (e) {
      if (!mounted) return;
      // Prefer the local cache when available; only fall back to defaults +
      // local CompanyProfile preview when no cache exists yet.
      final cached = localBackendBusinessProfileNotifier.value;
      final cachedTax = localBackendTaxProfileNotifier.value;
      setState(() {
        _hydrateBackendBusinessProfile(
          cached ??
              mergeLocalIntoBackendPreview(
                BackendBusinessProfile.defaults(),
                companyProfileNotifier.value,
              ),
        );
        _hydrateBackendTaxProfile(cachedTax ?? BackendTaxProfile.defaults());
        _mergeLocalIntoGeneralControllersIfEligible();
        final hasLocal =
            cached != null ||
            cachedTax != null ||
            companyProfileNotifier.value != null;
        _backendProfilesError = hasLocal
            ? _t(
                nl: 'Online bedrijfsinstellingen niet geladen. Lokale bedrijfsgegevens blijven beschikbaar.',
                en: 'Online business settings could not be loaded. Local company details remain available.',
                fr: 'Les parametres en ligne n ont pas pu etre charges. Les informations locales restent disponibles.',
                es: 'No se pudieron cargar los ajustes online. Los datos locales siguen disponibles.',
              )
            : _t(
                nl: 'Instellingen konden niet worden geladen. Standaardwaarden blijven zichtbaar.',
                en: 'Settings could not be loaded. Defaults remain visible.',
                fr: 'Impossible de charger les parametres. Les valeurs par defaut restent visibles.',
                es: 'No se pudo cargar la configuracion. Se muestran valores predeterminados.',
              );
      });
    } finally {
      if (mounted) {
        setState(() => _backendProfilesLoading = false);
      }
    }
  }

  String _googleCalendarSource() {
    return (_googleCalendarStatus?['source'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
  }

  bool _googleCalendarConnected() {
    return _googleCalendarStatus?['connected'] == true;
  }

  bool _googleCalendarConfigured() {
    return _googleCalendarStatus?['configured'] == true;
  }

  String _googleCalendarStatusCode() {
    if (_googleCalendarStatusError != null) return 'check_failed';
    final source = _googleCalendarSource();
    if (source == 'global_env') return 'legacy_global';
    if (_googleCalendarConnected()) return 'connected';
    final raw = (_googleCalendarStatus?['status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (raw == 'auth_required') return 'auth_required';
    if (raw == 'failed') return 'failed';
    if (!_googleCalendarConfigured() || raw == 'not_configured') {
      return 'not_configured';
    }
    return 'check_failed';
  }

  _SetupStatus _googleCalendarSetupStatus() {
    switch (_googleCalendarStatusCode()) {
      case 'connected':
        return _SetupStatus.complete;
      case 'legacy_global':
      case 'auth_required':
      case 'failed':
        return _SetupStatus.attention;
      case 'not_configured':
      case 'check_failed':
      default:
        return _SetupStatus.incomplete;
    }
  }

  String _googleCalendarStatusLabel() {
    switch (_googleCalendarStatusCode()) {
      case 'connected':
        return _t(
          nl: 'Verbonden',
          en: 'Connected',
          fr: 'Connecté',
          es: 'Conectado',
        );
      case 'auth_required':
      case 'failed':
        return _t(
          nl: 'Opnieuw koppelen vereist',
          en: 'Reconnect required',
          fr: 'Reconnexion requise',
          es: 'Requiere reconexión',
        );
      case 'legacy_global':
        return _t(
          nl: 'Legacy-koppeling actief',
          en: 'Legacy connection active',
          fr: 'Connexion héritée active',
          es: 'Conexión heredada activa',
        );
      case 'not_configured':
        return _t(
          nl: 'Niet geconfigureerd',
          en: 'Not configured',
          fr: 'Non configuré',
          es: 'No configurado',
        );
      case 'check_failed':
      default:
        return _t(
          nl: 'Controle mislukt',
          en: 'Check failed',
          fr: 'Échec du contrôle',
          es: 'Error de comprobación',
        );
    }
  }

  String _googleCalendarDescription() {
    switch (_googleCalendarStatusCode()) {
      case 'connected':
        return _t(
          nl: 'Google Calendar is gekoppeld voor dit bedrijf.',
          en: 'Google Calendar is connected for this company.',
          fr: 'Google Agenda est connecté pour cette entreprise.',
          es: 'Google Calendar está conectado para esta empresa.',
        );
      case 'legacy_global':
        return _t(
          nl: 'Deze koppeling gebruikt nog de legacy globale configuratie. Koppel Google Calendar opnieuw voor dit bedrijf.',
          en: 'This connection still uses the legacy global configuration. Reconnect Google Calendar for this company.',
          fr: 'Cette connexion utilise encore la configuration globale héritée. Reconnectez Google Agenda pour cette entreprise.',
          es: 'Esta conexión aún usa la configuración global heredada. Vuelve a conectar Google Calendar para esta empresa.',
        );
      case 'auth_required':
      case 'failed':
      case 'not_configured':
      case 'check_failed':
      default:
        return _t(
          nl: 'Koppel Google Calendar opnieuw voor dit bedrijf.',
          en: 'Reconnect Google Calendar for this company.',
          fr: 'Reconnectez Google Agenda pour cette entreprise.',
          es: 'Vuelve a conectar Google Calendar para esta empresa.',
        );
    }
  }

  String _googleCalendarPrimaryActionLabel() {
    switch (_googleCalendarStatusCode()) {
      case 'not_configured':
        return _t(
          nl: 'Koppelen',
          en: 'Connect',
          fr: 'Connecter',
          es: 'Conectar',
        );
      default:
        return _t(
          nl: 'Opnieuw koppelen',
          en: 'Reconnect',
          fr: 'Reconnecter',
          es: 'Volver a conectar',
        );
    }
  }

  String? _calendarStatusField(String key) {
    final raw = (_googleCalendarStatus?[key] ?? '').toString().trim();
    return raw.isEmpty ? null : raw;
  }

  Future<void> _loadGoogleCalendarStatus({bool showErrorSnack = false}) async {
    setState(() {
      _googleCalendarLoading = true;
      _googleCalendarStatusError = null;
    });
    try {
      final scope = _activeSettingsScope();
      final data = await fetchBackendGoogleCalendarStatus(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return;
      setState(() {
        _googleCalendarStatus = data;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _googleCalendarStatusError = e.toString();
      });
      if (showErrorSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Google Calendar status kon niet geladen worden.',
                en: 'Google Calendar status could not be loaded.',
                fr: 'Le statut Google Agenda n’a pas pu être chargé.',
                es: 'No se pudo cargar el estado de Google Calendar.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _googleCalendarLoading = false);
      }
    }
  }

  Future<void> _startGoogleCalendarReconnect() async {
    setState(() => _googleCalendarReconnectLoading = true);
    try {
      final scope = _activeSettingsScope();
      final data = await startBackendGoogleCalendarOAuth(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      final authUrl = (data['auth_url'] ?? '').toString().trim();
      if (authUrl.isEmpty) {
        throw Exception('missing_auth_url');
      }
      final launched = await launchUrl(
        Uri.parse(authUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw Exception('launch_failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Google OAuth geopend. Rond de koppeling af in je browser.',
              en: 'Google OAuth opened. Finish the connection in your browser.',
              fr: 'OAuth Google ouvert. Terminez la connexion dans votre navigateur.',
              es: 'OAuth de Google abierto. Termina la conexión en tu navegador.',
            ),
          ),
        ),
      );
      unawaited(_loadGoogleCalendarStatus());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Google Calendar koppeling kon niet gestart worden.',
              en: 'Google Calendar connection could not be started.',
              fr: 'La connexion Google Agenda n’a pas pu être démarrée.',
              es: 'No se pudo iniciar la conexión de Google Calendar.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _googleCalendarReconnectLoading = false);
      }
    }
  }

  Widget _googleCalendarCard() {
    final calendarId = _calendarStatusField('calendar_id');
    final accountEmail = _calendarStatusField('account_email');
    final lastConnectedAt = _calendarStatusField('last_connected_at');
    final lastSyncAt = _calendarStatusField('last_sync_at');
    final lastErrorCode = _calendarStatusField('last_error_code');
    final lastErrorAt = _calendarStatusField('last_error_at');
    return _collapsibleSettingsCard(
      id: 'google_calendar',
      icon: Icons.calendar_month_outlined,
      title: _t(
        nl: 'Google Calendar',
        en: 'Google Calendar',
        fr: 'Google Agenda',
        es: 'Google Calendar',
      ),
      subtitle: _t(
        nl: 'Kalenderkoppeling en herverbinden',
        en: 'Calendar connection and reconnect',
        fr: 'Connexion agenda et reconnexion',
        es: 'Conexión de calendario y reconexión',
      ),
      status: _googleCalendarSetupStatus(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_googleCalendarLoading && _googleCalendarStatus == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          Text(
            _googleCalendarStatusLabel(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _googleCalendarDescription(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          if (calendarId != null)
            Text(
              '${_t(nl: 'Kalender-ID', en: 'Calendar ID', fr: 'ID agenda', es: 'ID de calendario')}: $calendarId',
              style: const TextStyle(color: Colors.white70, fontSize: 11.5),
            ),
          if (accountEmail != null)
            Text(
              '${_t(nl: 'Account', en: 'Account', fr: 'Compte', es: 'Cuenta')}: $accountEmail',
              style: const TextStyle(color: Colors.white70, fontSize: 11.5),
            ),
          if (lastConnectedAt != null)
            Text(
              '${_t(nl: 'Laatste koppeling', en: 'Last connected', fr: 'Dernière connexion', es: 'Última conexión')}: $lastConnectedAt',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          if (lastSyncAt != null)
            Text(
              '${_t(nl: 'Laatste sync', en: 'Last sync', fr: 'Dernière synchro', es: 'Última sincronización')}: $lastSyncAt',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          if (lastErrorCode != null)
            Text(
              '${_t(nl: 'Foutcode', en: 'Error code', fr: 'Code erreur', es: 'Código de error')}: $lastErrorCode',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          if (lastErrorAt != null)
            Text(
              '${_t(nl: 'Laatste fout', en: 'Last error', fr: 'Dernière erreur', es: 'Último error')}: $lastErrorAt',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _googleCalendarReconnectLoading
                    ? null
                    : _startGoogleCalendarReconnect,
                icon: _googleCalendarReconnectLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_outlined),
                label: Text(_googleCalendarPrimaryActionLabel()),
              ),
              OutlinedButton.icon(
                onPressed: _googleCalendarLoading
                    ? null
                    : () => _loadGoogleCalendarStatus(showErrorSnack: true),
                icon: const Icon(Icons.refresh),
                label: Text(
                  _t(
                    nl: 'Vernieuwen',
                    en: 'Refresh',
                    fr: 'Actualiser',
                    es: 'Actualizar',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  BackendBusinessProfile _backendBusinessProfileFromForm() {
    return BackendBusinessProfile(
      companyName: _backendCompanyNameCtrl.text.trim(),
      legalName: _backendLegalNameCtrl.text.trim(),
      vatNumber: _backendVatNumberCtrl.text.trim(),
      companyRegistrationNumber: _backendRegistrationCtrl.text.trim(),
      address: _backendAddressCtrl.text.trim(),
      postcode: _backendPostcodeCtrl.text.trim(),
      city: _backendCityCtrl.text.trim(),
      country: _backendCountryCtrl.text.trim(),
      phone: _backendPhoneCtrl.text.trim(),
      email: _backendEmailCtrl.text.trim(),
      website: _backendWebsiteCtrl.text.trim(),
      bookingEmail: _backendBookingEmailCtrl.text.trim(),
      invoiceEmail: _backendInvoiceEmailCtrl.text.trim(),
      iban: _backendIbanCtrl.text.trim(),
      paymentReferencePrefix: _backendPaymentPrefixCtrl.text.trim(),
      invoiceReceiptFooterText: _backendFooterCtrl.text.trim(),
    );
  }

  BackendTaxProfile _backendTaxProfileFromForm() {
    final rawPct = double.tryParse(
      _backendVatRateCtrl.text.replaceAll(',', '.').trim(),
    );
    final pct = (rawPct == null || !rawPct.isFinite)
        ? 6.0
        : rawPct.clamp(0.0, 100.0).toDouble();
    return BackendTaxProfile(
      vatEnabled: _backendVatEnabled,
      vatRate: pct / 100.0,
      vatDisplayMode: _backendVatDisplayMode,
      vatLabels: <String, String>{
        'nl': _backendVatLabelNlCtrl.text.trim(),
        'en': _backendVatLabelEnCtrl.text.trim(),
        'fr': _backendVatLabelFrCtrl.text.trim(),
        'es': _backendVatLabelEsCtrl.text.trim(),
      },
    );
  }

  Future<void> _saveBackendBusinessProfile() async {
    setState(() {
      _backendBusinessSaving = true;
      _backendProfilesError = null;
      _backendProfilesStatus = null;
    });
    final formProfile = _backendBusinessProfileFromForm();
    // Save to local cache first so user-entered values survive app restart
    // even if the backend HTTP call fails or the device is offline.
    await updateLocalBackendBusinessProfileCache(formProfile);
    try {
      final scope = _activeSettingsScope();
      final saved = await saveBackendBusinessProfile(
        formProfile,
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return;
      // Merge so empty backend echo does not erase locally entered values.
      final merged = _mergeBackendBusinessProfile(
        local: formProfile,
        server: saved,
      );
      setState(() {
        _hydrateBackendBusinessProfile(merged);
        _backendProfilesStatus = _t(
          nl: 'Bedrijfsprofiel opgeslagen.',
          en: 'Business profile saved.',
          fr: 'Profil entreprise enregistre.',
          es: 'Perfil empresarial guardado.',
        );
      });
      unawaited(updateLocalBackendBusinessProfileCache(merged));
    } catch (e) {
      if (!mounted) return;
      // Local cache stays intact (saved above); just surface the existing
      // error message so the UI behaviour remains the same as before.
      setState(
        () => _backendProfilesError =
            '${_t(nl: 'Opslaan mislukt', en: 'Save failed', fr: 'Echec de l enregistrement', es: 'Error al guardar')}: $e',
      );
    } finally {
      if (mounted) setState(() => _backendBusinessSaving = false);
    }
  }

  Future<void> _saveBackendTaxProfile() async {
    setState(() {
      _backendTaxSaving = true;
      _backendProfilesError = null;
      _backendProfilesStatus = null;
    });
    final formProfile = _backendTaxProfileFromForm();
    // Save to local cache first so user-entered VAT settings survive app
    // restart even if the backend HTTP call fails or the device is offline.
    await updateLocalBackendTaxProfileCache(formProfile);
    try {
      final scope = _activeSettingsScope();
      final saved = await saveBackendTaxProfile(
        formProfile,
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return;
      setState(() {
        _hydrateBackendTaxProfile(saved);
        _backendProfilesStatus = _t(
          nl: 'BTW-profiel opgeslagen.',
          en: 'VAT profile saved.',
          fr: 'Profil TVA enregistre.',
          es: 'Perfil IVA guardado.',
        );
      });
      // Refresh local cache with the server-confirmed result, best-effort.
      unawaited(updateLocalBackendTaxProfileCache(saved));
      final pricingScope = _activeSettingsScope();
      unawaited(
        syncPricingProfileToBackend(
          tenantId: pricingScope.tenantId,
          companyId: pricingScope.companyId,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // Local cache stays intact (saved above); just surface the existing
      // error message so the UI behaviour remains the same as before.
      setState(
        () => _backendProfilesError =
            '${_t(nl: 'Opslaan mislukt', en: 'Save failed', fr: 'Echec de l enregistrement', es: 'Error al guardar')}: $e',
      );
    } finally {
      if (mounted) setState(() => _backendTaxSaving = false);
    }
  }

  double _toMoney(String raw, double fallback) {
    final parsed = double.tryParse(raw.replaceAll(',', '.').trim());
    if (parsed == null || !parsed.isFinite) return fallback;
    if (parsed < 0) return 0;
    return parsed;
  }

  void _save() {
    final current = businessSettingsNotifier.value;
    final scope = _activeSettingsScope();
    final vat = _activeVatConfig();
    updateBusinessSettings(
      current.copyWith(
        companyName: _companyCtrl.text.trim(),
        supportEmail: _supportEmailCtrl.text.trim(),
        supportPhone: _supportPhoneCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        vatCompanyNumber: _vatCtrl.text.trim(),
        logoAssetPath: _storedLogoPathForLocalTenant(_logoPathCtrl.text.trim()),
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
        pricingMinimumFare: _toMoney(
          _minimumFareCtrl.text,
          current.pricingMinimumFare,
        ),
        pricingWaitPerMinute: _toMoney(
          _waitPerMinCtrl.text,
          current.pricingWaitPerMinute,
        ),
        pricingReturnEnabled: _pricingReturnEnabled,
        pricingReturnFee: _toMoney(
          _returnFeeCtrl.text,
          current.pricingReturnFee,
        ),
        pricingFuelSurcharge: _toMoney(
          _fuelSurchargeCtrl.text,
          current.pricingFuelSurcharge,
        ),
        pricingVatRate: vat.vatRate,
        pricingVatMode: vat.vatMode,
        pricingBagFeeEach: _toMoney(
          _bagFeeCtrl.text,
          current.pricingBagFeeEach,
        ),
        pricingStopFeeEach: _toMoney(
          _stopFeeCtrl.text,
          current.pricingStopFeeEach,
        ),
        pricingTierFeeComfort: _toMoney(
          _tierComfortFeeCtrl.text,
          current.pricingTierFeeComfort,
        ),
        pricingTierFeePrivate: _toMoney(
          _tierPrivateFeeCtrl.text,
          current.pricingTierFeePrivate,
        ),
        pricingTierFeePremium: _toMoney(
          _tierPremiumFeeCtrl.text,
          current.pricingTierFeePremium,
        ),
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
      tenantId: scope.tenantId,
      companyId: scope.companyId,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Instellingen bijgewerkt (runtime).',
            en: 'Settings updated (runtime).',
            fr: 'Parametres mis a jour (runtime).',
            es: 'Configuracion actualizada (runtime).',
          ),
        ),
      ),
    );
  }

  bool _isAssetRef(String value) =>
      value.trim().toLowerCase().startsWith('assets/');

  /// Normalizes logo paths for comparing default Fluxidi branding references.
  String _normalizeLogoRefForCompare(String raw) {
    return raw.trim().replaceAll('\\', '/').toLowerCase();
  }

  /// True for empty paths and any known packaged/default Fluxidi logo reference.
  bool _isDefaultFluxidiLogoRef(String raw) {
    final norm = _normalizeLogoRefForCompare(raw);
    if (norm.isEmpty) return true;
    final config = _normalizeLogoRefForCompare(appConfig.logoAsset);
    if (norm == config) return true;
    if (norm == 'assets/fluxidi/fluxidi_logo.png') return true;
    if (norm == 'fluxidi_logo.png') return true;
    if (norm.endsWith('/fluxidi_logo.png')) return true;
    if (norm.contains('assets/fluxidi/fluxidi_logo.png')) return true;
    return false;
  }

  /// Values persisted and shown in logo controllers: never store Fluxidi pack logo as tenant logo.
  String _storedLogoPathForLocalTenant(String raw) {
    if (companyProfileNotifier.value == null) return raw.trim();
    if (_isDefaultFluxidiLogoRef(raw)) return '';
    return raw.trim();
  }

  void _maybeNormalizeStoredLogoInNotifier() {
    if (companyProfileNotifier.value == null) return;
    final cur = businessSettingsNotifier.value;
    final next = _storedLogoPathForLocalTenant(cur.logoAssetPath);
    if (next == cur.logoAssetPath) return;
    final scope = _activeSettingsScope();
    updateBusinessSettings(
      cur.copyWith(logoAssetPath: next),
      tenantId: scope.tenantId,
      companyId: scope.companyId,
    );
  }

  /// When tenant profile/settings load or update, clear Fluxidi defaults from controllers — but do not
  /// clobber an unsaved non-default logo path the user already picked.
  void _syncLocalTenantLogoFromNotifier() {
    if (!mounted) return;
    if (companyProfileNotifier.value == null) return;
    final sanitized = _storedLogoPathForLocalTenant(
      businessSettingsNotifier.value.logoAssetPath,
    );
    final ctrl = _logoPathCtrl.text.trim();
    final adv = _logoAdvancedCtrl.text.trim();
    if (sanitized == ctrl && sanitized == adv) {
      _maybeNormalizeStoredLogoInNotifier();
      return;
    }
    if (!_isDefaultFluxidiLogoRef(ctrl) && ctrl.isNotEmpty) {
      _maybeNormalizeStoredLogoInNotifier();
      return;
    }
    setState(() {
      _logoPathCtrl.text = sanitized;
      _logoAdvancedCtrl.text = sanitized;
    });
    _maybeNormalizeStoredLogoInNotifier();
  }

  /// Logo path for company branding preview ([ValueListenableBuilder] uses controllers).
  String? _effectiveCompanyLogoRef(String? raw) {
    final s = _storedLogoPathForLocalTenant(raw ?? '');
    return s.isEmpty ? null : s;
  }

  Future<void> _pickLogoImage() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );
      if (picked == null) return;
      final persisted = await _persistPickedLogo(picked.path);
      // Persisted copy in app documents survives image_picker cache cleanup.
      // Fallback to the original picker path on copy failure to preserve UX.
      _setLogoRef(persisted ?? picked.path);
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

  Future<String?> _persistPickedLogo(String sourcePath) async {
    try {
      final source = sourcePath.trim();
      if (source.isEmpty) return null;
      final src = File(source);
      if (!await src.exists()) return null;

      final base = await getApplicationDocumentsDirectory();
      final dir = Directory(
        '${base.path}${Platform.pathSeparator}tenant_state'
        '${Platform.pathSeparator}company_logo',
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final ext = _logoFileExtension(source);
      final fileName =
          'logo_${DateTime.now().millisecondsSinceEpoch}${ext.isEmpty ? '' : '.$ext'}';
      final target = File('${dir.path}${Platform.pathSeparator}$fileName');
      await src.copy(target.path);
      return target.path;
    } catch (_) {
      return null;
    }
  }

  String _logoFileExtension(String path) {
    final lower = path.toLowerCase();
    final slash = lower.lastIndexOf(Platform.pathSeparator);
    final altSlash = lower.lastIndexOf('/');
    final base = lower.substring((slash > altSlash ? slash : altSlash) + 1);
    final dot = base.lastIndexOf('.');
    if (dot <= 0 || dot == base.length - 1) return '';
    final raw = base.substring(dot + 1);
    const allowed = <String>{
      'png',
      'jpg',
      'jpeg',
      'webp',
      'gif',
      'bmp',
      'heic',
    };
    return allowed.contains(raw) ? raw : '';
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
                  title: Text(
                    _t(
                      nl: 'Upload logo',
                      en: 'Upload logo',
                      fr: 'Televerser logo',
                      es: 'Subir logo',
                    ),
                  ),
                  subtitle: Text(
                    _t(
                      nl: 'Placeholder voor echte upload',
                      en: 'Placeholder for real upload',
                      fr: 'Placeholder pour upload reel',
                      es: 'Placeholder para carga real',
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _setLogoRef('assets/fluxidi/fluxidi_logo.png');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(
                    _t(
                      nl: 'Kies standaard logo',
                      en: 'Choose default logo',
                      fr: 'Choisir logo par defaut',
                      es: 'Elegir logo predeterminado',
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _setLogoRef('assets/fluxidi/fluxidi_logo.png');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: Text(
                    _t(
                      nl: 'Gebruik voorbeeldreferentie',
                      en: 'Use sample reference',
                      fr: 'Utiliser reference exemple',
                      es: 'Usar referencia de ejemplo',
                    ),
                  ),
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
    return ValueListenableBuilder<CompanyProfile?>(
      valueListenable: companyProfileNotifier,
      builder: (context, _, __) {
        final effectiveRef = _effectiveCompanyLogoRef(_logoPathCtrl.text);
        final ref = effectiveRef ?? '';
        final showImage = ref.isNotEmpty;
        final logoUnsetForPreview = !showImage;

        Widget previewChild;
        if (!showImage) {
          previewChild = _logoPlaceholder();
        } else if (_isAssetRef(ref)) {
          previewChild = ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Image.asset(
              ref,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _logoPlaceholder(),
            ),
          );
        } else {
          previewChild = ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: kIsWeb
                ? Image.network(
                    ref,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => _logoPlaceholder(),
                  )
                : Image.file(
                    File(ref),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => _logoPlaceholder(),
                  ),
          );
        }

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
                child: previewChild,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _pickLogoImage,
                  icon: const Icon(Icons.upload_file),
                  label: Text(
                    _t(
                      nl: 'Upload logo',
                      en: 'Upload logo',
                      fr: 'Televerser logo',
                      es: 'Subir logo',
                    ),
                  ),
                ),
                if (!logoUnsetForPreview) ...[
                  OutlinedButton.icon(
                    onPressed: _pickLogoImage,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(
                      _t(
                        nl: 'Logo wijzigen',
                        en: 'Change logo',
                        fr: 'Modifier logo',
                        es: 'Cambiar logo',
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _setLogoRef(''),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(
                      _t(
                        nl: 'Logo verwijderen',
                        en: 'Remove logo',
                        fr: 'Supprimer logo',
                        es: 'Quitar logo',
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => setState(
                () => _showAdvancedLogoPath = !_showAdvancedLogoPath,
              ),
              icon: Icon(
                _showAdvancedLogoPath ? Icons.expand_less : Icons.expand_more,
              ),
              label: Text(
                _t(
                  nl: 'Geavanceerd: handmatige referentie',
                  en: 'Advanced: manual reference',
                  fr: 'Avance: reference manuelle',
                  es: 'Avanzado: referencia manual',
                ),
              ),
            ),
            if (_showAdvancedLogoPath)
              _txt(
                _logoAdvancedCtrl,
                _t(
                  nl: 'Logo pad/referentie',
                  en: 'Logo path/reference',
                  fr: 'Chemin/reference logo',
                  es: 'Ruta/referencia logo',
                ),
                onChanged: (v) => _setLogoRef(v),
              ),
          ],
        );
      },
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
            _t(
              nl: 'Geen bedrijfslogo ingesteld',
              en: 'No company logo set',
              fr: 'Aucun logo d’entreprise défini',
              es: 'No hay logotipo de empresa configurado',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _collapsibleSettingsCard({
    required String id,
    required String title,
    required IconData icon,
    required String subtitle,
    required Widget child,
    _SetupStatus? status,
  }) {
    final isExpanded = _expandedSections.contains(id);
    final statusResolved = status ?? _SetupStatus.comingSoon;
    final statusColor = _statusColor(statusResolved);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF101010), Color(0xFF07080C)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _setupGold.withOpacity(0.22)),
        boxShadow: [
          BoxShadow(
            color: _setupGold.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 0.2,
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedSections.remove(id);
            } else {
              _expandedSections.add(id);
            }
          });
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: const Color(0xFF15120A),
                    border: Border.all(color: _setupGold.withOpacity(0.32)),
                  ),
                  child: Icon(icon, size: 19, color: _setupGold),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.65),
                          fontSize: 11.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: statusColor.withOpacity(0.50),
                        ),
                      ),
                      child: Text(
                        _statusLabel(statusResolved),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10.6,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: _setupGold.withOpacity(0.95),
                      size: 22,
                    ),
                  ],
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: isExpanded
                  ? Column(
                      children: [
                        const SizedBox(height: 10),
                        Container(
                          height: 1,
                          color: Colors.white.withOpacity(0.10),
                        ),
                        const SizedBox(height: 10),
                        child,
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notice(String text, {bool isError = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFF3A1010) : const Color(0xFF12331F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError
              ? Colors.redAccent.withOpacity(.45)
              : Colors.greenAccent.withOpacity(.35),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isError
              ? Colors.redAccent.shade100
              : Colors.greenAccent.shade100,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _effectivePublicCompanyId() {
    final active = companyProfileNotifier.value?.companyId.trim() ?? '';
    if (active.isNotEmpty) return active;
    final resolved = resolvedCompanyId.trim();
    if (resolved.isNotEmpty) return resolved;
    return kTenantId;
  }

  ({String tenantId, String companyId}) _activeSettingsScope() {
    final activeCompanyId = _effectivePublicCompanyId().trim();
    final companyId = activeCompanyId.isEmpty ? kTenantId : activeCompanyId;
    return (tenantId: companyId, companyId: companyId);
  }

  ActiveVatConfig _activeVatConfig() {
    return resolveActiveVatConfig(
      settings: businessSettingsNotifier.value,
      taxProfile: localBackendTaxProfileNotifier.value,
    );
  }

  String _preparedPublicBookingUrl(String companyId) {
    final safeCompanyId = companyId.trim().isEmpty
        ? kTenantId
        : companyId.trim();
    final base = kPublicBookingBaseUrl.trim().isEmpty
        ? 'https://fluxidi.com/book'
        : kPublicBookingBaseUrl.trim();
    final encodedCompanyId = Uri.encodeQueryComponent(safeCompanyId);
    try {
      final uri = Uri.parse(base);
      final nextQuery = Map<String, String>.from(uri.queryParameters);
      nextQuery['company_id'] = safeCompanyId;
      return uri.replace(queryParameters: nextQuery).toString();
    } catch (_) {
      return '$base?company_id=$encodedCompanyId';
    }
  }

  Widget _txt(
    TextEditingController ctrl,
    String label, {
    ValueChanged<String>? onChanged,
    int maxLines = 1,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        onChanged: onChanged,
        maxLines: maxLines,
        readOnly: readOnly,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          alignLabelWithHint: maxLines > 1,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 16,
          ),
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
      children: options
          .map((o) {
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
              subtitle: Text(
                o.payloadValue,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  bool _nonEmpty(String value) => value.trim().isNotEmpty;

  bool _validPositiveNumber(String value) {
    final parsed = double.tryParse(value.replaceAll(',', '.').trim());
    return parsed != null && parsed.isFinite && parsed > 0;
  }

  Color get _setupGold => appConfig.primaryColor;

  String _statusLabel(_SetupStatus status) {
    switch (status) {
      case _SetupStatus.complete:
        return _t(
          nl: 'Compleet',
          en: 'Complete',
          fr: 'Complet',
          es: 'Completo',
        );
      case _SetupStatus.attention:
        return _t(
          nl: 'Aandacht nodig',
          en: 'Needs attention',
          fr: 'Attention requise',
          es: 'Requiere atención',
        );
      case _SetupStatus.incomplete:
        return _t(
          nl: 'Onvolledig',
          en: 'Incomplete',
          fr: 'Incomplet',
          es: 'Incompleto',
        );
      case _SetupStatus.comingSoon:
        return _t(
          nl: 'Binnenkort',
          en: 'Coming soon',
          fr: 'Bientôt',
          es: 'Próximamente',
        );
    }
  }

  Color _statusColor(_SetupStatus status) {
    switch (status) {
      case _SetupStatus.complete:
        return const Color(0xFF4ADE80);
      case _SetupStatus.attention:
        return const Color(0xFFE5B641);
      case _SetupStatus.incomplete:
        return const Color(0xFFF87171);
      case _SetupStatus.comingSoon:
        return Colors.grey.shade500;
    }
  }

  _SetupStatus _detailsStatus() {
    final fields = <String>[
      _backendCompanyNameCtrl.text,
      _backendLegalNameCtrl.text,
      _backendVatNumberCtrl.text,
      _backendAddressCtrl.text,
      _backendPostcodeCtrl.text,
      _backendCityCtrl.text,
      _backendCountryCtrl.text,
      _backendEmailCtrl.text,
      _backendPhoneCtrl.text,
    ];
    final completed = fields.where((f) => _nonEmpty(f)).length;
    if (completed == fields.length) return _SetupStatus.complete;
    if (completed >= 4) return _SetupStatus.attention;
    return _SetupStatus.incomplete;
  }

  _SetupStatus _billingVatStatus() {
    final hasVatEnabled = _backendVatEnabled;
    final hasVatRate = _validPositiveNumber(_backendVatRateCtrl.text);
    final hasVatMode = _nonEmpty(_backendVatDisplayMode);
    final hasInvoiceEmail = _nonEmpty(_backendInvoiceEmailCtrl.text);
    final hasIban = _nonEmpty(_backendIbanCtrl.text);
    final checks = <bool>[
      hasVatEnabled,
      hasVatRate,
      hasVatMode,
      hasInvoiceEmail,
      hasIban,
    ];
    final score = checks.where((v) => v).length;
    if (score == checks.length) return _SetupStatus.complete;
    if (score >= 2) return _SetupStatus.attention;
    return _SetupStatus.incomplete;
  }

  _SetupStatus _brandingSupportStatus() {
    final hasBrandName = _nonEmpty(_companyCtrl.text);
    final hasSupportEmail = _nonEmpty(_supportEmailCtrl.text);
    final hasSupportPhone = _nonEmpty(_supportPhoneCtrl.text);
    final hasLogo = _effectiveCompanyLogoRef(_logoPathCtrl.text) != null;
    final checks = <bool>[
      hasBrandName,
      hasSupportEmail,
      hasSupportPhone,
      hasLogo,
    ];
    final score = checks.where((v) => v).length;
    if (score == checks.length) return _SetupStatus.complete;
    if (score >= 2) return _SetupStatus.attention;
    return _SetupStatus.incomplete;
  }

  _SetupStatus _pricingStatus() {
    final checks = <bool>[
      _validPositiveNumber(_baseFareCtrl.text),
      _validPositiveNumber(_perKmCtrl.text),
      _validPositiveNumber(_perMinCtrl.text),
      _validPositiveNumber(_minimumFareCtrl.text),
    ];
    final score = checks.where((v) => v).length;
    if (score == checks.length) return _SetupStatus.complete;
    if (score >= 1) return _SetupStatus.attention;
    return _SetupStatus.incomplete;
  }

  _SetupStatus _servicesTiersStatus() {
    final hasServices = _serviceIds.isNotEmpty;
    final hasTiers = _tierIds.isNotEmpty;
    if (hasServices && hasTiers) return _SetupStatus.complete;
    if (hasServices || hasTiers) return _SetupStatus.attention;
    return _SetupStatus.incomplete;
  }

  _SetupStatus _publicLinkStatus() {
    final activeCompanyId =
        companyProfileNotifier.value?.companyId.trim() ?? '';
    final usingFallbackId = activeCompanyId.isEmpty;
    if (usingFallbackId) return _SetupStatus.incomplete;
    final prepared = _preparedPublicBookingUrl(_effectivePublicCompanyId());
    if (_nonEmpty(prepared)) return _SetupStatus.attention;
    return _SetupStatus.comingSoon;
  }

  List<_SetupItem> _setupItems() {
    return <_SetupItem>[
      _SetupItem(
        title: _t(
          nl: 'Bedrijfsgegevens',
          en: 'Company details',
          fr: 'Informations entreprise',
          es: 'Datos de empresa',
        ),
        subtitle: _t(
          nl: 'Naam, adres en contact',
          en: 'Name, address and contact',
          fr: 'Nom, adresse et contact',
          es: 'Nombre, dirección y contacto',
        ),
        icon: Icons.business_outlined,
        status: _detailsStatus(),
      ),
      _SetupItem(
        title: _t(
          nl: 'Facturatie & BTW',
          en: 'Billing & VAT',
          fr: 'Facturation et TVA',
          es: 'Facturación e IVA',
        ),
        subtitle: _t(
          nl: 'BTW, facturatie en IBAN',
          en: 'Tax, invoicing and IBAN',
          fr: 'TVA, facturation et IBAN',
          es: 'IVA, facturación e IBAN',
        ),
        icon: Icons.receipt_long_outlined,
        status: _billingVatStatus(),
      ),
      _SetupItem(
        title: _t(
          nl: 'Branding & support',
          en: 'Branding & support',
          fr: 'Branding et support',
          es: 'Marca y soporte',
        ),
        subtitle: _t(
          nl: 'Merknaam, support en logo',
          en: 'Brand, support and logo',
          fr: 'Marque, support et logo',
          es: 'Marca, soporte y logo',
        ),
        icon: Icons.brush_outlined,
        status: _brandingSupportStatus(),
      ),
      _SetupItem(
        title: _t(
          nl: 'Prijsinstellingen',
          en: 'Pricing settings',
          fr: 'Paramètres tarifaires',
          es: 'Ajustes de precio',
        ),
        subtitle: _t(
          nl: 'Basistarief en kernprijzen',
          en: 'Base fare and core prices',
          fr: 'Tarif de base et prix clés',
          es: 'Tarifa base y precios clave',
        ),
        icon: Icons.local_offer_outlined,
        status: _pricingStatus(),
      ),
      _SetupItem(
        title: _t(
          nl: 'Services & tiers',
          en: 'Services & tiers',
          fr: 'Services et catégories',
          es: 'Servicios y categorías',
        ),
        subtitle: _t(
          nl: 'Actieve ritopties',
          en: 'Enabled ride options',
          fr: 'Options de course actives',
          es: 'Opciones de viaje activas',
        ),
        icon: Icons.local_taxi_outlined,
        status: _servicesTiersStatus(),
      ),
      _SetupItem(
        title: _t(
          nl: 'Publieke boekingslink',
          en: 'Public booking link',
          fr: 'Lien de réservation public',
          es: 'Enlace público de reserva',
        ),
        subtitle: _t(
          nl: 'Voorbereid, nog niet live',
          en: 'Prepared, not live yet',
          fr: 'Préparé, pas encore en ligne',
          es: 'Preparado, aún no en vivo',
        ),
        icon: Icons.link_outlined,
        status: _publicLinkStatus(),
      ),
    ];
  }

  Widget _setupStatusChip(_SetupStatus status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildSetupItemCard(_SetupItem item, {required double width}) {
    final statusColor = _statusColor(item.status);
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF101010), Color(0xFF07080C)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _setupGold.withOpacity(0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor.withOpacity(0.45)),
                ),
                child: Icon(item.icon, size: 18, color: statusColor),
              ),
              const Spacer(),
              _setupStatusChip(item.status),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.66),
              fontSize: 11.2,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupCockpit() {
    final items = _setupItems();
    final completeCount = items
        .where((item) => item.status == _SetupStatus.complete)
        .length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF15120A), Color(0xFF101010), Color(0xFF07080C)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _setupGold.withOpacity(0.32)),
        boxShadow: [
          BoxShadow(
            color: _setupGold.withOpacity(0.09),
            blurRadius: 14,
            spreadRadius: 0.4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              nl: 'Setup voortgang',
              en: 'Setup progress',
              fr: 'Progression de configuration',
              es: 'Progreso de configuración',
            ),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _t(
              nl: 'Maak je bedrijf klaar voor boekingen.',
              en: 'Get your business ready for bookings.',
              fr: 'Préparez votre entreprise pour les réservations.',
              es: 'Prepara tu empresa para recibir reservas.',
            ),
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 12.3,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF07080C).withOpacity(0.86),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _setupGold.withOpacity(0.28)),
            ),
            child: Row(
              children: [
                Text(
                  _t(
                    nl: 'Instellingen overzicht',
                    en: 'Settings overview',
                    fr: 'Aperçu des paramètres',
                    es: 'Resumen de ajustes',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '$completeCount/${items.length} ${_t(nl: 'voltooid', en: 'completed', fr: 'terminé', es: 'completado')}',
                  style: TextStyle(
                    color: _setupGold,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              if (compact) {
                return Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      _buildSetupItemCard(
                        items[i],
                        width: constraints.maxWidth,
                      ),
                      if (i < items.length - 1) const SizedBox(height: 8),
                    ],
                  ],
                );
              }
              final cardWidth = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in items)
                    _buildSetupItemCard(item, width: cardWidth),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _t(
                        nl: 'Controleer de kaarten hierboven en vul ontbrekende velden in de formulieren hieronder aan.',
                        en: 'Review the cards above and complete missing fields in the forms below.',
                        fr: 'Vérifiez les cartes ci-dessus et complétez les champs manquants dans les formulaires ci-dessous.',
                        es: 'Revisa las tarjetas de arriba y completa los campos faltantes en los formularios de abajo.',
                      ),
                    ),
                  ),
                );
              },
              icon: Icon(Icons.checklist_outlined, color: _setupGold, size: 18),
              label: Text(
                _t(
                  nl: 'Controleer ontbrekende items',
                  en: 'Check missing items',
                  fr: 'Vérifier les éléments manquants',
                  es: 'Revisar elementos pendientes',
                ),
                style: TextStyle(
                  color: _setupGold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
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
          title: Text(
            _t(
              nl: 'Bedrijfsinstellingen',
              en: 'Business settings',
              fr: 'Parametres entreprise',
              es: 'Configuracion de empresa',
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_backendProfilesLoading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 10),
            ],
            if (_backendProfilesError != null) ...[
              _notice(_backendProfilesError!, isError: true),
              const SizedBox(height: 10),
            ],
            if (_backendProfilesStatus != null) ...[
              _notice(_backendProfilesStatus!),
              const SizedBox(height: 10),
            ],
            _buildSetupCockpit(),
            _collapsibleSettingsCard(
              id: 'local_company',
              icon: Icons.apartment_outlined,
              title: _t(
                nl: 'Lokaal bedrijf (dit toestel)',
                en: 'Local company (this device)',
                fr: 'Entreprise locale (cet appareil)',
                es: 'Empresa local (este dispositivo)',
              ),
              subtitle: _t(
                nl: 'Tenant-ID en lokale status',
                en: 'Tenant ID and local status',
                fr: 'ID tenant et statut local',
                es: 'ID de tenant y estado local',
              ),
              status: _detailsStatus(),
              child: ValueListenableBuilder<CompanyProfile?>(
                valueListenable: companyProfileNotifier,
                builder: (context, _, __) {
                  final p = companyProfileNotifier.value;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _t(
                                    nl: 'Bedrijfs-/tenant-ID (alleen lezen)',
                                    en: 'Company / tenant ID (read-only)',
                                    fr: 'ID entreprise / tenant (lecture seule)',
                                    es: 'ID de empresa / tenant (solo lectura)',
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  resolvedCompanyId,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: _t(
                              nl: 'ID kopiëren',
                              en: 'Copy ID',
                              fr: 'Copier l ID',
                              es: 'Copiar ID',
                            ),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: resolvedCompanyId),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _t(
                                      nl: 'Bedrijfs-ID gekopieerd.',
                                      en: 'Company ID copied.',
                                      fr: 'ID entreprise copie.',
                                      es: 'ID de empresa copiado.',
                                    ),
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy, color: Colors.white54),
                          ),
                        ],
                      ),
                      if (p != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _t(
                            nl: 'Bedrijfsstatus',
                            en: 'Company status',
                            fr: 'Statut de l entreprise',
                            es: 'Estado de la empresa',
                          ),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: p.isSuspended
                                  ? const Color(0xFF3A1010)
                                  : p.isVerified
                                  ? const Color(0xFF12331F)
                                  : const Color(0xFF2A2410),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: p.isSuspended
                                    ? Colors.red.withOpacity(0.45)
                                    : p.isVerified
                                    ? const Color(0xFF4ADE80).withOpacity(0.45)
                                    : const Color(0xFFE5B641).withOpacity(0.55),
                              ),
                            ),
                            child: Text(
                              p.verificationBadgeLabel(_lang),
                              style: TextStyle(
                                color: p.isSuspended
                                    ? const Color(0xFFFFB4B4)
                                    : p.isVerified
                                    ? const Color(0xFFB8F5C8)
                                    : const Color(0xFFE5D4A1),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        if (p.showsPendingVerificationNotice) ...[
                          const SizedBox(height: 8),
                          Text(
                            p.verificationPendingNotice(_lang),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.62),
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ],
                  );
                },
              ),
            ),
            _collapsibleSettingsCard(
              id: 'public_booking_link',
              icon: Icons.link_outlined,
              title: _t(
                nl: 'Publieke boekingslink',
                en: 'Public booking link',
                fr: 'Lien de réservation public',
                es: 'Enlace público de reserva',
              ),
              subtitle: _t(
                nl: 'Web/QR-link voorbereiding',
                en: 'Web/QR link preparation',
                fr: 'Préparation lien web/QR',
                es: 'Preparación de enlace web/QR',
              ),
              status: _publicLinkStatus(),
              child: ValueListenableBuilder<CompanyProfile?>(
                valueListenable: companyProfileNotifier,
                builder: (context, _, __) {
                  final activeCompanyId =
                      companyProfileNotifier.value?.companyId.trim() ?? '';
                  final effectiveCompanyId = _effectivePublicCompanyId();
                  final publicBookingUrl = _preparedPublicBookingUrl(
                    effectiveCompanyId,
                  );
                  final usingFallbackId = activeCompanyId.isEmpty;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _t(
                                    nl: 'Voorbereide publieke link',
                                    en: 'Prepared public link',
                                    fr: 'Lien public préparé',
                                    es: 'Enlace público preparado',
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  publicBookingUrl,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: _t(
                              nl: 'Publieke link kopiëren',
                              en: 'Copy public link',
                              fr: 'Copier le lien public',
                              es: 'Copiar enlace público',
                            ),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: publicBookingUrl),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _t(
                                      nl: 'Publieke boekingslink gekopieerd',
                                      en: 'Public booking link copied',
                                      fr: 'Lien de réservation public copié',
                                      es: 'Enlace público de reserva copiado',
                                    ),
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy, color: Colors.white54),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _t(
                          nl: 'Deze link is voorbereid voor websiteboekingen, QR-codes en sociale media. De publieke boekingspagina wordt in een volgende stap geactiveerd.',
                          en: 'This link is prepared for website bookings, QR codes and social media. The public booking page will be activated in a next step.',
                          fr: 'Ce lien est préparé pour les réservations via site web, QR codes et réseaux sociaux. La page de réservation publique sera activée lors d’une prochaine étape.',
                          es: 'Este enlace está preparado para reservas desde la web, códigos QR y redes sociales. La página pública de reserva se activará en un siguiente paso.',
                        ),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.qr_code_2_outlined,
                            size: 16,
                            color: Colors.white54,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _t(
                              nl: 'QR-code volgt',
                              en: 'QR code coming next',
                              fr: 'QR code à venir',
                              es: 'Código QR próximamente',
                            ),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.language_outlined,
                            size: 16,
                            color: Colors.white54,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _t(
                              nl: 'Websiteknop/embed volgt',
                              en: 'Website button/embed coming next',
                              fr: 'Bouton/intégration site web à venir',
                              es: 'Botón/integración web próximamente',
                            ),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      if (usingFallbackId) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.orangeAccent.withOpacity(0.45),
                            ),
                          ),
                          child: Text(
                            _t(
                              nl: 'Actieve bedrijfs-ID ontbreekt. De voorbereide link gebruikt momenteel een fallback-ID.',
                              en: 'Active company ID is missing. The prepared link currently uses a fallback ID.',
                              fr: 'L’ID entreprise active est manquant. Le lien préparé utilise actuellement un ID de secours.',
                              es: 'Falta el ID activo de empresa. El enlace preparado usa actualmente un ID de respaldo.',
                            ),
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            _googleCalendarCard(),
            _collapsibleSettingsCard(
              id: 'official_company_details',
              icon: Icons.business_outlined,
              title: _t(
                nl: 'Officiële bedrijfsgegevens',
                en: 'Official company details',
                fr: 'Informations officielles de l entreprise',
                es: 'Datos oficiales de la empresa',
              ),
              subtitle: _t(
                nl: 'Juridische en factuurgegevens',
                en: 'Legal and invoice details',
                fr: 'Données juridiques et de facturation',
                es: 'Datos legales y de facturación',
              ),
              status: _detailsStatus(),
              child: Column(
                children: [
                  _txt(
                    _backendCompanyNameCtrl,
                    _t(
                      nl: 'Bedrijfsnaam',
                      en: 'Company name',
                      fr: 'Nom de l entreprise',
                      es: 'Nombre de la empresa',
                    ),
                  ),
                  _txt(
                    _backendLegalNameCtrl,
                    _t(
                      nl: 'Juridische naam',
                      en: 'Legal name',
                      fr: 'Nom legal',
                      es: 'Nombre legal',
                    ),
                  ),
                  _txt(
                    _backendVatNumberCtrl,
                    _t(
                      nl: 'BTW-nummer',
                      en: 'VAT number',
                      fr: 'Numero TVA',
                      es: 'Numero de IVA',
                    ),
                  ),
                  _txt(
                    _backendRegistrationCtrl,
                    _t(
                      nl: 'Ondernemingsnummer',
                      en: 'Company registration number',
                      fr: 'Numero d entreprise',
                      es: 'Numero de registro',
                    ),
                  ),
                  _txt(
                    _backendAddressCtrl,
                    _t(
                      nl: 'Adres',
                      en: 'Address',
                      fr: 'Adresse',
                      es: 'Dirección',
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _txt(
                          _backendPostcodeCtrl,
                          _t(
                            nl: 'Postcode',
                            en: 'Postcode',
                            fr: 'Code postal',
                            es: 'Codigo postal',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _txt(
                          _backendCityCtrl,
                          _t(nl: 'Stad', en: 'City', fr: 'Ville', es: 'Ciudad'),
                        ),
                      ),
                    ],
                  ),
                  _txt(
                    _backendCountryCtrl,
                    _t(nl: 'Land', en: 'Country', fr: 'Pays', es: 'Pais'),
                  ),
                  _txt(
                    _backendPhoneCtrl,
                    _t(
                      nl: 'Telefoon',
                      en: 'Phone',
                      fr: 'Téléphone',
                      es: 'Teléfono',
                    ),
                  ),
                  _txt(
                    _backendEmailCtrl,
                    _t(nl: 'E-mail', en: 'Email', fr: 'E-mail', es: 'Correo'),
                  ),
                  _txt(
                    _backendBookingEmailCtrl,
                    _t(
                      nl: 'Boekingen e-mail',
                      en: 'Bookings email',
                      fr: 'E-mail des reservations',
                      es: 'Correo de reservas',
                    ),
                  ),
                  _txt(
                    _backendInvoiceEmailCtrl,
                    _t(
                      nl: 'Facturatie e-mail',
                      en: 'Invoice email',
                      fr: 'E-mail facturation',
                      es: 'Correo de facturacion',
                    ),
                  ),
                  _txt(
                    _backendWebsiteCtrl,
                    _t(
                      nl: 'Website',
                      en: 'Website',
                      fr: 'Site web',
                      es: 'Sitio web',
                    ),
                  ),
                  _txt(
                    _backendIbanCtrl,
                    _t(nl: 'IBAN', en: 'IBAN', fr: 'IBAN', es: 'IBAN'),
                  ),
                  _txt(
                    _backendPaymentPrefixCtrl,
                    _t(
                      nl: 'Betaalreferentie prefix',
                      en: 'Payment reference prefix',
                      fr: 'Prefixe reference paiement',
                      es: 'Prefijo referencia pago',
                    ),
                  ),
                  _txt(
                    _backendFooterCtrl,
                    _t(
                      nl: 'Factuur/ritbon footer',
                      en: 'Invoice/receipt footer',
                      fr: 'Pied facture/recu',
                      es: 'Pie factura/recibo',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton.icon(
                          onPressed: _backendBusinessSaving
                              ? null
                              : _saveBackendBusinessProfile,
                          icon: _backendBusinessSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.cloud_upload_outlined),
                          label: Text(
                            _t(
                              nl: 'Bedrijfsgegevens opslaan',
                              en: 'Save company details',
                              fr: 'Enregistrer les informations',
                              es: 'Guardar datos de empresa',
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _t(
                            nl: 'Slaat alleen de officiële bedrijfsgegevens op.',
                            en: 'Saves only the official company details.',
                            fr: 'Enregistre uniquement les informations officielles de l’entreprise.',
                            es: 'Guarda solo los datos oficiales de la empresa.',
                          ),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _collapsibleSettingsCard(
              id: 'vat_settings',
              icon: Icons.receipt_long_outlined,
              title: _t(
                nl: 'BTW-instellingen',
                en: 'VAT settings',
                fr: 'Parametres TVA',
                es: 'Configuracion de IVA',
              ),
              subtitle: _t(
                nl: 'BTW-profiel en weergavemodus',
                en: 'VAT profile and display mode',
                fr: 'Profil TVA et mode d’affichage',
                es: 'Perfil de IVA y modo de visualización',
              ),
              status: _billingVatStatus(),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _backendVatEnabled,
                    onChanged: (v) => setState(() => _backendVatEnabled = v),
                    title: Text(
                      _t(
                        nl: 'BTW ingeschakeld',
                        en: 'VAT enabled',
                        fr: 'TVA activee',
                        es: 'IVA activado',
                      ),
                    ),
                  ),
                  _txt(
                    _backendVatRateCtrl,
                    _t(
                      nl: 'BTW-percentage',
                      en: 'VAT percentage',
                      fr: 'Pourcentage TVA',
                      es: 'Porcentaje IVA',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _backendVatDisplayMode,
                    items: [
                      DropdownMenuItem(
                        value: 'incl',
                        child: Text(
                          _t(
                            nl: 'Prijzen inclusief BTW',
                            en: 'Prices including VAT',
                            fr: 'Prix TVA incluse',
                            es: 'Precios con IVA incluido',
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'excl',
                        child: Text(
                          _t(
                            nl: 'Prijzen exclusief BTW',
                            en: 'Prices excluding VAT',
                            fr: 'Prix hors TVA',
                            es: 'Precios sin IVA',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _backendVatDisplayMode = v);
                    },
                    decoration: InputDecoration(
                      labelText: _t(
                        nl: 'BTW weergavemodus',
                        en: 'VAT display mode',
                        fr: 'Mode affichage TVA',
                        es: 'Modo visualizacion IVA',
                      ),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 16,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0B0B0B),
                    ),
                    dropdownColor: const Color(0xFF111111),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton.icon(
                          onPressed: _backendTaxSaving
                              ? null
                              : _saveBackendTaxProfile,
                          icon: _backendTaxSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.cloud_upload_outlined),
                          label: Text(
                            _t(
                              nl: 'BTW-instellingen opslaan',
                              en: 'Save VAT settings',
                              fr: 'Enregistrer TVA',
                              es: 'Guardar IVA',
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _t(
                            nl: 'Slaat alleen de BTW-instellingen op.',
                            en: 'Saves only the VAT settings.',
                            fr: 'Enregistre uniquement les paramètres TVA.',
                            es: 'Guarda solo la configuración de IVA.',
                          ),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _collapsibleSettingsCard(
              id: 'branding_support',
              icon: Icons.brush_outlined,
              title: _t(
                nl: 'Branding & support',
                en: 'Branding & support',
                fr: 'Branding et support',
                es: 'Marca y soporte',
              ),
              subtitle: _t(
                nl: 'Merknaam, contact en logo',
                en: 'Brand name, contact and logo',
                fr: 'Marque, contact et logo',
                es: 'Marca, contacto y logo',
              ),
              status: _brandingSupportStatus(),
              child: Column(
                children: [
                  _txt(
                    _companyCtrl,
                    _t(
                      nl: 'Naam in app/branding',
                      en: 'App/branding name',
                      fr: 'Nom dans l app/branding',
                      es: 'Nombre en app/marca',
                    ),
                  ),
                  _txt(
                    _supportEmailCtrl,
                    _t(
                      nl: 'Support e-mail',
                      en: 'Support email',
                      fr: 'E-mail support',
                      es: 'Correo de soporte',
                    ),
                  ),
                  _txt(
                    _supportPhoneCtrl,
                    _t(
                      nl: 'Support telefoon',
                      en: 'Support phone',
                      fr: 'Téléphone support',
                      es: 'Teléfono de soporte',
                    ),
                  ),
                  _txt(
                    _senderCtrl,
                    _t(
                      nl: 'E-mail afzendernaam',
                      en: 'Email sender name',
                      fr: 'Nom expediteur e-mail',
                      es: 'Nombre remitente email',
                    ),
                  ),
                  _txt(
                    _replyToCtrl,
                    _t(
                      nl: 'Reply-to e-mail',
                      en: 'Reply-to email',
                      fr: 'E-mail de reponse',
                      es: 'Email de respuesta',
                    ),
                  ),
                  _txt(
                    _whatsAppCtrl,
                    _t(
                      nl: 'WhatsApp nummer',
                      en: 'WhatsApp number',
                      fr: 'Numero WhatsApp',
                      es: 'Numero WhatsApp',
                    ),
                  ),
                  _logoPreviewBlock(),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<AppLanguage>(
                    value: _defaultLanguage,
                    items: const [
                      DropdownMenuItem(
                        value: AppLanguage.nl,
                        child: Text('Nederlands'),
                      ),
                      DropdownMenuItem(
                        value: AppLanguage.en,
                        child: Text('English'),
                      ),
                      DropdownMenuItem(
                        value: AppLanguage.fr,
                        child: Text('Français'),
                      ),
                      DropdownMenuItem(
                        value: AppLanguage.es,
                        child: Text('Español'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _defaultLanguage = v);
                    },
                    decoration: InputDecoration(
                      labelText: _t(
                        nl: 'Standaard taal',
                        en: 'Default language',
                        fr: 'Langue par defaut',
                        es: 'Idioma predeterminado',
                      ),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 16,
                      ),
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
                      labelText: _t(
                        nl: 'Standaard valuta',
                        en: 'Default currency',
                        fr: 'Devise par defaut',
                        es: 'Moneda predeterminada',
                      ),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 16,
                      ),
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
                      labelText: _t(
                        nl: 'Belastinglabel',
                        en: 'Tax label',
                        fr: 'Libelle taxe',
                        es: 'Etiqueta de impuesto',
                      ),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 16,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0B0B0B),
                    ),
                    dropdownColor: const Color(0xFF111111),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _use24Hour,
                    onChanged: (v) => setState(() => _use24Hour = v),
                    title: Text(
                      _t(
                        nl: 'Gebruik 24-uurs notatie',
                        en: 'Use 24-hour time',
                        fr: 'Utiliser format 24h',
                        es: 'Usar formato 24 horas',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _collapsibleSettingsCard(
              id: 'service_setup',
              icon: Icons.local_taxi_outlined,
              title: _t(
                nl: 'Service setup',
                en: 'Service setup',
                fr: 'Configuration des services',
                es: 'Configuracion de servicios',
              ),
              subtitle: _t(
                nl: 'Services, tiers en opties',
                en: 'Services, tiers and options',
                fr: 'Services, catégories et options',
                es: 'Servicios, categorías y opciones',
              ),
              status: _servicesTiersStatus(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(
                      nl: 'Ingeschakelde services',
                      en: 'Enabled services',
                      fr: 'Services actifs',
                      es: 'Servicios habilitados',
                    ),
                  ),
                  _optionsChecklist(
                    options: appConfig.enabledServices,
                    selected: _serviceIds,
                    onChanged: (next) => setState(() => _serviceIds = next),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _t(
                      nl: 'Ingeschakelde tiers',
                      en: 'Enabled tiers',
                      fr: 'Categories actives',
                      es: 'Categorias habilitadas',
                    ),
                  ),
                  _optionsChecklist(
                    options: appConfig.enabledTiers,
                    selected: _tierIds,
                    onChanged: (next) => setState(() => _tierIds = next),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _t(
                      nl: 'Ingeschakelde extra opties',
                      en: 'Enabled extra options',
                      fr: 'Options extra actives',
                      es: 'Opciones extra habilitadas',
                    ),
                  ),
                  _optionsChecklist(
                    options: appConfig.enabledExtraOptions,
                    selected: _extraIds,
                    onChanged: (next) => setState(() => _extraIds = next),
                  ),
                ],
              ),
            ),
            _collapsibleSettingsCard(
              id: 'pricing_engine',
              icon: Icons.local_offer_outlined,
              title: _t(
                nl: 'Pricing engine',
                en: 'Pricing engine',
                fr: 'Moteur tarifaire',
                es: 'Motor de precios',
              ),
              subtitle: _t(
                nl: 'Basistarieven en toeslagen',
                en: 'Base rates and surcharges',
                fr: 'Tarifs de base et suppléments',
                es: 'Tarifas base y recargos',
              ),
              status: _pricingStatus(),
              child: Column(
                children: [
                  _txt(
                    _baseFareCtrl,
                    _t(
                      nl: 'Basistarief',
                      en: 'Base fare',
                      fr: 'Tarif de base',
                      es: 'Tarifa base',
                    ),
                  ),
                  _txt(
                    _perKmCtrl,
                    _t(
                      nl: 'Prijs per km',
                      en: 'Price per km',
                      fr: 'Prix par km',
                      es: 'Precio por km',
                    ),
                  ),
                  _txt(
                    _perMinCtrl,
                    _t(
                      nl: 'Prijs per minuut',
                      en: 'Price per minute',
                      fr: 'Prix par minute',
                      es: 'Precio por minuto',
                    ),
                  ),
                  _txt(
                    _minimumFareCtrl,
                    _t(
                      nl: 'Minimumtarief',
                      en: 'Minimum fare',
                      fr: 'Tarif minimum',
                      es: 'Tarifa minima',
                    ),
                  ),
                  _txt(
                    _waitPerMinCtrl,
                    _t(
                      nl: 'Wachttarief per minuut',
                      en: 'Waiting price per minute',
                      fr: 'Tarif d attente par minute',
                      es: 'Tarifa de espera por minuto',
                    ),
                  ),
                  Builder(
                    builder: (_) {
                      final vat = _activeVatConfig();
                      final vatPercent = (vat.vatRate * 100).clamp(0.0, 100.0);
                      final vatModeLabel = vat.vatMode == 'incl'
                          ? _t(
                              nl: 'inclusief',
                              en: 'inclusive',
                              fr: 'incluse',
                              es: 'incluido',
                            )
                          : _t(
                              nl: 'exclusief',
                              en: 'exclusive',
                              fr: 'hors taxe',
                              es: 'excluido',
                            );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${_t(nl: 'BTW wordt beheerd via BTW-instellingen hierboven.', en: 'VAT is managed in the VAT settings above.', fr: 'La TVA est gérée dans les paramètres TVA ci-dessus.', es: 'El IVA se gestiona en los ajustes de IVA de arriba.')} (${vatPercent % 1 == 0 ? vatPercent.toStringAsFixed(0) : vatPercent.toStringAsFixed(2)}%, $vatModeLabel)',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      );
                    },
                  ),
                  _txt(
                    _bagFeeCtrl,
                    _t(
                      nl: 'Bagagekost per stuk',
                      en: 'Bag fee each',
                      fr: 'Frais bagage par piece',
                      es: 'Tarifa por equipaje',
                    ),
                  ),
                  _txt(
                    _stopFeeCtrl,
                    _t(
                      nl: 'Stopkost per stop',
                      en: 'Stop fee each',
                      fr: 'Frais par arret',
                      es: 'Tarifa por parada',
                    ),
                  ),
                  _txt(
                    _tierComfortFeeCtrl,
                    _t(
                      nl: 'Tier fee comfort',
                      en: 'Tier fee comfort',
                      fr: 'Frais niveau confort',
                      es: 'Tarifa nivel comfort',
                    ),
                  ),
                  _txt(
                    _tierPrivateFeeCtrl,
                    _t(
                      nl: 'Tier fee private',
                      en: 'Tier fee private',
                      fr: 'Frais niveau prive',
                      es: 'Tarifa nivel private',
                    ),
                  ),
                  _txt(
                    _tierPremiumFeeCtrl,
                    _t(
                      nl: 'Tier fee premium',
                      en: 'Tier fee premium',
                      fr: 'Frais niveau premium',
                      es: 'Tarifa nivel premium',
                    ),
                  ),
                  _txt(
                    _nightSurchargeCtrl,
                    _t(
                      nl: 'Nachttoeslag (0-1)',
                      en: 'Night surcharge (0-1)',
                      fr: 'Surcharge nuit (0-1)',
                      es: 'Recargo nocturno (0-1)',
                    ),
                  ),
                  _txt(
                    _weekendSurchargeCtrl,
                    _t(
                      nl: 'Weekendtoeslag (0-1)',
                      en: 'Weekend surcharge (0-1)',
                      fr: 'Surcharge weekend (0-1)',
                      es: 'Recargo fin de semana (0-1)',
                    ),
                  ),
                  _txt(
                    _surchargeCapCtrl,
                    _t(
                      nl: 'Toeslag plafond (0-1)',
                      en: 'Surcharge cap (0-1)',
                      fr: 'Plafond surcharge (0-1)',
                      es: 'Tope de recargo (0-1)',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _pricingReturnEnabled,
                    onChanged: (v) => setState(() => _pricingReturnEnabled = v),
                    title: Text(
                      _t(
                        nl: 'Retourritten inschakelen',
                        en: 'Enable return trips',
                        fr: 'Activer les trajets retour',
                        es: 'Activar viajes de regreso',
                      ),
                    ),
                  ),
                  _txt(
                    _returnFeeCtrl,
                    _t(
                      nl: 'Retourtoeslag',
                      en: 'Return fee',
                      fr: 'Supplement retour',
                      es: 'Recargo de regreso',
                    ),
                  ),
                  _txt(
                    _fuelSurchargeCtrl,
                    _t(
                      nl: 'Brandstoftoeslag',
                      en: 'Fuel surcharge',
                      fr: 'Supplement carburant',
                      es: 'Recargo de combustible',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(
                _t(
                  nl: 'Branding, support & prijsinstellingen opslaan',
                  en: 'Save branding, support & pricing settings',
                  fr: 'Enregistrer branding, support et tarifs',
                  es: 'Guardar marca, soporte y precios',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
