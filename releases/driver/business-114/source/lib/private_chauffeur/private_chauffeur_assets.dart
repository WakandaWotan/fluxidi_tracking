/// Artwork from fluxidi_prive_chauffeur_assets. The photos have no type,
/// so the service card draws the title, icon and scrim itself.
const String kPrivateChauffeurBannerMobile =
    'assets/fluxidi/fluxidi_prive_chauffeur_mobile.png';
const String kPrivateChauffeurBannerTablet =
    'assets/fluxidi/fluxidi_prive_chauffeur_tablet.png';
const String kPrivateChauffeurBannerDesktop =
    'assets/fluxidi/fluxidi_prive_chauffeur_desktop.png';

/// Phone, tablet, then a wide window. Matches the supplied files.
String privateChauffeurBannerAsset({
  required double width,
  required double shortestSide,
}) {
  if (width >= 1100) return kPrivateChauffeurBannerDesktop;
  if (shortestSide >= 600) return kPrivateChauffeurBannerTablet;
  return kPrivateChauffeurBannerMobile;
}
