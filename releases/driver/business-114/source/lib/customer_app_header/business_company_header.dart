import 'package:flutter/material.dart';

import 'customer_app_header_branding.dart';
import 'customer_app_header_view.dart';

bool businessHomeUsesCompanyHeader({
  required bool enabled,
  required String profileCompanyId,
  required String activeCompanyId,
}) {
  final profile = profileCompanyId.trim();
  final active = activeCompanyId.trim();
  return enabled && profile.isNotEmpty && active.isNotEmpty && profile == active;
}

/// The company-owned dashboard header reuses the saved customer/driver media.
class BusinessCompanyHeader extends StatefulWidget {
  const BusinessCompanyHeader({
    super.key,
    required this.branding,
    required this.trailing,
    required this.accent,
    required this.surface,
    required this.background,
    required this.textPrimary,
  });

  final CustomerAppHeaderBranding branding;
  final Widget trailing;
  final Color accent;
  final Color surface;
  final Color background;
  final Color textPrimary;

  @override
  State<BusinessCompanyHeader> createState() => _BusinessCompanyHeaderState();
}

class _BusinessCompanyHeaderState extends State<BusinessCompanyHeader> {
  bool _coverFailed = false;
  bool _logoFailed = false;

  @override
  void didUpdateWidget(covariant BusinessCompanyHeader oldWidget) {
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
    return CustomerAppHeaderView(
      key: const Key('business_company_header'),
      branding: widget.branding.copyWith(
        coverUrl: _coverFailed ? '' : null,
        logoUrl: _logoFailed ? '' : null,
      ),
      trailing: widget.trailing,
      gold: widget.accent,
      surface: widget.surface,
      background: widget.background,
      textPrimary: widget.textPrimary,
      onCoverFailed: () {
        if (!_coverFailed) setState(() => _coverFailed = true);
      },
      onLogoFailed: () {
        if (!_logoFailed) setState(() => _logoFailed = true);
      },
    );
  }
}
