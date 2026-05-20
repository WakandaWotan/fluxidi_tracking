import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/airport/airport_catalog.generated.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
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
  static const List<String> _publicServiceCatalog = <String>[
    'taxi_vvb',
    'airport_transfer',
    'business_rides',
    'event_mobility',
    'hotel_bnb_pickup',
    'online_payments',
  ];
  static const List<String> _publicPaymentOptionCatalog = <String>[
    'cash',
    'qr_code',
    'tikkie',
    'bancontact',
    'payconiq_wero',
    'ideal',
    'cartes_bancaires',
    'card_payment',
    'apple_pay',
    'google_pay',
    'paypal',
    'online_payment',
    'bank_transfer_bacs',
  ];

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
  final _publicLogoUrlCtrl = TextEditingController();
  final _publicHeroPhotoUrlCtrl = TextEditingController();
  final _publicServedPostcodesCtrl = TextEditingController();
  final _publicCoverageLatCtrl = TextEditingController();
  final _publicCoverageLngCtrl = TextEditingController();
  final _publicServiceRadiusKmCtrl = TextEditingController();
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
  bool _publicPartnerProfilePublishing = false;
  bool _saveAllBusy = false;
  bool _publicLogoUploading = false;
  bool _publicHeroUploading = false;
  bool _googleCalendarLoading = false;
  bool _googleCalendarReconnectLoading = false;
  bool _googleCalendarDisconnectLoading = false;
  String? _backendProfilesError;
  String? _backendProfilesStatus;
  String? _publicPartnerProfileStatus;
  String? _publicPartnerProfileError;
  String _publicPartnerProfilePublishedAt = '';
  String _publicPartnerProfilePublishStatus = '';
  String? _googleCalendarStatusError;
  Map<String, dynamic>? _googleCalendarStatus;
  bool _showAdvancedLogoPath = false;
  bool _showAdvancedPublicMediaUrls = false;
  final ImagePicker _imagePicker = ImagePicker();
  Set<String> _serviceIds = <String>{};
  Set<String> _tierIds = <String>{};
  Set<String> _extraIds = <String>{};
  Set<String> _publicPaymentOptionIds = <String>{
    'cash',
    'qr_code',
    'online_payment',
  };
  Set<String> _publicServiceIds = <String>{};
  bool _publicServicesConfigured = false;
  final Set<String> _expandedSections = <String>{};
  static const List<String> _airportFixedFareDirections = <String>[
    'to_airport',
    'from_airport',
  ];
  static const List<String> _airportFixedFareZoneTypes = <String>[
    'postcode',
    'city',
    'country',
    'radius',
  ];
  static const List<String> _airportFixedFareTiers = <String>[
    'comfort',
    'private',
    'premium',
  ];
  static const List<String> _airportFixedFareCurrencies = <String>[
    'EUR',
    'GBP',
    'USD',
    'CHF',
    'NOK',
    'SEK',
    'DKK',
  ];
  static final List<Map<String, String>> _airportFixedFareCatalog =
      _buildAirportFixedFareCatalog();

  static List<Map<String, String>> _buildAirportFixedFareCatalog() {
    final seen = <String>{};
    final out = <Map<String, String>>[];
    for (final entry in kAirportCatalog) {
      final iata = entry.iata.trim().toUpperCase();
      final countryCode = entry.countryCode.trim().toUpperCase();
      if (iata.length != 3 || countryCode.isEmpty) continue;
      final dedupeKey = '$countryCode:$iata';
      if (!seen.add(dedupeKey)) continue;
      out.add(<String, String>{
        'country_code': countryCode,
        'country_name': entry.countryName.trim(),
        'iata': iata,
        'airport_name': entry.name.trim(),
      });
    }
    out.sort((a, b) {
      final cc = (a['country_code'] ?? '').compareTo(b['country_code'] ?? '');
      if (cc != 0) return cc;
      final name = (a['airport_name'] ?? '').compareTo(b['airport_name'] ?? '');
      if (name != 0) return name;
      return (a['iata'] ?? '').compareTo(b['iata'] ?? '');
    });
    return out;
  }

  bool _airportFixedFaresLoading = false;
  bool _airportFixedFaresSaving = false;
  bool _airportFixedFaresDirty = false;
  String? _airportFixedFaresError;
  String? _airportFixedFaresStatus;
  int _airportFixedFaresVersion = 1;
  String? _airportFixedFaresUpdatedAt;
  List<Map<String, dynamic>> _airportFixedFareRules = <Map<String, dynamic>>[];

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
    // Prefer locally cached "OfficiÃ«le bedrijfsgegevens" so user-entered values
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
    _loadAirportFixedFareRules();
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
    _publicLogoUrlCtrl.dispose();
    _publicHeroPhotoUrlCtrl.dispose();
    _publicServedPostcodesCtrl.dispose();
    _publicCoverageLatCtrl.dispose();
    _publicCoverageLngCtrl.dispose();
    _publicServiceRadiusKmCtrl.dispose();
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
    _publicLogoUrlCtrl.text = p.publicLogoUrl;
    _publicHeroPhotoUrlCtrl.text = p.publicHeroPhotoUrl;
    _publicServedPostcodesCtrl.text = p.publicServedPostcodes;
    _publicCoverageLatCtrl.text = p.publicCoverageLat;
    _publicCoverageLngCtrl.text = p.publicCoverageLng;
    _publicServiceRadiusKmCtrl.text = p.publicServiceRadiusKm;
    _publicPaymentOptionIds = _sanitizePublicPaymentOptionIds(
      p.publicPaymentOptions,
    );
    final sanitizedPublicServices = _sanitizePublicServiceIds(
      p.publicServiceIds,
    );
    _publicServicesConfigured = p.publicServicesConfigured;
    if (p.publicServicesConfigured) {
      _publicServiceIds = sanitizedPublicServices.toSet();
    } else {
      // Backward compatibility: older profiles had no dedicated public-service
      // section. Seed once from calculator service setup mapping.
      _publicServiceIds = _legacyPublicServiceIdsFromCalculator().toSet();
    }
    _publicPartnerProfilePublishedAt = p.publicPartnerProfilePublishedAt;
    _publicPartnerProfilePublishStatus = p.publicPartnerProfilePublishStatus;
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
    List<String> pickPaymentList(
      List<String> localValue,
      List<String> serverValue,
    ) {
      final normalizedServer = _sanitizePublicPaymentOptionIds(serverValue);
      if (normalizedServer.isNotEmpty) return normalizedServer.toList();
      final normalizedLocal = _sanitizePublicPaymentOptionIds(localValue);
      return normalizedLocal.toList();
    }

    List<String> pickPublicServiceList(
      List<String> localValue,
      List<String> serverValue,
    ) {
      final normalizedServer = _sanitizePublicServiceIds(serverValue);
      if (normalizedServer.isNotEmpty) return normalizedServer.toList();
      final normalizedLocal = _sanitizePublicServiceIds(localValue);
      return normalizedLocal.toList();
    }

    return BackendBusinessProfile(
      companyCode: pick(local.companyCode, server.companyCode),
      publicCompanyCode: pick(
        local.publicCompanyCode,
        server.publicCompanyCode,
      ),
      publicCompanySlug: pick(
        local.publicCompanySlug,
        server.publicCompanySlug,
      ),
      publicDisplayCode: pick(
        local.publicDisplayCode,
        server.publicDisplayCode,
      ),
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
      publicLogoUrl: pick(local.publicLogoUrl, server.publicLogoUrl),
      publicHeroPhotoUrl: pick(
        local.publicHeroPhotoUrl,
        server.publicHeroPhotoUrl,
      ),
      publicServedPostcodes: pick(
        local.publicServedPostcodes,
        server.publicServedPostcodes,
      ),
      publicCoverageLat: pick(
        local.publicCoverageLat,
        server.publicCoverageLat,
      ),
      publicCoverageLng: pick(
        local.publicCoverageLng,
        server.publicCoverageLng,
      ),
      publicServiceRadiusKm: pick(
        local.publicServiceRadiusKm,
        server.publicServiceRadiusKm,
      ),
      publicPaymentOptions: pickPaymentList(
        local.publicPaymentOptions,
        server.publicPaymentOptions,
      ),
      publicServiceIds: pickPublicServiceList(
        local.publicServiceIds,
        server.publicServiceIds,
      ),
      publicServicesConfigured:
          server.publicServicesConfigured || local.publicServicesConfigured,
      publicPartnerProfilePublishedAt: pick(
        local.publicPartnerProfilePublishedAt,
        server.publicPartnerProfilePublishedAt,
      ),
      publicPartnerProfilePublishStatus: pick(
        local.publicPartnerProfilePublishStatus,
        server.publicPartnerProfilePublishStatus,
      ),
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
      await _hydratePublicCompanyCodeFromBackendProfile(
        rawBiz,
        source: 'business_profile_get',
      );
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

  bool _googleCalendarCanDisconnect() {
    if (_googleCalendarSource() != 'scoped') return false;
    final raw = (_googleCalendarStatus?['status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return _googleCalendarConnected() || raw == 'connected';
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
    if (raw == 'disconnected') return 'disconnected';
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
      case 'disconnected':
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
          fr: 'ConnectÃ©',
          es: 'Conectado',
        );
      case 'auth_required':
      case 'failed':
        return _t(
          nl: 'Opnieuw koppelen vereist',
          en: 'Reconnect required',
          fr: 'Reconnexion requise',
          es: 'Requiere reconexiÃ³n',
        );
      case 'legacy_global':
        return _t(
          nl: 'Legacy-koppeling actief',
          en: 'Legacy connection active',
          fr: 'Connexion hÃ©ritÃ©e active',
          es: 'ConexiÃ³n heredada activa',
        );
      case 'disconnected':
        return _t(
          nl: 'Losgekoppeld',
          en: 'Disconnected',
          fr: 'DÃ©connectÃ©',
          es: 'Desconectado',
        );
      case 'not_configured':
        return _t(
          nl: 'Niet geconfigureerd',
          en: 'Not configured',
          fr: 'Non configurÃ©',
          es: 'No configurado',
        );
      case 'check_failed':
      default:
        return _t(
          nl: 'Controle mislukt',
          en: 'Check failed',
          fr: 'Ã‰chec du contrÃ´le',
          es: 'Error de comprobaciÃ³n',
        );
    }
  }

  String _googleCalendarDescription() {
    switch (_googleCalendarStatusCode()) {
      case 'connected':
        return _t(
          nl: 'Google Calendar is gekoppeld voor dit bedrijf.',
          en: 'Google Calendar is connected for this company.',
          fr: 'Google Agenda est connectÃ© pour cette entreprise.',
          es: 'Google Calendar estÃ¡ conectado para esta empresa.',
        );
      case 'legacy_global':
        return _t(
          nl: 'Deze koppeling gebruikt nog de legacy globale configuratie. Koppel Google Calendar opnieuw voor dit bedrijf.',
          en: 'This connection still uses the legacy global configuration. Reconnect Google Calendar for this company.',
          fr: 'Cette connexion utilise encore la configuration globale hÃ©ritÃ©e. Reconnectez Google Agenda pour cette entreprise.',
          es: 'Esta conexiÃ³n aÃºn usa la configuraciÃ³n global heredada. Vuelve a conectar Google Calendar para esta empresa.',
        );
      case 'disconnected':
        return _t(
          nl: 'Google Calendar is losgekoppeld voor dit bedrijf. Nieuwe boekingen worden niet meer automatisch in de agenda geplaatst.',
          en: 'Google Calendar is disconnected for this company. New bookings will no longer be added automatically to the calendar.',
          fr: 'Google Agenda est dÃ©connectÃ© pour cette entreprise. Les nouvelles rÃ©servations ne seront plus ajoutÃ©es automatiquement au calendrier.',
          es: 'Google Calendar estÃ¡ desconectado para esta empresa. Las nuevas reservas ya no se aÃ±adirÃ¡n automÃ¡ticamente al calendario.',
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
                fr: 'Le statut Google Agenda nâ€™a pas pu Ãªtre chargÃ©.',
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
              es: 'OAuth de Google abierto. Termina la conexiÃ³n en tu navegador.',
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
              fr: 'La connexion Google Agenda nâ€™a pas pu Ãªtre dÃ©marrÃ©e.',
              es: 'No se pudo iniciar la conexiÃ³n de Google Calendar.',
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

  Future<bool> _confirmGoogleCalendarDisconnect() async {
    final decision = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            _t(
              nl: 'Google Calendar loskoppelen?',
              en: 'Disconnect Google Calendar?',
              fr: 'DÃ©connecter Google Agenda ?',
              es: 'Â¿Desconectar Google Calendar?',
            ),
          ),
          content: Text(
            _t(
              nl: 'Nieuwe boekingen worden niet meer automatisch in Google Calendar geplaatst tot je opnieuw koppelt. Bestaande boekingen en agenda-items blijven behouden.',
              en: 'New bookings will no longer be added automatically to Google Calendar until you reconnect. Existing bookings and calendar events remain unchanged.',
              fr: 'Les nouvelles rÃ©servations ne seront plus ajoutÃ©es automatiquement Ã  Google Agenda jusquâ€™Ã  reconnexion. Les rÃ©servations et Ã©vÃ©nements existants restent inchangÃ©s.',
              es: 'Las nuevas reservas ya no se aÃ±adirÃ¡n automÃ¡ticamente a Google Calendar hasta que vuelvas a conectar. Las reservas y eventos existentes permanecen sin cambios.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
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
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                _t(
                  nl: 'Loskoppelen',
                  en: 'Disconnect',
                  fr: 'DÃ©connecter',
                  es: 'Desconectar',
                ),
              ),
            ),
          ],
        );
      },
    );
    return decision == true;
  }

  Future<void> _disconnectGoogleCalendar() async {
    final confirmed = await _confirmGoogleCalendarDisconnect();
    if (!confirmed || !mounted) return;
    setState(() => _googleCalendarDisconnectLoading = true);
    try {
      final scope = _activeSettingsScope();
      await disconnectBackendGoogleCalendar(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Google Calendar is losgekoppeld.',
              en: 'Google Calendar is disconnected.',
              fr: 'Google Agenda est dÃ©connectÃ©.',
              es: 'Google Calendar estÃ¡ desconectado.',
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
              nl: 'Google Calendar kon niet worden losgekoppeld.',
              en: 'Google Calendar could not be disconnected.',
              fr: 'Google Agenda nâ€™a pas pu Ãªtre dÃ©connectÃ©.',
              es: 'No se pudo desconectar Google Calendar.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _googleCalendarDisconnectLoading = false);
      }
    }
  }

  Widget _googleCalendarCard() {
    final calendarId = _calendarStatusField('calendar_id');
    final accountEmail = _calendarStatusField('account_email');
    final lastConnectedAt = _calendarStatusField('last_connected_at');
    final lastDisconnectedAt = _calendarStatusField('last_disconnected_at');
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
        es: 'ConexiÃ³n de calendario y reconexiÃ³n',
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
              '${_t(nl: 'Laatste koppeling', en: 'Last connected', fr: 'DerniÃ¨re connexion', es: 'Ãšltima conexiÃ³n')}: $lastConnectedAt',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          if (lastDisconnectedAt != null)
            Text(
              '${_t(nl: 'Laatst losgekoppeld', en: 'Last disconnected', fr: 'DerniÃ¨re dÃ©connexion', es: 'Ãšltima desconexiÃ³n')}: $lastDisconnectedAt',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          if (lastSyncAt != null)
            Text(
              '${_t(nl: 'Laatste sync', en: 'Last sync', fr: 'DerniÃ¨re synchro', es: 'Ãšltima sincronizaciÃ³n')}: $lastSyncAt',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          if (lastErrorCode != null)
            Text(
              '${_t(nl: 'Foutcode', en: 'Error code', fr: 'Code erreur', es: 'CÃ³digo de error')}: $lastErrorCode',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          if (lastErrorAt != null)
            Text(
              '${_t(nl: 'Laatste fout', en: 'Last error', fr: 'DerniÃ¨re erreur', es: 'Ãšltimo error')}: $lastErrorAt',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed:
                    (_googleCalendarReconnectLoading ||
                        _googleCalendarDisconnectLoading)
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
              if (_googleCalendarCanDisconnect())
                OutlinedButton.icon(
                  onPressed: _googleCalendarDisconnectLoading
                      ? null
                      : _disconnectGoogleCalendar,
                  icon: _googleCalendarDisconnectLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link_off_outlined),
                  label: Text(
                    _t(
                      nl: 'Loskoppelen',
                      en: 'Disconnect',
                      fr: 'DÃ©connecter',
                      es: 'Desconectar',
                    ),
                  ),
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
      publicLogoUrl: _publicLogoUrlCtrl.text.trim(),
      publicHeroPhotoUrl: _publicHeroPhotoUrlCtrl.text.trim(),
      publicServedPostcodes: _publicServedPostcodesCtrl.text.trim(),
      publicCoverageLat: _publicCoverageLatCtrl.text.trim(),
      publicCoverageLng: _publicCoverageLngCtrl.text.trim(),
      publicServiceRadiusKm: _publicServiceRadiusKmCtrl.text.trim(),
      publicPaymentOptions: _sanitizePublicPaymentOptionIds(
        _publicPaymentOptionIds,
      ).toList(growable: false),
      publicServiceIds: _publicServicesConfigured
          ? _sanitizePublicServiceIds(_publicServiceIds).toList(growable: false)
          : const <String>[],
      publicServicesConfigured: _publicServicesConfigured,
      publicPartnerProfilePublishedAt: _publicPartnerProfilePublishedAt.trim(),
      publicPartnerProfilePublishStatus: _publicPartnerProfilePublishStatus
          .trim(),
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

  Future<bool> _saveBackendBusinessProfile() async {
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
      if (!mounted) return false;
      await _hydratePublicCompanyCodeFromBackendProfile(
        saved,
        source: 'business_profile_post',
      );
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
      return true;
    } catch (e) {
      if (!mounted) return false;
      // Local cache stays intact (saved above); just surface the existing
      // error message so the UI behaviour remains the same as before.
      setState(
        () => _backendProfilesError =
            '${_t(nl: 'Opslaan mislukt', en: 'Save failed', fr: 'Echec de l enregistrement', es: 'Error al guardar')}: $e',
      );
      return false;
    } finally {
      if (mounted) setState(() => _backendBusinessSaving = false);
    }
  }

  Future<void> _uploadPublicCompanyMedia({required String mediaType}) async {
    final isLogo = mediaType == 'company_logo';
    setState(() {
      if (isLogo) {
        _publicLogoUploading = true;
      } else {
        _publicHeroUploading = true;
      }
      _publicPartnerProfileError = null;
      _publicPartnerProfileStatus = null;
    });
    try {
      final maxWidth = isLogo ? 800.0 : 1600.0;
      final quality = isLogo ? 88 : 82;
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxWidth,
        imageQuality: quality,
      );
      if (picked == null) return;
      final scope = _activeSettingsScope();
      final bytes = kIsWeb ? await picked.readAsBytes() : null;
      final uploaded = await uploadPublicPartnerMedia(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
        mediaType: mediaType,
        filePath: kIsWeb ? null : picked.path,
        fileBytes: bytes,
        filename: picked.name,
      );
      final url = (uploaded['url'] ?? '').toString().trim();
      if (!_isPublicHttpsUrl(url)) {
        throw Exception('Upload did not return a valid HTTPS URL');
      }

      if (isLogo) {
        _publicLogoUrlCtrl.text = url;
      } else {
        _publicHeroPhotoUrlCtrl.text = url;
      }

      final formProfile = _backendBusinessProfileFromForm();
      await updateLocalBackendBusinessProfileCache(formProfile);
      final saved = await saveBackendBusinessProfile(
        formProfile,
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return;
      await _hydratePublicCompanyCodeFromBackendProfile(
        saved,
        source: 'business_profile_media_post',
      );
      final merged = _mergeBackendBusinessProfile(
        local: formProfile,
        server: saved,
      );
      setState(() {
        _hydrateBackendBusinessProfile(merged);
        _publicPartnerProfileStatus = _t(
          nl: isLogo
              ? 'Publiek logo geÃ¼pload en opgeslagen.'
              : 'Publieke coverfoto geÃ¼pload en opgeslagen.',
          en: isLogo
              ? 'Public logo uploaded and saved.'
              : 'Public cover photo uploaded and saved.',
          fr: isLogo
              ? 'Logo public tÃ©lÃ©versÃ© et enregistrÃ©.'
              : 'Photo de couverture publique tÃ©lÃ©versÃ©e et enregistrÃ©e.',
          es: isLogo
              ? 'Logo pÃºblico subido y guardado.'
              : 'Foto de portada pÃºblica subida y guardada.',
        );
      });
      unawaited(updateLocalBackendBusinessProfileCache(merged));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _publicPartnerProfileError = _t(
          nl: 'Upload mislukt. Controleer of dit een JPG, PNG of WEBP-afbeelding is.',
          en: 'Upload failed. Please check that this is a JPG, PNG, or WEBP image.',
          fr: 'Ã‰chec du tÃ©lÃ©versement. VÃ©rifiez quâ€™il sâ€™agit dâ€™une image JPG, PNG ou WEBP.',
          es: 'La carga fallÃ³. Verifica que sea una imagen JPG, PNG o WEBP.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          if (isLogo) {
            _publicLogoUploading = false;
          } else {
            _publicHeroUploading = false;
          }
        });
      }
    }
  }

  Future<bool> _saveBackendTaxProfile() async {
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
      if (!mounted) return false;
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
      return true;
    } catch (e) {
      if (!mounted) return false;
      // Local cache stays intact (saved above); just surface the existing
      // error message so the UI behaviour remains the same as before.
      setState(
        () => _backendProfilesError =
            '${_t(nl: 'Opslaan mislukt', en: 'Save failed', fr: 'Echec de l enregistrement', es: 'Error al guardar')}: $e',
      );
      return false;
    } finally {
      if (mounted) setState(() => _backendTaxSaving = false);
    }
  }

  bool _isPublicHttpsUrl(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return false;
    final lower = raw.toLowerCase();
    if (lower.startsWith('assets/')) return false;
    if (lower.contains(r':\') ||
        lower.startsWith('/') ||
        lower.startsWith('.')) {
      return false;
    }
    return lower.startsWith('https://');
  }

  Widget _publicMediaPreview() {
    final logoUrl = _isPublicHttpsUrl(_publicLogoUrlCtrl.text)
        ? _publicLogoUrlCtrl.text.trim()
        : '';
    final heroUrl = _isPublicHttpsUrl(_publicHeroPhotoUrlCtrl.text)
        ? _publicHeroPhotoUrlCtrl.text.trim()
        : '';
    final hasLogo = logoUrl.isNotEmpty;
    final hasHero = heroUrl.isNotEmpty;
    final hasAny = hasLogo || hasHero;

    Widget fallbackTile({
      required String label,
      required IconData icon,
      double height = 120,
    }) {
      return Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF17110A),
              const Color(0xFF111214),
              _setupGold.withOpacity(0.18),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _setupGold.withOpacity(0.22)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(icon, color: _setupGold.withOpacity(0.96)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.86),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _setupGold.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              nl: 'Publieke media preview',
              en: 'Public media preview',
              fr: 'AperÃ§u des mÃ©dias publics',
              es: 'Vista previa de medios pÃºblicos',
            ),
            style: TextStyle(
              color: _setupGold.withOpacity(0.98),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (!hasAny)
            fallbackTile(
              label: _t(
                nl: 'Nog geen publieke media geÃ¼pload.',
                en: 'No public media uploaded yet.',
                fr: 'Aucun mÃ©dia public tÃ©lÃ©versÃ© pour le moment.',
                es: 'AÃºn no se ha subido ningÃºn medio pÃºblico.',
              ),
              icon: Icons.image_not_supported_outlined,
              height: 72,
            )
          else ...[
            if (hasHero)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 156,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        heroUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => fallbackTile(
                          label: _t(
                            nl: 'Publieke coverfoto',
                            en: 'Public cover photo',
                            fr: 'Photo de couverture publique',
                            es: 'Foto de portada pÃºblica',
                          ),
                          icon: Icons.image_outlined,
                          height: 156,
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.black.withOpacity(0.15),
                                Colors.black.withOpacity(0.55),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: _statusPill(
                          _t(
                            nl: 'Cover geÃ¼pload',
                            en: 'Cover uploaded',
                            fr: 'Couverture tÃ©lÃ©versÃ©e',
                            es: 'Portada subida',
                          ),
                          _setupGold,
                        ),
                      ),
                      if (hasLogo)
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.82),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.25),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.network(
                              logoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.business_outlined,
                                color: _setupGold.withOpacity(0.96),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (!hasHero && hasLogo)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: fallbackTile(
                  label: _t(
                    nl: 'Publiek logo',
                    en: 'Public logo',
                    fr: 'Logo public',
                    es: 'Logo pÃºblico',
                  ),
                  icon: Icons.business_outlined,
                ),
              ),
            if (!hasHero && hasLogo) ...[
              const SizedBox(height: 8),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _setupGold.withOpacity(0.24)),
                  color: const Color(0xFF0F1014),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.network(
                  logoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(
                      Icons.business_outlined,
                      color: _setupGold.withOpacity(0.96),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (hasLogo)
                  _statusPill(
                    _t(
                      nl: 'Logo geÃ¼pload',
                      en: 'Logo uploaded',
                      fr: 'Logo tÃ©lÃ©versÃ©',
                      es: 'Logo subido',
                    ),
                    const Color(0xFF34D29A),
                  ),
                if (hasHero)
                  _statusPill(
                    _t(
                      nl: 'Cover geÃ¼pload',
                      en: 'Cover uploaded',
                      fr: 'Couverture tÃ©lÃ©versÃ©e',
                      es: 'Portada subida',
                    ),
                    const Color(0xFF34D29A),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Set<String> _sanitizePublicServiceIds(Iterable<String> values) {
    final allowed = _publicServiceCatalog.toSet();
    final out = <String>{};
    for (final value in values) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty || !allowed.contains(normalized)) continue;
      out.add(normalized);
    }
    return out;
  }

  List<String> _legacyPublicServiceIdsFromCalculator() {
    final selected = _serviceIds.map((s) => s.trim().toLowerCase()).toSet();
    final mapped = <String>{};
    if (selected.contains('airport')) mapped.add('airport_transfer');
    if (selected.contains('passenger')) mapped.add('taxi_vvb');
    if (selected.contains('business')) mapped.add('business_rides');
    if (selected.contains('event')) mapped.add('event_mobility');
    if (selected.contains('courier')) mapped.add('hotel_bnb_pickup');
    if (selected.contains('care')) mapped.add('taxi_vvb');
    if (mapped.isNotEmpty) mapped.add('online_payments');
    return mapped.toList(growable: false);
  }

  List<String> _mappedPublicServiceIds() {
    final explicit = _sanitizePublicServiceIds(_publicServiceIds);
    if (_publicServicesConfigured) {
      return explicit.toList(growable: false);
    }
    // Temporary fallback for tenants that still have no dedicated public
    // service configuration saved yet.
    return _legacyPublicServiceIdsFromCalculator();
  }

  String _publicServiceLabel(String id) {
    switch (id.trim().toLowerCase()) {
      case 'taxi_vvb':
        return _t(
          nl: 'Taxi & VVB',
          en: 'Taxi & VVB',
          fr: 'Taxi & VVB',
          es: 'Taxi & VVB',
        );
      case 'airport_transfer':
        return _t(
          nl: 'Luchthavenvervoer',
          en: 'Airport transfer',
          fr: 'Transfert aÃ©roport',
          es: 'Traslado aeropuerto',
        );
      case 'business_rides':
        return _t(
          nl: 'Zakelijke ritten',
          en: 'Business rides',
          fr: 'Trajets business',
          es: 'Viajes de empresa',
        );
      case 'event_mobility':
        return _t(
          nl: 'Evenementen',
          en: 'Events',
          fr: 'Ã‰vÃ©nements',
          es: 'Eventos',
        );
      case 'hotel_bnb_pickup':
        return _t(
          nl: 'Hotels & B&B',
          en: 'Hotels & B&B',
          fr: 'HÃ´tels & B&B',
          es: 'Hoteles y B&B',
        );
      case 'online_payments':
        return _t(
          nl: 'Online betalen',
          en: 'Online payments',
          fr: 'Paiement en ligne',
          es: 'Pago online',
        );
      default:
        return id;
    }
  }

  String _publicTierCategoryLabel(String tierId) {
    final needle = tierId.trim();
    for (final t in appConfig.enabledTiers) {
      if (t.id == needle) {
        return t.labelFor(_lang).trim();
      }
    }
    return needle.isEmpty ? 'Comfort' : needle;
  }

  String _normalizeServedPostcodeToken(String value) {
    return value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  List<String> _normalizeServedPostcodes(String raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final part in raw.split(RegExp(r'[\s,;]+'))) {
      final token = _normalizeServedPostcodeToken(part);
      if (token.isEmpty || seen.contains(token)) continue;
      seen.add(token);
      out.add(token);
    }
    return out;
  }

  Set<String> _sanitizePublicPaymentOptionIds(Iterable<String> values) {
    final allowed = _publicPaymentOptionCatalog.toSet();
    final out = <String>{};
    for (final value in values) {
      final raw = value.trim().toLowerCase();
      final id = switch (raw) {
        'qr' => 'qr_code',
        'online_payments' => 'online_payment',
        _ => raw,
      };
      if (id.isEmpty || !allowed.contains(id)) continue;
      out.add(id);
    }
    return out;
  }

  String _publicPaymentOptionLabel(String id) {
    switch (id.trim().toLowerCase()) {
      case 'cash':
        return _t(nl: 'Cash', en: 'Cash', fr: 'EspÃ¨ces', es: 'Efectivo');
      case 'qr_code':
        return _t(
          nl: 'QR-code',
          en: 'QR code',
          fr: 'Code QR',
          es: 'CÃ³digo QR',
        );
      case 'tikkie':
        return 'Tikkie';
      case 'bancontact':
        return 'Bancontact';
      case 'payconiq_wero':
        return 'Payconiq / Wero';
      case 'ideal':
        return 'iDEAL';
      case 'cartes_bancaires':
        return 'Carte Bancaire / CB';
      case 'card_payment':
        return _t(
          nl: 'Kaartbetaling',
          en: 'Card payment',
          fr: 'Paiement par carte',
          es: 'Pago con tarjeta',
        );
      case 'apple_pay':
        return 'Apple Pay';
      case 'google_pay':
        return 'Google Pay';
      case 'paypal':
        return 'PayPal';
      case 'online_payment':
        return _t(
          nl: 'Online betaling',
          en: 'Online payment',
          fr: 'Paiement en ligne',
          es: 'Pago online',
        );
      case 'bank_transfer_bacs':
        return _t(
          nl: 'Bankoverschrijving',
          en: 'Bank transfer',
          fr: 'Virement bancaire',
          es: 'Transferencia bancaria',
        );
      default:
        return id.replaceAll('_', ' ');
    }
  }

  double? _tryParsePublicLat(String value) {
    final n = double.tryParse(value.replaceAll(',', '.').trim());
    if (n == null || !n.isFinite) return null;
    if (n < -90 || n > 90) return null;
    return n;
  }

  double? _tryParsePublicLng(String value) {
    final n = double.tryParse(value.replaceAll(',', '.').trim());
    if (n == null || !n.isFinite) return null;
    if (n < -180 || n > 180) return null;
    return n;
  }

  int? _tryParsePublicServiceRadiusKm(String value) {
    final n = double.tryParse(value.replaceAll(',', '.').trim());
    if (n == null || !n.isFinite) return null;
    final rounded = n.round();
    if (rounded < 1 || rounded > 100) return null;
    return rounded;
  }

  bool _hasPublicCoverageLocationSet() {
    return _tryParsePublicLat(_publicCoverageLatCtrl.text) != null &&
        _tryParsePublicLng(_publicCoverageLngCtrl.text) != null;
  }

  String _publicCoverageCoordsLabel() {
    final lat = _tryParsePublicLat(_publicCoverageLatCtrl.text);
    final lng = _tryParsePublicLng(_publicCoverageLngCtrl.text);
    if (lat == null || lng == null) return '';
    return '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
  }

  Future<void> _useCurrentLocationAsBusinessLocation() async {
    try {
      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Locatieservices zijn uitgeschakeld op dit toestel.',
                en: 'Location services are disabled on this device.',
                fr: 'Les services de localisation sont dÃ©sactivÃ©s sur cet appareil.',
                es: 'Los servicios de ubicaciÃ³n estÃ¡n desactivados en este dispositivo.',
              ),
            ),
          ),
        );
        return;
      }

      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Locatietoegang geweigerd.',
                en: 'Location access denied.',
                fr: 'AccÃ¨s Ã  la localisation refusÃ©.',
                es: 'Acceso a la ubicaciÃ³n denegado.',
              ),
            ),
          ),
        );
        return;
      }
      if (permission == geo.LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Locatietoegang permanent geweigerd. Schakel toestemming in via instellingen.',
                en: 'Location access is permanently denied. Enable permission in settings.',
                fr: 'Lâ€™accÃ¨s Ã  la localisation est refusÃ© dÃ©finitivement. Activez lâ€™autorisation dans les paramÃ¨tres.',
                es: 'El acceso a la ubicaciÃ³n estÃ¡ denegado permanentemente. Activa el permiso en la configuraciÃ³n.',
              ),
            ),
          ),
        );
        return;
      }

      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() {
        _publicCoverageLatCtrl.text = pos.latitude.toStringAsFixed(6);
        _publicCoverageLngCtrl.text = pos.longitude.toStringAsFixed(6);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Bedrijfslocatie ingesteld. Sla op en publiceer je profiel opnieuw.',
              en: 'Business location set. Save and publish your profile again.',
              fr: 'Emplacement professionnel dÃ©fini. Enregistrez et republiez votre profil.',
              es: 'UbicaciÃ³n de empresa configurada. Guarda y publica tu perfil de nuevo.',
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Huidige locatie kon niet worden opgehaald.',
              en: 'Could not fetch current location.',
              fr: 'Impossible de rÃ©cupÃ©rer la position actuelle.',
              es: 'No se pudo obtener la ubicaciÃ³n actual.',
            ),
          ),
        ),
      );
    }
  }

  Map<String, dynamic> _buildPublicPartnerProfilePayload({
    required String companyId,
  }) {
    final profileForm = _backendBusinessProfileFromForm();
    final localCompany = companyProfileNotifier.value;
    final companyName = profileForm.companyName.trim().isNotEmpty
        ? profileForm.companyName.trim()
        : (localCompany?.companyName.trim().isNotEmpty == true
              ? localCompany!.companyName.trim()
              : businessSettingsNotifier.value.companyName.trim());
    final postcode = profileForm.postcode.trim().isNotEmpty
        ? profileForm.postcode.trim()
        : (localCompany?.postalCode.trim() ?? '');
    final primaryPostcode = _normalizeServedPostcodeToken(postcode);
    final extraServedPostcodes = _normalizeServedPostcodes(
      profileForm.publicServedPostcodes,
    );
    final coveragePostcodes = <String>[
      if (primaryPostcode.isNotEmpty) primaryPostcode,
      ...extraServedPostcodes.where((pc) => pc != primaryPostcode),
    ];
    final city = profileForm.city.trim().isNotEmpty
        ? profileForm.city.trim()
        : (localCompany?.city.trim() ?? '');
    final country = profileForm.country.trim().isNotEmpty
        ? profileForm.country.trim()
        : (localCompany?.countryCode.trim() ?? '');
    final regionLabel = <String>[
      if (city.isNotEmpty) city,
      if (postcode.isNotEmpty) postcode,
      if (country.isNotEmpty) country,
    ].join(' â€¢ ');
    final services = _mappedPublicServiceIds();
    final companyPhone = profileForm.phone.trim().isNotEmpty
        ? profileForm.phone.trim()
        : (localCompany?.phone.trim() ?? '');
    final onlinePaymentsEnabled = services.contains('online_payments');
    final airportServiceEnabled = services.contains('airport_transfer');
    final publicPaymentMethods = _sanitizePublicPaymentOptionIds(
      _publicPaymentOptionIds,
    ).toList(growable: false);
    final coverageLat = _tryParsePublicLat(profileForm.publicCoverageLat);
    final coverageLng = _tryParsePublicLng(profileForm.publicCoverageLng);
    final serviceRadiusKm = _tryParsePublicServiceRadiusKm(
      profileForm.publicServiceRadiusKm,
    );

    final vehicles = vehiclesNotifier.value
        .where((v) => v.isActive)
        .where((v) => (v.companyId?.trim() ?? '') == companyId)
        .map((v) {
          final brand = v.brandModel.trim();
          final tier = v.tierId.trim().toLowerCase();
          final features = <String>{
            if (tier == 'comfort' || tier == 'private' || tier == 'premium')
              'comfort',
            if (brand.toLowerCase().contains('tesla') ||
                brand.toLowerCase().contains('electric') ||
                brand.toLowerCase().contains('ev'))
              'ev_available',
          };
          final publicPhoto = v.publicPhotoUrl?.trim() ?? '';
          final photoRef = v.primaryPhotoRef.trim();
          return <String, dynamic>{
            'name': v.vehicleName.trim(),
            'brand_model': brand,
            'category': _publicTierCategoryLabel(v.tierId),
            'pax': v.passengerCapacity < 0 ? 0 : v.passengerCapacity,
            'luggage': v.luggageCapacity < 0 ? 0 : v.luggageCapacity,
            'features': features.toList(growable: false),
            'photo_url': _isPublicHttpsUrl(publicPhoto)
                ? publicPhoto
                : (_isPublicHttpsUrl(photoRef) ? photoRef : ''),
          };
        })
        .toList(growable: false);

    final drivers = driversNotifier.value
        .where((d) => d.publicProfileEnabled)
        .where((d) => d.isActive)
        .where((d) => (d.companyId?.trim() ?? '') == companyId)
        .map((d) {
          final displayName = d.publicDisplayName?.trim() ?? '';
          final candidatePortrait = d.publicPortraitUrl?.trim() ?? '';
          return <String, dynamic>{
            'display_name': displayName.isNotEmpty
                ? displayName
                : _t(
                    nl: 'Professionele chauffeur',
                    en: 'Professional driver',
                    fr: 'Chauffeur professionnel',
                    es: 'Conductor profesional',
                  ),
            'languages': const <String>[],
            'badges': const <String>['verified_professional'],
            'portrait_url':
                d.publicProfileEnabled &&
                    d.publicPhotoEnabled &&
                    _isPublicHttpsUrl(candidatePortrait)
                ? candidatePortrait
                : '',
          };
        })
        .toList(growable: false);

    return <String, dynamic>{
      'partner_id': companyId,
      'company_name': companyName,
      'profile_enabled': true,
      'is_active': true,
      'subscription_status': 'active',
      'tagline': _t(
        nl: 'Premium mobiliteit in jouw regio',
        en: 'Premium mobility in your area',
        fr: 'Mobilite premium dans votre region',
        es: 'Movilidad premium en tu zona',
      ),
      'about_short': _t(
        nl: 'Betrouwbare ritten voor particulieren en bedrijven.',
        en: 'Reliable rides for private and business customers.',
        fr: 'Trajets fiables pour particuliers et entreprises.',
        es: 'Viajes fiables para clientes particulares y empresas.',
      ),
      'about_long': _t(
        nl: 'Dit publiek profiel bevat enkel veilige bedrijfsinformatie. Gevoelige interne gegevens worden niet gepubliceerd.',
        en: 'This public profile contains only safe company information. Sensitive internal data is not published.',
        fr: 'Ce profil public contient uniquement des informations d entreprise securisees. Les donnees internes sensibles ne sont pas publiees.',
        es: 'Este perfil publico contiene solo informacion empresarial segura. Los datos internos sensibles no se publican.',
      ),
      'coverage': <String, dynamic>{
        'region_label': regionLabel,
        'primary_postcode': primaryPostcode,
        'postcodes': coveragePostcodes,
        if (coverageLat != null && coverageLng != null) 'lat': coverageLat,
        if (coverageLat != null && coverageLng != null) 'lng': coverageLng,
        if (serviceRadiusKm != null) 'service_radius_km': serviceRadiusKm,
      },
      'public_contact': <String, dynamic>{
        'website': profileForm.website.trim(),
        'public_phone': companyPhone,
        'booking_email': profileForm.bookingEmail.trim(),
      },
      'media': <String, dynamic>{
        'logo_url': _isPublicHttpsUrl(profileForm.publicLogoUrl)
            ? profileForm.publicLogoUrl.trim()
            : '',
        'hero_photo_url': _isPublicHttpsUrl(profileForm.publicHeroPhotoUrl)
            ? profileForm.publicHeroPhotoUrl.trim()
            : '',
        'gallery': const <String>[],
      },
      'services': services,
      'airport_service_enabled': airportServiceEnabled,
      'airportServiceEnabled': airportServiceEnabled,
      'airport_transfer_enabled': airportServiceEnabled,
      'airportTransferEnabled': airportServiceEnabled,
      'capabilities': <String, dynamic>{
        'airport': airportServiceEnabled,
        'airport_transfer': airportServiceEnabled,
      },
      'payment_methods': publicPaymentMethods,
      'vehicles': vehicles,
      'drivers': drivers,
      'trust': const <String, dynamic>{
        'verified_partner': false,
        'professional_badge': false,
      },
      'booking_capabilities': <String, dynamic>{
        'online_payments': onlinePaymentsEnabled,
        'instant_quote': false,
        'profile_enabled': true,
        'airport': airportServiceEnabled,
        'airport_transfer': airportServiceEnabled,
        'airport_service_enabled': airportServiceEnabled,
        'airportServiceEnabled': airportServiceEnabled,
        'airport_transfer_enabled': airportServiceEnabled,
        'airportTransferEnabled': airportServiceEnabled,
      },
    };
  }

  Future<bool> _publishPublicPartnerProfile() async {
    setState(() {
      _publicPartnerProfilePublishing = true;
      _publicPartnerProfileStatus = null;
      _publicPartnerProfileError = null;
    });
    try {
      final scope = _activeSettingsScope();
      // Keep publish flow stateful: persist current business form values first
      // so manual public media URLs survive page close/reopen even if the user
      // uses "Publish public profile" without tapping "Save company details".
      final formProfile = _backendBusinessProfileFromForm();
      await updateLocalBackendBusinessProfileCache(formProfile);
      final savedBusiness = await saveBackendBusinessProfile(
        formProfile,
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return false;
      await _hydratePublicCompanyCodeFromBackendProfile(
        savedBusiness,
        source: 'business_profile_publish_pre_post',
      );
      final mergedBusiness = _mergeBackendBusinessProfile(
        local: formProfile,
        server: savedBusiness,
      );
      _hydrateBackendBusinessProfile(mergedBusiness);
      unawaited(updateLocalBackendBusinessProfileCache(mergedBusiness));

      final payload = _buildPublicPartnerProfilePayload(
        companyId: scope.companyId,
      );
      await publishBackendPublicPartnerProfile(
        partnerProfile: payload,
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return false;
      final publishedAt = DateTime.now().toUtc().toIso8601String();
      final publishedBusiness = BackendBusinessProfile(
        companyName: mergedBusiness.companyName,
        legalName: mergedBusiness.legalName,
        vatNumber: mergedBusiness.vatNumber,
        companyRegistrationNumber: mergedBusiness.companyRegistrationNumber,
        address: mergedBusiness.address,
        postcode: mergedBusiness.postcode,
        city: mergedBusiness.city,
        country: mergedBusiness.country,
        phone: mergedBusiness.phone,
        email: mergedBusiness.email,
        website: mergedBusiness.website,
        bookingEmail: mergedBusiness.bookingEmail,
        publicLogoUrl: mergedBusiness.publicLogoUrl,
        publicHeroPhotoUrl: mergedBusiness.publicHeroPhotoUrl,
        publicServedPostcodes: mergedBusiness.publicServedPostcodes,
        publicCoverageLat: mergedBusiness.publicCoverageLat,
        publicCoverageLng: mergedBusiness.publicCoverageLng,
        publicServiceRadiusKm: mergedBusiness.publicServiceRadiusKm,
        publicPaymentOptions: mergedBusiness.publicPaymentOptions,
        publicServiceIds: mergedBusiness.publicServiceIds,
        publicServicesConfigured: mergedBusiness.publicServicesConfigured,
        publicPartnerProfilePublishedAt: publishedAt,
        publicPartnerProfilePublishStatus: 'published',
        invoiceEmail: mergedBusiness.invoiceEmail,
        iban: mergedBusiness.iban,
        paymentReferencePrefix: mergedBusiness.paymentReferencePrefix,
        invoiceReceiptFooterText: mergedBusiness.invoiceReceiptFooterText,
      );
      await updateLocalBackendBusinessProfileCache(publishedBusiness);
      final savedPublishedBusiness = await saveBackendBusinessProfile(
        publishedBusiness,
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return false;
      await _hydratePublicCompanyCodeFromBackendProfile(
        savedPublishedBusiness,
        source: 'business_profile_publish_post',
      );
      final mergedPublishedBusiness = _mergeBackendBusinessProfile(
        local: publishedBusiness,
        server: savedPublishedBusiness,
      );
      setState(() {
        _hydrateBackendBusinessProfile(mergedPublishedBusiness);
        _publicPartnerProfileStatus = _t(
          nl: 'Publiek partnerprofiel gepubliceerd.',
          en: 'Public partner profile published.',
          fr: 'Profil partenaire public publie.',
          es: 'Perfil publico del socio publicado.',
        );
      });
      unawaited(
        updateLocalBackendBusinessProfileCache(mergedPublishedBusiness),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _publicPartnerProfileError =
            '${_t(nl: 'Publiceren mislukt', en: 'Publish failed', fr: 'Publication echouee', es: 'Error al publicar')}: $e';
      });
      return false;
    } finally {
      if (mounted) {
        setState(() => _publicPartnerProfilePublishing = false);
      }
    }
  }

  bool _isPublicPartnerProfilePublished() {
    final status = _publicPartnerProfilePublishStatus.trim().toLowerCase();
    if (status == 'published') return true;
    return _publicPartnerProfilePublishedAt.trim().isNotEmpty;
  }

  double _toMoney(String raw, double fallback) {
    final parsed = double.tryParse(raw.replaceAll(',', '.').trim());
    if (parsed == null || !parsed.isFinite) return fallback;
    if (parsed < 0) return 0;
    return parsed;
  }

  Future<void> _save() async {
    if (_saveAllBusy) return;
    final current = businessSettingsNotifier.value;
    final scope = _activeSettingsScope();
    final vat = _activeVatConfig();
    final failedParts = <String>[];
    final saveAirportRules =
        _airportFixedFaresDirty && !_airportFixedFaresLoading;
    setState(() => _saveAllBusy = true);
    try {
      updateBusinessSettings(
        current.copyWith(
          companyName: _companyCtrl.text.trim(),
          supportEmail: _supportEmailCtrl.text.trim(),
          supportPhone: _supportPhoneCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          vatCompanyNumber: _vatCtrl.text.trim(),
          logoAssetPath: _storedLogoPathForLocalTenant(
            _logoPathCtrl.text.trim(),
          ),
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
          pricingBaseFare: _toMoney(
            _baseFareCtrl.text,
            current.pricingBaseFare,
          ),
          pricingPerKm: _toMoney(_perKmCtrl.text, current.pricingPerKm),
          pricingPerMinute: _toMoney(
            _perMinCtrl.text,
            current.pricingPerMinute,
          ),
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
        syncToBackend: false,
      );

      final pricingSynced = await syncPricingProfileToBackend(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!pricingSynced) {
        failedParts.add(
          _t(
            nl: 'pricing synchronisatie',
            en: 'pricing sync',
            fr: 'synchronisation des tarifs',
            es: 'sincronizacion de precios',
          ),
        );
      }

      final businessSaved = await _saveBackendBusinessProfile();
      if (!businessSaved) {
        failedParts.add(
          _t(
            nl: 'bedrijfsprofiel',
            en: 'business profile',
            fr: 'profil entreprise',
            es: 'perfil empresarial',
          ),
        );
      }

      final taxSaved = await _saveBackendTaxProfile();
      if (!taxSaved) {
        failedParts.add(
          _t(
            nl: 'btw profiel',
            en: 'VAT profile',
            fr: 'profil TVA',
            es: 'perfil IVA',
          ),
        );
      }

      final publicPublished = await _publishPublicPartnerProfile();
      if (!publicPublished) {
        failedParts.add(
          _t(
            nl: 'publiek partnerprofiel',
            en: 'public partner profile',
            fr: 'profil partenaire public',
            es: 'perfil publico del socio',
          ),
        );
      }

      if (saveAirportRules) {
        final airportSaved = await _saveAirportFixedFareRules(
          showSnackBar: false,
        );
        if (!airportSaved) {
          failedParts.add(
            _t(
              nl: 'luchthaven vaste tariefregels',
              en: 'airport fixed fare rules',
              fr: 'regles tarif fixe aeroport',
              es: 'reglas de tarifa fija aeropuerto',
            ),
          );
        }
      }

      if (!mounted) return;
      final allSucceeded = failedParts.isEmpty;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            allSucceeded
                ? _t(
                    nl: 'Alles opgeslagen en gepubliceerd.',
                    en: 'Everything saved and published.',
                    fr: 'Tout est enregistre et publie.',
                    es: 'Todo se guardo y publico.',
                  )
                : _t(
                        nl: 'Deels opgeslagen. Mislukt: ',
                        en: 'Partially saved. Failed: ',
                        fr: 'Enregistrement partiel. Echec: ',
                        es: 'Guardado parcial. Fallo: ',
                      ) +
                      failedParts.join(', '),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saveAllBusy = false);
    }
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

  /// When tenant profile/settings load or update, clear Fluxidi defaults from controllers â€” but do not
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
              fr: 'Aucun logo dâ€™entreprise dÃ©fini',
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

  String _normalizePublicCompanyCode(String raw) {
    return raw
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  bool _isValidPublicCompanyCode(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return false;
    if (RegExp(r'[\s_]').hasMatch(raw)) return false;
    final v = _normalizePublicCompanyCode(value);
    if (v.length < 4 || v.length > 24) return false;
    if (!RegExp(r'^[A-Z0-9-]+$').hasMatch(v)) return false;
    if (!RegExp(r'^FLX(?:-?[0-9]{4,12})$').hasMatch(v)) return false;
    return true;
  }

  Future<void> _hydratePublicCompanyCodeFromBackendProfile(
    BackendBusinessProfile profile, {
    required String source,
  }) async {
    final profileMap = profile.toJson();
    for (final key in const <String>[
      'public_company_code',
      'publicCompanyCode',
      'company_code',
      'companyCode',
    ]) {
      final normalized = _normalizePublicCompanyCode(
        (profileMap[key] ?? '').toString(),
      );
      if (!_isValidPublicCompanyCode(normalized)) continue;
      await CompanySessionStore.instance.updateActiveSessionCompanyCode(
        normalized,
        source: source,
      );
      return;
    }
  }

  String? _activePublicCompanyCode({
    ActiveCompanySession? session,
    CompanyProfile? profile,
  }) {
    final fromSession = _normalizePublicCompanyCode(
      session?.companyCode ??
          activeCompanySessionNotifier.value?.companyCode ??
          '',
    );
    if (_isValidPublicCompanyCode(fromSession)) return fromSession;

    final profileMap = (profile ?? companyProfileNotifier.value)?.toJson();
    if (profileMap is Map<String, dynamic>) {
      String fromProfileKeys() {
        for (final key in const <String>[
          'companyCode',
          'publicCompanyCode',
          'company_code',
          'public_company_code',
        ]) {
          final normalized = _normalizePublicCompanyCode(
            (profileMap[key] ?? '').toString(),
          );
          if (_isValidPublicCompanyCode(normalized)) return normalized;
        }
        return '';
      }

      final fromProfile = fromProfileKeys();
      if (_isValidPublicCompanyCode(fromProfile)) return fromProfile;
    }
    return null;
  }

  ({String tenantId, String companyId}) _activeSettingsScope() {
    final activeCompanyId = _effectivePublicCompanyId().trim();
    final companyId = activeCompanyId.isEmpty ? kTenantId : activeCompanyId;
    return (tenantId: companyId, companyId: companyId);
  }

  String _airportRuleText(dynamic value, {String fallback = ''}) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  bool _airportRuleBool(dynamic value, {bool fallback = true}) {
    if (value is bool) return value;
    final text = (value ?? '').toString().trim().toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no') return false;
    return fallback;
  }

  int _airportRuleInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString().trim()) ?? fallback;
  }

  double? _airportRulePrice(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(
      (value ?? '').toString().trim().replaceAll(',', '.'),
    );
  }

  Map<String, dynamic>? _normalizeAirportFixedFareRule(dynamic raw, int idx) {
    if (raw is! Map) return null;
    final source = Map<String, dynamic>.from(raw);
    final airportIata = _airportRuleText(
      source['airport_iata'] ?? source['airportIata'],
    ).toUpperCase();
    final direction = _airportRuleText(source['direction']).toLowerCase();
    final zoneType = _airportRuleText(
      source['zone_type'] ?? source['zoneType'],
    ).toLowerCase();
    final zoneValue = _airportRuleText(
      source['zone_value'] ?? source['zoneValue'],
    );
    final zoneLabel = _airportRuleText(
      source['zone_label'] ?? source['zoneLabel'],
    );
    final zoneCenterLat = _airportRulePrice(
      source['zone_center_lat'] ??
          source['zoneCenterLat'] ??
          source['center_lat'] ??
          source['centerLat'],
    );
    final zoneCenterLng = _airportRulePrice(
      source['zone_center_lng'] ??
          source['zoneCenterLng'] ??
          source['center_lng'] ??
          source['centerLng'],
    );
    final radiusKm = _airportRulePrice(
      source['radius_km'] ?? source['radiusKm'],
    );
    final tier = _airportRuleText(source['tier']).toLowerCase();
    final price = _airportRulePrice(
      source['price_incl_vat'] ?? source['priceInclVat'],
    );
    final currency = _airportRuleText(
      source['currency'],
      fallback: 'EUR',
    ).toUpperCase();
    final isRadius = zoneType == 'radius';
    final zoneValid = isRadius
        ? zoneLabel.isNotEmpty &&
              zoneCenterLat != null &&
              zoneCenterLat.isFinite &&
              zoneCenterLat >= -90 &&
              zoneCenterLat <= 90 &&
              zoneCenterLng != null &&
              zoneCenterLng.isFinite &&
              zoneCenterLng >= -180 &&
              zoneCenterLng <= 180 &&
              radiusKm != null &&
              radiusKm.isFinite &&
              radiusKm >= 1 &&
              radiusKm <= 100
        : zoneValue.isNotEmpty;
    if (airportIata.isEmpty ||
        !_airportFixedFareDirections.contains(direction) ||
        !_airportFixedFareZoneTypes.contains(zoneType) ||
        !zoneValid ||
        !_airportFixedFareTiers.contains(tier) ||
        price == null ||
        !price.isFinite ||
        price <= 0) {
      return null;
    }
    return <String, dynamic>{
      'rule_id': _airportRuleText(
        source['rule_id'] ?? source['ruleId'],
        fallback: 'airport_rule_${idx + 1}',
      ),
      'enabled': _airportRuleBool(source['enabled'], fallback: true),
      'priority': _airportRuleInt(source['priority'], fallback: 0),
      'airport_iata': airportIata,
      'direction': direction,
      'zone_type': zoneType,
      if (!isRadius) 'zone_value': zoneValue,
      if (isRadius) 'zone_label': zoneLabel,
      if (isRadius) 'zone_center_lat': zoneCenterLat,
      if (isRadius) 'zone_center_lng': zoneCenterLng,
      if (isRadius) 'radius_km': radiusKm,
      'tier': tier,
      'price_incl_vat': price,
      'currency': currency.isEmpty ? 'EUR' : currency,
      'pax_min': _airportRuleInt(
        source['pax_min'] ?? source['paxMin'],
        fallback: 1,
      ),
      'pax_max': _airportRuleInt(
        source['pax_max'] ?? source['paxMax'],
        fallback: 99,
      ),
      'bags_max': _airportRuleInt(
        source['bags_max'] ?? source['bagsMax'],
        fallback: 99,
      ),
      if (_airportRuleText(source['airport_name']).isNotEmpty)
        'airport_name': _airportRuleText(source['airport_name']),
      if (_airportRuleText(source['airport_country']).isNotEmpty)
        'airport_country': _airportRuleText(source['airport_country']),
    };
  }

  String _nextAirportFixedFareRuleId(String airportIata, String direction) {
    final base = '${airportIata.toUpperCase()}_${direction.toLowerCase()}'
        .replaceAll(RegExp(r'[^A-Z0-9_]+'), '_');
    final seed = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '${base}_$seed';
  }

  List<String> _airportCatalogCountryCodes() {
    final out = <String>[];
    for (final item in _airportFixedFareCatalog) {
      final code = (item['country_code'] ?? '').trim().toUpperCase();
      if (code.isEmpty || out.contains(code)) continue;
      out.add(code);
    }
    return out;
  }

  String _airportCatalogCountryName(String countryCode) {
    final normalized = countryCode.trim().toUpperCase();
    for (final item in _airportFixedFareCatalog) {
      if ((item['country_code'] ?? '').trim().toUpperCase() == normalized) {
        final name = (item['country_name'] ?? '').trim();
        if (name.isNotEmpty) return name;
      }
    }
    return normalized;
  }

  List<Map<String, String>> _airportCatalogAirportsForCountry(
    String countryCode,
  ) {
    final normalized = countryCode.trim().toUpperCase();
    return _airportFixedFareCatalog
        .where(
          (item) =>
              (item['country_code'] ?? '').trim().toUpperCase() == normalized,
        )
        .map((item) => Map<String, String>.from(item))
        .toList(growable: false);
  }

  Map<String, String>? _airportCatalogByIata(String iata) {
    final normalized = iata.trim().toUpperCase();
    for (final item in _airportFixedFareCatalog) {
      if ((item['iata'] ?? '').trim().toUpperCase() == normalized) {
        return Map<String, String>.from(item);
      }
    }
    return null;
  }

  String _airportDirectionLabel(String value) {
    switch (value.trim().toLowerCase()) {
      case 'to_airport':
        return _t(
          nl: 'Naar luchthaven',
          en: 'To airport',
          fr: 'Vers aÃ©roport',
          es: 'Al aeropuerto',
        );
      case 'from_airport':
        return _t(
          nl: 'Van luchthaven',
          en: 'From airport',
          fr: 'Depuis aÃ©roport',
          es: 'Desde aeropuerto',
        );
      default:
        return value;
    }
  }

  String _airportZoneTypeLabel(String value) {
    switch (value.trim().toLowerCase()) {
      case 'postcode':
        return _t(
          nl: 'Postcode',
          en: 'Postcode',
          fr: 'Code postal',
          es: 'CÃ³digo postal',
        );
      case 'city':
        return _t(nl: 'Stad', en: 'City', fr: 'Ville', es: 'Ciudad');
      case 'country':
        return _t(nl: 'Land', en: 'Country', fr: 'Pays', es: 'PaÃ­s');
      case 'radius':
        return _t(
          nl: 'Radius rond locatie',
          en: 'Radius around location',
          fr: 'Rayon autour dâ€™un lieu',
          es: 'Radio alrededor de ubicaciÃ³n',
        );
      default:
        return value;
    }
  }

  String _airportTierLabel(String value) {
    switch (value.trim().toLowerCase()) {
      case 'comfort':
        return _t(nl: 'Comfort', en: 'Comfort', fr: 'Comfort', es: 'Comfort');
      case 'private':
        return _t(
          nl: 'Business',
          en: 'Business',
          fr: 'Business',
          es: 'Business',
        );
      case 'premium':
        return _t(nl: 'Premium', en: 'Premium', fr: 'Premium', es: 'Premium');
      default:
        return value;
    }
  }

  Future<void> _loadAirportFixedFareRules({bool showErrorSnack = false}) async {
    setState(() {
      _airportFixedFaresLoading = true;
      _airportFixedFaresError = null;
      _airportFixedFaresStatus = null;
    });
    try {
      final scope = _activeSettingsScope();
      final data = await fetchAdminAirportFixedFares(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      final rawDoc = data['airport_fixed_fares'];
      final doc = rawDoc is Map<String, dynamic>
          ? rawDoc
          : rawDoc is Map
          ? Map<String, dynamic>.from(rawDoc)
          : <String, dynamic>{};
      final rawRules = doc['rules'];
      final parsedRules = <Map<String, dynamic>>[];
      if (rawRules is List) {
        for (var i = 0; i < rawRules.length; i++) {
          final normalized = _normalizeAirportFixedFareRule(rawRules[i], i);
          if (normalized != null) parsedRules.add(normalized);
        }
      }
      if (!mounted) return;
      setState(() {
        _airportFixedFareRules = parsedRules;
        _airportFixedFaresVersion = _airportRuleInt(
          doc['version'],
          fallback: 1,
        );
        _airportFixedFaresUpdatedAt = _airportRuleText(
          doc['updated_at'] ?? doc['updatedAt'],
        );
        _airportFixedFaresStatus = _t(
          nl: 'Luchthaventarieven geladen.',
          en: 'Airport fixed fares loaded.',
          fr: 'Tarifs fixes aÃ©roport chargÃ©s.',
          es: 'Tarifas fijas de aeropuerto cargadas.',
        );
        _airportFixedFaresDirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().trim();
      setState(() {
        _airportFixedFaresError = message.isEmpty
            ? _t(
                nl: 'Luchthaventarieven konden niet worden geladen.',
                en: 'Airport fixed fares could not be loaded.',
                fr: 'Les tarifs fixes aÃ©roport nâ€™ont pas pu Ãªtre chargÃ©s.',
                es: 'No se pudieron cargar las tarifas fijas de aeropuerto.',
              )
            : message;
      });
      if (showErrorSnack) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_airportFixedFaresError!)));
      }
    } finally {
      if (mounted) {
        setState(() => _airportFixedFaresLoading = false);
      }
    }
  }

  Future<bool> _saveAirportFixedFareRules({bool showSnackBar = true}) async {
    if (_airportFixedFaresSaving) return false;
    setState(() {
      _airportFixedFaresSaving = true;
      _airportFixedFaresError = null;
      _airportFixedFaresStatus = null;
    });
    try {
      final scope = _activeSettingsScope();
      final payloadRules = _airportFixedFareRules
          .map((rule) => Map<String, dynamic>.from(rule))
          .toList(growable: false);
      final response = await saveAdminAirportFixedFares(
        <String, dynamic>{
          'version': _airportFixedFaresVersion <= 0
              ? 1
              : _airportFixedFaresVersion,
          'rules': payloadRules,
        },
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      final rawDoc = response['airport_fixed_fares'];
      final doc = rawDoc is Map<String, dynamic>
          ? rawDoc
          : rawDoc is Map
          ? Map<String, dynamic>.from(rawDoc)
          : <String, dynamic>{};
      final rawRules = doc['rules'];
      final parsedRules = <Map<String, dynamic>>[];
      if (rawRules is List) {
        for (var i = 0; i < rawRules.length; i++) {
          final normalized = _normalizeAirportFixedFareRule(rawRules[i], i);
          if (normalized != null) parsedRules.add(normalized);
        }
      }
      if (!mounted) return false;
      setState(() {
        _airportFixedFareRules = parsedRules;
        _airportFixedFaresVersion = _airportRuleInt(
          doc['version'],
          fallback: 1,
        );
        _airportFixedFaresUpdatedAt = _airportRuleText(
          doc['updated_at'] ?? doc['updatedAt'],
        );
        _airportFixedFaresStatus = _t(
          nl: 'Luchthaventarieven opgeslagen.',
          en: 'Airport fixed fares saved.',
          fr: 'Tarifs fixes aÃ©roport enregistrÃ©s.',
          es: 'Tarifas fijas de aeropuerto guardadas.',
        );
        _airportFixedFaresDirty = false;
      });
      if (showSnackBar) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_airportFixedFaresStatus!)));
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      final message = e.toString().trim();
      setState(() {
        _airportFixedFaresError = message.isEmpty
            ? _t(
                nl: 'Opslaan van luchthaventarieven mislukt.',
                en: 'Saving airport fixed fares failed.',
                fr: 'Ã‰chec de lâ€™enregistrement des tarifs fixes aÃ©roport.',
                es: 'Error al guardar tarifas fijas de aeropuerto.',
              )
            : message;
      });
      if (showSnackBar) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_airportFixedFaresError!)));
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _airportFixedFaresSaving = false);
      }
    }
  }

  _SetupStatus _airportFixedFaresSetupStatus() {
    if (_airportFixedFareRules.isEmpty) return _SetupStatus.attention;
    return _SetupStatus.complete;
  }

  Future<void> _editAirportFixedFareRule({int? index}) async {
    final existing =
        index != null && index >= 0 && index < _airportFixedFareRules.length
        ? Map<String, dynamic>.from(_airportFixedFareRules[index])
        : null;
    final zoneValueCtrl = TextEditingController(
      text: _airportRuleText(existing?['zone_value']),
    );
    final zoneLabelCtrl = TextEditingController(
      text: _airportRuleText(existing?['zone_label']),
    );
    final zoneCenterLatCtrl = TextEditingController(
      text: _airportRuleText(existing?['zone_center_lat']),
    );
    final zoneCenterLngCtrl = TextEditingController(
      text: _airportRuleText(existing?['zone_center_lng']),
    );
    final radiusKmCtrl = TextEditingController(
      text: _airportRuleText(existing?['radius_km']),
    );
    final priceCtrl = TextEditingController(
      text: existing == null
          ? ''
          : ((_airportRulePrice(existing['price_incl_vat']) ?? 0)
                .toStringAsFixed(2)),
    );
    var selectedCurrency = _airportRuleText(
      existing?['currency'],
      fallback: 'EUR',
    ).trim().toUpperCase();
    if (!_airportFixedFareCurrencies.contains(selectedCurrency)) {
      selectedCurrency = 'EUR';
    }
    final countryCodes = _airportCatalogCountryCodes();
    final existingAirport = _airportCatalogByIata(
      _airportRuleText(existing?['airport_iata']),
    );
    var selectedCountryCode = (existingAirport?['country_code'] ?? '')
        .trim()
        .toUpperCase();
    if (selectedCountryCode.isEmpty && countryCodes.isNotEmpty) {
      selectedCountryCode = countryCodes.first;
    }
    var airportsForCountry = _airportCatalogAirportsForCountry(
      selectedCountryCode,
    );
    var selectedAirportIata = _airportRuleText(
      existing?['airport_iata'],
    ).trim().toUpperCase();
    final existingAirportName = _airportRuleText(existing?['airport_name']);
    final existingAirportCountry = _airportRuleText(
      existing?['airport_country'],
    );
    if (selectedAirportIata.isEmpty && airportsForCountry.isNotEmpty) {
      selectedAirportIata = (airportsForCountry.first['iata'] ?? '')
          .toUpperCase();
    }
    if (selectedAirportIata.isNotEmpty &&
        !airportsForCountry.any(
          (item) =>
              (item['iata'] ?? '').trim().toUpperCase() == selectedAirportIata,
        )) {
      airportsForCountry = <Map<String, String>>[
        <String, String>{
          'country_code': selectedCountryCode,
          'country_name': existingAirportCountry,
          'iata': selectedAirportIata,
          'airport_name': existingAirportName.isNotEmpty
              ? existingAirportName
              : selectedAirportIata,
        },
        ...airportsForCountry,
      ];
    }
    if (selectedAirportIata.isNotEmpty &&
        !airportsForCountry.any(
          (item) =>
              (item['iata'] ?? '').trim().toUpperCase() == selectedAirportIata,
        ) &&
        airportsForCountry.isNotEmpty) {
      selectedAirportIata = (airportsForCountry.first['iata'] ?? '')
          .toUpperCase();
    }
    var enabled = _airportRuleBool(existing?['enabled'], fallback: true);
    var direction = _airportRuleText(
      existing?['direction'],
      fallback: 'to_airport',
    ).toLowerCase();
    if (!_airportFixedFareDirections.contains(direction)) {
      direction = _airportFixedFareDirections.first;
    }
    var zoneType = _airportRuleText(
      existing?['zone_type'],
      fallback: 'postcode',
    ).toLowerCase();
    if (!_airportFixedFareZoneTypes.contains(zoneType)) {
      zoneType = _airportFixedFareZoneTypes.first;
    }
    var radiusPreset = '20';
    final existingRadius = _airportRulePrice(existing?['radius_km']);
    if (existingRadius != null) {
      if ((existingRadius - 10).abs() < 0.0001) {
        radiusPreset = '10';
      } else if ((existingRadius - 20).abs() < 0.0001) {
        radiusPreset = '20';
      } else if ((existingRadius - 30).abs() < 0.0001) {
        radiusPreset = '30';
      } else {
        radiusPreset = 'custom';
      }
    } else if (radiusKmCtrl.text.trim().isNotEmpty) {
      radiusPreset = 'custom';
    }
    var tier = _airportRuleText(
      existing?['tier'],
      fallback: 'comfort',
    ).toLowerCase();
    if (!_airportFixedFareTiers.contains(tier)) {
      tier = _airportFixedFareTiers.first;
    }
    var showAdvancedRadiusCoordinates = false;
    String? airportError;
    String? zoneError;
    String? radiusError;
    String? priceError;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final viewInsets = MediaQuery.of(context).viewInsets;
            final media = MediaQuery.of(context).size;
            final airportDropdownItems = airportsForCountry
                .map(
                  (item) => DropdownMenuItem<String>(
                    value: (item['iata'] ?? '').toUpperCase(),
                    child: Text(
                      '${item['airport_name'] ?? ''} (${item['iata'] ?? ''})',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                )
                .toList(growable: false);
            return SafeArea(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: viewInsets.bottom),
                child: Dialog(
                  backgroundColor: const Color(0xFF111111),
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: media.height * 0.92),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            existing == null
                                ? _t(
                                    nl: 'Regel toevoegen',
                                    en: 'Add rule',
                                    fr: 'Ajouter une regle',
                                    es: 'Agregar regla',
                                  )
                                : _t(
                                    nl: 'Regel bewerken',
                                    en: 'Edit rule',
                                    fr: 'Modifier la regle',
                                    es: 'Editar regla',
                                  ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    value: enabled,
                                    onChanged: (value) =>
                                        setDialogState(() => enabled = value),
                                    title: Text(
                                      _t(
                                        nl: 'Ingeschakeld',
                                        en: 'Enabled',
                                        fr: 'Active',
                                        es: 'Habilitado',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: selectedCountryCode.isEmpty
                                        ? null
                                        : selectedCountryCode,
                                    decoration: InputDecoration(
                                      labelText: _t(
                                        nl: 'Land',
                                        en: 'Country',
                                        fr: 'Pays',
                                        es: 'Pais',
                                      ),
                                    ),
                                    items: countryCodes
                                        .map(
                                          (code) => DropdownMenuItem<String>(
                                            value: code,
                                            child: Text(
                                              _airportCatalogCountryName(code),
                                            ),
                                          ),
                                        )
                                        .toList(growable: false),
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setDialogState(() {
                                        selectedCountryCode = value;
                                        airportsForCountry =
                                            _airportCatalogAirportsForCountry(
                                              selectedCountryCode,
                                            );
                                        selectedAirportIata =
                                            airportsForCountry.isNotEmpty
                                            ? (airportsForCountry
                                                          .first['iata'] ??
                                                      '')
                                                  .toUpperCase()
                                            : '';
                                        airportError = null;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: selectedAirportIata.isEmpty
                                        ? null
                                        : selectedAirportIata,
                                    decoration: InputDecoration(
                                      labelText: _t(
                                        nl: 'Luchthaven',
                                        en: 'Airport',
                                        fr: 'Aeroport',
                                        es: 'Aeropuerto',
                                      ),
                                    ),
                                    selectedItemBuilder: (_) {
                                      return airportsForCountry
                                          .map(
                                            (item) => Text(
                                              '${item['airport_name'] ?? ''} (${item['iata'] ?? ''})',
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          )
                                          .toList(growable: false);
                                    },
                                    items: airportDropdownItems,
                                    onChanged: (value) {
                                      setDialogState(() {
                                        selectedAirportIata = (value ?? '')
                                            .toUpperCase();
                                        airportError = null;
                                      });
                                    },
                                  ),
                                  if (airportError != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      airportError!,
                                      style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: direction,
                                    decoration: InputDecoration(
                                      labelText: _t(
                                        nl: 'Richting',
                                        en: 'Direction',
                                        fr: 'Direction',
                                        es: 'Direccion',
                                      ),
                                    ),
                                    items: _airportFixedFareDirections
                                        .map(
                                          (value) => DropdownMenuItem<String>(
                                            value: value,
                                            child: Text(
                                              _airportDirectionLabel(value),
                                            ),
                                          ),
                                        )
                                        .toList(growable: false),
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setDialogState(() => direction = value);
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: zoneType,
                                    decoration: InputDecoration(
                                      labelText: _t(
                                        nl: 'Zone type',
                                        en: 'Zone type',
                                        fr: 'Type de zone',
                                        es: 'Tipo de zona',
                                      ),
                                    ),
                                    items: _airportFixedFareZoneTypes
                                        .map(
                                          (value) => DropdownMenuItem<String>(
                                            value: value,
                                            child: Text(
                                              _airportZoneTypeLabel(value),
                                            ),
                                          ),
                                        )
                                        .toList(growable: false),
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setDialogState(() {
                                        zoneType = value;
                                        zoneError = null;
                                        radiusError = null;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  if (zoneType == 'radius') ...[
                                    _txt(
                                      zoneLabelCtrl,
                                      _t(
                                        nl: 'Locatiecentrum',
                                        en: 'Centre location',
                                        fr: 'Centre de la zone',
                                        es: 'Centro de la zona',
                                      ),
                                      hint: _t(
                                        nl: 'Bijv. Maarkedal centrum',
                                        en: 'E.g. Maarkedal center',
                                        fr: 'Ex. centre de Maarkedal',
                                        es: 'Ej. centro de Maarkedal',
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _t(
                                        nl: 'Gebruik een plaats, postcode of adres als middelpunt van deze zone.',
                                        en: 'Use a place, postcode, or address as the center of this zone.',
                                        fr: 'Utilisez un lieu, code postal ou adresse comme centre de cette zone.',
                                        es: 'Usa una ciudad, codigo postal o direccion como centro de esta zona.',
                                      ),
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.72),
                                        fontSize: 12,
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      value: radiusPreset,
                                      decoration: InputDecoration(
                                        labelText: _t(
                                          nl: 'Radius',
                                          en: 'Radius',
                                          fr: 'Rayon',
                                          es: 'Radio',
                                        ),
                                      ),
                                      items:
                                          const <String>[
                                                '10',
                                                '20',
                                                '30',
                                                'custom',
                                              ]
                                              .map(
                                                (
                                                  value,
                                                ) => DropdownMenuItem<String>(
                                                  value: value,
                                                  child: Text(
                                                    value == 'custom'
                                                        ? _t(
                                                            nl: 'Aangepast',
                                                            en: 'Custom',
                                                            fr: 'Personnalise',
                                                            es: 'Personalizado',
                                                          )
                                                        : '$value km',
                                                  ),
                                                ),
                                              )
                                              .toList(growable: false),
                                      onChanged: (value) {
                                        if (value == null) return;
                                        setDialogState(() {
                                          radiusPreset = value;
                                          if (value != 'custom') {
                                            radiusKmCtrl.text = value;
                                          }
                                          radiusError = null;
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                    if (radiusPreset == 'custom')
                                      _txt(
                                        radiusKmCtrl,
                                        _t(
                                          nl: 'Aangepaste radius (km)',
                                          en: 'Custom radius (km)',
                                          fr: 'Rayon personnalise (km)',
                                          es: 'Radio personalizado (km)',
                                        ),
                                      ),
                                    ExpansionTile(
                                      tilePadding: EdgeInsets.zero,
                                      childrenPadding: EdgeInsets.zero,
                                      collapsedIconColor: const Color(
                                        0xFFE5B641,
                                      ),
                                      iconColor: const Color(0xFFE5B641),
                                      textColor: Colors.white,
                                      collapsedTextColor: Colors.white70,
                                      initiallyExpanded:
                                          showAdvancedRadiusCoordinates,
                                      title: Text(
                                        _t(
                                          nl: 'Geavanceerd: coordinaten handmatig invullen',
                                          en: 'Advanced: enter coordinates manually',
                                          fr: 'Avance: saisir les coordonnees manuellement',
                                          es: 'Avanzado: introducir coordenadas manualmente',
                                        ),
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      onExpansionChanged: (expanded) {
                                        setDialogState(() {
                                          showAdvancedRadiusCoordinates =
                                              expanded;
                                        });
                                      },
                                      children: [
                                        _txt(
                                          zoneCenterLatCtrl,
                                          _t(
                                            nl: 'Breedtegraad',
                                            en: 'Latitude',
                                            fr: 'Latitude',
                                            es: 'Latitud',
                                          ),
                                        ),
                                        _txt(
                                          zoneCenterLngCtrl,
                                          _t(
                                            nl: 'Lengtegraad',
                                            en: 'Longitude',
                                            fr: 'Longitude',
                                            es: 'Longitud',
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (radiusError != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        radiusError!,
                                        style: const TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ] else ...[
                                    _txt(
                                      zoneValueCtrl,
                                      _t(
                                        nl: 'Zone waarde',
                                        en: 'Zone value',
                                        fr: 'Valeur de zone',
                                        es: 'Valor de zona',
                                      ),
                                    ),
                                    if (zoneError != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        zoneError!,
                                        style: const TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ],
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: tier,
                                    decoration: InputDecoration(
                                      labelText: _t(
                                        nl: 'Tier',
                                        en: 'Tier',
                                        fr: 'Niveau',
                                        es: 'Nivel',
                                      ),
                                    ),
                                    items: _airportFixedFareTiers
                                        .map(
                                          (value) => DropdownMenuItem<String>(
                                            value: value,
                                            child: Text(
                                              _airportTierLabel(value),
                                            ),
                                          ),
                                        )
                                        .toList(growable: false),
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setDialogState(() => tier = value);
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  _txt(
                                    priceCtrl,
                                    _t(
                                      nl: 'Prijs incl. btw',
                                      en: 'Price incl. VAT',
                                      fr: 'Prix TTC',
                                      es: 'Precio con IVA',
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: selectedCurrency,
                                    decoration: InputDecoration(
                                      labelText: _t(
                                        nl: 'Munt',
                                        en: 'Currency',
                                        fr: 'Devise',
                                        es: 'Moneda',
                                      ),
                                    ),
                                    items: _airportFixedFareCurrencies
                                        .map(
                                          (value) => DropdownMenuItem<String>(
                                            value: value,
                                            child: Text(value),
                                          ),
                                        )
                                        .toList(growable: false),
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setDialogState(() {
                                        selectedCurrency = value;
                                        priceError = null;
                                      });
                                    },
                                  ),
                                  if (priceError != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      priceError!,
                                      style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(),
                                  child: Text(
                                    _t(
                                      nl: 'Annuleren',
                                      en: 'Cancel',
                                      fr: 'Annuler',
                                      es: 'Cancelar',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () {
                                    FocusScope.of(dialogContext).unfocus();
                                    setDialogState(() {
                                      airportError = null;
                                      zoneError = null;
                                      radiusError = null;
                                      priceError = null;
                                    });

                                    final zoneValue = zoneValueCtrl.text.trim();
                                    final zoneLabel = zoneLabelCtrl.text.trim();
                                    final zoneCenterLat = double.tryParse(
                                      zoneCenterLatCtrl.text.trim().replaceAll(
                                        ',',
                                        '.',
                                      ),
                                    );
                                    final zoneCenterLng = double.tryParse(
                                      zoneCenterLngCtrl.text.trim().replaceAll(
                                        ',',
                                        '.',
                                      ),
                                    );
                                    final radiusKm = radiusPreset == 'custom'
                                        ? double.tryParse(
                                            radiusKmCtrl.text.trim().replaceAll(
                                              ',',
                                              '.',
                                            ),
                                          )
                                        : double.tryParse(radiusPreset);
                                    final price = double.tryParse(
                                      priceCtrl.text.trim().replaceAll(
                                        ',',
                                        '.',
                                      ),
                                    );
                                    if (selectedAirportIata.trim().isEmpty) {
                                      setDialogState(() {
                                        airportError = _t(
                                          nl: 'Kies een luchthaven.',
                                          en: 'Choose an airport.',
                                          fr: 'Choisissez un aeroport.',
                                          es: 'Elige un aeropuerto.',
                                        );
                                      });
                                      return;
                                    }
                                    if (zoneType != 'radius' &&
                                        zoneValue.isEmpty) {
                                      setDialogState(() {
                                        zoneError = _t(
                                          nl: 'Vul een zonewaarde in.',
                                          en: 'Enter a zone value.',
                                          fr: 'Saisissez une valeur de zone.',
                                          es: 'Introduce un valor de zona.',
                                        );
                                      });
                                      return;
                                    }
                                    if (zoneType == 'radius') {
                                      if (zoneLabel.isEmpty) {
                                        setDialogState(() {
                                          radiusError = _t(
                                            nl: 'Vul een locatiecentrum in.',
                                            en: 'Enter a centre location.',
                                            fr: 'Saisissez un centre de zone.',
                                            es: 'Introduce el centro de la zona.',
                                          );
                                        });
                                        return;
                                      }
                                      if (zoneCenterLat == null ||
                                          !zoneCenterLat.isFinite ||
                                          zoneCenterLat < -90 ||
                                          zoneCenterLat > 90 ||
                                          zoneCenterLng == null ||
                                          !zoneCenterLng.isFinite ||
                                          zoneCenterLng < -180 ||
                                          zoneCenterLng > 180) {
                                        setDialogState(() {
                                          showAdvancedRadiusCoordinates = true;
                                          radiusError = _t(
                                            nl: 'Vul geldige centrumcoördinaten in.',
                                            en: 'Enter valid centre coordinates.',
                                            fr: 'Saisissez des coordonnees valides du centre.',
                                            es: 'Introduce coordenadas validas del centro.',
                                          );
                                        });
                                        return;
                                      }
                                      if (radiusKm == null ||
                                          !radiusKm.isFinite ||
                                          radiusKm < 1 ||
                                          radiusKm > 100) {
                                        setDialogState(() {
                                          radiusError = _t(
                                            nl: 'Vul een geldige radius in (1-100 km).',
                                            en: 'Enter a valid radius (1-100 km).',
                                            fr: 'Saisissez un rayon valide (1-100 km).',
                                            es: 'Introduce un radio valido (1-100 km).',
                                          );
                                        });
                                        return;
                                      }
                                    }
                                    if (price == null ||
                                        !price.isFinite ||
                                        price <= 0) {
                                      setDialogState(() {
                                        priceError = _t(
                                          nl: 'Vul een geldige prijs in.',
                                          en: 'Enter a valid price.',
                                          fr: 'Saisissez un prix valide.',
                                          es: 'Introduce un precio valido.',
                                        );
                                      });
                                      return;
                                    }
                                    final selectedAirport =
                                        _airportCatalogByIata(
                                          selectedAirportIata,
                                        );
                                    final airportIata = selectedAirportIata
                                        .trim()
                                        .toUpperCase();
                                    final normalizedCurrency =
                                        _airportFixedFareCurrencies.contains(
                                          selectedCurrency,
                                        )
                                        ? selectedCurrency
                                        : 'EUR';
                                    final ruleId =
                                        _airportRuleText(
                                          existing?['rule_id'],
                                        ).isEmpty
                                        ? _nextAirportFixedFareRuleId(
                                            airportIata,
                                            direction,
                                          )
                                        : _airportRuleText(
                                            existing?['rule_id'],
                                          );
                                    Navigator.of(
                                      dialogContext,
                                    ).pop(<String, dynamic>{
                                      'rule_id': ruleId,
                                      'enabled': enabled,
                                      'priority': _airportRuleInt(
                                        existing?['priority'],
                                        fallback: 0,
                                      ),
                                      'airport_iata': airportIata,
                                      'direction': direction,
                                      'zone_type': zoneType,
                                      if (zoneType != 'radius')
                                        'zone_value': zoneValue,
                                      if (zoneType == 'radius')
                                        'zone_label': zoneLabel,
                                      if (zoneType == 'radius')
                                        'zone_center_lat': zoneCenterLat,
                                      if (zoneType == 'radius')
                                        'zone_center_lng': zoneCenterLng,
                                      if (zoneType == 'radius')
                                        'radius_km': radiusKm,
                                      'tier': tier,
                                      'price_incl_vat': price,
                                      'currency': normalizedCurrency,
                                      'airport_name': _airportRuleText(
                                        selectedAirport?['airport_name'],
                                      ),
                                      'airport_country': _airportRuleText(
                                        selectedAirport?['country_name'],
                                      ),
                                      'pax_min': _airportRuleInt(
                                        existing?['pax_min'],
                                        fallback: 1,
                                      ),
                                      'pax_max': _airportRuleInt(
                                        existing?['pax_max'],
                                        fallback: 99,
                                      ),
                                      'bags_max': _airportRuleInt(
                                        existing?['bags_max'],
                                        fallback: 99,
                                      ),
                                    });
                                  },
                                  child: Text(
                                    _t(
                                      nl: 'Toepassen',
                                      en: 'Apply',
                                      fr: 'Appliquer',
                                      es: 'Aplicar',
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    zoneValueCtrl.dispose();
    zoneLabelCtrl.dispose();
    zoneCenterLatCtrl.dispose();
    zoneCenterLngCtrl.dispose();
    radiusKmCtrl.dispose();
    priceCtrl.dispose();
    if (result == null) return;
    setState(() {
      _airportFixedFaresError = null;
      _airportFixedFaresStatus = null;
      if (index != null &&
          index >= 0 &&
          index < _airportFixedFareRules.length) {
        _airportFixedFareRules[index] = result;
      } else {
        _airportFixedFareRules.add(result);
      }
      _airportFixedFaresDirty = true;
    });
  }

  Widget _airportFixedFareCard() {
    return _collapsibleSettingsCard(
      id: 'airport_fixed_fares',
      icon: Icons.flight_takeoff_outlined,
      title: _t(
        nl: 'Luchthaven vaste tarieven',
        en: 'Airport fixed fares',
        fr: 'Tarifs fixes aÃ©roport',
        es: 'Tarifas fijas aeropuerto',
      ),
      subtitle: _t(
        nl: 'Bedrijfsregels per luchthaven',
        en: 'Company rules per airport',
        fr: 'RÃ¨gles entreprise par aÃ©roport',
        es: 'Reglas de empresa por aeropuerto',
      ),
      status: _airportFixedFaresSetupStatus(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_airportFixedFaresLoading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 10),
          ],
          if (_airportFixedFaresError != null) ...[
            _notice(_airportFixedFaresError!, isError: true),
            const SizedBox(height: 8),
          ],
          if (_airportFixedFaresStatus != null) ...[
            _notice(_airportFixedFaresStatus!),
            const SizedBox(height: 8),
          ],
          if ((_airportFixedFaresUpdatedAt ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${_t(nl: 'Laatst bijgewerkt', en: 'Last updated', fr: 'DerniÃ¨re mise Ã  jour', es: 'Ãšltima actualizaciÃ³n')}: ${_airportFixedFaresUpdatedAt ?? ''}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.64),
                  fontSize: 11,
                ),
              ),
            ),
          if (_airportFixedFareRules.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _t(
                  nl: 'Nog geen vaste luchthaventarieven ingesteld.',
                  en: 'No airport fixed fare rules configured yet.',
                  fr: 'Aucune rÃ¨gle de tarif fixe aÃ©roport configurÃ©e.',
                  es: 'AÃºn no hay reglas de tarifa fija de aeropuerto configuradas.',
                ),
                style: TextStyle(color: Colors.white.withOpacity(0.74)),
              ),
            ),
          ..._airportFixedFareRules.asMap().entries.map((entry) {
            final index = entry.key;
            final rule = entry.value;
            final airportIata = _airportRuleText(rule['airport_iata']);
            final airportName = _airportRuleText(rule['airport_name']);
            final direction = _airportDirectionLabel(
              _airportRuleText(rule['direction']),
            );
            final zoneType = _airportZoneTypeLabel(
              _airportRuleText(rule['zone_type']),
            );
            final zoneValue = _airportRuleText(rule['zone_value']);
            final isRadiusRule =
                _airportRuleText(rule['zone_type']).toLowerCase() == 'radius';
            final zoneLabel = _airportRuleText(rule['zone_label']);
            final radiusKm = _airportRulePrice(rule['radius_km']);
            final radiusLabel = radiusKm == null
                ? '?'
                : radiusKm.toStringAsFixed(radiusKm % 1 == 0 ? 0 : 1);
            final tier = _airportTierLabel(_airportRuleText(rule['tier']));
            final price = _airportRulePrice(rule['price_incl_vat']) ?? 0;
            final currency = _airportRuleText(
              rule['currency'],
              fallback: 'EUR',
            );
            final enabled = _airportRuleBool(rule['enabled'], fallback: true);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0F12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          airportName.isNotEmpty
                              ? '$airportName ($airportIata) - â‚¬ ${price.toStringAsFixed(2)} $currency'
                              : '$airportIata - â‚¬ ${price.toStringAsFixed(2)} $currency',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: enabled
                              ? const Color(0xFF12331F)
                              : const Color(0xFF3A1010),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          enabled
                              ? _t(
                                  nl: 'Actief',
                                  en: 'Active',
                                  fr: 'Actif',
                                  es: 'Activo',
                                )
                              : _t(
                                  nl: 'Inactief',
                                  en: 'Inactive',
                                  fr: 'Inactif',
                                  es: 'Inactivo',
                                ),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isRadiusRule
                        ? '$direction - $zoneType: $zoneLabel ($radiusLabel km) - $tier'
                        : '$direction - $zoneType: $zoneValue - $tier',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.74),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _airportFixedFaresSaving
                            ? null
                            : () => _editAirportFixedFareRule(index: index),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: Text(
                          _t(
                            nl: 'Bewerken',
                            en: 'Edit',
                            fr: 'Modifier',
                            es: 'Editar',
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _airportFixedFaresSaving
                            ? null
                            : () {
                                setState(() {
                                  _airportFixedFaresError = null;
                                  _airportFixedFaresStatus = null;
                                  _airportFixedFareRules.removeAt(index);
                                  _airportFixedFaresDirty = true;
                                });
                              },
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: Text(
                          _t(
                            nl: 'Verwijderen',
                            en: 'Delete',
                            fr: 'Supprimer',
                            es: 'Eliminar',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed:
                    (_airportFixedFaresLoading || _airportFixedFaresSaving)
                    ? null
                    : () => _editAirportFixedFareRule(),
                icon: const Icon(Icons.add),
                label: Text(
                  _t(
                    nl: 'Regel toevoegen',
                    en: 'Add rule',
                    fr: 'Ajouter une rÃ¨gle',
                    es: 'Agregar regla',
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed:
                    (_airportFixedFaresLoading || _airportFixedFaresSaving)
                    ? null
                    : () => _loadAirportFixedFareRules(showErrorSnack: true),
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
              OutlinedButton.icon(
                onPressed:
                    (_airportFixedFaresLoading || _airportFixedFaresSaving)
                    ? null
                    : _saveAirportFixedFareRules,
                icon: _airportFixedFaresSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _t(
                    nl: 'Regels opslaan',
                    en: 'Save rules',
                    fr: 'Enregistrer les rÃ¨gles',
                    es: 'Guardar reglas',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  ActiveVatConfig _activeVatConfig() {
    return resolveActiveVatConfig(
      settings: businessSettingsNotifier.value,
      taxProfile: localBackendTaxProfileNotifier.value,
    );
  }

  String _preparedPublicBookingUrl(String companyCode) {
    final safeCompanyCode = _normalizePublicCompanyCode(companyCode);
    final base = kPublicBookingBaseUrl.trim().isEmpty
        ? 'https://fluxidi.com'
        : kPublicBookingBaseUrl.trim();
    final encodedCompanyCode = Uri.encodeQueryComponent(safeCompanyCode);
    try {
      final uri = Uri.parse(base);
      final normalizedPath = uri.path.trim().isEmpty || uri.path == '/'
          ? '/book'
          : (uri.path.endsWith('/book') ? uri.path : '${uri.path}/book');
      final nextQuery = Map<String, String>.from(uri.queryParameters);
      nextQuery['company_code'] = safeCompanyCode;
      return uri
          .replace(path: normalizedPath, queryParameters: nextQuery)
          .toString();
    } catch (_) {
      return '$base/book?company_code=$encodedCompanyCode';
    }
  }

  Widget _txt(
    TextEditingController ctrl,
    String label, {
    ValueChanged<String>? onChanged,
    String? hint,
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
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38),
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
          es: 'Requiere atenciÃ³n',
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
          fr: 'BientÃ´t',
          es: 'PrÃ³ximamente',
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
    final publicCompanyCode = _activePublicCompanyCode();
    if (publicCompanyCode == null) return _SetupStatus.incomplete;
    final prepared = _preparedPublicBookingUrl(publicCompanyCode);
    if (_nonEmpty(prepared)) return _SetupStatus.complete;
    return _SetupStatus.attention;
  }

  String _publicLinkSetupSubtitle() {
    switch (_publicLinkStatus()) {
      case _SetupStatus.complete:
        return _t(
          nl: 'Klaar om te delen via link en QR',
          en: 'Ready to share via link and QR',
          fr: 'PrÃªt Ã  partager via lien et QR',
          es: 'Listo para compartir por enlace y QR',
        );
      case _SetupStatus.attention:
      case _SetupStatus.incomplete:
      case _SetupStatus.comingSoon:
        return _t(
          nl: 'Publieke code of link ontbreekt',
          en: 'Public code or link is missing',
          fr: 'Code public ou lien manquant',
          es: 'Falta el cÃ³digo pÃºblico o el enlace',
        );
    }
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
          es: 'Nombre, direcciÃ³n y contacto',
        ),
        icon: Icons.business_outlined,
        status: _detailsStatus(),
      ),
      _SetupItem(
        title: _t(
          nl: 'Facturatie & BTW',
          en: 'Billing & VAT',
          fr: 'Facturation et TVA',
          es: 'FacturaciÃ³n e IVA',
        ),
        subtitle: _t(
          nl: 'BTW, facturatie en IBAN',
          en: 'Tax, invoicing and IBAN',
          fr: 'TVA, facturation et IBAN',
          es: 'IVA, facturaciÃ³n e IBAN',
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
          fr: 'ParamÃ¨tres tarifaires',
          es: 'Ajustes de precio',
        ),
        subtitle: _t(
          nl: 'Basistarief en kernprijzen',
          en: 'Base fare and core prices',
          fr: 'Tarif de base et prix clÃ©s',
          es: 'Tarifa base y precios clave',
        ),
        icon: Icons.local_offer_outlined,
        status: _pricingStatus(),
      ),
      _SetupItem(
        title: _t(
          nl: 'Services & tiers',
          en: 'Services & tiers',
          fr: 'Services et catÃ©gories',
          es: 'Servicios y categorÃ­as',
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
          fr: 'Lien de rÃ©servation public',
          es: 'Enlace pÃºblico de reserva',
        ),
        subtitle: _publicLinkSetupSubtitle(),
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
              es: 'Progreso de configuraciÃ³n',
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
              fr: 'PrÃ©parez votre entreprise pour les rÃ©servations.',
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
                    fr: 'AperÃ§u des paramÃ¨tres',
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
                  '$completeCount/${items.length} ${_t(nl: 'voltooid', en: 'completed', fr: 'terminÃ©', es: 'completado')}',
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
                        fr: 'VÃ©rifiez les cartes ci-dessus et complÃ©tez les champs manquants dans les formulaires ci-dessous.',
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
                  fr: 'VÃ©rifier les Ã©lÃ©ments manquants',
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
                              nl: 'ID kopiÃ«ren',
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
            ValueListenableBuilder<ActiveCompanySession?>(
              valueListenable: activeCompanySessionNotifier,
              builder: (context, activeSession, __) {
                return _collapsibleSettingsCard(
                  id: 'public_booking_link',
                  icon: Icons.link_outlined,
                  title: _t(
                    nl: 'Publieke boekingslink',
                    en: 'Public booking link',
                    fr: 'Lien de rÃ©servation public',
                    es: 'Enlace pÃºblico de reserva',
                  ),
                  subtitle: _t(
                    nl: 'Web/QR-link voorbereiding',
                    en: 'Web/QR link preparation',
                    fr: 'PrÃ©paration lien web/QR',
                    es: 'PreparaciÃ³n de enlace web/QR',
                  ),
                  status: _publicLinkStatus(),
                  child: ValueListenableBuilder<CompanyProfile?>(
                    valueListenable: companyProfileNotifier,
                    builder: (context, profile, _) {
                      final publicCompanyCode = _activePublicCompanyCode(
                        session: activeSession,
                        profile: profile,
                      );
                      final hasPublicCompanyCode = publicCompanyCode != null;
                      final effectivePublicCompanyCode = hasPublicCompanyCode
                          ? publicCompanyCode
                          : '';
                      final publicBookingUrl = hasPublicCompanyCode
                          ? _preparedPublicBookingUrl(
                              effectivePublicCompanyCode,
                            )
                          : '';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!hasPublicCompanyCode) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.orangeAccent.withOpacity(0.45),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _t(
                                      nl: 'Verifieer uw bedrijf eerst om een publieke boekingslink te gebruiken.',
                                      en: 'Verify your company first to use a public booking link.',
                                      fr: 'VÃ©rifiez dâ€™abord votre entreprise pour utiliser un lien de rÃ©servation public.',
                                      es: 'Verifica primero tu empresa para usar un enlace pÃºblico de reserva.',
                                    ),
                                    style: const TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _t(
                                      nl: 'Geen publieke Fluxidi-code gevonden.',
                                      en: 'No public Fluxidi code found.',
                                      fr: 'Aucun code Fluxidi public trouvÃ©.',
                                      es: 'No se encontrÃ³ ningÃºn cÃ³digo pÃºblico de Fluxidi.',
                                    ),
                                    style: TextStyle(
                                      color: Colors.orangeAccent.withOpacity(
                                        0.82,
                                      ),
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            Text(
                              _t(
                                nl: 'Deel deze link of QR-code met klanten zodat zij rechtstreeks kunnen boeken.',
                                en: 'Share this link or QR code with customers so they can book directly.',
                                fr: 'Partagez ce lien ou ce code QR avec les clients afin quâ€™ils puissent rÃ©server directement.',
                                es: 'Comparte este enlace o cÃ³digo QR con los clientes para que puedan reservar directamente.',
                              ),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.78),
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0B0B0B),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(
                                    0xFFD4AF4A,
                                  ).withOpacity(0.45),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _t(
                                      nl: 'Publieke bedrijfscode',
                                      en: 'Public company code',
                                      fr: 'Code entreprise public',
                                      es: 'CÃ³digo pÃºblico de empresa',
                                    ),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.72),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: SelectableText(
                                          effectivePublicCompanyCode,
                                          style: const TextStyle(
                                            color: Color(0xFFF0C85D),
                                            fontFamily: 'monospace',
                                            fontSize: 13.2,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton.icon(
                                        onPressed: () async {
                                          await Clipboard.setData(
                                            ClipboardData(
                                              text: effectivePublicCompanyCode,
                                            ),
                                          );
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                _t(
                                                  nl: 'Publieke bedrijfscode gekopieerd',
                                                  en: 'Public company code copied',
                                                  fr: 'Code entreprise public copiÃ©',
                                                  es: 'CÃ³digo pÃºblico de empresa copiado',
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.copy_outlined,
                                          size: 16,
                                        ),
                                        label: Text(
                                          _t(
                                            nl: 'Kopieer code',
                                            en: 'Copy code',
                                            fr: 'Copier le code',
                                            es: 'Copiar cÃ³digo',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0B0B0B),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.16),
                                ),
                              ),
                              child: SelectableText(
                                publicBookingUrl,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'monospace',
                                  fontSize: 12.2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: QrImageView(
                                  data: publicBookingUrl,
                                  version: QrVersions.auto,
                                  size: 180,
                                  backgroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
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
                                            fr: 'Lien de rÃ©servation public copiÃ©',
                                            es: 'Enlace pÃºblico de reserva copiado',
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.copy_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    _t(
                                      nl: 'KopiÃ«ren',
                                      en: 'Copy',
                                      fr: 'Copier',
                                      es: 'Copiar',
                                    ),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    await Share.share(publicBookingUrl);
                                  },
                                  icon: const Icon(
                                    Icons.share_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    _t(
                                      nl: 'Delen',
                                      en: 'Share',
                                      fr: 'Partager',
                                      es: 'Compartir',
                                    ),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    try {
                                      final uri = Uri.parse(publicBookingUrl);
                                      final launched = await launchUrl(
                                        uri,
                                        mode: LaunchMode.externalApplication,
                                      );
                                      if (!launched && context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              _t(
                                                nl: 'Publieke boekingslink kon niet geopend worden.',
                                                en: 'Could not open public booking link.',
                                                fr: 'Impossible dâ€™ouvrir le lien de rÃ©servation public.',
                                                es: 'No se pudo abrir el enlace pÃºblico de reserva.',
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                    } catch (_) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            _t(
                                              nl: 'Publieke boekingslink kon niet geopend worden.',
                                              en: 'Could not open public booking link.',
                                              fr: 'Impossible dâ€™ouvrir le lien de rÃ©servation public.',
                                              es: 'No se pudo abrir el enlace pÃºblico de reserva.',
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.open_in_new_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    _t(
                                      nl: 'Open link',
                                      en: 'Open link',
                                      fr: 'Ouvrir le lien',
                                      es: 'Abrir enlace',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _t(
                                nl: 'De publieke boekingspagina wordt verder gekoppeld aan deze Fluxidi-code.',
                                en: 'The public booking page will be further connected to this Fluxidi code.',
                                fr: 'La page de rÃ©servation publique sera davantage liÃ©e Ã  ce code Fluxidi.',
                                es: 'La pÃ¡gina pÃºblica de reserva se vincularÃ¡ mÃ¡s a este cÃ³digo Fluxidi.',
                              ),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.66),
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                );
              },
            ),
            _googleCalendarCard(),
            _collapsibleSettingsCard(
              id: 'official_company_details',
              icon: Icons.business_outlined,
              title: _t(
                nl: 'OfficiÃ«le bedrijfsgegevens',
                en: 'Official company details',
                fr: 'Informations officielles de l entreprise',
                es: 'Datos oficiales de la empresa',
              ),
              subtitle: _t(
                nl: 'Juridische en factuurgegevens',
                en: 'Legal and invoice details',
                fr: 'DonnÃ©es juridiques et de facturation',
                es: 'Datos legales y de facturaciÃ³n',
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
                      es: 'DirecciÃ³n',
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
                      fr: 'TÃ©lÃ©phone',
                      es: 'TelÃ©fono',
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
                            nl: 'Slaat alleen de officiÃ«le bedrijfsgegevens op.',
                            en: 'Saves only the official company details.',
                            fr: 'Enregistre uniquement les informations officielles de lâ€™entreprise.',
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
                fr: 'Profil TVA et mode dâ€™affichage',
                es: 'Perfil de IVA y modo de visualizaciÃ³n',
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
                            fr: 'Enregistre uniquement les paramÃ¨tres TVA.',
                            es: 'Guarda solo la configuraciÃ³n de IVA.',
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
              id: 'public_partner_profile',
              icon: Icons.public_outlined,
              title: _t(
                nl: 'Publiek partnerprofiel',
                en: 'Public partner profile',
                fr: 'Profil partenaire public',
                es: 'Perfil pÃºblico de socio',
              ),
              subtitle: _t(
                nl: 'Publiceer veilige profielgegevens voor klanten',
                en: 'Publish safe profile data for customers',
                fr: 'Publier des donnees de profil securisees',
                es: 'Publicar datos de perfil seguros',
              ),
              status: _publicPartnerProfileError != null
                  ? _SetupStatus.attention
                  : (_isPublicPartnerProfilePublished() ||
                            _publicPartnerProfileStatus != null
                        ? _SetupStatus.complete
                        : _SetupStatus.incomplete),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(
                      nl: 'Publiceer veilige bedrijfsinformatie zodat klanten je kunnen vinden via Taxiâ€™s in de buurt.',
                      en: 'Publish safe company information so customers can find you through Nearby taxis.',
                      fr: 'Publiez des informations publiques sÃ©curisÃ©es afin que les clients puissent vous trouver.',
                      es: 'Publica informaciÃ³n segura de la empresa para que los clientes puedan encontrarte.',
                    ),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _t(
                      nl: 'Upload een logo of coverfoto. Fluxidi maakt automatisch een publieke veilige link.',
                      en: 'Upload a logo or cover photo. Fluxidi automatically creates a safe public link.',
                      fr: 'TÃ©lÃ©versez un logo ou une photo de couverture. Fluxidi crÃ©e automatiquement un lien public sÃ©curisÃ©.',
                      es: 'Sube un logo o una foto de portada. Fluxidi crea automÃ¡ticamente un enlace pÃºblico seguro.',
                    ),
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _txt(
                    _publicServedPostcodesCtrl,
                    _t(
                      nl: 'Bediende postcodes',
                      en: 'Served postcodes',
                      fr: 'Codes postaux desservis',
                      es: 'CÃ³digos postales atendidos',
                    ),
                    hint: _t(
                      nl: 'Bijv. 9688, 9680, 9600, 9700',
                      en: 'E.g. 9688, 9680, 9600, 9700',
                      fr: 'Ex. 9688, 9680, 9600, 9700',
                      es: 'Ej. 9688, 9680, 9600, 9700',
                    ),
                    maxLines: 2,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t(
                      nl: 'Gebruik komma, spatie of nieuwe lijn tussen postcodes.',
                      en: 'Use commas, spaces, or new lines between postcodes.',
                      fr: 'Utilisez des virgules, espaces ou retours Ã  la ligne entre les codes postaux.',
                      es: 'Usa comas, espacios o saltos de lÃ­nea entre cÃ³digos postales.',
                    ),
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _t(
                      nl: 'Publieke dekking voor Taxiâ€™s in de buurt (optioneel).',
                      en: 'Public coverage for Taxis nearby (optional).',
                      fr: 'Couverture publique pour Taxis Ã  proximitÃ© (optionnel).',
                      es: 'Cobertura pÃºblica para Taxis cercanos (opcional).',
                    ),
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _useCurrentLocationAsBusinessLocation,
                      icon: const Icon(Icons.my_location_outlined),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE5B641),
                        side: BorderSide(
                          color: const Color(0xFFE5B641).withOpacity(0.42),
                        ),
                        backgroundColor: const Color(0xFF0B0B0B),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      label: Text(
                        _t(
                          nl: 'Gebruik huidige locatie als bedrijfslocatie',
                          en: 'Use current location as business location',
                          fr: 'Utiliser ma position actuelle comme adresse professionnelle',
                          es: 'Usar mi ubicaciÃ³n actual como ubicaciÃ³n de empresa',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B0B0B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.14)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hasPublicCoverageLocationSet()
                              ? _t(
                                  nl: 'Bedrijfslocatie ingesteld via GPS',
                                  en: 'Business location set via GPS',
                                  fr: 'Emplacement professionnel dÃ©fini via GPS',
                                  es: 'UbicaciÃ³n de empresa configurada por GPS',
                                )
                              : _t(
                                  nl: 'Nog geen bedrijfslocatie ingesteld.',
                                  en: 'No business location set yet.',
                                  fr: 'Aucun emplacement professionnel dÃ©fini.',
                                  es: 'AÃºn no se ha configurado la ubicaciÃ³n de empresa.',
                                ),
                          style: TextStyle(
                            color: _hasPublicCoverageLocationSet()
                                ? const Color(0xFF34D29A)
                                : Colors.white70,
                            fontSize: 12.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_hasPublicCoverageLocationSet()) ...[
                          const SizedBox(height: 4),
                          Text(
                            _publicCoverageCoordsLabel(),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 10.8,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _txt(
                    _publicServiceRadiusKmCtrl,
                    _t(
                      nl: 'Service radius (km)',
                      en: 'Service radius (km)',
                      fr: 'Rayon de service (km)',
                      es: 'Radio de servicio (km)',
                    ),
                    hint: _t(
                      nl: '1 t/m 100',
                      en: '1 to 100',
                      fr: '1 Ã  100',
                      es: '1 a 100',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _t(
                      nl: 'Publieke services en profielzichtbaarheid',
                      en: 'Public services and profile visibility',
                      fr: 'Services publics et visibilitÃ© du profil',
                      es: 'Servicios pÃºblicos y visibilidad del perfil',
                    ),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _t(
                      nl: 'Dit is los van Service setup. Service setup stuurt calculator/pricing; deze toggles sturen publiek profiel en boekings-CTAâ€™s.',
                      en: 'This is separate from Service setup. Service setup drives calculator/pricing; these toggles drive public profile and booking CTAs.',
                      fr: 'Ceci est sÃ©parÃ© de la configuration des services. Cette section contrÃ´le le profil public et les CTA de rÃ©servation.',
                      es: 'Esto es independiente de la configuraciÃ³n de servicios. Estos controles afectan el perfil pÃºblico y los CTA de reserva.',
                    ),
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _publicServiceCatalog
                        .map((id) {
                          final selected = _publicServiceIds.contains(id);
                          return FilterChip(
                            label: Text(_publicServiceLabel(id)),
                            selected: selected,
                            onSelected: (value) {
                              setState(() {
                                _publicServicesConfigured = true;
                                if (value) {
                                  _publicServiceIds.add(id);
                                } else {
                                  _publicServiceIds.remove(id);
                                }
                              });
                            },
                            selectedColor: const Color(
                              0xFFE5B641,
                            ).withOpacity(0.22),
                            checkmarkColor: const Color(0xFFE5B641),
                            backgroundColor: const Color(0xFF111315),
                            side: BorderSide(
                              color: selected
                                  ? const Color(0xFFE5B641).withOpacity(0.75)
                                  : Colors.white.withOpacity(0.18),
                            ),
                            labelStyle: TextStyle(
                              color: selected
                                  ? const Color(0xFFFFF2CC)
                                  : Colors.white.withOpacity(0.86),
                              fontWeight: FontWeight.w600,
                              fontSize: 11.6,
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _t(
                      nl: 'Betaalopties zichtbaar voor klanten',
                      en: 'Payment options visible to customers',
                      fr: 'Moyens de paiement visibles par les clients',
                      es: 'Opciones de pago visibles para clientes',
                    ),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _publicPaymentOptionCatalog
                        .map((id) {
                          final selected = _publicPaymentOptionIds.contains(id);
                          return FilterChip(
                            label: Text(_publicPaymentOptionLabel(id)),
                            selected: selected,
                            onSelected: (value) {
                              setState(() {
                                if (value) {
                                  _publicPaymentOptionIds.add(id);
                                } else {
                                  _publicPaymentOptionIds.remove(id);
                                }
                              });
                            },
                            selectedColor: const Color(
                              0xFFE5B641,
                            ).withOpacity(0.22),
                            checkmarkColor: const Color(0xFFE5B641),
                            backgroundColor: const Color(0xFF111315),
                            side: BorderSide(
                              color: selected
                                  ? const Color(0xFFE5B641).withOpacity(0.75)
                                  : Colors.white.withOpacity(0.18),
                            ),
                            labelStyle: TextStyle(
                              color: selected
                                  ? const Color(0xFFFFF2CC)
                                  : Colors.white.withOpacity(0.86),
                              fontWeight: FontWeight.w600,
                              fontSize: 11.6,
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 10),
                  _publicMediaPreview(),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              (_publicLogoUploading ||
                                  _publicHeroUploading ||
                                  _publicPartnerProfilePublishing)
                              ? null
                              : () => _uploadPublicCompanyMedia(
                                  mediaType: 'company_logo',
                                ),
                          icon: _publicLogoUploading
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.upload_file_outlined),
                          label: Text(
                            _isPublicHttpsUrl(_publicLogoUrlCtrl.text)
                                ? _t(
                                    nl: 'Vervang logo',
                                    en: 'Replace logo',
                                    fr: 'Remplacer le logo',
                                    es: 'Reemplazar logo',
                                  )
                                : _t(
                                    nl: 'Upload publiek logo',
                                    en: 'Upload public logo',
                                    fr: 'TÃ©lÃ©verser le logo public',
                                    es: 'Subir logo pÃºblico',
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              (_publicLogoUploading ||
                                  _publicHeroUploading ||
                                  _publicPartnerProfilePublishing)
                              ? null
                              : () => _uploadPublicCompanyMedia(
                                  mediaType: 'company_hero',
                                ),
                          icon: _publicHeroUploading
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.image_outlined),
                          label: Text(
                            _isPublicHttpsUrl(_publicHeroPhotoUrlCtrl.text)
                                ? _t(
                                    nl: 'Vervang coverfoto',
                                    en: 'Replace cover photo',
                                    fr: 'Remplacer la photo de couverture',
                                    es: 'Reemplazar foto de portada',
                                  )
                                : _t(
                                    nl: 'Upload publieke coverfoto',
                                    en: 'Upload public cover photo',
                                    fr: 'TÃ©lÃ©verser la couverture publique',
                                    es: 'Subir portada pÃºblica',
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    initiallyExpanded: _showAdvancedPublicMediaUrls,
                    onExpansionChanged: (v) {
                      setState(() => _showAdvancedPublicMediaUrls = v);
                    },
                    title: Text(
                      _t(
                        nl: 'Geavanceerd: handmatige publieke URL\'s (fallback)',
                        en: 'Advanced: manual public URLs (fallback)',
                        fr: 'AvancÃ© : URLs publiques manuelles (secours)',
                        es: 'Avanzado: URLs pÃºblicas manuales (respaldo)',
                      ),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.3,
                      ),
                    ),
                    children: [
                      _txt(
                        _publicLogoUrlCtrl,
                        _t(
                          nl: 'Publieke logo-URL',
                          en: 'Public logo URL',
                          fr: 'URL du logo public',
                          es: 'URL del logo pÃºblico',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      _txt(
                        _publicHeroPhotoUrlCtrl,
                        _t(
                          nl: 'Publieke coverfoto-URL',
                          en: 'Public cover photo URL',
                          fr: 'URL de la photo de couverture publique',
                          es: 'URL de la foto de portada pÃºblica',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      if (_publicLogoUrlCtrl.text.trim().isNotEmpty &&
                          !_isPublicHttpsUrl(_publicLogoUrlCtrl.text)) ...[
                        Text(
                          _t(
                            nl: 'Waarschuwing: logo-URL moet met https:// starten om gepubliceerd te worden.',
                            en: 'Warning: logo URL must start with https:// to be published.',
                            fr: 'Avertissement : lâ€™URL du logo doit commencer par https:// pour Ãªtre publiÃ©e.',
                            es: 'Advertencia: la URL del logo debe empezar con https:// para publicarse.',
                          ),
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (_publicHeroPhotoUrlCtrl.text.trim().isNotEmpty &&
                          !_isPublicHttpsUrl(_publicHeroPhotoUrlCtrl.text)) ...[
                        Text(
                          _t(
                            nl: 'Waarschuwing: coverfoto-URL moet met https:// starten om gepubliceerd te worden.',
                            en: 'Warning: cover photo URL must start with https:// to be published.',
                            fr: 'Avertissement : lâ€™URL de couverture doit commencer par https:// pour Ãªtre publiÃ©e.',
                            es: 'Advertencia: la URL de portada debe empezar con https:// para publicarse.',
                          ),
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _publicPartnerProfilePublishing
                        ? null
                        : _publishPublicPartnerProfile,
                    icon: _publicPartnerProfilePublishing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.publish_outlined),
                    label: Text(
                      _t(
                        nl: 'Publiek profiel publiceren',
                        en: 'Publish public profile',
                        fr: 'Publier le profil public',
                        es: 'Publicar perfil pÃºblico',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t(
                      nl: 'Gebruik alleen publieke HTTPS-links. Lokale fotoâ€™s worden niet gepubliceerd.',
                      en: 'Use public HTTPS links only. Local photos are not published.',
                      fr: 'Les photos locales ne sont pas encore publiÃ©es. Seules les images HTTPS publiques sont incluses.',
                      es: 'Las fotos locales aÃºn no se publican. Solo se incluyen imÃ¡genes HTTPS pÃºblicas.',
                    ),
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  if (_publicPartnerProfileStatus != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _publicPartnerProfileStatus!,
                      style: const TextStyle(
                        color: Color(0xFF34D29A),
                        fontSize: 11.8,
                      ),
                    ),
                  ],
                  if (_isPublicPartnerProfilePublished() &&
                      _publicPartnerProfilePublishedAt.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _t(
                        nl: 'Laatst gepubliceerd op: ${_publicPartnerProfilePublishedAt.trim()}',
                        en: 'Last published at: ${_publicPartnerProfilePublishedAt.trim()}',
                        fr: 'Derniere publication: ${_publicPartnerProfilePublishedAt.trim()}',
                        es: 'Ultima publicacion: ${_publicPartnerProfilePublishedAt.trim()}',
                      ),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10.8,
                      ),
                    ),
                  ],
                  if (_publicPartnerProfileError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _publicPartnerProfileError!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 11.8,
                      ),
                    ),
                  ],
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
                      fr: 'TÃ©lÃ©phone support',
                      es: 'TelÃ©fono de soporte',
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
                        child: Text('FranÃ§ais'),
                      ),
                      DropdownMenuItem(
                        value: AppLanguage.es,
                        child: Text('EspaÃ±ol'),
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
                fr: 'Services, catÃ©gories et options',
                es: 'Servicios, categorÃ­as y opciones',
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
                fr: 'Tarifs de base et supplÃ©ments',
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
                          '${_t(nl: 'BTW wordt beheerd via BTW-instellingen hierboven.', en: 'VAT is managed in the VAT settings above.', fr: 'La TVA est gÃ©rÃ©e dans les paramÃ¨tres TVA ci-dessus.', es: 'El IVA se gestiona en los ajustes de IVA de arriba.')} (${vatPercent % 1 == 0 ? vatPercent.toStringAsFixed(0) : vatPercent.toStringAsFixed(2)}%, $vatModeLabel)',
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
            _airportFixedFareCard(),
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: _saveAllBusy ? null : _save,
              icon: _saveAllBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(
                _t(
                  nl: 'Alles opslaan en publiceren',
                  en: 'Save and publish everything',
                  fr: 'Tout enregistrer et publier',
                  es: 'Guardar y publicar todo',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
