import 'package:flutter/material.dart';

/// Which product variant this build represents.
///
/// Phase 1 ships only [fluxidiMarketplace]. The white-label variant is listed
/// so later build-time configuration has a place to plug in, but no company
/// selection or white-label build matrix is implemented yet.
enum CustomerAppVariant {
  /// One Fluxidi customer app; the customer picks a taxi company in-app.
  fluxidiMarketplace,

  /// One customer app bound to a single taxi company at build time.
  whiteLabelSingleCompany,
}

/// Fluxidi brand palette, reused by value so this app shares no code with the
/// existing combined app.
@immutable
class CustomerBrandColors {
  const CustomerBrandColors({
    required this.primary,
    required this.accent,
    required this.background,
    required this.surface,
    required this.card,
    required this.textSoft,
  });

  final Color primary;
  final Color accent;
  final Color background;
  final Color surface;
  final Color card;
  final Color textSoft;
}

/// Central configuration for name, development identity and branding.
@immutable
class CustomerAppConfig {
  const CustomerAppConfig({
    required this.appName,
    required this.environmentLabel,
    required this.androidApplicationId,
    required this.deepLinkScheme,
    required this.deepLinkHost,
    required this.deepLinkPath,
    required this.variant,
    required this.brand,
  });

  /// User-visible app name.
  final String appName;

  /// Short label that marks this build as a development identity.
  final String environmentLabel;

  /// Android applicationId this build is expected to carry.
  final String androidApplicationId;

  /// Own payment-return scheme. Never the combined app's scheme.
  final String deepLinkScheme;
  final String deepLinkHost;
  final String deepLinkPath;

  final CustomerAppVariant variant;
  final CustomerBrandColors brand;

  /// Payment-return link this build answers to, for documentation and tests.
  String get paymentReturnUrl => '$deepLinkScheme://$deepLinkHost$deepLinkPath';

  bool get isWhiteLabel => variant == CustomerAppVariant.whiteLabelSingleCompany;
}

/// Development identity for phase 1. Not a final Play identity.
const CustomerAppConfig kCustomerAppConfig = CustomerAppConfig(
  appName: 'Fluxidi Customer Dev',
  environmentLabel: 'DEV',
  androidApplicationId: 'com.fluxidi.customer.dev',
  deepLinkScheme: 'fluxidicustomerdev',
  deepLinkHost: 'pay',
  deepLinkPath: '/return',
  variant: CustomerAppVariant.fluxidiMarketplace,
  brand: CustomerBrandColors(
    primary: Color(0xFFFFD400),
    accent: Color(0xFFFFD54F),
    background: Color(0xFF07080B),
    surface: Color(0xFF121318),
    card: Color(0xFF171922),
    textSoft: Color(0xFFB8BDC9),
  ),
);
