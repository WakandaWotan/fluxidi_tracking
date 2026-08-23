import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/airport/airport_catalog.generated.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/branding/company_logo_ref.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_page.dart';
import 'package:fluxidi_tracking/business_settings_sticky_save.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/chiron_company_connection_config.dart';
import 'package:fluxidi_tracking/company/billit_customer_connect_gate.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_entry.dart';
import 'package:fluxidi_tracking/limousine/limousine_dimensions.dart';
import 'package:fluxidi_tracking/limousine/limousine_marketplace_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_offer_card.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_service_persist.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_requests_nav.dart';
import 'package:fluxidi_tracking/limousine/limousine_service_capability.dart';
import 'package:fluxidi_tracking/limousine/limousine_state_composition.dart';
import 'package:fluxidi_tracking/limousine/limousine_taxi_qr_isolation.dart';
import 'package:fluxidi_tracking/vehicle_gallery_contract.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/widgets/chiron_environment_status_labels.dart';
import 'package:fluxidi_tracking/widgets/chiron_self_service_wizard.dart';
import 'package:fluxidi_tracking/payment/mollie_capability_status.dart';
import 'package:fluxidi_tracking/payment/mollie_terminal_link_copy.dart';
import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';
import 'package:fluxidi_tracking/payment/payment_method_logo.dart';
import 'package:fluxidi_tracking/payment/payment_method_resolver.dart';
import 'package:fluxidi_tracking/pricing/pricing_setup_completeness.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

enum _SetupStatus {
  complete,
  attention,
  incomplete,
  optional,
  activationPending,
  comingSoon,
}

/// Deep-link target for opening a specific settings section from external
/// flows (e.g. Chiron readiness actions). Does not affect step-mode wizard
/// navigation, which continues to use [BusinessSettingsPage.initialFocus].
enum BusinessSettingsInitialSection { officialCompanyDetails, vatSettings }

extension BusinessSettingsInitialSectionId on BusinessSettingsInitialSection {
  String get sectionId {
    switch (this) {
      case BusinessSettingsInitialSection.officialCompanyDetails:
        return 'official_company_details';
      case BusinessSettingsInitialSection.vatSettings:
        return 'vat_settings';
    }
  }
}

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
  const BusinessSettingsPage({
    super.key,
    this.initialFocus,
    this.initialSection,
    this.stepMode = false,
    this.onStepSaved,
    this.stepTitle,
    this.stepSubtitle,
    this.stepIndex,
    this.stepTotal,
    this.onSkipStep,
    this.skipStepLabel,
    this.onExitWizard,
    this.exitWizardLabel,
  });

  /// When [stepMode] is true and [initialFocus] matches one of the focusable
  /// section ids ([_kStepFocusableSectionIds]), the page renders ONLY that
  /// section, opens it automatically, and replaces the global "Save and
  /// publish everything" button with a localized "Save and continue" that
  /// calls the existing [_BusinessSettingsPageState._save] orchestrator and
  /// then [onStepSaved]. When [stepMode] is false (default), behavior is
  /// byte-identical to the pre-existing single-page settings cockpit so all
  /// existing call sites (`const BusinessSettingsPage()`) keep working.
  final String? initialFocus;

  /// When set in normal (non-step) mode, opens the matching settings section,
  /// scrolls it into view after the first frame, and briefly highlights it.
  final BusinessSettingsInitialSection? initialSection;

  /// See [initialFocus]. Default `false` preserves existing behavior. When
  /// `true` and [initialFocus] is unknown/null, the page gracefully falls
  /// back to the normal full cockpit so callers cannot accidentally open a
  /// blank screen.
  final bool stepMode;

  /// Invoked after [_BusinessSettingsPageState._save] returns successfully
  /// in step mode. The wizard orchestrator typically uses this to advance
  /// to the next step. Has no effect outside [stepMode].
  final VoidCallback? onStepSaved;

  /// Optional pre-localized chrome shown when active step mode is on:
  /// [stepTitle] replaces the AppBar title, [stepSubtitle] is rendered as
  /// supporting copy in the AppBar progress strip, [stepIndex]/[stepTotal]
  /// drive a "Stap X van Y" label and a thin LinearProgressIndicator, and
  /// [onSkipStep] (if non-null) renders a leading-side "Later instellen"
  /// action so the wizard host can let the user defer setup. All five
  /// fields default to `null` and have no effect outside step mode, so
  /// existing `const BusinessSettingsPage()` call sites are unaffected.
  final String? stepTitle;
  final String? stepSubtitle;
  final int? stepIndex;
  final int? stepTotal;
  final VoidCallback? onSkipStep;

  /// Optional override for the AppBar per-step skip-action label in
  /// active step mode. Defaults to `null` → the localized
  /// "Deze stap overslaan / Skip this step" label is used so users
  /// cannot accidentally abandon the whole wizard by tapping the
  /// top-right action. Has no effect outside step mode.
  final String? skipStepLabel;

  /// Optional whole-wizard exit callback in active step mode. When
  /// non-null, the AppBar renders a separate "more options" overflow
  /// menu (3-dot icon) whose single item invokes this callback. Use
  /// this for "Finish setup later" — distinct from [onSkipStep], which
  /// only advances one step. Has no effect outside step mode.
  final VoidCallback? onExitWizard;

  /// Optional override for the overflow menu item label that triggers
  /// [onExitWizard]. Defaults to localized "Setup later afmaken /
  /// Finish setup later". Has no effect outside step mode.
  final String? exitWizardLabel;

  @override
  State<BusinessSettingsPage> createState() => _BusinessSettingsPageState();
}

/// Section ids that may be rendered in isolation via
/// [BusinessSettingsPage.initialFocus] when [BusinessSettingsPage.stepMode]
/// is true. Includes the first-run wizard steps (company, VAT, services,
/// pricing, payments, branding, booking link) plus optional integrations
/// (Mollie terminals, Google Calendar, Airport fixed fares, Chiron
/// connection — all skippable, all reuse existing settings cards, none
/// blocks reaching BusinessHomePage). Other settings sections (cancellation
/// policy, public partner profile, local company) remain reachable only
/// via the full settings page.
const Set<String> _kStepFocusableSectionIds = <String>{
  'limousine_offers_pricing',
  'official_company_details',
  'vat_settings',
  'service_setup',
  'pricing_engine',
  'payment_ownership',
  'mollie_terminal_payments',
  'billit_peppol',
  'branding_support',
  'google_calendar',
  'airport_fixed_fares',
  'chiron_connection',
  'public_booking_link',
};

class _BusinessSettingsPageState extends State<BusinessSettingsPage> {
  static const List<String> _publicServiceCatalog = <String>[
    'taxi_vvb',
    'airport_transfer',
    'business_rides',
    'event_mobility',
    'hotel_bnb_pickup',
    'online_payments',
    kLimousinePublicServiceId,
  ];
  static const List<String> _publicPaymentOptionCatalog = <String>[
    'cash',
    'qr_code',
    'bancontact',
    'kbc_cbc',
    'belfius',
    'payconiq_wero',
    'ideal',
    'cartes_bancaires',
    'bizum',
    'card_payment',
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
  final _cancellationTaxiCutoffCtrl = TextEditingController();
  final _cancellationAirportCutoffCtrl = TextEditingController();
  final _cancellationBusinessCutoffCtrl = TextEditingController();
  final _driverEnRouteEtaCutoffCtrl = TextEditingController();
  final _driverEnRouteDistanceCutoffCtrl = TextEditingController();
  final _driverLocationFreshnessCtrl = TextEditingController();
  final _driverHandoffBufferCtrl = TextEditingController();

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
  bool _cancellationPolicyLoading = false;
  bool _cancellationPolicySaving = false;
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
  String? _cancellationPolicyStatus;
  String? _cancellationPolicyError;
  String _publicPartnerProfilePublishedAt = '';
  String _publicPartnerProfilePublishStatus = '';
  bool _allowCustomerOnlineCancellation = true;
  String _paidBookingCancellationMode = 'review_required';
  bool _blockWhenDriverEnRoute = false;
  String? _googleCalendarStatusError;
  Map<String, dynamic>? _googleCalendarStatus;
  bool _chironEnabled = ChironCompanyConnectionDefaults.chironEnabled;
  String _chironEnvironment = ChironCompanyConnectionDefaults.chironEnvironment;
  String _chironConnectionStatus =
      ChironCompanyConnectionDefaults.chironConnectionStatus;
  String _chironRegionScope = ChironCompanyConnectionDefaults.chironRegionScope;
  bool _chironProductionEnabled =
      ChironCompanyConnectionDefaults.chironProductionEnabled;
  bool _chironConnectionLoading = false;
  bool _chironConnectionSaving = false;
  bool _chironBackendConfirmed = false;
  String? _chironConnectionStatusError;
  bool _mollieConnectLoading = false;
  bool _mollieConnectStartLoading = false;
  bool _mollieConnectDisconnectLoading = false;
  bool _mollieTerminalsLoading = false;
  bool _mollieTerminalsSyncLoading = false;
  String? _mollieTerminalLinkBusyId;
  String? _mollieConnectStatusError;
  Map<String, dynamic>? _mollieConnectStatus;
  String? _mollieTerminalsError;
  Map<String, dynamic>? _mollieTerminalsSnapshot;
  bool _billitLoading = false;
  bool _billitStartLoading = false;
  bool _billitDisconnectLoading = false;
  String? _billitStatusError;
  Map<String, dynamic>? _billitStatus;
  // Patch B10a: company Billit auto-create setting (default OFF, sandbox-only).
  bool _billitAutoCreateEnabled = false;
  bool _billitAutoCreateLoading = false;
  bool _billitAutoCreateSaving = false;
  bool _billitAutoCreateLoaded = false;
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
  String _paymentOwnerMode = 'fluxidi_central_demo';
  bool _paymentDemoMode = true;
  bool _mollieConnected = false;
  final Set<String> _expandedSections = <String>{};
  final ScrollController _settingsScrollController = ScrollController();
  final Map<String, GlobalKey> _sectionAnchorKeys = <String, GlobalKey>{
    'official_company_details': GlobalKey(),
    'billit_peppol': GlobalKey(),
  };
  String? _highlightedSectionId;
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

  // LIMOUSINE-MARKETPLACE-P2B2 — limousine offers used by the public preview.
  bool _limousineSectionEnabled = false;
  bool _limousinePublicAvailable = false;
  bool _limousineDiscoveryListable = false;
  Map<String, String> _limousinePublicTitle = const <String, String>{};
  Map<String, String> _limousinePublicDescription = const <String, String>{};
  List<Map<String, dynamic>> _limousineOffers = <Map<String, dynamic>>[];
  LimousineOffersEditorSnapshot _limousineOffersConfirmed =
      const LimousineOffersEditorSnapshot(
        enabled: false,
        offers: <Map<String, dynamic>>[],
      );

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
  BusinessThemePalette get _palette =>
      paletteForBusinessTheme(businessThemeNotifier.value);
  bool get _isDark => _palette.isDark;
  bool get _isCorporateBlue =>
      businessThemeNotifier.value == BusinessThemeVariant.corporateBlue;
  bool get _isCleanProfessional =>
      businessThemeNotifier.value == BusinessThemeVariant.cleanProfessional;
  Color get _pageBg => _palette.background;
  Color get _panelBg => _palette.surface;
  Color get _subPanelBg => _palette.surfaceAlt;
  Color get _subSurfaceBg => _subPanelBg;
  Color get _accent => _palette.accent;
  Color get _textPrimary => _palette.textPrimary;
  Color get _textSecondary => _palette.textSecondary;
  Color get _textMuted => _palette.textMuted;
  Color get _textOnAccent => _palette.textOnAccent;
  Color get _border => _palette.border;
  Color get _success => _palette.success;
  Color get _danger => _palette.danger;
  Color get _shadow => _palette.shadow;
  Color get _inputFill =>
      businessThemeNotifier.value == BusinessThemeVariant.brandSignatureGold
      ? _palette.surfaceAlt
      : _isDark
      ? (_isCorporateBlue ? const Color(0xFF0F1A2F) : const Color(0xFF0B0B0B))
      : const Color(0xFFF7F9FC);
  Color get _inputBorderColor =>
      _border.withOpacity(_isDark ? (_isCorporateBlue ? 0.72 : 0.55) : 0.92);
  Color get _inputFocusColor =>
      _isCleanProfessional ? _accent : _accent.withOpacity(0.92);

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
      case AppLanguage.de:
        return en;
    }
  }

  /// LIMOUSINE-MARKETPLACE-P2A: read-only readiness summary using the typed
  /// domain resolver (no duplicated eligibility logic in the widget). Shows the
  /// authoritative six-state result; missing/stale state fails closed. No
  /// subscription-private detail (price/plan) is shown.
  Map<String, dynamic> _limousineReadinessCandidate({
    required String subscriptionStatus,
    required bool entitled,
  }) {
    final services = _mappedPublicServiceIds();
    final vehicles = <Map<String, dynamic>>[];
    for (final v in vehiclesNotifier.value) {
      if (!v.isActive) continue;
      final category = v.serviceCategory.trim().toLowerCase();
      final classId = v.serviceClassId.trim();
      if (category != 'limousine') continue;
      if (classId.isEmpty || isForbiddenClassInferenceToken(classId)) continue;
      vehicles.add(<String, dynamic>{
        'service_category': 'limousine',
        'service_class': classId,
        'category': 'limousine',
        'is_active': true,
      });
    }
    return <String, dynamic>{
      'subscription_status': subscriptionStatus,
      'features': <String, dynamic>{'limousine': entitled},
      'is_active': true,
      'services': services,
      'profile_enabled': _isPublicPartnerProfilePublished(),
      'published_at': _publicPartnerProfilePublishedAt,
      'bookable': true,
      'vehicles': vehicles,
      'limousine_offers': _limousineOffers,
      if (_limousinePublicAvailable) 'limousine_available': true,
      if (_limousineDiscoveryListable) 'discovery_listable': true,
    };
  }

  Widget _limousineReadinessRow(LimousinePublicAvailabilityState state) {
    final label = limousineAvailabilityStateLabelFor(state, _lang);
    final available =
        state == LimousinePublicAvailabilityState.publiclyAvailable;
    final blocked =
        state == LimousinePublicAvailabilityState.suspendedOrBlocked;
    final Color dot = available
        ? const Color(0xFF34D29A)
        : (blocked ? const Color(0xFFE5534B) : _textMuted);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _inputFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _inputBorderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(
                    nl: 'Limousine-status',
                    en: 'Limousine readiness',
                    fr: 'État limousine',
                    es: 'Estado de limusina',
                  ),
                  style: TextStyle(color: _textMuted, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // LIMOUSINE-MARKETPLACE-P2B2 — Limousine offers and pricing
  //
  // Owns pricing rules, packages, terms and publication. Deliberately separate
  // from the taxi Pricing engine, Airport fixed fares and driver management.
  // Prices are never configured per driver.
  // ===========================================================================

  List<String> get _limousineKnownClassIds => appConfig
      .enabledLimousineServiceClasses
      .map((o) => o.id)
      .toList(growable: false);

  String _limousineMoneyLabel(int? cents, String currency) {
    if (cents == null) return '—';
    final amount = (cents / 100).toStringAsFixed(2);
    return '$amount ${currency.isEmpty ? '' : currency}'.trim();
  }

  Future<void> _loadLimousineOffers() async {
    final scope = _strictSettingsScopeForAction(
      action: 'limousine_offers_load',
      showUx: false,
    );
    if (scope == null) return;
    try {
      final data = await fetchAdminLimousinePricing(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      final section = (data['limousine'] is Map)
          ? Map<String, dynamic>.from(data['limousine'] as Map)
          : <String, dynamic>{};
      final offers = (section['offers'] is List)
          ? (section['offers'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      rememberLimousineQuoteRequestsConfirmedOffers(offers);
      setState(() {
        _limousineOffers = offers;
        _limousineSectionEnabled = section['enabled'] == true;
        _limousinePublicTitle = limousineLocalizedOf(section['public_title']);
        _limousinePublicDescription = limousineLocalizedOf(
          section['public_description'],
        );
        _limousinePublicAvailable =
            data['visibility_ok'] == true || data['discovery_listable'] == true;
        _limousineDiscoveryListable = data['discovery_listable'] == true;
        _limousineOffersConfirmed = LimousineOffersEditorSnapshot(
          enabled: _limousineSectionEnabled,
          offers: _limousineOffers,
        ).copy();
      });
    } catch (e) {
      if (!mounted) return;
      limousineFriendlyCompanyError(e, language: _lang);
      final rolled = limousineRollbackFailedPersistence(
        confirmed: _limousineOffersConfirmed,
      );
      setState(() {
        _limousineSectionEnabled = rolled.enabled;
        _limousineOffers = rolled.offers.toList();
      });
    }
  }

  _SetupStatus _limousineOffersCardStatus() {
    final publicOn = _mappedPublicServiceIds().contains(
      kLimousinePublicServiceId,
    );
    if (limousineBusinessSettingsCardIsOptional(
      publicServiceEnabled: publicOn,
      sectionEnabled: _limousineSectionEnabled,
    )) {
      return _SetupStatus.optional;
    }
    final vehicles = vehiclesNotifier.value;
    final hasVehicle = limousineSetupLimousineVehicles(
      vehicles,
    ).any((vehicle) => vehicle.isActive);
    final hasOffer = _limousineOffers.any(
      (offer) => limousineOfferIsValidPublished(
        offer,
        vehicles: vehicles,
        knownClassIds: _limousineKnownClassIds,
      ),
    );
    final hasText =
        limousinePublicTextIsComplete(
          title: _limousinePublicTitle,
          description: _limousinePublicDescription,
        ) ||
        _limousineOffers.any(
          (offer) => limousinePublicTextIsComplete(
            title: limousineLocalizedOf(offer['title']),
            description: limousineLocalizedOf(offer['description']),
          ),
        );
    final hasMedia =
        _publicHeroPhotoUrlCtrl.text.trim().isNotEmpty ||
        vehicles.any(limousineVehicleHasSafePublicPhoto);
    return limousineBusinessSettingsCardIsComplete(
          publicServiceEnabled: publicOn,
          sectionEnabled: _limousineSectionEnabled || hasOffer,
          hasEligibleVehicle: hasVehicle,
          hasPublishedOffer: hasOffer,
          hasPublicText: hasText,
          hasSafePublicMedia: hasMedia,
        )
        ? _SetupStatus.complete
        : _SetupStatus.incomplete;
  }

  Widget _limousineOffersCard() {
    return _collapsibleSettingsCard(
      id: 'limousine_offers_pricing',
      icon: Icons.workspace_premium_outlined,
      title: kLimousineOffersPricingSectionTitle.of(_lang),
      subtitle: kLimousineOffersPricingSectionIntro.of(_lang),
      status: _limousineOffersCardStatus(),
      child: Column(
        key: kLimousineCompanyOffersStatusKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _subPanelBg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _inputBorderColor),
            ),
            child: Text(
              kLimousineBusinessSetupTestBadge.of(_lang),
              style: TextStyle(
                color: _textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: kLimousineBusinessSetupOpenKey,
            onPressed: () => openLimousineBusinessSetup(
              context,
              language: _lang,
              backgroundColor: _panelBg,
              companyName: _companyCtrl.text.trim(),
              entryEnabled: LimousineCustomerEntryContract.isVisible,
            ),
            icon: const Icon(Icons.workspace_premium_outlined),
            label: Text(kLimousineBusinessSetupOpenAction.of(_lang)),
          ),
        ],
      ),
    );
  }

  /// Read-only safe preview of what customers would see. Uses the shared safe
  /// projection so the private operating base can never leak.
  Widget _limousineOffersPublicPreview() {
    final safe = buildSafePublicLimousineOffers(
      _limousineOffers,
      eligible: _limousineSectionEnabled,
      vehicles: vehiclesNotifier.value,
      knownClassIds: _limousineKnownClassIds,
      readiness: _limousineSectionEnabled,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _subPanelBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _inputBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              nl: 'Veilige publieke preview',
              en: 'Safe public preview',
              fr: 'Aperçu public sécurisé',
              es: 'Vista previa pública segura',
            ),
            style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            _t(
              nl: 'Alleen gepubliceerd en geldig aanbod. Je exacte standplaats wordt nooit gedeeld.',
              en: 'Published and valid offers only. Your exact operating base is never shared.',
              fr: 'Offres publiées et valides uniquement. Votre base exacte n’est jamais partagée.',
              es: 'Solo ofertas publicadas y válidas. Tu base exacta nunca se comparte.',
            ),
            style: TextStyle(color: _textMuted, fontSize: 11),
          ),
          const SizedBox(height: 8),
          if (safe.isEmpty)
            Text(
              _t(
                nl: 'Nog niets zichtbaar voor klanten.',
                en: 'Nothing visible to customers yet.',
                fr: 'Rien de visible pour les clients.',
                es: 'Nada visible para los clientes todavía.',
              ),
              style: TextStyle(color: _textSecondary, fontSize: 12),
            )
          else
            Column(
              key: kLimousineSettingsPublicOfferPreviewKey,
              children: [
                for (final map in safe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: LimousinePublicOfferCard(
                      offer: LimousinePublishedOffer.fromJson(map),
                      language: _lang,
                      tokens: LimousineUxTokens(
                        background: _pageBg,
                        surface: _panelBg,
                        surfaceAlt: _subPanelBg,
                        onSurface: _textPrimary,
                        muted: _textMuted,
                        border: _inputBorderColor,
                        gold: _accent,
                        danger: _danger,
                        fieldFill: _inputFill,
                        onHero: _textPrimary,
                        heroScrim: _pageBg.withOpacity(0.42),
                        isDark: _isDark,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _limousineReadinessSummary() {
    final scopeId = _strictSettingsScopeForAction(
      action: 'limousine_readiness',
    )?.companyId;
    if (scopeId == null || scopeId.trim().isEmpty) {
      return _limousineReadinessRow(
        LimousinePublicAvailabilityState.suspendedOrBlocked,
      );
    }
    return FutureBuilder<BackendSubscriptionProfile>(
      future: fetchCompanySubscriptionProfile(
        tenantId: scopeId,
        companyId: scopeId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _limousineReadinessRow(
            LimousinePublicAvailabilityState.unavailableUnderSubscription,
          );
        }
        final profile = snapshot.data;
        final status = profile == null
            ? ''
            : (profile.subscriptionStatus.trim().isNotEmpty
                  ? profile.subscriptionStatus
                  : profile.status);
        final entitled = profile?.features['limousine'] == true;
        final candidate = _limousineReadinessCandidate(
          subscriptionStatus: status,
          entitled: entitled,
        );
        final composition = composeLimousinePublicAvailability(candidate);
        return _limousineReadinessRow(composition.state);
      },
    );
  }

  /// True when the page is rendering a single focused setup step. False when
  /// `widget.stepMode` is `false`, when `widget.initialFocus` is null/empty,
  /// or when `widget.initialFocus` is not in the supported step set
  /// ([_kStepFocusableSectionIds]). Returning false for unknown ids causes
  /// [build] to render the full cockpit, which is the documented graceful
  /// fallback.
  bool get _isActiveStepMode {
    if (!widget.stepMode) return false;
    final focus = widget.initialFocus;
    if (focus == null || focus.isEmpty) return false;
    return _kStepFocusableSectionIds.contains(focus);
  }

  /// Gate used by every section render in [build]. Returns `true` for every
  /// section in normal mode (so the existing single-page cockpit is
  /// byte-identical), and only the focused id in step mode.
  bool _shouldShowSection(String id) {
    if (!_isActiveStepMode) return true;
    return id == widget.initialFocus;
  }

  String? _resolvedInitialSectionId() {
    if (_isActiveStepMode || widget.initialSection == null) return null;
    return widget.initialSection!.sectionId;
  }

  void _scrollToSection(String sectionId) {
    final anchorKey = _sectionAnchorKeys[sectionId];
    final targetContext = anchorKey?.currentContext;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.08,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _scheduleInitialSectionFocus(String sectionId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToSection(sectionId);
      });
      Future<void>.delayed(const Duration(milliseconds: 2200), () {
        if (!mounted) return;
        if (_highlightedSectionId == sectionId) {
          setState(() => _highlightedSectionId = null);
        }
      });
    });
  }

  /// Localizes the "Step X of Y" progress label rendered in the AppBar
  /// strip when active step mode is on. Returns an empty string when
  /// either index or total is missing so the strip can hide cleanly.
  String _stepProgressLabel() {
    final i = widget.stepIndex;
    final t = widget.stepTotal;
    if (i == null || t == null || t <= 0) return '';
    switch (_lang) {
      case AppLanguage.nl:
        return 'Stap $i van $t';
      case AppLanguage.en:
        return 'Step $i of $t';
      case AppLanguage.fr:
        return 'Étape $i sur $t';
      case AppLanguage.es:
        return 'Paso $i de $t';
      case AppLanguage.de:
        return 'Step $i of $t';
    }
  }

  /// Step-mode wrapper around [_save]. Reuses the existing orchestrator
  /// (which already drives `saveBackendBusinessProfile`,
  /// `_saveBackendTaxProfile`, `_saveCancellationPolicyProfile`,
  /// `_saveAirportFixedFareRules`, and `updateBusinessSettings`) so no save
  /// path is duplicated. After [_save] returns we forward to
  /// `widget.onStepSaved` so the wizard parent can decide whether to
  /// advance. Per-part backend failures are still surfaced via the existing
  /// in-page snackbar shown by [_save] itself; the wizard parent inspects
  /// the relevant `_*Status()` getter to decide the next move.
  Future<void> _saveAndContinue() async {
    if (_saveAllBusy) return;
    await _save();
    if (!mounted) return;
    widget.onStepSaved?.call();
  }

  @override
  void initState() {
    super.initState();
    companyProfileNotifier.addListener(_onLogoSanitizationListeners);
    businessSettingsNotifier.addListener(_onLogoSanitizationListeners);
    // In step mode, auto-expand the focused section so the user does not
    // have to tap the collapsible header. _expandedSections is private to
    // this State instance, so this cannot leak into a normal-mode page.
    if (widget.stepMode) {
      final focus = widget.initialFocus;
      if (focus != null && _kStepFocusableSectionIds.contains(focus)) {
        _expandedSections.add(focus);
      }
    }
    final initialSectionId = _resolvedInitialSectionId();
    if (initialSectionId != null) {
      _expandedSections.add(initialSectionId);
      _highlightedSectionId = initialSectionId;
      _scheduleInitialSectionFocus(initialSectionId);
    }
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
    _hydrateCancellationPolicyProfile(
      BackendCancellationPolicyProfile.defaults(),
    );
    _mergeLocalIntoGeneralControllersIfEligible();
    final cachedChironStatus = backendChironConnectionStatusNotifier.value;
    if (cachedChironStatus != null) {
      _applyBackendChironStatus(cachedChironStatus, confirmed: true);
    }
    _loadBackendProfiles();
    _loadGoogleCalendarStatus();
    _loadMollieConnectStatus();
    _loadMollieTerminalsSnapshot();
    _loadBillitIntegrationStatus();
    _loadBillitAutoCreateSettings();
    _loadAirportFixedFareRules();
    _loadLimousineOffers();
    _loadChironConnectionStatus();
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
    _settingsScrollController.dispose();
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
    _cancellationTaxiCutoffCtrl.dispose();
    _cancellationAirportCutoffCtrl.dispose();
    _cancellationBusinessCutoffCtrl.dispose();
    _driverEnRouteEtaCutoffCtrl.dispose();
    _driverEnRouteDistanceCutoffCtrl.dispose();
    _driverLocationFreshnessCtrl.dispose();
    _driverHandoffBufferCtrl.dispose();
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
    _chironEnabled = s.chironEnabled;
    _chironEnvironment = s.chironEnvironment;
    _chironConnectionStatus = s.chironConnectionStatus;
    _chironRegionScope = s.chironRegionScope;
    _chironProductionEnabled = s.chironProductionEnabled;
  }

  void _applyBackendChironStatus(
    BackendChironConnectionStatus status, {
    required bool confirmed,
  }) {
    _chironEnabled = status.enabled;
    _chironEnvironment = status.environment;
    _chironRegionScope = status.region == ChironRegionScope.flanders
        ? ChironRegionScope.flanders
        : '';
    _chironConnectionStatus =
        ChironCompanyConnectionDefaults.mapBackendLastConnectionStatus(
          status.lastConnectionStatus,
        );
    _chironProductionEnabled = status.productionEnabled;
    _chironBackendConfirmed = confirmed;
    _chironConnectionStatusError = null;
  }

  void _syncLocalChironFallback(BackendChironConnectionStatus status) {
    final current = businessSettingsNotifier.value;
    updateBusinessSettings(
      current.copyWith(
        chironEnabled: status.enabled,
        chironEnvironment: status.environment,
        chironConnectionStatus:
            ChironCompanyConnectionDefaults.mapBackendLastConnectionStatus(
              status.lastConnectionStatus,
            ),
        chironRegionScope: status.region == ChironRegionScope.flanders
            ? ChironRegionScope.flanders
            : '',
        chironLastTestedAt: status.lastConnectionTestAt ?? '',
        chironProductionEnabled: status.productionEnabled,
      ),
      syncToBackend: false,
    );
  }

  void _revertChironFromServer() {
    final cached = backendChironConnectionStatusNotifier.value;
    if (cached != null) {
      _applyBackendChironStatus(cached, confirmed: _chironBackendConfirmed);
      return;
    }
    _hydrateFromSettings(businessSettingsNotifier.value);
    _chironBackendConfirmed = false;
  }

  String _chironRegionForBackend() {
    final scope = _chironRegionScope.trim().toLowerCase();
    if (scope == ChironRegionScope.flanders) return ChironRegionScope.flanders;
    return ChironRegionScope.flanders;
  }

  String _normalizeChironRegionForSave(String? region) {
    final raw = (region ?? _chironRegionForBackend()).trim().toLowerCase();
    if (raw.isEmpty || raw != ChironRegionScope.flanders) {
      return ChironRegionScope.flanders;
    }
    return ChironRegionScope.flanders;
  }

  Future<void> _loadChironConnectionStatus({
    bool showErrorSnack = false,
  }) async {
    setState(() {
      _chironConnectionLoading = true;
      _chironConnectionStatusError = null;
    });
    try {
      final scope = _activeSettingsScopeStrict();
      if (scope == null) {
        debugPrint(
          '[BUSINESS_SETTINGS_SCOPE][SKIP] reason=missing_strict_company_scope action=load_chiron_connection_status',
        );
        return;
      }
      final status = await fetchBackendChironConnectionStatus(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return;
      setState(() {
        _applyBackendChironStatus(status, confirmed: true);
      });
      updateBackendChironConnectionStatusCache(status);
      _syncLocalChironFallback(status);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chironBackendConfirmed = false;
        _chironConnectionStatusError = e.toString();
      });
      debugPrint('[CHIRON_CONNECTION][LOAD] error=$e');
      if (showErrorSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Chiron-status kon niet van de server geladen worden.',
                en: 'Chiron status could not be loaded from the server.',
                fr: 'Le statut Chiron n’a pas pu être chargé depuis le serveur.',
                es: 'No se pudo cargar el estado Chiron desde el servidor.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _chironConnectionLoading = false);
      }
    }
  }

  void _showChironProductionRequiresTestPassedSnackbar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Productie kan pas na een geslaagde Chiron-test.',
            en: 'Production is only available after a successful Chiron test.',
            fr: 'La production n’est possible qu’après un test Chiron réussi.',
            es: 'La producción solo está disponible tras una prueba Chiron exitosa.',
          ),
        ),
      ),
    );
  }

  void _showChironSaveErrorSnackbar({String? errorCode}) {
    if (!mounted) return;
    final code = (errorCode ?? '').trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          code.isEmpty
              ? _t(
                  nl: 'Chiron-koppeling kon niet opgeslagen worden.',
                  en: 'Chiron connection could not be saved.',
                  fr: 'La connexion Chiron n’a pas pu être enregistrée.',
                  es: 'No se pudo guardar la conexión Chiron.',
                )
              : _t(
                  nl: 'Chiron-koppeling kon niet opgeslagen worden ($code).',
                  en: 'Chiron connection could not be saved ($code).',
                  fr: 'La connexion Chiron n’a pas pu être enregistrée ($code).',
                  es: 'No se pudo guardar la conexión Chiron ($code).',
                ),
        ),
      ),
    );
  }

  Future<bool> _saveChironConnectionToBackend({
    bool? enabled,
    bool? productionEnabled,
    String? region,
  }) async {
    final scope = _strictSettingsScopeForAction(
      action: 'save_chiron_connection',
    );
    if (scope == null) {
      _revertChironFromServer();
      return false;
    }
    setState(() => _chironConnectionSaving = true);
    try {
      final saved = await saveBackendChironConnectionStatus(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
        enabled: enabled ?? _chironEnabled,
        environment: _chironEnvironment,
        region: _normalizeChironRegionForSave(region),
        productionEnabled: productionEnabled ?? _chironProductionEnabled,
      );
      if (!mounted) return true;
      setState(() {
        _applyBackendChironStatus(saved, confirmed: true);
      });
      updateBackendChironConnectionStatusCache(saved);
      _syncLocalChironFallback(saved);
      return true;
    } on BackendChironConnectionApiException catch (e) {
      if (!mounted) return false;
      setState(() {
        _revertChironFromServer();
      });
      if (e.error == 'production_requires_test_passed') {
        _showChironProductionRequiresTestPassedSnackbar();
      } else {
        _showChironSaveErrorSnackbar(errorCode: e.error);
      }
      debugPrint(
        '[CHIRON_CONNECTION][SAVE] error=${e.error} status=${e.statusCode}',
      );
      return false;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _revertChironFromServer();
      });
      _showChironSaveErrorSnackbar();
      debugPrint('[CHIRON_CONNECTION][SAVE] error=$e');
      return false;
    } finally {
      if (mounted) {
        setState(() => _chironConnectionSaving = false);
      }
    }
  }

  Future<void> _onChironEnabledChanged(bool value) async {
    final previousEnabled = _chironEnabled;
    setState(() {
      _chironEnabled = value;
      if (!value) {
        _chironProductionEnabled = false;
      }
    });
    final saved = await _saveChironConnectionToBackend(enabled: value);
    if (!saved && mounted && _chironEnabled != previousEnabled) {
      setState(() => _chironEnabled = previousEnabled);
    }
  }

  Future<void> _onChironRegionScopeChanged(String? value) async {
    final previous = _chironRegionScope;
    final next = (value ?? '').trim();
    setState(() => _chironRegionScope = next);
    final saved = await _saveChironConnectionToBackend(region: next);
    if (!saved && mounted && _chironRegionScope != previous) {
      setState(() => _chironRegionScope = previous);
    }
  }

  Future<void> _onChironProductionEnabledChanged(bool value) async {
    final previous = _chironProductionEnabled;
    setState(() => _chironProductionEnabled = value);
    final saved = await _saveChironConnectionToBackend(
      productionEnabled: value,
    );
    if (!saved && mounted && _chironProductionEnabled != previous) {
      setState(() => _chironProductionEnabled = previous);
    }
  }

  String _chironBackendLastConnectionStatusRaw() {
    final cached = backendChironConnectionStatusNotifier.value;
    if (cached != null && _chironBackendConfirmed) {
      return cached.lastConnectionStatus;
    }
    if (_chironConnectionStatus == ChironConnectionStatus.testPassed) {
      return ChironConnectionStatus.testPassed;
    }
    if (_chironConnectionStatus == ChironConnectionStatus.testFailed) {
      return ChironConnectionStatus.testFailed;
    }
    if (_chironConnectionStatus == ChironConnectionStatus.testPending) {
      return ChironConnectionStatus.testPending;
    }
    return ChironBackendLastConnectionStatus.neverTested;
  }

  bool _chironProductionAllowedFromServer() {
    return ChironCompanyConnectionDefaults.canEnableProductionFromBackend(
      enabled: _chironEnabled,
      lastConnectionStatus: _chironBackendLastConnectionStatusRaw(),
    );
  }

  _SetupStatus _chironConnectionSetupStatus() {
    // RELEASE-P0-CHIRON-SELF-SERVICE-2026-07-31: never show Complete for
    // ACC-test-only. Complete only when production submission is truly active.
    if (!_chironEnabled) {
      return _SetupStatus.optional;
    }
    final backend = backendChironConnectionStatusNotifier.value;
    if (backend?.productionSubmitActive == true) {
      return _SetupStatus.complete;
    }
    if (backend?.lastConnectionStatus == ChironConnectionStatus.testFailed ||
        backend?.productionLastConnectionStatus ==
            ChironConnectionStatus.testFailed) {
      return _SetupStatus.attention;
    }
    if (backend?.testCredentialsStored == true &&
        backend?.lastConnectionStatus == ChironConnectionStatus.testPassed &&
        backend?.testflowStatus.trim().toLowerCase() != 'complete') {
      return _SetupStatus.activationPending;
    }
    if (backend?.testflowStatus.trim().toLowerCase() == 'complete') {
      return _SetupStatus.activationPending; // production still to set up
    }
    switch (_chironConnectionStatus) {
      case ChironConnectionStatus.testPassed:
        return _SetupStatus.activationPending;
      case ChironConnectionStatus.testFailed:
        return _SetupStatus.attention;
      case ChironConnectionStatus.testPending:
        return _SetupStatus.activationPending;
      default:
        return _SetupStatus.attention;
    }
  }

  String _chironConnectionStatusLabel() {
    if (!_chironEnabled) {
      return _t(
        nl: 'Uitgeschakeld',
        en: 'Disabled',
        fr: 'Désactivé',
        es: 'Desactivado',
      );
    }
    final backendStatus = _chironBackendLastConnectionStatusRaw();
    switch (backendStatus) {
      case ChironConnectionStatus.testPassed:
        return _t(
          nl: 'Test geslaagd',
          en: 'Test passed',
          fr: 'Test réussi',
          es: 'Prueba superada',
        );
      case ChironConnectionStatus.testFailed:
        return _t(
          nl: 'Test mislukt',
          en: 'Test failed',
          fr: 'Test échoué',
          es: 'Prueba fallida',
        );
      case ChironConnectionStatus.testPending:
        return _t(
          nl: 'Test in afwachting',
          en: 'Test pending',
          fr: 'Test en attente',
          es: 'Prueba pendiente',
        );
      case ChironBackendLastConnectionStatus.neverTested:
        return _t(
          nl: 'Ingeschakeld · nog niet getest',
          en: 'Enabled · not tested yet',
          fr: 'Activé · pas encore testé',
          es: 'Activado · aún no probado',
        );
      default:
        return _t(
          nl: 'Nog niet getest',
          en: 'Not tested yet',
          fr: 'Pas encore testé',
          es: 'Aún no probado',
        );
    }
  }

  String _chironEnvironmentLabel() {
    if (_chironEnvironment == ChironConnectionEnvironment.production) {
      return _t(
        nl: 'productie',
        en: 'production',
        fr: 'production',
        es: 'producción',
      );
    }
    return _t(nl: 'test', en: 'test', fr: 'test', es: 'prueba');
  }

  Widget _chironBackendStatusPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _subPanelBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_chironBackendConfirmed) ...[
            Text(
              _t(
                nl: 'Status niet bevestigd door server (lokaal voorbeeld).',
                en: 'Status not confirmed by server (local preview).',
                fr: 'Statut non confirmé par le serveur (aperçu local).',
                es: 'Estado no confirmado por el servidor (vista local).',
              ),
              style: TextStyle(
                color: _danger,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            chironHonestSetupStatusLabel(
              status: backendChironConnectionStatusNotifier.value,
              language: appConfig.currentLanguage,
              enabled: _chironEnabled,
            ),
            style: TextStyle(
              color: _textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ChironEnvironmentStatusLabels(
            status: backendChironConnectionStatusNotifier.value,
            language: appConfig.currentLanguage,
            textColor: _textPrimary,
            mutedColor: _textSecondary,
          ),
          const SizedBox(height: 8),
          Text(
            chironHonestNextStepLabel(
              status: backendChironConnectionStatusNotifier.value,
              language: appConfig.currentLanguage,
              enabled: _chironEnabled,
            ),
            style: TextStyle(color: _textMuted, fontSize: 11.5, height: 1.35),
          ),
        ],
      ),
    );
  }

  String _chironDetailedStatusLabel() {
    final backendStatus = _chironBackendLastConnectionStatusRaw();
    switch (backendStatus) {
      case ChironConnectionStatus.testPassed:
        return _t(
          nl: 'test geslaagd',
          en: 'test passed',
          fr: 'test réussi',
          es: 'prueba superada',
        );
      case ChironConnectionStatus.testFailed:
        return _t(
          nl: 'test mislukt',
          en: 'test failed',
          fr: 'test échoué',
          es: 'prueba fallida',
        );
      case ChironConnectionStatus.testPending:
        return _t(
          nl: 'test in afwachting',
          en: 'test pending',
          fr: 'test en attente',
          es: 'prueba pendiente',
        );
      default:
        return _t(
          nl: 'nog niet getest',
          en: 'not tested yet',
          fr: 'pas encore testé',
          es: 'aún no probado',
        );
    }
  }

  Widget _chironEnvironmentChip() {
    final isProduction =
        _chironEnvironment == ChironConnectionEnvironment.production;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _isDark ? _accent.withOpacity(0.14) : _subPanelBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _isDark
              ? _accent.withOpacity(0.45)
              : _border.withOpacity(0.95),
        ),
      ),
      child: Text(
        isProduction
            ? _t(
                nl: 'Productie',
                en: 'Production',
                fr: 'Production',
                es: 'Producción',
              )
            : _t(nl: 'Test', en: 'Test', fr: 'Test', es: 'Prueba'),
        style: TextStyle(
          color: _textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _chironRegionScopeDropdown() {
    return DropdownButtonFormField<String>(
      value: _chironRegionScope.isEmpty ? '' : _chironRegionScope,
      isExpanded: true,
      style: TextStyle(color: _textPrimary, fontSize: 13),
      iconEnabledColor: _textSecondary,
      dropdownColor: _isDark ? _subPanelBg : _inputFill,
      decoration: InputDecoration(
        labelText: _t(
          nl: 'Regio-scope (optioneel)',
          en: 'Region scope (optional)',
          fr: 'Portée régionale (optionnel)',
          es: 'Ámbito regional (opcional)',
        ),
        labelStyle: TextStyle(color: _textSecondary),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        filled: true,
        fillColor: _inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _inputBorderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _inputBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _inputFocusColor, width: 1.2),
        ),
      ),
      items: [
        DropdownMenuItem(
          value: '',
          child: Text(
            _t(
              nl: 'Niet van toepassing',
              en: 'Not applicable',
              fr: 'Non applicable',
              es: 'No aplicable',
            ),
            style: TextStyle(color: _textPrimary),
          ),
        ),
        DropdownMenuItem(
          value: ChironRegionScope.flanders,
          child: Text(
            _t(nl: 'Vlaanderen', en: 'Flanders', fr: 'Flandre', es: 'Flandes'),
            style: TextStyle(color: _textPrimary),
          ),
        ),
      ],
      onChanged: _chironConnectionSaving || _chironConnectionLoading
          ? null
          : _onChironRegionScopeChanged,
    );
  }

  bool get _isChironOnboardingStep =>
      _isActiveStepMode && widget.initialFocus == 'chiron_connection';

  Widget _chironOnboardingNotes() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _subPanelBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              nl: 'Chiron is alleen nodig voor bedrijven met een Vlaamse Chiron-meldplicht. Geen Chiron-plicht? Laat deze koppeling uitgeschakeld en ga verder.',
              en: 'Chiron is only needed for companies that are required to report through Chiron in Flanders. Not required to use Chiron? Leave this connection disabled and continue.',
              fr: 'Chiron est uniquement nécessaire pour les entreprises soumises à l’obligation de déclaration Chiron en Flandre. Pas d’obligation Chiron ? Laissez cette connexion désactivée et continuez.',
              es: 'Chiron solo es necesario para empresas obligadas a informar mediante Chiron en Flandes. ¿No estás obligado a usar Chiron? Deja esta conexión desactivada y continúa.',
            ),
            style: TextStyle(
              color: _textSecondary,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              nl: 'De Chiron-toegang hoort bij het bedrijf. Fluxidi gebruikt geen centraal Chiron-account voor klanten.',
              en: 'Chiron access belongs to the company. Fluxidi does not use one central Chiron account for customers.',
              fr: 'L’accès Chiron appartient à l’entreprise. Fluxidi n’utilise pas de compte Chiron central pour ses clients.',
              es: 'El acceso Chiron pertenece a la empresa. Fluxidi no utiliza una cuenta Chiron central para los clientes.',
            ),
            style: TextStyle(color: _textMuted, fontSize: 11.5, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _chironManagementInfoNote() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _subPanelBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Text(
        _t(
          nl: 'Beheer de Chiron-koppeling met de officiële toegang van dit bedrijf.',
          en: 'Manage the Chiron connection using this company’s official Chiron access.',
          fr: 'Gérez la connexion Chiron avec l’accès Chiron officiel de cette entreprise.',
          es: 'Gestiona la conexión Chiron con el acceso Chiron oficial de esta empresa.',
        ),
        style: TextStyle(color: _textMuted, fontSize: 11.5, height: 1.35),
      ),
    );
  }

  Widget _chironConnectionCard() {
    final productionAllowed = _chironProductionAllowedFromServer();
    return _collapsibleSettingsCard(
      id: 'chiron_connection',
      icon: Icons.verified_user_outlined,
      title: _t(
        nl: 'Chiron-koppeling',
        en: 'Chiron connection',
        fr: 'Connexion Chiron',
        es: 'Conexión Chiron',
      ),
      subtitle: _t(
        nl: 'Optionele koppeling voor Vlaamse Chiron-plichtige exploitanten',
        en: 'Optional connection for Flemish Chiron-regulated operators',
        fr: 'Connexion optionnelle pour les exploitants Chiron en Flandre',
        es: 'Conexión opcional para operadores Chiron en Flandes',
      ),
      status: _chironConnectionSetupStatus(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              nl: 'Koppel de Chiron-toegang van je bedrijf aan Fluxidi. Test de verbinding eerst veilig in de Chiron-testomgeving voordat je overschakelt naar productie.',
              en: 'Connect your company’s Chiron access to Fluxidi. Test the connection safely in the Chiron test environment before switching to production.',
              fr: 'Connectez l’accès Chiron de votre entreprise à Fluxidi. Testez d’abord la connexion dans l’environnement de test Chiron avant de passer en production.',
              es: 'Conecta el acceso Chiron de tu empresa con Fluxidi. Prueba primero la conexión en el entorno de pruebas de Chiron antes de pasar a producción.',
            ),
            style: TextStyle(color: _textSecondary, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              nl: 'Niet elk bedrijf heeft Chiron nodig. Fluxidi activeert deze koppeling alleen wanneer jouw regio en vergunning dit vereisen.',
              en: 'Not every company needs Chiron. Fluxidi only enables this connection when your region and licence require it.',
              fr: 'Toutes les entreprises n’ont pas besoin de Chiron. Fluxidi n’active cette connexion que si votre région et votre autorisation l’exigent.',
              es: 'No todas las empresas necesitan Chiron. Fluxidi solo activa esta conexión cuando tu región y licencia lo requieren.',
            ),
            style: TextStyle(color: _textMuted, fontSize: 11.5, height: 1.35),
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              nl: 'Chiron is bedoeld voor Vlaamse taxi-, VVB- en IBP-exploitanten met een Chiron-meldingsplicht. Wallonië, Brussel en buitenland vallen doorgaans buiten deze koppeling.',
              en: 'Chiron is intended for Flemish taxi, VVB and IBP operators with a Chiron reporting obligation. Wallonia, Brussels and abroad are usually outside this connection.',
              fr: 'Chiron est destiné aux exploitants taxi, VVB et IBP flamands soumis à déclaration Chiron. La Wallonie, Bruxelles et l’étranger sont en général hors scope.',
              es: 'Chiron está pensado para operadores de taxi, VVB e IBP flamencos con obligación de notificación Chiron. Valonia, Bruselas y el extranjero suelen quedar fuera.',
            ),
            style: TextStyle(color: _textMuted, fontSize: 11.5, height: 1.35),
          ),
          const SizedBox(height: 12),
          if (_chironConnectionLoading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: _accent,
                backgroundColor: _border.withOpacity(0.35),
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _t(
                nl: 'Chiron-koppeling inschakelen',
                en: 'Enable Chiron connection',
                fr: 'Activer la connexion Chiron',
                es: 'Activar conexión Chiron',
              ),
              style: TextStyle(
                color: _textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            subtitle: Text(
              _chironConnectionStatusLabel(),
              style: TextStyle(color: _textSecondary, fontSize: 11.5),
            ),
            value: _chironEnabled,
            onChanged: _chironConnectionSaving || _chironConnectionLoading
                ? null
                : _onChironEnabledChanged,
          ),
          if (_chironEnabled) ...[
            const SizedBox(height: 8),
            _chironBackendStatusPanel(),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _t(
                  nl: 'Omgeving',
                  en: 'Environment',
                  fr: 'Environnement',
                  es: 'Entorno',
                ),
                style: TextStyle(color: _textPrimary, fontSize: 13),
              ),
              subtitle: Text(
                _t(
                  nl: 'Testomgeving (standaard)',
                  en: 'Test environment (default)',
                  fr: 'Environnement de test (par défaut)',
                  es: 'Entorno de pruebas (predeterminado)',
                ),
                style: TextStyle(color: _textSecondary, fontSize: 11.5),
              ),
              trailing: _chironEnvironmentChip(),
            ),
            _chironRegionScopeDropdown(),
            if (!_isChironOnboardingStep) ...[
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _t(
                    nl: 'Productie',
                    en: 'Production',
                    fr: 'Production',
                    es: 'Producción',
                  ),
                  style: TextStyle(
                    color: productionAllowed ? _textPrimary : _textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  _t(
                    nl: 'Alleen na geslaagde test',
                    en: 'Only after a successful test',
                    fr: 'Uniquement après un test réussi',
                    es: 'Solo tras una prueba exitosa',
                  ),
                  style: TextStyle(color: _textSecondary, fontSize: 11.5),
                ),
                value: _chironProductionEnabled && productionAllowed,
                onChanged: productionAllowed && !_chironConnectionSaving
                    ? _onChironProductionEnabledChanged
                    : null,
              ),
              const SizedBox(height: 8),
              _chironManagementInfoNote(),
            ],
          ],
          if (_isChironOnboardingStep) ...[
            const SizedBox(height: 12),
            _chironOnboardingNotes(),
          ],
        ],
      ),
    );
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
    final normalizedCountryCode = _normalizeBusinessCountryCode(p.country);
    if (normalizedCountryCode.isNotEmpty) {
      _backendCountryCtrl.text = normalizedCountryCode;
    }
    _backendPhoneCtrl.text = p.phone;
    _backendEmailCtrl.text = resolvePrimaryCompanyContactEmail(
      backend: p,
      local: companyProfileNotifier.value,
    );
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
    final incoming = PublicServiceSelection(
      ids: p.publicServiceIds,
      configured: p.publicServicesConfigured,
    );
    _publicServicesConfigured =
        incoming.configured || incoming.limousineEnabled;
    if (_publicServicesConfigured) {
      _publicServiceIds = incoming.ids.toSet();
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
    _paymentOwnerMode = p.paymentOwnerMode.trim().isEmpty
        ? 'fluxidi_central_demo'
        : p.paymentOwnerMode.trim();
    _paymentDemoMode = p.paymentDemoMode;
    _mollieConnected = p.mollieConnected;
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

  void _hydrateCancellationPolicyProfile(BackendCancellationPolicyProfile p) {
    final safeTaxi = p.taxiCutoffMinutes.clamp(0, 10080).toInt();
    final safeAirport = p.airportCutoffMinutes.clamp(0, 10080).toInt();
    final safeBusiness = p.businessCutoffMinutes.clamp(0, 10080).toInt();
    final safeEta = p.driverEnRouteEtaCutoffMinutes.clamp(0, 240).toInt();
    final safeDistance = p.driverEnRouteDistanceCutoffKm.clamp(0, 100);
    final safeFreshness = p.driverLocationFreshnessSeconds
        .clamp(30, 3600)
        .toInt();
    final safeHandoff = p.driverHandoffBufferMinutes.clamp(0, 120).toInt();
    _allowCustomerOnlineCancellation = p.allowCustomerOnlineCancellation;
    _cancellationTaxiCutoffCtrl.text = safeTaxi.toString();
    _cancellationAirportCutoffCtrl.text = safeAirport.toString();
    _cancellationBusinessCutoffCtrl.text = safeBusiness.toString();
    _blockWhenDriverEnRoute = p.blockWhenDriverEnRoute;
    _driverEnRouteEtaCutoffCtrl.text = safeEta.toString();
    _driverEnRouteDistanceCutoffCtrl.text = safeDistance % 1 == 0
        ? safeDistance.toStringAsFixed(0)
        : safeDistance.toStringAsFixed(2);
    _driverLocationFreshnessCtrl.text = safeFreshness.toString();
    _driverHandoffBufferCtrl.text = safeHandoff.toString();
    _paidBookingCancellationMode = 'review_required';
  }

  int? _parseCancellationIntOrNull(
    String raw, {
    required int min,
    required int max,
  }) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    if (parsed == null) return null;
    if (parsed < min || parsed > max) return null;
    return parsed;
  }

  double? _parseCancellationDoubleOrNull(
    String raw, {
    required double min,
    required double max,
  }) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text.replaceAll(',', '.'));
    if (parsed == null || !parsed.isFinite) return null;
    if (parsed < min || parsed > max) return null;
    return parsed;
  }

  BackendCancellationPolicyProfile? _cancellationPolicyProfileFromFormOrNull() {
    final defaults = BackendCancellationPolicyProfile.defaults();
    final taxi = _parseCancellationIntOrNull(
      _cancellationTaxiCutoffCtrl.text,
      min: 0,
      max: 10080,
    );
    final airport = _parseCancellationIntOrNull(
      _cancellationAirportCutoffCtrl.text,
      min: 0,
      max: 10080,
    );
    final business = _parseCancellationIntOrNull(
      _cancellationBusinessCutoffCtrl.text,
      min: 0,
      max: 10080,
    );
    final etaCutoff = _parseCancellationIntOrNull(
      _driverEnRouteEtaCutoffCtrl.text,
      min: 0,
      max: 240,
    );
    final distanceCutoff = _parseCancellationDoubleOrNull(
      _driverEnRouteDistanceCutoffCtrl.text,
      min: 0,
      max: 100,
    );
    final freshnessSeconds = _parseCancellationIntOrNull(
      _driverLocationFreshnessCtrl.text,
      min: 30,
      max: 3600,
    );
    final handoffMinutes = _parseCancellationIntOrNull(
      _driverHandoffBufferCtrl.text,
      min: 0,
      max: 120,
    );
    if (taxi == null ||
        airport == null ||
        business == null ||
        etaCutoff == null ||
        distanceCutoff == null ||
        freshnessSeconds == null ||
        handoffMinutes == null) {
      return null;
    }
    return BackendCancellationPolicyProfile(
      version: defaults.version,
      allowCustomerOnlineCancellation: _allowCustomerOnlineCancellation,
      taxiCutoffMinutes: taxi,
      airportCutoffMinutes: airport,
      businessCutoffMinutes: business,
      paidBookingCancellationMode: 'review_required',
      blockWhenDriverEnRoute: _blockWhenDriverEnRoute,
      driverEnRouteEtaCutoffMinutes: etaCutoff,
      driverEnRouteDistanceCutoffKm: distanceCutoff,
      driverLocationFreshnessSeconds: freshnessSeconds,
      driverHandoffBufferMinutes: handoffMinutes,
      updatedAt: '',
    );
  }

  Future<bool> _saveCancellationPolicyProfile({
    bool showErrorSnackBar = false,
  }) async {
    final profile = _cancellationPolicyProfileFromFormOrNull();
    if (profile == null) {
      final msg = _t(
        nl: 'Ongeldige waarde. Controleer de ingestelde limieten.',
        en: 'Invalid value. Please check the configured limits.',
        fr: 'Valeur invalide. Verifiez les limites configurees.',
        es: 'Valor invalido. Revisa los limites configurados.',
      );
      setState(() {
        _cancellationPolicyError = msg;
        _cancellationPolicyStatus = null;
      });
      if (showErrorSnackBar && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
      return false;
    }
    setState(() {
      _cancellationPolicySaving = true;
      _cancellationPolicyError = null;
      _cancellationPolicyStatus = null;
    });
    try {
      final scope = _strictSettingsScopeForAction(
        action: 'save_cancellation_policy_profile',
      );
      if (scope == null) return false;
      final saved = await saveBackendCancellationPolicyProfile(
        profile,
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return false;
      setState(() {
        _hydrateCancellationPolicyProfile(saved);
        _cancellationPolicyStatus = _t(
          nl: 'Opgeslagen.',
          en: 'Saved.',
          fr: 'Enregistre.',
          es: 'Guardado.',
        );
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      final msg =
          '${_t(nl: 'Opslaan mislukt', en: 'Save failed', fr: 'Echec de l enregistrement', es: 'Error al guardar')}: $e';
      setState(() {
        _cancellationPolicyError = msg;
        _cancellationPolicyStatus = null;
      });
      if (showErrorSnackBar && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _cancellationPolicySaving = false);
      }
    }
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
      List<String> serverValue, {
      required bool localConfigured,
      required bool serverConfigured,
    }) {
      return mergePublicServiceSelection(
        local: PublicServiceSelection(
          ids: localValue,
          configured: localConfigured,
        ),
        server: PublicServiceSelection(
          ids: serverValue,
          configured: serverConfigured,
        ),
        serverFieldPresent: serverConfigured || serverValue.isNotEmpty,
      ).ids;
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
      companyEmail: pick(local.companyEmail, server.companyEmail),
      supportEmail: pick(local.supportEmail, server.supportEmail),
      notificationEmail: pick(
        local.notificationEmail,
        server.notificationEmail,
      ),
      pendingEmail: pick(local.pendingEmail, server.pendingEmail),
      emailVerificationStatus: pick(
        local.emailVerificationStatus,
        server.emailVerificationStatus,
      ),
      confirmationRequired:
          server.confirmationRequired || local.confirmationRequired,
      emailChallengeId: pick(local.emailChallengeId, server.emailChallengeId),
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
        localConfigured: local.publicServicesConfigured,
        serverConfigured: server.publicServicesConfigured,
      ),
      publicServicesConfigured: mergePublicServiceSelection(
        local: PublicServiceSelection(
          ids: local.publicServiceIds,
          configured: local.publicServicesConfigured,
        ),
        server: PublicServiceSelection(
          ids: server.publicServiceIds,
          configured: server.publicServicesConfigured,
        ),
        serverFieldPresent:
            server.publicServicesConfigured ||
            server.publicServiceIds.isNotEmpty,
      ).configured,
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
      paymentOwnerMode: server.paymentOwnerMode.trim().isNotEmpty
          ? server.paymentOwnerMode
          : local.paymentOwnerMode,
      paymentDemoMode: server.paymentDemoMode || local.paymentDemoMode,
      mollieConnected: server.mollieConnected || local.mollieConnected,
      mollieOrganizationId: server.mollieOrganizationId.isNotEmpty
          ? server.mollieOrganizationId
          : local.mollieOrganizationId,
      mollieProfileId: server.mollieProfileId.isNotEmpty
          ? server.mollieProfileId
          : local.mollieProfileId,
      mollieTokenRef: server.mollieTokenRef.isNotEmpty
          ? server.mollieTokenRef
          : local.mollieTokenRef,
    );
  }

  Future<void> _loadBackendProfiles() async {
    setState(() {
      _backendProfilesLoading = true;
      _cancellationPolicyLoading = true;
      _backendProfilesError = null;
      _backendProfilesStatus = null;
    });
    try {
      final scope = _activeSettingsScopeStrict();
      if (scope == null) {
        debugPrint(
          '[BUSINESS_SETTINGS_SCOPE][SKIP] reason=missing_strict_company_scope action=load_backend_profiles',
        );
        return;
      }
      final results = await Future.wait<dynamic>([
        fetchBackendBusinessProfile(
          tenantId: scope.tenantId,
          companyId: scope.companyId,
        ),
        fetchBackendTaxProfile(
          tenantId: scope.tenantId,
          companyId: scope.companyId,
        ),
        fetchBackendCancellationPolicyProfile(
          tenantId: scope.tenantId,
          companyId: scope.companyId,
        ),
      ]);
      if (!mounted) return;
      final rawBiz = results[0] as BackendBusinessProfile;
      final rawTax = results[1] as BackendTaxProfile;
      final rawCancellation = results[2] as BackendCancellationPolicyProfile;
      await _hydratePublicCompanyCodeFromBackendProfile(
        rawBiz,
        source: 'business_profile_get',
      );
      // Merge server response over the locally cached profile so empty server
      // fields do not wipe non-empty user-saved values. Prefer the current
      // form when the user already toggled public services during load.
      final cached = localBackendBusinessProfileNotifier.value;
      final formNow = _backendBusinessProfileFromForm();
      final localBase = _mergeBackendBusinessProfile(
        local:
            cached ??
            mergeLocalIntoBackendPreview(
              BackendBusinessProfile.defaults(),
              companyProfileNotifier.value,
            ),
        server: formNow,
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
        _hydrateCancellationPolicyProfile(rawCancellation);
        _cancellationPolicyError = null;
        _cancellationPolicyStatus = null;
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
        _hydrateCancellationPolicyProfile(
          BackendCancellationPolicyProfile.defaults(),
        );
        _cancellationPolicyError = _t(
          nl: 'Annulatiebeleid kon niet online geladen worden. Standaardwaarden blijven actief.',
          en: 'Cancellation policy could not be loaded online. Defaults remain active.',
          fr: 'La politique d annulation n a pas pu etre chargee en ligne. Les valeurs par defaut restent actives.',
          es: 'No se pudo cargar la politica de cancelacion en linea. Los valores predeterminados siguen activos.',
        );
        _cancellationPolicyStatus = null;
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
        setState(() {
          _backendProfilesLoading = false;
          _cancellationPolicyLoading = false;
        });
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
      case 'disconnected':
        return _t(
          nl: 'Losgekoppeld',
          en: 'Disconnected',
          fr: 'Déconnecté',
          es: 'Desconectado',
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
      case 'disconnected':
        return _t(
          nl: 'Google Calendar is losgekoppeld voor dit bedrijf. Nieuwe boekingen worden niet meer automatisch in de agenda geplaatst.',
          en: 'Google Calendar is disconnected for this company. New bookings will no longer be added automatically to the calendar.',
          fr: 'Google Agenda est déconnecté pour cette entreprise. Les nouvelles réservations ne seront plus ajoutées automatiquement au calendrier.',
          es: 'Google Calendar está desconectado para esta empresa. Las nuevas reservas ya no se añadirán automáticamente al calendario.',
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

  String? _mollieConnectStatusField(String key) {
    final raw = (_mollieConnectStatus?[key] ?? '').toString().trim();
    return raw.isEmpty ? null : raw;
  }

  bool get _mollieConnectConnected => _mollieConnectStatus?['connected'] is bool
      ? _mollieConnectStatus!['connected'] as bool
      : _mollieConnected;

  String _mollieConnectStatusCode() {
    final raw = (_mollieConnectStatus?['status'] ?? '').toString().trim();
    if (raw.isNotEmpty) return raw.toLowerCase();
    return _mollieConnectConnected ? 'connected' : 'not_configured';
  }

  String _mollieConnectStatusLabel() {
    switch (_mollieConnectStatusCode()) {
      case 'connected':
        return _t(
          nl: 'Mollie-account gekoppeld',
          en: 'Mollie account connected',
          fr: 'Compte Mollie connecte',
          es: 'Cuenta Mollie conectada',
        );
      case 'disconnected':
        return _t(
          nl: 'Mollie-account losgekoppeld',
          en: 'Mollie account disconnected',
          fr: 'Compte Mollie deconnecte',
          es: 'Cuenta Mollie desconectada',
        );
      case 'failed':
      case 'auth_required':
        return _t(
          nl: 'Mollie-koppeling vraagt aandacht',
          en: 'Mollie connection needs attention',
          fr: 'La connexion Mollie demande attention',
          es: 'La conexión de Mollie requiere atención',
        );
      case 'not_configured':
      default:
        return _t(
          nl: 'Mollie nog niet gekoppeld',
          en: 'Mollie not connected yet',
          fr: 'Mollie pas encore connecte',
          es: 'Mollie aún no conectado',
        );
    }
  }

  String _mollieConnectDescription() {
    if (_mollieConnectConnected) {
      return _t(
        nl: 'Je Mollie-account is gekoppeld. Online betalingen via je eigen Mollie-account worden in een volgende stap geactiveerd.',
        en: 'Your Mollie account is connected. Online payments through your own Mollie account will be activated in a next step.',
        fr: 'Votre compte Mollie est connecte. Les paiements en ligne via votre propre compte Mollie seront actives dans une prochaine etape.',
        es: 'Tu cuenta de Mollie esta conectada. Los pagos online a traves de tu propia cuenta Mollie se activaran en un siguiente paso.',
      );
    }
    return _t(
      nl: 'Koppel het eigen Mollie-account van dit bedrijf om online betaalmethodes zoals Bancontact, iDEAL, kaartbetalingen, Apple Pay, Google Pay en PayPal te activeren.',
      en: 'Connect this company’s own Mollie account to activate online payment methods such as Bancontact, iDEAL, card payments, Apple Pay, Google Pay and PayPal.',
      fr: 'Connectez le compte Mollie propre à cette entreprise pour activer les moyens de paiement en ligne comme Bancontact, iDEAL, les paiements par carte, Apple Pay, Google Pay et PayPal.',
      es: 'Conecta la cuenta Mollie propia de esta empresa para activar métodos de pago en línea como Bancontact, iDEAL, pagos con tarjeta, Apple Pay, Google Pay y PayPal.',
    );
  }

  String _mollieModeLabel(String? raw) {
    final token = (raw ?? '').trim().toLowerCase();
    switch (token) {
      case 'test':
        return 'TEST';
      case 'live':
        return 'LIVE';
      default:
        return _t(
          nl: 'Onbekend',
          en: 'Unknown',
          fr: 'Inconnu',
          es: 'Desconocido',
        );
    }
  }

  String _maskedMollieId(String? raw) {
    final text = (raw ?? '').trim();
    if (text.length <= 10) return text;
    final prefix = text.contains('_') ? '${text.split('_').first}_' : '';
    final suffix = text.substring(text.length - 4);
    return '$prefix...$suffix';
  }

  List<Map<String, dynamic>> _mollieTerminalList() {
    final raw = _mollieTerminalsSnapshot?['terminals'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }

  bool _isMollieTerminalForgotten(Map<String, dynamic> terminal) {
    if (terminal['forgotten'] == true || terminal['forgotten'] == 'true') {
      return true;
    }
    if (terminal['removed_from_fluxidi'] == true) return true;
    return false;
  }

  bool _isMollieTerminalExcluded(Map<String, dynamic> terminal) {
    if (_isMollieTerminalForgotten(terminal)) return true;
    if (terminal['excluded'] == true || terminal['excluded'] == 'true') {
      return true;
    }
    if (terminal['linked'] == false || terminal['linked'] == 'false') {
      return true;
    }
    return false;
  }

  List<Map<String, dynamic>> _mollieActiveTerminalList() =>
      _mollieTerminalList()
          .where(
            (t) =>
                !_isMollieTerminalExcluded(t) && !_isMollieTerminalForgotten(t),
          )
          .toList(growable: false);

  List<Map<String, dynamic>> _mollieExcludedTerminalList() =>
      _mollieTerminalList()
          .where(
            (t) =>
                _isMollieTerminalExcluded(t) && !_isMollieTerminalForgotten(t),
          )
          .toList(growable: false);

  String _mollieTerminalsStatusCode() {
    final raw = (_mollieTerminalsSnapshot?['status'] ?? '').toString().trim();
    if (raw.isNotEmpty) return raw.toLowerCase();
    if (_mollieTerminalsError != null) return 'fetch_failed';
    return 'not_synced';
  }

  String _mollieTerminalCardSubtitle() {
    return _t(
      nl: 'Terminalstatus en synchronisatie',
      en: 'Terminal status and sync',
      fr: 'Statut et synchronisation',
      es: 'Estado y sincronización',
    );
  }

  String _mollieTerminalStatusTitle() {
    final status = _mollieTerminalsStatusCode();
    final terminals = _mollieTerminalList();
    if (status == 'terminals_scope_missing') {
      return _t(
        nl: 'Mollie opnieuw verbinden nodig',
        en: 'Reconnect Mollie required',
        fr: 'Reconnexion Mollie nécessaire',
        es: 'Es necesario volver a conectar Mollie',
      );
    }
    if (status == 'synced' && terminals.isEmpty) {
      return _t(
        nl: 'Geen terminals gevonden',
        en: 'No terminals found',
        fr: 'Aucun terminal trouvé',
        es: 'No se encontraron terminales',
      );
    }
    if (status == 'synced') {
      return _t(
        nl: 'Terminals gevonden',
        en: 'Terminals found',
        fr: 'Terminaux trouvés',
        es: 'Terminales encontrados',
      );
    }
    if (status == 'fetch_failed') {
      return _t(
        nl: 'Terminalstatus kon niet geladen worden',
        en: 'Terminal status could not be loaded',
        fr: 'Le statut des terminaux n’a pas pu être chargé',
        es: 'No se pudo cargar el estado de los terminales',
      );
    }
    return _t(
      nl: 'Nog niet gesynchroniseerd',
      en: 'Not synced yet',
      fr: 'Pas encore synchronisé',
      es: 'Aún no sincronizado',
    );
  }

  String _mollieTerminalStatusDescription() {
    final status = _mollieTerminalsStatusCode();
    final terminals = _mollieTerminalList();
    if (status == 'terminals_scope_missing') {
      return _t(
        nl: 'De huidige Mollie-koppeling heeft nog geen terminalrechten. Verbind Mollie opnieuw om terminals te kunnen synchroniseren.',
        en: 'The current Mollie connection does not have terminal permissions yet. Reconnect Mollie to sync terminals.',
        fr: 'La connexion Mollie actuelle ne dispose pas encore des droits pour les terminaux. Reconnectez Mollie pour les synchroniser.',
        es: 'La conexión actual de Mollie aún no tiene permisos para terminales. Vuelve a conectar Mollie para poder sincronizarlos.',
      );
    }
    if (status == 'synced' && terminals.isEmpty) {
      return _t(
        nl: 'Controleer in Mollie of Point of Sale/terminalbetalingen actief zijn voor dit profiel. In testmodus kan Mollie een testterminal beschikbaar maken wanneer Point of Sale actief is.',
        en: 'Check in Mollie whether Point of Sale or terminal payments are active for this profile. In test mode, Mollie may provide a test terminal when Point of Sale is active.',
        fr: 'Vérifiez dans Mollie si les paiements Point of Sale ou par terminal sont actifs pour ce profil. En mode test, Mollie peut fournir un terminal de test lorsque Point of Sale est actif.',
        es: 'Comprueba en Mollie si los pagos Point of Sale o con terminal están activos para este perfil. En modo de prueba, Mollie puede ofrecer un terminal de prueba cuando Point of Sale está activo.',
      );
    }
    if (status == 'synced') {
      return _t(
        nl: 'Fluxidi heeft de terminalsnapshot opgehaald voor dit Mollie-profiel.',
        en: 'Fluxidi has fetched the terminal snapshot for this Mollie profile.',
        fr: 'Fluxidi a récupéré l’instantané des terminaux pour ce profil Mollie.',
        es: 'Fluxidi ha obtenido la instantánea de terminales para este perfil de Mollie.',
      );
    }
    if (status == 'fetch_failed') {
      return _t(
        nl: 'De opgeslagen terminalsnapshot kon niet opgehaald worden. Probeer opnieuw of synchroniseer terminals later.',
        en: 'The saved terminal snapshot could not be fetched. Try again or sync terminals later.',
        fr: 'L’instantané enregistré des terminaux n’a pas pu être récupéré. Réessayez ou synchronisez les terminaux plus tard.',
        es: 'No se pudo obtener la instantánea guardada de terminales. Inténtalo de nuevo o sincroniza los terminales más tarde.',
      );
    }
    return _t(
      nl: 'Er is nog geen terminalsnapshot opgeslagen. Synchroniseer terminals om te controleren of Mollie-terminals beschikbaar zijn voor dit bedrijf.',
      en: 'No terminal snapshot has been saved yet. Sync terminals to check whether Mollie terminals are available for this company.',
      fr: 'Aucun instantané de terminal n’a encore été enregistré. Synchronisez les terminaux pour vérifier si des terminaux Mollie sont disponibles pour cette entreprise.',
      es: 'Aún no se ha guardado ninguna instantánea de terminales. Sincroniza los terminales para comprobar si hay terminales Mollie disponibles para esta empresa.',
    );
  }

  _SetupStatus _mollieTerminalSetupStatus() {
    final status = _mollieTerminalsStatusCode();
    if (status == 'synced' && _mollieTerminalList().isNotEmpty) {
      return _SetupStatus.complete;
    }
    if (status == 'terminals_scope_missing' || status == 'fetch_failed') {
      return _SetupStatus.attention;
    }
    return _SetupStatus.activationPending;
  }

  Future<void> _loadMollieTerminalsSnapshot({
    bool showErrorSnack = false,
  }) async {
    setState(() {
      _mollieTerminalsLoading = true;
      _mollieTerminalsError = null;
    });
    try {
      final scope = _activeSettingsScopeStrict();
      if (scope == null) {
        debugPrint(
          '[BUSINESS_SETTINGS_SCOPE][SKIP] reason=missing_strict_company_scope action=load_mollie_terminals_snapshot',
        );
        return;
      }
      final data = await fetchCompanyMollieTerminals(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return;
      setState(() {
        _mollieTerminalsSnapshot = data;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mollieTerminalsError = e.toString();
      });
      if (showErrorSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Terminalstatus kon niet geladen worden.',
                en: 'Terminal status could not be loaded.',
                fr: 'Le statut des terminaux n’a pas pu être chargé.',
                es: 'No se pudo cargar el estado de los terminales.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _mollieTerminalsLoading = false);
      }
    }
  }

  Future<void> _syncMollieTerminals() async {
    setState(() {
      _mollieTerminalsSyncLoading = true;
      _mollieTerminalsError = null;
    });
    try {
      final scope = _strictSettingsScopeForAction(
        action: 'sync_mollie_terminals',
      );
      if (scope == null) return;
      final data = await syncCompanyMollieTerminals(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return;
      setState(() {
        _mollieTerminalsSnapshot = data;
      });
      final status = (data['status'] ?? data['error'] ?? data['code'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final message = status == 'terminals_scope_missing'
          ? _t(
              nl: 'Mollie moet opnieuw verbonden worden om terminalrechten toe te voegen.',
              en: 'Mollie must be reconnected to add terminal permissions.',
              fr: 'Mollie doit être reconnecté pour ajouter les droits de terminal.',
              es: 'Hay que volver a conectar Mollie para añadir permisos de terminal.',
            )
          : _t(
              nl: 'Mollie-terminals zijn gesynchroniseerd.',
              en: 'Mollie terminals have been synced.',
              fr: 'Les terminaux Mollie ont été synchronisés.',
              es: 'Los terminales de Mollie se han sincronizado.',
            );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mollieTerminalsError = 'sync_failed';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Mollie-terminals konden niet gesynchroniseerd worden.',
              en: 'Mollie terminals could not be synced.',
              fr: 'Les terminaux Mollie n’ont pas pu être synchronisés.',
              es: 'No se pudieron sincronizar los terminales de Mollie.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _mollieTerminalsSyncLoading = false);
      }
    }
  }

  Future<void> _unlinkMollieTerminal(Map<String, dynamic> terminal) async {
    final terminalId = (terminal['id'] ?? '').toString().trim();
    if (terminalId.isEmpty || _mollieTerminalLinkBusyId != null) return;
    final scope = _strictSettingsScopeForAction(
      action: 'unlink_mollie_terminal',
    );
    if (scope == null) return;
    setState(() => _mollieTerminalLinkBusyId = terminalId);
    try {
      final data = await unlinkCompanyMollieTerminal(
        terminalId: terminalId,
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return;
      setState(() => _mollieTerminalsSnapshot = data);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mollieTerminalLinkCopy(key: 'unlinked_snack', lang: _lang.name),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final blocked = msg.contains('terminal_unlink_blocked_pending_payment');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            blocked
                ? mollieTerminalLinkCopy(
                    key: 'unlink_blocked_pending',
                    lang: _lang.name,
                  )
                : _t(
                    nl: 'Terminal kon niet ontkoppeld worden.',
                    en: 'Terminal could not be unlinked.',
                    fr: 'Le terminal n’a pas pu être déconnecté.',
                    es: 'No se pudo desvincular el terminal.',
                  ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _mollieTerminalLinkBusyId = null);
      }
    }
  }

  Future<void> _relinkMollieTerminal(Map<String, dynamic> terminal) async {
    final terminalId = (terminal['id'] ?? '').toString().trim();
    if (terminalId.isEmpty || _mollieTerminalLinkBusyId != null) return;
    final scope = _strictSettingsScopeForAction(
      action: 'relink_mollie_terminal',
    );
    if (scope == null) return;
    setState(() => _mollieTerminalLinkBusyId = terminalId);
    try {
      final data = await relinkCompanyMollieTerminal(
        terminalId: terminalId,
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return;
      setState(() => _mollieTerminalsSnapshot = data);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mollieTerminalLinkCopy(key: 'relinked_snack', lang: _lang.name),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Terminal kon niet opnieuw gekoppeld worden.',
              en: 'Terminal could not be reconnected.',
              fr: 'Le terminal n’a pas pu être reconnecté.',
              es: 'No se pudo volver a vincular el terminal.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _mollieTerminalLinkBusyId = null);
      }
    }
  }

  Future<void> _forgetMollieTerminal(Map<String, dynamic> terminal) async {
    final terminalId = (terminal['id'] ?? '').toString().trim();
    if (terminalId.isEmpty || _mollieTerminalLinkBusyId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          mollieTerminalLinkCopy(key: 'forget_confirm_title', lang: _lang.name),
        ),
        content: Text(
          mollieTerminalLinkCopy(key: 'forget_confirm_body', lang: _lang.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              mollieTerminalLinkCopy(key: 'forget_cancel', lang: _lang.name),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              mollieTerminalLinkCopy(
                key: 'forget_confirm_action',
                lang: _lang.name,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final scope = _strictSettingsScopeForAction(
      action: 'forget_mollie_terminal',
    );
    if (scope == null) return;
    setState(() => _mollieTerminalLinkBusyId = terminalId);
    try {
      final data = await forgetCompanyMollieTerminal(
        terminalId: terminalId,
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return;
      setState(() => _mollieTerminalsSnapshot = data);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mollieTerminalLinkCopy(key: 'forgotten_snack', lang: _lang.name),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final blocked = msg.contains('terminal_unlink_blocked_pending_payment');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            blocked
                ? mollieTerminalLinkCopy(
                    key: 'forget_blocked_pending',
                    lang: _lang.name,
                  )
                : _t(
                    nl: 'Terminal kon niet uit Fluxidi verwijderd worden.',
                    en: 'Terminal could not be removed from Fluxidi.',
                    fr: 'Le terminal n’a pas pu être supprimé de Fluxidi.',
                    es: 'No se pudo eliminar el terminal de Fluxidi.',
                  ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _mollieTerminalLinkBusyId = null);
      }
    }
  }

  Future<void> _loadGoogleCalendarStatus({bool showErrorSnack = false}) async {
    setState(() {
      _googleCalendarLoading = true;
      _googleCalendarStatusError = null;
    });
    try {
      final scope = _activeSettingsScopeStrict();
      if (scope == null) {
        debugPrint(
          '[BUSINESS_SETTINGS_SCOPE][SKIP] reason=missing_strict_company_scope action=load_google_calendar_status',
        );
        return;
      }
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

  // MOLLIE-ONBOARDING-STATUS-P1: [forceRefresh] is what the "Refresh status"
  // button passes to actually re-verify with Mollie (?refresh=live) instead
  // of re-reading the same cached snapshot. On ANY failure here — network,
  // timeout, or a truthful `status_check: "failed"` from the backend — the
  // previous [_mollieConnectStatus] is left untouched below, so a transient
  // failure can never downgrade an already-confirmed active/complete card.
  Future<void> _loadMollieConnectStatus({
    bool showErrorSnack = false,
    bool forceRefresh = false,
  }) async {
    setState(() {
      _mollieConnectLoading = true;
      _mollieConnectStatusError = null;
    });
    try {
      final scope = _activeSettingsScopeStrict();
      if (scope == null) {
        debugPrint(
          '[BUSINESS_SETTINGS_SCOPE][SKIP] reason=missing_strict_company_scope action=load_mollie_connect_status',
        );
        return;
      }
      final data = await fetchBackendMollieConnectStatus(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _mollieConnectStatus = data;
        if (data['connected'] is bool) {
          _mollieConnected = data['connected'] as bool;
        }
      });
      if (showErrorSnack &&
          forceRefresh &&
          (data['status_check'] ?? '').toString() == 'failed') {
        final permissionMissing =
            (data['status_check_error'] ?? '').toString() ==
            'mollie_onboarding_permission_missing';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              permissionMissing
                  ? _t(
                      nl: 'Mollie is gekoppeld. Verbind Mollie opnieuw om de actuele accountstatus te kunnen controleren.',
                      en: 'Mollie is connected. Reconnect Mollie to verify the current account status.',
                      fr: 'Mollie est connecté. Reconnectez Mollie pour vérifier le statut actuel du compte.',
                      es: 'Mollie está conectado. Vuelve a conectar Mollie para verificar el estado actual de la cuenta.',
                    )
                  : _t(
                      nl: 'Kon Mollie-status niet live verifiëren. De laatst bekende status wordt getoond.',
                      en: 'Could not verify the live Mollie status. Showing the last known status.',
                      fr: 'Impossible de vérifier le statut Mollie en direct. Le dernier statut connu est affiché.',
                      es: 'No se pudo verificar el estado de Mollie en vivo. Se muestra el último estado conocido.',
                    ),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mollieConnectStatusError = e.toString();
      });
      if (showErrorSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Mollie-status kon niet geladen worden.',
                en: 'Mollie status could not be loaded.',
                fr: 'Le statut Mollie n’a pas pu etre charge.',
                es: 'No se pudo cargar el estado de Mollie.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _mollieConnectLoading = false);
      }
    }
  }

  Future<void> _reconnectMollieForTerminals() async {
    await _startMollieConnect();
    if (!mounted) return;
    await _loadMollieConnectStatus();
    if (!mounted) return;
    await _loadMollieTerminalsSnapshot();
  }

  Future<void> _startMollieConnect() async {
    setState(() => _mollieConnectStartLoading = true);
    try {
      final scope = _strictSettingsScopeForAction(
        action: 'start_mollie_connect',
      );
      if (scope == null) return;
      final data = await startBackendMollieConnect(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      final authUrl = (data['auth_url'] ?? data['authUrl'] ?? '')
          .toString()
          .trim();
      if (authUrl.isEmpty) throw Exception('missing_auth_url');
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
              nl: 'Mollie geopend. Rond de koppeling af in je browser en vernieuw daarna de status.',
              en: 'Mollie opened. Finish the connection in your browser, then refresh the status.',
              fr: 'Mollie est ouvert. Terminez la connexion dans votre navigateur, puis actualisez le statut.',
              es: 'Mollie abierto. Termina la conexión en tu navegador y luego actualiza el estado.',
            ),
          ),
        ),
      );
      unawaited(_loadMollieConnectStatus());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Mollie-koppeling kon niet gestart worden.',
              en: 'Mollie connection could not be started.',
              fr: 'La connexion Mollie n’a pas pu etre demarree.',
              es: 'No se pudo iniciar la conexión de Mollie.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _mollieConnectStartLoading = false);
      }
    }
  }

  Future<bool> _confirmMollieConnectDisconnect() async {
    final decision = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            _t(
              nl: 'Mollie loskoppelen?',
              en: 'Disconnect Mollie?',
              fr: 'Deconnecter Mollie ?',
              es: '¿Desconectar Mollie?',
            ),
          ),
          content: Text(
            _t(
              nl: 'Je kunt later opnieuw koppelen. Online betalingen via het eigen Mollie-account zijn in deze fase nog niet actief.',
              en: 'You can reconnect later. Online payments through the own Mollie account are not active in this phase yet.',
              fr: 'Vous pourrez reconnecter plus tard. Les paiements en ligne via le compte Mollie propre ne sont pas encore actifs dans cette phase.',
              es: 'Puedes volver a conectar más tarde. Los pagos online mediante la cuenta Mollie propia aún no están activos en esta fase.',
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
                  fr: 'Deconnecter',
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

  Future<void> _disconnectMollieConnect() async {
    final confirmed = await _confirmMollieConnectDisconnect();
    if (!confirmed || !mounted) return;
    setState(() => _mollieConnectDisconnectLoading = true);
    try {
      final scope = _strictSettingsScopeForAction(
        action: 'disconnect_mollie_connect',
      );
      if (scope == null) return;
      await disconnectBackendMollieConnect(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Mollie is losgekoppeld.',
              en: 'Mollie is disconnected.',
              fr: 'Mollie est deconnecte.',
              es: 'Mollie está desconectado.',
            ),
          ),
        ),
      );
      unawaited(_loadMollieConnectStatus());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Mollie kon niet worden losgekoppeld.',
              en: 'Mollie could not be disconnected.',
              fr: 'Mollie n’a pas pu etre deconnecte.',
              es: 'No se pudo desconectar Mollie.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _mollieConnectDisconnectLoading = false);
      }
    }
  }

  Future<void> _loadBillitIntegrationStatus({
    bool showErrorSnack = false,
  }) async {
    setState(() {
      _billitLoading = true;
      _billitStatusError = null;
    });
    try {
      final scope = _activeSettingsScopeStrict();
      if (scope == null) {
        debugPrint(
          '[BUSINESS_SETTINGS_SCOPE][SKIP] reason=missing_strict_company_scope action=load_billit_status',
        );
        return;
      }
      final data = await fetchCompanyBillitIntegrationStatus(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return;
      setState(() {
        _billitStatus = data;
      });
    } on BillitIntegrationApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _billitStatusError = e.error;
      });
      if (showErrorSnack) {
        final forbidden = e.statusCode == 401 || e.statusCode == 403;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              forbidden
                  ? _t(
                      nl: 'Geen toegang tot Billit-instellingen voor dit bedrijf.',
                      en: 'No access to Billit settings for this company.',
                      fr: 'Pas d’accès aux paramètres Billit pour cette entreprise.',
                      es: 'Sin acceso a la configuración de Billit para esta empresa.',
                    )
                  : _t(
                      nl: 'Billit-status kon niet worden opgehaald.',
                      en: 'Billit status could not be loaded.',
                      fr: 'Le statut Billit n’a pas pu être chargé.',
                      es: 'No se pudo cargar el estado de Billit.',
                    ),
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _billitStatusError = 'network_error';
      });
      if (showErrorSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Billit-status kon niet worden opgehaald.',
                en: 'Billit status could not be loaded.',
                fr: 'Le statut Billit n’a pas pu être chargé.',
                es: 'No se pudo cargar el estado de Billit.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _billitLoading = false);
      }
    }
  }

  // Patch B10a: read the company Billit auto-create setting (company-session
  // auth, no admin token). Read-only; failures leave the switch at its safe
  // default (OFF) without a scary error.
  Future<void> _loadBillitAutoCreateSettings() async {
    setState(() => _billitAutoCreateLoading = true);
    try {
      final scope = _activeSettingsScopeStrict();
      if (scope == null) {
        debugPrint(
          '[BUSINESS_SETTINGS_SCOPE][SKIP] reason=missing_strict_company_scope action=load_billit_auto_create',
        );
        return;
      }
      final data = await fetchCompanyBillitAutoCreateSettings(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return;
      setState(() {
        _billitAutoCreateEnabled =
            data['billit_auto_create_after_paid_business_invoice'] == true;
        _billitAutoCreateLoaded = true;
      });
    } catch (_) {
      // Leave at safe default (OFF); the switch simply reflects false.
    } finally {
      if (mounted) {
        setState(() => _billitAutoCreateLoading = false);
      }
    }
  }

  // Patch B10a: persist the toggle. Save-then-update with rollback on failure;
  // the final state always reflects the backend response. Never calls Billit,
  // Peppol send, or any admin route.
  Future<void> _setBillitAutoCreate(bool next) async {
    if (_billitAutoCreateSaving || _billitAutoCreateLoading) return;
    final previous = _billitAutoCreateEnabled;
    setState(() => _billitAutoCreateSaving = true);
    try {
      final scope = _activeSettingsScopeStrict();
      if (scope == null) {
        debugPrint(
          '[BUSINESS_SETTINGS_SCOPE][SKIP] reason=missing_strict_company_scope action=update_billit_auto_create',
        );
        return;
      }
      final data = await updateCompanyBillitAutoCreateSettings(
        enabled: next,
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return;
      setState(() {
        _billitAutoCreateEnabled =
            data['billit_auto_create_after_paid_business_invoice'] == true;
        _billitAutoCreateLoaded = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Instelling opgeslagen.',
              en: 'Setting saved.',
              fr: 'Paramètre enregistré.',
              es: 'Ajuste guardado.',
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _billitAutoCreateEnabled = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Instelling kon niet worden opgeslagen. Probeer opnieuw.',
              en: 'Setting could not be saved. Please try again.',
              fr: 'Le paramètre n’a pas pu être enregistré. Veuillez réessayer.',
              es: 'No se pudo guardar el ajuste. Inténtalo de nuevo.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _billitAutoCreateSaving = false);
      }
    }
  }

  Future<void> _startBillitConnect() async {
    final configured = _billitStatus?['configured'] == true;
    final connected = _billitStatus?['connected'] == true;
    if (!configured || connected) return;
    final connectUx = _billitCustomerConnectPresentation();
    if (!connectUx.connectButtonEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Billit-koppeling is nog niet beschikbaar: goedkeuring in behandeling.',
              en: 'Billit connection is not available yet: approval is pending.',
              fr: 'La connexion Billit n’est pas encore disponible : approbation en cours.',
              es: 'La conexión con Billit aún no está disponible: aprobación en curso.',
            ),
          ),
        ),
      );
      return;
    }
    setState(() => _billitStartLoading = true);
    try {
      final scope = _strictSettingsScopeForAction(action: 'start_billit_oauth');
      if (scope == null) return;
      final data = await startCompanyBillitOAuth(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      final ok = data['ok'] == true;
      final error = (data['error'] ?? '').toString().trim();
      final authUrl = (data['authorization_url'] ?? '').toString().trim();
      if (!ok || error == 'billit_oauth_not_configured' || authUrl.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                nl: 'Billit-koppeling is nog niet geactiveerd voor Fluxidi.',
                en: 'Billit connection is not activated for Fluxidi yet.',
                fr: 'La connexion Billit n’est pas encore activée pour Fluxidi.',
                es: 'La conexión con Billit aún no está activada para Fluxidi.',
              ),
            ),
          ),
        );
        return;
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
              nl: 'Billit geopend. Rond de koppeling af in je browser en vernieuw daarna de status.',
              en: 'Billit opened. Finish the connection in your browser, then refresh the status.',
              fr: 'Billit ouvert. Terminez la connexion dans votre navigateur, puis actualisez le statut.',
              es: 'Billit abierto. Termina la conexión en tu navegador y luego actualiza el estado.',
            ),
          ),
        ),
      );
      unawaited(_loadBillitIntegrationStatus());
    } on BillitIntegrationApiException catch (e) {
      if (!mounted) return;
      final forbidden = e.statusCode == 401 || e.statusCode == 403;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            forbidden
                ? _t(
                    nl: 'Geen toegang tot Billit-instellingen voor dit bedrijf.',
                    en: 'No access to Billit settings for this company.',
                    fr: 'Pas d’accès aux paramètres Billit pour cette entreprise.',
                    es: 'Sin acceso a la configuración de Billit para esta empresa.',
                  )
                : _t(
                    nl: 'Billit-koppeling kon niet gestart worden.',
                    en: 'Billit connection could not be started.',
                    fr: 'La connexion Billit n’a pas pu être démarrée.',
                    es: 'No se pudo iniciar la conexión de Billit.',
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
              nl: 'Billit-koppeling kon niet gestart worden.',
              en: 'Billit connection could not be started.',
              fr: 'La connexion Billit n’a pas pu être démarrée.',
              es: 'No se pudo iniciar la conexión de Billit.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _billitStartLoading = false);
      }
    }
  }

  Future<bool> _confirmBillitDisconnect() async {
    final decision = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            _t(
              nl: 'Billit loskoppelen?',
              en: 'Disconnect Billit?',
              fr: 'Déconnecter Billit ?',
              es: '¿Desconectar Billit?',
            ),
          ),
          content: Text(
            _t(
              nl: 'Je kunt later opnieuw koppelen. Facturen, creditnota’s en Peppol-verzending via Billit worden daarna pas weer voorbereid zodra je opnieuw koppelt.',
              en: 'You can reconnect later. Invoices, credit notes and Peppol sending via Billit are only prepared again once you reconnect.',
              fr: 'Vous pourrez reconnecter plus tard. Les factures, notes de crédit et l’envoi Peppol via Billit ne seront préparés à nouveau qu’après reconnexion.',
              es: 'Puedes volver a conectar más tarde. Las facturas, notas de crédito y el envío Peppol mediante Billit solo se preparan de nuevo al reconectar.',
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
                  fr: 'Déconnecter',
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

  Future<void> _disconnectBillit() async {
    final connected = _billitStatus?['connected'] == true;
    if (!connected) return;
    final confirmed = await _confirmBillitDisconnect();
    if (!confirmed || !mounted) return;
    setState(() => _billitDisconnectLoading = true);
    try {
      final scope = _strictSettingsScopeForAction(
        action: 'disconnect_billit_oauth',
      );
      if (scope == null) return;
      await disconnectCompanyBillitOAuth(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Billit is losgekoppeld.',
              en: 'Billit is disconnected.',
              fr: 'Billit est déconnecté.',
              es: 'Billit está desconectado.',
            ),
          ),
        ),
      );
      unawaited(_loadBillitIntegrationStatus());
    } on BillitIntegrationApiException catch (e) {
      if (!mounted) return;
      final forbidden = e.statusCode == 401 || e.statusCode == 403;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            forbidden
                ? _t(
                    nl: 'Geen toegang tot Billit-instellingen voor dit bedrijf.',
                    en: 'No access to Billit settings for this company.',
                    fr: 'Pas d’accès aux paramètres Billit pour cette entreprise.',
                    es: 'Sin acceso a la configuración de Billit para esta empresa.',
                  )
                : _t(
                    nl: 'Billit kon niet worden losgekoppeld.',
                    en: 'Billit could not be disconnected.',
                    fr: 'Billit n’a pas pu être déconnecté.',
                    es: 'No se pudo desconectar Billit.',
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
              nl: 'Billit kon niet worden losgekoppeld.',
              en: 'Billit could not be disconnected.',
              fr: 'Billit n’a pas pu être déconnecté.',
              es: 'No se pudo desconectar Billit.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _billitDisconnectLoading = false);
      }
    }
  }

  Future<void> _startGoogleCalendarReconnect() async {
    setState(() => _googleCalendarReconnectLoading = true);
    try {
      final scope = _strictSettingsScopeForAction(
        action: 'start_google_calendar_reconnect',
      );
      if (scope == null) return;
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

  Future<bool> _confirmGoogleCalendarDisconnect() async {
    final decision = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            _t(
              nl: 'Google Calendar loskoppelen?',
              en: 'Disconnect Google Calendar?',
              fr: 'Déconnecter Google Agenda ?',
              es: '¿Desconectar Google Calendar?',
            ),
          ),
          content: Text(
            _t(
              nl: 'Nieuwe boekingen worden niet meer automatisch in Google Calendar geplaatst tot je opnieuw koppelt. Bestaande boekingen en agenda-items blijven behouden.',
              en: 'New bookings will no longer be added automatically to Google Calendar until you reconnect. Existing bookings and calendar events remain unchanged.',
              fr: 'Les nouvelles réservations ne seront plus ajoutées automatiquement à Google Agenda jusqu’à reconnexion. Les réservations et événements existants restent inchangés.',
              es: 'Las nuevas reservas ya no se añadirán automáticamente a Google Calendar hasta que vuelvas a conectar. Las reservas y eventos existentes permanecen sin cambios.',
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
                  fr: 'Déconnecter',
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
      final scope = _strictSettingsScopeForAction(
        action: 'disconnect_google_calendar',
      );
      if (scope == null) return;
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
              fr: 'Google Agenda est déconnecté.',
              es: 'Google Calendar está desconectado.',
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
              fr: 'Google Agenda n’a pas pu être déconnecté.',
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
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _googleCalendarDescription(),
            style: TextStyle(color: _textSecondary, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 10),
          if (calendarId != null)
            Text(
              '${_t(nl: 'Kalender-ID', en: 'Calendar ID', fr: 'ID agenda', es: 'ID de calendario')}: $calendarId',
              style: TextStyle(color: _textSecondary, fontSize: 11.5),
            ),
          if (accountEmail != null)
            Text(
              '${_t(nl: 'Account', en: 'Account', fr: 'Compte', es: 'Cuenta')}: $accountEmail',
              style: TextStyle(color: _textSecondary, fontSize: 11.5),
            ),
          if (lastConnectedAt != null)
            Text(
              '${_t(nl: 'Laatste koppeling', en: 'Last connected', fr: 'Dernière connexion', es: 'Última conexión')}: $lastConnectedAt',
              style: TextStyle(color: _textMuted, fontSize: 11),
            ),
          if (lastDisconnectedAt != null)
            Text(
              '${_t(nl: 'Laatst losgekoppeld', en: 'Last disconnected', fr: 'Dernière déconnexion', es: 'Última desconexión')}: $lastDisconnectedAt',
              style: TextStyle(color: _textMuted, fontSize: 11),
            ),
          if (lastSyncAt != null)
            Text(
              '${_t(nl: 'Laatste sync', en: 'Last sync', fr: 'Dernière synchro', es: 'Última sincronización')}: $lastSyncAt',
              style: TextStyle(color: _textMuted, fontSize: 11),
            ),
          if (lastErrorCode != null)
            Text(
              '${_t(nl: 'Foutcode', en: 'Error code', fr: 'Code erreur', es: 'Código de error')}: $lastErrorCode',
              style: TextStyle(color: _textMuted, fontSize: 11),
            ),
          if (lastErrorAt != null)
            Text(
              '${_t(nl: 'Laatste fout', en: 'Last error', fr: 'Dernière erreur', es: 'Último error')}: $lastErrorAt',
              style: TextStyle(color: _textMuted, fontSize: 11),
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
                      fr: 'Déconnecter',
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

  String _paymentOwnerModeLabel(String mode) {
    switch (mode.trim().toLowerCase()) {
      case 'company_mollie':
        return _t(
          nl: 'Eigen Mollie-account',
          en: 'Own Mollie account',
          fr: 'Compte Mollie propre',
          es: 'Cuenta Mollie propia',
        );
      case 'manual_only':
        return _t(
          nl: 'Alleen handmatig',
          en: 'Manual only',
          fr: 'Manuel uniquement',
          es: 'Solo manual',
        );
      case 'fluxidi_central_demo':
      default:
        return _t(
          nl: 'Fluxidi demo-betaalaccount',
          en: 'Fluxidi demo payment account',
          fr: 'Compte de paiement demo Fluxidi',
          es: 'Cuenta de pago demo de Fluxidi',
        );
    }
  }

  Widget _onlinePaymentsSetupHelpCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _subPanelBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withOpacity(_isDark ? 0.28 : 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              nl: 'Zo stel je online betalingen in',
              en: 'How to set up online payments',
              fr: 'Comment configurer les paiements en ligne',
              es: 'Cómo configurar pagos en línea',
            ),
            style: TextStyle(
              color: _textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              nl:
                  '1. Maak of open je eigen Mollie-account.\n'
                  '2. Vul je bedrijfsgegevens en bankrekening aan in Mollie.\n'
                  '3. Activeer de betaalmethodes die je klanten wilt aanbieden.\n'
                  '4. Koppel daarna je Mollie-account aan Fluxidi.\n'
                  '5. Keer terug naar Fluxidi en vernieuw de betaalstatus.',
              en:
                  '1. Create or open your own Mollie account.\n'
                  '2. Complete your business details and bank account in Mollie.\n'
                  '3. Activate the payment methods you want to offer customers.\n'
                  '4. Then connect your Mollie account to Fluxidi.\n'
                  '5. Return to Fluxidi and refresh the payment status.',
              fr:
                  '1. Créez ou ouvrez votre propre compte Mollie.\n'
                  '2. Complétez vos données d’entreprise et votre compte bancaire dans Mollie.\n'
                  '3. Activez les moyens de paiement que vous souhaitez proposer aux clients.\n'
                  '4. Connectez ensuite votre compte Mollie à Fluxidi.\n'
                  '5. Revenez dans Fluxidi et actualisez le statut des paiements.',
              es:
                  '1. Crea o abre tu propia cuenta Mollie.\n'
                  '2. Completa los datos de empresa y la cuenta bancaria en Mollie.\n'
                  '3. Activa los métodos de pago que quieres ofrecer a tus clientes.\n'
                  '4. Después conecta tu cuenta Mollie con Fluxidi.\n'
                  '5. Vuelve a Fluxidi y actualiza el estado de pagos.',
            ),
            style: TextStyle(color: _textSecondary, fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              nl: 'De betaalmethodes worden beheerd in het Mollie Dashboard. Fluxidi toont alleen betaalopties die door Fluxidi ondersteund worden én voor dit bedrijf beschikbaar of geactiveerd zijn.',
              en: 'Payment methods are managed in the Mollie Dashboard. Fluxidi only shows payment options that are supported by Fluxidi and available or activated for this company.',
              fr: 'Les moyens de paiement sont gérés dans le tableau de bord Mollie. Fluxidi affiche uniquement les options de paiement prises en charge par Fluxidi et disponibles ou activées pour cette entreprise.',
              es: 'Los métodos de pago se gestionan en el panel de Mollie. Fluxidi solo muestra las opciones de pago compatibles con Fluxidi y disponibles o activadas para esta empresa.',
            ),
            style: TextStyle(color: _textMuted, fontSize: 11.5, height: 1.35),
          ),
          const SizedBox(height: 10),
          Text(
            _t(
              nl: 'Betaalopties in Fluxidi',
              en: 'Payment options in Fluxidi',
              fr: 'Options de paiement dans Fluxidi',
              es: 'Opciones de pago en Fluxidi',
            ),
            style: TextStyle(
              color: _textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final label in [
                _t(
                  nl: 'Bancontact',
                  en: 'Bancontact',
                  fr: 'Bancontact',
                  es: 'Bancontact',
                ),
                _t(nl: 'iDEAL', en: 'iDEAL', fr: 'iDEAL', es: 'iDEAL'),
                _t(
                  nl: 'Kaartbetalingen',
                  en: 'Card payments',
                  fr: 'Paiements par carte',
                  es: 'Pagos con tarjeta',
                ),
                _t(
                  nl: 'Apple Pay',
                  en: 'Apple Pay',
                  fr: 'Apple Pay',
                  es: 'Apple Pay',
                ),
                _t(
                  nl: 'Google Pay',
                  en: 'Google Pay',
                  fr: 'Google Pay',
                  es: 'Google Pay',
                ),
                _t(nl: 'PayPal', en: 'PayPal', fr: 'PayPal', es: 'PayPal'),
                _t(nl: 'KBC/CBC', en: 'KBC/CBC', fr: 'KBC/CBC', es: 'KBC/CBC'),
                _t(nl: 'Belfius', en: 'Belfius', fr: 'Belfius', es: 'Belfius'),
              ])
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _isDark ? _accent.withOpacity(0.12) : _inputFill,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _border.withOpacity(_isDark ? 0.5 : 0.85),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              nl: 'Fluxidi ondersteunt online betalingen via je eigen Mollie-account, zoals Bancontact, iDEAL, kaartbetalingen, Apple Pay, Google Pay, PayPal, KBC/CBC en Belfius. Daarnaast kun je betalingen opvolgen via betalen in de wagen, Mollie terminals, QR/EPC-bankoverschrijving, gewone bankoverschrijving en handmatige opvolging.',
              en: 'Fluxidi supports online payments through your own Mollie account, such as Bancontact, iDEAL, card payments, Apple Pay, Google Pay, PayPal, KBC/CBC and Belfius. You can also track payments through pay in the vehicle, Mollie terminals, QR/EPC bank transfer, regular bank transfer and manual follow-up.',
              fr: 'Fluxidi prend en charge les paiements en ligne via votre propre compte Mollie, comme Bancontact, iDEAL, les paiements par carte, Apple Pay, Google Pay, PayPal, KBC/CBC et Belfius. Vous pouvez aussi suivre les paiements via le paiement dans le véhicule, les terminaux Mollie, le virement QR/EPC, le virement bancaire classique et le suivi manuel.',
              es: 'Fluxidi admite pagos en línea mediante tu propia cuenta Mollie, como Bancontact, iDEAL, pagos con tarjeta, Apple Pay, Google Pay, PayPal, KBC/CBC y Belfius. También puedes hacer seguimiento de pagos mediante pago en el vehículo, terminales Mollie, transferencia bancaria QR/EPC, transferencia bancaria normal y seguimiento manual.',
            ),
            style: TextStyle(
              color: _textSecondary,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              nl: 'De exacte beschikbaarheid hangt af van je land, je Mollie-account, bedrijfsverificatie en de betaalmethodes die voor dit bedrijf geactiveerd zijn.',
              en: 'Exact availability depends on your country, Mollie account, business verification and the payment methods activated for this company.',
              fr: 'La disponibilité exacte dépend de votre pays, de votre compte Mollie, de la vérification de l’entreprise et des moyens de paiement activés pour cette entreprise.',
              es: 'La disponibilidad exacta depende de tu país, tu cuenta Mollie, la verificación de empresa y los métodos de pago activados para esta empresa.',
            ),
            style: TextStyle(color: _textMuted, fontSize: 11.5, height: 1.35),
          ),
        ],
      ),
    );
  }

  // MOLLIE-ONBOARDING-STATUS-P1
  //
  // ROOT CAUSE (proven): the card status below used to be a single hardcoded
  // ternary — `mollieConnected ? _SetupStatus.activationPending : ...` — so
  // EVERY connected Mollie account, LIVE or TEST, fully onboarded or not,
  // unconditionally showed "Activation pending". It never looked at
  // onboarding/capability data at all. Separately, the one signal that WAS
  // captured (`onboarding_status`) was always null server-side because it was
  // read from the wrong Mollie endpoint (`/v2/organizations/me`, which has no
  // onboarding field) instead of the dedicated Onboarding API
  // (`/v2/onboarding/me`) — see workers/booking/modules/mollie_connect.js.
  // "Refresh status" never re-asked Mollie either, so the bug could never
  // self-heal.
  //
  // Fix: account connection (this card's header chip) and online-payment-
  // method activation (its own row below) are resolved independently via
  // `resolveMollieAccountConnection` / `resolveOnlinePaymentMethods`, driven
  // by the authoritative `can_receive_payments` signal now fetched from the
  // correct Mollie endpoint (see mollie_connect.js) and — on explicit
  // "Refresh status" — re-verified live without ever touching credentials,
  // OAuth, the webhook, or the payment flow.
  MollieAccountConnection _mollieAccountConnection() {
    return resolveMollieAccountConnection(
      connected: _mollieConnectConnected,
      statusCode: _mollieConnectStatusCode(),
      mollieMode: _mollieConnectStatusField('mollie_mode'),
    );
  }

  bool? _mollieCanReceivePayments() {
    final raw = _mollieConnectStatus?['can_receive_payments'];
    return raw is bool ? raw : null;
  }

  bool _mollieStatusCheckFailed() {
    return (_mollieConnectStatus?['status_check'] ?? '').toString() == 'failed';
  }

  /// MOLLIE-ONBOARDING-READ-SCOPE-P0-1: live onboarding/me returned 403
  /// (missing onboarding.read). Distinct from a transient lookup failure.
  bool _mollieOnboardingPermissionMissing() {
    final live = (_mollieConnectStatus?['status_check_error'] ?? '').toString();
    final last = (_mollieConnectStatus?['last_status_check_error'] ?? '')
        .toString();
    return live == 'mollie_onboarding_permission_missing' ||
        last == 'mollie_onboarding_permission_missing';
  }

  /// Only a true "lookup failed" state (nothing authoritative to show at
  /// all) when the latest check errored AND there is neither a
  /// can_receive_payments signal nor an onboarding_status to fall back on.
  /// A transient failure that still has prior good data must keep showing
  /// that data — never downgrade to "failed".
  bool _mollieOnlineMethodsLookupFailed() {
    if (_mollieOnboardingPermissionMissing()) return false;
    return _mollieStatusCheckFailed() &&
        _mollieCanReceivePayments() == null &&
        _mollieConnectStatusField('onboarding_status') == null;
  }

  OnlinePaymentMethodsStatus _onlinePaymentMethodsStatus() {
    return resolveOnlinePaymentMethods(
      connected: _mollieConnectConnected,
      onboardingStatus: _mollieConnectStatusField('onboarding_status'),
      canReceivePayments: _mollieCanReceivePayments(),
      lookupFailed: _mollieOnlineMethodsLookupFailed(),
      statusCheckPermissionMissing: _mollieOnboardingPermissionMissing(),
    );
  }

  String _onlinePaymentMethodsLabel(OnlinePaymentMethodsStatus s) {
    switch (s) {
      case OnlinePaymentMethodsStatus.active:
        return _t(nl: 'Actief', en: 'Active', fr: 'Actif', es: 'Activo');
      case OnlinePaymentMethodsStatus.partiallyActive:
        return _t(
          nl: 'Gedeeltelijk actief',
          en: 'Partially active',
          fr: 'Partiellement actif',
          es: 'Parcialmente activo',
        );
      case OnlinePaymentMethodsStatus.actionRequired:
        return _t(
          nl: 'Actie vereist',
          en: 'Action required',
          fr: 'Action requise',
          es: 'Acción requerida',
        );
      case OnlinePaymentMethodsStatus.activationPending:
        return _t(
          nl: 'Activering volgt',
          en: 'Activation pending',
          fr: 'Activation à venir',
          es: 'Activación pendiente',
        );
      case OnlinePaymentMethodsStatus.noneActive:
        return _t(
          nl: 'Geen actief',
          en: 'None active',
          fr: 'Aucun actif',
          es: 'Ninguno activo',
        );
      case OnlinePaymentMethodsStatus.lookupFailed:
        return _t(
          nl: 'Status kon niet gecontroleerd worden',
          en: 'Could not verify status',
          fr: 'Statut non vérifiable',
          es: 'No se pudo verificar el estado',
        );
      case OnlinePaymentMethodsStatus.statusCheckPermissionMissing:
        return _t(
          nl: 'Statuscontrole vereist herkoppeling',
          en: 'Status check needs reconnect',
          fr: 'Vérification : reconnecter',
          es: 'Verificación requiere reconexión',
        );
    }
  }

  Widget _paymentOwnershipCard() {
    final demoActive = _paymentOwnerMode == 'fluxidi_central_demo';
    final mollieConnected = _mollieConnectConnected;
    final accountConnection = _mollieAccountConnection();
    final onlineMethods = _onlinePaymentMethodsStatus();
    final _SetupStatus cardStatus;
    switch (accountConnection) {
      case MollieAccountConnection.disconnected:
        cardStatus = demoActive
            ? _SetupStatus.attention
            : _SetupStatus.incomplete;
        break;
      case MollieAccountConnection.reconnectRequired:
        cardStatus = _SetupStatus.attention;
        break;
      case MollieAccountConnection.connectedLive:
      case MollieAccountConnection.connectedTest:
        switch (onlineMethods) {
          case OnlinePaymentMethodsStatus.active:
          case OnlinePaymentMethodsStatus.partiallyActive:
            cardStatus = _SetupStatus.complete;
            break;
          case OnlinePaymentMethodsStatus.activationPending:
            cardStatus = _SetupStatus.activationPending;
            break;
          case OnlinePaymentMethodsStatus.actionRequired:
          case OnlinePaymentMethodsStatus.noneActive:
          case OnlinePaymentMethodsStatus.lookupFailed:
          case OnlinePaymentMethodsStatus.statusCheckPermissionMissing:
            cardStatus = _SetupStatus.attention;
            break;
        }
        break;
    }
    final mollieMode = _mollieConnectStatusField('mollie_mode');
    final onboardingStatus = _mollieConnectStatusField('onboarding_status');
    final lastConnectedAt = _mollieConnectStatusField('last_connected_at');
    final lastErrorCode = _mollieConnectStatusField('last_error_code');
    return _collapsibleSettingsCard(
      id: 'payment_ownership',
      icon: Icons.account_balance_wallet_outlined,
      title: _t(
        nl: 'Betalingen ontvangen',
        en: 'Receive payments',
        fr: 'Recevoir les paiements',
        es: 'Recibir pagos',
      ),
      subtitle: _paymentOwnerModeLabel(_paymentOwnerMode),
      status: cardStatus,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (demoActive)
            Text(
              _t(
                nl: 'Demo-betaalmodus actief. Voor productie koppel je het eigen Mollie-account van dit bedrijf, zodat betalingen rechtstreeks onder de juiste bedrijfsaccount verlopen.',
                en: 'Demo payment mode is active. For production, connect this company’s own Mollie account so payments are processed under the correct business account.',
                fr: 'Le mode de paiement démo est actif. Pour la production, connectez le compte Mollie propre à cette entreprise afin que les paiements soient traités sous le bon compte professionnel.',
                es: 'El modo de pago de demostración está activo. Para producción, conecta la cuenta Mollie propia de esta empresa para que los pagos se procesen bajo la cuenta empresarial correcta.',
              ),
              style: TextStyle(color: _textSecondary, height: 1.45),
            ),
          if (_mollieConnectLoading && _mollieConnectStatus == null)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          const SizedBox(height: 12),
          _onlinePaymentsSetupHelpCard(),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  _mollieConnectStatusLabel(),
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              buildMollieProviderLogo(
                isDarkSurface: _isDark,
                height: 14,
                width: 52,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _mollieConnectDescription(),
            style: TextStyle(color: _textSecondary, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 12),
          _paymentOwnershipInfoRow(
            _t(
              nl: 'Betaalmodus',
              en: 'Payment owner mode',
              fr: 'Mode de paiement',
              es: 'Modo de pago',
            ),
            _paymentOwnerModeLabel(_paymentOwnerMode),
          ),
          _paymentOwnershipInfoRow(
            _t(
              nl: 'Mollie gekoppeld',
              en: 'Mollie connected',
              fr: 'Mollie connecte',
              es: 'Mollie conectado',
            ),
            mollieConnected
                ? _t(nl: 'Ja', en: 'Yes', fr: 'Oui', es: 'Si')
                : _t(nl: 'Nee', en: 'No', fr: 'Non', es: 'No'),
          ),
          _paymentOwnershipInfoRow(
            _t(nl: 'Status', en: 'Status', fr: 'Statut', es: 'Estado'),
            _mollieConnectStatusCode(),
          ),
          if (mollieConnected)
            _paymentOwnershipInfoRow(
              _t(
                nl: 'Online betaalmethodes',
                en: 'Online payment methods',
                fr: 'Moyens de paiement en ligne',
                es: 'Métodos de pago online',
              ),
              _onlinePaymentMethodsLabel(onlineMethods),
            ),
          if (mollieMode != null)
            _paymentOwnershipInfoRow(
              _t(
                nl: 'Mollie-modus',
                en: 'Mollie mode',
                fr: 'Mode Mollie',
                es: 'Modo Mollie',
              ),
              _mollieModeLabel(mollieMode),
            ),
          if (onboardingStatus != null)
            _paymentOwnershipInfoRow(
              _t(
                nl: 'Onboarding',
                en: 'Onboarding',
                fr: 'Onboarding',
                es: 'Onboarding',
              ),
              onboardingStatus,
            ),
          if (lastConnectedAt != null)
            _paymentOwnershipInfoRow(
              _t(
                nl: 'Laatst gekoppeld',
                en: 'Last connected',
                fr: 'Derniere connexion',
                es: 'Última conexión',
              ),
              lastConnectedAt,
            ),
          if (lastErrorCode != null)
            _paymentOwnershipInfoRow(
              _t(
                nl: 'Laatste fout',
                en: 'Last error',
                fr: 'Derniere erreur',
                es: 'Último error',
              ),
              lastErrorCode,
            ),
          _paymentOwnershipInfoRow(
            _t(
              nl: 'Demomodus',
              en: 'Demo mode',
              fr: 'Mode demo',
              es: 'Modo demo',
            ),
            _paymentDemoMode
                ? _t(nl: 'Ja', en: 'Yes', fr: 'Oui', es: 'Si')
                : _t(nl: 'Nee', en: 'No', fr: 'Non', es: 'No'),
          ),
          const SizedBox(height: 12),
          // MOLLIE-ONBOARDING-STATUS-P1 / MOLLIE-ONBOARDING-READ-SCOPE-P0-1:
          // failed LIVE re-verification is reported truthfully; permission-
          // missing (403 / onboarding.read) asks for reconnect without
          // claiming payments are disabled or activation is pending.
          if (_mollieOnboardingPermissionMissing())
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _t(
                  nl: 'Mollie is gekoppeld. Verbind Mollie opnieuw om de actuele accountstatus te kunnen controleren.',
                  en: 'Mollie is connected. Reconnect Mollie to verify the current account status.',
                  fr: 'Mollie est connecté. Reconnectez Mollie pour vérifier le statut actuel du compte.',
                  es: 'Mollie está conectado. Vuelve a conectar Mollie para verificar el estado actual de la cuenta.',
                ),
                style: TextStyle(
                  color: _textMuted,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            )
          else if (_mollieStatusCheckFailed())
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _t(
                  nl: 'Kon de laatste Mollie-verificatie niet uitvoeren. De status hierboven is de laatst bekende, bevestigde status.',
                  en: 'Could not complete the latest live Mollie verification. The status above is the last known, confirmed status.',
                  fr: 'La dernière vérification Mollie en direct a échoué. Le statut ci-dessus est le dernier statut connu et confirmé.',
                  es: 'No se pudo completar la última verificación en vivo de Mollie. El estado anterior es el último estado confirmado conocido.',
                ),
                style: TextStyle(
                  color: _textMuted,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ),
          if (_mollieConnectStatusError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _t(
                  nl: 'Mollie-status kon niet geladen worden.',
                  en: 'Mollie status could not be loaded.',
                  fr: 'Le statut Mollie n’a pas pu etre charge.',
                  es: 'No se pudo cargar el estado de Mollie.',
                ),
                style: TextStyle(color: _danger, fontSize: 12),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed:
                    (_mollieConnectStartLoading ||
                        _mollieConnectDisconnectLoading)
                    ? null
                    : _startMollieConnect,
                icon: _mollieConnectStartLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_outlined),
                label: Text(
                  mollieConnected
                      ? (_mollieOnboardingPermissionMissing()
                            ? _t(
                                nl: 'Opnieuw verbinden voor statuscontrole',
                                en: 'Reconnect for status check',
                                fr: 'Reconnecter pour le statut',
                                es: 'Reconectar para verificar estado',
                              )
                            : _t(
                                nl: 'Opnieuw koppelen',
                                en: 'Reconnect',
                                fr: 'Reconnecter',
                                es: 'Volver a conectar',
                              ))
                      : _t(
                          nl: 'Mollie koppelen',
                          en: 'Connect Mollie',
                          fr: 'Connecter Mollie',
                          es: 'Conectar Mollie',
                        ),
                ),
              ),
              if (mollieConnected)
                OutlinedButton.icon(
                  onPressed: _mollieConnectDisconnectLoading
                      ? null
                      : _disconnectMollieConnect,
                  icon: _mollieConnectDisconnectLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link_off_outlined),
                  label: Text(
                    _t(
                      nl: 'Mollie ontkoppelen',
                      en: 'Disconnect Mollie',
                      fr: 'Deconnecter Mollie',
                      es: 'Desconectar Mollie',
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _mollieConnectLoading
                    ? null
                    : () => _loadMollieConnectStatus(
                        showErrorSnack: true,
                        forceRefresh: true,
                      ),
                icon: _mollieConnectLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_outlined),
                label: Text(
                  _t(
                    nl: 'Status vernieuwen',
                    en: 'Refresh status',
                    fr: 'Actualiser le statut',
                    es: 'Actualizar estado',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paymentOwnershipInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(color: _textMuted, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(color: _textPrimary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  String _billitStatusField(String key) {
    final raw = (_billitStatus?[key] ?? '').toString().trim();
    return raw;
  }

  BillitCustomerConnectPresentation _billitCustomerConnectPresentation() {
    final environment = _billitStatusField('environment');
    final env = environment.isEmpty ? 'sandbox' : environment;
    // Server-authoritative only. Never unlock sandbox from a client dart-define.
    final allowSandbox =
        _billitStatus?['company_sandbox_oauth_allowed'] == true;
    final productionConnectEnabled =
        env.toLowerCase() == 'production' &&
        _billitStatus?['customer_connect_allowed'] == true;
    return resolveBillitCustomerConnectPresentation(
      configured: _billitStatus?['configured'] == true,
      connected: _billitStatus?['connected'] == true,
      environment: env,
      allowSandboxConnect: allowSandbox,
      productionConnectEnabled: productionConnectEnabled,
    );
  }

  ({String label, _SetupStatus status}) _billitStatusDescriptor() {
    final configured = _billitStatus?['configured'] == true;
    final connected = _billitStatus?['connected'] == true;
    final statusCode = _billitStatusField('status');
    final connectUx = _billitCustomerConnectPresentation();
    if (connected) {
      return (
        label: _t(
          nl: 'Gekoppeld',
          en: 'Connected',
          fr: 'Connecté',
          es: 'Conectado',
        ),
        status: _SetupStatus.complete,
      );
    }
    if (connectUx.mode == BillitCustomerConnectMode.productionApprovalPending) {
      return (
        label: _t(
          nl: 'Billit-goedkeuring in behandeling',
          en: 'Billit approval pending',
          fr: 'Approbation Billit en cours',
          es: 'Aprobación de Billit en curso',
        ),
        status: _SetupStatus.activationPending,
      );
    }
    if (statusCode == 'error') {
      return (
        label: _t(
          nl: 'Aandacht nodig',
          en: 'Needs attention',
          fr: 'Attention requise',
          es: 'Requiere atención',
        ),
        status: _SetupStatus.attention,
      );
    }
    if (statusCode == 'authorization_started') {
      return (
        label: _t(
          nl: 'Koppeling gestart',
          en: 'Connection started',
          fr: 'Connexion démarrée',
          es: 'Conexión iniciada',
        ),
        status: _SetupStatus.attention,
      );
    }
    if (configured && connectUx.connectButtonEnabled) {
      return (
        label: _t(
          nl: 'Klaar om te koppelen',
          en: 'Ready to connect',
          fr: 'Prêt à connecter',
          es: 'Listo para conectar',
        ),
        status: _SetupStatus.incomplete,
      );
    }
    if (configured) {
      return (
        label: _t(
          nl: 'Billit-goedkeuring in behandeling',
          en: 'Billit approval pending',
          fr: 'Approbation Billit en cours',
          es: 'Aprobación de Billit en curso',
        ),
        status: _SetupStatus.activationPending,
      );
    }
    return (
      label: _t(
        nl: 'Nog niet geconfigureerd',
        en: 'Not configured yet',
        fr: 'Pas encore configuré',
        es: 'Aún no configurado',
      ),
      status: _SetupStatus.comingSoon,
    );
  }

  Widget _billitIntegrationCard() {
    final configured = _billitStatus?['configured'] == true;
    final connected = _billitStatus?['connected'] == true;
    final descriptor = _billitStatusDescriptor();
    final connectUx = _billitCustomerConnectPresentation();
    final environment = _billitStatusField('environment');
    final connectedAt = _billitStatusField('connected_at');
    final updatedAt = _billitStatusField('updated_at');
    final lastErrorCode = _billitStatusField('last_error_code');
    final loadingInitial = _billitLoading && _billitStatus == null;
    final busy = _billitStartLoading || _billitDisconnectLoading;
    final connectEnabled =
        configured && !connected && !busy && connectUx.connectButtonEnabled;
    return _collapsibleSettingsCard(
      id: 'billit_peppol',
      anchorKey: _sectionAnchorKeys['billit_peppol'],
      icon: Icons.receipt_long_outlined,
      title: _t(
        nl: 'Billit & Peppol',
        en: 'Billit & Peppol',
        fr: 'Billit & Peppol',
        es: 'Billit y Peppol',
      ),
      subtitle: descriptor.label,
      status: descriptor.status,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              nl: 'Koppel je eigen Billit-account om facturen, creditnota’s en Peppol-verzending vanuit Fluxidi voor te bereiden. Lokale Fluxidi-facturen en PDF’s blijven beschikbaar zonder Billit.',
              en: 'Connect your own Billit account to prepare invoices, credit notes and Peppol sending from Fluxidi. Local Fluxidi invoices and PDFs remain available without Billit.',
              fr: 'Connectez votre propre compte Billit pour préparer factures, notes de crédit et envoi Peppol depuis Fluxidi. Les factures et PDF Fluxidi locaux restent disponibles sans Billit.',
              es: 'Conecta tu propia cuenta de Billit para preparar facturas, notas de crédito y envío Peppol desde Fluxidi. Las facturas y PDF locales de Fluxidi siguen disponibles sin Billit.',
            ),
            style: TextStyle(color: _textSecondary, height: 1.45),
          ),
          if (connectUx.showApprovalPendingBanner)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _subPanelBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t(
                        nl: 'Billit-goedkeuring in behandeling',
                        en: 'Billit approval pending',
                        fr: 'Approbation Billit en cours',
                        es: 'Aprobación de Billit en curso',
                      ),
                      style: TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _t(
                        nl: 'De productie-integratie wordt momenteel door Billit beoordeeld. Na goedkeuring kan je hier je eigen Billit-account koppelen.',
                        en: 'The production integration is currently being reviewed by Billit. After approval you can connect your own Billit account here.',
                        fr: 'L’intégration de production est actuellement examinée par Billit. Après approbation, vous pourrez connecter votre propre compte Billit ici.',
                        es: 'Billit está revisando actualmente la integración de producción. Tras la aprobación podrás conectar aquí tu propia cuenta de Billit.',
                      ),
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 12.2,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (connectUx.showSandboxInternalHint)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _t(
                  nl: 'Interne Billit-sandbox',
                  en: 'Internal Billit sandbox',
                  fr: 'Sandbox Billit interne',
                  es: 'Sandbox interno de Billit',
                ),
                style: TextStyle(color: _textSecondary, fontSize: 12),
              ),
            ),
          if (loadingInitial)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          const SizedBox(height: 12),
          _paymentOwnershipInfoRow(
            _t(nl: 'Status', en: 'Status', fr: 'Statut', es: 'Estado'),
            descriptor.label,
          ),
          if (environment.isNotEmpty &&
              (connected || connectUx.connectButtonEnabled))
            _paymentOwnershipInfoRow(
              _t(
                nl: 'Omgeving',
                en: 'Environment',
                fr: 'Environnement',
                es: 'Entorno',
              ),
              environment,
            ),
          if (connectedAt.isNotEmpty)
            _paymentOwnershipInfoRow(
              _t(
                nl: 'Gekoppeld op',
                en: 'Connected at',
                fr: 'Connecté le',
                es: 'Conectado el',
              ),
              connectedAt,
            ),
          if (updatedAt.isNotEmpty)
            _paymentOwnershipInfoRow(
              _t(
                nl: 'Laatst bijgewerkt',
                en: 'Last updated',
                fr: 'Dernière mise à jour',
                es: 'Última actualización',
              ),
              updatedAt,
            ),
          if (lastErrorCode.isNotEmpty)
            _paymentOwnershipInfoRow(
              _t(
                nl: 'Laatste fout',
                en: 'Last error',
                fr: 'Dernière erreur',
                es: 'Último error',
              ),
              lastErrorCode,
            ),
          if (!configured && !connectUx.showApprovalPendingBanner)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                _t(
                  nl: 'Fluxidi wacht nog op de Billit OAuth-gegevens. De koppeling wordt actief zodra deze zijn ingesteld.',
                  en: 'Fluxidi is still waiting for the Billit OAuth credentials. The connection becomes available once these are set.',
                  fr: 'Fluxidi attend encore les identifiants OAuth Billit. La connexion sera disponible dès qu’ils seront configurés.',
                  es: 'Fluxidi aún espera las credenciales OAuth de Billit. La conexión estará disponible una vez configuradas.',
                ),
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          if (_billitStatusError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                _billitStatusError == 'forbidden'
                    ? _t(
                        nl: 'Geen toegang tot Billit-instellingen voor dit bedrijf.',
                        en: 'No access to Billit settings for this company.',
                        fr: 'Pas d’accès aux paramètres Billit pour cette entreprise.',
                        es: 'Sin acceso a la configuración de Billit para esta empresa.',
                      )
                    : _t(
                        nl: 'Billit-status kon niet worden opgehaald.',
                        en: 'Billit status could not be loaded.',
                        fr: 'Le statut Billit n’a pas pu être chargé.',
                        es: 'No se pudo cargar el estado de Billit.',
                      ),
                style: TextStyle(color: _danger, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          _billitAutoCreateSwitchRow(),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _billitLoading
                    ? null
                    : () => _loadBillitIntegrationStatus(showErrorSnack: true),
                icon: _billitLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_outlined),
                label: Text(
                  _t(
                    nl: 'Status vernieuwen',
                    en: 'Refresh status',
                    fr: 'Actualiser le statut',
                    es: 'Actualizar estado',
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: connectEnabled ? _startBillitConnect : null,
                icon: _billitStartLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_outlined),
                label: Text(
                  _t(
                    nl: 'Billit koppelen',
                    en: 'Connect Billit',
                    fr: 'Connecter Billit',
                    es: 'Conectar Billit',
                  ),
                ),
              ),
              if (connected)
                OutlinedButton.icon(
                  onPressed: _billitDisconnectLoading
                      ? null
                      : _disconnectBillit,
                  icon: _billitDisconnectLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link_off_outlined),
                  label: Text(
                    _t(
                      nl: 'Koppeling verbreken',
                      en: 'Disconnect',
                      fr: 'Déconnecter',
                      es: 'Desconectar',
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // Patch B10a: compact switch to let a company enable/disable automatic Billit
  // invoice preparation after a paid business ride. Peppol sending stays manual.
  Widget _billitAutoCreateSwitchRow() {
    final busy = _billitAutoCreateLoading || _billitAutoCreateSaving;
    final showSpinner =
        (_billitAutoCreateLoading && !_billitAutoCreateLoaded) ||
        _billitAutoCreateSaving;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _subPanelBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 10),
                child: Icon(
                  Icons.receipt_long_outlined,
                  size: 20,
                  color: _accent,
                ),
              ),
              Expanded(
                child: Text(
                  _t(
                    nl: 'Billit-facturen automatisch klaarzetten',
                    en: 'Automatically prepare Billit invoices',
                    fr: 'Préparer automatiquement les factures Billit',
                    es: 'Preparar automáticamente facturas en Billit',
                  ),
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (showSpinner)
                const Padding(
                  padding: EdgeInsets.only(right: 6, top: 4),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              Switch(
                value: _billitAutoCreateEnabled,
                onChanged: busy ? null : (v) => _setBillitAutoCreate(v),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _t(
              nl: 'Fluxidi zet na een betaalde zakelijke rit automatisch een factuur klaar in Billit. Peppol-verzending blijft handmatig. Controleer altijd klantgegevens, btw-gegevens en bedragen vóór verzending. Op Billit zijn de voorwaarden en het privacybeleid van Billit van toepassing.',
              en: 'After a paid business ride, Fluxidi can automatically prepare an invoice in Billit. Peppol sending remains manual. Always check customer details, VAT details and amounts before sending. Billit’s terms and privacy policy apply to the use of Billit.',
              fr: 'Après une course professionnelle payée, Fluxidi peut préparer automatiquement une facture dans Billit. L’envoi Peppol reste manuel. Vérifiez toujours les données client, les données TVA et les montants avant l’envoi. Les conditions et la politique de confidentialité de Billit s’appliquent à l’utilisation de Billit.',
              es: 'Después de un viaje empresarial pagado, Fluxidi puede preparar automáticamente una factura en Billit. El envío por Peppol sigue siendo manual. Compruebe siempre los datos del cliente, los datos de IVA y los importes antes de enviar. Se aplican las condiciones y la política de privacidad de Billit.',
            ),
            style: TextStyle(color: _textSecondary, fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 6),
          Text(
            _billitAutoCreateEnabled
                ? _t(
                    nl: 'Automatisch klaarzetten staat aan. Peppol verzenden blijft handmatig.',
                    en: 'Automatic preparation is on. Peppol sending stays manual.',
                    fr: 'La préparation automatique est activée. L’envoi Peppol reste manuel.',
                    es: 'La preparación automática está activada. El envío por Peppol sigue siendo manual.',
                  )
                : _t(
                    nl: 'Automatisch klaarzetten staat uit.',
                    en: 'Automatic preparation is off.',
                    fr: 'La préparation automatique est désactivée.',
                    es: 'La preparación automática está desactivada.',
                  ),
            style: TextStyle(
              color: _textMuted,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mollieTerminalSetupHelpCard() {
    const assetPath = 'assets/fluxidi/payments/mollie_terminal_setup.png';
    final isTabletLayout = MediaQuery.sizeOf(context).shortestSide >= 600;

    Widget stepsContent() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              nl: 'Zo koppel je Mollie terminals',
              en: 'How to connect Mollie terminals',
              fr: 'Comment connecter les terminaux Mollie',
              es: 'Cómo conectar terminales Mollie',
            ),
            style: TextStyle(
              color: _textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              nl:
                  '1. Open je eigen Mollie Dashboard.\n'
                  '2. Ga naar In-person betalingen.\n'
                  '3. Kies een terminaloptie: koop een terminal, activeer de Tap app of gebruik Tap to Pay.\n'
                  '4. Installeer of activeer de Mollie-app op je toestel.\n'
                  '5. Verbind het toestel met het juiste Mollie-profiel.\n'
                  '6. Keer terug naar Fluxidi en klik op Terminals synchroniseren.',
              en:
                  '1. Open your own Mollie Dashboard.\n'
                  '2. Go to In-person payments.\n'
                  '3. Choose a terminal option: buy a terminal, activate the Tap app or use Tap to Pay.\n'
                  '4. Install or activate the Mollie app on your device.\n'
                  '5. Connect the device to the correct Mollie profile.\n'
                  '6. Return to Fluxidi and tap Synchronize terminals.',
              fr:
                  '1. Ouvrez votre propre tableau de bord Mollie.\n'
                  '2. Allez dans Paiements en personne.\n'
                  '3. Choisissez une option : acheter un terminal, activer l’application Tap ou utiliser Tap to Pay.\n'
                  '4. Installez ou activez l’application Mollie sur votre appareil.\n'
                  '5. Connectez l’appareil au bon profil Mollie.\n'
                  '6. Revenez dans Fluxidi et appuyez sur Synchroniser les terminaux.',
              es:
                  '1. Abre tu propio panel de Mollie.\n'
                  '2. Ve a Pagos presenciales.\n'
                  '3. Elige una opción: comprar un terminal, activar la app Tap o usar Tap to Pay.\n'
                  '4. Instala o activa la app de Mollie en tu dispositivo.\n'
                  '5. Conecta el dispositivo al perfil de Mollie correcto.\n'
                  '6. Vuelve a Fluxidi y pulsa Sincronizar terminales.',
            ),
            style: TextStyle(color: _textSecondary, fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              nl: 'Fluxidi bewaart geen Mollie-wachtwoord. Het bedrijf beheert terminals en activatie via het eigen Mollie-account.',
              en: 'Fluxidi does not store your Mollie password. The company manages terminal activation through its own Mollie account.',
              fr: 'Fluxidi ne stocke pas votre mot de passe Mollie. L’entreprise gère l’activation des terminaux via son propre compte Mollie.',
              es: 'Fluxidi no guarda tu contraseña de Mollie. La empresa gestiona la activación de terminales desde su propia cuenta de Mollie.',
            ),
            style: TextStyle(color: _textMuted, fontSize: 11.5, height: 1.35),
          ),
          const SizedBox(height: 10),
          Text(
            _t(
              nl: 'Ondersteunde betaalkaarten en wallets',
              en: 'Supported payment cards and wallets',
              fr: 'Cartes et wallets pris en charge',
              es: 'Tarjetas y wallets compatibles',
            ),
            style: TextStyle(
              color: _textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _t(
              nl: 'Klanten kunnen in de wagen betalen met ondersteunde betaalkaarten en wallets, zoals Visa, Mastercard/Maestro, Visa Electron, V Pay, Apple Pay, Google Pay en Samsung Pay. Afhankelijk van het Mollie-account, het land, het terminaltype en de geactiveerde betaalmethodes kunnen ook kaarten zoals American Express, JCB, UnionPay, Discover en Diners Club beschikbaar zijn.',
              en: 'Customers can pay in the vehicle with supported payment cards and wallets, such as Visa, Mastercard/Maestro, Visa Electron, V Pay, Apple Pay, Google Pay and Samsung Pay. Depending on the Mollie account, country, terminal type and activated payment methods, cards such as American Express, JCB, UnionPay, Discover and Diners Club may also be available.',
              fr: 'Les clients peuvent payer dans le véhicule avec les cartes et wallets pris en charge, comme Visa, Mastercard/Maestro, Visa Electron, V Pay, Apple Pay, Google Pay et Samsung Pay. Selon le compte Mollie, le pays, le type de terminal et les moyens de paiement activés, des cartes comme American Express, JCB, UnionPay, Discover et Diners Club peuvent également être disponibles.',
              es: 'Los clientes pueden pagar en el vehículo con tarjetas y wallets compatibles, como Visa, Mastercard/Maestro, Visa Electron, V Pay, Apple Pay, Google Pay y Samsung Pay. Según la cuenta Mollie, el país, el tipo de terminal y los métodos de pago activados, también pueden estar disponibles tarjetas como American Express, JCB, UnionPay, Discover y Diners Club.',
            ),
            style: TextStyle(color: _textMuted, fontSize: 11.5, height: 1.35),
          ),
        ],
      );
    }

    Widget illustration() {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          assetPath,
          fit: BoxFit.cover,
          width: isTabletLayout ? 148 : double.infinity,
          height: isTabletLayout ? 112 : 120,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _subPanelBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withOpacity(_isDark ? 0.28 : 0.18)),
      ),
      child: isTabletLayout
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                illustration(),
                const SizedBox(width: 12),
                Expanded(child: stepsContent()),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                illustration(),
                const SizedBox(height: 10),
                stepsContent(),
              ],
            ),
    );
  }

  Widget _mollieTerminalPaymentsCard() {
    final statusCode = _mollieTerminalsStatusCode();
    final terminals = _mollieTerminalList();
    final activeTerminals = _mollieActiveTerminalList();
    final excludedTerminals = _mollieExcludedTerminalList();
    final syncedAt = (_mollieTerminalsSnapshot?['synced_at'] ?? '')
        .toString()
        .trim();
    final showReconnect = statusCode == 'terminals_scope_missing';
    return _collapsibleSettingsCard(
      id: 'mollie_terminal_payments',
      icon: Icons.point_of_sale_outlined,
      title: _t(
        nl: 'Mollie terminals',
        en: 'Mollie terminals',
        fr: 'Terminaux Mollie',
        es: 'Terminales Mollie',
      ),
      titleMaxLines: 2,
      subtitle: _mollieTerminalCardSubtitle(),
      status: _mollieTerminalSetupStatus(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              nl: 'Laat klanten in de wagen betalen via gekoppelde Mollie-terminals. Fluxidi kan terminalstatussen synchroniseren en betalingen beter koppelen aan ritten, voertuigen en chauffeurs.',
              en: 'Let customers pay in the vehicle using connected Mollie terminals. Fluxidi can synchronize terminal statuses and link payments more clearly to rides, vehicles and drivers.',
              fr: 'Permettez aux clients de payer dans le véhicule avec des terminaux Mollie connectés. Fluxidi peut synchroniser l’état des terminaux et mieux relier les paiements aux trajets, véhicules et chauffeurs.',
              es: 'Permite que los clientes paguen en el vehículo con terminales Mollie conectados. Fluxidi puede sincronizar el estado de los terminales y vincular mejor los pagos con viajes, vehículos y conductores.',
            ),
            style: TextStyle(color: _textSecondary, fontSize: 12, height: 1.38),
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              nl: 'Bestellen en activeren gebeurt via het eigen Mollie-dashboard van het bedrijf. Fluxidi gebruikt daarna de gekoppelde terminalinformatie voor opvolging en rapportage.',
              en: 'Ordering and activation are handled through the company’s own Mollie dashboard. Fluxidi then uses the connected terminal information for follow-up and reporting.',
              fr: 'La commande et l’activation se font via le tableau de bord Mollie propre à l’entreprise. Fluxidi utilise ensuite les informations des terminaux connectés pour le suivi et les rapports.',
              es: 'La compra y activación se gestionan desde el panel Mollie propio de la empresa. Fluxidi utiliza después la información de los terminales conectados para seguimiento e informes.',
            ),
            style: TextStyle(color: _textMuted, fontSize: 11.5, height: 1.35),
          ),
          const SizedBox(height: 12),
          _mollieTerminalSetupHelpCard(),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _subPanelBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _border.withOpacity(_isDark ? 0.48 : 0.9),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _mollieTerminalStatusTitle(),
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    _mollieTerminalsLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : _setupStatusChip(_mollieTerminalSetupStatus()),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _mollieTerminalStatusDescription(),
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 11.6,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Text(
                      '${_t(nl: 'Terminals', en: 'Terminals', fr: 'Terminaux', es: 'Terminales')}: ${activeTerminals.length}',
                      style: TextStyle(
                        color: _textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (excludedTerminals.isNotEmpty)
                      Text(
                        '${_t(nl: 'Ontkoppeld', en: 'Unlinked', fr: 'Déconnectés', es: 'Desvinculados')}: ${excludedTerminals.length}',
                        style: TextStyle(
                          color: _textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (syncedAt.isNotEmpty)
                      Text(
                        '${_t(nl: 'Laatste sync', en: 'Last sync', fr: 'Dernière synchro', es: 'Última sincronización')}: $syncedAt',
                        style: TextStyle(color: _textMuted, fontSize: 11.5),
                      ),
                  ],
                ),
                if (_mollieTerminalsError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _t(
                      nl: 'Laatste terminalcontrole gaf een fout. De bestaande instellingen blijven bruikbaar.',
                      en: 'The latest terminal check returned an error. Existing settings remain usable.',
                      fr: 'Le dernier contrôle des terminaux a renvoyé une erreur. Les paramètres existants restent utilisables.',
                      es: 'La última comprobación de terminales devolvió un error. La configuración existente sigue siendo utilizable.',
                    ),
                    style: TextStyle(
                      color: _danger,
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (activeTerminals.isNotEmpty) ...[
            const SizedBox(height: 10),
            Column(
              children: activeTerminals
                  .map((t) => _mollieTerminalListTile(t, excluded: false))
                  .toList(growable: false),
            ),
          ],
          if (excludedTerminals.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              mollieTerminalLinkCopy(key: 'unlinked_section', lang: _lang.name),
              style: TextStyle(
                color: _textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Column(
              children: excludedTerminals
                  .map((t) => _mollieTerminalListTile(t, excluded: true))
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _mollieTerminalsSyncLoading
                    ? null
                    : _syncMollieTerminals,
                icon: _mollieTerminalsSyncLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
                label: Text(
                  _t(
                    nl: 'Terminals synchroniseren',
                    en: 'Sync terminals',
                    fr: 'Synchroniser les terminaux',
                    es: 'Sincronizar terminales',
                  ),
                ),
              ),
              if (showReconnect)
                OutlinedButton.icon(
                  onPressed: _mollieConnectStartLoading
                      ? null
                      : _reconnectMollieForTerminals,
                  icon: _mollieConnectStartLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link_outlined),
                  label: Text(
                    _t(
                      nl: 'Mollie opnieuw verbinden',
                      en: 'Reconnect Mollie',
                      fr: 'Reconnecter Mollie',
                      es: 'Volver a conectar Mollie',
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _mollieTerminalsLoading
                    ? null
                    : () => _loadMollieTerminalsSnapshot(showErrorSnack: true),
                icon: _mollieTerminalsLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_outlined),
                label: Text(
                  _t(
                    nl: 'Snapshot vernieuwen',
                    en: 'Refresh snapshot',
                    fr: 'Actualiser l’instantané',
                    es: 'Actualizar instantánea',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _t(
              nl: 'Bestellen en activeren gebeurt via je eigen Mollie Dashboard.',
              en: 'Ordering and activation happen through your own Mollie Dashboard.',
              fr: 'La commande et l’activation se font via votre propre tableau de bord Mollie.',
              es: 'El pedido y la activación se realizan desde tu propio panel de Mollie.',
            ),
            style: TextStyle(color: _textMuted, fontSize: 11.4, height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _mollieTerminalListTile(
    Map<String, dynamic> terminal, {
    bool excluded = false,
  }) {
    String value(String key) => (terminal[key] ?? '').toString().trim();
    final terminalId = value('id');
    final id = _maskedMollieId(terminalId);
    final profileId = _maskedMollieId(value('profile_id'));
    final description = value('description');
    final status = value('status');
    final brand = value('brand');
    final model = value('model');
    final busy = _mollieTerminalLinkBusyId == terminalId;
    final title = description.isNotEmpty
        ? description
        : _t(
            nl: 'Mollie-terminal',
            en: 'Mollie terminal',
            fr: 'Terminal Mollie',
            es: 'Terminal Mollie',
          );
    final statusLabel = excluded
        ? _t(
            nl: 'ontkoppeld',
            en: 'unlinked',
            fr: 'déconnecté',
            es: 'desvinculado',
          )
        : (status.isNotEmpty
              ? status
              : _t(nl: 'active', en: 'active', fr: 'actif', es: 'activo'));
    final detailParts = <String>[
      if (id.isNotEmpty) id,
      statusLabel,
      if (brand.isNotEmpty || model.isNotEmpty)
        [brand, model].where((part) => part.isNotEmpty).join(' '),
      if (profileId.isNotEmpty)
        '${_t(nl: 'Profiel', en: 'Profile', fr: 'Profil', es: 'Perfil')}: $profileId',
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _panelBg.withOpacity(_isDark ? 0.55 : 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border.withOpacity(_isDark ? 0.42 : 0.82)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _subPanelBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border.withOpacity(0.72)),
                ),
                child: Icon(
                  Icons.point_of_sale_rounded,
                  size: 18,
                  color: _accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (detailParts.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        detailParts.join(' • '),
                        style: TextStyle(
                          color: _textMuted,
                          fontSize: 11.1,
                          height: 1.28,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: excluded
                ? Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: busy || terminalId.isEmpty
                            ? null
                            : () => _relinkMollieTerminal(terminal),
                        icon: busy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.link_rounded, size: 16),
                        label: Text(
                          mollieTerminalLinkCopy(
                            key: 'relink',
                            lang: _lang.name,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy || terminalId.isEmpty
                            ? null
                            : () => _forgetMollieTerminal(terminal),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                        ),
                        label: Text(
                          mollieTerminalLinkCopy(
                            key: 'forget',
                            lang: _lang.name,
                          ),
                        ),
                      ),
                    ],
                  )
                : OutlinedButton.icon(
                    onPressed: busy || terminalId.isEmpty
                        ? null
                        : () => _unlinkMollieTerminal(terminal),
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link_off_rounded, size: 16),
                    label: Text(
                      mollieTerminalLinkCopy(key: 'unlink', lang: _lang.name),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _cancellationPolicyCard() {
    return _collapsibleSettingsCard(
      id: 'cancellation_policy',
      icon: Icons.cancel_schedule_send_outlined,
      title: _t(
        nl: 'Annulatiebeleid',
        en: 'Cancellation policy',
        fr: 'Politique d annulation',
        es: 'Politica de cancelacion',
      ),
      subtitle: _t(
        nl: 'Bepaal tot wanneer klanten hun boeking zelf online kunnen annuleren.',
        en: 'Choose until when customers can cancel their booking online.',
        fr: 'Definissez jusqu a quand les clients peuvent annuler leur reservation en ligne.',
        es: 'Define hasta cuando los clientes pueden cancelar su reserva en linea.',
      ),
      status: _cancellationPolicySetupStatus(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _allowCustomerOnlineCancellation,
            onChanged: (v) =>
                setState(() => _allowCustomerOnlineCancellation = v),
            title: Text(
              _t(
                nl: 'Online annuleren toestaan',
                en: 'Allow online cancellation',
                fr: 'Autoriser l annulation en ligne',
                es: 'Permitir cancelacion en linea',
              ),
            ),
          ),
          _cancellationCutoffField(
            controller: _cancellationTaxiCutoffCtrl,
            label: _t(nl: 'Taxi', en: 'Taxi', fr: 'Taxi', es: 'Taxi'),
          ),
          _cancellationCutoffField(
            controller: _cancellationAirportCutoffCtrl,
            label: _t(
              nl: 'Luchthavenritten',
              en: 'Airport transfers',
              fr: 'Transferts aeroport',
              es: 'Traslados al aeropuerto',
            ),
          ),
          _cancellationCutoffField(
            controller: _cancellationBusinessCutoffCtrl,
            label: _t(
              nl: 'Zakelijke ritten',
              en: 'Business rides',
              fr: 'Courses professionnelles',
              es: 'Viajes de empresa',
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _subPanelBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _inputBorderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(
                    nl: 'Slimme annulatieblokkering',
                    en: 'Smart cancellation blocking',
                    fr: 'Blocage intelligent des annulations',
                    es: 'Bloqueo inteligente de cancelaciones',
                  ),
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 12.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _t(
                    nl: 'Fluxidi bepaalt automatisch of de chauffeur al aantoonbaar onderweg is naar de klant. Is dat zo, dan kan de klant niet meer online annuleren.',
                    en: 'Fluxidi automatically determines whether the driver is clearly already on the way to the customer. If so, the customer can no longer cancel online.',
                    fr: 'Fluxidi détermine automatiquement si le chauffeur est déjà clairement en route vers le client. Si c’est le cas, le client ne peut plus annuler en ligne.',
                    es: 'Fluxidi determina automáticamente si el conductor ya está claramente en camino hacia el cliente. Si es así, el cliente ya no puede cancelar en línea.',
                  ),
                  style: TextStyle(color: _textSecondary, fontSize: 11.6),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _blockWhenDriverEnRoute,
                  onChanged: (v) => setState(() => _blockWhenDriverEnRoute = v),
                  title: Text(
                    _t(
                      nl: 'Blokkeer annuleren wanneer chauffeur onderweg is',
                      en: 'Block cancellation when the driver is already on the way',
                      fr: 'Bloquer l annulation lorsque le chauffeur est deja en route',
                      es: 'Bloquear la cancelacion cuando el conductor ya esta en camino',
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _blockWhenDriverEnRoute
                      ? _t(
                          nl: 'Actief. Fluxidi gebruikt rit- en locatiegegevens om online annuleren automatisch te blokkeren wanneer de chauffeur onderweg is.',
                          en: 'Active. Fluxidi uses ride and location data to automatically block online cancellation when the driver is on the way.',
                          fr: 'Actif. Fluxidi utilise les données de course et de localisation pour bloquer automatiquement l’annulation en ligne lorsque le chauffeur est en route.',
                          es: 'Activo. Fluxidi utiliza datos del viaje y ubicación para bloquear automáticamente la cancelación en línea cuando el conductor está en camino.',
                        )
                      : _t(
                          nl: 'Uitgeschakeld. Klanten kunnen annuleren volgens de gewone tijdsregels.',
                          en: 'Disabled. Customers can cancel according to the normal time rules.',
                          fr: 'Désactivé. Les clients peuvent annuler selon les règles de temps normales.',
                          es: 'Desactivado. Los clientes pueden cancelar según las reglas de tiempo normales.',
                        ),
                  style: TextStyle(
                    color: _blockWhenDriverEnRoute ? _success : _textMuted,
                    fontSize: 11.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _t(
              nl: 'Betaalde boekingen',
              en: 'Paid bookings',
              fr: 'Reservations payees',
              es: 'Reservas pagadas',
            ),
            style: TextStyle(
              color: _textPrimary,
              fontSize: 12.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: _subPanelBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _inputBorderColor),
            ),
            child: Text(
              _t(
                nl: 'Handmatige beoordeling vereist',
                en: 'Manual review required',
                fr: 'Verification manuelle requise',
                es: 'Revision manual requerida',
              ),
              style: TextStyle(
                color: _textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_cancellationPolicyStatus != null) ...[
            const SizedBox(height: 8),
            Text(
              _cancellationPolicyStatus!,
              style: const TextStyle(color: Color(0xFF34D29A), fontSize: 11.8),
            ),
          ],
          if (_cancellationPolicyError != null) ...[
            const SizedBox(height: 8),
            Text(
              _cancellationPolicyError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 11.8),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _cancellationPolicyLoading || _cancellationPolicySaving
                  ? null
                  : () =>
                        _saveCancellationPolicyProfile(showErrorSnackBar: true),
              icon: _cancellationPolicySaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                _t(nl: 'Opslaan', en: 'Save', fr: 'Enregistrer', es: 'Guardar'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  BackendBusinessProfile _backendBusinessProfileFromForm() {
    final cached = localBackendBusinessProfileNotifier.value;
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
      companyEmail: cached?.companyEmail ?? '',
      supportEmail: cached?.supportEmail ?? '',
      notificationEmail: cached?.notificationEmail ?? '',
      pendingEmail: cached?.pendingEmail ?? '',
      emailVerificationStatus: cached?.emailVerificationStatus ?? '',
      website: _backendWebsiteCtrl.text.trim(),
      bookingEmail: _backendBookingEmailCtrl.text.trim(),
      publicLogoUrl: _publicLogoUrlCtrl.text.trim(),
      publicHeroPhotoUrl: _publicHeroPhotoUrlCtrl.text.trim(),
      publicServedPostcodes: _publicServedPostcodesCtrl.text.trim(),
      publicCoverageLat: _publicCoverageLatCtrl.text.trim(),
      publicCoverageLng: _publicCoverageLngCtrl.text.trim(),
      publicServiceRadiusKm: _publicServiceRadiusKmCtrl.text.trim(),
      publicPaymentOptions: _orderedPublicPaymentOptionIds(
        _publicPaymentOptionIds,
      ),
      publicServiceIds:
          _publicServicesConfigured ||
              _publicServiceIds.contains(kLimousinePublicServiceId)
          ? _sanitizePublicServiceIds(_publicServiceIds).toList(growable: false)
          : const <String>[],
      publicServicesConfigured:
          _publicServicesConfigured ||
          _publicServiceIds.contains(kLimousinePublicServiceId),
      publicPartnerProfilePublishedAt: _publicPartnerProfilePublishedAt.trim(),
      publicPartnerProfilePublishStatus: _publicPartnerProfilePublishStatus
          .trim(),
      invoiceEmail: _backendInvoiceEmailCtrl.text.trim(),
      iban: _backendIbanCtrl.text.trim(),
      paymentReferencePrefix: _backendPaymentPrefixCtrl.text.trim(),
      invoiceReceiptFooterText: _backendFooterCtrl.text.trim(),
      paymentOwnerMode: _paymentOwnerMode,
      paymentDemoMode: _paymentDemoMode,
      mollieConnected: _mollieConnected,
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
      final scope = _strictSettingsScopeForAction(
        action: 'save_backend_business_profile',
      );
      if (scope == null) return false;
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
      final pending = merged.pendingEmail.trim();
      final confirmationRequired =
          saved.confirmationRequired || pending.isNotEmpty;
      setState(() {
        _hydrateBackendBusinessProfile(merged);
        _backendProfilesStatus = confirmationRequired
            ? _t(
                nl: 'Bevestiging nodig. De huidige herstelmail blijft actief tot de nieuwe e-mail is bevestigd.',
                en: 'Confirmation required. The current recovery email stays active until the new email is confirmed.',
                fr: 'Confirmation requise. L e-mail de recuperation actuel reste actif jusqu a confirmation.',
                es: 'Se requiere confirmacion. El correo de recuperacion actual sigue activo hasta confirmar.',
              )
            : _t(
                nl: 'Bedrijfsprofiel opgeslagen.',
                en: 'Business profile saved.',
                fr: 'Profil entreprise enregistre.',
                es: 'Perfil empresarial guardado.',
              );
      });
      unawaited(updateLocalBackendBusinessProfileCache(merged));
      if (!confirmationRequired) {
        final syncedEmail = resolvePrimaryCompanyContactEmail(backend: merged);
        if (syncedEmail.isNotEmpty) {
          unawaited(
            CompanySessionStore.instance.updatePrimaryContactEmailFromBackend(
              syncedEmail,
            ),
          );
        }
      }
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
      final scope = _strictSettingsScopeForAction(
        action: 'upload_public_company_media',
      );
      if (scope == null) return;
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
              ? 'Publiek logo geüpload en opgeslagen.'
              : 'Publieke coverfoto geüpload en opgeslagen.',
          en: isLogo
              ? 'Public logo uploaded and saved.'
              : 'Public cover photo uploaded and saved.',
          fr: isLogo
              ? 'Logo public téléversé et enregistré.'
              : 'Photo de couverture publique téléversée et enregistrée.',
          es: isLogo
              ? 'Logo público subido y guardado.'
              : 'Foto de portada pública subida y guardada.',
        );
      });
      unawaited(updateLocalBackendBusinessProfileCache(merged));
    } catch (e) {
      if (!mounted) return;
      final errorText = e.toString().toLowerCase();
      final isAuthError =
          errorText.contains('401') ||
          errorText.contains('403') ||
          errorText.contains('unauthorized') ||
          errorText.contains('forbidden');
      final isFormatError =
          errorText.contains('unsupported content type') ||
          errorText.contains('content_type_mismatch') ||
          errorText.contains('unsupported content');
      setState(() {
        _publicPartnerProfileError = isAuthError
            ? _t(
                nl: 'Upload mislukt. Uw bedrijfssessie is niet geldig. Herkoppel of herstel uw bedrijf en probeer opnieuw.',
                en: 'Upload failed. Your company session is not valid. Relink or recover your company and try again.',
                fr: 'Échec du téléversement. Votre session entreprise n’est pas valide. Reconnectez ou récupérez votre entreprise et réessayez.',
                es: 'La carga falló. Tu sesión de empresa no es válida. Vuelve a vincular o recuperar tu empresa e inténtalo de nuevo.',
              )
            : isFormatError
            ? _t(
                nl: 'Upload mislukt. Controleer of dit een JPG, PNG of WEBP-afbeelding is.',
                en: 'Upload failed. Please check that this is a JPG, PNG, or WEBP image.',
                fr: 'Échec du téléversement. Vérifiez qu’il s’agit d’une image JPG, PNG ou WEBP.',
                es: 'La carga falló. Verifica que sea una imagen JPG, PNG o WEBP.',
              )
            : _t(
                nl: 'Upload mislukt. Probeer opnieuw.',
                en: 'Upload failed. Please try again.',
                fr: 'Échec du téléversement. Réessayez.',
                es: 'La carga falló. Inténtalo de nuevo.',
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
      final scope = _strictSettingsScopeForAction(
        action: 'save_backend_tax_profile',
      );
      if (scope == null) return false;
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
      final pricingScope = _strictSettingsScopeForAction(
        action: 'sync_pricing_after_tax_profile_save',
        showUx: false,
      );
      if (pricingScope == null) return true;
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
    return resolvePublicHttpsMediaUrl(value).isNotEmpty;
  }

  String _publicPublishMediaUrl(String raw) => resolvePublicHttpsMediaUrl(raw);

  String _publicDriverPortraitUrlForPublish(DriverProfile driver) {
    if (!driver.publicProfileEnabled ||
        !driver.publicPhotoEnabled ||
        !driver.isActive) {
      return '';
    }
    return _publicPublishMediaUrl(driver.publicPortraitUrl ?? '');
  }

  String _publicVehiclePhotoUrlForPublish(VehicleProfile vehicle) {
    final publicPhoto = _publicPublishMediaUrl(vehicle.publicPhotoUrl ?? '');
    if (publicPhoto.isNotEmpty) return publicPhoto;
    return _publicPublishMediaUrl(vehicle.primaryPhotoRef);
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
            colors: [_subPanelBg, _panelBg, _setupGold.withOpacity(0.18)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border.withOpacity(_isDark ? 0.55 : 0.95)),
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
                  color: _textPrimary,
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
        color: _panelBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border.withOpacity(_isDark ? 0.58 : 0.95)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(
              nl: 'Publieke media preview',
              en: 'Public media preview',
              fr: 'Aperçu des médias publics',
              es: 'Vista previa de medios públicos',
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
                nl: 'Nog geen publieke media geüpload.',
                en: 'No public media uploaded yet.',
                fr: 'Aucun média public téléversé pour le moment.',
                es: 'Aún no se ha subido ningún medio público.',
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
                            es: 'Foto de portada pública',
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
                            nl: 'Cover geüpload',
                            en: 'Cover uploaded',
                            fr: 'Couverture téléversée',
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
                              color: _isDark
                                  ? Colors.black.withOpacity(0.62)
                                  : Colors.white.withOpacity(0.88),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _border.withOpacity(
                                  _isDark ? 0.48 : 0.95,
                                ),
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
                    es: 'Logo público',
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
                  border: Border.all(
                    color: _border.withOpacity(_isDark ? 0.5 : 0.95),
                  ),
                  color: _subPanelBg,
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
                      nl: 'Logo geüpload',
                      en: 'Logo uploaded',
                      fr: 'Logo téléversé',
                      es: 'Logo subido',
                    ),
                    const Color(0xFF34D29A),
                  ),
                if (hasHero)
                  _statusPill(
                    _t(
                      nl: 'Cover geüpload',
                      en: 'Cover uploaded',
                      fr: 'Couverture téléversée',
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
    return mappedPublicServiceIdsForPublish(
      configured: _publicServicesConfigured,
      selected: _publicServiceIds,
      legacyFallback: _legacyPublicServiceIdsFromCalculator(),
    );
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
          fr: 'Transfert aéroport',
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
          fr: 'Événements',
          es: 'Eventos',
        );
      case 'hotel_bnb_pickup':
        return _t(
          nl: 'Hotels & B&B',
          en: 'Hotels & B&B',
          fr: 'Hôtels & B&B',
          es: 'Hoteles y B&B',
        );
      case 'online_payments':
        return _t(
          nl: 'Online betalen',
          en: 'Online payments',
          fr: 'Paiement en ligne',
          es: 'Pago online',
        );
      case kLimousinePublicServiceId:
        return limousinePublicServiceLabelFor(_lang);
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
    return filterPublicPartnerPaymentOptionIds(
      values,
    ).where(allowed.contains).toSet();
  }

  String _companyCountryCodeForPaymentResolver() {
    final code = normalizeCountryCode(_backendCountryCtrl.text.trim());
    if (code.isEmpty) return PaymentCountryCodes.belgium;
    if (code == PaymentCountryCodes.unitedKingdom) {
      return PaymentCountryCodes.greatBritain;
    }
    return PaymentCountryCodes.supported.contains(code)
        ? code
        : PaymentCountryCodes.belgium;
  }

  List<String> _orderedPublicPaymentOptionCatalogForUi() {
    return PaymentMethodResolver.reorderByCountryProfile(
      countryCode: _companyCountryCodeForPaymentResolver(),
      candidateIds: _publicPaymentOptionCatalog,
    );
  }

  List<String> _orderedPublicPaymentOptionIds(Iterable<String> values) {
    final sanitized = _sanitizePublicPaymentOptionIds(values);
    if (sanitized.isEmpty) return const <String>[];
    return PaymentMethodResolver.reorderByCountryProfile(
      countryCode: _companyCountryCodeForPaymentResolver(),
      candidateIds: sanitized,
    );
  }

  String _publicPaymentOptionLabel(String id) {
    switch (id.trim().toLowerCase()) {
      case 'cash':
        return _t(nl: 'Cash', en: 'Cash', fr: 'Espèces', es: 'Efectivo');
      case 'qr_code':
        return _t(nl: 'QR-code', en: 'QR code', fr: 'Code QR', es: 'Código QR');
      case 'bancontact':
        return 'Bancontact';
      case 'kbc_cbc':
        return 'KBC/CBC Payment Button';
      case 'belfius':
        return 'Belfius Pay Button';
      case 'payconiq_wero':
        return 'Payconiq / Wero';
      case 'ideal':
        return 'iDEAL';
      case 'cartes_bancaires':
        return 'Carte Bancaire / CB';
      case 'bizum':
        return 'Bizum';
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

  Widget _publicPaymentOptionFilterChip(String id) {
    final selected = _publicPaymentOptionIds.contains(id);
    return FilterChip(
      avatar: paymentMethodLogoAssetForId(id) == null
          ? null
          : buildPaymentMethodLogo(
              methodId: id,
              plateWidth: 48,
              plateHeight: 34,
              imageMaxWidth: 42,
              imageMaxHeight: 28,
              plateBorderRadius: 6,
              platePadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 3,
              ),
              fallbackIconSize: 18,
            ),
      label: Text(_publicPaymentOptionLabel(id)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
      selectedColor: _accent.withOpacity(_isDark ? 0.22 : 0.14),
      checkmarkColor: _accent,
      backgroundColor: _subPanelBg,
      side: BorderSide(
        color: selected
            ? _accent.withOpacity(0.75)
            : _border.withOpacity(_isDark ? 0.48 : 0.95),
      ),
      labelStyle: TextStyle(
        color: selected ? (_isDark ? _textOnAccent : _accent) : _textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 11.6,
      ),
    );
  }

  Widget _publicPaymentOptionsChipSection() {
    final paymentCatalog = _orderedPublicPaymentOptionCatalogForUi();
    final lastMollieIdx = lastMollieCheckoutMethodIndex(paymentCatalog);
    final leadingIds = lastMollieIdx == null
        ? paymentCatalog
        : paymentCatalog.sublist(0, lastMollieIdx + 1);
    final trailingIds = lastMollieIdx == null
        ? const <String>[]
        : paymentCatalog.sublist(lastMollieIdx + 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: leadingIds
              .map(_publicPaymentOptionFilterChip)
              .toList(growable: false),
        ),
        if (lastMollieIdx != null) ...[
          const SizedBox(height: 10),
          buildPaymentsByMollieTrustBadge(isDarkSurface: _isDark),
        ],
        if (trailingIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: trailingIds
                .map(_publicPaymentOptionFilterChip)
                .toList(growable: false),
          ),
        ],
      ],
    );
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
                fr: 'Les services de localisation sont désactivés sur cet appareil.',
                es: 'Los servicios de ubicación están desactivados en este dispositivo.',
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
                fr: 'Accès à la localisation refusé.',
                es: 'Acceso a la ubicación denegado.',
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
                fr: 'L’accès à la localisation est refusé définitivement. Activez l’autorisation dans les paramètres.',
                es: 'El acceso a la ubicación está denegado permanentemente. Activa el permiso en la configuración.',
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
              fr: 'Emplacement professionnel défini. Enregistrez et republiez votre profil.',
              es: 'Ubicación de empresa configurada. Guarda y publica tu perfil de nuevo.',
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
              fr: 'Impossible de récupérer la position actuelle.',
              es: 'No se pudo obtener la ubicación actual.',
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
    ].join(' • ');
    final services = _mappedPublicServiceIds();
    final companyPhone = profileForm.phone.trim().isNotEmpty
        ? profileForm.phone.trim()
        : (localCompany?.phone.trim() ?? '');
    final onlinePaymentsEnabled = services.contains('online_payments');
    final airportServiceEnabled = services.contains('airport_transfer');
    final limousineServiceEnabled = services.contains(
      kLimousinePublicServiceId,
    );
    final publicPaymentMethods = _orderedPublicPaymentOptionIds(
      _publicPaymentOptionIds,
    );
    final coverageLat = _tryParsePublicLat(profileForm.publicCoverageLat);
    final coverageLng = _tryParsePublicLng(profileForm.publicCoverageLng);
    final serviceRadiusKm = _tryParsePublicServiceRadiusKm(
      profileForm.publicServiceRadiusKm,
    );

    final scopedActiveVehicles = vehiclesNotifier.value
        .where((v) => v.isActive)
        .where((v) => vehicleBelongsToCompanyPublishScope(v, companyId))
        .toList(growable: false);
    final vehicles = scopedActiveVehicles
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
          final serviceCategory = v.serviceCategory.trim().toLowerCase();
          final serviceClass = v.serviceClassId.trim().toLowerCase();
          final isLimousine = serviceCategory == 'limousine';
          final galleryUrls = isLimousine
              ? orderPublicVehicleGalleryUrls(
                  primaryUrl: _publicVehiclePhotoUrlForPublish(v),
                  galleryUrls: [
                    for (final ref in v.galleryPhotoRefs)
                      _publicPublishMediaUrl(ref),
                  ],
                )
              : const <String>[];
          final photoUrl = isLimousine
              ? (galleryUrls.isEmpty
                    ? _publicVehiclePhotoUrlForPublish(v)
                    : galleryUrls.first)
              : _publicVehiclePhotoUrlForPublish(v);
          // LIMOUSINE-MARKETPLACE-P1: emit authoritative configured
          // classification only. `category` stays the human tier label; the
          // machine-authoritative service_category/service_class are emitted
          // solely when explicitly configured (never inferred from tier/brand).
          // Gallery fields stay limousine-only so taxi/airport contracts stay
          // a single photo_url.
          return <String, dynamic>{
            'name': v.vehicleName.trim(),
            'brand_model': brand,
            'category': _publicTierCategoryLabel(v.tierId),
            if (isLimousine && v.id.trim().isNotEmpty)
              'vehicle_id': v.id.trim(),
            if (serviceCategory.isNotEmpty) 'service_category': serviceCategory,
            if (serviceClass.isNotEmpty) 'service_class': serviceClass,
            'pax': v.passengerCapacity < 0 ? 0 : v.passengerCapacity,
            'luggage': v.luggageCapacity < 0 ? 0 : v.luggageCapacity,
            'features': features.toList(growable: false),
            'photo_url': photoUrl,
            if (isLimousine && photoUrl.isNotEmpty)
              'primary_photo_url': photoUrl,
            if (isLimousine && galleryUrls.isNotEmpty)
              'gallery_photo_urls': galleryUrls,
          };
        })
        .toList(growable: false);
    final vehiclePhotoCount = vehicles
        .where((row) => ((row['photo_url'] ?? '').toString().trim().isNotEmpty))
        .length;
    final vehiclesWithRawPublicPhoto = scopedActiveVehicles
        .where((v) => (v.publicPhotoUrl ?? '').trim().isNotEmpty)
        .length;
    for (final vehicle in scopedActiveVehicles) {
      final hasRawPublic = (vehicle.publicPhotoUrl ?? '').trim().isNotEmpty;
      final hasResolvedPublic = _publicVehiclePhotoUrlForPublish(
        vehicle,
      ).isNotEmpty;
      debugPrint(
        '[PUBLIC_PARTNER_PUBLISH][VEHICLE_MEDIA] vehicle=${maskVehicleIdForLog(vehicle.id)} '
        'raw_public=$hasRawPublic resolved_public=$hasResolvedPublic',
      );
    }

    final scopedPublicDrivers = driversNotifier.value
        .where((d) => d.publicProfileEnabled)
        .where((d) => d.isActive)
        .where((d) => (d.companyId?.trim() ?? '') == companyId)
        .toList(growable: false);
    final drivers = scopedPublicDrivers
        .map((d) {
          final displayName = d.publicDisplayName?.trim() ?? '';
          final portraitUrl = _publicDriverPortraitUrlForPublish(d);
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
            'portrait_url': portraitUrl,
          };
        })
        .toList(growable: false);
    final driverPortraitCount = drivers
        .where(
          (row) => ((row['portrait_url'] ?? '').toString().trim().isNotEmpty),
        )
        .length;
    final maskedCompanyId = companyId.length <= 4
        ? '…'
        : '${companyId.substring(0, 2)}…${companyId.substring(companyId.length - 2)}';
    debugPrint(
      '[PUBLIC_PARTNER_PUBLISH][MEDIA] company=$maskedCompanyId '
      'drivers=${scopedPublicDrivers.length} portraits=$driverPortraitCount '
      'vehicles=${scopedActiveVehicles.length} '
      'vehicle_raw_public_photos=$vehiclesWithRawPublicPhoto '
      'vehicle_photos=$vehiclePhotoCount',
    );

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
        'logo_url': _publicPublishMediaUrl(profileForm.publicLogoUrl),
        'hero_photo_url': _publicPublishMediaUrl(
          profileForm.publicHeroPhotoUrl,
        ),
        'gallery': const <String>[],
      },
      'services': services,
      'airport_service_enabled': airportServiceEnabled,
      'airportServiceEnabled': airportServiceEnabled,
      'airport_transfer_enabled': airportServiceEnabled,
      'airportTransferEnabled': airportServiceEnabled,
      'limousine_service_enabled': limousineServiceEnabled,
      'limousineServiceEnabled': limousineServiceEnabled,
      'capabilities': <String, dynamic>{
        'airport': airportServiceEnabled,
        'airport_transfer': airportServiceEnabled,
        'limousine': limousineServiceEnabled,
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
        'limousine': limousineServiceEnabled,
        'limousine_service_enabled': limousineServiceEnabled,
        'limousineServiceEnabled': limousineServiceEnabled,
      },
    };
  }

  Future<bool> _publishPublicPartnerProfile() async {
    if (!mounted) return false;
    setState(() {
      _publicPartnerProfilePublishing = true;
      _publicPartnerProfileStatus = null;
      _publicPartnerProfileError = null;
    });
    try {
      final scope = _strictSettingsScopeForAction(
        action: 'publish_public_partner_profile',
      );
      if (scope == null) return false;
      // Keep publish flow stateful: persist current business form values first
      // so manual public media URLs survive page close/reopen even if the user
      // uses "Publish public profile" without tapping "Save company details".
      final formProfile = _backendBusinessProfileFromForm();
      await updateLocalBackendBusinessProfileCache(formProfile);
      if (!mounted) return false;
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
      if (!mounted) return false;
      final mergedBusiness = _mergeBackendBusinessProfile(
        local: formProfile,
        server: savedBusiness,
      );
      if (mounted) {
        _hydrateBackendBusinessProfile(mergedBusiness);
      }
      unawaited(updateLocalBackendBusinessProfileCache(mergedBusiness));

      await syncFleetInventoryToBackend(
        tenantId: scope.tenantId,
        companyId: scope.companyId,
      );
      if (!mounted) return false;

      final payload = _buildPublicPartnerProfilePayload(
        companyId: scope.companyId,
      );
      late final Map<String, dynamic> published;
      try {
        published = await publishBackendPublicPartnerProfile(
          partnerProfile: payload,
          tenantId: scope.tenantId,
          companyId: scope.companyId,
        );
      } catch (e) {
        if (e.toString().contains('409') ||
            e.toString().contains('stale_partner_profile_revision')) {
          if (!mounted) return false;
          setState(() {
            _publicPartnerProfileError = _t(
              nl: 'Publiceren geweigerd: een nieuwere versie staat al op de server. De lokale Limousine-keuze blijft behouden. Probeer opnieuw.',
              en: 'Publish rejected: a newer version is already on the server. The local Limousine selection is kept. Try again.',
              fr: 'Publication refusee : une version plus recente est deja sur le serveur. La selection Limousine locale est conservee. Reessayez.',
              es: 'Publicacion rechazada: ya hay una version mas reciente en el servidor. La seleccion de Limusina local se conserva. Intentalo de nuevo.',
            );
          });
          return false;
        }
        rethrow;
      }
      if (!mounted) return false;
      final publishedProfile = published['profile'];
      if (publishedProfile is Map) {
        final publishedServices = publishedProfile['services'];
        if (publishedServices is List) {
          final recovered = applyPublishedPartnerServices(
            current: PublicServiceSelection(
              ids: _mappedPublicServiceIds(),
              configured: true,
            ),
            publishedServices: publishedServices.map((e) => '$e'),
          );
          _publicServicesConfigured = recovered.configured;
          _publicServiceIds = recovered.ids.toSet();
        }
      }
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
      if (!mounted) return false;
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
      if (!mounted) return false;
      final mergedPublishedBusiness = _mergeBackendBusinessProfile(
        local: publishedBusiness,
        server: savedPublishedBusiness,
      );
      if (!mounted) return false;
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

  bool _isBelgianPostcodeLike(String value) {
    return RegExp(r'^\d{4}$').hasMatch(value.trim());
  }

  String _radiusCenterResolveQuery(String zoneLabel) {
    final normalized = zoneLabel.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return '';
    if (_isBelgianPostcodeLike(normalized)) {
      return '$normalized Belgium';
    }
    return normalized;
  }

  Future<Map<String, double>?> _resolveRadiusCenterCoordinates(
    String zoneLabel,
  ) async {
    final token = kMapboxToken.trim();
    if (token.isEmpty) return null;
    final query = _radiusCenterResolveQuery(zoneLabel);
    if (query.isEmpty) return null;
    try {
      final uri = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/'
        '${Uri.encodeComponent(query)}.json'
        '?access_token=${Uri.encodeComponent(token)}'
        '&autocomplete=true'
        '&limit=1'
        '&types=postcode,address,place,locality,district',
      );
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final features = decoded['features'];
      if (features is! List || features.isEmpty) return null;
      final first = features.first;
      if (first is! Map) return null;
      final center = first['center'];
      if (center is! List || center.length < 2) return null;
      final lngRaw = center[0];
      final latRaw = center[1];
      final lat = latRaw is num
          ? latRaw.toDouble()
          : double.tryParse('$latRaw');
      final lng = lngRaw is num
          ? lngRaw.toDouble()
          : double.tryParse('$lngRaw');
      if (lat == null ||
          lng == null ||
          !lat.isFinite ||
          !lng.isFinite ||
          lat < -90 ||
          lat > 90 ||
          lng < -180 ||
          lng > 180) {
        return null;
      }
      return <String, double>{'lat': lat, 'lng': lng};
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    if (_saveAllBusy) return;
    final current = businessSettingsNotifier.value;
    final scope = _activeSettingsScope();
    final vat = _activeVatConfig();
    final failedParts = <String>[];
    final saveAirportRules =
        _airportFixedFaresDirty && !_airportFixedFaresLoading;
    final cancellationCandidate = _cancellationPolicyProfileFromFormOrNull();
    if (cancellationCandidate == null) {
      final msg = _t(
        nl: 'Ongeldige waarde in Annulatiebeleid. Controleer de ingestelde limieten.',
        en: 'Invalid value in Cancellation policy. Please check the configured limits.',
        fr: 'Valeur invalide dans la politique d annulation. Verifiez les limites configurees.',
        es: 'Valor invalido en Politica de cancelacion. Revisa los limites configurados.',
      );
      setState(() {
        _cancellationPolicyError = msg;
        _cancellationPolicyStatus = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
      return;
    }
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
          chironEnabled:
              backendChironConnectionStatusNotifier.value?.enabled ??
              _chironEnabled,
          chironEnvironment:
              backendChironConnectionStatusNotifier.value?.environment ??
              (_chironEnabled
                  ? ChironConnectionEnvironment.test
                  : current.chironEnvironment),
          chironConnectionStatus:
              backendChironConnectionStatusNotifier.value != null &&
                  _chironBackendConfirmed
              ? ChironCompanyConnectionDefaults.mapBackendLastConnectionStatus(
                  backendChironConnectionStatusNotifier
                      .value!
                      .lastConnectionStatus,
                )
              : (_chironEnabled
                    ? _chironConnectionStatus
                    : ChironConnectionStatus.notConfigured),
          chironRegionScope:
              backendChironConnectionStatusNotifier.value?.region ==
                  ChironRegionScope.flanders
              ? ChironRegionScope.flanders
              : _chironRegionScope,
          chironLastTestedAt:
              backendChironConnectionStatusNotifier
                  .value
                  ?.lastConnectionTestAt ??
              current.chironLastTestedAt,
          chironProductionEnabled:
              backendChironConnectionStatusNotifier.value?.productionEnabled ??
              (_chironProductionAllowedFromServer()
                  ? _chironProductionEnabled
                  : false),
        ),
        tenantId: scope.tenantId,
        companyId: scope.companyId,
        syncToBackend: false,
      );

      final pricingScope = _strictSettingsScopeForAction(
        action: 'save_pricing_sync',
      );
      final pricingSynced = pricingScope == null
          ? false
          : await syncPricingProfileToBackend(
              tenantId: pricingScope.tenantId,
              companyId: pricingScope.companyId,
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

      final cancellationSaved = await _saveCancellationPolicyProfile(
        showErrorSnackBar: false,
      );
      if (!cancellationSaved) {
        failedParts.add(
          _t(
            nl: 'annulatiebeleid',
            en: 'cancellation policy',
            fr: 'politique d annulation',
            es: 'politica de cancelacion',
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
        // Canonical resolution, shared with the business dashboard. The stored
        // reference may be a packaged asset, an on-device file written by the
        // picker, or the company's public https URL after startup bootstrap —
        // all three must render here.
        final resolved = resolveCompanyLogoRef(
          localPath: _effectiveCompanyLogoRef(_logoPathCtrl.text) ?? '',
          publicUrl: _publicLogoUrlCtrl.text,
          configuredFluxidiAsset: appConfig.logoAsset,
          resolvePublicUrl: resolvePublicHttpsMediaUrl,
          isWeb: kIsWeb,
        );
        final ref = resolved.ref;
        final showImage = resolved.isCompanyOwned;
        final logoUnsetForPreview = !showImage;

        Widget previewChild;
        if (!showImage) {
          previewChild = _logoPlaceholder();
        } else {
          Widget image;
          switch (resolved.kind) {
            case CompanyLogoRefKind.asset:
              image = Image.asset(
                ref,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _logoUnavailableNotice(),
              );
            case CompanyLogoRefKind.network:
              image = Image.network(
                ref,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : _logoLoadingNotice(),
                errorBuilder: (_, __, ___) => _logoUnavailableNotice(),
              );
            case CompanyLogoRefKind.file:
              image = Image.file(
                File(ref),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _logoUnavailableNotice(),
              );
            case CompanyLogoRefKind.none:
              image = _logoPlaceholder();
          }
          previewChild = ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: image,
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
                  color: _inputFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _inputBorderColor),
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

  /// Bounded notice for a logo that is set but currently cannot be shown.
  ///
  /// Never claims the company has no logo: that is a different fact and saying
  /// it here is what made a stored logo look lost after a restart.
  Widget _logoBoundedNotice({required IconData icon, required String label}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: _textMuted),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: _textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _logoLoadingNotice() => _logoBoundedNotice(
    icon: Icons.downloading_outlined,
    label: _t(
      nl: 'Bedrijfslogo laden…',
      en: 'Loading company logo…',
      fr: 'Chargement du logo…',
      es: 'Cargando el logotipo…',
    ),
  );

  Widget _logoUnavailableNotice() => _logoBoundedNotice(
    icon: Icons.image_not_supported_outlined,
    label: _t(
      nl: 'Bedrijfslogo kon niet worden geladen. Het blijft opgeslagen.',
      en: 'Company logo could not be loaded. It is still saved.',
      fr: 'Le logo n’a pas pu être chargé. Il reste enregistré.',
      es: 'No se pudo cargar el logotipo. Sigue guardado.',
    ),
  );

  Widget _logoPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 28, color: _textMuted),
          const SizedBox(height: 6),
          Text(
            _t(
              nl: 'Geen bedrijfslogo ingesteld',
              en: 'No company logo set',
              fr: 'Aucun logo d’entreprise défini',
              es: 'No hay logotipo de empresa configurado',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: _textSecondary, fontSize: 12),
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
    int? titleMaxLines,
    GlobalKey? anchorKey,
    bool highlighted = false,
  }) {
    final isExpanded = _expandedSections.contains(id);
    final statusResolved = status ?? _SetupStatus.comingSoon;
    final statusColor = _statusColor(statusResolved);
    return Container(
      key: anchorKey,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_panelBg, _isDark ? _pageBg : _subPanelBg],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted
              ? _accent.withOpacity(_isDark ? 0.9 : 0.82)
              : _border.withOpacity(_isDark ? 0.55 : 0.95),
          width: highlighted ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _shadow.withOpacity(_isDark ? 0.22 : 0.12),
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
                    color: _subPanelBg,
                    border: Border.all(color: _border.withOpacity(0.9)),
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
                        maxLines: titleMaxLines,
                        overflow: titleMaxLines != null
                            ? TextOverflow.ellipsis
                            : null,
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _textMuted, fontSize: 11.4),
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
                      color: _setupGold,
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
                          color: _border.withOpacity(_isDark ? 0.4 : 0.9),
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
        color: isError
            ? (_isDark ? const Color(0xFF3A1010) : const Color(0xFFFBECEF))
            : (_isDark ? const Color(0xFF12331F) : const Color(0xFFE9F7F0)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? _danger.withOpacity(.55) : _success.withOpacity(.45),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isError
              ? (_isDark ? Colors.redAccent.shade100 : _danger)
              : (_isDark ? Colors.greenAccent.shade100 : _success),
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

  ({String tenantId, String companyId})? _activeSettingsScopeStrict() {
    final profileCompanyId =
        companyProfileNotifier.value?.companyId.trim() ?? '';
    final sessionCompanyId =
        activeCompanySessionNotifier.value?.companyId.trim() ?? '';
    if (profileCompanyId.isNotEmpty &&
        sessionCompanyId.isNotEmpty &&
        profileCompanyId != sessionCompanyId) {
      return null;
    }
    final companyId = profileCompanyId.isNotEmpty
        ? profileCompanyId
        : sessionCompanyId;
    if (companyId.isEmpty) return null;
    return (tenantId: companyId, companyId: companyId);
  }

  void _showMissingStrictCompanyScopeSnackbar() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Backend synchronisatie vereist een actieve bedrijfssessie. Herkoppel of herstel eerst uw bedrijf.',
          ),
        ),
      );
    });
  }

  ({String tenantId, String companyId})? _strictSettingsScopeForAction({
    required String action,
    bool showUx = true,
  }) {
    final scope = _activeSettingsScopeStrict();
    if (scope != null) return scope;
    debugPrint(
      '[BUSINESS_SETTINGS_SCOPE][BLOCK] reason=missing_strict_company_scope action=$action',
    );
    if (showUx) _showMissingStrictCompanyScopeSnackbar();
    return null;
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
          fr: 'Vers aéroport',
          es: 'Al aeropuerto',
        );
      case 'from_airport':
        return _t(
          nl: 'Van luchthaven',
          en: 'From airport',
          fr: 'Depuis aéroport',
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
          es: 'Código postal',
        );
      case 'city':
        return _t(nl: 'Stad', en: 'City', fr: 'Ville', es: 'Ciudad');
      case 'country':
        return _t(nl: 'Land', en: 'Country', fr: 'Pays', es: 'País');
      case 'radius':
        return _t(
          nl: 'Radius rond locatie',
          en: 'Radius around location',
          fr: 'Rayon autour d’un lieu',
          es: 'Radio alrededor de ubicación',
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
      final scope = _activeSettingsScopeStrict();
      if (scope == null) {
        debugPrint(
          '[BUSINESS_SETTINGS_SCOPE][SKIP] reason=missing_strict_company_scope action=load_airport_fixed_fare_rules',
        );
        return;
      }
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
          fr: 'Tarifs fixes aéroport chargés.',
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
                fr: 'Les tarifs fixes aéroport n’ont pas pu être chargés.',
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
      final scope = _strictSettingsScopeForAction(
        action: 'save_airport_fixed_fare_rules',
      );
      if (scope == null) return false;
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
          fr: 'Tarifs fixes aéroport enregistrés.',
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
                fr: 'Échec de l’enregistrement des tarifs fixes aéroport.',
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
    var isResolvingRadiusCenter = false;
    String? radiusCenterResolveStatus;
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
                                        nl: 'Bijvoorbeeld: 9688, Ronse, Maarkedal of een volledig adres.',
                                        en: 'For example: 9688, Ronse, Maarkedal, or a full address.',
                                        fr: 'Par exemple: 9688, Ronse, Maarkedal ou une adresse complete.',
                                        es: 'Por ejemplo: 9688, Ronse, Maarkedal o una direccion completa.',
                                      ),
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.72),
                                        fontSize: 12,
                                        height: 1.3,
                                      ),
                                    ),
                                    if (isResolvingRadiusCenter) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _t(
                                                nl: 'Locatiecentrum wordt opgezocht...',
                                                en: 'Resolving center location...',
                                                fr: 'Recherche du centre de zone...',
                                                es: 'Buscando el centro de la zona...',
                                              ),
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(
                                                  0.78,
                                                ),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ] else if (radiusCenterResolveStatus !=
                                        null) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        radiusCenterResolveStatus!,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.65),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
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
                                      collapsedIconColor: _accent,
                                      iconColor: _accent,
                                      textColor: _textPrimary,
                                      collapsedTextColor: _textSecondary,
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
                                  onPressed: isResolvingRadiusCenter
                                      ? null
                                      : () async {
                                          FocusScope.of(
                                            dialogContext,
                                          ).unfocus();
                                          setDialogState(() {
                                            airportError = null;
                                            zoneError = null;
                                            radiusError = null;
                                            priceError = null;
                                            radiusCenterResolveStatus = null;
                                          });

                                          final zoneValue = zoneValueCtrl.text
                                              .trim();
                                          final zoneLabel = zoneLabelCtrl.text
                                              .trim();
                                          var zoneCenterLat = double.tryParse(
                                            zoneCenterLatCtrl.text
                                                .trim()
                                                .replaceAll(',', '.'),
                                          );
                                          var zoneCenterLng = double.tryParse(
                                            zoneCenterLngCtrl.text
                                                .trim()
                                                .replaceAll(',', '.'),
                                          );
                                          final radiusKm =
                                              radiusPreset == 'custom'
                                              ? double.tryParse(
                                                  radiusKmCtrl.text
                                                      .trim()
                                                      .replaceAll(',', '.'),
                                                )
                                              : double.tryParse(radiusPreset);
                                          final price = double.tryParse(
                                            priceCtrl.text.trim().replaceAll(
                                              ',',
                                              '.',
                                            ),
                                          );
                                          if (selectedAirportIata
                                              .trim()
                                              .isEmpty) {
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
                                            final hasValidCoords =
                                                zoneCenterLat != null &&
                                                zoneCenterLat.isFinite &&
                                                zoneCenterLat >= -90 &&
                                                zoneCenterLat <= 90 &&
                                                zoneCenterLng != null &&
                                                zoneCenterLng.isFinite &&
                                                zoneCenterLng >= -180 &&
                                                zoneCenterLng <= 180;
                                            if (!hasValidCoords) {
                                              setDialogState(() {
                                                isResolvingRadiusCenter = true;
                                              });
                                              final resolvedCoords =
                                                  await _resolveRadiusCenterCoordinates(
                                                    zoneLabel,
                                                  );
                                              if (!dialogContext.mounted)
                                                return;
                                              if (resolvedCoords == null) {
                                                setDialogState(() {
                                                  isResolvingRadiusCenter =
                                                      false;
                                                  showAdvancedRadiusCoordinates =
                                                      true;
                                                  radiusError = _t(
                                                    nl: 'Locatiecentrum niet gevonden. Controleer de postcode, stad of vul coördinaten handmatig in.',
                                                    en: 'Center location not found. Check the postcode/city or enter coordinates manually.',
                                                    fr: 'Centre introuvable. Verifiez le code postal/la ville ou saisissez les coordonnees manuellement.',
                                                    es: 'No se encontro el centro. Comprueba el codigo postal/ciudad o introduce coordenadas manualmente.',
                                                  );
                                                });
                                                return;
                                              }
                                              zoneCenterLat =
                                                  resolvedCoords['lat'];
                                              zoneCenterLng =
                                                  resolvedCoords['lng'];
                                              zoneCenterLatCtrl.text =
                                                  zoneCenterLat!
                                                      .toStringAsFixed(6);
                                              zoneCenterLngCtrl.text =
                                                  zoneCenterLng!
                                                      .toStringAsFixed(6);
                                              setDialogState(() {
                                                isResolvingRadiusCenter = false;
                                                radiusCenterResolveStatus = _t(
                                                  nl: 'Centrum gevonden.',
                                                  en: 'Center found.',
                                                  fr: 'Centre trouve.',
                                                  es: 'Centro encontrado.',
                                                );
                                              });
                                            }
                                            if (!zoneCenterLat.isFinite ||
                                                zoneCenterLat < -90 ||
                                                zoneCenterLat > 90 ||
                                                !zoneCenterLng.isFinite ||
                                                zoneCenterLng < -180 ||
                                                zoneCenterLng > 180) {
                                              setDialogState(() {
                                                showAdvancedRadiusCoordinates =
                                                    true;
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
                                          final airportIata =
                                              selectedAirportIata
                                                  .trim()
                                                  .toUpperCase();
                                          final normalizedCurrency =
                                              _airportFixedFareCurrencies
                                                  .contains(selectedCurrency)
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
        fr: 'Tarifs fixes aéroport',
        es: 'Tarifas fijas aeropuerto',
      ),
      subtitle: _t(
        nl: 'Bedrijfsregels per luchthaven',
        en: 'Company rules per airport',
        fr: 'Règles entreprise par aéroport',
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
                '${_t(nl: 'Laatst bijgewerkt', en: 'Last updated', fr: 'Dernière mise à jour', es: 'Última actualización')}: ${_airportFixedFaresUpdatedAt ?? ''}',
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
                  fr: 'Aucune règle de tarif fixe aéroport configurée.',
                  es: 'Aún no hay reglas de tarifa fija de aeropuerto configuradas.',
                ),
                style: TextStyle(color: _textSecondary),
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
                              ? '$airportName ($airportIata) - € ${price.toStringAsFixed(2)} $currency'
                              : '$airportIata - € ${price.toStringAsFixed(2)} $currency',
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
                    fr: 'Ajouter une règle',
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
                    fr: 'Enregistrer les règles',
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
        style: TextStyle(color: _textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: _textSecondary),
          hintText: hint,
          hintStyle: TextStyle(color: _textMuted.withOpacity(0.85)),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          alignLabelWithHint: maxLines > 1,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 16,
          ),
          filled: true,
          fillColor: _inputFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _inputBorderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _inputBorderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _inputFocusColor, width: 1.2),
          ),
        ),
      ),
    );
  }

  String _countryLabelForCode(String code) {
    for (final entry in _kBusinessCountryCodes) {
      if (entry[0] == code) {
        switch (_lang) {
          case AppLanguage.nl:
            return entry[1];
          case AppLanguage.en:
            return entry[2];
          case AppLanguage.fr:
            return entry[3];
          case AppLanguage.es:
            return entry[4];
          case AppLanguage.de:
            return entry[2];
        }
      }
    }
    return code;
  }

  Widget _businessCountryDropdown() {
    final currentCode = _normalizeBusinessCountryCode(_backendCountryCtrl.text);
    final dropdownValue = currentCode.isEmpty ? null : currentCode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        value: dropdownValue,
        style: TextStyle(color: _textPrimary),
        iconEnabledColor: _textSecondary,
        dropdownColor: _inputFill,
        decoration: InputDecoration(
          labelText: _t(nl: 'Land', en: 'Country', fr: 'Pays', es: 'País'),
          labelStyle: TextStyle(color: _textSecondary),
          helperText: _t(
            nl: 'Gebruikt voor facturatie, betalingen en officiële bedrijfsgegevens.',
            en: 'Used for invoicing, payments and official company details.',
            fr: "Utilisé pour la facturation, les paiements et les coordonnées officielles de l'entreprise.",
            es: 'Se usa para facturación, pagos y datos oficiales de la empresa.',
          ),
          helperStyle: TextStyle(color: _textMuted, fontSize: 11.5),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 16,
          ),
          filled: true,
          fillColor: _inputFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _inputBorderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _inputBorderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _inputFocusColor, width: 1.2),
          ),
        ),
        items: _kBusinessCountryCodes
            .map(
              (entry) => DropdownMenuItem<String>(
                value: entry[0],
                child: Text(
                  '${_countryLabelForCode(entry[0])} (${entry[0]})',
                  style: TextStyle(color: _textPrimary),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            )
            .toList(growable: false),
        onChanged: (value) {
          if (value == null) return;
          if (_backendCountryCtrl.text.trim() == value) return;
          setState(() {
            _backendCountryCtrl.text = value;
          });
        },
      ),
    );
  }

  Widget _cancellationCutoffField({
    required TextEditingController controller,
    required String label,
    String? helperText,
    bool allowDecimal = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(
            allowDecimal ? RegExp(r'[0-9\.,]') : RegExp(r'[0-9]'),
          ),
        ],
        style: TextStyle(color: _textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: _textSecondary),
          helperText:
              helperText ??
              _t(
                nl: 'Minuten voor vertrek (0-10080)',
                en: 'Minutes before departure (0-10080)',
                fr: 'Minutes avant depart (0-10080)',
                es: 'Minutos antes de la salida (0-10080)',
              ),
          helperStyle: TextStyle(color: _textMuted, fontSize: 11.5),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 16,
          ),
          filled: true,
          fillColor: _inputFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _inputBorderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _inputBorderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _inputFocusColor, width: 1.2),
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
                style: TextStyle(color: _textMuted, fontSize: 12),
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

  Color get _setupGold => _accent;

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
          fr: 'A verifier',
          es: 'Requiere atención',
        );
      case _SetupStatus.incomplete:
        return _t(
          nl: 'Onvolledig',
          en: 'Incomplete',
          fr: 'Incomplet',
          es: 'Incompleto',
        );
      case _SetupStatus.optional:
        return _t(
          nl: 'Optioneel',
          en: 'Optional',
          fr: 'Optionnel',
          es: 'Opcional',
        );
      case _SetupStatus.activationPending:
        return _t(
          nl: 'Activering volgt',
          en: 'Activation pending',
          fr: 'Activation à venir',
          es: 'Activación pendiente',
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
      case _SetupStatus.optional:
        return _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
      case _SetupStatus.activationPending:
        return const Color(0xFFE5B641);
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
    return _mapPricingCompletenessKind(_pricingCompleteness().kind);
  }

  PricingSetupCompleteness _pricingCompleteness() {
    return evaluatePricingSetupCompleteness(
      baseFare: _baseFareCtrl.text,
      perKm: _perKmCtrl.text,
      perMinute: _perMinCtrl.text,
      minimumFare: _minimumFareCtrl.text,
    );
  }

  _SetupStatus _mapPricingCompletenessKind(PricingSetupCompletenessKind kind) {
    switch (kind) {
      case PricingSetupCompletenessKind.complete:
        return _SetupStatus.complete;
      case PricingSetupCompletenessKind.attention:
        return _SetupStatus.attention;
      case PricingSetupCompletenessKind.incomplete:
        return _SetupStatus.incomplete;
    }
  }

  String _pricingSetupReasonLabel(String key) {
    switch (key) {
      case PricingSetupReasonKey.baseFareMissing:
        return _t(
          nl: 'Basistarief ontbreekt',
          en: 'Base fare is missing',
          fr: 'Tarif de base manquant',
          es: 'Falta la tarifa base',
        );
      case PricingSetupReasonKey.baseFareInvalid:
        return _t(
          nl: 'Basistarief is ongeldig',
          en: 'Base fare is invalid',
          fr: 'Tarif de base invalide',
          es: 'Tarifa base no válida',
        );
      case PricingSetupReasonKey.perKmMissing:
        return _t(
          nl: 'Prijs per km ontbreekt',
          en: 'Price per km is missing',
          fr: 'Prix par km manquant',
          es: 'Falta el precio por km',
        );
      case PricingSetupReasonKey.perKmInvalid:
        return _t(
          nl: 'Prijs per km is ongeldig',
          en: 'Price per km is invalid',
          fr: 'Prix par km invalide',
          es: 'Precio por km no válido',
        );
      case PricingSetupReasonKey.perMinuteMissing:
        return _t(
          nl: 'Prijs per minuut ontbreekt',
          en: 'Price per minute is missing',
          fr: 'Prix par minute manquant',
          es: 'Falta el precio por minuto',
        );
      case PricingSetupReasonKey.perMinuteInvalid:
        return _t(
          nl: 'Prijs per minuut is ongeldig',
          en: 'Price per minute is invalid',
          fr: 'Prix par minute invalide',
          es: 'Precio por minuto no válido',
        );
      case PricingSetupReasonKey.minimumFareMissing:
        return _t(
          nl: 'Minimumtarief ontbreekt',
          en: 'Minimum fare is missing',
          fr: 'Tarif minimum manquant',
          es: 'Falta la tarifa mínima',
        );
      case PricingSetupReasonKey.minimumFareInvalid:
        return _t(
          nl: 'Minimumtarief is ongeldig',
          en: 'Minimum fare is invalid',
          fr: 'Tarif minimum invalide',
          es: 'Tarifa mínima no válida',
        );
      default:
        return _t(
          nl: 'Kernprijzen onvolledig',
          en: 'Core prices incomplete',
          fr: 'Prix clés incomplets',
          es: 'Precios clave incompletos',
        );
    }
  }

  String _pricingSetupSubtitle() {
    final result = _pricingCompleteness();
    if (result.isComplete) {
      return _t(
        nl: 'Basistarief en kernprijzen',
        en: 'Base fare and core prices',
        fr: 'Tarif de base et prix clés',
        es: 'Tarifa base y precios clave',
      );
    }
    if (result.reasonKeys.isEmpty) {
      return _t(
        nl: 'Basistarief en kernprijzen',
        en: 'Base fare and core prices',
        fr: 'Tarif de base et prix clés',
        es: 'Tarifa base y precios clave',
      );
    }
    return _pricingSetupReasonLabel(result.reasonKeys.first);
  }

  void _onPricingFieldEdited(String _) {
    if (!mounted) return;
    setState(() {});
  }

  _SetupStatus _cancellationPolicySetupStatus() {
    final hasAllowFlag =
        _allowCustomerOnlineCancellation == true ||
        _allowCustomerOnlineCancellation == false;
    final hasTaxi =
        _parseCancellationIntOrNull(
          _cancellationTaxiCutoffCtrl.text,
          min: 0,
          max: 10080,
        ) !=
        null;
    final hasAirport =
        _parseCancellationIntOrNull(
          _cancellationAirportCutoffCtrl.text,
          min: 0,
          max: 10080,
        ) !=
        null;
    final hasBusiness =
        _parseCancellationIntOrNull(
          _cancellationBusinessCutoffCtrl.text,
          min: 0,
          max: 10080,
        ) !=
        null;
    final hasBlockFlag =
        _blockWhenDriverEnRoute == true || _blockWhenDriverEnRoute == false;
    final hasEta =
        _parseCancellationIntOrNull(
          _driverEnRouteEtaCutoffCtrl.text,
          min: 0,
          max: 240,
        ) !=
        null;
    final hasDistance =
        _parseCancellationDoubleOrNull(
          _driverEnRouteDistanceCutoffCtrl.text,
          min: 0,
          max: 100,
        ) !=
        null;
    final hasFreshness =
        _parseCancellationIntOrNull(
          _driverLocationFreshnessCtrl.text,
          min: 30,
          max: 3600,
        ) !=
        null;
    final hasHandoff =
        _parseCancellationIntOrNull(
          _driverHandoffBufferCtrl.text,
          min: 0,
          max: 120,
        ) !=
        null;
    final hasPaidMode = _paidBookingCancellationMode == 'review_required';
    final checks = <bool>[
      hasAllowFlag,
      hasTaxi,
      hasAirport,
      hasBusiness,
      hasBlockFlag,
      hasEta,
      hasDistance,
      hasFreshness,
      hasHandoff,
      hasPaidMode,
    ];
    final score = checks.where((v) => v).length;
    if (score == checks.length) return _SetupStatus.complete;
    if (score >= 3) return _SetupStatus.attention;
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
          fr: 'Prêt à partager via lien et QR',
          es: 'Listo para compartir por enlace y QR',
        );
      case _SetupStatus.attention:
      case _SetupStatus.incomplete:
      case _SetupStatus.optional:
      case _SetupStatus.activationPending:
      case _SetupStatus.comingSoon:
        return _t(
          nl: 'Publieke code of link ontbreekt',
          en: 'Public code or link is missing',
          fr: 'Code public ou lien manquant',
          es: 'Falta el código público o el enlace',
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
        subtitle: _pricingSetupSubtitle(),
        icon: Icons.local_offer_outlined,
        status: _pricingStatus(),
      ),
      _SetupItem(
        title: _t(
          nl: 'Annulatiebeleid',
          en: 'Cancellation policy',
          fr: 'Politique d annulation',
          es: 'Politica de cancelacion',
        ),
        subtitle: _t(
          nl: 'Online annuleren en tijdsvensters',
          en: 'Online cancellation and cutoffs',
          fr: 'Annulation en ligne et delais',
          es: 'Cancelacion online y ventanas',
        ),
        icon: Icons.cancel_schedule_send_outlined,
        status: _cancellationPolicySetupStatus(),
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_panelBg, _isDark ? _pageBg : _subPanelBg],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border.withOpacity(_isDark ? 0.52 : 0.92)),
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
            style: TextStyle(
              color: _textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _textMuted, fontSize: 11.2, height: 1.25),
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_subPanelBg, _panelBg, _isDark ? _pageBg : _subPanelBg],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border.withOpacity(_isDark ? 0.62 : 0.95)),
        boxShadow: [
          BoxShadow(
            color: _shadow.withOpacity(_isDark ? 0.24 : 0.14),
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
            style: TextStyle(
              color: _textPrimary,
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
            style: TextStyle(color: _textSecondary, fontSize: 12.3),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: BoxDecoration(
              color: _isDark
                  ? _pageBg.withOpacity(0.82)
                  : _subPanelBg.withOpacity(0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _border.withOpacity(_isDark ? 0.58 : 0.95),
              ),
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
                  style: TextStyle(
                    color: _textPrimary,
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
    return AnimatedBuilder(
      animation: Listenable.merge([
        appLanguageNotifier,
        businessThemeNotifier,
        brandSignaturePaletteNotifier,
      ]),
      builder: (context, _) => Theme(
        data: Theme.of(context).copyWith(
          // Scope a brightness/text-theme override to BusinessSettingsPage
          // only. The global app theme stays Brightness.dark with white
          // textTheme, so driver/customer/role-entry screens are unchanged.
          // Without this override, every default-styled Text widget on the
          // settings page (SwitchListTile titles, ExpansionTile headers,
          // DropdownButtonFormField items, etc.) would inherit white text
          // and disappear on the Clean Professional light palette.
          brightness: _isDark ? Brightness.dark : Brightness.light,
          scaffoldBackgroundColor: _pageBg,
          textTheme:
              (_isDark
                      ? Typography.whiteMountainView
                      : Typography.blackMountainView)
                  .apply(bodyColor: _textPrimary, displayColor: _textPrimary),
          primaryTextTheme:
              (_isDark
                      ? Typography.whiteMountainView
                      : Typography.blackMountainView)
                  .apply(bodyColor: _textPrimary, displayColor: _textPrimary),
          colorScheme: Theme.of(context).colorScheme.copyWith(
            brightness: _isDark ? Brightness.dark : Brightness.light,
            primary: _accent,
            secondary: _accent,
            surface: _panelBg,
            onSurface: _textPrimary,
            onPrimary: _textOnAccent,
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: _pageBg,
            foregroundColor: _textPrimary,
            elevation: 0,
          ),
          iconTheme: IconThemeData(color: _textSecondary),
          inputDecorationTheme: InputDecorationTheme(
            labelStyle: TextStyle(color: _textSecondary),
            hintStyle: TextStyle(color: _textMuted),
            helperStyle: TextStyle(color: _textMuted, fontSize: 11.5),
            filled: true,
            fillColor: _inputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _inputBorderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _inputBorderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _inputFocusColor, width: 1.2),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: _accent,
              side: BorderSide(
                color: _border.withOpacity(_isDark ? 0.75 : 0.98),
              ),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: _textOnAccent,
            ),
          ),
          switchTheme: SwitchThemeData(
            thumbColor: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.selected)) return _accent;
              return _isDark ? _textMuted : _textSecondary;
            }),
            trackColor: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.selected)) {
                return _accent.withOpacity(_isDark ? 0.5 : 0.42);
              }
              return _isDark
                  ? _border.withOpacity(0.6)
                  : _border.withOpacity(0.95);
            }),
          ),
        ),
        child: Scaffold(
          backgroundColor: _pageBg,
          appBar: AppBar(
            backgroundColor: _pageBg,
            title: Text(
              (_isActiveStepMode &&
                      widget.stepTitle != null &&
                      widget.stepTitle!.trim().isNotEmpty)
                  ? widget.stepTitle!
                  : _t(
                      nl: 'Bedrijfsinstellingen',
                      en: 'Business settings',
                      fr: 'Parametres entreprise',
                      es: 'Configuracion de empresa',
                    ),
            ),
            actions:
                (_isActiveStepMode &&
                    (widget.onSkipStep != null || widget.onExitWizard != null))
                ? <Widget>[
                    // Top-right primary action: per-step skip. Always
                    // labelled "Deze stap overslaan / Skip this step" so
                    // users cannot mistake it for a whole-wizard exit.
                    // The wizard host wires this to a handler that
                    // advances ONE step.
                    if (widget.onSkipStep != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: TextButton(
                          onPressed: widget.onSkipStep,
                          style: TextButton.styleFrom(
                            foregroundColor: _textSecondary,
                          ),
                          child: Text(
                            widget.skipStepLabel ??
                                _t(
                                  nl: 'Deze stap overslaan',
                                  en: 'Skip this step',
                                  fr: 'Ignorer cette étape',
                                  es: 'Omitir este paso',
                                ),
                          ),
                        ),
                      ),
                    // Secondary, less-prominent action: whole-wizard
                    // exit ("Finish setup later"). Hidden behind a
                    // standard 3-dot overflow menu so it cannot be hit
                    // accidentally while skipping a single step.
                    if (widget.onExitWizard != null)
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, color: _textSecondary),
                        tooltip: _t(
                          nl: 'Meer opties',
                          en: 'More options',
                          fr: "Plus d'options",
                          es: 'Más opciones',
                        ),
                        onSelected: (value) {
                          if (value == 'exit_wizard') {
                            widget.onExitWizard?.call();
                          }
                        },
                        itemBuilder: (popupCtx) => <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            value: 'exit_wizard',
                            child: Text(
                              widget.exitWizardLabel ??
                                  _t(
                                    nl: 'Setup later afmaken',
                                    en: 'Finish setup later',
                                    fr: 'Terminer plus tard',
                                    es: 'Terminar más tarde',
                                  ),
                            ),
                          ),
                        ],
                      ),
                  ]
                : null,
            bottom:
                (_isActiveStepMode &&
                    widget.stepIndex != null &&
                    widget.stepTotal != null &&
                    widget.stepTotal! > 0)
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(54),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _stepProgressLabel(),
                                style: TextStyle(
                                  color: _textMuted,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              if (widget.stepSubtitle != null &&
                                  widget.stepSubtitle!.trim().isNotEmpty) ...[
                                Text(
                                  '  •  ',
                                  style: TextStyle(
                                    color: _textMuted,
                                    fontSize: 11.5,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    widget.stepSubtitle!,
                                    style: TextStyle(
                                      color: _textSecondary,
                                      fontSize: 11.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: widget.stepIndex! / widget.stepTotal!,
                              minHeight: 4,
                              backgroundColor: _border.withOpacity(
                                _isDark ? 0.45 : 0.7,
                              ),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          ),
          body: ListView(
            controller: _settingsScrollController,
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
              if (!_isActiveStepMode) _buildSetupCockpit(),
              if (!_isActiveStepMode)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: _panelBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _border.withOpacity(_isDark ? 0.55 : 0.95),
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(Icons.palette_outlined, color: _accent),
                    title: Text(
                      _t(
                        nl: "Thema's & uitstraling",
                        en: 'Themes & appearance',
                        fr: 'Thèmes et apparence',
                        es: 'Temas y apariencia',
                      ),
                    ),
                    subtitle: Text(
                      _t(
                        nl: 'Kies de kleuren voor bedrijf, chauffeurs en klantweergave.',
                        en: 'Choose colors for business, drivers, and customer display.',
                        fr: 'Choisissez les couleurs pour l’entreprise, les chauffeurs et la vue client.',
                        es: 'Elige los colores para empresa, conductores y vista cliente.',
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: _textSecondary,
                    ),
                    onTap: () async {
                      final result = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => const BusinessThemePage(),
                        ),
                      );
                      if (result == true && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
              if (_shouldShowSection('local_company'))
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
                      return ValueListenableBuilder<ActiveCompanySession?>(
                        valueListenable: activeCompanySessionNotifier,
                        builder: (context, session, ___) {
                          final p = companyProfileNotifier.value;
                          final serverPaired = hasServerConfirmedCompanyPairing(
                            profile: p,
                            session: session,
                          );
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                          style: TextStyle(
                                            color: _textPrimary,
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
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
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
                                    icon: Icon(Icons.copy, color: _textMuted),
                                  ),
                                ],
                              ),
                              if (p != null) ...[
                                const SizedBox(height: 14),
                                Text(
                                  _t(
                                    nl: 'Bedrijfsstatus',
                                    en: 'Company status',
                                    fr: 'Statut de l’entreprise',
                                    es: 'Estado de la empresa',
                                  ),
                                  style: TextStyle(
                                    color: _textMuted,
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
                                          : serverPaired
                                          ? const Color(0xFF102433)
                                          : const Color(0xFF2A2410),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: p.isSuspended
                                            ? Colors.red.withOpacity(0.45)
                                            : p.isVerified
                                            ? const Color(
                                                0xFF4ADE80,
                                              ).withOpacity(0.45)
                                            : serverPaired
                                            ? const Color(
                                                0xFF38BDF8,
                                              ).withOpacity(0.45)
                                            : _accent.withOpacity(0.55),
                                      ),
                                    ),
                                    child: Text(
                                      p.verificationBadgeLabel(
                                        _lang,
                                        serverPaired: serverPaired,
                                      ),
                                      style: TextStyle(
                                        color: p.isSuspended
                                            ? const Color(0xFFFFB4B4)
                                            : p.isVerified
                                            ? const Color(0xFFB8F5C8)
                                            : serverPaired
                                            ? const Color(0xFFBAE6FD)
                                            : const Color(0xFFE5D4A1),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                if (p.showsPendingVerificationNotice(
                                  serverPaired: serverPaired,
                                )) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    p.verificationPendingNotice(_lang),
                                    style: TextStyle(
                                      color: _textMuted,
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              if (_shouldShowSection('public_booking_link') &&
                  companyShouldShowTaxiBookingQr())
                ValueListenableBuilder<ActiveCompanySession?>(
                  valueListenable: activeCompanySessionNotifier,
                  builder: (context, activeSession, __) {
                    return _collapsibleSettingsCard(
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
                        builder: (context, profile, _) {
                          final publicCompanyCode = _activePublicCompanyCode(
                            session: activeSession,
                            profile: profile,
                          );
                          final hasPublicCompanyCode =
                              publicCompanyCode != null;
                          final effectivePublicCompanyCode =
                              hasPublicCompanyCode ? publicCompanyCode : '';
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
                                      color: Colors.orangeAccent.withOpacity(
                                        0.45,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _t(
                                          nl: 'Verifieer uw bedrijf eerst om een publieke boekingslink te gebruiken.',
                                          en: 'Verify your company first to use a public booking link.',
                                          fr: 'Vérifiez d’abord votre entreprise pour utiliser un lien de réservation public.',
                                          es: 'Verifica primero tu empresa para usar un enlace público de reserva.',
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
                                          fr: 'Aucun code Fluxidi public trouvé.',
                                          es: 'No se encontró ningún código público de Fluxidi.',
                                        ),
                                        style: TextStyle(
                                          color: Colors.orangeAccent
                                              .withOpacity(0.82),
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
                                    fr: 'Partagez ce lien ou ce code QR avec les clients afin qu’ils puissent réserver directement.',
                                    es: 'Comparte este enlace o código QR con los clientes para que puedan reservar directamente.',
                                  ),
                                  style: TextStyle(
                                    color: _textSecondary,
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
                                    color: _subPanelBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _border.withOpacity(
                                        _isDark ? 0.58 : 0.95,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _t(
                                          nl: 'Publieke bedrijfscode',
                                          en: 'Public company code',
                                          fr: 'Code entreprise public',
                                          es: 'Código público de empresa',
                                        ),
                                        style: TextStyle(
                                          color: _textSecondary,
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
                                              style: TextStyle(
                                                color: _accent,
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
                                                  text:
                                                      effectivePublicCompanyCode,
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
                                                      fr: 'Code entreprise public copié',
                                                      es: 'Código público de empresa copiado',
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
                                                es: 'Copiar código',
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
                                    color: _subPanelBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _border.withOpacity(
                                        _isDark ? 0.5 : 0.95,
                                      ),
                                    ),
                                  ),
                                  child: SelectableText(
                                    publicBookingUrl,
                                    style: TextStyle(
                                      color: _textPrimary,
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
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
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
                                      icon: const Icon(
                                        Icons.copy_outlined,
                                        size: 16,
                                      ),
                                      label: Text(
                                        _t(
                                          nl: 'Kopiëren',
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
                                          final uri = Uri.parse(
                                            publicBookingUrl,
                                          );
                                          final launched = await launchUrl(
                                            uri,
                                            mode:
                                                LaunchMode.externalApplication,
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
                                                    fr: 'Impossible d’ouvrir le lien de réservation public.',
                                                    es: 'No se pudo abrir el enlace público de reserva.',
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
                                                  fr: 'Impossible d’ouvrir le lien de réservation public.',
                                                  es: 'No se pudo abrir el enlace público de reserva.',
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
                                    fr: 'La page de réservation publique sera davantage liée à ce code Fluxidi.',
                                    es: 'La página pública de reserva se vinculará más a este código Fluxidi.',
                                  ),
                                  style: TextStyle(
                                    color: _textMuted,
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
              if (_shouldShowSection('google_calendar')) _googleCalendarCard(),
              if (_shouldShowSection('chiron_connection'))
                _chironConnectionCard(),
              if (_shouldShowSection('official_company_details'))
                _collapsibleSettingsCard(
                  id: 'official_company_details',
                  anchorKey: _sectionAnchorKeys['official_company_details'],
                  highlighted:
                      _highlightedSectionId == 'official_company_details',
                  icon: Icons.business_outlined,
                  title: _t(
                    nl: 'Officiële bedrijfsgegevens',
                    en: 'Official company details',
                    fr: 'Informations officielles de l’entreprise',
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
                          fr: 'Nom de l’entreprise',
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
                              _t(
                                nl: 'Stad',
                                en: 'City',
                                fr: 'Ville',
                                es: 'Ciudad',
                              ),
                            ),
                          ),
                        ],
                      ),
                      _businessCountryDropdown(),
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
                        _t(
                          nl: 'E-mail',
                          en: 'Email',
                          fr: 'E-mail',
                          es: 'Correo',
                        ),
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
                      // Section-local "Save company details" button. Hidden
                      // in active step mode so the wizard's bottom
                      // "Opslaan en verder" button is the single primary
                      // step action; in normal full-settings mode this
                      // button stays visible and behaves exactly like
                      // before.
                      if (!_isActiveStepMode) ...[
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
                    ],
                  ),
                ),
              if (_shouldShowSection('payment_ownership'))
                _paymentOwnershipCard(),
              if (_shouldShowSection('mollie_terminal_payments'))
                _mollieTerminalPaymentsCard(),
              if (_shouldShowSection('billit_peppol')) _billitIntegrationCard(),
              if (_shouldShowSection('vat_settings'))
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
                        onChanged: (v) =>
                            setState(() => _backendVatEnabled = v),
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
                          fillColor: _inputFill,
                        ),
                        dropdownColor: _subPanelBg,
                      ),
                      // Section-local "Save VAT settings" button. Hidden
                      // in active step mode so the wizard's bottom
                      // "Opslaan en verder" button is the single primary
                      // step action; in normal full-settings mode this
                      // button stays visible and behaves exactly like
                      // before.
                      if (!_isActiveStepMode) ...[
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
                                style: TextStyle(
                                  color: _textMuted,
                                  fontSize: 11,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (_shouldShowSection('public_partner_profile'))
                _collapsibleSettingsCard(
                  id: 'public_partner_profile',
                  icon: Icons.public_outlined,
                  title: _t(
                    nl: 'Publiek partnerprofiel',
                    en: 'Public partner profile',
                    fr: 'Profil partenaire public',
                    es: 'Perfil público de socio',
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
                          nl: 'Publiceer veilige bedrijfsinformatie zodat klanten je kunnen vinden via Taxi’s in de buurt.',
                          en: 'Publish safe company information so customers can find you through Nearby taxis.',
                          fr: 'Publiez des informations publiques sécurisées afin que les clients puissent vous trouver.',
                          es: 'Publica información segura de la empresa para que los clientes puedan encontrarte.',
                        ),
                        style: TextStyle(color: _textSecondary, fontSize: 12.5),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _t(
                          nl: 'Upload een logo of coverfoto. Fluxidi maakt automatisch een publieke veilige link.',
                          en: 'Upload a logo or cover photo. Fluxidi automatically creates a safe public link.',
                          fr: 'Téléversez un logo ou une photo de couverture. Fluxidi crée automatiquement un lien public sécurisé.',
                          es: 'Sube un logo o una foto de portada. Fluxidi crea automáticamente un enlace público seguro.',
                        ),
                        style: TextStyle(color: _textMuted, fontSize: 11.4),
                      ),
                      const SizedBox(height: 10),
                      _txt(
                        _publicServedPostcodesCtrl,
                        _t(
                          nl: 'Bediende postcodes',
                          en: 'Served postcodes',
                          fr: 'Codes postaux desservis',
                          es: 'Códigos postales atendidos',
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
                          fr: 'Utilisez des virgules, espaces ou retours à la ligne entre les codes postaux.',
                          es: 'Usa comas, espacios o saltos de línea entre códigos postales.',
                        ),
                        style: TextStyle(color: _textMuted, fontSize: 11.2),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _t(
                          nl: 'Publieke dekking voor Taxi’s in de buurt (optioneel).',
                          en: 'Public coverage for Taxis nearby (optional).',
                          fr: 'Couverture publique pour Taxis à proximité (optionnel).',
                          es: 'Cobertura pública para Taxis cercanos (opcional).',
                        ),
                        style: TextStyle(color: _textMuted, fontSize: 11.2),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _useCurrentLocationAsBusinessLocation,
                          icon: const Icon(Icons.my_location_outlined),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _accent,
                            side: BorderSide(
                              color: _border.withOpacity(_isDark ? 0.72 : 0.95),
                            ),
                            backgroundColor: _subPanelBg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          label: Text(
                            _t(
                              nl: 'Gebruik huidige locatie als bedrijfslocatie',
                              en: 'Use current location as business location',
                              fr: 'Utiliser ma position actuelle comme adresse professionnelle',
                              es: 'Usar mi ubicación actual como ubicación de empresa',
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
                          color: _subPanelBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _border.withOpacity(_isDark ? 0.45 : 0.95),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _hasPublicCoverageLocationSet()
                                  ? _t(
                                      nl: 'Bedrijfslocatie ingesteld via GPS',
                                      en: 'Business location set via GPS',
                                      fr: 'Emplacement professionnel défini via GPS',
                                      es: 'Ubicación de empresa configurada por GPS',
                                    )
                                  : _t(
                                      nl: 'Nog geen bedrijfslocatie ingesteld.',
                                      en: 'No business location set yet.',
                                      fr: 'Aucun emplacement professionnel défini.',
                                      es: 'Aún no se ha configurado la ubicación de empresa.',
                                    ),
                              style: TextStyle(
                                color: _hasPublicCoverageLocationSet()
                                    ? _success
                                    : _textSecondary,
                                fontSize: 12.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (_hasPublicCoverageLocationSet()) ...[
                              const SizedBox(height: 4),
                              Text(
                                _publicCoverageCoordsLabel(),
                                style: TextStyle(
                                  color: _textMuted,
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
                          fr: '1 à 100',
                          es: '1 a 100',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _t(
                          nl: 'Publieke services en profielzichtbaarheid',
                          en: 'Public services and profile visibility',
                          fr: 'Services publics et visibilité du profil',
                          es: 'Servicios públicos y visibilidad del perfil',
                        ),
                        style: TextStyle(
                          color: _textSecondary,
                          fontSize: 12.6,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _t(
                          nl: 'Dit is los van Service setup. Service setup stuurt calculator/pricing; deze toggles sturen publiek profiel en boekings-CTA’s.',
                          en: 'This is separate from Service setup. Service setup drives calculator/pricing; these toggles drive public profile and booking CTAs.',
                          fr: 'Ceci est séparé de la configuration des services. Cette section contrôle le profil public et les CTA de réservation.',
                          es: 'Esto es independiente de la configuración de servicios. Estos controles afectan el perfil público y los CTA de reserva.',
                        ),
                        style: TextStyle(color: _textMuted, fontSize: 11.2),
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
                                selectedColor: _accent.withOpacity(
                                  _isDark ? 0.22 : 0.14,
                                ),
                                checkmarkColor: _accent,
                                backgroundColor: _subPanelBg,
                                side: BorderSide(
                                  color: selected
                                      ? _accent.withOpacity(0.75)
                                      : _border.withOpacity(
                                          _isDark ? 0.48 : 0.95,
                                        ),
                                ),
                                labelStyle: TextStyle(
                                  color: selected
                                      ? (_isDark ? _textOnAccent : _accent)
                                      : _textPrimary,
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
                        style: TextStyle(
                          color: _textSecondary,
                          fontSize: 12.6,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _publicPaymentOptionsChipSection(),
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
                                        fr: 'Téléverser le logo public',
                                        es: 'Subir logo público',
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
                                        fr: 'Téléverser la couverture publique',
                                        es: 'Subir portada pública',
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
                            fr: 'Avancé : URLs publiques manuelles (secours)',
                            es: 'Avanzado: URLs públicas manuales (respaldo)',
                          ),
                          style: TextStyle(
                            color: _textSecondary,
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
                              es: 'URL del logo público',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          _txt(
                            _publicHeroPhotoUrlCtrl,
                            _t(
                              nl: 'Publieke coverfoto-URL',
                              en: 'Public cover photo URL',
                              fr: 'URL de la photo de couverture publique',
                              es: 'URL de la foto de portada pública',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          if (_publicLogoUrlCtrl.text.trim().isNotEmpty &&
                              !_isPublicHttpsUrl(_publicLogoUrlCtrl.text)) ...[
                            Text(
                              _t(
                                nl: 'Waarschuwing: logo-URL moet met https:// starten om gepubliceerd te worden.',
                                en: 'Warning: logo URL must start with https:// to be published.',
                                fr: 'Avertissement : l’URL du logo doit commencer par https:// pour être publiée.',
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
                              !_isPublicHttpsUrl(
                                _publicHeroPhotoUrlCtrl.text,
                              )) ...[
                            Text(
                              _t(
                                nl: 'Waarschuwing: coverfoto-URL moet met https:// starten om gepubliceerd te worden.',
                                en: 'Warning: cover photo URL must start with https:// to be published.',
                                fr: 'Avertissement : l’URL de couverture doit commencer par https:// pour être publiée.',
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
                      _limousineReadinessSummary(),
                      const SizedBox(height: 10),
                      // LIMOUSINE-MARKETPLACE-P2B2 — publication surface only.
                      // Read-only mirror of what will be published; pricing is
                      // authored in "Limousine offers and pricing".
                      _limousineOffersPublicPreview(),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _publicPartnerProfilePublishing
                            ? null
                            : _publishPublicPartnerProfile,
                        icon: _publicPartnerProfilePublishing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.publish_outlined),
                        label: Text(
                          _t(
                            nl: 'Publiek profiel publiceren',
                            en: 'Publish public profile',
                            fr: 'Publier le profil public',
                            es: 'Publicar perfil público',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          nl: 'Gebruik alleen publieke HTTPS-links. Lokale foto’s worden niet gepubliceerd.',
                          en: 'Use public HTTPS links only. Local photos are not published.',
                          fr: 'Les photos locales ne sont pas encore publiées. Seules les images HTTPS publiques sont incluses.',
                          es: 'Las fotos locales aún no se publican. Solo se incluyen imágenes HTTPS públicas.',
                        ),
                        style: TextStyle(color: _textMuted, fontSize: 11),
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
                          _publicPartnerProfilePublishedAt
                              .trim()
                              .isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _t(
                            nl: 'Laatst gepubliceerd op: ${_publicPartnerProfilePublishedAt.trim()}',
                            en: 'Last published at: ${_publicPartnerProfilePublishedAt.trim()}',
                            fr: 'Derniere publication: ${_publicPartnerProfilePublishedAt.trim()}',
                            es: 'Ultima publicacion: ${_publicPartnerProfilePublishedAt.trim()}',
                          ),
                          style: TextStyle(color: _textMuted, fontSize: 10.8),
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
              if (_shouldShowSection('branding_support'))
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
                          DropdownMenuItem(
                            value: AppLanguage.de,
                            child: Text('Deutsch'),
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
                          fillColor: _inputFill,
                        ),
                        dropdownColor: _subPanelBg,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _defaultCurrency,
                        items: const ['EUR', 'USD', 'GBP', 'CHF']
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
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
                          fillColor: _inputFill,
                        ),
                        dropdownColor: _subPanelBg,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _taxLabel,
                        items: const ['BTW', 'VAT', 'TVA', 'IVA', 'GST', 'Tax']
                            .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)),
                            )
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
                          fillColor: _inputFill,
                        ),
                        dropdownColor: _subPanelBg,
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
              if (_shouldShowSection('pricing_engine'))
                _collapsibleSettingsCard(
                  id: 'pricing_engine',
                  icon: Icons.local_offer_outlined,
                  title: _t(
                    nl: 'Pricing engine',
                    en: 'Pricing engine',
                    fr: 'Moteur tarifaire',
                    es: 'Motor de precios',
                  ),
                  subtitle: _pricingSetupSubtitle(),
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
                        onChanged: _onPricingFieldEdited,
                      ),
                      _txt(
                        _perKmCtrl,
                        _t(
                          nl: 'Prijs per km',
                          en: 'Price per km',
                          fr: 'Prix par km',
                          es: 'Precio por km',
                        ),
                        onChanged: _onPricingFieldEdited,
                      ),
                      _txt(
                        _perMinCtrl,
                        _t(
                          nl: 'Prijs per minuut',
                          en: 'Price per minute',
                          fr: 'Prix par minute',
                          es: 'Precio por minuto',
                        ),
                        onChanged: _onPricingFieldEdited,
                      ),
                      _txt(
                        _minimumFareCtrl,
                        _t(
                          nl: 'Minimumtarief',
                          en: 'Minimum fare',
                          fr: 'Tarif minimum',
                          es: 'Tarifa minima',
                        ),
                        onChanged: _onPricingFieldEdited,
                      ),
                      _txt(
                        _waitPerMinCtrl,
                        _t(
                          nl: 'Wachttarief per minuut',
                          en: 'Waiting price per minute',
                          fr: 'Tarif d attente par minute',
                          es: 'Tarifa de espera por minuto',
                        ),
                        onChanged: _onPricingFieldEdited,
                      ),
                      Builder(
                        builder: (_) {
                          final vat = _activeVatConfig();
                          final vatPercent = (vat.vatRate * 100).clamp(
                            0.0,
                            100.0,
                          );
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
                              style: TextStyle(color: _textMuted, fontSize: 12),
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
                        onChanged: (v) =>
                            setState(() => _pricingReturnEnabled = v),
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
              if (_shouldShowSection('cancellation_policy'))
                _cancellationPolicyCard(),
              if (_shouldShowSection('service_setup'))
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
                    fr: 'Services, categories et options',
                    es: 'Servicios, categorias y opciones',
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
              if (_shouldShowSection('airport_fixed_fares'))
                _airportFixedFareCard(),
              // LIMOUSINE-MARKETPLACE-P2B2 — dedicated, visually and
              // semantically separate from the taxi pricing engine and the
              // airport fixed fares above.
              if (_shouldShowSection('limousine_offers_pricing'))
                _limousineOffersCard(),
            ],
          ),
          bottomNavigationBar: BusinessSettingsStickySaveBar(
            background: _pageBg,
            busy: _saveAllBusy,
            continueMode: _isActiveStepMode,
            onPressed: _saveAllBusy
                ? null
                : (_isActiveStepMode ? _saveAndContinue : _save),
            label: _isActiveStepMode
                ? _t(
                    nl: 'Opslaan en verder',
                    en: 'Save and continue',
                    fr: 'Enregistrer et continuer',
                    es: 'Guardar y continuar',
                  )
                : _t(
                    nl: 'Alles opslaan en publiceren',
                    en: 'Save and publish everything',
                    fr: 'Tout enregistrer et publier',
                    es: 'Guardar y publicar todo',
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Official company details — supported country options + normalization.
//
// Keep this list aligned with what BusinessSettings persists in
// `BackendBusinessProfile.country`. The code (column 0) is the value stored.
// Columns 1..4 are display labels in nl/en/fr/es. Used by the in-page
// dropdown and by [_normalizeBusinessCountryCode] to translate legacy free
// text values into a canonical ISO-style code on hydrate.
// ---------------------------------------------------------------------------
const List<List<String>> _kBusinessCountryCodes = <List<String>>[
  <String>['BE', 'België', 'Belgium', 'Belgique', 'Bélgica'],
  <String>['NL', 'Nederland', 'Netherlands', 'Pays-Bas', 'Países Bajos'],
  <String>['LU', 'Luxemburg', 'Luxembourg', 'Luxembourg', 'Luxemburgo'],
  <String>['FR', 'Frankrijk', 'France', 'France', 'Francia'],
  <String>['DE', 'Duitsland', 'Germany', 'Allemagne', 'Alemania'],
  <String>['ES', 'Spanje', 'Spain', 'Espagne', 'España'],
  <String>['PT', 'Portugal', 'Portugal', 'Portugal', 'Portugal'],
  <String>[
    'GB',
    'Verenigd Koninkrijk',
    'United Kingdom',
    'Royaume-Uni',
    'Reino Unido',
  ],
];

String _stripBusinessCountryDiacritics(String input) {
  const fromMap = 'àáäâãèéëêìíïîòóöôõùúüûñç';
  const toMap = 'aaaaaeeeeiiiioooooouuuunc';
  final buffer = StringBuffer();
  for (final ch in input.runes) {
    final source = String.fromCharCode(ch);
    final idx = fromMap.indexOf(source);
    buffer.write(idx >= 0 ? toMap[idx] : source);
  }
  return buffer.toString();
}

/// Normalizes a free-text or ISO country value to one of the codes supported
/// by the business country dropdown: BE, NL, LU, FR, DE, ES, PT, GB.
///
/// Returns an empty string when the input does not map to a supported code,
/// so callers can preserve unknown legacy values without overwriting them.
String _normalizeBusinessCountryCode(String? value) {
  if (value == null) return '';
  final raw = value.trim();
  if (raw.isEmpty) return '';
  final upper = raw.toUpperCase();
  if (upper.length == 2) {
    if (upper == 'UK') return 'GB';
    for (final entry in _kBusinessCountryCodes) {
      if (entry[0] == upper) return upper;
    }
  }
  final norm = _stripBusinessCountryDiacritics(raw.toLowerCase());
  for (final entry in _kBusinessCountryCodes) {
    for (var i = 1; i < entry.length; i++) {
      if (_stripBusinessCountryDiacritics(entry[i].toLowerCase()) == norm) {
        return entry[0];
      }
    }
  }
  switch (norm) {
    case 'belgie':
      return 'BE';
    case 'holanda':
    case 'paises bajos':
      return 'NL';
    case 'deutschland':
      return 'DE';
    case 'great britain':
      return 'GB';
  }
  return '';
}
