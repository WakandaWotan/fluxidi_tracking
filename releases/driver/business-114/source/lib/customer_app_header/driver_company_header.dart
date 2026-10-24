import 'package:flutter/material.dart';

import 'package:fluxidi_tracking/app_config.dart';

import 'customer_app_header_branding.dart';
import 'customer_app_header_view.dart';

/// Company header on the driver home only when this session's company opted in.
bool driverHomeUsesCompanyHeader({
  required bool enabled,
  required String sessionCompanyId,
  required String activeCompanyId,
}) {
  if (!enabled) return false;
  final session = sessionCompanyId.trim();
  final active = activeCompanyId.trim();
  if (session.isEmpty || active.isEmpty) return false;
  return session == active;
}

/// Device company settings may belong to a different company after QR login.
/// An empty name deliberately selects the packaged Fluxidi header fallback.
String driverHomeCompanyName({
  required String sessionCompanyId,
  required String deviceCompanyId,
  required String deviceCompanyName,
  required String profileCompanyId,
  required String profileCompanyName,
}) {
  final owner = sessionCompanyId.trim();
  if (owner.isEmpty) return '';
  if (profileCompanyId.trim() == owner && profileCompanyName.trim().isNotEmpty) {
    return profileCompanyName.trim();
  }
  return deviceCompanyId.trim() == owner ? deviceCompanyName.trim() : '';
}

CustomerAppHeaderBranding customerAppHeaderBrandingFromBusinessProfile(
  BackendBusinessProfile profile,
) {
  return CustomerAppHeaderBranding.fromJson(<String, dynamic>{
    'customer_app_header_mode': profile.customerAppHeaderMode,
    'customer_app_header_logo_position': profile.customerAppHeaderLogoPosition,
    'customer_app_header_media_revision': profile.customerAppHeaderMediaRevision,
    'public_logo_url': profile.publicLogoUrl,
    'public_hero_photo_url': profile.publicHeroPhotoUrl,
    'company_name': profile.companyName,
    'driver_app_use_company_header': profile.driverAppUseCompanyHeader,
    'business_app_use_company_header': profile.businessAppUseCompanyHeader,
  });
}

/// Same company images as the customer app. Controls stay above the banner.
class DriverCompanyHeader extends StatefulWidget {
  const DriverCompanyHeader({
    super.key,
    required this.branding,
    required this.trailing,
  });

  final CustomerAppHeaderBranding branding;
  final Widget trailing;

  @override
  State<DriverCompanyHeader> createState() => _DriverCompanyHeaderState();
}

class _DriverCompanyHeaderState extends State<DriverCompanyHeader> {
  bool _coverFailed = false;
  bool _logoFailed = false;

  @override
  void didUpdateWidget(covariant DriverCompanyHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branding.logoUrl != widget.branding.logoUrl ||
        oldWidget.branding.mediaRevision != widget.branding.mediaRevision) {
      _logoFailed = false;
    }
    if (oldWidget.branding.coverUrl != widget.branding.coverUrl ||
        oldWidget.branding.mediaRevision != widget.branding.mediaRevision) {
      _coverFailed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final branding = widget.branding.copyWith(
      coverUrl: _coverFailed ? '' : null,
      logoUrl: _logoFailed ? '' : null,
    );
    return CustomerAppHeaderView(
      key: const Key('driver_company_header'),
      branding: branding,
      trailing: widget.trailing,
      gold: const Color(0xFFE5B641),
      surface: const Color(0xFF111111),
      background: const Color(0xFF090909),
      textPrimary: Colors.white,
      onCoverFailed: () {
        if (_coverFailed) return;
        setState(() => _coverFailed = true);
      },
      onLogoFailed: () {
        if (_logoFailed) return;
        setState(() => _logoFailed = true);
      },
    );
  }
}
