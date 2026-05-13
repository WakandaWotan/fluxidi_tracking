import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
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
  final String publicPartnerProfilePublishedAt;
  final String publicPartnerProfilePublishStatus;
  final String invoiceEmail;
  final String iban;
  final String paymentReferencePrefix;
  final String invoiceReceiptFooterText;

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
    this.publicPartnerProfilePublishedAt = '',
    this.publicPartnerProfilePublishStatus = '',
    required this.invoiceEmail,
    required this.iban,
    required this.paymentReferencePrefix,
    required this.invoiceReceiptFooterText,
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
    publicPartnerProfilePublishedAt: '',
    publicPartnerProfilePublishStatus: '',
    invoiceEmail: appConfig.supportEmail,
    iban: '',
    paymentReferencePrefix: 'FLX',
    invoiceReceiptFooterText: '',
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
    'publicPartnerProfilePublishedAt': publicPartnerProfilePublishedAt,
    'public_partner_profile_published_at': publicPartnerProfilePublishedAt,
    'publicPartnerProfilePublishStatus': publicPartnerProfilePublishStatus,
    'public_partner_profile_publish_status': publicPartnerProfilePublishStatus,
    'invoiceEmail': invoiceEmail,
    'iban': iban,
    'paymentReferencePrefix': paymentReferencePrefix,
    'invoiceReceiptFooterText': invoiceReceiptFooterText,
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
  final String phone;
  final String taxiDriverCardNumber;
  final String taxiDriverCardExpiry;
  final bool isActive;
  final String? profilePhotoPath;
  final bool publicProfileEnabled;
  final bool publicPhotoEnabled;
  final String? publicDisplayName;
  final String? publicPortraitUrl;

  /// See [VehicleProfile.companyId].
  final String? companyId;

  String? get tenantId => companyId;

  const DriverProfile({
    required this.id,
    required this.fullName,
    required this.employeeNumber,
    required this.phone,
    this.taxiDriverCardNumber = '',
    this.taxiDriverCardExpiry = '',
    required this.isActive,
    this.profilePhotoPath,
    this.publicProfileEnabled = false,
    this.publicPhotoEnabled = false,
    this.publicDisplayName,
    this.publicPortraitUrl,
    this.companyId,
  });

  DriverProfile copyWith({
    String? id,
    String? fullName,
    String? employeeNumber,
    String? phone,
    String? taxiDriverCardNumber,
    String? taxiDriverCardExpiry,
    bool? isActive,
    Object? profilePhotoPath = _driverProfileUnset,
    bool? publicProfileEnabled,
    bool? publicPhotoEnabled,
    Object? publicDisplayName = _driverProfileUnset,
    Object? publicPortraitUrl = _driverProfileUnset,
    String? companyId,
  }) {
    return DriverProfile(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      employeeNumber: employeeNumber ?? this.employeeNumber,
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
      companyId: companyId ?? this.companyId,
    );
  }
}

const Object _driverProfileUnset = Object();

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
}) {
  businessSettingsNotifier.value = next;
  _persistLocalTenantState();
  unawaited(
    syncPricingProfileToBackend(tenantId: tenantId, companyId: companyId),
  );
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

void addVehicle(VehicleProfile vehicle) {
  vehiclesNotifier.value = <VehicleProfile>[...vehiclesNotifier.value, vehicle];
  _persistLocalTenantState();
  unawaited(syncLocalCompanyInventoryToBackend(reason: 'vehicle_save'));
}

void updateVehicle(String id, VehicleProfile updated) {
  vehiclesNotifier.value = vehiclesNotifier.value
      .map((v) => v.id == id ? updated : v)
      .toList(growable: false);
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
  _persistLocalTenantState();
  unawaited(syncLocalCompanyInventoryToBackend(reason: 'driver_save'));
}

void updateDriver(String id, DriverProfile updated) {
  final normalizedUpdated = _driverWithNormalizedLoginCode(updated);
  driversNotifier.value = driversNotifier.value
      .map((d) => d.id == id ? normalizedUpdated : d)
      .toList(growable: false);
  _persistLocalTenantState();
  unawaited(syncLocalCompanyInventoryToBackend(reason: 'driver_save'));
}

DriverProfile _driverWithNormalizedLoginCode(DriverProfile driver) {
  final fallbackCode = driver.id.trim();
  final code = driver.employeeNumber.trim();
  if (code.isNotEmpty) return driver;
  if (fallbackCode.isEmpty) return driver;
  return driver.copyWith(employeeNumber: fallbackCode);
}

void deleteDriver(String id) {
  DriverProfile? existingDriver;
  for (final d in driversNotifier.value) {
    if (d.id == id) {
      existingDriver = d;
      break;
    }
  }
  final scopeId = _fleetScopeIdFromLocalState();
  if (existingDriver != null) {
    unawaited(
      syncDriverIndexEntryToBackend(
        existingDriver,
        tenantId: scopeId,
        companyId: scopeId,
        isActiveOverride: false,
      ),
    );
  }
  driversNotifier.value = driversNotifier.value
      .where((d) => d.id != id)
      .toList(growable: false);
  vehiclesNotifier.value = vehiclesNotifier.value
      .map((v) => v.driverId == id ? v.copyWith(driverId: null) : v)
      .toList(growable: false);
  _persistLocalTenantState();
  unawaited(syncFleetInventoryToBackend(tenantId: scopeId, companyId: scopeId));
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
  if (!hadDriver && !hadVehicleLinks) return;

  driversNotifier.value = driversNotifier.value
      .where((d) => d.id != driverId)
      .toList(growable: false);
  vehiclesNotifier.value = vehiclesNotifier.value
      .map((v) => v.driverId == driverId ? v.copyWith(driverId: null) : v)
      .toList(growable: false);

  _persistLocalTenantState();

  final scope = _resolveAdminTenantCompanyScope(
    tenantId: tenantId,
    companyId: companyId,
  );
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
  };
}

BusinessSettingsState _decodeBusinessSettings(
  Map<String, dynamic> m, {
  required BusinessSettingsState fallback,
}) {
  Set<String> _setOf(dynamic v, Set<String> fb) {
    if (v is List) {
      return v.map((e) => e.toString()).toSet();
    }
    return fb;
  }

  double _toDouble(dynamic v, double fb) {
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
    enabledServiceIds: _setOf(
      m['enabledServiceIds'],
      fallback.enabledServiceIds,
    ),
    enabledTierIds: _setOf(m['enabledTierIds'], fallback.enabledTierIds),
    enabledExtraOptionIds: _setOf(
      m['enabledExtraOptionIds'],
      fallback.enabledExtraOptionIds,
    ),
    bookingSender: (m['bookingSender'] ?? fallback.bookingSender).toString(),
    bookingReplyTo: (m['bookingReplyTo'] ?? fallback.bookingReplyTo).toString(),
    whatsappNumber: (m['whatsappNumber'] ?? fallback.whatsappNumber).toString(),
    pricingBaseFare: _toDouble(m['pricingBaseFare'], fallback.pricingBaseFare),
    pricingPerKm: _toDouble(m['pricingPerKm'], fallback.pricingPerKm),
    pricingPerMinute: _toDouble(
      m['pricingPerMinute'],
      fallback.pricingPerMinute,
    ),
    pricingMinimumFare: _toDouble(
      m['pricingMinimumFare'],
      fallback.pricingMinimumFare,
    ),
    pricingWaitPerMinute: _toDouble(
      m['pricingWaitPerMinute'],
      fallback.pricingWaitPerMinute,
    ),
    pricingReturnEnabled: (m['pricingReturnEnabled'] is bool)
        ? m['pricingReturnEnabled'] as bool
        : fallback.pricingReturnEnabled,
    pricingReturnFee: _toDouble(
      m['pricingReturnFee'],
      fallback.pricingReturnFee,
    ),
    pricingFuelSurcharge: _toDouble(
      m['pricingFuelSurcharge'],
      fallback.pricingFuelSurcharge,
    ),
    pricingVatRate: _toDouble(m['pricingVatRate'], fallback.pricingVatRate),
    pricingVatMode: (m['pricingVatMode'] ?? fallback.pricingVatMode).toString(),
    pricingBagFeeEach: _toDouble(
      m['pricingBagFeeEach'],
      fallback.pricingBagFeeEach,
    ),
    pricingStopFeeEach: _toDouble(
      m['pricingStopFeeEach'],
      fallback.pricingStopFeeEach,
    ),
    pricingTierFeeComfort: _toDouble(
      m['pricingTierFeeComfort'],
      fallback.pricingTierFeeComfort,
    ),
    pricingTierFeePrivate: _toDouble(
      m['pricingTierFeePrivate'],
      fallback.pricingTierFeePrivate,
    ),
    pricingTierFeePremium: _toDouble(
      m['pricingTierFeePremium'],
      fallback.pricingTierFeePremium,
    ),
    pricingNightSurchargeRate: _toDouble(
      m['pricingNightSurchargeRate'],
      fallback.pricingNightSurchargeRate,
    ),
    pricingWeekendSurchargeRate: _toDouble(
      m['pricingWeekendSurchargeRate'],
      fallback.pricingWeekendSurchargeRate,
    ),
    pricingSurchargeCapRate: _toDouble(
      m['pricingSurchargeCapRate'],
      fallback.pricingSurchargeCapRate,
    ),
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
    'phone': d.phone,
    'taxiDriverCardNumber': d.taxiDriverCardNumber,
    'taxiDriverCardExpiry': d.taxiDriverCardExpiry,
    'isActive': d.isActive,
    'profilePhotoPath': d.profilePhotoPath,
    'publicProfileEnabled': d.publicProfileEnabled,
    'publicPhotoEnabled': d.publicPhotoEnabled,
    'publicDisplayName': d.publicDisplayName,
    'publicPortraitUrl': d.publicPortraitUrl,
    'companyId': d.companyId,
  };
}

VehicleProfile _decodeVehicle(
  Map<String, dynamic> m, {
  required VehicleProfile fallback,
}) {
  int _toInt(dynamic v, int fb) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? fb;
  }

  List<String> _toStringList(dynamic v) {
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
  final gallery = _toStringList(m['galleryPhotoRefs']);
  final String? publicPhotoUrl = () {
    final raw = m['publicPhotoUrl'];
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
    passengerCapacity: _toInt(
      m['passengerCapacity'],
      fallback.passengerCapacity,
    ),
    luggageCapacity: _toInt(m['luggageCapacity'], fallback.luggageCapacity),
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

  final id = (m['id'] ?? fallback.id).toString();
  final employeeNumber = (m['employeeNumber'] ?? fallback.employeeNumber)
      .toString()
      .trim();
  final resolvedEmployeeNumber = employeeNumber.isNotEmpty
      ? employeeNumber
      : id.trim();

  return fallback.copyWith(
    id: id,
    fullName: (m['fullName'] ?? fallback.fullName).toString(),
    employeeNumber: resolvedEmployeeNumber,
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

String _maskCompanyScopeForLog(String value) {
  final text = value.trim();
  if (text.isEmpty) return '—';
  if (text.length <= 4) return '…${text.substring(text.length - 1)}';
  return '${text.substring(0, 2)}…${text.substring(text.length - 2)}';
}

Map<String, String> _resolveAdminTenantCompanyScope({
  String? tenantId,
  String? companyId,
}) {
  final effectiveTenant = (tenantId ?? companyId ?? '').trim();
  final effectiveCompany = (companyId ?? tenantId ?? '').trim();
  final normalizedTenant = effectiveTenant.isEmpty
      ? kTenantId
      : effectiveTenant;
  final normalizedCompany = effectiveCompany.isEmpty
      ? normalizedTenant
      : effectiveCompany;
  return <String, String>{
    'tenant_id': normalizedTenant,
    'company_id': normalizedCompany,
    'tenantId': normalizedTenant,
    'companyId': normalizedCompany,
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

Map<String, dynamic> _encodePricingProfileForBackend(BusinessSettingsState s) {
  final vat = resolveActiveVatConfig(settings: s);
  return <String, dynamic>{
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
  final resolvedTenant = tenantId.trim().isEmpty ? kTenantId : tenantId.trim();
  final resolvedCompany = companyId.trim().isEmpty
      ? resolvedTenant
      : companyId.trim();
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
  final driverCode = driver.employeeNumber.trim();
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
    'employee_number': driverCode,
    'employeeNumber': driverCode,
    'driver_code': driverCode,
    'driverCode': driverCode,
    'login_code': driverCode,
    'loginCode': driverCode,
    'chauffeur_code': driverCode,
    'chauffeurCode': driverCode,
    if (normalizedPhone != null) 'phone': normalizedPhone,
    'is_active': isActiveOverride ?? driver.isActive,
    'isActive': isActiveOverride ?? driver.isActive,
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
    await http
        .post(
          endpoint,
          headers: _adminJsonHeaders(),
          body: jsonEncode(<String, dynamic>{
            ...scope,
            'pricing_profile': profilePayload,
          }),
        )
        .timeout(const Duration(seconds: 12));
    return true;
  } catch (_) {
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
            tenantId: scope['tenant_id'] ?? kTenantId,
            companyId: scope['company_id'] ?? kTenantId,
          ),
        )
        .where((e) => (e['vehicle_id'] as String).isNotEmpty)
        .toList(growable: false);
    await http
        .post(
          endpoint,
          headers: _adminJsonHeaders(),
          body: jsonEncode(<String, dynamic>{
            ...scope,
            'vehicles': fleetPayload,
          }),
        )
        .timeout(const Duration(seconds: 12));
    return true;
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
    if (driverId.isEmpty) return false;
    final payload = _encodeDriverForBackendIndexPayload(
      driver,
      tenantId: scope['tenant_id'] ?? kTenantId,
      companyId: scope['company_id'] ?? kTenantId,
      isActiveOverride: isActiveOverride,
    );
    final response = await http
        .post(endpoint, headers: _adminJsonHeaders(), body: jsonEncode(payload))
        .timeout(const Duration(seconds: 12));
    return response.statusCode >= 200 && response.statusCode < 300;
  } catch (_) {
    return false;
  }
}

Future<void> syncLocalCompanyInventoryToBackend({
  required String reason,
  String? tenantId,
  String? companyId,
}) async {
  if (_companyInventorySyncInFlight) return;
  final token = _fleetSyncAdminToken.trim();
  if (token.isEmpty) return;
  final localScopeId = _fleetScopeIdFromLocalState().trim();
  final resolvedTenant = (tenantId ?? companyId ?? localScopeId).trim();
  final resolvedCompany = (companyId ?? tenantId ?? localScopeId).trim();
  if (resolvedTenant.isEmpty || resolvedCompany.isEmpty) return;

  final scopedVehicles = vehiclesNotifier.value
      .where(
        (v) =>
            (v.companyId?.trim().isEmpty ?? true) ||
            v.companyId!.trim() == resolvedCompany,
      )
      .toList(growable: false);
  final scopedDrivers = driversNotifier.value
      .where(
        (d) =>
            (d.companyId?.trim().isEmpty ?? true) ||
            d.companyId!.trim() == resolvedCompany,
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
    '[COMPANY_SYNC][START] reason=$reason vehicles=${scopedVehicles.length} drivers=${scopedDrivers.length} company=${_maskCompanyScopeForLog(resolvedCompany)}',
  );
  debugPrint(
    '[COMPANY_SYNC][LOCAL_COUNTS] vehicles=${vehiclesNotifier.value.length} drivers=${driversNotifier.value.length} scopedVehicles=${scopedVehicles.length} scopedDrivers=${scopedDrivers.length}',
  );
  debugPrint(
    '[COMPANY_SYNC][LINKS] vehicleLinks=$vehicleLinks driverVehicleLinks=$driverVehicleLinks',
  );
  try {
    final scope = _resolveAdminTenantCompanyScope(
      tenantId: resolvedTenant,
      companyId: resolvedCompany,
    );

    if (scopedVehicles.isNotEmpty) {
      try {
        final endpoint = _withAdminTenantCompanyScope(
          Uri.parse('${appConfig.bookingBaseUrl}/admin/fleet/vehicles'),
          tenantId: scope['tenant_id'],
          companyId: scope['company_id'],
        );
        final fleetPayload = scopedVehicles
            .map(
              (vehicle) => _encodeVehicleForBackendFleet(
                vehicle,
                tenantId: scope['tenant_id'] ?? kTenantId,
                companyId: scope['company_id'] ?? kTenantId,
              ),
            )
            .where((e) => (e['vehicle_id'] as String).isNotEmpty)
            .toList(growable: false);
        final response = await http
            .post(
              endpoint,
              headers: _adminJsonHeaders(),
              body: jsonEncode(<String, dynamic>{
                ...scope,
                'vehicles': fleetPayload,
              }),
            )
            .timeout(const Duration(seconds: 12));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          debugPrint(
            '[COMPANY_SYNC][VEHICLES_OK] count=${fleetPayload.length}',
          );
        } else {
          debugPrint(
            '[COMPANY_SYNC][VEHICLES_ERROR] status=${response.statusCode} message=non_2xx',
          );
        }
      } catch (_) {
        debugPrint(
          '[COMPANY_SYNC][VEHICLES_ERROR] status=network message=exception',
        );
      }
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
            tenantId: scope['tenant_id'] ?? kTenantId,
            companyId: scope['company_id'] ?? kTenantId,
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
  final res = await http
      .get(endpoint, headers: _adminJsonHeaders())
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
  final res = await http
      .post(
        endpoint,
        headers: _adminJsonHeaders(),
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
  final res = await http
      .get(endpoint, headers: _adminJsonHeaders())
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
  final res = await http
      .post(
        endpoint,
        headers: _adminJsonHeaders(),
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

int? _lastCompanyBootstrapHttpStatusCode;
int? get lastCompanyBootstrapHttpStatusCode =>
    _lastCompanyBootstrapHttpStatusCode;

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
        publicPortraitUrl: ((remote.publicPortraitUrl ?? '').trim().isNotEmpty)
            ? remote.publicPortraitUrl
            : local.publicPortraitUrl,
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
            driverId,
          ]),
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
        nextDrivers.add(
          existingDriver == null
              ? remoteDriver
              : mergeDriverPreferLocal(remoteDriver, existingDriver),
        );
      }
      for (final local in driversNotifier.value) {
        final localId = local.id.trim();
        if (localId.isEmpty || remoteDriverIds.contains(localId)) continue;
        final localCompany = (local.companyId ?? '').trim();
        if (localCompany.isNotEmpty &&
            localCompany != bootstrapScopeCompanyId) {
          continue;
        }
        nextDrivers.add(local);
      }
      mappedDriversCount = nextDrivers.length;
      driversNotifier.value = nextDrivers;
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
  final res = await http
      .post(
        endpoint,
        headers: _adminJsonHeaders(),
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

  final request = http.MultipartRequest('POST', endpoint);
  final headers = Map<String, String>.from(_adminJsonHeaders());
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
  final res = await http
      .get(endpoint, headers: _adminJsonHeaders())
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
  final res = await http
      .post(
        endpoint,
        headers: _adminJsonHeaders(),
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
  final res = await http
      .post(
        endpoint,
        headers: _adminJsonHeaders(),
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

Future<void> loadLocalTenantState() async {
  try {
    final file = await _tenantStateFile();
    final exists = await file.exists();
    debugPrint('tenant_state_load path=${file.path} exists=$exists');
    if (!exists) return;

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return;
    final map = Map<String, dynamic>.from(decoded);

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
