// Shared vehicle gallery capacity and public URL ordering.
// Applies to every vehicle editor. Public projections emit HTTPS only.

import 'dart:math';

import 'package:flutter/foundation.dart';

const int kVehicleGalleryMaxPhotos = 10;
const int kVehicleGalleryRecommendedPhotos = 5;

/// Object-path identity: `?v=` / fragments do not create a second photo.
String publicMediaObjectIdentity(String raw) {
  var text = raw.trim();
  final hash = text.indexOf('#');
  if (hash >= 0) text = text.substring(0, hash);
  final query = text.indexOf('?');
  if (query >= 0) text = text.substring(0, query);
  return text;
}

/// Safe public label: `gallery/{mediaId}.ext` or `photo.ext`, never tenant/company.
String publicVehicleGallerySafeObjectLabel(String raw) {
  final identity = publicMediaObjectIdentity(raw);
  if (identity.isEmpty) return '';
  final gallery = identity.lastIndexOf('/gallery/');
  if (gallery >= 0 && gallery + 9 < identity.length) {
    return 'gallery/${identity.substring(gallery + 9)}';
  }
  final photo = identity.lastIndexOf('/photo.');
  if (photo >= 0) {
    return identity.substring(photo + 1);
  }
  final slash = identity.lastIndexOf('/');
  if (slash >= 0 && slash < identity.length - 1) {
    return identity.substring(slash + 1);
  }
  return identity;
}

List<String> publicVehicleGalleryEvidenceLabels(Iterable<String> urls) {
  final out = <String>[];
  final seen = <String>{};
  for (final raw in urls) {
    final label = publicVehicleGallerySafeObjectLabel(raw);
    if (label.isEmpty || !seen.add(label)) continue;
    out.add(label);
  }
  return List<String>.from(out, growable: false);
}

void logVehicleGalleryEvidence({
  required String stage,
  required String vehicleId,
  String mediaId = '',
  String bytesSha256 = '',
  Iterable<String> urls = const <String>[],
}) {
  final labels = publicVehicleGalleryEvidenceLabels(urls);
  final media = mediaId.trim();
  final hash = bytesSha256.trim();
  debugPrint(
    '[VEHICLE_GALLERY][$stage] vehicle=$vehicleId count=${labels.length}'
    '${media.isEmpty ? '' : ' media_id=$media'}'
    '${hash.isEmpty ? '' : ' bytes_sha256=$hash'}'
    ' objects=${labels.join(',')}',
  );
}

String newVehicleGalleryMediaId() {
  final random = Random.secure();
  final buffer = StringBuffer('m');
  buffer.write(DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36));
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  for (var i = 0; i < 10; i++) {
    buffer.write(alphabet[random.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}

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
    final identity = publicMediaObjectIdentity(url);
    if (identity.isEmpty || !seen.add(identity)) return;
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
