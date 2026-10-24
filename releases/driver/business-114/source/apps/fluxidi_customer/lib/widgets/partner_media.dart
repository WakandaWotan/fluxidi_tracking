import 'package:flutter/material.dart';

import '../app/customer_app_config.dart';

/// Partner hero or logo image with a neutral fallback.
///
/// Only renders a remote image when the server supplied a usable https URL;
/// a broken or missing image falls back instead of showing an error box.
class PartnerMedia extends StatelessWidget {
  const PartnerMedia({
    super.key,
    required this.heroUrl,
    required this.logoUrl,
    required this.height,
    this.config = kCustomerAppConfig,
  });

  final String heroUrl;
  final String logoUrl;
  final double height;
  final CustomerAppConfig config;

  @override
  Widget build(BuildContext context) {
    final url = heroUrl.isNotEmpty ? heroUrl : logoUrl;
    final fallback = _Fallback(height: height, config: config);
    if (url.isEmpty) return fallback;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Image.network(
        url,
        fit: heroUrl.isNotEmpty ? BoxFit.cover : BoxFit.contain,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.height, required this.config});

  final double height;
  final CustomerAppConfig config;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            config.brand.surface,
            config.brand.card,
            config.brand.primary.withValues(alpha: 0.18),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Icon(
        Icons.local_taxi_outlined,
        color: config.brand.primary.withValues(alpha: 0.9),
      ),
    );
  }
}
