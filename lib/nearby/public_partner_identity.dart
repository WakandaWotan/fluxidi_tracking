// White-label identity for public / customer-facing partner surfaces.
// Fluxidi is the platform, never a partner brand fallback.

import 'package:flutter/widgets.dart';

import '../branding/company_logo_ref.dart';

bool isPlatformBrandPublicName(String raw) {
  final name = raw.trim().toLowerCase();
  if (name.isEmpty) return false;
  return name == 'fluxidi' ||
      name == 'fluxidi platform' ||
      name == 'fluxidi partner' ||
      name == 'partenaire fluxidi' ||
      name == 'socio fluxidi';
}

String sanitizePublicPartnerBrandName(String raw) {
  final name = raw.trim();
  if (name.isEmpty || isPlatformBrandPublicName(name)) return '';
  return name;
}

bool publicPartnerLogoIsRenderable(String logoUrl) {
  final url = logoUrl.trim();
  if (url.isEmpty || isDefaultFluxidiLogoRef(url)) return false;
  return classifyCompanyLogoRef(url) == CompanyLogoRefKind.network &&
      url.startsWith('https://');
}

class PublicPartnerHeroIdentity {
  const PublicPartnerHeroIdentity({
    this.logoUrl = '',
    this.logoImage,
    this.nameFallback = '',
    this.description = '',
  });

  final String logoUrl;
  final ImageProvider? logoImage;
  final String nameFallback;
  final String description;

  bool get hasLogo =>
      logoImage != null || publicPartnerLogoIsRenderable(logoUrl);

  bool get showsLogo => hasLogo;

  bool get showsName => !hasLogo && nameFallback.isNotEmpty;
}

PublicPartnerHeroIdentity resolvePublicPartnerHeroIdentity({
  String logoUrl = '',
  ImageProvider? logoImage,
  String companyName = '',
  String description = '',
}) {
  final hasLogo = logoImage != null || publicPartnerLogoIsRenderable(logoUrl);
  return PublicPartnerHeroIdentity(
    logoUrl: hasLogo ? logoUrl.trim() : '',
    logoImage: logoImage,
    nameFallback: hasLogo ? '' : sanitizePublicPartnerBrandName(companyName),
    description: description.trim(),
  );
}
