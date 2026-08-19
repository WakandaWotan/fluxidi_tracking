import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/vehicle_gallery_contract.dart';

Uint8List _pngWithPayload(int marker) {
  return Uint8List.fromList(<int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    marker,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);
}

String _galleryKey(String vehicleId, String mediaId) {
  return 'public-media/tenant/company/vehicles/$vehicleId/gallery/$mediaId.png';
}

void main() {
  test('five distinct byte fixtures keep five hashes and five object keys', () {
    final ids = <String>[];
    final hashes = <String>{};
    final keys = <String>{};
    for (var i = 0; i < 5; i++) {
      final bytes = _pngWithPayload(i + 1);
      hashes.add(sha256.convert(bytes).toString());
      final mediaId = newVehicleGalleryMediaId();
      expect(ids.contains(mediaId), isFalse);
      ids.add(mediaId);
      final key = _galleryKey('vh_hummer', mediaId);
      expect(key.contains('/photo.png'), isFalse);
      expect(key.contains('/photo.jpg'), isFalse);
      expect(key.contains('/gallery/'), isTrue);
      keys.add(key);
    }
    expect(hashes.length, 5);
    expect(ids.toSet().length, 5);
    expect(keys.length, 5);
  });

  test('fresh GET-style hydrate keeps five distinct public URLs', () {
    final urls = <String>[
      for (var i = 0; i < 5; i++)
        'https://cdn.example/public-media/t/c/vehicles/vh_party/gallery/m$i.png?v=${100 + i}',
    ];
    final ordered = orderPublicVehicleGalleryUrls(
      primaryUrl: urls.first,
      galleryUrls: urls,
    );
    expect(ordered.length, 5);
    expect(ordered.map(publicMediaObjectIdentity).toSet().length, 5);
  });

  test('legacy photo.jpg?v= aliases collapse instead of cloning one object', () {
    final collapsed = orderPublicVehicleGalleryUrls(
      primaryUrl:
          'https://host/public/media/public-media/t/c/vehicles/vh_hummer/photo.jpg?v=1',
      galleryUrls: const <String>[
        'https://host/public/media/public-media/t/c/vehicles/vh_hummer/photo.jpg?v=2',
        'https://host/public/media/public-media/t/c/vehicles/vh_hummer/photo.jpg?v=3',
        'https://host/public/media/public-media/t/c/vehicles/vh_hummer/photo.jpg?v=4',
        'https://host/public/media/public-media/t/c/vehicles/vh_hummer/photo.jpg?v=5',
      ],
    );
    expect(collapsed.length, 1);
    expect(
      publicMediaObjectIdentity(collapsed.single).endsWith('/photo.jpg'),
      isTrue,
    );
  });

  test('choosing a primary URL does not drop other unique gallery objects', () {
    const primary =
        'https://cdn.example/public-media/t/c/vehicles/vh_party/gallery/a.png';
    const gallery = <String>[
      'https://cdn.example/public-media/t/c/vehicles/vh_party/gallery/a.png?v=9',
      'https://cdn.example/public-media/t/c/vehicles/vh_party/gallery/b.png',
      'https://cdn.example/public-media/t/c/vehicles/vh_party/gallery/c.png',
    ];
    final urls = orderPublicVehicleGalleryUrls(
      primaryUrl: primary,
      galleryUrls: gallery,
    );
    expect(urls.length, 3);
    expect(
      publicMediaObjectIdentity(urls.first),
      publicMediaObjectIdentity(primary),
    );
    expect(
      urls.map(publicMediaObjectIdentity).where((id) => id.endsWith('/b.png')),
      isNotEmpty,
    );
  });

  test(
    'republish contract keeps the full unique gallery under the existing max',
    () {
      final urls = orderPublicVehicleGalleryUrls(
        primaryUrl:
            'https://cdn.example/public-media/t/c/vehicles/vh_1/gallery/one.jpg',
        galleryUrls: const <String>[
          'https://cdn.example/public-media/t/c/vehicles/vh_1/gallery/two.jpg',
          'https://cdn.example/public-media/t/c/vehicles/vh_1/gallery/three.jpg',
          'https://cdn.example/public-media/t/c/vehicles/vh_1/gallery/four.jpg',
          'https://cdn.example/public-media/t/c/vehicles/vh_1/gallery/five.jpg',
        ],
      );
      expect(urls.length, 5);
      expect(urls.length, lessThanOrEqualTo(kVehicleGalleryMaxPhotos));
      expect(kVehicleGalleryMaxPhotos, 10);
    },
  );

  test('public gallery URLs never carry tenant, company or object-key fields', () {
    final urls = orderPublicVehicleGalleryUrls(
      primaryUrl:
          'https://cdn.example/public/media/public-media/t/c/vehicles/vh_1/gallery/m1.jpg',
      galleryUrls: const <String>[
        'https://cdn.example/public/media/public-media/t/c/vehicles/vh_1/gallery/m2.jpg',
      ],
    );
    final encoded = jsonEncode(urls);
    expect(encoded.contains('tenant_id'), isFalse);
    expect(encoded.contains('company_id'), isFalse);
    expect(encoded.contains('object_key'), isFalse);
    expect(encoded.contains('r2_key'), isFalse);
  });

  test('transaction compile gates stay off so CTAs cannot POST', () {
    expect(kLimousineCustomerQuoteGateEnabled, isFalse);
    expect(kLimousineCustomerManualQuoteGateEnabled, isFalse);
    expect(kLimousineCustomerBookGateEnabled, isFalse);
    expect(limousineCustomerQuoteCtaEnabled(), isFalse);
    expect(limousineCustomerBookCtaEnabled(), isFalse);
  });
}
