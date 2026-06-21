import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/chiron_company_connection_config.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';

class CompanyIdentityConfig {
  final String companyName;
  final String appTitle;
  final String logoAsset;
  final String companyShortName;
  final String supportEmail;
  final String supportPhone;

  const CompanyIdentityConfig({
    required this.companyName,
    required this.appTitle,
    required this.logoAsset,
    required this.companyShortName,
    required this.supportEmail,
    required this.supportPhone,
  });
}

class BrandingConfig {
  final Color primaryColor;
  final Color accentColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final Color cardColor;
  final Color textSoftColor;
  final Color softAccentColor;
  final Color calculatorScaffoldColor;
  final Color calculatorPanelColor;
  final Color calculatorDropdownColor;

  const BrandingConfig({
    required this.primaryColor,
    required this.accentColor,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.cardColor,
    required this.textSoftColor,
    required this.softAccentColor,
    required this.calculatorScaffoldColor,
    required this.calculatorPanelColor,
    required this.calculatorDropdownColor,
  });
}

class BusinessDefaultsConfig {
  final String defaultCurrency;
  final String defaultCurrencySymbol;
  final String taxDisplayLabel;
  final double defaultVatRate;
  final String distanceUnitLabel;
  final String durationUnitLabel;
  final bool use24HourTime;
  final bool showDetailedBreakdown;

  const BusinessDefaultsConfig({
    required this.defaultCurrency,
    required this.defaultCurrencySymbol,
    required this.taxDisplayLabel,
    required this.defaultVatRate,
    required this.distanceUnitLabel,
    required this.durationUnitLabel,
    required this.use24HourTime,
    required this.showDetailedBreakdown,
  });
}

class AppOption {
  final String id;
  final LocalizedText label;
  final String payloadValue;

  const AppOption({
    required this.id,
    required this.label,
    required this.payloadValue,
  });

  String labelFor(AppLanguage language) => label.of(language);
}

class AppFeatures {
  final bool calculatorEnabled;
  final bool trackingEnabled;
  final bool liveMapEnabled;
  final bool bookingsEnabled;

  const AppFeatures({
    required this.calculatorEnabled,
    required this.trackingEnabled,
    required this.liveMapEnabled,
    required this.bookingsEnabled,
  });
}

class BusinessSettingsState {
  final String companyName;
  final String supportEmail;
  final String supportPhone;
  final String address;
  final String vatCompanyNumber;
  final String logoAssetPath;
  final AppLanguage defaultLanguage;
  final String defaultCurrency;
  final String taxLabel;
  final bool use24HourTime;
  final Set<String> enabledServiceIds;
  final Set<String> enabledTierIds;
  final Set<String> enabledExtraOptionIds;
  final String bookingSender;
  final String bookingReplyTo;
  final String whatsappNumber;
  final double pricingBaseFare;
  final double pricingPerKm;
  final double pricingPerMinute;
  final double pricingMinimumFare;
  final double pricingWaitPerMinute;
  final bool pricingReturnEnabled;
  final double pricingReturnFee;
  final double pricingFuelSurcharge;
  final double pricingVatRate;
  final String pricingVatMode;
  final double pricingBagFeeEach;
  final double pricingStopFeeEach;
  final double pricingTierFeeComfort;
  final double pricingTierFeePrivate;
  final double pricingTierFeePremium;
  final double pricingNightSurchargeRate;
  final double pricingWeekendSurchargeRate;
  final double pricingSurchargeCapRate;
  final bool chironEnabled;
  final String chironEnvironment;
  final String chironConnectionStatus;
  final String chironRegionScope;
  final String chironLastTestedAt;
  final bool chironProductionEnabled;

  const BusinessSettingsState({
    required this.companyName,
    required this.supportEmail,
    required this.supportPhone,
    required this.address,
    required this.vatCompanyNumber,
    required this.logoAssetPath,
    required this.defaultLanguage,
    required this.defaultCurrency,
    required this.taxLabel,
    required this.use24HourTime,
    required this.enabledServiceIds,
    required this.enabledTierIds,
    required this.enabledExtraOptionIds,
    required this.bookingSender,
    required this.bookingReplyTo,
    required this.whatsappNumber,
    required this.pricingBaseFare,
    required this.pricingPerKm,
    required this.pricingPerMinute,
    required this.pricingMinimumFare,
    required this.pricingWaitPerMinute,
    required this.pricingReturnEnabled,
    required this.pricingReturnFee,
    required this.pricingFuelSurcharge,
    required this.pricingVatRate,
    required this.pricingVatMode,
    required this.pricingBagFeeEach,
    required this.pricingStopFeeEach,
    required this.pricingTierFeeComfort,
    required this.pricingTierFeePrivate,
    required this.pricingTierFeePremium,
    required this.pricingNightSurchargeRate,
    required this.pricingWeekendSurchargeRate,
    required this.pricingSurchargeCapRate,
    this.chironEnabled = ChironCompanyConnectionDefaults.chironEnabled,
    this.chironEnvironment = ChironCompanyConnectionDefaults.chironEnvironment,
    this.chironConnectionStatus =
        ChironCompanyConnectionDefaults.chironConnectionStatus,
    this.chironRegionScope = ChironCompanyConnectionDefaults.chironRegionScope,
    this.chironLastTestedAt =
        ChironCompanyConnectionDefaults.chironLastTestedAt,
    this.chironProductionEnabled =
        ChironCompanyConnectionDefaults.chironProductionEnabled,
  });

  BusinessSettingsState copyWith({
    String? companyName,
    String? supportEmail,
    String? supportPhone,
    String? address,
    String? vatCompanyNumber,
    String? logoAssetPath,
    AppLanguage? defaultLanguage,
    String? defaultCurrency,
    String? taxLabel,
    bool? use24HourTime,
    Set<String>? enabledServiceIds,
    Set<String>? enabledTierIds,
    Set<String>? enabledExtraOptionIds,
    String? bookingSender,
    String? bookingReplyTo,
    String? whatsappNumber,
    double? pricingBaseFare,
    double? pricingPerKm,
    double? pricingPerMinute,
    double? pricingMinimumFare,
    double? pricingWaitPerMinute,
    bool? pricingReturnEnabled,
    double? pricingReturnFee,
    double? pricingFuelSurcharge,
    double? pricingVatRate,
    String? pricingVatMode,
    double? pricingBagFeeEach,
    double? pricingStopFeeEach,
    double? pricingTierFeeComfort,
    double? pricingTierFeePrivate,
    double? pricingTierFeePremium,
    double? pricingNightSurchargeRate,
    double? pricingWeekendSurchargeRate,
    double? pricingSurchargeCapRate,
    bool? chironEnabled,
    String? chironEnvironment,
    String? chironConnectionStatus,
    String? chironRegionScope,
    String? chironLastTestedAt,
    bool? chironProductionEnabled,
  }) {
    return BusinessSettingsState(
      companyName: companyName ?? this.companyName,
      supportEmail: supportEmail ?? this.supportEmail,
      supportPhone: supportPhone ?? this.supportPhone,
      address: address ?? this.address,
      vatCompanyNumber: vatCompanyNumber ?? this.vatCompanyNumber,
      logoAssetPath: logoAssetPath ?? this.logoAssetPath,
      defaultLanguage: defaultLanguage ?? this.defaultLanguage,
      defaultCurrency: defaultCurrency ?? this.defaultCurrency,
      taxLabel: taxLabel ?? this.taxLabel,
      use24HourTime: use24HourTime ?? this.use24HourTime,
      enabledServiceIds: enabledServiceIds ?? this.enabledServiceIds,
      enabledTierIds: enabledTierIds ?? this.enabledTierIds,
      enabledExtraOptionIds:
          enabledExtraOptionIds ?? this.enabledExtraOptionIds,
      bookingSender: bookingSender ?? this.bookingSender,
      bookingReplyTo: bookingReplyTo ?? this.bookingReplyTo,
      whatsappNumber: whatsappNumber ?? this.whatsappNumber,
      pricingBaseFare: pricingBaseFare ?? this.pricingBaseFare,
      pricingPerKm: pricingPerKm ?? this.pricingPerKm,
      pricingPerMinute: pricingPerMinute ?? this.pricingPerMinute,
      pricingMinimumFare: pricingMinimumFare ?? this.pricingMinimumFare,
      pricingWaitPerMinute: pricingWaitPerMinute ?? this.pricingWaitPerMinute,
      pricingReturnEnabled: pricingReturnEnabled ?? this.pricingReturnEnabled,
      pricingReturnFee: pricingReturnFee ?? this.pricingReturnFee,
      pricingFuelSurcharge: pricingFuelSurcharge ?? this.pricingFuelSurcharge,
      pricingVatRate: pricingVatRate ?? this.pricingVatRate,
      pricingVatMode: pricingVatMode ?? this.pricingVatMode,
      pricingBagFeeEach: pricingBagFeeEach ?? this.pricingBagFeeEach,
      pricingStopFeeEach: pricingStopFeeEach ?? this.pricingStopFeeEach,
      pricingTierFeeComfort:
          pricingTierFeeComfort ?? this.pricingTierFeeComfort,
      pricingTierFeePrivate:
          pricingTierFeePrivate ?? this.pricingTierFeePrivate,
      pricingTierFeePremium:
          pricingTierFeePremium ?? this.pricingTierFeePremium,
      pricingNightSurchargeRate:
          pricingNightSurchargeRate ?? this.pricingNightSurchargeRate,
      pricingWeekendSurchargeRate:
          pricingWeekendSurchargeRate ?? this.pricingWeekendSurchargeRate,
      pricingSurchargeCapRate:
          pricingSurchargeCapRate ?? this.pricingSurchargeCapRate,
      chironEnabled: chironEnabled ?? this.chironEnabled,
      chironEnvironment: chironEnvironment ?? this.chironEnvironment,
      chironConnectionStatus:
          chironConnectionStatus ?? this.chironConnectionStatus,
      chironRegionScope: chironRegionScope ?? this.chironRegionScope,
      chironLastTestedAt: chironLastTestedAt ?? this.chironLastTestedAt,
      chironProductionEnabled:
          chironProductionEnabled ?? this.chironProductionEnabled,
    );
  }
}

class BackendBusinessProfile {
  final String companyCode;
  final String publicCompanyCode;
  final String publicCompanySlug;
  final String publicDisplayCode;
  final String companyName;
  final String legalName;
  final String vatNumber;
  final String companyRegistrationNumber;
  final String address;
  final String postcode;
  final String city;
  final String country;
  final String phone;
  final String email;
  final String website;
  final String bookingEmail;
  final String publicLogoUrl;
  final String publicHeroPhotoUrl;
  final String publicServedPostcodes;
  final String publicCoverageLat;
  final String publicCoverageLng;
  final String publicServiceRadiusKm;
  final List<String> publicPaymentOptions;
  final List<String> publicServiceIds;
  final bool publicServicesConfigured;
  final String publicPartnerProfilePublishedAt;
  final String publicPartnerProfilePublishStatus;
  final String invoiceEmail;
  final String iban;
  final String paymentReferencePrefix;
  final String invoiceReceiptFooterText;
  final String paymentOwnerMode;
  final bool paymentDemoMode;
  final bool mollieConnected;
  final bool? livePaymentsEnabled;
  final bool? mollieForcedTestMode;
  final String mollieOrganizationId;
  final String mollieProfileId;
  final String mollieTokenRef;

  const BackendBusinessProfile({
    this.companyCode = '',
    this.publicCompanyCode = '',
    this.publicCompanySlug = '',
    this.publicDisplayCode = '',
    required this.companyName,
    required this.legalName,
    required this.vatNumber,
    required this.companyRegistrationNumber,
    required this.address,
    required this.postcode,
    required this.city,
    required this.country,
    required this.phone,
    required this.email,
    required this.website,
    required this.bookingEmail,
    this.publicLogoUrl = '',
    this.publicHeroPhotoUrl = '',
    this.publicServedPostcodes = '',
    this.publicCoverageLat = '',
    this.publicCoverageLng = '',
    this.publicServiceRadiusKm = '',
    this.publicPaymentOptions = const <String>[],
    this.publicServiceIds = const <String>[],
    this.publicServicesConfigured = false,
    this.publicPartnerProfilePublishedAt = '',
    this.publicPartnerProfilePublishStatus = '',
    required this.invoiceEmail,
    required this.iban,
    required this.paymentReferencePrefix,
    required this.invoiceReceiptFooterText,
    this.paymentOwnerMode = 'fluxidi_central_demo',
    this.paymentDemoMode = true,
    this.mollieConnected = false,
    this.livePaymentsEnabled,
    this.mollieForcedTestMode,
    this.mollieOrganizationId = '',
    this.mollieProfileId = '',
    this.mollieTokenRef = '',
  });

  factory BackendBusinessProfile.defaults() => BackendBusinessProfile(
    companyName: appConfig.companyName,
    legalName: appConfig.companyName,
    vatNumber: '',
    companyRegistrationNumber: '',
    address: '',
    postcode: '',
    city: '',
    country: 'BE',
    phone: appConfig.supportPhone,
    email: appConfig.supportEmail,
    website: '',
    bookingEmail: '',
    publicLogoUrl: '',
    publicHeroPhotoUrl: '',
    publicServedPostcodes: '',
    publicCoverageLat: '',
    publicCoverageLng: '',
    publicServiceRadiusKm: '',
    publicPaymentOptions: const <String>[],
    publicServiceIds: const <String>[],
    publicServicesConfigured: false,
    publicPartnerProfilePublishedAt: '',
    publicPartnerProfilePublishStatus: '',
    invoiceEmail: appConfig.supportEmail,
    iban: '',
    paymentReferencePrefix: 'FLX',
    invoiceReceiptFooterText: '',
    paymentOwnerMode: 'fluxidi_central_demo',
    paymentDemoMode: true,
    mollieConnected: false,
  );

  factory BackendBusinessProfile.fromJson(Map<String, dynamic> json) {
    final fallback = BackendBusinessProfile.defaults();
    String text(String key, String fallbackValue) =>
        (json[key] ?? fallbackValue).toString();
    String textAny(List<String> keys, String fallbackValue) {
      for (final key in keys) {
        final v = json[key];
        if (v == null) continue;
        final s = v.toString();
        if (s.trim().isNotEmpty) return s;
      }
      return fallbackValue;
    }

    List<String> textListAny(List<String> keys, List<String> fallbackValue) {
      for (final key in keys) {
        final raw = json[key];
        if (raw is List) {
          final out = raw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList(growable: false);
          if (out.isNotEmpty) return out;
          continue;
        }
        final text = raw?.toString().trim() ?? '';
        if (text.isEmpty) continue;
        final out = text
            .split(RegExp(r'[\s,;]+'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList(growable: false);
        if (out.isNotEmpty) return out;
      }
      return fallbackValue;
    }

    bool? boolOptional(dynamic value) {
      if (value is bool) return value;
      return null;
    }

    return BackendBusinessProfile(
      companyCode: textAny(const [
        'company_code',
        'companyCode',
      ], fallback.companyCode),
      publicCompanyCode: textAny(const [
        'public_company_code',
        'publicCompanyCode',
        'company_code',
        'companyCode',
      ], fallback.publicCompanyCode),
      publicCompanySlug: textAny(const [
        'public_company_slug',
        'publicCompanySlug',
      ], fallback.publicCompanySlug),
      publicDisplayCode: textAny(const [
        'public_display_code',
        'publicDisplayCode',
      ], fallback.publicDisplayCode),
      companyName: text('companyName', fallback.companyName),
      legalName: text('legalName', fallback.legalName),
      vatNumber: text('vatNumber', fallback.vatNumber),
      companyRegistrationNumber: text(
        'companyRegistrationNumber',
        fallback.companyRegistrationNumber,
      ),
      address: text('address', fallback.address),
      postcode: text('postcode', fallback.postcode),
      city: text('city', fallback.city),
      country: text('country', fallback.country),
      phone: text('phone', fallback.phone),
      email: text('email', fallback.email),
      website: text('website', fallback.website),
      bookingEmail: text('bookingEmail', fallback.bookingEmail),
      publicLogoUrl: textAny(const [
        'publicLogoUrl',
        'public_logo_url',
      ], fallback.publicLogoUrl),
      publicHeroPhotoUrl: textAny(const [
        'publicHeroPhotoUrl',
        'public_hero_photo_url',
      ], fallback.publicHeroPhotoUrl),
      publicServedPostcodes: textAny(const [
        'publicServedPostcodes',
        'public_served_postcodes',
      ], fallback.publicServedPostcodes),
      publicCoverageLat: textAny(const [
        'publicCoverageLat',
        'public_coverage_lat',
      ], fallback.publicCoverageLat),
      publicCoverageLng: textAny(const [
        'publicCoverageLng',
        'public_coverage_lng',
      ], fallback.publicCoverageLng),
      publicServiceRadiusKm: textAny(const [
        'publicServiceRadiusKm',
        'public_service_radius_km',
      ], fallback.publicServiceRadiusKm),
      publicPaymentOptions: textListAny(const [
        'publicPaymentOptions',
        'public_payment_options',
      ], fallback.publicPaymentOptions),
      publicServiceIds: textListAny(const [
        'publicServiceIds',
        'public_service_ids',
      ], fallback.publicServiceIds),
      publicServicesConfigured:
          (json['publicServicesConfigured'] ??
                  json['public_services_configured'])
              is bool
          ? ((json['publicServicesConfigured'] ??
                    json['public_services_configured'])
                as bool)
          : (textListAny(const [
                  'publicServiceIds',
                  'public_service_ids',
                ], const <String>[]).isNotEmpty ||
                fallback.publicServicesConfigured),
      publicPartnerProfilePublishedAt: textAny(const [
        'publicPartnerProfilePublishedAt',
        'public_partner_profile_published_at',
      ], fallback.publicPartnerProfilePublishedAt),
      publicPartnerProfilePublishStatus: textAny(const [
        'publicPartnerProfilePublishStatus',
        'public_partner_profile_publish_status',
      ], fallback.publicPartnerProfilePublishStatus),
      invoiceEmail: text('invoiceEmail', fallback.invoiceEmail),
      iban: text('iban', fallback.iban),
      paymentReferencePrefix: text(
        'paymentReferencePrefix',
        fallback.paymentReferencePrefix,
      ),
      invoiceReceiptFooterText: text(
        'invoiceReceiptFooterText',
        fallback.invoiceReceiptFooterText,
      ),
      paymentOwnerMode: textAny(const [
        'paymentOwnerMode',
        'payment_owner_mode',
      ], fallback.paymentOwnerMode),
      paymentDemoMode:
          (json['paymentDemoMode'] ?? json['payment_demo_mode']) is bool
          ? ((json['paymentDemoMode'] ?? json['payment_demo_mode']) as bool)
          : fallback.paymentDemoMode,
      mollieConnected:
          (json['mollieConnected'] ?? json['mollie_connected']) is bool
          ? ((json['mollieConnected'] ?? json['mollie_connected']) as bool)
          : fallback.mollieConnected,
      livePaymentsEnabled: boolOptional(
        json['livePaymentsEnabled'] ?? json['live_payments_enabled'],
      ),
      mollieForcedTestMode: boolOptional(
        json['mollieForcedTestMode'] ??
            json['mollie_forced_testmode'] ??
            json['forced_testmode'] ??
            json['forcedTestmode'],
      ),
      mollieOrganizationId: textAny(const [
        'mollieOrganizationId',
        'mollie_organization_id',
      ], fallback.mollieOrganizationId),
      mollieProfileId: textAny(const [
        'mollieProfileId',
        'mollie_profile_id',
      ], fallback.mollieProfileId),
      mollieTokenRef: textAny(const [
        'mollieTokenRef',
        'mollie_token_ref',
      ], fallback.mollieTokenRef),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (companyCode.trim().isNotEmpty) ...<String, dynamic>{
      'company_code': companyCode,
      'companyCode': companyCode,
    },
    if (publicCompanyCode.trim().isNotEmpty) ...<String, dynamic>{
      'public_company_code': publicCompanyCode,
      'publicCompanyCode': publicCompanyCode,
    },
    if (publicCompanySlug.trim().isNotEmpty) ...<String, dynamic>{
      'public_company_slug': publicCompanySlug,
      'publicCompanySlug': publicCompanySlug,
    },
    if (publicDisplayCode.trim().isNotEmpty) ...<String, dynamic>{
      'public_display_code': publicDisplayCode,
      'publicDisplayCode': publicDisplayCode,
    },
    'companyName': companyName,
    'legalName': legalName,
    'vatNumber': vatNumber,
    'companyRegistrationNumber': companyRegistrationNumber,
    'address': address,
    'postcode': postcode,
    'city': city,
    'country': country,
    'phone': phone,
    'email': email,
    'website': website,
    'bookingEmail': bookingEmail,
    'publicLogoUrl': publicLogoUrl,
    'public_logo_url': publicLogoUrl,
    'publicHeroPhotoUrl': publicHeroPhotoUrl,
    'public_hero_photo_url': publicHeroPhotoUrl,
    'publicServedPostcodes': publicServedPostcodes,
    'public_served_postcodes': publicServedPostcodes,
    'publicCoverageLat': publicCoverageLat,
    'public_coverage_lat': publicCoverageLat,
    'publicCoverageLng': publicCoverageLng,
    'public_coverage_lng': publicCoverageLng,
    'publicServiceRadiusKm': publicServiceRadiusKm,
    'public_service_radius_km': publicServiceRadiusKm,
    'publicPaymentOptions': publicPaymentOptions,
    'public_payment_options': publicPaymentOptions,
    'publicServiceIds': publicServiceIds,
    'public_service_ids': publicServiceIds,
    'publicServicesConfigured': publicServicesConfigured,
    'public_services_configured': publicServicesConfigured,
    'publicPartnerProfilePublishedAt': publicPartnerProfilePublishedAt,
    'public_partner_profile_published_at': publicPartnerProfilePublishedAt,
    'publicPartnerProfilePublishStatus': publicPartnerProfilePublishStatus,
    'public_partner_profile_publish_status': publicPartnerProfilePublishStatus,
    'invoiceEmail': invoiceEmail,
    'iban': iban,
    'paymentReferencePrefix': paymentReferencePrefix,
    'invoiceReceiptFooterText': invoiceReceiptFooterText,
    'paymentOwnerMode': paymentOwnerMode,
    'payment_owner_mode': paymentOwnerMode,
    'paymentDemoMode': paymentDemoMode,
    'payment_demo_mode': paymentDemoMode,
    'mollieConnected': mollieConnected,
    'mollie_connected': mollieConnected,
    if (livePaymentsEnabled != null) ...<String, dynamic>{
      'livePaymentsEnabled': livePaymentsEnabled,
      'live_payments_enabled': livePaymentsEnabled,
    },
    if (mollieForcedTestMode != null) ...<String, dynamic>{
      'mollieForcedTestMode': mollieForcedTestMode,
      'mollie_forced_testmode': mollieForcedTestMode,
      'forced_testmode': mollieForcedTestMode,
      'forcedTestmode': mollieForcedTestMode,
    },
    'mollieOrganizationId': mollieOrganizationId,
    'mollie_organization_id': mollieOrganizationId,
    'mollieProfileId': mollieProfileId,
    'mollie_profile_id': mollieProfileId,
    'mollieTokenRef': mollieTokenRef,
    'mollie_token_ref': mollieTokenRef,
  };
}

class BackendTaxProfile {
  final bool vatEnabled;
  final double vatRate;
  final String vatDisplayMode;
  final Map<String, String> vatLabels;

  const BackendTaxProfile({
    required this.vatEnabled,
    required this.vatRate,
    required this.vatDisplayMode,
    required this.vatLabels,
  });

  factory BackendTaxProfile.defaults() => BackendTaxProfile(
    vatEnabled: true,
    vatRate: appConfig.defaultVatRate,
    vatDisplayMode: 'excl',
    vatLabels: const <String, String>{
      'nl': 'BTW',
      'en': 'VAT',
      'fr': 'TVA',
      'es': 'IVA',
    },
  );

  factory BackendTaxProfile.fromJson(Map<String, dynamic> json) {
    final fallback = BackendTaxProfile.defaults();
    final rawRate = json['vatRate'] ?? json['vat_rate'];
    final parsedRate = rawRate is num
        ? rawRate.toDouble()
        : double.tryParse(rawRate?.toString().replaceAll(',', '.') ?? '');
    final labels = json['vatLabels'] is Map
        ? Map<String, dynamic>.from(json['vatLabels'] as Map)
        : const <String, dynamic>{};
    String label(String key) =>
        (labels[key] ?? fallback.vatLabels[key] ?? '').toString();
    final mode =
        (json['vatDisplayMode'] ?? json['vat_mode'] ?? fallback.vatDisplayMode)
            .toString()
            .trim()
            .toLowerCase();
    return BackendTaxProfile(
      vatEnabled: json['vatEnabled'] is bool
          ? json['vatEnabled'] as bool
          : fallback.vatEnabled,
      vatRate: parsedRate == null || !parsedRate.isFinite
          ? fallback.vatRate
          : parsedRate.clamp(0.0, 1.0).toDouble(),
      vatDisplayMode: mode == 'incl' ? 'incl' : 'excl',
      vatLabels: <String, String>{
        'nl': label('nl'),
        'en': label('en'),
        'fr': label('fr'),
        'es': label('es'),
      },
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'vatEnabled': vatEnabled,
    'vatRate': vatRate,
    'vatDisplayMode': vatDisplayMode,
    'vatLabels': vatLabels,
  };
}

class BackendCancellationPolicyProfile {
  final int version;
  final bool allowCustomerOnlineCancellation;
  final int taxiCutoffMinutes;
  final int airportCutoffMinutes;
  final int businessCutoffMinutes;
  final String paidBookingCancellationMode;
  final bool blockWhenDriverEnRoute;
  final int driverEnRouteEtaCutoffMinutes;
  final double driverEnRouteDistanceCutoffKm;
  final int driverLocationFreshnessSeconds;
  final int driverHandoffBufferMinutes;
  final String updatedAt;

  const BackendCancellationPolicyProfile({
    required this.version,
    required this.allowCustomerOnlineCancellation,
    required this.taxiCutoffMinutes,
    required this.airportCutoffMinutes,
    required this.businessCutoffMinutes,
    required this.paidBookingCancellationMode,
    required this.blockWhenDriverEnRoute,
    required this.driverEnRouteEtaCutoffMinutes,
    required this.driverEnRouteDistanceCutoffKm,
    required this.driverLocationFreshnessSeconds,
    required this.driverHandoffBufferMinutes,
    required this.updatedAt,
  });

  factory BackendCancellationPolicyProfile.defaults() =>
      const BackendCancellationPolicyProfile(
        version: 1,
        allowCustomerOnlineCancellation: true,
        taxiCutoffMinutes: 120,
        airportCutoffMinutes: 1440,
        businessCutoffMinutes: 1440,
        paidBookingCancellationMode: 'review_required',
        blockWhenDriverEnRoute: false,
        driverEnRouteEtaCutoffMinutes: 15,
        driverEnRouteDistanceCutoffKm: 10,
        driverLocationFreshnessSeconds: 300,
        driverHandoffBufferMinutes: 15,
        updatedAt: '',
      );

  factory BackendCancellationPolicyProfile.fromJson(Map<String, dynamic> json) {
    final fallback = BackendCancellationPolicyProfile.defaults();

    int intValue(String snake, String camel, int fallbackValue) {
      final raw = json[snake] ?? json[camel];
      final n = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
      if (n == null || n < 0) return fallbackValue;
      return n;
    }

    int boundedIntValue(
      String snake,
      String camel,
      int fallbackValue, {
      required int min,
      required int max,
    }) {
      final value = intValue(snake, camel, fallbackValue);
      if (value < min || value > max) return fallbackValue;
      return value;
    }

    bool boolValue(String snake, String camel, bool fallbackValue) {
      final raw = json[snake] ?? json[camel];
      if (raw is bool) return raw;
      final text = (raw ?? '').toString().trim().toLowerCase();
      if (text == 'true' || text == '1' || text == 'yes') return true;
      if (text == 'false' || text == '0' || text == 'no') return false;
      return fallbackValue;
    }

    String textValue(String snake, String camel, String fallbackValue) {
      final text = (json[snake] ?? json[camel] ?? fallbackValue)
          .toString()
          .trim();
      return text.isEmpty ? fallbackValue : text;
    }

    double boundedDoubleValue(
      String snake,
      String camel,
      double fallbackValue, {
      required double min,
      required double max,
    }) {
      final raw = json[snake] ?? json[camel];
      final parsed = raw is num
          ? raw.toDouble()
          : double.tryParse((raw ?? '').toString().replaceAll(',', '.'));
      if (parsed == null || !parsed.isFinite) return fallbackValue;
      if (parsed < min || parsed > max) return fallbackValue;
      return parsed;
    }

    final mode = textValue(
      'paid_booking_cancellation_mode',
      'paidBookingCancellationMode',
      fallback.paidBookingCancellationMode,
    ).toLowerCase();

    return BackendCancellationPolicyProfile(
      version: intValue('version', 'version', fallback.version),
      allowCustomerOnlineCancellation: boolValue(
        'allow_customer_online_cancellation',
        'allowCustomerOnlineCancellation',
        fallback.allowCustomerOnlineCancellation,
      ),
      taxiCutoffMinutes: intValue(
        'taxi_cutoff_minutes',
        'taxiCutoffMinutes',
        fallback.taxiCutoffMinutes,
      ),
      airportCutoffMinutes: intValue(
        'airport_cutoff_minutes',
        'airportCutoffMinutes',
        fallback.airportCutoffMinutes,
      ),
      businessCutoffMinutes: intValue(
        'business_cutoff_minutes',
        'businessCutoffMinutes',
        fallback.businessCutoffMinutes,
      ),
      paidBookingCancellationMode: mode.isEmpty
          ? fallback.paidBookingCancellationMode
          : mode,
      blockWhenDriverEnRoute: boolValue(
        'block_when_driver_en_route',
        'blockWhenDriverEnRoute',
        fallback.blockWhenDriverEnRoute,
      ),
      driverEnRouteEtaCutoffMinutes: boundedIntValue(
        'driver_en_route_eta_cutoff_minutes',
        'driverEnRouteEtaCutoffMinutes',
        fallback.driverEnRouteEtaCutoffMinutes,
        min: 0,
        max: 240,
      ),
      driverEnRouteDistanceCutoffKm: boundedDoubleValue(
        'driver_en_route_distance_cutoff_km',
        'driverEnRouteDistanceCutoffKm',
        fallback.driverEnRouteDistanceCutoffKm,
        min: 0,
        max: 100,
      ),
      driverLocationFreshnessSeconds: boundedIntValue(
        'driver_location_freshness_seconds',
        'driverLocationFreshnessSeconds',
        fallback.driverLocationFreshnessSeconds,
        min: 30,
        max: 3600,
      ),
      driverHandoffBufferMinutes: boundedIntValue(
        'driver_handoff_buffer_minutes',
        'driverHandoffBufferMinutes',
        fallback.driverHandoffBufferMinutes,
        min: 0,
        max: 120,
      ),
      updatedAt: textValue('updated_at', 'updatedAt', fallback.updatedAt),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': version,
    'allow_customer_online_cancellation': allowCustomerOnlineCancellation,
    'allowCustomerOnlineCancellation': allowCustomerOnlineCancellation,
    'taxi_cutoff_minutes': taxiCutoffMinutes,
    'taxiCutoffMinutes': taxiCutoffMinutes,
    'airport_cutoff_minutes': airportCutoffMinutes,
    'airportCutoffMinutes': airportCutoffMinutes,
    'business_cutoff_minutes': businessCutoffMinutes,
    'businessCutoffMinutes': businessCutoffMinutes,
    'paid_booking_cancellation_mode': paidBookingCancellationMode,
    'paidBookingCancellationMode': paidBookingCancellationMode,
    'block_when_driver_en_route': blockWhenDriverEnRoute,
    'blockWhenDriverEnRoute': blockWhenDriverEnRoute,
    'driver_en_route_eta_cutoff_minutes': driverEnRouteEtaCutoffMinutes,
    'driverEnRouteEtaCutoffMinutes': driverEnRouteEtaCutoffMinutes,
    'driver_en_route_distance_cutoff_km': driverEnRouteDistanceCutoffKm,
    'driverEnRouteDistanceCutoffKm': driverEnRouteDistanceCutoffKm,
    'driver_location_freshness_seconds': driverLocationFreshnessSeconds,
    'driverLocationFreshnessSeconds': driverLocationFreshnessSeconds,
    'driver_handoff_buffer_minutes': driverHandoffBufferMinutes,
    'driverHandoffBufferMinutes': driverHandoffBufferMinutes,
    'updated_at': updatedAt,
    'updatedAt': updatedAt,
  };

  Map<String, dynamic> toApiPayload() => <String, dynamic>{
    'allow_customer_online_cancellation': allowCustomerOnlineCancellation,
    'taxi_cutoff_minutes': taxiCutoffMinutes,
    'airport_cutoff_minutes': airportCutoffMinutes,
    'business_cutoff_minutes': businessCutoffMinutes,
    'paid_booking_cancellation_mode': paidBookingCancellationMode,
    'block_when_driver_en_route': blockWhenDriverEnRoute,
    'driver_en_route_eta_cutoff_minutes': driverEnRouteEtaCutoffMinutes,
    'driver_en_route_distance_cutoff_km': driverEnRouteDistanceCutoffKm,
    'driver_location_freshness_seconds': driverLocationFreshnessSeconds,
    'driver_handoff_buffer_minutes': driverHandoffBufferMinutes,
  };
}

class BackendSubscriptionProfile {
  final String tenantId;
  final String companyId;
  final String plan;
  final String status;
  final String trialStartedAt;
  final String trialEndsAt;
  final String billingEmail;
  final int includedVehicles;
  final int maxVehicles;
  final int maxDrivers;
  final Map<String, bool> features;
  final String createdAt;
  final String updatedAt;

  const BackendSubscriptionProfile({
    required this.tenantId,
    required this.companyId,
    required this.plan,
    required this.status,
    required this.trialStartedAt,
    required this.trialEndsAt,
    required this.billingEmail,
    required this.includedVehicles,
    required this.maxVehicles,
    required this.maxDrivers,
    required this.features,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BackendSubscriptionProfile.defaults() =>
      const BackendSubscriptionProfile(
        tenantId: '',
        companyId: '',
        plan: 'starter',
        status: 'trialing',
        trialStartedAt: '',
        trialEndsAt: '',
        billingEmail: '',
        includedVehicles: 1,
        maxVehicles: 1,
        maxDrivers: 3,
        features: <String, bool>{
          'ai_assistant': false,
          'airport_module': false,
          'live_dispatch': false,
          'ev_dispatch': false,
          'compliance_dashboard': true,
          'white_label_branding': false,
          'public_booking': false,
          'receipt_pdf': true,
          'whatsapp_email_receipts': true,
        },
        createdAt: '',
        updatedAt: '',
      );

  factory BackendSubscriptionProfile.fromJson(Map<String, dynamic> json) {
    final fallback = BackendSubscriptionProfile.defaults();
    final featuresRaw = json['features'];
    final featuresIn = featuresRaw is Map
        ? Map<String, dynamic>.from(featuresRaw)
        : const <String, dynamic>{};
    bool feature(String key, bool fallbackValue) {
      final v = featuresIn[key];
      return v is bool ? v : fallbackValue;
    }

    int intVal(String snake, String camel, int fallbackValue) {
      final raw = json[snake] ?? json[camel];
      final n = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
      if (n == null || n < 0) return fallbackValue;
      return n;
    }

    String text(String snake, String camel, String fallbackValue) =>
        (json[snake] ?? json[camel] ?? fallbackValue).toString();

    return BackendSubscriptionProfile(
      tenantId: text('tenant_id', 'tenantId', fallback.tenantId),
      companyId: text('company_id', 'companyId', fallback.companyId),
      plan: text('plan', 'plan', fallback.plan).trim().toLowerCase(),
      status: text('status', 'status', fallback.status).trim().toLowerCase(),
      trialStartedAt: text(
        'trial_started_at',
        'trialStartedAt',
        fallback.trialStartedAt,
      ),
      trialEndsAt: text('trial_ends_at', 'trialEndsAt', fallback.trialEndsAt),
      billingEmail: text(
        'billing_email',
        'billingEmail',
        fallback.billingEmail,
      ),
      includedVehicles: intVal(
        'included_vehicles',
        'includedVehicles',
        fallback.includedVehicles,
      ),
      maxVehicles: intVal('max_vehicles', 'maxVehicles', fallback.maxVehicles),
      maxDrivers: intVal('max_drivers', 'maxDrivers', fallback.maxDrivers),
      features: <String, bool>{
        'ai_assistant': feature(
          'ai_assistant',
          fallback.features['ai_assistant'] ?? false,
        ),
        'airport_module': feature(
          'airport_module',
          fallback.features['airport_module'] ?? false,
        ),
        'live_dispatch': feature(
          'live_dispatch',
          fallback.features['live_dispatch'] ?? false,
        ),
        'ev_dispatch': feature(
          'ev_dispatch',
          fallback.features['ev_dispatch'] ?? false,
        ),
        'compliance_dashboard': feature(
          'compliance_dashboard',
          fallback.features['compliance_dashboard'] ?? true,
        ),
        'white_label_branding': feature(
          'white_label_branding',
          fallback.features['white_label_branding'] ?? false,
        ),
        'public_booking': feature(
          'public_booking',
          fallback.features['public_booking'] ?? false,
        ),
        'receipt_pdf': feature(
          'receipt_pdf',
          fallback.features['receipt_pdf'] ?? true,
        ),
        'whatsapp_email_receipts': feature(
          'whatsapp_email_receipts',
          fallback.features['whatsapp_email_receipts'] ?? true,
        ),
      },
      createdAt: text('created_at', 'createdAt', fallback.createdAt),
      updatedAt: text('updated_at', 'updatedAt', fallback.updatedAt),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'tenant_id': tenantId,
    'company_id': companyId,
    'plan': plan,
    'status': status,
    'trial_started_at': trialStartedAt,
    'trial_ends_at': trialEndsAt,
    'billing_email': billingEmail,
    'included_vehicles': includedVehicles,
    'max_vehicles': maxVehicles,
    'max_drivers': maxDrivers,
    'features': features,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

class ActiveVatConfig {
  final bool vatEnabled;
  final double vatRate;
  final String vatMode;

  const ActiveVatConfig({
    required this.vatEnabled,
    required this.vatRate,
    required this.vatMode,
  });
}

ActiveVatConfig resolveActiveVatConfig({
  BusinessSettingsState? settings,
  BackendTaxProfile? taxProfile,
}) {
  final fallbackSettings = settings ?? businessSettingsNotifier.value;
  final fallbackRateRaw = fallbackSettings.pricingVatRate;
  final fallbackRate = fallbackRateRaw.isFinite
      ? fallbackRateRaw.clamp(0.0, 1.0).toDouble()
      : appConfig.defaultVatRate;
  final fallbackMode =
      fallbackSettings.pricingVatMode.trim().toLowerCase() == 'incl'
      ? 'incl'
      : 'excl';

  final source = taxProfile ?? localBackendTaxProfileNotifier.value;
  final enabled = source?.vatEnabled ?? true;
  final mode =
      (source?.vatDisplayMode ?? fallbackMode).trim().toLowerCase() == 'incl'
      ? 'incl'
      : 'excl';
  final rateRaw = source?.vatRate ?? fallbackRate;
  final rate = rateRaw.isFinite ? rateRaw.clamp(0.0, 1.0).toDouble() : 0.0;
  return ActiveVatConfig(
    vatEnabled: enabled,
    vatRate: enabled ? rate : 0.0,
    vatMode: mode,
  );
}

class VehicleProfile {
  final String id;
  final String vehicleName;
  final String brandModel;
  final String licensePlate;
  final String exploitationLicenseNumber;
  final String vehicleRegistrationNumber;
  final String color;
  final int passengerCapacity;
  final int luggageCapacity;
  final String tierId;
  final bool isActive;
  final String? driverId;

  /// Local tenant ownership (nullable = legacy MVP rows before this field existed).
  /// TODO(backend): authoritative tenant id comes from the server; never trust client-side ids alone.
  final String? companyId;
  final String primaryPhotoRef;
  final List<String> galleryPhotoRefs;
  final String? publicPhotoUrl;
  // Backward-compatible alias for legacy UI/code paths.
  String get photoRef => primaryPhotoRef;

  String? get tenantId => companyId;

  const VehicleProfile({
    required this.id,
    required this.vehicleName,
    required this.brandModel,
    required this.licensePlate,
    this.exploitationLicenseNumber = '',
    this.vehicleRegistrationNumber = '',
    required this.color,
    required this.passengerCapacity,
    required this.luggageCapacity,
    required this.tierId,
    required this.isActive,
    required this.driverId,
    this.companyId,
    required this.primaryPhotoRef,
    required this.galleryPhotoRefs,
    this.publicPhotoUrl,
  });

  VehicleProfile copyWith({
    String? id,
    String? vehicleName,
    String? brandModel,
    String? licensePlate,
    String? exploitationLicenseNumber,
    String? vehicleRegistrationNumber,
    String? color,
    int? passengerCapacity,
    int? luggageCapacity,
    String? tierId,
    bool? isActive,
    String? driverId,
    String? companyId,
    String? primaryPhotoRef,
    List<String>? galleryPhotoRefs,
    String? publicPhotoUrl,
  }) {
    return VehicleProfile(
      id: id ?? this.id,
      vehicleName: vehicleName ?? this.vehicleName,
      brandModel: brandModel ?? this.brandModel,
      licensePlate: licensePlate ?? this.licensePlate,
      exploitationLicenseNumber:
          exploitationLicenseNumber ?? this.exploitationLicenseNumber,
      vehicleRegistrationNumber:
          vehicleRegistrationNumber ?? this.vehicleRegistrationNumber,
      color: color ?? this.color,
      passengerCapacity: passengerCapacity ?? this.passengerCapacity,
      luggageCapacity: luggageCapacity ?? this.luggageCapacity,
      tierId: tierId ?? this.tierId,
      isActive: isActive ?? this.isActive,
      driverId: driverId ?? this.driverId,
      companyId: companyId ?? this.companyId,
      primaryPhotoRef: primaryPhotoRef ?? this.primaryPhotoRef,
      galleryPhotoRefs: galleryPhotoRefs ?? this.galleryPhotoRefs,
      publicPhotoUrl: publicPhotoUrl ?? this.publicPhotoUrl,
    );
  }
}

class DriverProfile {
  final String id;
  final String fullName;
  final String employeeNumber;
  final bool hasLoginCode;
  final String? driverCodeLast4;
  final String? loginCodeLast4;
  final String phone;
  final String taxiDriverCardNumber;
  final String taxiDriverCardExpiry;
  final bool isActive;
  final String? profilePhotoPath;
  final bool publicProfileEnabled;
  final bool publicPhotoEnabled;
  final String? publicDisplayName;
  final String? publicPortraitUrl;
  final String availabilityStatus;
  final double? ratingAvg;
  final int? ratingCount;

  /// See [VehicleProfile.companyId].
  final String? companyId;

  String? get tenantId => companyId;

  const DriverProfile({
    required this.id,
    required this.fullName,
    required this.employeeNumber,
    this.hasLoginCode = false,
    this.driverCodeLast4,
    this.loginCodeLast4,
    required this.phone,
    this.taxiDriverCardNumber = '',
    this.taxiDriverCardExpiry = '',
    required this.isActive,
    this.profilePhotoPath,
    this.publicProfileEnabled = false,
    this.publicPhotoEnabled = false,
    this.publicDisplayName,
    this.publicPortraitUrl,
    this.availabilityStatus = 'available',
    this.ratingAvg,
    this.ratingCount,
    this.companyId,
  });

  DriverProfile copyWith({
    String? id,
    String? fullName,
    String? employeeNumber,
    bool? hasLoginCode,
    Object? driverCodeLast4 = _driverProfileUnset,
    Object? loginCodeLast4 = _driverProfileUnset,
    String? phone,
    String? taxiDriverCardNumber,
    String? taxiDriverCardExpiry,
    bool? isActive,
    Object? profilePhotoPath = _driverProfileUnset,
    bool? publicProfileEnabled,
    bool? publicPhotoEnabled,
    Object? publicDisplayName = _driverProfileUnset,
    Object? publicPortraitUrl = _driverProfileUnset,
    String? availabilityStatus,
    Object? ratingAvg = _driverProfileUnset,
    Object? ratingCount = _driverProfileUnset,
    String? companyId,
  }) {
    return DriverProfile(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      employeeNumber: employeeNumber ?? this.employeeNumber,
      hasLoginCode: hasLoginCode ?? this.hasLoginCode,
      driverCodeLast4: identical(driverCodeLast4, _driverProfileUnset)
          ? this.driverCodeLast4
          : driverCodeLast4 as String?,
      loginCodeLast4: identical(loginCodeLast4, _driverProfileUnset)
          ? this.loginCodeLast4
          : loginCodeLast4 as String?,
      phone: phone ?? this.phone,
      taxiDriverCardNumber: taxiDriverCardNumber ?? this.taxiDriverCardNumber,
      taxiDriverCardExpiry: taxiDriverCardExpiry ?? this.taxiDriverCardExpiry,
      isActive: isActive ?? this.isActive,
      profilePhotoPath: identical(profilePhotoPath, _driverProfileUnset)
          ? this.profilePhotoPath
          : profilePhotoPath as String?,
      publicProfileEnabled: publicProfileEnabled ?? this.publicProfileEnabled,
      publicPhotoEnabled: publicPhotoEnabled ?? this.publicPhotoEnabled,
      publicDisplayName: identical(publicDisplayName, _driverProfileUnset)
          ? this.publicDisplayName
          : publicDisplayName as String?,
      publicPortraitUrl: identical(publicPortraitUrl, _driverProfileUnset)
          ? this.publicPortraitUrl
          : publicPortraitUrl as String?,
      availabilityStatus: normalizeDriverAvailabilityState(
        availabilityStatus ?? this.availabilityStatus,
      ),
      ratingAvg: identical(ratingAvg, _driverProfileUnset)
          ? this.ratingAvg
          : ratingAvg as double?,
      ratingCount: identical(ratingCount, _driverProfileUnset)
          ? this.ratingCount
          : ratingCount as int?,
      companyId: companyId ?? this.companyId,
    );
  }
}

const Object _driverProfileUnset = Object();

String normalizeDriverAvailabilityState(
  dynamic raw, {
  String fallback = 'available',
}) {
  final text = (raw ?? '').toString().trim().toLowerCase();
  switch (text) {
    case 'available':
    case 'ready':
    case 'online':
      return 'available';
    case 'paused':
    case 'pause':
    case 'not_available':
    case 'unavailable':
      return 'paused';
    case 'offline':
      return 'offline';
    case 'busy':
    case 'on_trip':
    case 'on_the_way':
    case 'waiting':
      return 'busy';
    default:
      final normalizedFallback = fallback.toString().trim().toLowerCase();
      if (normalizedFallback == 'paused' ||
          normalizedFallback == 'offline' ||
          normalizedFallback == 'busy') {
        return normalizedFallback;
      }
      return 'available';
  }
}

bool driverAvailabilityAllowsDispatch(String availabilityStatus) {
  final normalized = normalizeDriverAvailabilityState(
    availabilityStatus,
    fallback: 'available',
  );
  return normalized == 'available';
}

enum FleetUpsellMode { includedOnly, perVehicleMonthly, tierUpgrade }

class FleetSubscriptionPolicy {
  final int includedVehicles;
  final FleetUpsellMode upsellMode;
  final double additionalVehicleMonthlyPrice;

  const FleetSubscriptionPolicy({
    required this.includedVehicles,
    required this.upsellMode,
    required this.additionalVehicleMonthlyPrice,
  });
}

class AppConfig {
  final CompanyIdentityConfig identity;
  final BrandingConfig branding;
  final BusinessDefaultsConfig businessDefaults;
  final String workerBaseUrl;
  final String bookingBaseUrl;
  final AppLanguage defaultLanguage;
  final List<AppOption> enabledServices;
  final List<AppOption> enabledTiers;
  final List<AppOption> enabledExtraOptions;
  final AppLabels labels;
  final AppFeatures features;

  const AppConfig({
    required this.identity,
    required this.branding,
    required this.businessDefaults,
    required this.workerBaseUrl,
    required this.bookingBaseUrl,
    required this.defaultLanguage,
    required this.enabledServices,
    required this.enabledTiers,
    required this.enabledExtraOptions,
    required this.labels,
    required this.features,
  });

  // Backward-compatible aliases for existing code usage.
  String get companyName => identity.companyName;
  String get appTitle => identity.appTitle;
  String get logoAsset => identity.logoAsset;
  String get companyShortName => identity.companyShortName;
  String get supportEmail => identity.supportEmail;
  String get supportPhone => identity.supportPhone;

  Color get primaryColor => branding.primaryColor;
  Color get accentColor => branding.accentColor;
  Color get backgroundColor => branding.backgroundColor;

  String get defaultCurrency => businessDefaults.defaultCurrency;
  String get defaultCurrencySymbol => businessDefaults.defaultCurrencySymbol;
  String get taxDisplayLabel => businessDefaults.taxDisplayLabel;
  double get defaultVatRate => businessDefaults.defaultVatRate;
  String get distanceUnitLabel => businessDefaults.distanceUnitLabel;
  String get durationUnitLabel => businessDefaults.durationUnitLabel;
  bool get use24HourTime => businessDefaults.use24HourTime;
  bool get showDetailedBreakdown => businessDefaults.showDetailedBreakdown;
  AppLanguage get currentLanguage => appLanguageNotifier.value;
  AppStrings get strings => AppStrings.forLanguage(currentLanguage);
}

final ValueNotifier<AppLanguage> appLanguageNotifier =
    ValueNotifier<AppLanguage>(AppLanguage.en);

const String kTenantId = 'fluxidi';
const String kCompanyId = kTenantId;
const String kPublicBookingBaseUrl = String.fromEnvironment(
  'PUBLIC_BOOKING_BASE_URL',
  defaultValue: 'https://fluxidi-booking-api.fluxidi.workers.dev',
);
const String kBookingBaseUrlOverride = String.fromEnvironment(
  'BOOKING_BASE_URL',
  defaultValue: '',
);
const String kMapboxToken = String.fromEnvironment(
  'MAPBOX_TOKEN',
  defaultValue: '',
);
// Booking.com CJ affiliate/deeplink only — not Demand API, not native inventory, no iframe.
// Pending until CJ approves the BENELUX program and BOOKING_COM_CJ_BASE_URL is configured.
const String kBookingComCjBaseUrl = String.fromEnvironment(
  'BOOKING_COM_CJ_BASE_URL',
  defaultValue: '',
);

bool get kBookingComCjConfigured {
  final base = kBookingComCjBaseUrl.trim();
  if (base.isEmpty) return false;
  final uri = Uri.tryParse(base);
  if (uri == null || !uri.hasScheme) return false;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

String get kBookingBaseUrl {
  final v = kBookingBaseUrlOverride.trim();
  if (v.isNotEmpty) return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  return appConfig.bookingBaseUrl;
}

/// True when [raw] looks like a private/local filesystem or app asset reference.
bool isLocalOrPrivateMediaRef(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return true;
  final lower = text.toLowerCase();
  if (lower.startsWith('assets/')) return true;
  if (lower.startsWith('file://') || lower.startsWith('content://')) {
    return true;
  }
  if (lower.contains(r':\') || RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(text)) {
    return true;
  }
  if (text.startsWith(r'\\')) return true;
  if (lower.startsWith('/data/') ||
      lower.startsWith('/storage/') ||
      lower.startsWith('/sdcard/') ||
      lower.startsWith('/var/mobile/') ||
      lower.startsWith('/private/var/mobile/') ||
      lower.startsWith('/var/containers/')) {
    return true;
  }
  if (lower.startsWith('/') && !lower.startsWith('/public/media/')) {
    return true;
  }
  if (lower.startsWith('.') && !lower.startsWith('https://')) return true;
  return false;
}

/// Resolves partner media refs to an HTTPS booking-worker URL for public output.
/// Returns empty when the input is missing, local/private, or non-HTTPS.
String resolvePublicHttpsMediaUrl(String raw, {String? bookingBaseUrl}) {
  final text = raw.trim();
  if (text.isEmpty || isLocalOrPrivateMediaRef(text)) return '';
  final lower = text.toLowerCase();
  if (lower.startsWith('https://')) return text;
  if (lower.startsWith('http://')) return '';

  final base = (bookingBaseUrl ?? kBookingBaseUrl).trim();
  if (base.isEmpty) return '';
  final normalizedBase = base.endsWith('/')
      ? base.substring(0, base.length - 1)
      : base;

  if (lower.startsWith('/public/media/')) {
    return '$normalizedBase$text';
  }
  if (lower.startsWith('public-media/')) {
    final suffix = text.substring('public-media/'.length).trim();
    if (suffix.isEmpty) return '';
    return '$normalizedBase/public/media/$suffix';
  }
  return '';
}

enum AppRole { customer, driver, companyAdmin, dispatcher }

final ValueNotifier<AppRole> appRoleNotifier = ValueNotifier<AppRole>(
  AppRole.driver,
);

void setAppRole(AppRole role) {
  if (appRoleNotifier.value == role) return;
  appRoleNotifier.value = role;
}

void setAppLanguage(AppLanguage language) {
  if (appLanguageNotifier.value == language) return;
  appLanguageNotifier.value = language;
}

String get currentLanguageCode {
  switch (appLanguageNotifier.value) {
    case AppLanguage.nl:
      return 'nl';
    case AppLanguage.en:
      return 'en';
    case AppLanguage.fr:
      return 'fr';
    case AppLanguage.es:
      return 'es';
  }
}

void setAppLanguageByCode(String code) {
  switch (code) {
    case 'nl':
      setAppLanguage(AppLanguage.nl);
      return;
    case 'en':
      setAppLanguage(AppLanguage.en);
      return;
    case 'fr':
      setAppLanguage(AppLanguage.fr);
      return;
    case 'es':
      setAppLanguage(AppLanguage.es);
      return;
    default:
      return;
  }
}

final ValueNotifier<BusinessSettingsState> businessSettingsNotifier =
    ValueNotifier<BusinessSettingsState>(
      BusinessSettingsState(
        companyName: appConfig.companyName,
        supportEmail: appConfig.supportEmail,
        supportPhone: appConfig.supportPhone,
        address: '',
        vatCompanyNumber: '',
        logoAssetPath: appConfig.logoAsset,
        defaultLanguage: appConfig.defaultLanguage,
        defaultCurrency: appConfig.defaultCurrency,
        taxLabel: appConfig.taxDisplayLabel,
        use24HourTime: appConfig.use24HourTime,
        enabledServiceIds: appConfig.enabledServices.map((o) => o.id).toSet(),
        enabledTierIds: appConfig.enabledTiers.map((o) => o.id).toSet(),
        enabledExtraOptionIds: appConfig.enabledExtraOptions
            .map((o) => o.id)
            .toSet(),
        bookingSender: appConfig.supportEmail,
        bookingReplyTo: appConfig.supportEmail,
        whatsappNumber: appConfig.supportPhone,
        pricingBaseFare: 3.0,
        pricingPerKm: 1.50,
        pricingPerMinute: 0.0,
        pricingMinimumFare: 3.0,
        pricingWaitPerMinute: 40.0 / 60.0,
        pricingReturnEnabled: true,
        pricingReturnFee: 0.0,
        pricingFuelSurcharge: 0.0,
        pricingVatRate: appConfig.defaultVatRate,
        pricingVatMode: 'excl',
        pricingBagFeeEach: 5.0,
        pricingStopFeeEach: 7.5,
        pricingTierFeeComfort: 0.0,
        pricingTierFeePrivate: 5.0,
        pricingTierFeePremium: 10.0,
        pricingNightSurchargeRate: 0.12,
        pricingWeekendSurchargeRate: 0.08,
        pricingSurchargeCapRate: 0.20,
      ),
    );

void updateBusinessSettings(
  BusinessSettingsState next, {
  String? tenantId,
  String? companyId,
  bool syncToBackend = true,
}) {
  businessSettingsNotifier.value = next;
  _persistLocalTenantState();
  if (syncToBackend) {
    unawaited(
      syncPricingProfileToBackend(tenantId: tenantId, companyId: companyId),
    );
  }
}

final ValueNotifier<List<VehicleProfile>> vehiclesNotifier =
    ValueNotifier<List<VehicleProfile>>(<VehicleProfile>[
      const VehicleProfile(
        id: 'vh_1',
        vehicleName: 'Hoofdwagen',
        brandModel: 'Tesla Model 3',
        licensePlate: '1-ABC-123',
        color: 'Zwart',
        passengerCapacity: 3,
        luggageCapacity: 3,
        tierId: 'premium',
        isActive: true,
        driverId: null,
        companyId: null,
        primaryPhotoRef: '',
        galleryPhotoRefs: <String>[],
      ),
    ]);

final ValueNotifier<List<DriverProfile>> driversNotifier =
    ValueNotifier<List<DriverProfile>>(<DriverProfile>[
      const DriverProfile(
        id: 'drv_1',
        fullName: 'Standaard chauffeur',
        employeeNumber: 'DRV-001',
        phone: '+32 000 00 00 01',
        isActive: true,
        companyId: null,
      ),
    ]);

final Map<String, Set<String>> _deletedDriverIdsByScope =
    <String, Set<String>>{};

String _normalizedDriverIdForTombstone(String value) => value.trim();

String _deletedDriverScopeKey({
  required String tenantId,
  required String companyId,
}) {
  final normalizedTenant = tenantId.trim();
  final normalizedCompany = companyId.trim();
  if (normalizedTenant.isEmpty || normalizedCompany.isEmpty) return '';
  return '$normalizedTenant::$normalizedCompany';
}

Set<String> _deletedDriverIdsForScope({
  required String tenantId,
  required String companyId,
}) {
  final key = _deletedDriverScopeKey(tenantId: tenantId, companyId: companyId);
  if (key.isEmpty) return const <String>{};
  return _deletedDriverIdsByScope[key] ?? const <String>{};
}

bool _isDriverIdTombstonedForScope({
  required String tenantId,
  required String companyId,
  required String driverId,
}) {
  final normalizedDriverId = _normalizedDriverIdForTombstone(driverId);
  if (normalizedDriverId.isEmpty) return false;
  final ids = _deletedDriverIdsForScope(
    tenantId: tenantId,
    companyId: companyId,
  );
  return ids.contains(normalizedDriverId);
}

void _markDeletedDriverForScope({
  required String tenantId,
  required String companyId,
  required String driverId,
}) {
  final normalizedDriverId = _normalizedDriverIdForTombstone(driverId);
  if (normalizedDriverId.isEmpty) return;
  final key = _deletedDriverScopeKey(tenantId: tenantId, companyId: companyId);
  if (key.isEmpty) return;
  final current = _deletedDriverIdsByScope[key] ?? <String>{};
  current.add(normalizedDriverId);
  _deletedDriverIdsByScope[key] = current;
}

Map<String, dynamic> _encodeDeletedDriverTombstonesForPersistence() {
  if (_deletedDriverIdsByScope.isEmpty) return const <String, dynamic>{};
  final out = <String, dynamic>{};
  for (final entry in _deletedDriverIdsByScope.entries) {
    final ids =
        entry.value
            .map((e) => _normalizedDriverIdForTombstone(e))
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    if (ids.isEmpty) continue;
    out[entry.key] = ids;
  }
  return out;
}

void _decodeDeletedDriverTombstonesFromPersistence(dynamic raw) {
  _deletedDriverIdsByScope.clear();
  if (raw is! Map) return;
  for (final entry in raw.entries) {
    final key = entry.key.toString().trim();
    if (key.isEmpty) continue;
    final parts = key.split('::');
    if (parts.length != 2) continue;
    final normalizedKey = _deletedDriverScopeKey(
      tenantId: parts.first,
      companyId: parts.last,
    );
    if (normalizedKey.isEmpty) continue;
    if (entry.value is! List) continue;
    final ids = <String>{};
    for (final item in (entry.value as List)) {
      final normalized = _normalizedDriverIdForTombstone('$item');
      if (normalized.isEmpty) continue;
      ids.add(normalized);
    }
    if (ids.isEmpty) continue;
    _deletedDriverIdsByScope[normalizedKey] = ids;
  }
}

String _normalizeDriverIdentityText(String raw) {
  return raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// True for the seeded demo driver (e.g. drv_1 / Standaard chauffeur).
bool isSeededOrPlaceholderDriver(DriverProfile driver) {
  final id = _normalizeDriverIdentityText(driver.id);
  final isDefaultId = id == 'drv_1';
  final employee = _normalizeDriverIdentityText(driver.employeeNumber);
  final isDefaultEmployee = employee == 'drv-001';
  final name = _normalizeDriverIdentityText(driver.fullName);
  final isDefaultName =
      name == 'standaard chauffeur' ||
      name == 'default driver' ||
      name == 'standard driver' ||
      name == 'chauffeur standard' ||
      name == 'conductor estándar';
  if (isDefaultId || isDefaultName) return true;
  return isDefaultEmployee && (isDefaultId || isDefaultName);
}

String? resolveActiveCompanyIdForFleetUi() {
  final profileCompanyId = companyProfileNotifier.value?.companyId.trim() ?? '';
  if (profileCompanyId.isNotEmpty) return profileCompanyId;
  final sessionCompanyId =
      activeCompanySessionNotifier.value?.companyId.trim() ?? '';
  if (sessionCompanyId.isNotEmpty) return sessionCompanyId;
  return null;
}

bool _fleetVehicleBelongsToScope(VehicleProfile vehicle, String companyId) {
  if (companyId.isEmpty) {
    return fleetRecordBelongsToActiveCompanyOrLegacy(vehicle.companyId);
  }
  final scoped = vehicle.companyId?.trim() ?? '';
  return scoped.isEmpty || scoped == companyId;
}

bool _isPrimaryFleetVehicleName(String rawName) {
  final normalized = rawName.trim().toLowerCase();
  return normalized == 'hoofdwagen' ||
      normalized == 'main vehicle' ||
      normalized == 'véhicule principal' ||
      normalized == 'vehículo principal';
}

List<VehicleProfile> scopedActiveFleetVehicles({String? companyId}) {
  final effectiveCompany =
      (companyId ?? resolveActiveCompanyIdForFleetUi() ?? '').trim();
  return vehiclesNotifier.value
      .where(
        (vehicle) =>
            vehicle.isActive &&
            _fleetVehicleBelongsToScope(vehicle, effectiveCompany),
      )
      .toList(growable: false);
}

String? resolvePrimaryFleetVehicleId({String? companyId}) {
  final scoped = scopedActiveFleetVehicles(companyId: companyId);
  if (scoped.isEmpty) return null;
  for (final vehicle in scoped) {
    if (_isPrimaryFleetVehicleName(vehicle.vehicleName)) {
      final vehicleId = vehicle.id.trim();
      if (vehicleId.isNotEmpty) return vehicleId;
    }
  }
  final firstId = scoped.first.id.trim();
  return firstId.isEmpty ? null : firstId;
}

String? resolveFleetDriverIdForVehicle(String vehicleId, {String? companyId}) {
  final normalizedVehicleId = vehicleId.trim();
  if (normalizedVehicleId.isEmpty) return null;
  final effectiveCompany =
      (companyId ?? resolveActiveCompanyIdForFleetUi() ?? '').trim();
  for (final vehicle in vehiclesNotifier.value) {
    if (!vehicle.isActive) continue;
    if (vehicle.id.trim() != normalizedVehicleId) continue;
    if (!_fleetVehicleBelongsToScope(vehicle, effectiveCompany)) continue;
    final driverId = vehicle.driverId?.trim() ?? '';
    return driverId.isEmpty ? null : driverId;
  }
  return null;
}

String? resolveFleetVehicleIdForDriver(String driverId, {String? companyId}) {
  final normalizedDriverId = driverId.trim();
  if (normalizedDriverId.isEmpty) return null;
  final effectiveCompany =
      (companyId ?? resolveActiveCompanyIdForFleetUi() ?? '').trim();
  for (final vehicle in vehiclesNotifier.value) {
    if (!vehicle.isActive) continue;
    final vehicleId = vehicle.id.trim();
    if (vehicleId.isEmpty) continue;
    if ((vehicle.driverId?.trim() ?? '') != normalizedDriverId) continue;
    if (!_fleetVehicleBelongsToScope(vehicle, effectiveCompany)) continue;
    return vehicleId;
  }
  return null;
}

String? resolvePrimaryFleetVehicleLinkedDriverId({String? companyId}) {
  final vehicleId = resolvePrimaryFleetVehicleId(companyId: companyId);
  if (vehicleId == null) return null;
  return resolveFleetDriverIdForVehicle(vehicleId, companyId: companyId);
}

bool isDriverFleetLinkedToVehicle({
  required String driverId,
  String? vehicleId,
  String? companyId,
}) {
  final normalizedDriverId = driverId.trim();
  if (normalizedDriverId.isEmpty) return false;
  final linkedVehicleId = resolveFleetVehicleIdForDriver(
    normalizedDriverId,
    companyId: companyId,
  );
  if (linkedVehicleId == null) return false;
  final normalizedVehicleId = (vehicleId ?? '').trim();
  if (normalizedVehicleId.isEmpty) return true;
  return linkedVehicleId == normalizedVehicleId;
}

class OperationalCockpitDriver {
  const OperationalCockpitDriver({required this.driver, required this.vehicle});

  final DriverProfile driver;
  final VehicleProfile vehicle;
}

List<OperationalCockpitDriver> resolveOperationalCockpitEligibleDrivers({
  String? companyId,
  bool logCandidates = false,
}) {
  final effectiveCompany =
      (companyId ?? resolveActiveCompanyIdForFleetUi() ?? '').trim();
  final assigned = <OperationalCockpitDriver>[];
  final seenDriverIds = <String>{};

  void logSkip(String driverId, String reason) {
    if (!logCandidates) return;
    debugPrint(
      '[DRIVER_COCKPIT][SKIP] driver=${_maskDriverIdForDiag(driverId)} reason=$reason',
    );
  }

  DriverProfile? findDriver(String driverId) {
    for (final driver in driversNotifier.value) {
      if (driver.id.trim() == driverId) return driver;
    }
    return null;
  }

  for (final vehicle in scopedActiveFleetVehicles(
    companyId: effectiveCompany,
  )) {
    final driverId = vehicle.driverId?.trim() ?? '';
    if (driverId.isEmpty || seenDriverIds.contains(driverId)) continue;
    seenDriverIds.add(driverId);

    if (effectiveCompany.isNotEmpty &&
        _isDriverIdTombstonedForScope(
          tenantId: effectiveCompany,
          companyId: effectiveCompany,
          driverId: driverId,
        )) {
      logSkip(driverId, 'deleted');
      continue;
    }

    final driver = findDriver(driverId);
    if (driver == null) {
      logSkip(driverId, 'missing_driver');
      continue;
    }
    if (!driver.isActive) {
      logSkip(driverId, 'inactive');
      continue;
    }
    if (isSeededOrPlaceholderDriver(driver)) {
      logSkip(driverId, 'placeholder');
      continue;
    }
    final driverCompany = (driver.companyId ?? '').trim();
    if (effectiveCompany.isNotEmpty &&
        driverCompany.isNotEmpty &&
        driverCompany != effectiveCompany) {
      logSkip(driverId, 'scope_mismatch');
      continue;
    }

    assigned.add(OperationalCockpitDriver(driver: driver, vehicle: vehicle));
  }

  if (logCandidates) {
    debugPrint(
      '[DRIVER_COCKPIT][ELIGIBLE] count=${assigned.length} assigned=${assigned.length}',
    );
  }
  return assigned;
}

String? standaloneDriverSessionOperationalBlockReason({
  required String driverId,
  required String? assignedVehicleId,
  required String? tenantId,
  required String? companyId,
  required List<DriverProfile> drivers,
  String? activeCompanyId,
}) {
  final normalizedDriverId = driverId.trim();
  if (normalizedDriverId.isEmpty) return null;

  final normalizedCompany = (companyId ?? '').trim();
  final activeCompany =
      (activeCompanyId ?? resolveActiveCompanyIdForFleetUi() ?? '').trim();
  final canUseActiveDriverInventory =
      normalizedCompany.isNotEmpty &&
      activeCompany.isNotEmpty &&
      normalizedCompany == activeCompany;

  if (!canUseActiveDriverInventory) return null;

  DriverProfile? matched;
  for (final driver in drivers) {
    if (driver.id.trim() != normalizedDriverId) continue;
    final driverCompany = (driver.companyId ?? '').trim();
    if (normalizedCompany.isNotEmpty &&
        driverCompany.isNotEmpty &&
        driverCompany != normalizedCompany) {
      continue;
    }
    matched = driver;
    break;
  }
  if (matched == null ||
      !matched.isActive ||
      isSeededOrPlaceholderDriver(matched)) {
    return null;
  }

  final sessionVehicleId = (assignedVehicleId ?? '').trim();
  final linkedVehicleId = resolveFleetVehicleIdForDriver(
    normalizedDriverId,
    companyId: normalizedCompany,
  );

  if (sessionVehicleId.isNotEmpty) {
    final vehicleDriverId = resolveFleetDriverIdForVehicle(
      sessionVehicleId,
      companyId: normalizedCompany,
    );
    if (vehicleDriverId != normalizedDriverId) {
      return 'vehicle_assignment_changed';
    }
    return null;
  }

  if (linkedVehicleId == null) {
    return 'no_vehicle_assigned';
  }

  return null;
}

String? standaloneDriverSessionFleetInvalidationReason({
  required String driverId,
  required String employeeNumber,
  required String? assignedVehicleId,
  required String? tenantId,
  required String? companyId,
  required List<DriverProfile> drivers,
  required bool validateVehicleAssignment,
  String? activeCompanyId,
}) {
  final normalizedDriverId = driverId.trim();
  if (normalizedDriverId.isEmpty) return 'driver_deleted';

  final normalizedTenant = (tenantId ?? '').trim();
  final normalizedCompany = (companyId ?? '').trim();
  final activeCompany =
      (activeCompanyId ?? resolveActiveCompanyIdForFleetUi() ?? '').trim();

  if (normalizedTenant.isNotEmpty &&
      normalizedCompany.isNotEmpty &&
      _isDriverIdTombstonedForScope(
        tenantId: normalizedTenant,
        companyId: normalizedCompany,
        driverId: normalizedDriverId,
      )) {
    debugPrint(
      '[DRIVER_SESSION][VALIDATE_ASSIGNMENT] session_company=${_maskCompanyScopeForLog(normalizedCompany)} active_company=${_maskCompanyScopeForLog(activeCompany)} source=scoped_bootstrap',
    );
    return 'driver_deleted';
  }

  final canUseActiveDriverInventory =
      normalizedCompany.isNotEmpty &&
      activeCompany.isNotEmpty &&
      normalizedCompany == activeCompany;

  if (!canUseActiveDriverInventory) {
    debugPrint(
      '[DRIVER_SESSION][VALIDATE_ASSIGNMENT] session_company=${_maskCompanyScopeForLog(normalizedCompany)} active_company=${_maskCompanyScopeForLog(activeCompany)} source=active_company_blocked',
    );
    if (normalizedCompany.isNotEmpty &&
        activeCompany.isNotEmpty &&
        normalizedCompany != activeCompany) {
      debugPrint(
        '[DRIVER_SESSION][INVALIDATE_SKIP] reason=active_company_mismatch_not_proof driver=${_maskDriverIdForDiag(normalizedDriverId)}',
      );
    }
    return null;
  }

  DriverProfile? matched;
  for (final driver in drivers) {
    if (driver.id.trim() != normalizedDriverId) continue;
    final driverCompany = (driver.companyId ?? '').trim();
    if (normalizedCompany.isNotEmpty &&
        driverCompany.isNotEmpty &&
        driverCompany != normalizedCompany) {
      continue;
    }
    matched = driver;
    break;
  }
  if (matched == null) {
    debugPrint(
      '[DRIVER_SESSION][VALIDATE_ASSIGNMENT] session_company=${_maskCompanyScopeForLog(normalizedCompany)} active_company=${_maskCompanyScopeForLog(activeCompany)} source=session_scope',
    );
    return 'driver_deleted';
  }
  if (!matched.isActive) return 'driver_inactive';
  if (isSeededOrPlaceholderDriver(matched)) return 'driver_deleted';

  final sessionEmployee = employeeNumber.trim();
  final profileEmployee = matched.employeeNumber.trim();
  if (sessionEmployee.isEmpty ||
      profileEmployee.isEmpty ||
      sessionEmployee.toLowerCase() != profileEmployee.toLowerCase()) {
    debugPrint(
      '[DRIVER_SESSION][VALIDATE_ASSIGNMENT] reason=employee_mismatch driver=${_maskDriverIdForDiag(normalizedDriverId)} session_company=${_maskCompanyScopeForLog(normalizedCompany)} active_company=${_maskCompanyScopeForLog(activeCompany)}',
    );
    return 'employee_mismatch';
  }

  if (!validateVehicleAssignment) return null;

  final blockReason = standaloneDriverSessionOperationalBlockReason(
    driverId: normalizedDriverId,
    assignedVehicleId: assignedVehicleId,
    tenantId: normalizedTenant,
    companyId: normalizedCompany,
    drivers: drivers,
    activeCompanyId: activeCompany,
  );
  if (blockReason == 'vehicle_assignment_changed') {
    debugPrint(
      '[DRIVER_SESSION][VALIDATE_ASSIGNMENT] driver=${_maskDriverIdForDiag(normalizedDriverId)} session_company=${_maskCompanyScopeForLog(normalizedCompany)} active_company=${_maskCompanyScopeForLog(activeCompany)} source=session_scope',
    );
    return 'vehicle_assignment_changed';
  }

  return null;
}

void _normalizeFleetVehicleDriverExclusivity({
  required String vehicleId,
  required String? newDriverId,
  String? companyId,
}) {
  final normalizedVehicleId = vehicleId.trim();
  final normalizedDriverId = (newDriverId ?? '').trim();
  if (normalizedVehicleId.isEmpty || normalizedDriverId.isEmpty) return;

  var changed = false;
  final next = vehiclesNotifier.value
      .map((vehicle) {
        if (vehicle.id.trim() == normalizedVehicleId) return vehicle;
        if ((vehicle.driverId?.trim() ?? '') != normalizedDriverId) {
          return vehicle;
        }
        if (!_fleetVehicleBelongsToScope(
          vehicle,
          (companyId ?? resolveActiveCompanyIdForFleetUi() ?? '').trim(),
        )) {
          return vehicle;
        }
        changed = true;
        debugPrint(
          '[VEHICLE_ASSIGNMENT][UNLINK] vehicle=${_maskVehicleIdForDiag(vehicle.id)} driver=${_maskDriverIdForDiag(normalizedDriverId)} reason=reassigned_elsewhere',
        );
        return vehicle.copyWith(driverId: null);
      })
      .toList(growable: false);
  if (changed) {
    vehiclesNotifier.value = next;
  }
}

({String tenantId, String companyId})? _resolveDriverSanitizeScope({
  String? tenantId,
  String? companyId,
}) {
  final explicitTenant = (tenantId ?? '').trim();
  final explicitCompany = (companyId ?? '').trim();
  if (explicitTenant.isNotEmpty && explicitCompany.isNotEmpty) {
    return (tenantId: explicitTenant, companyId: explicitCompany);
  }
  final activeCompanyId = resolveActiveCompanyIdForFleetUi();
  if (activeCompanyId != null && activeCompanyId.isNotEmpty) {
    return (tenantId: activeCompanyId, companyId: activeCompanyId);
  }
  final strictScope = _activeStrictPrivateCompanyScope();
  if (strictScope != null) return strictScope;
  return null;
}

bool _driverBelongsToSanitizeScope(DriverProfile driver, String companyId) {
  if (companyId.isEmpty) return true;
  final scoped = driver.companyId?.trim() ?? '';
  return scoped.isEmpty || scoped == companyId;
}

List<DriverProfile> sanitizeScopedDriverInventory({
  required List<DriverProfile> drivers,
  String? tenantId,
  String? companyId,
  required String reason,
}) {
  final scope = _resolveDriverSanitizeScope(
    tenantId: tenantId,
    companyId: companyId,
  );
  final effectiveTenant = scope?.tenantId ?? '';
  final effectiveCompany = scope?.companyId ?? '';

  final realDriversInScope = drivers
      .where(
        (driver) =>
            !isSeededOrPlaceholderDriver(driver) &&
            _driverBelongsToSanitizeScope(driver, effectiveCompany),
      )
      .length;

  final out = <DriverProfile>[];
  for (final driver in drivers) {
    final driverId = driver.id.trim();
    if (driverId.isEmpty) continue;

    final tombstoned =
        effectiveTenant.isNotEmpty &&
        effectiveCompany.isNotEmpty &&
        _isDriverIdTombstonedForScope(
          tenantId: effectiveTenant,
          companyId: effectiveCompany,
          driverId: driverId,
        );
    if (tombstoned) {
      debugPrint(
        '[DRIVER_MANAGEMENT][DEFAULT_FILTER] driver=${_maskDriverIdForDiag(driverId)} reason=tombstone source=$reason',
      );
      continue;
    }

    if (isSeededOrPlaceholderDriver(driver)) {
      if (realDriversInScope > 0) {
        if (effectiveTenant.isNotEmpty && effectiveCompany.isNotEmpty) {
          _markDeletedDriverForScope(
            tenantId: effectiveTenant,
            companyId: effectiveCompany,
            driverId: driverId,
          );
          debugPrint(
            '[DRIVER_MANAGEMENT][DEFAULT_TOMBSTONE] driver=${_maskDriverIdForDiag(driverId)} reason=real_drivers_exist source=$reason',
          );
        }
        debugPrint(
          '[DRIVER_MANAGEMENT][DEFAULT_SKIP_RECREATE] driver=${_maskDriverIdForDiag(driverId)} reason=real_drivers_exist count=$realDriversInScope source=$reason',
        );
        continue;
      }
      out.add(driver);
      continue;
    }

    out.add(driver);
  }
  return out;
}

void _applySanitizedDriversToNotifier({
  String? tenantId,
  String? companyId,
  required String reason,
  bool persist = false,
}) {
  final sanitized = sanitizeScopedDriverInventory(
    drivers: driversNotifier.value,
    tenantId: tenantId,
    companyId: companyId,
    reason: reason,
  );
  if (sanitized.length == driversNotifier.value.length &&
      sanitized.every(
        (driver) => driversNotifier.value.any((d) => d.id == driver.id),
      )) {
    return;
  }
  driversNotifier.value = sanitized;
  if (persist) {
    unawaited(_persistLocalTenantState());
  }
}

const FleetSubscriptionPolicy fleetSubscriptionPolicy = FleetSubscriptionPolicy(
  includedVehicles: 1,
  upsellMode: FleetUpsellMode.perVehicleMonthly,
  additionalVehicleMonthlyPrice: 49.0,
);

int get includedVehicleLimit => fleetSubscriptionPolicy.includedVehicles;
int get extraVehicleCount =>
    (vehiclesNotifier.value.length - includedVehicleLimit).clamp(0, 1000000);

String _fleetScopeIdFromLocalState() {
  for (final v in vehiclesNotifier.value) {
    final id = v.companyId?.trim() ?? '';
    if (id.isNotEmpty) return id;
  }
  for (final d in driversNotifier.value) {
    final id = d.companyId?.trim() ?? '';
    if (id.isNotEmpty) return id;
  }
  return kTenantId;
}

String _fleetScopeIdFromLocalStateStrict() {
  for (final v in vehiclesNotifier.value) {
    final id = v.companyId?.trim() ?? '';
    if (id.isNotEmpty) return id;
  }
  for (final d in driversNotifier.value) {
    final id = d.companyId?.trim() ?? '';
    if (id.isNotEmpty) return id;
  }
  return '';
}

({String tenantId, String companyId})? _activeStrictPrivateCompanyScope() {
  final localCompanyId = _fleetScopeIdFromLocalStateStrict();
  if (localCompanyId.isNotEmpty) {
    return (tenantId: localCompanyId, companyId: localCompanyId);
  }
  return null;
}

String _effectiveStrictAdminScopeId({String? tenantId, String? companyId}) {
  final explicitTenant = (tenantId ?? '').trim();
  final explicitCompany = (companyId ?? '').trim();
  if (explicitTenant.isNotEmpty || explicitCompany.isNotEmpty) {
    if (explicitTenant.isEmpty || explicitCompany.isEmpty) {
      debugPrint(
        '[PRIVATE_SCOPE][ADMIN][SKIP] reason=missing_explicit_tenant_or_company tenant=${_maskCompanyScopeForLog(explicitTenant)} company=${_maskCompanyScopeForLog(explicitCompany)}',
      );
      throw StateError('missing_tenant_scope');
    }
    if (explicitTenant != explicitCompany) {
      debugPrint(
        '[PRIVATE_SCOPE][ADMIN][SKIP] reason=tenant_company_mismatch tenant=${_maskCompanyScopeForLog(explicitTenant)} company=${_maskCompanyScopeForLog(explicitCompany)}',
      );
      throw StateError('missing_tenant_scope');
    }
    return explicitTenant;
  }
  final activeScope = _activeStrictPrivateCompanyScope();
  if (activeScope != null) {
    return activeScope.companyId;
  }
  debugPrint(
    '[PRIVATE_SCOPE][ADMIN][SKIP] reason=missing_active_company_context',
  );
  throw StateError('missing_tenant_scope');
}

void addVehicle(VehicleProfile vehicle) {
  final driverId = vehicle.driverId?.trim() ?? '';
  if (driverId.isNotEmpty) {
    _normalizeFleetVehicleDriverExclusivity(
      vehicleId: vehicle.id,
      newDriverId: driverId,
      companyId: vehicle.companyId,
    );
  }
  vehiclesNotifier.value = <VehicleProfile>[...vehiclesNotifier.value, vehicle];
  _persistLocalTenantState();
  unawaited(syncLocalCompanyInventoryToBackend(reason: 'vehicle_save'));
}

void updateVehicle(String id, VehicleProfile updated) {
  final normalizedVehicleId = id.trim();
  VehicleProfile? previous;
  for (final vehicle in vehiclesNotifier.value) {
    if (vehicle.id.trim() == normalizedVehicleId) {
      previous = vehicle;
      break;
    }
  }
  final previousDriverId = previous?.driverId?.trim() ?? '';
  final nextDriverId = updated.driverId?.trim() ?? '';
  if (nextDriverId.isNotEmpty) {
    _normalizeFleetVehicleDriverExclusivity(
      vehicleId: normalizedVehicleId,
      newDriverId: nextDriverId,
      companyId: updated.companyId,
    );
  }
  vehiclesNotifier.value = vehiclesNotifier.value
      .map((v) => v.id == id ? updated : v)
      .toList(growable: false);
  debugPrint(
    '[VEHICLE_ASSIGNMENT][LOCAL] vehicle=${_maskVehicleIdForDiag(normalizedVehicleId)} previousDriver=${_maskDriverIdForDiag(previousDriverId)} nextDriver=${_maskDriverIdForDiag(nextDriverId)}',
  );
  _persistLocalTenantState();
  unawaited(syncLocalCompanyInventoryToBackend(reason: 'vehicle_save'));
}

void deleteVehicle(String id) {
  vehiclesNotifier.value = vehiclesNotifier.value
      .where((v) => v.id != id)
      .toList(growable: false);
  _persistLocalTenantState();
}

void addDriver(DriverProfile driver) {
  final normalizedDriver = _driverWithNormalizedLoginCode(driver);
  driversNotifier.value = <DriverProfile>[
    ...driversNotifier.value,
    normalizedDriver,
  ];
  if (!isSeededOrPlaceholderDriver(normalizedDriver)) {
    _applySanitizedDriversToNotifier(reason: 'driver_add');
  }
  _persistLocalTenantState();
  unawaited(syncLocalCompanyInventoryToBackend(reason: 'driver_save'));
}

void updateDriver(
  String id,
  DriverProfile updated, {
  bool syncInventory = true,
}) {
  final normalizedUpdated = _driverWithNormalizedLoginCode(updated);
  String maskDriverForLog(String value) {
    final text = value.trim();
    if (text.isEmpty) return 'unknown';
    if (text.length <= 4) return '…${text.substring(text.length - 1)}';
    return '${text.substring(0, 2)}…${text.substring(text.length - 2)}';
  }

  debugPrint(
    '[UPDATE_DRIVER][CALLED] driver=${maskDriverForLog(id)} isActive=${normalizedUpdated.isActive} syncInventory=$syncInventory',
  );
  driversNotifier.value = driversNotifier.value
      .map((d) => d.id == id ? normalizedUpdated : d)
      .toList(growable: false);
  _persistLocalTenantState();
  if (syncInventory) {
    debugPrint(
      '[UPDATE_DRIVER][BROAD_SYNC_TRIGGERED] reason=driver_save driver=${maskDriverForLog(id)}',
    );
    unawaited(syncLocalCompanyInventoryToBackend(reason: 'driver_save'));
  }
}

DriverProfile _driverWithNormalizedLoginCode(DriverProfile driver) {
  final code = driver.employeeNumber.trim();
  if (code.isNotEmpty) return driver;
  return driver.copyWith(employeeNumber: '');
}

void deleteDriver(String id) {
  DriverProfile? existingDriver;
  for (final d in driversNotifier.value) {
    if (d.id == id) {
      existingDriver = d;
      break;
    }
  }
  final strictScope = _activeStrictPrivateCompanyScope();
  if (existingDriver != null) {
    if (strictScope != null) {
      unawaited(
        syncDriverIndexEntryToBackend(
          existingDriver,
          tenantId: strictScope.tenantId,
          companyId: strictScope.companyId,
          isActiveOverride: false,
        ),
      );
    } else {
      debugPrint(
        '[PRIVATE_SCOPE][ADMIN][SKIP] reason=missing_active_company_context op=driver_index_soft_delete',
      );
    }
  }
  driversNotifier.value = driversNotifier.value
      .where((d) => d.id != id)
      .toList(growable: false);
  vehiclesNotifier.value = vehiclesNotifier.value
      .map((v) => v.driverId == id ? v.copyWith(driverId: null) : v)
      .toList(growable: false);
  debugPrint(
    '[DRIVER_DELETE][LOCAL_REMOVE] driver=${_maskDriverIdForDiag(id)} tenant=${_maskCompanyScopeForLog(strictScope?.tenantId ?? "")} company=${_maskCompanyScopeForLog(strictScope?.companyId ?? "")}',
  );
  if (strictScope != null) {
    _markDeletedDriverForScope(
      tenantId: strictScope.tenantId,
      companyId: strictScope.companyId,
      driverId: id,
    );
    debugPrint(
      '[DRIVER_DELETE][TOMBSTONE] driver=${_maskDriverIdForDiag(id)} tenant=${_maskCompanyScopeForLog(strictScope.tenantId)} company=${_maskCompanyScopeForLog(strictScope.companyId)}',
    );
  }
  _persistLocalTenantState();
  if (strictScope != null) {
    unawaited(
      syncFleetInventoryToBackend(
        tenantId: strictScope.tenantId,
        companyId: strictScope.companyId,
      ),
    );
  } else {
    debugPrint(
      '[PRIVATE_SCOPE][ADMIN][SKIP] reason=missing_active_company_context op=fleet_sync_after_driver_delete',
    );
  }
}

void removeDriverLocallyAfterBackendDelete(
  String id, {
  String? tenantId,
  String? companyId,
}) {
  final driverId = id.trim();
  if (driverId.isEmpty) return;

  final hadDriver = driversNotifier.value.any((d) => d.id == driverId);
  final hadVehicleLinks = vehiclesNotifier.value.any(
    (v) => v.driverId == driverId,
  );
  final localChanged = hadDriver || hadVehicleLinks;

  if (localChanged) {
    driversNotifier.value = driversNotifier.value
        .where((d) => d.id != driverId)
        .toList(growable: false);
    vehiclesNotifier.value = vehiclesNotifier.value
        .map((v) => v.driverId == driverId ? v.copyWith(driverId: null) : v)
        .toList(growable: false);
  }

  late final Map<String, String> scope;
  try {
    scope = _resolveAdminTenantCompanyScope(
      tenantId: tenantId,
      companyId: companyId,
    );
  } catch (_) {
    debugPrint(
      '[PRIVATE_SCOPE][ADMIN][SKIP] reason=missing_tenant_scope op=remove_driver_locally_after_backend_delete',
    );
    _persistLocalTenantState();
    return;
  }
  debugPrint(
    '[DRIVER_DELETE][LOCAL_REMOVE] driver=${_maskDriverIdForDiag(driverId)} tenant=${_maskCompanyScopeForLog(scope["tenant_id"] ?? "")} company=${_maskCompanyScopeForLog(scope["company_id"] ?? "")}',
  );
  _markDeletedDriverForScope(
    tenantId: scope['tenant_id'] ?? '',
    companyId: scope['company_id'] ?? '',
    driverId: driverId,
  );
  debugPrint(
    '[DRIVER_DELETE][TOMBSTONE] driver=${_maskDriverIdForDiag(driverId)} tenant=${_maskCompanyScopeForLog(scope["tenant_id"] ?? "")} company=${_maskCompanyScopeForLog(scope["company_id"] ?? "")}',
  );
  _persistLocalTenantState();
  unawaited(
    syncFleetInventoryToBackend(
      tenantId: scope['tenant_id'],
      companyId: scope['company_id'],
    ),
  );
  unawaited(
    syncLocalCompanyInventoryToBackend(
      reason: 'driver_delete',
      tenantId: scope['tenant_id'],
      companyId: scope['company_id'],
    ),
  );
}

String _languageCode(AppLanguage l) {
  switch (l) {
    case AppLanguage.nl:
      return 'nl';
    case AppLanguage.en:
      return 'en';
    case AppLanguage.fr:
      return 'fr';
    case AppLanguage.es:
      return 'es';
  }
}

AppLanguage _languageFromCode(String code) {
  switch (code) {
    case 'en':
      return AppLanguage.en;
    case 'fr':
      return AppLanguage.fr;
    case 'es':
      return AppLanguage.es;
    case 'nl':
    default:
      return AppLanguage.nl;
  }
}

Map<String, dynamic> _encodeBusinessSettings(BusinessSettingsState s) {
  return <String, dynamic>{
    'companyName': s.companyName,
    'supportEmail': s.supportEmail,
    'supportPhone': s.supportPhone,
    'address': s.address,
    'vatCompanyNumber': s.vatCompanyNumber,
    'logoAssetPath': s.logoAssetPath,
    'defaultLanguage': _languageCode(s.defaultLanguage),
    'defaultCurrency': s.defaultCurrency,
    'taxLabel': s.taxLabel,
    'use24HourTime': s.use24HourTime,
    'enabledServiceIds': s.enabledServiceIds.toList(growable: false),
    'enabledTierIds': s.enabledTierIds.toList(growable: false),
    'enabledExtraOptionIds': s.enabledExtraOptionIds.toList(growable: false),
    'bookingSender': s.bookingSender,
    'bookingReplyTo': s.bookingReplyTo,
    'whatsappNumber': s.whatsappNumber,
    'pricingBaseFare': s.pricingBaseFare,
    'pricingPerKm': s.pricingPerKm,
    'pricingPerMinute': s.pricingPerMinute,
    'pricingMinimumFare': s.pricingMinimumFare,
    'pricingWaitPerMinute': s.pricingWaitPerMinute,
    'pricingReturnEnabled': s.pricingReturnEnabled,
    'pricingReturnFee': s.pricingReturnFee,
    'pricingFuelSurcharge': s.pricingFuelSurcharge,
    'pricingVatRate': s.pricingVatRate,
    'pricingVatMode': s.pricingVatMode,
    'pricingBagFeeEach': s.pricingBagFeeEach,
    'pricingStopFeeEach': s.pricingStopFeeEach,
    'pricingTierFeeComfort': s.pricingTierFeeComfort,
    'pricingTierFeePrivate': s.pricingTierFeePrivate,
    'pricingTierFeePremium': s.pricingTierFeePremium,
    'pricingNightSurchargeRate': s.pricingNightSurchargeRate,
    'pricingWeekendSurchargeRate': s.pricingWeekendSurchargeRate,
    'pricingSurchargeCapRate': s.pricingSurchargeCapRate,
    'chironEnabled': s.chironEnabled,
    'chironEnvironment': s.chironEnvironment,
    'chironConnectionStatus': s.chironConnectionStatus,
    'chironRegionScope': s.chironRegionScope,
    'chironLastTestedAt': s.chironLastTestedAt,
    'chironProductionEnabled': s.chironProductionEnabled,
  };
}

BusinessSettingsState _decodeBusinessSettings(
  Map<String, dynamic> m, {
  required BusinessSettingsState fallback,
}) {
  Set<String> setOf(dynamic v, Set<String> fb) {
    if (v is List) {
      return v.map((e) => e.toString()).toSet();
    }
    return fb;
  }

  double toDouble(dynamic v, double fb) {
    if (v is num) return v.toDouble();
    final parsed = double.tryParse((v ?? '').toString());
    return parsed ?? fb;
  }

  return fallback.copyWith(
    companyName: (m['companyName'] ?? fallback.companyName).toString(),
    supportEmail: (m['supportEmail'] ?? fallback.supportEmail).toString(),
    supportPhone: (m['supportPhone'] ?? fallback.supportPhone).toString(),
    address: (m['address'] ?? fallback.address).toString(),
    vatCompanyNumber: (m['vatCompanyNumber'] ?? fallback.vatCompanyNumber)
        .toString(),
    logoAssetPath: (m['logoAssetPath'] ?? fallback.logoAssetPath).toString(),
    defaultLanguage: _languageFromCode(
      (m['defaultLanguage'] ?? _languageCode(fallback.defaultLanguage))
          .toString(),
    ),
    defaultCurrency: (m['defaultCurrency'] ?? fallback.defaultCurrency)
        .toString(),
    taxLabel: (m['taxLabel'] ?? fallback.taxLabel).toString(),
    use24HourTime: (m['use24HourTime'] is bool)
        ? m['use24HourTime'] as bool
        : fallback.use24HourTime,
    enabledServiceIds: setOf(
      m['enabledServiceIds'],
      fallback.enabledServiceIds,
    ),
    enabledTierIds: setOf(m['enabledTierIds'], fallback.enabledTierIds),
    enabledExtraOptionIds: setOf(
      m['enabledExtraOptionIds'],
      fallback.enabledExtraOptionIds,
    ),
    bookingSender: (m['bookingSender'] ?? fallback.bookingSender).toString(),
    bookingReplyTo: (m['bookingReplyTo'] ?? fallback.bookingReplyTo).toString(),
    whatsappNumber: (m['whatsappNumber'] ?? fallback.whatsappNumber).toString(),
    pricingBaseFare: toDouble(m['pricingBaseFare'], fallback.pricingBaseFare),
    pricingPerKm: toDouble(m['pricingPerKm'], fallback.pricingPerKm),
    pricingPerMinute: toDouble(
      m['pricingPerMinute'],
      fallback.pricingPerMinute,
    ),
    pricingMinimumFare: toDouble(
      m['pricingMinimumFare'],
      fallback.pricingMinimumFare,
    ),
    pricingWaitPerMinute: toDouble(
      m['pricingWaitPerMinute'],
      fallback.pricingWaitPerMinute,
    ),
    pricingReturnEnabled: (m['pricingReturnEnabled'] is bool)
        ? m['pricingReturnEnabled'] as bool
        : fallback.pricingReturnEnabled,
    pricingReturnFee: toDouble(
      m['pricingReturnFee'],
      fallback.pricingReturnFee,
    ),
    pricingFuelSurcharge: toDouble(
      m['pricingFuelSurcharge'],
      fallback.pricingFuelSurcharge,
    ),
    pricingVatRate: toDouble(m['pricingVatRate'], fallback.pricingVatRate),
    pricingVatMode: (m['pricingVatMode'] ?? fallback.pricingVatMode).toString(),
    pricingBagFeeEach: toDouble(
      m['pricingBagFeeEach'],
      fallback.pricingBagFeeEach,
    ),
    pricingStopFeeEach: toDouble(
      m['pricingStopFeeEach'],
      fallback.pricingStopFeeEach,
    ),
    pricingTierFeeComfort: toDouble(
      m['pricingTierFeeComfort'],
      fallback.pricingTierFeeComfort,
    ),
    pricingTierFeePrivate: toDouble(
      m['pricingTierFeePrivate'],
      fallback.pricingTierFeePrivate,
    ),
    pricingTierFeePremium: toDouble(
      m['pricingTierFeePremium'],
      fallback.pricingTierFeePremium,
    ),
    pricingNightSurchargeRate: toDouble(
      m['pricingNightSurchargeRate'],
      fallback.pricingNightSurchargeRate,
    ),
    pricingWeekendSurchargeRate: toDouble(
      m['pricingWeekendSurchargeRate'],
      fallback.pricingWeekendSurchargeRate,
    ),
    pricingSurchargeCapRate: toDouble(
      m['pricingSurchargeCapRate'],
      fallback.pricingSurchargeCapRate,
    ),
    chironEnabled: (m['chironEnabled'] is bool)
        ? m['chironEnabled'] as bool
        : fallback.chironEnabled,
    chironEnvironment: (m['chironEnvironment'] ?? fallback.chironEnvironment)
        .toString(),
    chironConnectionStatus:
        (m['chironConnectionStatus'] ?? fallback.chironConnectionStatus)
            .toString(),
    chironRegionScope: (m['chironRegionScope'] ?? fallback.chironRegionScope)
        .toString(),
    chironLastTestedAt: (m['chironLastTestedAt'] ?? fallback.chironLastTestedAt)
        .toString(),
    chironProductionEnabled: (m['chironProductionEnabled'] is bool)
        ? m['chironProductionEnabled'] as bool
        : fallback.chironProductionEnabled,
  );
}

Map<String, dynamic> _encodeVehicle(VehicleProfile v) {
  return <String, dynamic>{
    'id': v.id,
    'vehicleName': v.vehicleName,
    'brandModel': v.brandModel,
    'licensePlate': v.licensePlate,
    'exploitationLicenseNumber': v.exploitationLicenseNumber,
    'vehicleRegistrationNumber': v.vehicleRegistrationNumber,
    'color': v.color,
    'passengerCapacity': v.passengerCapacity,
    'luggageCapacity': v.luggageCapacity,
    'tierId': v.tierId,
    'isActive': v.isActive,
    'driverId': v.driverId,
    'companyId': v.companyId,
    'primaryPhotoRef': v.primaryPhotoRef,
    'galleryPhotoRefs': v.galleryPhotoRefs,
    'publicPhotoUrl': v.publicPhotoUrl,
    // Keep legacy key for backward readability/debug
    'photoRef': v.primaryPhotoRef,
  };
}

Map<String, dynamic> _encodeDriver(DriverProfile d) {
  return <String, dynamic>{
    'id': d.id,
    'fullName': d.fullName,
    'employeeNumber': d.employeeNumber,
    'hasLoginCode': d.hasLoginCode,
    if ((d.driverCodeLast4 ?? '').trim().isNotEmpty)
      'driverCodeLast4': d.driverCodeLast4!.trim(),
    if ((d.loginCodeLast4 ?? '').trim().isNotEmpty)
      'loginCodeLast4': d.loginCodeLast4!.trim(),
    'phone': d.phone,
    'taxiDriverCardNumber': d.taxiDriverCardNumber,
    'taxiDriverCardExpiry': d.taxiDriverCardExpiry,
    'isActive': d.isActive,
    'profilePhotoPath': d.profilePhotoPath,
    'publicProfileEnabled': d.publicProfileEnabled,
    'publicPhotoEnabled': d.publicPhotoEnabled,
    'publicDisplayName': d.publicDisplayName,
    'publicPortraitUrl': d.publicPortraitUrl,
    'availabilityStatus': d.availabilityStatus,
    'ratingAvg': d.ratingAvg,
    'ratingCount': d.ratingCount,
    'companyId': d.companyId,
  };
}

VehicleProfile _decodeVehicle(
  Map<String, dynamic> m, {
  required VehicleProfile fallback,
}) {
  int toInt(dynamic v, int fb) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? fb;
  }

  List<String> toStringList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  // Backward compatibility:
  // - old shape had only photoRef
  // - new shape has primaryPhotoRef + galleryPhotoRefs
  final legacyPhoto = (m['photoRef'] ?? fallback.primaryPhotoRef).toString();
  final primaryPhoto = (m['primaryPhotoRef'] ?? legacyPhoto).toString();
  final gallery = toStringList(m['galleryPhotoRefs']);
  final String? publicPhotoUrl = () {
    final raw =
        m['publicPhotoUrl'] ??
        m['public_photo_url'] ??
        m['vehiclePhotoUrl'] ??
        m['vehicle_photo_url'];
    if (raw == null) return null;
    final text = raw.toString().trim();
    return text.isEmpty ? null : text;
  }();

  final cidRaw = m['companyId'] ?? m['tenantId'];
  final String? companyId = cidRaw == null
      ? fallback.companyId
      : () {
          final s = cidRaw.toString().trim();
          return s.isEmpty ? fallback.companyId : s;
        }();

  return fallback.copyWith(
    id: (m['id'] ?? fallback.id).toString(),
    vehicleName: (m['vehicleName'] ?? fallback.vehicleName).toString(),
    brandModel: (m['brandModel'] ?? fallback.brandModel).toString(),
    licensePlate: (m['licensePlate'] ?? fallback.licensePlate).toString(),
    exploitationLicenseNumber:
        (m['exploitationLicenseNumber'] ?? fallback.exploitationLicenseNumber)
            .toString(),
    vehicleRegistrationNumber:
        (m['vehicleRegistrationNumber'] ?? fallback.vehicleRegistrationNumber)
            .toString(),
    color: (m['color'] ?? fallback.color).toString(),
    passengerCapacity: toInt(
      m['passengerCapacity'],
      fallback.passengerCapacity,
    ),
    luggageCapacity: toInt(m['luggageCapacity'], fallback.luggageCapacity),
    tierId: (m['tierId'] ?? fallback.tierId).toString(),
    isActive: (m['isActive'] is bool)
        ? m['isActive'] as bool
        : fallback.isActive,
    driverId: m['driverId']?.toString(),
    companyId: companyId,
    primaryPhotoRef: primaryPhoto,
    galleryPhotoRefs: gallery,
    publicPhotoUrl: publicPhotoUrl,
  );
}

DriverProfile _decodeDriver(
  Map<String, dynamic> m, {
  required DriverProfile fallback,
}) {
  final cidRaw = m['companyId'] ?? m['tenantId'];
  final profilePhotoRaw = m['profilePhotoPath'];
  final String? companyId = cidRaw == null
      ? fallback.companyId
      : () {
          final s = cidRaw.toString().trim();
          return s.isEmpty ? fallback.companyId : s;
        }();
  final String? profilePhotoPath = profilePhotoRaw == null
      ? null
      : () {
          final text = profilePhotoRaw.toString().trim();
          return text.isEmpty ? null : text;
        }();
  final bool publicProfileEnabled = (m['publicProfileEnabled'] is bool)
      ? m['publicProfileEnabled'] as bool
      : false;
  final bool publicPhotoEnabled = (m['publicPhotoEnabled'] is bool)
      ? m['publicPhotoEnabled'] as bool
      : false;
  final String? publicDisplayName = () {
    final raw = m['publicDisplayName'];
    if (raw == null) return null;
    final text = raw.toString().trim();
    return text.isEmpty ? null : text;
  }();
  final String? publicPortraitUrl = () {
    final raw = m['publicPortraitUrl'];
    if (raw == null) return null;
    final text = raw.toString().trim();
    return text.isEmpty ? null : text;
  }();
  final availabilityStatus = normalizeDriverAvailabilityState(
    m['availabilityStatus'] ?? m['availability_status'],
    fallback: fallback.availabilityStatus,
  );
  final double? ratingAvg = () {
    final raw =
        m['ratingAvg'] ??
        m['rating_avg'] ??
        m['average_rating'] ??
        m['averageRating'] ??
        m['driver_rating_avg'] ??
        m['driverRatingAvg'];
    if (raw is num) return raw.toDouble();
    final parsed = double.tryParse((raw ?? '').toString().trim());
    return parsed != null && parsed.isFinite ? parsed : fallback.ratingAvg;
  }();
  final int? ratingCount = () {
    final raw =
        m['ratingCount'] ??
        m['rating_count'] ??
        m['reviews_count'] ??
        m['reviewsCount'] ??
        m['driver_rating_count'] ??
        m['driverRatingCount'];
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    final parsed = int.tryParse((raw ?? '').toString().trim());
    return parsed ?? fallback.ratingCount;
  }();

  final id = (m['id'] ?? fallback.id).toString();
  final employeeNumber = (m['employeeNumber'] ?? fallback.employeeNumber)
      .toString()
      .trim();
  final resolvedEmployeeNumber = employeeNumber.isNotEmpty
      ? employeeNumber
      : fallback.employeeNumber.trim();
  final hasLoginCode = () {
    final raw = m['hasLoginCode'] ?? m['has_login_code'];
    if (raw is bool) return raw;
    final text = (raw ?? '').toString().trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
    return fallback.hasLoginCode;
  }();
  final driverCodeLast4 = () {
    final text = (m['driverCodeLast4'] ?? m['driver_code_last4'] ?? '')
        .toString()
        .trim();
    if (text.isEmpty) return fallback.driverCodeLast4;
    return text;
  }();
  final loginCodeLast4 = () {
    final text = (m['loginCodeLast4'] ?? m['login_code_last4'] ?? '')
        .toString()
        .trim();
    if (text.isEmpty) return fallback.loginCodeLast4;
    return text;
  }();

  return fallback.copyWith(
    id: id,
    fullName: (m['fullName'] ?? fallback.fullName).toString(),
    employeeNumber: resolvedEmployeeNumber,
    hasLoginCode: hasLoginCode,
    driverCodeLast4: driverCodeLast4,
    loginCodeLast4: loginCodeLast4,
    phone: (m['phone'] ?? fallback.phone).toString(),
    taxiDriverCardNumber:
        (m['taxiDriverCardNumber'] ?? fallback.taxiDriverCardNumber).toString(),
    taxiDriverCardExpiry:
        (m['taxiDriverCardExpiry'] ?? fallback.taxiDriverCardExpiry).toString(),
    isActive: (m['isActive'] is bool)
        ? m['isActive'] as bool
        : fallback.isActive,
    profilePhotoPath: profilePhotoPath,
    publicProfileEnabled: publicProfileEnabled,
    publicPhotoEnabled: publicProfileEnabled ? publicPhotoEnabled : false,
    publicDisplayName: publicDisplayName,
    publicPortraitUrl: publicPortraitUrl,
    availabilityStatus: availabilityStatus,
    ratingAvg: ratingAvg,
    ratingCount: ratingCount,
    companyId: companyId,
  );
}

Future<Directory> _tenantStateBaseDir() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}${Platform.pathSeparator}tenant_state');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

Future<File> _tenantStateFile() async {
  final dir = await _tenantStateBaseDir();
  return File('${dir.path}${Platform.pathSeparator}tenant_state_v1.json');
}

/// Local on-device cache for the "Officiële bedrijfsgegevens" backend profile.
///
/// Backed by [_persistLocalTenantState]/[loadLocalTenantState] so values typed
/// in Business Settings survive app restarts even if the backend save fails or
/// the device is offline. Backend remains preferred when it returns meaningful
/// (non-empty) values; see merge logic in `business_settings_page.dart`.
final ValueNotifier<BackendBusinessProfile?>
localBackendBusinessProfileNotifier = ValueNotifier<BackendBusinessProfile?>(
  null,
);

/// Update the local cache for [BackendBusinessProfile] and persist to disk.
///
/// Pass `null` to clear the cache. Persistence is best-effort and never throws.
Future<void> updateLocalBackendBusinessProfileCache(
  BackendBusinessProfile? profile,
) async {
  localBackendBusinessProfileNotifier.value = profile;
  await _persistLocalTenantState();
}

/// Local on-device cache for the "BTW-instellingen" backend tax profile.
///
/// Backed by [_persistLocalTenantState]/[loadLocalTenantState] so the VAT
/// rate/mode/labels typed in Business Settings survive app restarts even when
/// the backend tax endpoint is offline. Backend remains preferred for the
/// initial first-time hydrate when no cache exists yet; once the user has a
/// cached profile we keep it as the source of truth for the form to avoid
/// backend defaults silently overwriting saved values.
final ValueNotifier<BackendTaxProfile?> localBackendTaxProfileNotifier =
    ValueNotifier<BackendTaxProfile?>(null);

/// Update the local cache for [BackendTaxProfile] and persist to disk.
///
/// Pass `null` to clear the cache. Persistence is best-effort and never throws.
Future<void> updateLocalBackendTaxProfileCache(
  BackendTaxProfile? profile,
) async {
  localBackendTaxProfileNotifier.value = profile;
  await _persistLocalTenantState();
}

Future<void> _persistLocalTenantState() async {
  try {
    final file = await _tenantStateFile();
    final cachedBackendProfile = localBackendBusinessProfileNotifier.value
        ?.toJson();
    final cachedTaxProfile = localBackendTaxProfileNotifier.value?.toJson();
    final payload = <String, dynamic>{
      'version': 1,
      'businessSettings': _encodeBusinessSettings(
        businessSettingsNotifier.value,
      ),
      if (cachedBackendProfile != null)
        'backendBusinessProfile': cachedBackendProfile,
      if (cachedTaxProfile != null) 'backendTaxProfile': cachedTaxProfile,
      'vehicles': vehiclesNotifier.value
          .map(_encodeVehicle)
          .toList(growable: false),
      'drivers': driversNotifier.value
          .map(_encodeDriver)
          .toList(growable: false),
      'deletedDriverIdsByScope': _encodeDeletedDriverTombstonesForPersistence(),
    };
    await file.writeAsString(jsonEncode(payload));
    debugPrint(
      'tenant_state_save path=${file.path} bytes=${jsonEncode(payload).length}',
    );
  } catch (_) {
    // Keep UI flow resilient: persistence failures must not crash app.
  }
}

const String _fleetSyncAdminToken = String.fromEnvironment(
  'ADMIN_TOKEN',
  defaultValue: '',
);
bool _companyInventorySyncInFlight = false;

Map<String, String> _adminJsonHeaders() {
  final headers = <String, String>{'Content-Type': 'application/json'};
  final token = _fleetSyncAdminToken.trim();
  if (token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
    headers['x-admin-token'] = token;
  }
  return headers;
}

/// How company-owner admin API calls authenticated.
enum CompanyOwnerAuthMode { admin, companySession, none }

class CompanyOwnerAuthHeaders {
  const CompanyOwnerAuthHeaders({required this.headers, required this.mode});

  final Map<String, String> headers;
  final CompanyOwnerAuthMode mode;
}

/// Resolves auth headers for company-owner calls to scoped `/admin/*` routes.
///
/// Prefers compile-time admin token when present (dev/ops builds). Otherwise
/// falls back to the active company session bearer from local storage.
Future<CompanyOwnerAuthHeaders> resolveCompanyOwnerAuthHeaders({
  bool json = true,
}) async {
  final headers = <String, String>{'Accept': 'application/json'};
  if (json) headers['Content-Type'] = 'application/json';

  final adminToken = _fleetSyncAdminToken.trim();
  if (adminToken.isNotEmpty) {
    headers['Authorization'] = 'Bearer $adminToken';
    headers['x-admin-token'] = adminToken;
    debugPrint('[COMPANY_OWNER_AUTH][MODE] auth_mode=admin');
    return CompanyOwnerAuthHeaders(
      headers: headers,
      mode: CompanyOwnerAuthMode.admin,
    );
  }

  final resolved = await CompanySessionStore.instance
      .resolveCompanyBootstrapToken();
  final companyToken = (resolved.token ?? '').trim();
  if (companyToken.isNotEmpty) {
    headers['Authorization'] = 'Bearer $companyToken';
    debugPrint(
      '[COMPANY_OWNER_AUTH][MODE] auth_mode=company_session source=${resolved.source}',
    );
    return CompanyOwnerAuthHeaders(
      headers: headers,
      mode: CompanyOwnerAuthMode.companySession,
    );
  }

  debugPrint('[COMPANY_OWNER_AUTH][MODE] auth_mode=none');
  return CompanyOwnerAuthHeaders(
    headers: headers,
    mode: CompanyOwnerAuthMode.none,
  );
}

enum TripsHistoryAuthMode { admin, companySession, driverSession, none }

class TripsHistoryAuthHeaders {
  final Map<String, String> headers;
  final TripsHistoryAuthMode mode;

  const TripsHistoryAuthHeaders({required this.headers, required this.mode});

  /// Compact label for `[DRIVER_HISTORY][FETCH]` logs.
  String get fetchLogAuthMode => switch (mode) {
    TripsHistoryAuthMode.admin ||
    TripsHistoryAuthMode.companySession => 'company',
    TripsHistoryAuthMode.driverSession => 'driver',
    TripsHistoryAuthMode.none => 'none',
  };
}

/// Auth headers for tracking-worker `GET /trips/history`.
///
/// Prefers compile-time admin token or active company session when available
/// (business preview / company tablet). Falls back to the standalone public
/// driver session bearer when no company-owner auth is present.
///
/// When [preferDriverSession] is true (standalone driver History), the driver
/// bearer is used first so stale company profile/session on the device cannot
/// be mixed with the active standalone driver session.
Future<TripsHistoryAuthHeaders> resolveTripsHistoryAuthHeaders({
  bool json = true,
  bool preferDriverSession = false,
}) async {
  final headers = <String, String>{'Accept': 'application/json'};
  if (json) headers['Content-Type'] = 'application/json';

  if (preferDriverSession) {
    final driverSessionToken =
        (activeDriverSessionNotifier.value?.driverSessionToken ?? '').trim();
    if (driverSessionToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $driverSessionToken';
      debugPrint(
        '[TRIPS_HISTORY_AUTH][MODE] auth_mode=driver_session prefer=true',
      );
      return TripsHistoryAuthHeaders(
        headers: headers,
        mode: TripsHistoryAuthMode.driverSession,
      );
    }
  }

  final companyAuth = await resolveCompanyOwnerAuthHeaders(json: json);
  if (companyAuth.mode == CompanyOwnerAuthMode.admin) {
    return TripsHistoryAuthHeaders(
      headers: companyAuth.headers,
      mode: TripsHistoryAuthMode.admin,
    );
  }
  if (companyAuth.mode == CompanyOwnerAuthMode.companySession) {
    return TripsHistoryAuthHeaders(
      headers: companyAuth.headers,
      mode: TripsHistoryAuthMode.companySession,
    );
  }

  final driverSessionToken =
      (activeDriverSessionNotifier.value?.driverSessionToken ?? '').trim();
  if (driverSessionToken.isNotEmpty) {
    headers['Authorization'] = 'Bearer $driverSessionToken';
    debugPrint('[TRIPS_HISTORY_AUTH][MODE] auth_mode=driver_session');
    return TripsHistoryAuthHeaders(
      headers: headers,
      mode: TripsHistoryAuthMode.driverSession,
    );
  }

  debugPrint('[TRIPS_HISTORY_AUTH][MODE] auth_mode=none');
  return TripsHistoryAuthHeaders(
    headers: headers,
    mode: TripsHistoryAuthMode.none,
  );
}

String _maskCompanyScopeForLog(String value) {
  final text = value.trim();
  if (text.isEmpty) return '—';
  if (text.length <= 4) return '…${text.substring(text.length - 1)}';
  return '${text.substring(0, 2)}…${text.substring(text.length - 2)}';
}

String _maskDriverIdForDiag(String value) {
  final text = value.trim();
  if (text.isEmpty) return 'unknown';
  if (text.length <= 4) return '…${text.substring(text.length - 1)}';
  return '${text.substring(0, 2)}…${text.substring(text.length - 2)}';
}

String _shortBodyPreviewForDiag(String value) {
  final single = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (single.isEmpty) return '—';
  return single.length <= 140 ? single : '${single.substring(0, 140)}…';
}

String _maskVehicleIdForDiag(String value) {
  final text = value.trim();
  if (text.isEmpty) return 'unknown';
  if (text.length <= 4) return '…${text.substring(text.length - 1)}';
  return '${text.substring(0, 2)}…${text.substring(text.length - 2)}';
}

String maskVehicleIdForLog(String value) => _maskVehicleIdForDiag(value);

VehicleProfile? vehicleProfileById(String vehicleId) {
  final needle = vehicleId.trim();
  if (needle.isEmpty) return null;
  for (final vehicle in vehiclesNotifier.value) {
    if (vehicle.id.trim() == needle) return vehicle;
  }
  return null;
}

/// Applies a public HTTPS vehicle photo URL to the in-memory fleet record.
bool applyVehiclePublicPhotoUrlToNotifier({
  required String vehicleId,
  required String publicPhotoUrl,
  String? companyId,
}) {
  final url = resolvePublicHttpsMediaUrl(publicPhotoUrl);
  if (url.isEmpty) return false;
  final normalizedId = vehicleId.trim();
  if (normalizedId.isEmpty) return false;
  final current = vehicleProfileById(normalizedId);
  if (current == null) {
    debugPrint(
      '[VEHICLE_PUBLIC_PHOTO][NOTIFIER_UPDATE] vehicle=${maskVehicleIdForLog(normalizedId)} updated=false reason=not_found',
    );
    return false;
  }
  final scopeCompany = (companyId ?? '').trim();
  final nextCompanyId = (current.companyId?.trim().isNotEmpty ?? false)
      ? current.companyId
      : (scopeCompany.isEmpty ? current.companyId : scopeCompany);
  updateVehicle(
    current.id,
    current.copyWith(publicPhotoUrl: url, companyId: nextCompanyId),
  );
  debugPrint(
    '[VEHICLE_PUBLIC_PHOTO][NOTIFIER_UPDATE] vehicle=${maskVehicleIdForLog(normalizedId)} updated=true',
  );
  return true;
}

bool vehicleBelongsToCompanyPublishScope(
  VehicleProfile vehicle,
  String companyId,
) {
  final scopedCompany = vehicle.companyId?.trim() ?? '';
  final needle = companyId.trim();
  if (needle.isEmpty) return scopedCompany.isEmpty;
  if (scopedCompany.isEmpty) return true;
  return scopedCompany == needle;
}

String _shortVehicleTextForDiag(String value) {
  final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return '—';
  return text.length <= 48 ? text : '${text.substring(0, 48)}…';
}

void _logVehicleAssignmentSyncOut(Map<String, dynamic> payload) {
  final vehicleId = (payload['vehicle_id'] ?? payload['vehicleId'] ?? '')
      .toString()
      .trim();
  final vehicleName = (payload['vehicle_name'] ?? payload['vehicleName'] ?? '')
      .toString()
      .trim();
  final licensePlate =
      (payload['license_plate'] ?? payload['licensePlate'] ?? '')
          .toString()
          .trim();
  final assignedDriverId = (() {
    final direct =
        (payload['assigned_driver_id'] ??
                payload['assignedDriverId'] ??
                payload['driver_id'] ??
                payload['driverId'] ??
                '')
            .toString()
            .trim();
    if (direct.isNotEmpty) return direct;
    final assignedDriverRaw = payload['assigned_driver'];
    if (assignedDriverRaw is Map) {
      return (assignedDriverRaw['driver_id'] ??
              assignedDriverRaw['driverId'] ??
              assignedDriverRaw['id'] ??
              '')
          .toString()
          .trim();
    }
    return '';
  })();
  debugPrint(
    '[VEHICLE_ASSIGNMENT_SYNC][OUT] vehicle=${_maskVehicleIdForDiag(vehicleId)} name=${_shortVehicleTextForDiag(vehicleName)} plate=${_shortVehicleTextForDiag(licensePlate)} driver=${_maskDriverIdForDiag(assignedDriverId)}',
  );
}

Future<bool> _postFleetVehiclesWithTruthfulResult({
  required Uri endpoint,
  required Map<String, String> scope,
  required List<Map<String, dynamic>> fleetPayload,
}) async {
  for (final payload in fleetPayload) {
    _logVehicleAssignmentSyncOut(payload);
  }
  try {
    final auth = await resolveCompanyOwnerAuthHeaders();
    if (auth.mode == CompanyOwnerAuthMode.none) {
      debugPrint('[COMPANY_SYNC][VEHICLES_ERROR] reason=missing_auth');
      return false;
    }
    final response = await http
        .post(
          endpoint,
          headers: auth.headers,
          body: jsonEncode(<String, dynamic>{
            ...scope,
            'vehicles': fleetPayload,
          }),
        )
        .timeout(const Duration(seconds: 12));
    final status = response.statusCode;
    final bodyPreview = _shortBodyPreviewForDiag(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    if (status < 200 || status >= 300) {
      debugPrint(
        '[COMPANY_SYNC][VEHICLES_ERROR] status=$status auth_mode=${auth.mode.name} reason=http_non_2xx body=$bodyPreview',
      );
      return false;
    }
    final rawBody = utf8
        .decode(response.bodyBytes, allowMalformed: true)
        .trim();
    if (rawBody.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawBody);
        if (decoded is Map &&
            decoded.containsKey('ok') &&
            decoded['ok'] != true) {
          debugPrint(
            '[COMPANY_SYNC][VEHICLES_ERROR] status=$status reason=ok_false body=$bodyPreview',
          );
          return false;
        }
      } catch (_) {
        // Preserve success behavior for 2xx responses with non-JSON bodies.
      }
    }
    debugPrint(
      '[COMPANY_SYNC][VEHICLES_OK] auth_mode=${auth.mode.name} count=${fleetPayload.length}',
    );
    return true;
  } catch (error) {
    debugPrint(
      '[COMPANY_SYNC][VEHICLES_ERROR] status=network reason=exception error=${_shortBodyPreviewForDiag(error.toString())}',
    );
    return false;
  }
}

class DriverStatusSaveResult {
  const DriverStatusSaveResult({
    required this.ok,
    required this.statusCode,
    required this.authSource,
    required this.endpointPath,
    required this.errorCode,
    required this.payloadFieldNames,
  });

  final bool ok;
  final int? statusCode;
  final String authSource;
  final String endpointPath;
  final String errorCode;
  final List<String> payloadFieldNames;
}

class DriverAvailabilitySaveResult {
  const DriverAvailabilitySaveResult({
    required this.ok,
    required this.statusCode,
    required this.endpointPath,
    required this.errorCode,
    required this.availabilityStatus,
  });

  final bool ok;
  final int? statusCode;
  final String endpointPath;
  final String errorCode;
  final String availabilityStatus;
}

String _safeDriverStatusSaveErrorCode(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('401')) return 'unauthorized';
  if (text.contains('403')) return 'forbidden';
  if (text.contains('400')) return 'bad_request';
  if (text.contains('422')) return 'unprocessable_entity';
  if (text.contains('timeout')) return 'timeout';
  if (text.contains('socket') || text.contains('network')) return 'network';
  return 'exception';
}

Future<DriverAvailabilitySaveResult> syncPublicDriverAvailabilityToBackend({
  required String driverSessionToken,
  required String availabilityStatus,
}) async {
  final endpoint = Uri.parse(
    '${appConfig.bookingBaseUrl}/public/driver/availability',
  );
  final normalized = normalizeDriverAvailabilityState(
    availabilityStatus,
    fallback: 'available',
  );
  try {
    final response = await http
        .post(
          endpoint,
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${driverSessionToken.trim()}',
          },
          body: jsonEncode(<String, dynamic>{
            'availability_status': normalized,
            'availabilityStatus': normalized,
          }),
        )
        .timeout(const Duration(seconds: 12));
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    var errorCode = '';
    var responseStatus = normalized;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) {
        errorCode = (decoded['error'] ?? decoded['reason'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        responseStatus = normalizeDriverAvailabilityState(
          decoded['availability_status'] ?? decoded['availabilityStatus'],
          fallback: normalized,
        );
      }
    } catch (_) {}
    return DriverAvailabilitySaveResult(
      ok: ok,
      statusCode: response.statusCode,
      endpointPath: endpoint.path,
      errorCode: ok ? '' : (errorCode.isEmpty ? 'request_failed' : errorCode),
      availabilityStatus: responseStatus,
    );
  } catch (error) {
    return DriverAvailabilitySaveResult(
      ok: false,
      statusCode: null,
      endpointPath: endpoint.path,
      errorCode: _safeDriverStatusSaveErrorCode(error),
      availabilityStatus: normalized,
    );
  }
}

class DriverOperationalAvailabilityLookup {
  const DriverOperationalAvailabilityLookup({
    required this.ok,
    required this.availabilityStatus,
    required this.source,
  });

  final bool ok;
  final String availabilityStatus;
  final String source;
}

String? _readDriverAvailabilityFromPayloadMap(Map<String, dynamic> map) {
  final raw = map['availability_status'] ?? map['availabilityStatus'];
  if (raw == null) return null;
  return normalizeDriverAvailabilityState(raw, fallback: 'available');
}

String _readDriverIdFromPayloadMap(Map<String, dynamic> map) {
  for (final key in const ['driver_id', 'driverId', 'id']) {
    final value = (map[key] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

/// Resolves live operational availability for one driver from canonical backend
/// sources. Prefers company bootstrap (driver index), then public partner profile.
Future<DriverOperationalAvailabilityLookup>
fetchDriverOperationalAvailabilityStatus({
  required String driverId,
  required String tenantId,
  required String companyId,
  String? companySessionToken,
}) async {
  final normalizedDriverId = driverId.trim();
  final normalizedCompanyId = companyId.trim().isNotEmpty
      ? companyId.trim()
      : tenantId.trim();
  if (normalizedDriverId.isEmpty || normalizedCompanyId.isEmpty) {
    return const DriverOperationalAvailabilityLookup(
      ok: false,
      availabilityStatus: 'available',
      source: 'local',
    );
  }

  final token = (companySessionToken ?? '').trim();
  if (token.isNotEmpty) {
    final bootstrap = await fetchCompanyBootstrapWithToken(
      companySessionToken: token,
    );
    final driversRaw = bootstrap?['drivers'];
    if (driversRaw is List) {
      for (final row in driversRaw) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);
        final rowDriverId = _readDriverIdFromPayloadMap(map);
        if (rowDriverId != normalizedDriverId) continue;
        final status =
            _readDriverAvailabilityFromPayloadMap(map) ?? 'available';
        return DriverOperationalAvailabilityLookup(
          ok: true,
          availabilityStatus: status,
          source: 'company_bootstrap',
        );
      }
    }
  }

  final partnerUri = Uri.parse('${appConfig.bookingBaseUrl}/partners/profile')
      .replace(
        queryParameters: <String, String>{'partner_id': normalizedCompanyId},
      );
  try {
    final response = await http
        .get(
          partnerUri,
          headers: const <String, String>{'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['ok'] == true) {
        final profileRaw = decoded['profile'];
        if (profileRaw is Map) {
          final profile = Map<String, dynamic>.from(profileRaw);
          final driversRaw = profile['drivers'];
          if (driversRaw is List) {
            for (final row in driversRaw) {
              if (row is! Map) continue;
              final map = Map<String, dynamic>.from(row);
              final rowDriverId = _readDriverIdFromPayloadMap(map);
              if (rowDriverId != normalizedDriverId) continue;
              final status =
                  _readDriverAvailabilityFromPayloadMap(map) ?? 'available';
              return DriverOperationalAvailabilityLookup(
                ok: true,
                availabilityStatus: status,
                source: 'partner_profile',
              );
            }
          }
        }
      }
    }
  } catch (_) {}

  for (final driver in driversNotifier.value) {
    if (driver.id.trim() != normalizedDriverId) continue;
    return DriverOperationalAvailabilityLookup(
      ok: true,
      availabilityStatus: normalizeDriverAvailabilityState(
        driver.availabilityStatus,
        fallback: 'available',
      ),
      source: 'local',
    );
  }

  return const DriverOperationalAvailabilityLookup(
    ok: false,
    availabilityStatus: 'available',
    source: 'local',
  );
}

Map<String, String> _resolveAdminTenantCompanyScope({
  String? tenantId,
  String? companyId,
}) {
  final scopeId = _effectiveStrictAdminScopeId(
    tenantId: tenantId,
    companyId: companyId,
  );
  return <String, String>{
    'tenant_id': scopeId,
    'company_id': scopeId,
    'tenantId': scopeId,
    'companyId': scopeId,
  };
}

Uri _withAdminTenantCompanyScope(
  Uri endpoint, {
  String? tenantId,
  String? companyId,
}) {
  final scope = _resolveAdminTenantCompanyScope(
    tenantId: tenantId,
    companyId: companyId,
  );
  final merged = <String, String>{...endpoint.queryParameters, ...scope};
  return endpoint.replace(queryParameters: merged);
}

String normalizeExplicitIsoCurrencyCode(String raw) {
  final upper = raw.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(upper)) return '';
  return upper;
}

Map<String, dynamic> _encodePricingProfileForBackend(BusinessSettingsState s) {
  final vat = resolveActiveVatConfig(settings: s);
  final profile = <String, dynamic>{
    'base_fare': s.pricingBaseFare,
    'price_per_km': s.pricingPerKm,
    'price_per_minute': s.pricingPerMinute,
    'minimum_fare': s.pricingMinimumFare,
    'wait_per_minute': s.pricingWaitPerMinute,
    'return_enabled': s.pricingReturnEnabled,
    'return_fee': s.pricingReturnFee,
    'fuel_surcharge': s.pricingFuelSurcharge,
    'vat_rate': vat.vatRate,
    'vat_mode': vat.vatMode,
    'bag_fee_each': s.pricingBagFeeEach,
    'stop_fee_each': s.pricingStopFeeEach,
    'tier_fee_comfort': s.pricingTierFeeComfort,
    'tier_fee_private': s.pricingTierFeePrivate,
    'tier_fee_premium': s.pricingTierFeePremium,
    'night_surcharge_rate': s.pricingNightSurchargeRate,
    'weekend_surcharge_rate': s.pricingWeekendSurchargeRate,
    'surcharge_cap_rate': s.pricingSurchargeCapRate,
  };
  final currency = normalizeExplicitIsoCurrencyCode(s.defaultCurrency);
  if (currency.isNotEmpty) {
    profile['currency'] = currency;
    profile['default_currency'] = currency;
    profile['defaultCurrency'] = currency;
  }
  return profile;
}

String? _sanitizeOutboundFleetMediaRef(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final lower = text.toLowerCase();

  final isWindowsAbsolutePath = RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(text);
  final isWindowsUncPath = text.startsWith(r'\\');
  final isMobileLocalPath =
      lower.startsWith('/data/') ||
      lower.startsWith('/storage/') ||
      lower.startsWith('/sdcard/') ||
      lower.startsWith('/var/mobile/') ||
      lower.startsWith('/private/var/mobile/') ||
      lower.startsWith('/var/containers/');

  if (lower.startsWith('file://') ||
      lower.startsWith('content://') ||
      isWindowsAbsolutePath ||
      isWindowsUncPath ||
      isMobileLocalPath) {
    return null;
  }

  if (lower.startsWith('https://') || lower.startsWith('http://')) {
    return text;
  }
  if (lower.startsWith('/public/media/') ||
      lower.startsWith('public-media/') ||
      lower.startsWith('/public-media/')) {
    return text;
  }
  return null;
}

List<String> _sanitizeOutboundFleetMediaRefs(Iterable<String> refs) {
  final out = <String>[];
  for (final ref in refs) {
    final sanitized = _sanitizeOutboundFleetMediaRef(ref);
    if (sanitized == null || out.contains(sanitized)) continue;
    out.add(sanitized);
  }
  return out;
}

Map<String, dynamic> _encodeVehicleForBackendFleet(
  VehicleProfile v, {
  required String tenantId,
  required String companyId,
}) {
  final resolvedTenant = tenantId.trim();
  final resolvedCompany = companyId.trim();
  DriverProfile? linkedDriver;
  for (final d in driversNotifier.value) {
    if (d.id == v.driverId) {
      linkedDriver = d;
      break;
    }
  }
  final assignedDriver = linkedDriver == null
      ? ((v.driverId ?? '').trim().isEmpty
            ? null
            : <String, dynamic>{
                'driver_id': v.driverId!.trim(),
                'driverId': v.driverId!.trim(),
                'id': v.driverId!.trim(),
              })
      : <String, dynamic>{
          'driver_id': linkedDriver.id.trim(),
          'driverId': linkedDriver.id.trim(),
          'id': linkedDriver.id.trim(),
          'name': linkedDriver.fullName.trim(),
          'display_name': linkedDriver.fullName.trim(),
          'displayName': linkedDriver.fullName.trim(),
          'phone': linkedDriver.phone.trim(),
        };
  final safePrimaryPhotoRef = _sanitizeOutboundFleetMediaRef(v.primaryPhotoRef);
  final safeGalleryPhotoRefs = _sanitizeOutboundFleetMediaRefs(
    v.galleryPhotoRefs,
  );
  return <String, dynamic>{
    'vehicle_id': v.id.trim(),
    'vehicleId': v.id.trim(),
    'vehicle_name': v.vehicleName.trim(),
    'vehicleName': v.vehicleName.trim(),
    'brand_model': v.brandModel.trim(),
    'brandModel': v.brandModel.trim(),
    'license_plate': v.licensePlate.trim(),
    'licensePlate': v.licensePlate.trim(),
    'exploitation_license_number': v.exploitationLicenseNumber.trim(),
    'exploitationLicenseNumber': v.exploitationLicenseNumber.trim(),
    'vehicle_registration_number': v.vehicleRegistrationNumber.trim(),
    'vehicleRegistrationNumber': v.vehicleRegistrationNumber.trim(),
    'color': v.color.trim(),
    'is_active': v.isActive,
    'isActive': v.isActive,
    'tier': v.tierId.trim().toLowerCase(),
    'tierId': v.tierId.trim().toLowerCase(),
    'passenger_capacity': v.passengerCapacity < 0 ? 0 : v.passengerCapacity,
    'passengerCapacity': v.passengerCapacity < 0 ? 0 : v.passengerCapacity,
    'luggage_capacity': v.luggageCapacity < 0 ? 0 : v.luggageCapacity,
    'luggageCapacity': v.luggageCapacity < 0 ? 0 : v.luggageCapacity,
    'tenant_id': (v.companyId?.trim().isNotEmpty ?? false)
        ? v.companyId!.trim()
        : resolvedTenant,
    'company_id': (v.companyId?.trim().isNotEmpty ?? false)
        ? v.companyId!.trim()
        : resolvedCompany,
    'tenantId': (v.companyId?.trim().isNotEmpty ?? false)
        ? v.companyId!.trim()
        : resolvedTenant,
    'companyId': (v.companyId?.trim().isNotEmpty ?? false)
        ? v.companyId!.trim()
        : resolvedCompany,
    if (safePrimaryPhotoRef != null) ...{
      'primary_photo_ref': safePrimaryPhotoRef,
      'primaryPhotoRef': safePrimaryPhotoRef,
      'photo_ref': safePrimaryPhotoRef,
      'photoRef': safePrimaryPhotoRef,
    },
    if (safeGalleryPhotoRefs.isNotEmpty) ...{
      'gallery_photo_refs': safeGalleryPhotoRefs,
      'galleryPhotoRefs': safeGalleryPhotoRefs,
    },
    if ((v.publicPhotoUrl ?? '').trim().isNotEmpty) ...{
      'public_photo_url': v.publicPhotoUrl!.trim(),
      'publicPhotoUrl': v.publicPhotoUrl!.trim(),
      'vehicle_photo_url': v.publicPhotoUrl!.trim(),
      'vehiclePhotoUrl': v.publicPhotoUrl!.trim(),
    },
    if (assignedDriver != null) 'assigned_driver': assignedDriver,
    if ((v.driverId ?? '').trim().isNotEmpty) ...{
      'assigned_driver_id': v.driverId!.trim(),
      'assignedDriverId': v.driverId!.trim(),
      'driver_id': v.driverId!.trim(),
      'driverId': v.driverId!.trim(),
    },
  };
}

Map<String, dynamic> _encodeDriverForBackendIndexPayload(
  DriverProfile driver, {
  required String tenantId,
  required String companyId,
  String? assignedVehicleIdOverride,
  bool? isActiveOverride,
}) {
  String? normalizedDriverPhoneForBackend(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return null;
    if (!raw.startsWith('+')) return null;
    final digitsOnly = raw.substring(1).replaceAll(RegExp(r'[^0-9]'), '');
    final normalized = '+$digitsOnly';
    if (!RegExp(r'^\+\d{8,15}$').hasMatch(normalized)) return null;
    return normalized;
  }

  String? normalizedPublicDriverPhotoUrl(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    if (text.startsWith('https://') || text.startsWith('http://')) {
      return text;
    }
    if (text.startsWith('/public/media/') || text.startsWith('public-media/')) {
      return text;
    }
    return null;
  }

  String? assignedVehicleId = assignedVehicleIdOverride?.trim();
  if (assignedVehicleId != null && assignedVehicleId.isEmpty) {
    assignedVehicleId = null;
  }
  for (final vehicle in vehiclesNotifier.value) {
    if (vehicle.driverId == driver.id) {
      final candidate = vehicle.id.trim();
      if (candidate.isNotEmpty) {
        assignedVehicleId = candidate;
        break;
      }
    }
  }

  final driverId = driver.id.trim();
  final normalizedPhone = normalizedDriverPhoneForBackend(driver.phone);
  final safePublicDriverPhotoUrl = normalizedPublicDriverPhotoUrl(
    driver.publicPortraitUrl,
  );
  return <String, dynamic>{
    'tenant_id': tenantId,
    'company_id': companyId,
    'tenantId': tenantId,
    'companyId': companyId,
    'driver_id': driverId,
    'driverId': driverId,
    'id': driverId,
    'display_name': driver.fullName.trim(),
    'displayName': driver.fullName.trim(),
    'driver_name': driver.fullName.trim(),
    'driverName': driver.fullName.trim(),
    'full_name': driver.fullName.trim(),
    'fullName': driver.fullName.trim(),
    'name': driver.fullName.trim(),
    if (normalizedPhone != null) 'phone': normalizedPhone,
    'is_active': isActiveOverride ?? driver.isActive,
    'isActive': isActiveOverride ?? driver.isActive,
    'availability_status': normalizeDriverAvailabilityState(
      driver.availabilityStatus,
      fallback: 'available',
    ),
    'availabilityStatus': normalizeDriverAvailabilityState(
      driver.availabilityStatus,
      fallback: 'available',
    ),
    'taxi_driver_card_number': driver.taxiDriverCardNumber.trim(),
    'taxiDriverCardNumber': driver.taxiDriverCardNumber.trim(),
    'taxi_driver_card_expiry': driver.taxiDriverCardExpiry.trim(),
    'taxiDriverCardExpiry': driver.taxiDriverCardExpiry.trim(),
    'public_profile_enabled': driver.publicProfileEnabled,
    'publicProfileEnabled': driver.publicProfileEnabled,
    'public_photo_enabled': driver.publicPhotoEnabled,
    'publicPhotoEnabled': driver.publicPhotoEnabled,
    if ((driver.publicDisplayName ?? '').trim().isNotEmpty) ...{
      'public_display_name': driver.publicDisplayName!.trim(),
      'publicDisplayName': driver.publicDisplayName!.trim(),
    },
    if (assignedVehicleId != null) ...{
      'assigned_vehicle_id': assignedVehicleId,
      'assignedVehicleId': assignedVehicleId,
    },
    if (safePublicDriverPhotoUrl != null) ...{
      'public_portrait_url': safePublicDriverPhotoUrl,
      'publicPortraitUrl': safePublicDriverPhotoUrl,
      'driver_photo_url': safePublicDriverPhotoUrl,
      'driverPhotoUrl': safePublicDriverPhotoUrl,
    },
  };
}

Future<bool> syncPricingProfileToBackend({
  String? tenantId,
  String? companyId,
}) async {
  try {
    final endpoint = _withAdminTenantCompanyScope(
      Uri.parse('${appConfig.bookingBaseUrl}/admin/pricing/profile'),
      tenantId: tenantId,
      companyId: companyId,
    );
    final profilePayload = _encodePricingProfileForBackend(
      businessSettingsNotifier.value,
    );
    final scope = _resolveAdminTenantCompanyScope(
      tenantId: tenantId,
      companyId: companyId,
    );
    final auth = await resolveCompanyOwnerAuthHeaders();
    final res = await http
        .post(
          endpoint,
          headers: auth.headers,
          body: jsonEncode(<String, dynamic>{
            ...scope,
            'pricing_profile': profilePayload,
          }),
        )
        .timeout(const Duration(seconds: 12));
    final status = res.statusCode;
    if (status < 200 || status >= 300) {
      final snippet = res.body.replaceAll(RegExp(r'\s+'), ' ').trim();
      final safeSnippet = snippet.length > 120
          ? '${snippet.substring(0, 120)}...'
          : snippet;
      debugPrint(
        '[PRICING_PROFILE_SYNC][FAIL] status=$status auth_mode=${auth.mode.name} reason=http_error'
        '${safeSnippet.isNotEmpty ? ' detail=$safeSnippet' : ''}',
      );
      return false;
    }
    final rawBody = res.body.trim();
    if (rawBody.isEmpty) {
      debugPrint(
        '[PRICING_PROFILE_SYNC][FAIL] status=$status reason=empty_body',
      );
      return false;
    }
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map) {
        debugPrint(
          '[PRICING_PROFILE_SYNC][FAIL] status=$status reason=invalid_json_shape',
        );
        return false;
      }
      final body = Map<String, dynamic>.from(decoded);
      if (body['ok'] != true) {
        final reason = (body['error'] ?? body['message'] ?? 'ok_false')
            .toString()
            .trim();
        debugPrint(
          '[PRICING_PROFILE_SYNC][FAIL] status=$status reason=${reason.isNotEmpty ? reason : 'ok_false'}',
        );
        return false;
      }
    } catch (_) {
      debugPrint(
        '[PRICING_PROFILE_SYNC][FAIL] status=$status reason=invalid_json',
      );
      return false;
    }
    debugPrint('[PRICING_PROFILE_SYNC][OK] status=$status');
    return true;
  } catch (e) {
    final reason = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    debugPrint('[PRICING_PROFILE_SYNC][FAIL] reason=$reason');
    return false;
  }
}

Future<bool> syncFleetInventoryToBackend({
  String? tenantId,
  String? companyId,
}) async {
  try {
    final scope = _resolveAdminTenantCompanyScope(
      tenantId: tenantId,
      companyId: companyId,
    );
    final endpoint = _withAdminTenantCompanyScope(
      Uri.parse('${appConfig.bookingBaseUrl}/admin/fleet/vehicles'),
      tenantId: scope['tenant_id'],
      companyId: scope['company_id'],
    );
    final fleetPayload = vehiclesNotifier.value
        .map(
          (vehicle) => _encodeVehicleForBackendFleet(
            vehicle,
            tenantId: scope['tenant_id'] ?? '',
            companyId: scope['company_id'] ?? '',
          ),
        )
        .where((e) => (e['vehicle_id'] as String).isNotEmpty)
        .toList(growable: false);
    return await _postFleetVehiclesWithTruthfulResult(
      endpoint: endpoint,
      scope: scope,
      fleetPayload: fleetPayload,
    );
  } catch (_) {
    // Keep local-first UX stable even when backend sync fails.
    return false;
  }
}

Future<bool> syncDriverIndexEntryToBackend(
  DriverProfile driver, {
  String? tenantId,
  String? companyId,
  bool? isActiveOverride,
  String? companySessionToken,
}) async {
  final result = await syncDriverStatusToBackend(
    driver,
    tenantId: tenantId,
    companyId: companyId,
    isActiveOverride: isActiveOverride,
    companySessionToken: companySessionToken,
  );
  return result.ok;
}

Future<DriverStatusSaveResult> syncDriverStatusToBackend(
  DriverProfile driver, {
  String? tenantId,
  String? companyId,
  bool? isActiveOverride,
  String? companySessionToken,
}) async {
  try {
    final scope = _resolveAdminTenantCompanyScope(
      tenantId: tenantId,
      companyId: companyId,
    );
    final endpoint = _withAdminTenantCompanyScope(
      Uri.parse(
        '${appConfig.bookingBaseUrl}/admin/company/drivers/index/upsert',
      ),
      tenantId: scope['tenant_id'],
      companyId: scope['company_id'],
    );
    final driverId = driver.id.trim();
    if (driverId.isEmpty) {
      return const DriverStatusSaveResult(
        ok: false,
        statusCode: null,
        authSource: 'none',
        endpointPath: '/admin/company/drivers/index/upsert',
        errorCode: 'missing_driver_id',
        payloadFieldNames: <String>[],
      );
    }
    final isActiveValue = isActiveOverride ?? driver.isActive;
    final token = (companySessionToken ?? '').trim();
    final hasCompanyToken = token.isNotEmpty;
    debugPrint(
      '[DRIVER_STATUS_SAVE][TOKEN] source=${hasCompanyToken ? 'company_session' : 'none'} hasToken=$hasCompanyToken',
    );
    debugPrint(
      '[DRIVER_INDEX_UPSERT][REQUEST] driver=${_maskDriverIdForDiag(driverId)} isActive=$isActiveValue tenant=${_maskCompanyScopeForLog(scope["tenant_id"] ?? "")} company=${_maskCompanyScopeForLog(scope["company_id"] ?? "")}',
    );
    debugPrint(
      '[DRIVER_STATUS_SAVE][REQUEST] driver=${_maskDriverIdForDiag(driverId)} tenant=${_maskCompanyScopeForLog(scope["tenant_id"] ?? "")} company=${_maskCompanyScopeForLog(scope["company_id"] ?? "")} endpoint=${endpoint.path}',
    );
    final payload = _encodeDriverForBackendIndexPayload(
      driver,
      tenantId: scope['tenant_id'] ?? '',
      companyId: scope['company_id'] ?? '',
      isActiveOverride: isActiveOverride,
    );
    final payloadFieldNames = payload.keys.toList(growable: false)..sort();
    debugPrint(
      '[DRIVER_STATUS_SAVE][PAYLOAD] driver=${_maskDriverIdForDiag(driverId)} fields=${payloadFieldNames.join(",")}',
    );
    if (!hasCompanyToken) {
      return DriverStatusSaveResult(
        ok: false,
        statusCode: null,
        authSource: 'none',
        endpointPath: endpoint.path,
        errorCode: 'missing_company_session_token',
        payloadFieldNames: payloadFieldNames,
      );
    }
    final response = await http
        .post(
          endpoint,
          headers: companyBearerHeaders(token, json: true),
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 12));
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    String errorCode = '';
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) {
        errorCode = (decoded['error'] ?? decoded['reason'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
      }
    } catch (_) {}
    debugPrint(
      '[DRIVER_STATUS_SAVE][RESPONSE] driver=${_maskDriverIdForDiag(driverId)} status=${response.statusCode} ok=$ok',
    );
    debugPrint(
      '[DRIVER_INDEX_UPSERT][RESPONSE] driver=${_maskDriverIdForDiag(driverId)} status=${response.statusCode} ok=$ok bodyPreview=${_shortBodyPreviewForDiag(utf8.decode(response.bodyBytes))}',
    );
    if (!ok) {
      final resolvedError = errorCode.isEmpty ? 'request_failed' : errorCode;
      debugPrint(
        '[DRIVER_STATUS_SAVE][FAILED] driver=${_maskDriverIdForDiag(driverId)} status=${response.statusCode} error=$resolvedError',
      );
      return DriverStatusSaveResult(
        ok: false,
        statusCode: response.statusCode,
        authSource: 'company_session',
        endpointPath: endpoint.path,
        errorCode: resolvedError,
        payloadFieldNames: payloadFieldNames,
      );
    }
    return DriverStatusSaveResult(
      ok: true,
      statusCode: response.statusCode,
      authSource: 'company_session',
      endpointPath: endpoint.path,
      errorCode: '',
      payloadFieldNames: payloadFieldNames,
    );
  } catch (error) {
    debugPrint(
      '[DRIVER_STATUS_SAVE][FAILED] driver=${_maskDriverIdForDiag(driver.id)} status=none error=${_safeDriverStatusSaveErrorCode(error)}',
    );
    return DriverStatusSaveResult(
      ok: false,
      statusCode: null,
      authSource: 'company_session',
      endpointPath: '/admin/company/drivers/index/upsert',
      errorCode: _safeDriverStatusSaveErrorCode(error),
      payloadFieldNames: const <String>[],
    );
  }
}

Future<Map<String, dynamic>?> rotateDriverLoginCode({
  required String driverId,
  String? tenantId,
  String? companyId,
}) async {
  try {
    final normalizedDriverId = driverId.trim();
    if (normalizedDriverId.isEmpty) return null;
    final scope = _resolveAdminTenantCompanyScope(
      tenantId: tenantId,
      companyId: companyId,
    );
    final endpoint = _withAdminTenantCompanyScope(
      Uri.parse(
        '${appConfig.bookingBaseUrl}/admin/company/drivers/login-code/rotate',
      ),
      tenantId: scope['tenant_id'],
      companyId: scope['company_id'],
    );
    final payload = <String, dynamic>{
      ...scope,
      'driver_id': normalizedDriverId,
      'driverId': normalizedDriverId,
    };
    final auth = await resolveCompanyOwnerAuthHeaders();
    final response = await http
        .post(endpoint, headers: auth.headers, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '[DRIVER_LOGIN_CODE_ROTATE][FAIL] status=${response.statusCode} auth_mode=${auth.mode.name}',
      );
      return null;
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    if (map['ok'] != true) return null;
    final loginCode = (map['login_code'] ?? map['loginCode'] ?? '')
        .toString()
        .trim();
    final driverCodeLast4 =
        (map['driver_code_last4'] ?? map['driverCodeLast4'] ?? '')
            .toString()
            .trim();
    final loginCodeLast4 =
        (map['login_code_last4'] ?? map['loginCodeLast4'] ?? '')
            .toString()
            .trim();
    return <String, dynamic>{
      'ok': true,
      'login_code': loginCode,
      'driver_code_last4': driverCodeLast4,
      'login_code_last4': loginCodeLast4,
    };
  } catch (_) {
    return null;
  }
}

Future<Map<String, dynamic>?> createDriverLinkCode({
  required String driverId,
  required String tenantId,
  required String companyId,
  required String companyCode,
  int? expiresInSeconds,
}) async {
  try {
    final normalizedDriverId = driverId.trim();
    final normalizedCompanyCode = companyCode.trim().toUpperCase();
    if (normalizedDriverId.isEmpty || normalizedCompanyCode.isEmpty)
      return null;
    final scope = _resolveAdminTenantCompanyScope(
      tenantId: tenantId,
      companyId: companyId,
    );
    final endpoint = _withAdminTenantCompanyScope(
      Uri.parse(
        '${appConfig.bookingBaseUrl}/admin/company/driver-link-code/create',
      ),
      tenantId: scope['tenant_id'],
      companyId: scope['company_id'],
    );
    final payload = <String, dynamic>{
      ...scope,
      'driver_id': normalizedDriverId,
      'driverId': normalizedDriverId,
      'company_code': normalizedCompanyCode,
      'companyCode': normalizedCompanyCode,
      if (expiresInSeconds != null && expiresInSeconds > 0) ...{
        'expires_in_seconds': expiresInSeconds,
        'expiresInSeconds': expiresInSeconds,
      },
    };
    final response = await http
        .post(endpoint, headers: _adminJsonHeaders(), body: jsonEncode(payload))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var preview = utf8.decode(response.bodyBytes);
      preview = preview.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (preview.length > 160) {
        preview = preview.substring(0, 160);
      }
      preview = preview
          .replaceAll(
            RegExp(r'"pairing_code"\s*:\s*"[^"]*"', caseSensitive: false),
            '"pairing_code":"***"',
          )
          .replaceAll(
            RegExp(r'"challenge_id"\s*:\s*"[^"]*"', caseSensitive: false),
            '"challenge_id":"***"',
          )
          .replaceAll(
            RegExp(r'"driver_id"\s*:\s*"[^"]*"', caseSensitive: false),
            '"driver_id":"***"',
          );
      debugPrint(
        '[DRIVER_LINK_QR][CREATE_HTTP_FAIL] status=${response.statusCode} body_prefix=$preview',
      );
      return null;
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    if (map['ok'] != true) {
      final errorCode = (map['error'] ?? map['reason'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      debugPrint('[DRIVER_LINK_QR][CREATE_OK_FALSE] error=$errorCode');
      return null;
    }
    final resolvedCompanyCode =
        (map['company_code'] ?? map['companyCode'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
    final pairingCode = (map['pairing_code'] ?? map['pairingCode'] ?? '')
        .toString()
        .trim();
    final challengeId = (map['challenge_id'] ?? map['challengeId'] ?? '')
        .toString()
        .trim();
    final expiresAt = (map['expires_at'] ?? map['expiresAt'] ?? '')
        .toString()
        .trim();
    final resolvedExpiresIn = int.tryParse(
      (map['expires_in_seconds'] ?? map['expiresInSeconds'] ?? '')
          .toString()
          .trim(),
    );
    if (resolvedCompanyCode.isEmpty ||
        pairingCode.isEmpty ||
        challengeId.isEmpty) {
      return null;
    }
    return <String, dynamic>{
      'ok': true,
      'company_code': resolvedCompanyCode,
      'pairing_code': pairingCode,
      'challenge_id': challengeId,
      'expires_at': expiresAt,
      if (resolvedExpiresIn != null) 'expires_in_seconds': resolvedExpiresIn,
    };
  } catch (error) {
    debugPrint('[DRIVER_LINK_QR][CREATE_ERROR] type=${error.runtimeType}');
    return null;
  }
}

Future<void> syncLocalCompanyInventoryToBackend({
  required String reason,
  String? tenantId,
  String? companyId,
  bool requireCompanySessionToken = false,
  bool hasCompanySessionToken = true,
}) async {
  if (requireCompanySessionToken && !hasCompanySessionToken) {
    debugPrint('[COMPANY_SYNC][SKIP_NO_COMPANY_TOKEN] reason=$reason');
    return;
  }
  if (_companyInventorySyncInFlight) return;
  final token = _fleetSyncAdminToken.trim();
  if (token.isEmpty) return;
  final resolvedTenant = (tenantId ?? '').trim();
  final resolvedCompany = (companyId ?? '').trim();
  final strictScope = _activeStrictPrivateCompanyScope();
  final effectiveTenant = resolvedTenant.isNotEmpty
      ? resolvedTenant
      : (strictScope?.tenantId ?? '');
  final effectiveCompany = resolvedCompany.isNotEmpty
      ? resolvedCompany
      : (strictScope?.companyId ?? '');
  if (effectiveTenant.isEmpty || effectiveCompany.isEmpty) {
    debugPrint(
      '[PRIVATE_SCOPE][ADMIN][SKIP] reason=missing_active_company_context op=syncLocalCompanyInventoryToBackend',
    );
    return;
  }

  final scopedVehicles = vehiclesNotifier.value
      .where(
        (v) =>
            (v.companyId?.trim().isEmpty ?? true) ||
            v.companyId!.trim() == effectiveCompany,
      )
      .toList(growable: false);
  final scopedDrivers = driversNotifier.value
      .where(
        (d) =>
            (d.companyId?.trim().isEmpty ?? true) ||
            d.companyId!.trim() == effectiveCompany,
      )
      .toList(growable: false);

  final vehicleLinkByDriverId = <String, String>{};
  var vehicleLinks = 0;
  for (final vehicle in scopedVehicles) {
    final driverId = (vehicle.driverId ?? '').trim();
    final vehicleId = vehicle.id.trim();
    if (driverId.isEmpty || vehicleId.isEmpty) continue;
    vehicleLinks += 1;
    vehicleLinkByDriverId.putIfAbsent(driverId, () => vehicleId);
  }
  var driverVehicleLinks = 0;
  for (final driver in scopedDrivers) {
    if (vehicleLinkByDriverId.containsKey(driver.id.trim())) {
      driverVehicleLinks += 1;
    }
  }

  _companyInventorySyncInFlight = true;
  debugPrint(
    '[COMPANY_SYNC][START] reason=$reason vehicles=${scopedVehicles.length} drivers=${scopedDrivers.length} company=${_maskCompanyScopeForLog(effectiveCompany)}',
  );
  debugPrint(
    '[COMPANY_SYNC][LOCAL_COUNTS] vehicles=${vehiclesNotifier.value.length} drivers=${driversNotifier.value.length} scopedVehicles=${scopedVehicles.length} scopedDrivers=${scopedDrivers.length}',
  );
  debugPrint(
    '[COMPANY_SYNC][LINKS] vehicleLinks=$vehicleLinks driverVehicleLinks=$driverVehicleLinks',
  );
  try {
    final scope = _resolveAdminTenantCompanyScope(
      tenantId: effectiveTenant,
      companyId: effectiveCompany,
    );
    final tombstonedDriverIds = <String>{
      ..._deletedDriverIdsForScope(
        tenantId: scope['tenant_id'] ?? '',
        companyId: scope['company_id'] ?? '',
      ),
    };
    final syncTenantId = scope['tenant_id'] ?? '';
    final syncCompanyId = scope['company_id'] ?? '';
    final syncTenantMasked = _maskCompanyScopeForLog(syncTenantId);
    final syncCompanyMasked = _maskCompanyScopeForLog(syncCompanyId);
    final removedDriverIdsAfterConflict = <String>{};

    void removeDriverLocallyAfterConflict(String driverId) {
      final normalizedDriverId = driverId.trim();
      if (normalizedDriverId.isEmpty) return;
      if (!removedDriverIdsAfterConflict.add(normalizedDriverId)) return;
      driversNotifier.value = driversNotifier.value
          .where((d) => d.id.trim() != normalizedDriverId)
          .toList(growable: false);
      vehiclesNotifier.value = vehiclesNotifier.value
          .map(
            (v) => (v.driverId ?? '').trim() == normalizedDriverId
                ? v.copyWith(driverId: null)
                : v,
          )
          .toList(growable: false);
      debugPrint(
        '[COMPANY_SYNC][LOCAL_REMOVE_AFTER_CONFLICT] driver=${_maskDriverIdForDiag(normalizedDriverId)}',
      );
      _persistLocalTenantState();
    }

    bool isDeletedConflictResponse(http.Response response) {
      if (response.statusCode == 409) return true;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final errorCode = (decoded['error'] ?? decoded['reason'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          return errorCode == 'driver_deleted_conflict';
        }
      } catch (_) {}
      return false;
    }

    if (scopedVehicles.isNotEmpty) {
      final endpoint = _withAdminTenantCompanyScope(
        Uri.parse('${appConfig.bookingBaseUrl}/admin/fleet/vehicles'),
        tenantId: scope['tenant_id'],
        companyId: scope['company_id'],
      );
      final fleetPayload = scopedVehicles
          .map(
            (vehicle) => _encodeVehicleForBackendFleet(
              vehicle,
              tenantId: scope['tenant_id'] ?? '',
              companyId: scope['company_id'] ?? '',
            ),
          )
          .where((e) => (e['vehicle_id'] as String).isNotEmpty)
          .toList(growable: false);
      await _postFleetVehiclesWithTruthfulResult(
        endpoint: endpoint,
        scope: scope,
        fleetPayload: fleetPayload,
      );
    }

    if (scopedDrivers.isNotEmpty) {
      String maskDriverIdForLog(String value) {
        final text = value.trim();
        if (text.isEmpty) return 'unknown';
        if (text.length <= 4) return '…${text.substring(text.length - 1)}';
        return '${text.substring(0, 2)}…${text.substring(text.length - 2)}';
      }

      var okCount = 0;
      var skippedCount = 0;
      var failedCount = 0;
      for (final driver in scopedDrivers) {
        final driverId = driver.id.trim();
        final maskedDriver = maskDriverIdForLog(driverId);
        if (driverId.isEmpty) {
          skippedCount += 1;
          debugPrint(
            '[COMPANY_SYNC][DRIVER_SKIP] reason=missing_driver_id driver=unknown',
          );
          continue;
        }
        if (isSeededOrPlaceholderDriver(driver)) {
          skippedCount += 1;
          debugPrint(
            '[COMPANY_SYNC][DRIVER_SKIP] reason=placeholder driver=$maskedDriver',
          );
          continue;
        }
        if (tombstonedDriverIds.contains(driverId)) {
          skippedCount += 1;
          debugPrint(
            '[COMPANY_SYNC][SKIP_DELETED_DRIVER] driver=$maskedDriver reason=tombstone',
          );
          continue;
        }
        try {
          final endpoint = _withAdminTenantCompanyScope(
            Uri.parse(
              '${appConfig.bookingBaseUrl}/admin/company/drivers/index/upsert',
            ),
            tenantId: scope['tenant_id'],
            companyId: scope['company_id'],
          );
          final payload = _encodeDriverForBackendIndexPayload(
            driver,
            tenantId: scope['tenant_id'] ?? '',
            companyId: scope['company_id'] ?? '',
            assignedVehicleIdOverride: vehicleLinkByDriverId[driver.id.trim()],
          );
          final response = await http
              .post(
                endpoint,
                headers: _adminJsonHeaders(),
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 12));
          if (response.statusCode >= 200 && response.statusCode < 300) {
            okCount += 1;
            debugPrint('[COMPANY_SYNC][DRIVER_OK] driver=$maskedDriver');
          } else {
            if (isDeletedConflictResponse(response)) {
              skippedCount += 1;
              tombstonedDriverIds.add(driverId);
              _markDeletedDriverForScope(
                tenantId: syncTenantId,
                companyId: syncCompanyId,
                driverId: driverId,
              );
              debugPrint(
                '[COMPANY_SYNC][REMOTE_DELETE_CONFLICT] driver=$maskedDriver tenant=$syncTenantMasked company=$syncCompanyMasked',
              );
              removeDriverLocallyAfterConflict(driverId);
              continue;
            }
            failedCount += 1;
            String reason = 'non_2xx';
            try {
              final decoded = jsonDecode(response.body);
              if (decoded is Map) {
                final maybeReason =
                    (decoded['reason'] ?? decoded['error'] ?? '')
                        .toString()
                        .trim();
                if (maybeReason.isNotEmpty) {
                  reason = maybeReason;
                }
              }
            } catch (_) {}
            debugPrint(
              '[COMPANY_SYNC][DRIVER_ERROR] status=${response.statusCode} reason=$reason driver=$maskedDriver',
            );
          }
        } catch (_) {
          failedCount += 1;
          debugPrint(
            '[COMPANY_SYNC][DRIVER_ERROR] status=network reason=exception driver=$maskedDriver',
          );
        }
      }
      debugPrint(
        '[COMPANY_SYNC][DRIVERS_DONE] ok=$okCount skipped=$skippedCount failed=$failedCount',
      );
    }
  } finally {
    _companyInventorySyncInFlight = false;
    debugPrint('[COMPANY_SYNC][DONE]');
  }
}

Future<BackendBusinessProfile> fetchBackendBusinessProfile({
  String? tenantId,
  String? companyId,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/business/profile'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .get(endpoint, headers: auth.headers)
      .timeout(const Duration(seconds: 12));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) throw Exception('Invalid response');
  final decodedMap = Map<String, dynamic>.from(decoded);
  final profile = decoded['business_profile'];
  if (profile is! Map) throw Exception('Missing business_profile');
  final mergedProfile = Map<String, dynamic>.from(profile);
  for (final key in const <String>[
    'company_code',
    'companyCode',
    'public_company_code',
    'publicCompanyCode',
    'public_company_slug',
    'publicCompanySlug',
    'public_display_code',
    'publicDisplayCode',
  ]) {
    final top = decodedMap[key];
    if (top == null) continue;
    final topText = top.toString().trim();
    if (topText.isEmpty) continue;
    final curText = (mergedProfile[key] ?? '').toString().trim();
    if (curText.isEmpty) {
      mergedProfile[key] = topText;
    }
  }
  return BackendBusinessProfile.fromJson(mergedProfile);
}

Future<BackendBusinessProfile> saveBackendBusinessProfile(
  BackendBusinessProfile profile, {
  String? tenantId,
  String? companyId,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/business/profile'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final scope = _resolveAdminTenantCompanyScope(
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .post(
        endpoint,
        headers: auth.headers,
        body: jsonEncode(<String, dynamic>{
          ...scope,
          'business_profile': profile.toJson(),
        }),
      )
      .timeout(const Duration(seconds: 12));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) throw Exception('Invalid response');
  final decodedMap = Map<String, dynamic>.from(decoded);
  final saved = decoded['business_profile'];
  if (saved is! Map) throw Exception('Missing business_profile');
  final mergedProfile = Map<String, dynamic>.from(saved);
  for (final key in const <String>[
    'company_code',
    'companyCode',
    'public_company_code',
    'publicCompanyCode',
    'public_company_slug',
    'publicCompanySlug',
    'public_display_code',
    'publicDisplayCode',
  ]) {
    final top = decodedMap[key];
    if (top == null) continue;
    final topText = top.toString().trim();
    if (topText.isEmpty) continue;
    final curText = (mergedProfile[key] ?? '').toString().trim();
    if (curText.isEmpty) {
      mergedProfile[key] = topText;
    }
  }
  return BackendBusinessProfile.fromJson(mergedProfile);
}

Future<BackendTaxProfile> fetchBackendTaxProfile({
  String? tenantId,
  String? companyId,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/tax/profile'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .get(endpoint, headers: auth.headers)
      .timeout(const Duration(seconds: 12));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) throw Exception('Invalid response');
  final profile = decoded['tax_profile'];
  if (profile is! Map) throw Exception('Missing tax_profile');
  return BackendTaxProfile.fromJson(Map<String, dynamic>.from(profile));
}

Future<BackendTaxProfile> saveBackendTaxProfile(
  BackendTaxProfile profile, {
  String? tenantId,
  String? companyId,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/tax/profile'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final scope = _resolveAdminTenantCompanyScope(
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .post(
        endpoint,
        headers: auth.headers,
        body: jsonEncode(<String, dynamic>{
          ...scope,
          'tax_profile': profile.toJson(),
        }),
      )
      .timeout(const Duration(seconds: 12));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) throw Exception('Invalid response');
  final saved = decoded['tax_profile'];
  if (saved is! Map) throw Exception('Missing tax_profile');
  return BackendTaxProfile.fromJson(Map<String, dynamic>.from(saved));
}

Future<BackendCancellationPolicyProfile> fetchBackendCancellationPolicyProfile({
  String? tenantId,
  String? companyId,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/cancellation-policy/profile'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .get(endpoint, headers: auth.headers)
      .timeout(const Duration(seconds: 12));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) throw Exception('Invalid response');
  final profile = decoded['cancellation_policy_profile'];
  if (profile is! Map) throw Exception('Missing cancellation_policy_profile');
  return BackendCancellationPolicyProfile.fromJson(
    Map<String, dynamic>.from(profile),
  );
}

Future<BackendCancellationPolicyProfile> saveBackendCancellationPolicyProfile(
  BackendCancellationPolicyProfile profile, {
  String? tenantId,
  String? companyId,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/cancellation-policy/profile'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final scope = _resolveAdminTenantCompanyScope(
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .post(
        endpoint,
        headers: auth.headers,
        body: jsonEncode(<String, dynamic>{
          ...scope,
          'cancellation_policy_profile': profile.toApiPayload(),
        }),
      )
      .timeout(const Duration(seconds: 12));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) throw Exception('Invalid response');
  final saved = decoded['cancellation_policy_profile'];
  if (saved is! Map) throw Exception('Missing cancellation_policy_profile');
  return BackendCancellationPolicyProfile.fromJson(
    Map<String, dynamic>.from(saved),
  );
}

Future<BackendSubscriptionProfile> fetchBackendSubscriptionProfile({
  String? tenantId,
  String? companyId,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/subscription/profile'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final res = await http
      .get(endpoint, headers: _adminJsonHeaders())
      .timeout(const Duration(seconds: 12));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) throw Exception('Invalid response');
  final profile = decoded['subscription_profile'];
  if (profile is! Map) throw Exception('Missing subscription_profile');
  return BackendSubscriptionProfile.fromJson(
    Map<String, dynamic>.from(profile),
  );
}

Future<BackendSubscriptionProfile> saveBackendSubscriptionProfile(
  BackendSubscriptionProfile profile, {
  String? tenantId,
  String? companyId,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/subscription/profile'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final scope = _resolveAdminTenantCompanyScope(
    tenantId: tenantId,
    companyId: companyId,
  );
  final res = await http
      .post(
        endpoint,
        headers: _adminJsonHeaders(),
        body: jsonEncode(<String, dynamic>{
          ...scope,
          'subscription_profile': profile.toJson(),
        }),
      )
      .timeout(const Duration(seconds: 12));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) throw Exception('Invalid response');
  final saved = decoded['subscription_profile'];
  if (saved is! Map) throw Exception('Missing subscription_profile');
  return BackendSubscriptionProfile.fromJson(Map<String, dynamic>.from(saved));
}

String _adminApiErrorMessageFromResponse(
  dynamic decoded,
  int statusCode, {
  String fallback = 'request_failed',
}) {
  if (decoded is Map) {
    final map = Map<String, dynamic>.from(decoded);
    final error = (map['error'] ?? map['message'] ?? '').toString().trim();
    final details = map['details'];
    if (details is List && details.isNotEmpty) {
      final detailText = details
          .map((item) => item is Map ? Map<String, dynamic>.from(item) : null)
          .whereType<Map<String, dynamic>>()
          .map((item) {
            final field = (item['field'] ?? '').toString().trim();
            final issue = (item['error'] ?? '').toString().trim();
            if (field.isNotEmpty && issue.isNotEmpty) return '$field: $issue';
            if (issue.isNotEmpty) return issue;
            return '';
          })
          .where((item) => item.isNotEmpty)
          .join('; ');
      if (detailText.isNotEmpty) {
        return '${error.isNotEmpty ? '$error - ' : ''}$detailText';
      }
    }
    if (error.isNotEmpty) return error;
  }
  return 'HTTP $statusCode: $fallback';
}

Future<Map<String, dynamic>> fetchAdminAirportFixedFares({
  String? tenantId,
  String? companyId,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/pricing/airport-fixed-fares'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .get(endpoint, headers: auth.headers)
      .timeout(const Duration(seconds: 12));
  final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
  if (decoded is! Map) throw Exception('Invalid response');
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception(
      _adminApiErrorMessageFromResponse(
        map,
        res.statusCode,
        fallback: 'airport_fixed_fares_fetch_failed',
      ),
    );
  }
  return map;
}

Future<Map<String, dynamic>> saveAdminAirportFixedFares(
  Map<String, dynamic> airportFixedFaresDocument, {
  String? tenantId,
  String? companyId,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/pricing/airport-fixed-fares'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final scope = _resolveAdminTenantCompanyScope(
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .post(
        endpoint,
        headers: auth.headers,
        body: jsonEncode(<String, dynamic>{
          ...scope,
          'airport_fixed_fares': airportFixedFaresDocument,
        }),
      )
      .timeout(const Duration(seconds: 12));
  final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
  if (decoded is! Map) throw Exception('Invalid response');
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception(
      _adminApiErrorMessageFromResponse(
        map,
        res.statusCode,
        fallback: 'airport_fixed_fares_save_failed',
      ),
    );
  }
  return map;
}

int? _lastCompanyBootstrapHttpStatusCode;
int? get lastCompanyBootstrapHttpStatusCode =>
    _lastCompanyBootstrapHttpStatusCode;

int? _lastCustomerBootstrapHttpStatusCode;
int? get lastCustomerBootstrapHttpStatusCode =>
    _lastCustomerBootstrapHttpStatusCode;

int? _lastCustomerProfileHttpStatusCode;
int? get lastCustomerProfileHttpStatusCode =>
    _lastCustomerProfileHttpStatusCode;

String _trimBookingBaseUrl(String bookingBaseUrl) {
  final base = bookingBaseUrl.trim();
  if (base.isEmpty) return '';
  if (base.endsWith('/')) return base.substring(0, base.length - 1);
  return base;
}

Map<String, String> companyBearerHeaders(
  String companySessionToken, {
  bool json = false,
}) {
  final token = companySessionToken.trim();
  final headers = <String, String>{'Accept': 'application/json'};
  if (json) headers['Content-Type'] = 'application/json';
  if (token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }
  return headers;
}

Future<Map<String, dynamic>> uploadAdminDriverDocument({
  required String bookingBaseUrl,
  required String companySessionToken,
  required String tenantId,
  required String companyId,
  required String driverId,
  required String documentId,
  required String documentType,
  required String title,
  String expiryDate = '',
  String status = 'pending_review',
  String notes = '',
  required String filePath,
}) async {
  final baseUrl = _trimBookingBaseUrl(bookingBaseUrl);
  final token = companySessionToken.trim();
  final normalizedTenantId = tenantId.trim();
  final normalizedCompanyId = companyId.trim();
  final normalizedDriverId = driverId.trim();
  final normalizedDocumentId = documentId.trim();
  final normalizedDocumentType = documentType.trim();
  final normalizedTitle = title.trim();
  final normalizedStatus = status.trim().isEmpty
      ? 'pending_review'
      : status.trim();
  final normalizedNotes = notes.trim();
  final normalizedExpiryDate = expiryDate.trim();
  final normalizedFilePath = filePath.trim();

  if (baseUrl.isEmpty) throw Exception('bookingBaseUrl is required');
  if (token.isEmpty) throw Exception('companySessionToken is required');
  if (normalizedTenantId.isEmpty) throw Exception('tenantId is required');
  if (normalizedCompanyId.isEmpty) throw Exception('companyId is required');
  if (normalizedDriverId.isEmpty) throw Exception('driverId is required');
  if (normalizedDocumentId.isEmpty) throw Exception('documentId is required');
  if (normalizedDocumentType.isEmpty)
    throw Exception('documentType is required');
  if (normalizedTitle.isEmpty) throw Exception('title is required');
  if (normalizedFilePath.isEmpty) throw Exception('filePath is required');
  if (!await File(normalizedFilePath).exists()) {
    throw Exception('filePath does not exist');
  }

  final endpoint = Uri.parse('$baseUrl/admin/driver-documents/upload');
  final request = http.MultipartRequest('POST', endpoint);
  final headers = Map<String, String>.from(companyBearerHeaders(token));
  headers.removeWhere((key, _) => key.toLowerCase() == 'content-type');
  request.headers.addAll(headers);

  request.fields['tenant_id'] = normalizedTenantId;
  request.fields['company_id'] = normalizedCompanyId;
  request.fields['driver_id'] = normalizedDriverId;
  request.fields['document_id'] = normalizedDocumentId;
  request.fields['document_type'] = normalizedDocumentType;
  request.fields['title'] = normalizedTitle;
  request.fields['status'] = normalizedStatus;
  if (normalizedExpiryDate.isNotEmpty) {
    request.fields['expiry_date'] = normalizedExpiryDate;
  }
  if (normalizedNotes.isNotEmpty) {
    request.fields['notes'] = normalizedNotes;
  }

  request.files.add(
    await http.MultipartFile.fromPath('file', normalizedFilePath),
  );

  final streamed = await request.send().timeout(const Duration(seconds: 30));
  final body = await streamed.stream.bytesToString();
  if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
    throw Exception('HTTP ${streamed.statusCode}: $body');
  }
  final decoded = jsonDecode(body);
  if (decoded is! Map) {
    throw Exception('driver_document_upload_failed');
  }
  return Map<String, dynamic>.from(decoded);
}

Future<Map<String, dynamic>> listAdminDriverDocuments({
  required String bookingBaseUrl,
  required String companySessionToken,
  required String tenantId,
  required String companyId,
  required String driverId,
}) async {
  final baseUrl = _trimBookingBaseUrl(bookingBaseUrl);
  final token = companySessionToken.trim();
  final normalizedTenantId = tenantId.trim();
  final normalizedCompanyId = companyId.trim();
  final normalizedDriverId = driverId.trim();

  if (baseUrl.isEmpty) throw Exception('bookingBaseUrl is required');
  if (token.isEmpty) throw Exception('companySessionToken is required');
  if (normalizedTenantId.isEmpty) throw Exception('tenantId is required');
  if (normalizedCompanyId.isEmpty) throw Exception('companyId is required');
  if (normalizedDriverId.isEmpty) throw Exception('driverId is required');

  final endpoint = Uri.parse('$baseUrl/admin/driver-documents/list').replace(
    queryParameters: <String, String>{
      'tenant_id': normalizedTenantId,
      'company_id': normalizedCompanyId,
      'driver_id': normalizedDriverId,
    },
  );
  final res = await http
      .get(endpoint, headers: companyBearerHeaders(token))
      .timeout(const Duration(seconds: 12));
  final decoded = jsonDecode(utf8.decode(res.bodyBytes));
  if (decoded is! Map) {
    throw Exception('driver_document_list_failed');
  }
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    final errorCode = (map['error'] ?? '').toString().trim();
    if (errorCode.isNotEmpty) throw Exception(errorCode);
    throw Exception('driver_document_list_failed');
  }
  return map;
}

Future<Map<String, dynamic>> deleteAdminDriverDocument({
  required String bookingBaseUrl,
  required String companySessionToken,
  required String tenantId,
  required String companyId,
  required String driverId,
  required String documentId,
}) async {
  final baseUrl = _trimBookingBaseUrl(bookingBaseUrl);
  final token = companySessionToken.trim();
  final normalizedTenantId = tenantId.trim();
  final normalizedCompanyId = companyId.trim();
  final normalizedDriverId = driverId.trim();
  final normalizedDocumentId = documentId.trim();

  if (baseUrl.isEmpty) throw Exception('bookingBaseUrl is required');
  if (token.isEmpty) throw Exception('companySessionToken is required');
  if (normalizedTenantId.isEmpty) throw Exception('tenantId is required');
  if (normalizedCompanyId.isEmpty) throw Exception('companyId is required');
  if (normalizedDriverId.isEmpty) throw Exception('driverId is required');
  if (normalizedDocumentId.isEmpty) throw Exception('documentId is required');

  final encodedDocumentId = Uri.encodeComponent(normalizedDocumentId);
  final endpoint =
      Uri.parse('$baseUrl/admin/driver-documents/$encodedDocumentId').replace(
        queryParameters: <String, String>{
          'tenant_id': normalizedTenantId,
          'company_id': normalizedCompanyId,
          'driver_id': normalizedDriverId,
        },
      );
  final res = await http
      .delete(endpoint, headers: companyBearerHeaders(token))
      .timeout(const Duration(seconds: 12));
  final decoded = jsonDecode(utf8.decode(res.bodyBytes));
  if (decoded is! Map) {
    throw Exception('driver_document_delete_failed');
  }
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    final errorCode = (map['error'] ?? '').toString().trim();
    if (errorCode.isNotEmpty) throw Exception(errorCode);
    throw Exception('driver_document_delete_failed');
  }
  return map;
}

Future<Map<String, dynamic>> updateAdminDriverDocumentMetadata({
  required String bookingBaseUrl,
  required String companySessionToken,
  required String tenantId,
  required String companyId,
  required String driverId,
  required String documentId,
  required String documentType,
  required String title,
  String expiryDate = '',
  String status = 'pending_review',
  String notes = '',
}) async {
  final baseUrl = _trimBookingBaseUrl(bookingBaseUrl);
  final token = companySessionToken.trim();
  final normalizedTenantId = tenantId.trim();
  final normalizedCompanyId = companyId.trim();
  final normalizedDriverId = driverId.trim();
  final normalizedDocumentId = documentId.trim();
  final normalizedDocumentType = documentType.trim();
  final normalizedTitle = title.trim();
  final normalizedStatus = status.trim().isEmpty
      ? 'pending_review'
      : status.trim();
  final normalizedNotes = notes.trim();
  final normalizedExpiryDate = expiryDate.trim();

  if (baseUrl.isEmpty) throw Exception('bookingBaseUrl is required');
  if (token.isEmpty) throw Exception('companySessionToken is required');
  if (normalizedTenantId.isEmpty) throw Exception('tenantId is required');
  if (normalizedCompanyId.isEmpty) throw Exception('companyId is required');
  if (normalizedDriverId.isEmpty) throw Exception('driverId is required');
  if (normalizedDocumentId.isEmpty) throw Exception('documentId is required');
  if (normalizedDocumentType.isEmpty) {
    throw Exception('documentType is required');
  }
  if (normalizedTitle.isEmpty) throw Exception('title is required');

  final endpoint = Uri.parse('$baseUrl/admin/driver-documents/update');
  final payload = <String, dynamic>{
    'tenant_id': normalizedTenantId,
    'company_id': normalizedCompanyId,
    'driver_id': normalizedDriverId,
    'document_id': normalizedDocumentId,
    'document_type': normalizedDocumentType,
    'title': normalizedTitle,
    'status': normalizedStatus,
    'notes': normalizedNotes,
    if (normalizedExpiryDate.isNotEmpty) 'expiry_date': normalizedExpiryDate,
  };
  final res = await http
      .post(
        endpoint,
        headers: companyBearerHeaders(token, json: true),
        body: jsonEncode(payload),
      )
      .timeout(const Duration(seconds: 12));
  final decoded = jsonDecode(utf8.decode(res.bodyBytes));
  if (decoded is! Map) {
    throw Exception('driver_document_update_failed');
  }
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    final errorCode = (map['error'] ?? '').toString().trim();
    if (errorCode.isNotEmpty) throw Exception(errorCode);
    throw Exception('driver_document_update_failed');
  }
  return map;
}

class DriverDocumentFileDownloadResult {
  const DriverDocumentFileDownloadResult({
    required this.localPath,
    required this.contentType,
    required this.fileName,
    required this.bytes,
  });

  final String localPath;
  final String contentType;
  final String fileName;
  final int bytes;
}

Future<DriverDocumentFileDownloadResult> downloadAdminDriverDocumentFile({
  required String bookingBaseUrl,
  required String companySessionToken,
  required String tenantId,
  required String companyId,
  required String driverId,
  required String documentId,
}) async {
  final baseUrl = _trimBookingBaseUrl(bookingBaseUrl);
  final token = companySessionToken.trim();
  final normalizedTenantId = tenantId.trim();
  final normalizedCompanyId = companyId.trim();
  final normalizedDriverId = driverId.trim();
  final normalizedDocumentId = documentId.trim();

  if (baseUrl.isEmpty) throw Exception('bookingBaseUrl is required');
  if (token.isEmpty) throw Exception('companySessionToken is required');
  if (normalizedTenantId.isEmpty) throw Exception('tenantId is required');
  if (normalizedCompanyId.isEmpty) throw Exception('companyId is required');
  if (normalizedDriverId.isEmpty) throw Exception('driverId is required');
  if (normalizedDocumentId.isEmpty) throw Exception('documentId is required');

  final endpoint = Uri.parse('$baseUrl/admin/driver-documents/file').replace(
    queryParameters: <String, String>{
      'tenant_id': normalizedTenantId,
      'company_id': normalizedCompanyId,
      'driver_id': normalizedDriverId,
      'document_id': normalizedDocumentId,
    },
  );
  final response = await http
      .get(endpoint, headers: companyBearerHeaders(token))
      .timeout(const Duration(seconds: 20));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('HTTP ${response.statusCode}');
  }

  String sanitizeFileName(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return 'driver_document';
    text = text.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    text = text.replaceAll(RegExp(r'_+'), '_');
    text = text.replaceAll(RegExp(r'^_+|_+$'), '');
    if (text.isEmpty) return 'driver_document';
    return text.length > 160 ? text.substring(0, 160) : text;
  }

  String resolveFileNameFromHeaders(http.Response res) {
    final cd = res.headers['content-disposition'] ?? '';
    final quoted = RegExp(r'filename="([^"]+)"').firstMatch(cd);
    if (quoted != null) return sanitizeFileName(quoted.group(1) ?? '');
    final plain = RegExp(r'filename=([^;]+)').firstMatch(cd);
    if (plain != null) return sanitizeFileName(plain.group(1) ?? '');
    return 'driver_document';
  }

  final contentType =
      (response.headers['content-type'] ?? 'application/octet-stream').trim();
  final fallbackExt = () {
    if (contentType.contains('pdf')) return '.pdf';
    if (contentType.contains('jpeg')) return '.jpg';
    if (contentType.contains('png')) return '.png';
    if (contentType.contains('webp')) return '.webp';
    return '.bin';
  }();
  var fileName = resolveFileNameFromHeaders(response);
  if (!fileName.contains('.')) {
    fileName = '$fileName$fallbackExt';
  }
  final tempDir = await getTemporaryDirectory();
  final cacheDir = Directory(
    '${tempDir.path}${Platform.pathSeparator}driver_document_cache',
  );
  if (!await cacheDir.exists()) {
    await cacheDir.create(recursive: true);
  }
  final savePath =
      '${cacheDir.path}${Platform.pathSeparator}${sanitizeFileName(normalizedDriverId)}_${sanitizeFileName(normalizedDocumentId)}_$fileName';
  final file = File(savePath);
  await file.writeAsBytes(response.bodyBytes, flush: true);
  return DriverDocumentFileDownloadResult(
    localPath: savePath,
    contentType: contentType,
    fileName: fileName,
    bytes: response.bodyBytes.length,
  );
}

Future<Map<String, dynamic>?> fetchCompanyBootstrapWithToken({
  required String companySessionToken,
}) async {
  final token = companySessionToken.trim();
  if (token.isEmpty) return null;
  _lastCompanyBootstrapHttpStatusCode = null;
  final endpoint = Uri.parse('${appConfig.bookingBaseUrl}/company/bootstrap');
  try {
    final res = await http
        .get(
          endpoint,
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 12));
    _lastCompanyBootstrapHttpStatusCode = res.statusCode;
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    return map['ok'] == true ? map : null;
  } catch (_) {
    return null;
  }
}

Future<Map<String, dynamic>> registerPublicCompany({
  required Map<String, dynamic> payload,
}) async {
  final endpoint = Uri.parse(
    '${appConfig.bookingBaseUrl}/public/company/register',
  );
  final res = await http
      .post(
        endpoint,
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      )
      .timeout(const Duration(seconds: 12));
  final decoded = jsonDecode(utf8.decode(res.bodyBytes));
  if (decoded is! Map) {
    throw Exception('registration_failed');
  }
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode >= 200 && res.statusCode < 300 && map['ok'] == true) {
    return map;
  }
  final errorCode = (map['error'] ?? '').toString().trim();
  if (errorCode.isNotEmpty) throw Exception(errorCode);
  throw Exception('registration_failed');
}

Future<Map<String, dynamic>> startPublicCompanyRecovery({
  required Map<String, dynamic> payload,
}) async {
  final endpoint = Uri.parse(
    '${appConfig.bookingBaseUrl}/public/company/recovery/start',
  );
  final res = await http
      .post(
        endpoint,
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      )
      .timeout(const Duration(seconds: 12));
  final decoded = jsonDecode(utf8.decode(res.bodyBytes));
  if (decoded is! Map) {
    throw Exception('recovery_start_failed');
  }
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode >= 200 && res.statusCode < 300 && map['ok'] == true) {
    return map;
  }
  final errorCode = (map['error'] ?? '').toString().trim();
  if (errorCode.isNotEmpty) throw Exception(errorCode);
  throw Exception('recovery_start_failed');
}

Future<Map<String, dynamic>> verifyPublicCompanyRecovery({
  required Map<String, dynamic> payload,
}) async {
  final endpoint = Uri.parse(
    '${appConfig.bookingBaseUrl}/public/company/recovery/verify',
  );
  final res = await http
      .post(
        endpoint,
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      )
      .timeout(const Duration(seconds: 12));
  final decoded = jsonDecode(utf8.decode(res.bodyBytes));
  if (decoded is! Map) {
    throw Exception('recovery_verify_failed');
  }
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode >= 200 && res.statusCode < 300 && map['ok'] == true) {
    return map;
  }
  final errorCode = (map['error'] ?? '').toString().trim();
  if (errorCode.isNotEmpty) throw Exception(errorCode);
  throw Exception('recovery_verify_failed');
}

Future<Map<String, dynamic>> startPublicCustomerPhoneAuth({
  required Map<String, dynamic> payload,
}) async {
  final endpoint = Uri.parse(
    '${appConfig.bookingBaseUrl}/public/customer/auth/phone/start',
  );
  final res = await http
      .post(
        endpoint,
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      )
      .timeout(const Duration(seconds: 12));
  final decoded = jsonDecode(utf8.decode(res.bodyBytes));
  if (decoded is! Map) {
    throw Exception('customer_phone_auth_start_failed');
  }
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode >= 200 && res.statusCode < 300 && map['ok'] == true) {
    return map;
  }
  final errorCode = (map['error'] ?? '').toString().trim();
  if (errorCode.isNotEmpty) throw Exception(errorCode);
  throw Exception('customer_phone_auth_start_failed');
}

Future<Map<String, dynamic>> verifyPublicCustomerPhoneAuth({
  required Map<String, dynamic> payload,
}) async {
  final endpoint = Uri.parse(
    '${appConfig.bookingBaseUrl}/public/customer/auth/phone/verify',
  );
  final res = await http
      .post(
        endpoint,
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      )
      .timeout(const Duration(seconds: 12));
  final decoded = jsonDecode(utf8.decode(res.bodyBytes));
  if (decoded is! Map) {
    throw Exception('customer_phone_auth_verify_failed');
  }
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode >= 200 && res.statusCode < 300 && map['ok'] == true) {
    return map;
  }
  final errorCode = (map['error'] ?? '').toString().trim();
  if (errorCode.isNotEmpty) throw Exception(errorCode);
  throw Exception('customer_phone_auth_verify_failed');
}

Future<Map<String, dynamic>> startPublicCustomerEmailAuth({
  required Map<String, dynamic> payload,
}) async {
  final endpoint = Uri.parse(
    '${appConfig.bookingBaseUrl}/public/customer/auth/email/start',
  );
  final res = await http
      .post(
        endpoint,
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      )
      .timeout(const Duration(seconds: 12));
  final decoded = jsonDecode(utf8.decode(res.bodyBytes));
  if (decoded is! Map) {
    throw Exception('customer_email_auth_start_failed');
  }
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode >= 200 && res.statusCode < 300 && map['ok'] == true) {
    return map;
  }
  final errorCode = (map['error'] ?? '').toString().trim();
  if (errorCode.isNotEmpty) throw Exception(errorCode);
  throw Exception('customer_email_auth_start_failed');
}

Future<Map<String, dynamic>> verifyPublicCustomerEmailAuth({
  required Map<String, dynamic> payload,
}) async {
  final endpoint = Uri.parse(
    '${appConfig.bookingBaseUrl}/public/customer/auth/email/verify',
  );
  final res = await http
      .post(
        endpoint,
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      )
      .timeout(const Duration(seconds: 12));
  final decoded = jsonDecode(utf8.decode(res.bodyBytes));
  if (decoded is! Map) {
    throw Exception('customer_email_auth_verify_failed');
  }
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode >= 200 && res.statusCode < 300 && map['ok'] == true) {
    return map;
  }
  final errorCode = (map['error'] ?? '').toString().trim();
  if (errorCode.isNotEmpty) throw Exception(errorCode);
  throw Exception('customer_email_auth_verify_failed');
}

Future<Map<String, dynamic>?> fetchPublicCustomerSessionBootstrap({
  required String customerSessionToken,
}) async {
  final token = customerSessionToken.trim();
  if (token.isEmpty) return null;
  _lastCustomerBootstrapHttpStatusCode = null;
  final endpoint = Uri.parse(
    '${appConfig.bookingBaseUrl}/public/customer/session/bootstrap',
  );
  try {
    final res = await http
        .get(
          endpoint,
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 12));
    _lastCustomerBootstrapHttpStatusCode = res.statusCode;
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    return map['ok'] == true ? map : null;
  } catch (_) {
    return null;
  }
}

Future<Map<String, dynamic>?> fetchPublicHotelSearch({
  String? city,
  String? country,
  String? region,
  String? searchText,
  double? lat,
  double? lng,
  double? radiusKm,
  String source = 'approved-local',
}) async {
  final qp = <String, String>{
    'source': source.trim().isEmpty ? 'approved-local' : source.trim(),
  };
  final normalizedCity = (city ?? '').trim();
  final normalizedCountry = (country ?? '').trim();
  final normalizedRegion = (region ?? '').trim();
  final normalizedSearchText = (searchText ?? '').trim();
  if (normalizedCity.isNotEmpty) qp['city'] = normalizedCity;
  if (normalizedCountry.isNotEmpty) qp['country'] = normalizedCountry;
  if (normalizedRegion.isNotEmpty) qp['region'] = normalizedRegion;
  if (normalizedSearchText.isNotEmpty) qp['q'] = normalizedSearchText;
  if (lat != null && lat.isFinite) qp['lat'] = lat.toStringAsFixed(6);
  if (lng != null && lng.isFinite) qp['lng'] = lng.toStringAsFixed(6);
  if (radiusKm != null && radiusKm.isFinite && radiusKm >= 0) {
    qp['radius_km'] = radiusKm.toStringAsFixed(2);
  }
  final endpoint = Uri.parse(
    '${appConfig.bookingBaseUrl}/public/hotels/search',
  ).replace(queryParameters: qp);
  try {
    final res = await http
        .get(
          endpoint,
          headers: const <String, String>{'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    return map['ok'] == true ? map : null;
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _sanitizePublicCustomerProfilePayload(
  Map<String, dynamic> payload,
) {
  String readAny(List<String> keys) {
    for (final key in keys) {
      final value = payload[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  List<String> readListAny(List<String> keys) {
    for (final key in keys) {
      final raw = payload[key];
      if (raw is! List) continue;
      final seen = <String>{};
      final out = <String>[];
      for (final item in raw) {
        final value = item.toString().trim();
        if (value.isEmpty || seen.contains(value)) continue;
        seen.add(value);
        out.add(value);
      }
      return out;
    }
    return const <String>[];
  }

  return <String, dynamic>{
    'name': readAny(const ['name']),
    'phone': readAny(const ['phone']),
    'email': readAny(const ['email']).toLowerCase(),
    'preferred_postcode': readAny(const [
      'preferred_postcode',
      'preferredPostcode',
    ]),
    'company_name': readAny(const ['company_name', 'companyName']),
    'vat_number': readAny(const ['vat_number', 'vatNumber']),
    'favorite_partner_ids': readListAny(const [
      'favorite_partner_ids',
      'favoritePartnerIds',
      'favourite_partner_ids',
      'favouritePartnerIds',
    ]),
  };
}

Future<Map<String, dynamic>?> fetchPublicCustomerProfile({
  required String customerSessionToken,
}) async {
  final token = customerSessionToken.trim();
  if (token.isEmpty) return null;
  _lastCustomerProfileHttpStatusCode = null;
  final endpoint = Uri.parse(
    '${appConfig.bookingBaseUrl}/public/customer/profile',
  );
  try {
    final res = await http
        .get(
          endpoint,
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 12));
    _lastCustomerProfileHttpStatusCode = res.statusCode;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      debugPrint(
        '[CUSTOMER_PROFILE_API][GET] ok=false status=${res.statusCode} reason=http_error',
      );
      return null;
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) {
      debugPrint(
        '[CUSTOMER_PROFILE_API][GET] ok=false status=${res.statusCode} reason=invalid_response',
      );
      return null;
    }
    final map = Map<String, dynamic>.from(decoded);
    final profileRaw = map['profile'];
    final profile = profileRaw is Map
        ? Map<String, dynamic>.from(profileRaw)
        : null;
    final ok = map['ok'] == true && profile != null;
    debugPrint(
      '[CUSTOMER_PROFILE_API][GET] ok=$ok status=${res.statusCode} reason=${ok ? "ok" : "missing_profile"}',
    );
    return ok ? profile : null;
  } catch (_) {
    debugPrint(
      '[CUSTOMER_PROFILE_API][GET] ok=false status=0 reason=network_error',
    );
    return null;
  }
}

Future<Map<String, dynamic>?> upsertPublicCustomerProfile({
  required String customerSessionToken,
  required Map<String, dynamic> payload,
}) async {
  final token = customerSessionToken.trim();
  if (token.isEmpty) return null;
  _lastCustomerProfileHttpStatusCode = null;
  final endpoint = Uri.parse(
    '${appConfig.bookingBaseUrl}/public/customer/profile',
  );
  final safePayload = _sanitizePublicCustomerProfilePayload(payload);
  try {
    final res = await http
        .post(
          endpoint,
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(safePayload),
        )
        .timeout(const Duration(seconds: 12));
    _lastCustomerProfileHttpStatusCode = res.statusCode;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      debugPrint(
        '[CUSTOMER_PROFILE_API][POST] ok=false status=${res.statusCode} reason=http_error',
      );
      return null;
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) {
      debugPrint(
        '[CUSTOMER_PROFILE_API][POST] ok=false status=${res.statusCode} reason=invalid_response',
      );
      return null;
    }
    final map = Map<String, dynamic>.from(decoded);
    final profileRaw = map['profile'];
    final profile = profileRaw is Map
        ? Map<String, dynamic>.from(profileRaw)
        : null;
    final ok = map['ok'] == true && profile != null;
    debugPrint(
      '[CUSTOMER_PROFILE_API][POST] ok=$ok status=${res.statusCode} reason=${ok ? "ok" : "missing_profile"}',
    );
    return ok ? profile : null;
  } catch (_) {
    debugPrint(
      '[CUSTOMER_PROFILE_API][POST] ok=false status=0 reason=network_error',
    );
    return null;
  }
}

Future<bool> hydrateCompanyStateFromBootstrap(
  Map<String, dynamic> bootstrap,
) async {
  if (bootstrap['ok'] != true) return false;
  try {
    String textAny(List<dynamic> values) {
      for (final value in values) {
        final text = (value ?? '').toString().trim();
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    int intAny(List<dynamic> values, int fallback) {
      for (final value in values) {
        if (value is int) return value;
        if (value is num) return value.round();
        final parsed = int.tryParse((value ?? '').toString().trim());
        if (parsed != null) return parsed;
      }
      return fallback;
    }

    double doubleAny(List<dynamic> values, double fallback) {
      for (final value in values) {
        if (value is double) return value;
        if (value is num) return value.toDouble();
        final parsed = double.tryParse(
          (value ?? '').toString().trim().replaceAll(',', '.'),
        );
        if (parsed != null && parsed.isFinite) return parsed;
      }
      return fallback;
    }

    bool boolAny(List<dynamic> values, bool fallback) {
      for (final value in values) {
        if (value is bool) return value;
        final text = (value ?? '').toString().trim().toLowerCase();
        if (text == 'true' || text == '1' || text == 'yes') return true;
        if (text == 'false' || text == '0' || text == 'no') return false;
      }
      return fallback;
    }

    String? safeRemoteMediaRef(String raw) {
      final text = raw.trim();
      if (text.isEmpty) return null;
      if (text.startsWith('https://') || text.startsWith('http://')) {
        return text;
      }
      if (text.startsWith('/public/media/') ||
          text.startsWith('public-media/')) {
        return text;
      }
      return null;
    }

    String? safeVehiclePhotoRef(String raw) {
      final text = raw.trim();
      if (text.isEmpty) return null;
      final lower = text.toLowerCase();
      if (lower.startsWith('https://') || lower.startsWith('http://')) {
        return text;
      }
      if (lower.startsWith('/public/media/') ||
          lower.startsWith('public-media/')) {
        return text;
      }
      if (lower.startsWith('assets/')) return text;
      return null;
    }

    List<String> safeVehiclePhotoRefsFromAny(List<dynamic> values) {
      for (final value in values) {
        if (value is! List) continue;
        final out = <String>[];
        for (final row in value) {
          final ref = safeVehiclePhotoRef((row ?? '').toString());
          if (ref == null || out.contains(ref)) continue;
          out.add(ref);
          if (out.length >= 12) break;
        }
        if (out.isNotEmpty) return out;
      }
      return const <String>[];
    }

    String maskScopeForLog(String value) {
      final text = value.trim();
      if (text.isEmpty) return '—';
      if (text.length <= 4) return '…${text.substring(text.length - 1)}';
      return '${text.substring(0, 2)}…${text.substring(text.length - 2)}';
    }

    final tenantId = textAny(<dynamic>[
      bootstrap['tenant_id'],
      bootstrap['tenantId'],
    ]);
    final companyId = textAny(<dynamic>[
      bootstrap['company_id'],
      bootstrap['companyId'],
      tenantId,
    ]);
    final bootstrapScopeCompanyId = companyId.trim().isNotEmpty
        ? companyId.trim()
        : tenantId.trim();
    final remoteDeletedDriverIds = <String>{};
    final deletedDriverIdsRaw =
        bootstrap['deleted_driver_ids'] ?? bootstrap['deletedDriverIds'];
    if (deletedDriverIdsRaw is List) {
      for (final row in deletedDriverIdsRaw) {
        final driverId = _normalizedDriverIdForTombstone('$row');
        if (driverId.isEmpty) continue;
        remoteDeletedDriverIds.add(driverId);
      }
    }
    debugPrint(
      '[DRIVER_DELETE][REMOTE_TOMBSTONE_SYNC] count=${remoteDeletedDriverIds.length}',
    );
    if (tenantId.isNotEmpty && bootstrapScopeCompanyId.isNotEmpty) {
      for (final driverId in remoteDeletedDriverIds) {
        _markDeletedDriverForScope(
          tenantId: tenantId,
          companyId: bootstrapScopeCompanyId,
          driverId: driverId,
        );
        debugPrint(
          '[DRIVER_DELETE][REMOTE_TOMBSTONE_APPLY] driver=${_maskDriverIdForDiag(driverId)}',
        );
      }
      if (remoteDeletedDriverIds.isNotEmpty) {
        driversNotifier.value = driversNotifier.value
            .where(
              (driver) => !remoteDeletedDriverIds.contains(driver.id.trim()),
            )
            .toList(growable: false);
        vehiclesNotifier.value = vehiclesNotifier.value
            .map(
              (vehicle) =>
                  remoteDeletedDriverIds.contains(
                    (vehicle.driverId ?? '').trim(),
                  )
                  ? vehicle.copyWith(driverId: null)
                  : vehicle,
            )
            .toList(growable: false);
      }
    }

    final businessMap = bootstrap['business_profile'] is Map
        ? Map<String, dynamic>.from(bootstrap['business_profile'] as Map)
        : <String, dynamic>{};
    final taxMap = bootstrap['tax_profile'] is Map
        ? Map<String, dynamic>.from(bootstrap['tax_profile'] as Map)
        : <String, dynamic>{};
    final pricingMap = bootstrap['pricing_profile'] is Map
        ? Map<String, dynamic>.from(bootstrap['pricing_profile'] as Map)
        : <String, dynamic>{};
    final mediaMap = bootstrap['media'] is Map
        ? Map<String, dynamic>.from(bootstrap['media'] as Map)
        : <String, dynamic>{};

    BackendBusinessProfile? backendBusinessProfile;
    if (businessMap.isNotEmpty) {
      backendBusinessProfile = BackendBusinessProfile.fromJson(businessMap);
      localBackendBusinessProfileNotifier.value = backendBusinessProfile;
    }
    BackendTaxProfile? backendTaxProfile;
    if (taxMap.isNotEmpty) {
      backendTaxProfile = BackendTaxProfile.fromJson(taxMap);
      localBackendTaxProfileNotifier.value = backendTaxProfile;
    }

    final current = businessSettingsNotifier.value;
    final backend =
        backendBusinessProfile ?? localBackendBusinessProfileNotifier.value;
    final effectiveTax =
        backendTaxProfile ?? localBackendTaxProfileNotifier.value;
    final logoUrl = safeRemoteMediaRef(
      textAny(<dynamic>[
        mediaMap['company_logo_url'],
        mediaMap['companyLogoUrl'],
        backend?.publicLogoUrl,
      ]),
    );
    final companyName = textAny(<dynamic>[
      backend?.companyName,
      (bootstrap['company'] is Map)
          ? (bootstrap['company'] as Map)['display_name']
          : null,
      current.companyName,
    ]);
    final supportEmail = textAny(<dynamic>[
      businessMap['supportEmail'],
      businessMap['support_email'],
      businessMap['email'],
      backend?.email,
      current.supportEmail,
    ]);
    final supportPhone = textAny(<dynamic>[
      businessMap['phone'],
      backend?.phone,
      current.supportPhone,
    ]);
    final bookingEmail = textAny(<dynamic>[
      businessMap['bookingEmail'],
      businessMap['booking_email'],
      backend?.bookingEmail,
      current.bookingSender,
    ]);
    final replyTo = textAny(<dynamic>[
      businessMap['replyToEmail'],
      businessMap['reply_to_email'],
      businessMap['notificationEmail'],
      businessMap['notification_email'],
      supportEmail,
      current.bookingReplyTo,
    ]);
    final address = <String>[
      textAny(<dynamic>[businessMap['address'], backend?.address]),
      textAny(<dynamic>[businessMap['postcode'], backend?.postcode]),
      textAny(<dynamic>[businessMap['city'], backend?.city]),
      textAny(<dynamic>[businessMap['country'], backend?.country]),
    ].where((e) => e.isNotEmpty).join('\n');

    final nextSettings = current.copyWith(
      companyName: companyName,
      supportEmail: supportEmail,
      supportPhone: supportPhone,
      vatCompanyNumber: textAny(<dynamic>[
        businessMap['vatNumber'],
        businessMap['vat_number'],
        backend?.vatNumber,
        current.vatCompanyNumber,
      ]),
      address: address.isEmpty ? current.address : address,
      bookingSender: bookingEmail,
      bookingReplyTo: replyTo,
      whatsappNumber: supportPhone,
      logoAssetPath: logoUrl ?? current.logoAssetPath,
      pricingBaseFare: doubleAny(<dynamic>[
        pricingMap['base_fare'],
        pricingMap['baseFare'],
      ], current.pricingBaseFare),
      pricingPerKm: doubleAny(<dynamic>[
        pricingMap['price_per_km'],
        pricingMap['pricePerKm'],
      ], current.pricingPerKm),
      pricingPerMinute: doubleAny(<dynamic>[
        pricingMap['price_per_minute'],
        pricingMap['pricePerMinute'],
      ], current.pricingPerMinute),
      pricingMinimumFare: doubleAny(<dynamic>[
        pricingMap['minimum_fare'],
        pricingMap['minimumFare'],
      ], current.pricingMinimumFare),
      pricingWaitPerMinute: doubleAny(<dynamic>[
        pricingMap['wait_per_minute'],
        pricingMap['waitPerMinute'],
      ], current.pricingWaitPerMinute),
      pricingReturnEnabled: boolAny(<dynamic>[
        pricingMap['return_enabled'],
        pricingMap['returnEnabled'],
      ], current.pricingReturnEnabled),
      pricingReturnFee: doubleAny(<dynamic>[
        pricingMap['return_fee'],
        pricingMap['returnFee'],
      ], current.pricingReturnFee),
      pricingFuelSurcharge: doubleAny(<dynamic>[
        pricingMap['fuel_surcharge'],
        pricingMap['fuelSurcharge'],
      ], current.pricingFuelSurcharge),
      pricingVatRate: doubleAny(<dynamic>[
        pricingMap['vat_rate'],
        pricingMap['vatRate'],
        effectiveTax?.vatRate,
      ], current.pricingVatRate),
      pricingVatMode: textAny(<dynamic>[
        pricingMap['vat_mode'],
        pricingMap['vatMode'],
        effectiveTax?.vatDisplayMode,
        current.pricingVatMode,
      ]),
    );
    updateBusinessSettings(nextSettings);

    String pickTextPreferRemote(String remote, String local) =>
        remote.trim().isNotEmpty ? remote.trim() : local;

    VehicleProfile mergeVehiclePreferLocal(
      VehicleProfile remote,
      VehicleProfile local,
    ) {
      return remote.copyWith(
        vehicleName: pickTextPreferRemote(
          remote.vehicleName,
          local.vehicleName,
        ),
        brandModel: pickTextPreferRemote(remote.brandModel, local.brandModel),
        licensePlate: pickTextPreferRemote(
          remote.licensePlate,
          local.licensePlate,
        ),
        exploitationLicenseNumber: pickTextPreferRemote(
          remote.exploitationLicenseNumber,
          local.exploitationLicenseNumber,
        ),
        vehicleRegistrationNumber: pickTextPreferRemote(
          remote.vehicleRegistrationNumber,
          local.vehicleRegistrationNumber,
        ),
        color: pickTextPreferRemote(remote.color, local.color),
        passengerCapacity: remote.passengerCapacity > 0
            ? remote.passengerCapacity
            : local.passengerCapacity,
        luggageCapacity: remote.luggageCapacity > 0
            ? remote.luggageCapacity
            : local.luggageCapacity,
        tierId: pickTextPreferRemote(remote.tierId, local.tierId),
        driverId: (remote.driverId ?? '').trim().isNotEmpty
            ? remote.driverId
            : local.driverId,
        companyId: (remote.companyId ?? '').trim().isNotEmpty
            ? remote.companyId
            : local.companyId,
        primaryPhotoRef: pickTextPreferRemote(
          remote.primaryPhotoRef,
          local.primaryPhotoRef,
        ),
        galleryPhotoRefs: remote.galleryPhotoRefs.isNotEmpty
            ? remote.galleryPhotoRefs
            : local.galleryPhotoRefs,
        publicPhotoUrl: ((remote.publicPhotoUrl ?? '').trim().isNotEmpty)
            ? remote.publicPhotoUrl
            : local.publicPhotoUrl,
      );
    }

    DriverProfile mergeDriverPreferLocal(
      DriverProfile remote,
      DriverProfile local,
    ) {
      return remote.copyWith(
        fullName: pickTextPreferRemote(remote.fullName, local.fullName),
        employeeNumber: pickTextPreferRemote(
          remote.employeeNumber,
          local.employeeNumber,
        ),
        hasLoginCode: remote.hasLoginCode || local.hasLoginCode,
        driverCodeLast4: ((remote.driverCodeLast4 ?? '').trim().isNotEmpty)
            ? remote.driverCodeLast4
            : local.driverCodeLast4,
        loginCodeLast4: ((remote.loginCodeLast4 ?? '').trim().isNotEmpty)
            ? remote.loginCodeLast4
            : local.loginCodeLast4,
        phone: pickTextPreferRemote(remote.phone, local.phone),
        taxiDriverCardNumber: pickTextPreferRemote(
          remote.taxiDriverCardNumber,
          local.taxiDriverCardNumber,
        ),
        taxiDriverCardExpiry: pickTextPreferRemote(
          remote.taxiDriverCardExpiry,
          local.taxiDriverCardExpiry,
        ),
        companyId: (remote.companyId ?? '').trim().isNotEmpty
            ? remote.companyId
            : local.companyId,
        publicDisplayName: ((remote.publicDisplayName ?? '').trim().isNotEmpty)
            ? remote.publicDisplayName
            : local.publicDisplayName,
        // Keep backend bootstrap canonical for remote-present driver records.
        publicPortraitUrl: remote.publicPortraitUrl,
        // Backend bootstrap is canonical for active/inactive state.
        isActive: remote.isActive,
        // Backend bootstrap is canonical for operational availability state.
        availabilityStatus: remote.availabilityStatus,
        ratingAvg: remote.ratingAvg ?? local.ratingAvg,
        ratingCount: remote.ratingCount ?? local.ratingCount,
      );
    }

    var rawVehiclesCount = 0;
    var mappedVehiclesCount = 0;
    final vehiclesRaw = bootstrap['vehicles'];
    if (vehiclesRaw is List) {
      rawVehiclesCount = vehiclesRaw.length;
      final existingVehiclesById = <String, VehicleProfile>{
        for (final item in vehiclesNotifier.value)
          if (item.id.trim().isNotEmpty) item.id.trim(): item,
      };
      final nextVehicles = <VehicleProfile>[];
      final remoteVehicleIds = <String>{};
      for (final row in vehiclesRaw) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);
        final vehicleId = textAny(<dynamic>[
          map['vehicle_id'],
          map['vehicleId'],
          map['id'],
        ]);
        if (vehicleId.isEmpty) continue;
        remoteVehicleIds.add(vehicleId);
        final assignedDriver = map['assigned_driver'] is Map
            ? Map<String, dynamic>.from(map['assigned_driver'] as Map)
            : <String, dynamic>{};
        final vehiclePhotoUrl = safeRemoteMediaRef(
          textAny(<dynamic>[
            map['public_photo_url'],
            map['publicPhotoUrl'],
            map['vehicle_photo_url'],
            map['vehiclePhotoUrl'],
            map['photo_url'],
            map['photoUrl'],
          ]),
        );
        final primaryPhotoRef = safeVehiclePhotoRef(
          textAny(<dynamic>[
            map['primary_photo_ref'],
            map['primaryPhotoRef'],
            map['photo_ref'],
            map['photoRef'],
            map['public_photo_url'],
            map['publicPhotoUrl'],
            map['vehicle_photo_url'],
            map['vehiclePhotoUrl'],
          ]),
        );
        final galleryPhotoRefs = safeVehiclePhotoRefsFromAny(<dynamic>[
          map['gallery_photo_refs'],
          map['galleryPhotoRefs'],
        ]);
        final assignedDriverId = textAny(<dynamic>[
          assignedDriver['driver_id'],
          assignedDriver['driverId'],
          assignedDriver['id'],
          map['driver_id'],
          map['driverId'],
          map['assigned_driver_id'],
          map['assignedDriverId'],
        ]);
        debugPrint(
          '[VEHICLE_ASSIGNMENT_BOOTSTRAP][IN] vehicle=${_maskVehicleIdForDiag(vehicleId)} name=${_shortVehicleTextForDiag(textAny(<dynamic>[map["vehicle_name"], map["vehicleName"], map["name"], vehicleId]))} plate=${_shortVehicleTextForDiag(textAny(<dynamic>[map["license_plate"], map["licensePlate"]]))} driver=${_maskDriverIdForDiag(assignedDriverId)}',
        );
        final vehicleCompanyId = textAny(<dynamic>[
          map['company_id'],
          map['companyId'],
          bootstrapScopeCompanyId,
        ]);
        final remoteVehicle = VehicleProfile(
          id: vehicleId,
          vehicleName: textAny(<dynamic>[
            map['vehicle_name'],
            map['vehicleName'],
            map['name'],
            vehicleId,
          ]),
          brandModel: textAny(<dynamic>[
            map['brand_model'],
            map['brandModel'],
            '',
          ]),
          licensePlate: textAny(<dynamic>[
            map['license_plate'],
            map['licensePlate'],
            '',
          ]),
          exploitationLicenseNumber: textAny(<dynamic>[
            map['exploitation_license_number'],
            map['exploitationLicenseNumber'],
            '',
          ]),
          vehicleRegistrationNumber: textAny(<dynamic>[
            map['vehicle_registration_number'],
            map['vehicleRegistrationNumber'],
            '',
          ]),
          color: textAny(<dynamic>[map['color'], '']),
          passengerCapacity: intAny(<dynamic>[
            map['passenger_capacity'],
            map['passengerCapacity'],
          ], 0),
          luggageCapacity: intAny(<dynamic>[
            map['luggage_capacity'],
            map['luggageCapacity'],
          ], 0),
          tierId: textAny(<dynamic>[
            map['tier'],
            map['tier_id'],
            map['tierId'],
            'comfort',
          ]),
          isActive: boolAny(<dynamic>[map['is_active'], map['isActive']], true),
          driverId: assignedDriverId.isEmpty ? null : assignedDriverId,
          companyId: vehicleCompanyId.isEmpty
              ? (bootstrapScopeCompanyId.isEmpty
                    ? null
                    : bootstrapScopeCompanyId)
              : vehicleCompanyId,
          primaryPhotoRef: primaryPhotoRef ?? '',
          galleryPhotoRefs: galleryPhotoRefs,
          publicPhotoUrl: vehiclePhotoUrl,
        );
        final existingVehicle = existingVehiclesById[vehicleId];
        nextVehicles.add(
          existingVehicle == null
              ? remoteVehicle
              : mergeVehiclePreferLocal(remoteVehicle, existingVehicle),
        );
      }
      for (final local in vehiclesNotifier.value) {
        final localId = local.id.trim();
        if (localId.isEmpty || remoteVehicleIds.contains(localId)) continue;
        final localCompany = (local.companyId ?? '').trim();
        if (localCompany.isNotEmpty &&
            localCompany != bootstrapScopeCompanyId) {
          continue;
        }
        nextVehicles.add(local);
      }
      mappedVehiclesCount = nextVehicles.length;
      vehiclesNotifier.value = nextVehicles;
    }

    var rawDriversCount = 0;
    var mappedDriversCount = 0;
    final driversRaw = bootstrap['drivers'];
    if (driversRaw is List) {
      rawDriversCount = driversRaw.length;
      final existingDriversById = <String, DriverProfile>{
        for (final item in driversNotifier.value)
          if (item.id.trim().isNotEmpty) item.id.trim(): item,
      };
      final nextDrivers = <DriverProfile>[];
      final remoteDriverIds = <String>{};
      for (final row in driversRaw) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);
        final driverId = textAny(<dynamic>[
          map['driver_id'],
          map['driverId'],
          map['id'],
        ]);
        if (driverId.isEmpty) continue;
        if (remoteDeletedDriverIds.contains(driverId)) {
          debugPrint(
            '[DRIVER_HYDRATE_MERGE][SKIP_TOMBSTONED_LOCAL] driver=${_maskDriverIdForDiag(driverId)}',
          );
          continue;
        }
        remoteDriverIds.add(driverId);
        final fullName = textAny(<dynamic>[
          map['display_name'],
          map['displayName'],
          map['public_display_name'],
          map['publicDisplayName'],
          map['driver_name'],
          map['driverName'],
          driverId,
        ]);
        final driverPhotoUrl = safeRemoteMediaRef(
          textAny(<dynamic>[
            map['driver_photo_url'],
            map['driverPhotoUrl'],
            map['public_portrait_url'],
            map['publicPortraitUrl'],
          ]),
        );
        final driverCompanyId = textAny(<dynamic>[
          map['tenant_id'],
          map['tenantId'],
          map['company_id'],
          map['companyId'],
          bootstrapScopeCompanyId,
        ]);
        final remoteDriver = DriverProfile(
          id: driverId,
          fullName: fullName,
          employeeNumber: textAny(<dynamic>[
            map['employee_number'],
            map['employeeNumber'],
          ]),
          hasLoginCode: boolAny(<dynamic>[
            map['has_login_code'],
            map['hasLoginCode'],
          ], false),
          driverCodeLast4: () {
            final value = textAny(<dynamic>[
              map['driver_code_last4'],
              map['driverCodeLast4'],
            ]);
            return value.isEmpty ? null : value;
          }(),
          loginCodeLast4: () {
            final value = textAny(<dynamic>[
              map['login_code_last4'],
              map['loginCodeLast4'],
            ]);
            return value.isEmpty ? null : value;
          }(),
          phone: textAny(<dynamic>[map['phone'], '']),
          taxiDriverCardNumber: textAny(<dynamic>[
            map['taxi_driver_card_number'],
            map['taxiDriverCardNumber'],
            '',
          ]),
          taxiDriverCardExpiry: textAny(<dynamic>[
            map['taxi_driver_card_expiry'],
            map['taxiDriverCardExpiry'],
            '',
          ]),
          isActive: boolAny(<dynamic>[map['is_active'], map['isActive']], true),
          availabilityStatus: normalizeDriverAvailabilityState(
            map['availability_status'] ?? map['availabilityStatus'],
            fallback: 'available',
          ),
          ratingAvg: () {
            final raw =
                map['rating_avg'] ??
                map['ratingAvg'] ??
                map['average_rating'] ??
                map['averageRating'] ??
                map['driver_rating_avg'] ??
                map['driverRatingAvg'];
            if (raw is num) return raw.toDouble();
            final parsed = double.tryParse((raw ?? '').toString().trim());
            return parsed != null && parsed.isFinite ? parsed : null;
          }(),
          ratingCount: () {
            final raw =
                map['rating_count'] ??
                map['ratingCount'] ??
                map['reviews_count'] ??
                map['reviewsCount'] ??
                map['driver_rating_count'] ??
                map['driverRatingCount'];
            if (raw is int) return raw;
            if (raw is num) return raw.round();
            return int.tryParse((raw ?? '').toString().trim());
          }(),
          companyId: driverCompanyId.isEmpty
              ? (bootstrapScopeCompanyId.isEmpty
                    ? null
                    : bootstrapScopeCompanyId)
              : driverCompanyId,
          publicProfileEnabled: boolAny(<dynamic>[
            map['public_profile_enabled'],
            map['publicProfileEnabled'],
          ], false),
          publicPhotoEnabled: boolAny(<dynamic>[
            map['public_photo_enabled'],
            map['publicPhotoEnabled'],
          ], false),
          publicDisplayName: () {
            final value = textAny(<dynamic>[
              map['public_display_name'],
              map['publicDisplayName'],
            ]);
            return value.isEmpty ? null : value;
          }(),
          publicPortraitUrl: driverPhotoUrl,
        );
        final existingDriver = existingDriversById[driverId];
        if (existingDriver != null) {
          final finalDriver = mergeDriverPreferLocal(
            remoteDriver,
            existingDriver,
          );
          debugPrint(
            '[DRIVER_HYDRATE_MERGE][REMOTE_WINS] id=${_maskDriverIdForDiag(driverId)} name=${finalDriver.fullName.trim()} remoteActive=${remoteDriver.isActive} localActive=${existingDriver.isActive} finalActive=${finalDriver.isActive}',
          );
          nextDrivers.add(finalDriver);
          continue;
        }
        nextDrivers.add(remoteDriver);
      }
      for (final local in driversNotifier.value) {
        final localId = local.id.trim();
        if (localId.isEmpty || remoteDriverIds.contains(localId)) continue;
        final localCompany = (local.companyId ?? '').trim();
        if (localCompany.isNotEmpty &&
            localCompany != bootstrapScopeCompanyId) {
          continue;
        }
        final tombstoneCompanyId = bootstrapScopeCompanyId.isNotEmpty
            ? bootstrapScopeCompanyId
            : tenantId;
        final isTombstoned = _isDriverIdTombstonedForScope(
          tenantId: tenantId,
          companyId: tombstoneCompanyId,
          driverId: localId,
        );
        if (isTombstoned) {
          debugPrint(
            '[DRIVER_HYDRATE_MERGE][SKIP_TOMBSTONED_LOCAL] driver=${_maskDriverIdForDiag(localId)}',
          );
          continue;
        }
        debugPrint(
          '[DRIVER_HYDRATE_MERGE][LOCAL_ONLY_RETAINED] id=${_maskDriverIdForDiag(localId)} name=${local.fullName.trim()} isActive=${local.isActive} company=${_maskCompanyScopeForLog(localCompany)}',
        );
        nextDrivers.add(local);
      }
      mappedDriversCount = nextDrivers.length;
      driversNotifier.value = nextDrivers;
      _applySanitizedDriversToNotifier(
        tenantId: tenantId,
        companyId: bootstrapScopeCompanyId,
        reason: 'bootstrap_hydrate',
      );
      mappedDriversCount = driversNotifier.value.length;
    }

    debugPrint(
      '[COMPANY_BOOTSTRAP][HYDRATE_COUNTS] rawVehicles=$rawVehiclesCount mappedVehicles=$mappedVehiclesCount rawDrivers=$rawDriversCount mappedDrivers=$mappedDriversCount company=${maskScopeForLog(bootstrapScopeCompanyId)}',
    );
    debugPrint(
      '[COMPANY_BOOTSTRAP][NOTIFIERS] vehicles=${vehiclesNotifier.value.length} drivers=${driversNotifier.value.length}',
    );

    await _persistLocalTenantState();
    return true;
  } catch (_) {
    return false;
  }
}

Future<Map<String, dynamic>> publishBackendPublicPartnerProfile({
  required Map<String, dynamic> partnerProfile,
  String? tenantId,
  String? companyId,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/partners/profile/publish'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final scope = _resolveAdminTenantCompanyScope(
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .post(
        endpoint,
        headers: auth.headers,
        body: jsonEncode(<String, dynamic>{
          ...scope,
          'partner_profile': partnerProfile,
        }),
      )
      .timeout(const Duration(seconds: 12));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) throw Exception('Invalid response');
  return Map<String, dynamic>.from(decoded);
}

Future<Map<String, dynamic>> uploadPublicPartnerMedia({
  required String mediaType,
  String? tenantId,
  String? companyId,
  String? entityId,
  String? filePath,
  Uint8List? fileBytes,
  String? filename,
  String? contentType,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/partners/media/upload'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final scope = _resolveAdminTenantCompanyScope(
    tenantId: tenantId,
    companyId: companyId,
  );
  final normalizedType = mediaType.trim().toLowerCase();
  if (normalizedType.isEmpty) {
    throw Exception('mediaType is required');
  }
  final hasPath = (filePath ?? '').trim().isNotEmpty;
  final bytesForUpload = fileBytes ?? Uint8List(0);
  final hasBytes = bytesForUpload.isNotEmpty;
  if (!hasPath && !hasBytes) {
    throw Exception('filePath or fileBytes is required');
  }

  String fallbackFilename() {
    if ((filename ?? '').trim().isNotEmpty) return filename!.trim();
    if (hasPath) {
      final raw = filePath!.trim();
      final slash = raw.lastIndexOf('/');
      final backSlash = raw.lastIndexOf('\\');
      final idx = slash > backSlash ? slash : backSlash;
      if (idx >= 0 && idx < raw.length - 1) {
        return raw.substring(idx + 1);
      }
      return raw;
    }
    switch (contentType?.trim().toLowerCase()) {
      case 'image/png':
        return 'upload.png';
      case 'image/webp':
        return 'upload.webp';
      default:
        return 'upload.jpg';
    }
  }

  final auth = await resolveCompanyOwnerAuthHeaders(json: false);
  final request = http.MultipartRequest('POST', endpoint);
  final headers = Map<String, String>.from(auth.headers);
  headers.removeWhere((k, _) => k.toLowerCase() == 'content-type');
  request.headers.addAll(headers);
  request.fields['tenant_id'] = scope['tenant_id'] ?? '';
  request.fields['company_id'] = scope['company_id'] ?? '';
  request.fields['media_type'] = normalizedType;
  final trimmedEntityId = (entityId ?? '').trim();
  if (trimmedEntityId.isNotEmpty) {
    request.fields['entity_id'] = trimmedEntityId;
  }

  final uploadFilename = fallbackFilename();
  String mimeFromFilename(String name) {
    final lower = name.trim().toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return '';
  }

  String mimeFromBytes(Uint8List bytes) {
    final len = bytes.length;
    if (len >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (len >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    if (len >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return '';
  }

  Future<Uint8List?> sniffBytesFromPath(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final all = await file.readAsBytes();
      final count = all.length < 32 ? all.length : 32;
      return Uint8List.sublistView(all, 0, count);
    } catch (_) {
      return null;
    }
  }

  final mimeFromName = mimeFromFilename(uploadFilename);
  final providedContentType = (contentType ?? '').trim().toLowerCase();
  final bytesForSniff = hasBytes
      ? Uint8List.sublistView(
          bytesForUpload,
          0,
          bytesForUpload.length < 32 ? bytesForUpload.length : 32,
        )
      : await sniffBytesFromPath(filePath!.trim());
  final mimeFromMagic = bytesForSniff == null
      ? ''
      : mimeFromBytes(bytesForSniff);
  final resolvedMime =
      <String>[mimeFromMagic, mimeFromName, providedContentType].firstWhere(
        (m) => m == 'image/jpeg' || m == 'image/png' || m == 'image/webp',
        orElse: () => 'application/octet-stream',
      );
  final slash = resolvedMime.indexOf('/');
  final multipartMediaType = slash > 0 && slash < resolvedMime.length - 1
      ? MediaType(
          resolvedMime.substring(0, slash),
          resolvedMime.substring(slash + 1),
        )
      : MediaType('application', 'octet-stream');

  if (hasBytes) {
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytesForUpload,
        filename: uploadFilename,
        contentType: multipartMediaType,
      ),
    );
  } else {
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        filePath!.trim(),
        filename: uploadFilename,
        contentType: multipartMediaType,
      ),
    );
  }

  final streamed = await request.send().timeout(const Duration(seconds: 30));
  final body = await streamed.stream.bytesToString();
  if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
    throw Exception('HTTP ${streamed.statusCode}: $body');
  }
  final decoded = jsonDecode(body);
  if (decoded is! Map) throw Exception('Invalid response');
  return Map<String, dynamic>.from(decoded);
}

Future<Map<String, dynamic>> fetchBackendGoogleCalendarStatus({
  String? tenantId,
  String? companyId,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/google-calendar/status'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .get(endpoint, headers: auth.headers)
      .timeout(const Duration(seconds: 12));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) throw Exception('Invalid response');
  return Map<String, dynamic>.from(decoded);
}

Future<Map<String, dynamic>> startBackendGoogleCalendarOAuth({
  String? tenantId,
  String? companyId,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/google-calendar/oauth/start'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final scope = _resolveAdminTenantCompanyScope(
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .post(
        endpoint,
        headers: auth.headers,
        body: jsonEncode(<String, dynamic>{...scope}),
      )
      .timeout(const Duration(seconds: 12));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) throw Exception('Invalid response');
  return Map<String, dynamic>.from(decoded);
}

Future<Map<String, dynamic>> disconnectBackendGoogleCalendar({
  String? tenantId,
  String? companyId,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/google-calendar/disconnect'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final scope = _resolveAdminTenantCompanyScope(
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .post(
        endpoint,
        headers: auth.headers,
        body: jsonEncode(<String, dynamic>{...scope}),
      )
      .timeout(const Duration(seconds: 12));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) throw Exception('Invalid response');
  return Map<String, dynamic>.from(decoded);
}

Map<String, dynamic> _safeMollieConnectMap(Map<dynamic, dynamic> raw) {
  String textAny(List<String> keys) {
    for (final key in keys) {
      final value = raw[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  bool boolAny(List<String> keys) {
    for (final key in keys) {
      final value = raw[key];
      if (value is bool) return value;
      if (value is String) {
        final token = value.trim().toLowerCase();
        if (token == 'true') return true;
        if (token == 'false') return false;
      }
    }
    return false;
  }

  return <String, dynamic>{
    'connected': boolAny(const ['connected']),
    'status': textAny(const ['status']),
    'mollie_organization_id': textAny(const [
      'mollie_organization_id',
      'mollieOrganizationId',
    ]),
    'mollieOrganizationId': textAny(const [
      'mollieOrganizationId',
      'mollie_organization_id',
    ]),
    'mollie_profile_id': textAny(const [
      'mollie_profile_id',
      'mollieProfileId',
    ]),
    'mollieProfileId': textAny(const ['mollieProfileId', 'mollie_profile_id']),
    'mollie_mode': textAny(const ['mollie_mode', 'mollieMode']),
    'mollieMode': textAny(const ['mollieMode', 'mollie_mode']),
    'onboarding_status': textAny(const [
      'onboarding_status',
      'onboardingStatus',
    ]),
    'onboardingStatus': textAny(const [
      'onboardingStatus',
      'onboarding_status',
    ]),
    'last_connected_at': textAny(const [
      'last_connected_at',
      'lastConnectedAt',
    ]),
    'lastConnectedAt': textAny(const ['lastConnectedAt', 'last_connected_at']),
    'updated_at': textAny(const ['updated_at', 'updatedAt']),
    'updatedAt': textAny(const ['updatedAt', 'updated_at']),
    'last_error_code': textAny(const ['last_error_code', 'lastErrorCode']),
    'lastErrorCode': textAny(const ['lastErrorCode', 'last_error_code']),
    'auth_url': textAny(const ['auth_url', 'authUrl']),
    'authUrl': textAny(const ['authUrl', 'auth_url']),
  };
}

Future<Map<String, dynamic>> fetchBackendMollieConnectStatus({
  String? tenantId,
  String? companyId,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/mollie/connect/status'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .get(endpoint, headers: auth.headers)
      .timeout(const Duration(seconds: 12));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) throw Exception('Invalid response');
  return _safeMollieConnectMap(decoded);
}

Future<Map<String, dynamic>> startBackendMollieConnect({
  String? tenantId,
  String? companyId,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/mollie/connect/start'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final scope = _resolveAdminTenantCompanyScope(
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .post(
        endpoint,
        headers: auth.headers,
        body: jsonEncode(<String, dynamic>{...scope}),
      )
      .timeout(const Duration(seconds: 12));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) throw Exception('Invalid response');
  return _safeMollieConnectMap(decoded);
}

Future<Map<String, dynamic>> disconnectBackendMollieConnect({
  String? tenantId,
  String? companyId,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/mollie/connect/disconnect'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final scope = _resolveAdminTenantCompanyScope(
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .post(
        endpoint,
        headers: auth.headers,
        body: jsonEncode(<String, dynamic>{...scope}),
      )
      .timeout(const Duration(seconds: 12));
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) throw Exception('Invalid response');
  return _safeMollieConnectMap(decoded);
}

Future<Map<String, dynamic>> fetchCompanyMollieTerminals({
  String? tenantId,
  String? companyId,
  bool testmode = false,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/mollie/terminals').replace(
      queryParameters: testmode
          ? const <String, String>{'testmode': 'true'}
          : null,
    ),
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .get(endpoint, headers: auth.headers)
      .timeout(const Duration(seconds: 12));
  final decoded = jsonDecode(utf8.decode(res.bodyBytes));
  if (decoded is! Map) throw Exception('Invalid response');
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception(
      _adminApiErrorMessageFromResponse(
        map,
        res.statusCode,
        fallback: 'mollie_terminals_fetch_failed',
      ),
    );
  }
  return map;
}

Future<Map<String, dynamic>> syncCompanyMollieTerminals({
  String? tenantId,
  String? companyId,
  bool testmode = false,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse('${appConfig.bookingBaseUrl}/admin/mollie/terminals/sync'),
    tenantId: tenantId,
    companyId: companyId,
  );
  final scope = _resolveAdminTenantCompanyScope(
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .post(
        endpoint,
        headers: auth.headers,
        body: jsonEncode(<String, dynamic>{
          ...scope,
          if (testmode) 'testmode': true,
        }),
      )
      .timeout(const Duration(seconds: 20));
  final decoded = jsonDecode(utf8.decode(res.bodyBytes));
  if (decoded is! Map) throw Exception('Invalid response');
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception(
      _adminApiErrorMessageFromResponse(
        map,
        res.statusCode,
        fallback: 'mollie_terminals_sync_failed',
      ),
    );
  }
  return map;
}

Future<Map<String, dynamic>> startBackendMollieTerminalPayment({
  required String tenantId,
  required String companyId,
  required String bookingId,
  required String terminalId,
  required String amountValue,
  String currency = 'EUR',
  String description = 'Fluxidi terminal test payment',
  bool dryRun = true,
  bool confirmLiveTerminalPayment = false,
}) async {
  final endpoint = _withAdminTenantCompanyScope(
    Uri.parse(
      '${appConfig.bookingBaseUrl}/admin/mollie/terminal-payment/start',
    ),
    tenantId: tenantId,
    companyId: companyId,
  );
  final auth = await resolveCompanyOwnerAuthHeaders();
  final res = await http
      .post(
        endpoint,
        headers: auth.headers,
        body: jsonEncode(<String, dynamic>{
          'tenant_id': tenantId,
          'company_id': companyId,
          'booking_id': bookingId,
          'terminal_id': terminalId,
          'amount': <String, dynamic>{
            'currency': currency,
            'value': amountValue,
          },
          'description': description,
          'dry_run': dryRun,
          'confirm_live_terminal_payment': confirmLiveTerminalPayment,
        }),
      )
      .timeout(const Duration(seconds: 20));
  final decoded = jsonDecode(utf8.decode(res.bodyBytes));
  if (decoded is! Map) throw Exception('Invalid response');
  final map = Map<String, dynamic>.from(decoded);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception(
      _adminApiErrorMessageFromResponse(
        map,
        res.statusCode,
        fallback: 'mollie_terminal_payment_start_failed',
      ),
    );
  }
  return map;
}

Future<void> loadLocalTenantState() async {
  try {
    _deletedDriverIdsByScope.clear();
    final file = await _tenantStateFile();
    final exists = await file.exists();
    debugPrint('tenant_state_load path=${file.path} exists=$exists');
    if (!exists) return;

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return;
    final map = Map<String, dynamic>.from(decoded);
    _decodeDeletedDriverTombstonesFromPersistence(
      map['deletedDriverIdsByScope'],
    );

    final currentBusiness = businessSettingsNotifier.value;
    final businessMap = map['businessSettings'];
    if (businessMap is Map) {
      final businessJson = Map<String, dynamic>.from(businessMap);
      final loadedBusiness = _decodeBusinessSettings(
        businessJson,
        fallback: currentBusiness,
      );
      businessSettingsNotifier.value = loadedBusiness;
      // Respect explicit saved language preference only.
      // If no language key exists in saved data, keep app default.
      if (businessJson.containsKey('defaultLanguage')) {
        setAppLanguage(loadedBusiness.defaultLanguage);
      }
    }

    // Backward-compatible: only present when the user already saved official
    // company details locally. Older tenant_state_v1.json files load fine.
    final backendProfileMap = map['backendBusinessProfile'];
    if (backendProfileMap is Map) {
      try {
        localBackendBusinessProfileNotifier.value =
            BackendBusinessProfile.fromJson(
              Map<String, dynamic>.from(backendProfileMap),
            );
      } catch (_) {
        // Ignore malformed cached profile; defaults remain.
      }
    }

    // Backward-compatible: only present when the user already saved BTW
    // settings locally. Older tenant_state_v1.json files load fine.
    final backendTaxProfileMap = map['backendTaxProfile'];
    if (backendTaxProfileMap is Map) {
      try {
        localBackendTaxProfileNotifier.value = BackendTaxProfile.fromJson(
          Map<String, dynamic>.from(backendTaxProfileMap),
        );
      } catch (_) {
        // Ignore malformed cached tax profile; defaults remain.
      }
    }

    final vehiclesRaw = map['vehicles'];
    if (vehiclesRaw is List && vehiclesRaw.isNotEmpty) {
      final fallbackVehicle = vehiclesNotifier.value.isNotEmpty
          ? vehiclesNotifier.value.first
          : const VehicleProfile(
              id: 'vh_fallback',
              vehicleName: '',
              brandModel: '',
              licensePlate: '',
              color: '',
              passengerCapacity: 0,
              luggageCapacity: 0,
              tierId: 'comfort',
              isActive: true,
              driverId: null,
              companyId: null,
              primaryPhotoRef: '',
              galleryPhotoRefs: <String>[],
            );
      final loaded = vehiclesRaw
          .whereType<Map>()
          .map(
            (e) => _decodeVehicle(
              Map<String, dynamic>.from(e),
              fallback: fallbackVehicle,
            ),
          )
          .toList(growable: false);
      if (loaded.isNotEmpty) {
        vehiclesNotifier.value = loaded;
      }
    }
    final driversRaw = map['drivers'];
    if (driversRaw is List && driversRaw.isNotEmpty) {
      final fallbackDriver = driversNotifier.value.isNotEmpty
          ? driversNotifier.value.first
          : const DriverProfile(
              id: 'drv_fallback',
              fullName: '',
              employeeNumber: '',
              phone: '',
              isActive: true,
              companyId: null,
            );
      final loadedDrivers = driversRaw
          .whereType<Map>()
          .map(
            (e) => _decodeDriver(
              Map<String, dynamic>.from(e),
              fallback: fallbackDriver,
            ),
          )
          .toList(growable: false);
      if (loadedDrivers.isNotEmpty) {
        driversNotifier.value = loadedDrivers;
        _applySanitizedDriversToNotifier(
          reason: 'tenant_state_load',
          persist: true,
        );
      }
    }
    debugPrint(
      'tenant_state_loaded business=${businessSettingsNotifier.value.companyName} vehicles=${vehiclesNotifier.value.length} drivers=${driversNotifier.value.length}',
    );
  } catch (_) {
    // Ignore corrupt/missing local state and keep defaults.
  }
}

class AppLabels {
  final String calculatorTitle;
  final String calculatorQuoteTitle;
  final String bookingsTitle;
  final String liveRideTitle;
  final String activeRideTitle;
  final String refreshBookingsLabel;
  final String centerOnMeLabel;
  final String drawerDriverIdLabel;
  final String drawerWorkerLabel;
  final String drawerMapboxTokenLabel;
  final String followCarLabel;
  final String followCarSubtitle;
  final String bookingsMenuSubtitle;
  final String liveRideMenuSubtitle;
  final String calculatorMenuSubtitle;
  final String activeRideMenuSubtitle;
  final String availableBookingsTitle;
  final String refreshShortLabel;
  final String bookingsEmptyLabel;
  final String stopShortLabel;

  // Optional calculator-focused labels for safer white-label reuse.
  final String calculatorFromLabel;
  final String calculatorToLabel;
  final String calculatorBagsLabel;
  final String calculatorPassengersLabel;
  final String calculatorPickupTimeLabel;
  final String calculatorServiceLabel;
  final String calculatorTierLabel;
  final String calculatorReturnLabel;
  final String calculatorWaitTimeLabel;
  final String calculatorBreakdownTitle;
  final String calculatorButtonLabel;
  final String calculatorButtonBusyLabel;
  final String calculatorExtraServiceOptionalLabel;
  final String calculatorReturnSubtitle;
  final String calculatorVatRateLabel;
  final String calculatorAddressHint;
  final String calculatorUseCurrentLocationTooltip;
  final String calculatorSuggestionTapHint;
  final String calculatorChoosePickupTimeLabel;
  final String calculatorWaitStepHint;
  final String calculatorQuoteTipText;
  final String calculatorPriceInclVatLabel;
  final String calculatorPriceExVatLabel;
  final String calculatorVatLabel;
  final String calculatorDistanceLabel;
  final String calculatorDurationLabel;
  final String calculatorErrorPrefix;
  final String calculatorFillFromToError;
  final String calculatorLocationServiceOffError;
  final String calculatorNoLocationPermissionError;
  final String calculatorCurrentLocationFailedError;
  final String calculatorCurrentLocationFallbackLabel;
  final String calculatorMaxBagsHint;
  final String calculatorMaxPassengersHint;

  const AppLabels({
    required this.calculatorTitle,
    required this.calculatorQuoteTitle,
    required this.bookingsTitle,
    required this.liveRideTitle,
    required this.activeRideTitle,
    required this.refreshBookingsLabel,
    required this.centerOnMeLabel,
    required this.drawerDriverIdLabel,
    required this.drawerWorkerLabel,
    required this.drawerMapboxTokenLabel,
    required this.followCarLabel,
    required this.followCarSubtitle,
    required this.bookingsMenuSubtitle,
    required this.liveRideMenuSubtitle,
    required this.calculatorMenuSubtitle,
    required this.activeRideMenuSubtitle,
    required this.availableBookingsTitle,
    required this.refreshShortLabel,
    required this.bookingsEmptyLabel,
    required this.stopShortLabel,
    required this.calculatorFromLabel,
    required this.calculatorToLabel,
    required this.calculatorBagsLabel,
    required this.calculatorPassengersLabel,
    required this.calculatorPickupTimeLabel,
    required this.calculatorServiceLabel,
    required this.calculatorTierLabel,
    required this.calculatorReturnLabel,
    required this.calculatorWaitTimeLabel,
    required this.calculatorBreakdownTitle,
    required this.calculatorButtonLabel,
    required this.calculatorButtonBusyLabel,
    required this.calculatorExtraServiceOptionalLabel,
    required this.calculatorReturnSubtitle,
    required this.calculatorVatRateLabel,
    required this.calculatorAddressHint,
    required this.calculatorUseCurrentLocationTooltip,
    required this.calculatorSuggestionTapHint,
    required this.calculatorChoosePickupTimeLabel,
    required this.calculatorWaitStepHint,
    required this.calculatorQuoteTipText,
    required this.calculatorPriceInclVatLabel,
    required this.calculatorPriceExVatLabel,
    required this.calculatorVatLabel,
    required this.calculatorDistanceLabel,
    required this.calculatorDurationLabel,
    required this.calculatorErrorPrefix,
    required this.calculatorFillFromToError,
    required this.calculatorLocationServiceOffError,
    required this.calculatorNoLocationPermissionError,
    required this.calculatorCurrentLocationFailedError,
    required this.calculatorCurrentLocationFallbackLabel,
    required this.calculatorMaxBagsHint,
    required this.calculatorMaxPassengersHint,
  });
}

const AppConfig appConfig = AppConfig(
  identity: CompanyIdentityConfig(
    companyName: 'Fluxidi',
    appTitle: 'Fluxidi Driver',
    logoAsset: 'assets/fluxidi/fluxidi_logo.png',
    companyShortName: 'Fluxidi',
    supportEmail: 'support@fluxidi.com',
    supportPhone: '+32 000 00 00 00',
  ),
  branding: BrandingConfig(
    primaryColor: Color(0xFFFFD400),
    accentColor: Color(0xFFFFD54F),
    backgroundColor: Color(0xFF07080B),
    surfaceColor: Color(0xFF121318),
    cardColor: Color(0xFF171922),
    textSoftColor: Color(0xFFB8BDC9),
    softAccentColor: Color(0x33FFD400),
    calculatorScaffoldColor: Color(0xFF050505),
    calculatorPanelColor: Color(0xFF0B0B0B),
    calculatorDropdownColor: Color(0xFF111111),
  ),
  businessDefaults: BusinessDefaultsConfig(
    defaultCurrency: 'EUR',
    defaultCurrencySymbol: '€',
    taxDisplayLabel: 'BTW',
    defaultVatRate: 0.06,
    distanceUnitLabel: 'km',
    durationUnitLabel: 'min',
    use24HourTime: true,
    showDetailedBreakdown: true,
  ),
  workerBaseUrl: 'https://fluxidi-tracking-api.fluxidi.workers.dev',
  bookingBaseUrl: 'https://fluxidi-booking-api.fluxidi.workers.dev',
  defaultLanguage: AppLanguage.en,
  enabledServices: <AppOption>[
    AppOption(
      id: 'airport',
      label: LocalizedText(
        nl: 'Luchthaven',
        en: 'Airport',
        fr: 'Aeroport',
        es: 'Aeropuerto',
      ),
      payloadValue: 'AIRPORT',
    ),
    AppOption(
      id: 'passenger',
      label: LocalizedText(
        nl: 'Personenvervoer',
        en: 'Passenger transport',
        fr: 'Transport passagers',
        es: 'Transporte de pasajeros',
      ),
      payloadValue: 'PASSENGER',
    ),
    AppOption(
      id: 'business',
      label: LocalizedText(
        nl: 'Zakelijk',
        en: 'Business',
        fr: 'Affaires',
        es: 'Negocios',
      ),
      payloadValue: 'BUSINESS',
    ),
    AppOption(
      id: 'courier',
      label: LocalizedText(
        nl: 'Spoedkoerier',
        en: 'Courier',
        fr: 'Coursier',
        es: 'Mensajeria',
      ),
      payloadValue: 'COURIER',
    ),
    AppOption(
      id: 'care',
      label: LocalizedText(
        nl: 'Zorgvervoer',
        en: 'Care transport',
        fr: 'Transport de soins',
        es: 'Transporte asistencial',
      ),
      payloadValue: 'CARE',
    ),
    // Backward-compatible payload for current Worker.
    AppOption(
      id: 'event',
      label: LocalizedText(
        nl: 'Evenement',
        en: 'Event',
        fr: 'Evenement',
        es: 'Evento',
      ),
      payloadValue: 'SPECIAL',
    ),
  ],
  enabledTiers: <AppOption>[
    AppOption(
      id: 'comfort',
      label: LocalizedText(
        nl: 'Comfort',
        en: 'Comfort',
        fr: 'Confort',
        es: 'Confort',
      ),
      payloadValue: 'COMFORT',
    ),
    AppOption(
      id: 'private',
      label: LocalizedText(
        nl: 'Private',
        en: 'Private',
        fr: 'Prive',
        es: 'Privado',
      ),
      payloadValue: 'PRIVATE',
    ),
    AppOption(
      id: 'premium',
      label: LocalizedText(
        nl: 'Premium',
        en: 'Premium',
        fr: 'Premium',
        es: 'Premium',
      ),
      payloadValue: 'PREMIUM',
    ),
  ],
  enabledExtraOptions: <AppOption>[
    AppOption(
      id: 'none',
      label: LocalizedText(
        nl: 'Geen extra service',
        en: 'No extra service',
        fr: 'Aucun service supplementaire',
        es: 'Sin servicio extra',
      ),
      payloadValue: 'NONE',
    ),
    AppOption(
      id: 'drinks',
      label: LocalizedText(
        nl: 'Drankservice (water/fris — alcohol op aanvraag)',
        en: 'Drinks service (water/soft drinks — alcohol on request)',
        fr: 'Service boissons (eau/softs — alcool sur demande)',
        es: 'Servicio de bebidas (agua/refrescos — alcohol bajo solicitud)',
      ),
      payloadValue: 'DRINKS',
    ),
    AppOption(
      id: 'worktable',
      label: LocalizedText(
        nl: 'Werktafel (laptop)',
        en: 'Work table (laptop)',
        fr: 'Table de travail (mode ordinateur)',
        es: 'Mesa de trabajo (modo portatil)',
      ),
      payloadValue: 'WORKTABLE',
    ),
  ],
  labels: AppLabels(
    calculatorTitle: 'Calculator',
    calculatorQuoteTitle: 'Jouw ritprijs',
    bookingsTitle: 'Ritten',
    liveRideTitle: 'Live rit',
    activeRideTitle: 'Actieve rit',
    refreshBookingsLabel: 'Vernieuw ritten',
    centerOnMeLabel: 'Centreer op mij',
    drawerDriverIdLabel: 'Driver ID',
    drawerWorkerLabel: 'Worker',
    drawerMapboxTokenLabel: 'Mapbox REST token',
    followCarLabel: 'Follow car',
    followCarSubtitle: 'Tesla-style camera in driving mode',
    bookingsMenuSubtitle: 'Bekijk & beheer ritten',
    liveRideMenuSubtitle: 'Start een rit (A → B)',
    calculatorMenuSubtitle: 'Prijsberekening',
    activeRideMenuSubtitle: 'Cockpit',
    availableBookingsTitle: 'Beschikbare ritten',
    refreshShortLabel: 'Vernieuw',
    bookingsEmptyLabel: 'Geen ritten gevonden.',
    stopShortLabel: 'Stop',
    calculatorFromLabel: 'VAN',
    calculatorToLabel: 'NAAR',
    calculatorBagsLabel: 'Bagage',
    calculatorPassengersLabel: 'Passagiers',
    calculatorPickupTimeLabel: 'Ophaaltijd',
    calculatorServiceLabel: 'Service',
    calculatorTierLabel: 'Tier',
    calculatorReturnLabel: 'Retour',
    calculatorWaitTimeLabel: 'Wachttijd (min)',
    calculatorBreakdownTitle: 'Breakdown',
    calculatorButtonLabel: 'Bereken mijn ritprijs',
    calculatorButtonBusyLabel: 'Berekenen…',
    calculatorExtraServiceOptionalLabel: 'Extra service (optioneel)',
    calculatorReturnSubtitle: 'Heen + terug',
    calculatorVatRateLabel: 'VAT rate',
    calculatorAddressHint: 'Typ een adres…',
    calculatorUseCurrentLocationTooltip: 'Gebruik mijn huidige locatie',
    calculatorSuggestionTapHint: 'Tik om te selecteren',
    calculatorChoosePickupTimeLabel: 'Kies…',
    calculatorWaitStepHint: 'In stappen van 5 min.',
    calculatorQuoteTipText:
        'Tip: de Worker blijft de source-of-truth. Deze UI is puur input + weergave.',
    calculatorPriceInclVatLabel: 'Prijs incl. btw',
    calculatorPriceExVatLabel: 'Prijs excl. btw',
    calculatorVatLabel: 'BTW',
    calculatorDistanceLabel: 'Afstand',
    calculatorDurationLabel: 'Duur',
    calculatorErrorPrefix: 'Error',
    calculatorFillFromToError: 'Vul zowel VAN als NAAR in.',
    calculatorLocationServiceOffError: 'Locatie staat uit op je toestel.',
    calculatorNoLocationPermissionError: 'Geen locatie-permissie.',
    calculatorCurrentLocationFailedError: 'Kon huidige locatie niet ophalen.',
    calculatorCurrentLocationFallbackLabel: 'Huidige locatie',
    calculatorMaxBagsHint: 'Max 3 koffers.',
    calculatorMaxPassengersHint: 'Max 3 passagiers.',
  ),
  features: AppFeatures(
    calculatorEnabled: true,
    trackingEnabled: true,
    liveMapEnabled: true,
    bookingsEnabled: true,
  ),
);
