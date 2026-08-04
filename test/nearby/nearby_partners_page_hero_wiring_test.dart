import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Taxi Nearby partner card uses shared contain hero media (no cover crop)', () {
    final page = File('lib/nearby_partners_page.dart').readAsStringSync();
    final media = File('lib/nearby/nearby_partner_hero_media.dart').readAsStringSync();

    expect(page.contains("import 'nearby/nearby_partner_hero_media.dart';"), isTrue);
    expect(page.contains('NearbyPartnerHeroMedia('), isTrue);
    expect(page.contains('nearbyPartnerHeroMediaHeight('), isTrue);

    // Hero strip must not reintroduce aggressive cover crop.
    expect(media.contains('BoxFit.contain'), isTrue);
    expect(
      RegExp(r'Image\([\s\S]*?fit:\s*BoxFit\.contain').hasMatch(media),
      isTrue,
    );

    // Legacy fixed 90 + cover must not remain on the partner card hero path.
    expect(page.contains('height: 90'), isFalse);
    expect(
      page.contains('fit: BoxFit.cover'),
      isFalse,
      reason: 'partner card hero/logo strip should not use BoxFit.cover',
    );
  });
}
