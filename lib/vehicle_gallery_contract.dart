// Shared vehicle gallery capacity and public URL ordering.
// Applies to every vehicle editor. Public projections emit HTTPS only.

const int kVehicleGalleryMaxPhotos = 10;
const int kVehicleGalleryRecommendedPhotos = 5;

/// Ordered public gallery: primary first, no duplicates, HTTPS only, max 10.
List<String> orderPublicVehicleGalleryUrls({
  required String primaryUrl,
  Iterable<String> galleryUrls = const <String>[],
  int max = kVehicleGalleryMaxPhotos,
}) {
  final out = <String>[];
  final seen = <String>{};
  void add(String raw) {
    final url = raw.trim();
    if (!url.toLowerCase().startsWith('https://')) return;
    if (!seen.add(url)) return;
    if (out.length >= max) return;
    out.add(url);
  }

  add(primaryUrl);
  for (final url in galleryUrls) {
    add(url);
  }
  return List<String>.from(out, growable: false);
}

String vehicleGalleryProgressLabel({
  required int count,
  required String languageCode,
  int recommended = kVehicleGalleryRecommendedPhotos,
  int max = kVehicleGalleryMaxPhotos,
}) {
  switch (languageCode) {
    case 'en':
      return '$count of $recommended recommended photos · maximum $max';
    case 'fr':
      return '$count sur $recommended photos recommandées · maximum $max';
    case 'es':
      return '$count de $recommended fotos recomendadas · máximo $max';
    default:
      return '$count van $recommended aanbevolen foto’s · maximaal $max';
  }
}

String vehicleGalleryGuidanceLabel(String languageCode) {
  switch (languageCode) {
    case 'en':
      return 'Recommended: exterior, second angle, interior, seats, atmosphere.';
    case 'fr':
      return 'Recommandé : extérieur, second angle, intérieur, sièges, ambiance.';
    case 'es':
      return 'Recomendado: exterior, segundo ángulo, interior, asientos, ambiente.';
    default:
      return 'Aanbevolen: buitenkant, tweede hoek, interieur, zitplaatsen, sfeer.';
  }
}
