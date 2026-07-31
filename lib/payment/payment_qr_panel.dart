import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:url_launcher/url_launcher.dart';

/// Customer-facing Belgian QR payment panel (Payconiq / Bancontact Pay QR).
class PaymentQrPanel extends StatelessWidget {
  const PaymentQrPanel({
    super.key,
    required this.language,
    required this.qrSrc,
    this.checkoutUrl,
    this.onOpenCheckout,
  });

  final AppLanguage language;
  final String qrSrc;
  final String? checkoutUrl;
  final VoidCallback? onOpenCheckout;

  static String titleFor(AppLanguage language) => switch (language) {
    AppLanguage.en => 'Scan and pay',
    AppLanguage.fr => 'Scanner et payer',
    AppLanguage.es => 'Escanear y pagar',
    AppLanguage.nl => 'Scan en betaal',
    AppLanguage.de => 'Scan and pay',
  };

  static String subtitleFor(AppLanguage language) => switch (language) {
    AppLanguage.en => 'Open Bancontact Pay, Payconiq by Bancontact, or your Belgian banking app and scan this QR code.',
    AppLanguage.fr =>
      'Ouvrez Bancontact Pay, Payconiq by Bancontact ou votre application bancaire belge et scannez ce QR code.',
    AppLanguage.es =>
      'Abre Bancontact Pay, Payconiq by Bancontact o tu app bancaria belga y escanea este código QR.',
    AppLanguage.nl =>
      'Open Bancontact Pay, Payconiq by Bancontact of je bank-app en scan deze QR-code.',
    AppLanguage.de =>
      'Open Bancontact Pay, Payconiq by Bancontact, or your Belgian banking app and scan this QR code.',
  };

  static String fallbackButtonLabelFor(AppLanguage language) =>
      switch (language) {
        AppLanguage.en => 'Open payment page',
        AppLanguage.fr => 'Ouvrir la page de paiement',
        AppLanguage.es => 'Abrir página de pago',
        AppLanguage.nl => 'Open betaalpagina',
        AppLanguage.de => 'Open payment page',
      };

  Widget? _buildQrImage(String src) {
    final trimmed = src.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('https://') || trimmed.startsWith('http://')) {
      return Image.network(
        trimmed,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    if (trimmed.startsWith('data:image/')) {
      final comma = trimmed.indexOf(',');
      if (comma < 0) return null;
      try {
        final bytes = base64Decode(trimmed.substring(comma + 1));
        if (bytes.isEmpty) return null;
        return Image.memory(bytes, fit: BoxFit.contain);
      } catch (_) {
        // TODO(P2D): data URI QR rendering failed — caller should fall back to checkoutUrl.
        return null;
      }
    }

    return null;
  }

  Future<void> _openCheckout(BuildContext context) async {
    if (onOpenCheckout != null) {
      onOpenCheckout!();
      return;
    }
    final url = checkoutUrl?.trim() ?? '';
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final qrImage = _buildQrImage(qrSrc);
    final hasCheckout = (checkoutUrl?.trim().isNotEmpty ?? false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          titleFor(language),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          subtitleFor(language),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (qrImage != null) ...[
          const SizedBox(height: 16),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240, maxHeight: 240),
              child: qrImage,
            ),
          ),
        ],
        if (hasCheckout) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => _openCheckout(context),
            child: Text(fallbackButtonLabelFor(language)),
          ),
        ],
      ],
    );
  }
}
