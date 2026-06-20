import 'package:flutter/material.dart';

import 'payment_method_catalog.dart';

const _logosDir = 'assets/payment/logos';
const _badgesDir = 'assets/payment/badges';
const _providersDir = 'assets/payment/providers';

/// Logo files known to exist under [_logosDir]. Add names here when new PNGs land.
const _availableLogoFileNames = <String>{
  'bancontact.png',
  'bank_transfer.png',
  'belfius.png',
  'card.png',
  'carte_bancaire.png',
  'google_pay.png',
  'ideal.png',
  'kbc_cbc.png',
  'paypal.png',
};

String? _logoAssetIfAvailable(String fileName) {
  if (!_availableLogoFileNames.contains(fileName)) return null;
  return '$_logosDir/$fileName';
}

/// Official Mollie payment logo asset path for [methodId], or null when none.
String? paymentMethodLogoAssetForId(String methodId) {
  final id = normalizePaymentMethodId(methodId);
  switch (id) {
    case PaymentMethodIds.bancontact:
      return _logoAssetIfAvailable('bancontact.png');
    case PaymentMethodIds.kbcCbc:
      return _logoAssetIfAvailable('kbc_cbc.png');
    case PaymentMethodIds.belfius:
      return _logoAssetIfAvailable('belfius.png');
    case PaymentMethodIds.cardPayment:
      return _logoAssetIfAvailable('card.png');
    case PaymentMethodIds.paypal:
      return _logoAssetIfAvailable('paypal.png');
    case PaymentMethodIds.googlePay:
      return _logoAssetIfAvailable('google_pay.png');
    case PaymentMethodIds.bankTransferBacs:
      return _logoAssetIfAvailable('bank_transfer.png');
    case PaymentMethodIds.ideal:
      return _logoAssetIfAvailable('ideal.png');
    case PaymentMethodIds.cartesBancaires:
      return _logoAssetIfAvailable('carte_bancaire.png');
    case PaymentMethodIds.bizum:
      return _logoAssetIfAvailable('bizum.png');
    default:
      return null;
  }
}

/// Material icon fallback for payment methods without an official logo asset.
IconData paymentMethodFallbackIconForId(String methodId) {
  final id = normalizePaymentMethodId(methodId);
  if (id == PaymentMethodIds.inVehicleCard) {
    return Icons.local_taxi_rounded;
  }
  if (id == PaymentMethodIds.qrCode) {
    return Icons.qr_code_2_rounded;
  }
  if (id == PaymentMethodIds.payconiqWero) {
    return Icons.schedule_rounded;
  }
  if (id == PaymentMethodIds.bancontactQr) {
    return Icons.qr_code_2_rounded;
  }
  if (id == PaymentMethodIds.kbcCbc || id == PaymentMethodIds.belfius) {
    return Icons.account_balance_rounded;
  }
  return Icons.language_rounded;
}

/// Renders an official payment logo on a near-white plate, or a fallback icon.
Widget buildPaymentMethodLogo({
  required String methodId,
  Color? fallbackIconColor,
  double plateWidth = 44,
  double plateHeight = 32,
  double? imageMaxWidth,
  double? imageMaxHeight,
  double fallbackIconSize = 18,
  double plateBorderRadius = 6,
  EdgeInsets platePadding = const EdgeInsets.symmetric(
    horizontal: 4,
    vertical: 3,
  ),
}) {
  final assetPath = paymentMethodLogoAssetForId(methodId);
  if (assetPath == null) {
    return Icon(
      paymentMethodFallbackIconForId(methodId),
      color: fallbackIconColor,
      size: fallbackIconSize,
    );
  }

  Widget logoImage = Image.asset(
    assetPath,
    fit: BoxFit.contain,
    errorBuilder: (_, __, ___) => Icon(
      paymentMethodFallbackIconForId(methodId),
      color: fallbackIconColor,
      size: fallbackIconSize,
    ),
  );
  if (imageMaxWidth != null || imageMaxHeight != null) {
    logoImage = SizedBox(
      width: imageMaxWidth,
      height: imageMaxHeight,
      child: logoImage,
    );
  }

  return SizedBox(
    width: plateWidth,
    height: plateHeight,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(plateBorderRadius),
        border: Border.all(color: const Color(0xFFE8E8E8), width: 0.8),
      ),
      child: Padding(
        padding: platePadding,
        child: Center(child: logoImage),
      ),
    ),
  );
}

/// Whether [methodIds] includes at least one Mollie online checkout method.
bool shouldShowPaymentsByMollieBadge(Iterable<String> methodIds) {
  for (final raw in methodIds) {
    if (PaymentMethodCatalog.isMollieMethod(raw)) return true;
  }
  return false;
}

/// Index of the last Mollie checkout method in [methodIds], or null when none.
int? lastMollieCheckoutMethodIndex(List<String> methodIds) {
  int? lastIndex;
  for (var i = 0; i < methodIds.length; i++) {
    if (PaymentMethodCatalog.isMollieMethod(methodIds[i])) {
      lastIndex = i;
    }
  }
  return lastIndex;
}

String mollieProviderLogoAsset({required bool isDarkSurface}) {
  return isDarkSurface
      ? '$_providersDir/mollie_logo_white.png'
      : '$_providersDir/mollie_logo_black.png';
}

String paymentsByMollieBadgeAsset({required bool isDarkSurface}) {
  return isDarkSurface
      ? '$_badgesDir/payments_by_mollie_dark.png'
      : '$_badgesDir/payments_by_mollie_light.png';
}

/// Small Mollie wordmark for account/connect surfaces.
Widget buildMollieProviderLogo({
  required bool isDarkSurface,
  double height = 16,
  double? width,
}) {
  return Image.asset(
    mollieProviderLogoAsset(isDarkSurface: isDarkSurface),
    height: height,
    width: width,
    fit: BoxFit.contain,
    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
  );
}

/// Subtle “Payments by Mollie” trust badge for online payment sections.
Widget buildPaymentsByMollieTrustBadge({
  required bool isDarkSurface,
  double height = 18,
  double? width,
  Alignment alignment = Alignment.centerLeft,
}) {
  return Align(
    alignment: alignment,
    child: Opacity(
      opacity: isDarkSurface ? 0.96 : 0.88,
      child: Image.asset(
        paymentsByMollieBadgeAsset(isDarkSurface: isDarkSurface),
        height: height,
        width: width,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    ),
  );
}
