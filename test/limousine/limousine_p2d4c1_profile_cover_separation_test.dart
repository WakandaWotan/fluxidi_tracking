import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery.dart';
import 'package:fluxidi_tracking/limousine/limousine_hero_contract.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/nearby/public_partner_market.dart';

const String _kTaxiTesla =
    'https://cdn.example/public/media/public-media/t1/c1/company/hero.jpg?v=111';
const String _kTaxiTeslaLater =
    'https://cdn.example/public/media/public-media/t1/c1/company/hero.jpg?v=999';
const String _kLimousineHummer =
    'https://cdn.example/public/media/public-media/t1/c1/limousine/profile-cover.jpg?v=222';
const String _kVehicleGallery =
    'https://cdn.example/public/media/public-media/t1/c1/vehicles/vh_hummer/photo.jpg';

Map<String, dynamic> _cover(String url) => <String, dynamic>{
  'photo_url': url,
  'source_kind': 'upload',
  'vehicle_id': '',
  'alignment': 'center',
  'source_revision': 1,
};

Map<String, dynamic> _taxiDraft({String hero = _kTaxiTesla}) {
  return <String, dynamic>{
    'companyName': 'Maison',
    'publicHeroPhotoUrl': hero,
    'public_hero_photo_url': hero,
    'tagline': 'Taxi tagline',
    'about_short': 'Taxi about',
  };
}

Map<String, dynamic> _taxiPublished({String hero = _kTaxiTesla}) {
  return <String, dynamic>{
    'partner_id': 'mix_1',
    'company_name': 'Maison',
    'tagline': 'Taxi tagline',
    'about_short': 'Taxi about',
    'publicHeroPhotoUrl': hero,
    'media': taxiPublishedPartnerMedia(heroUrl: hero, logoUrl: 'https://cdn.example/logo.png'),
    'hero_photo_url': hero,
    'vehicles': <Map<String, dynamic>>[
      <String, dynamic>{
        'vehicle_id': 'taxi_1',
        'service_category': 'taxi_vvb',
        'photo_url': 'https://cdn.example/taxi-van.jpg',
        'gallery_photo_urls': <String>['https://cdn.example/taxi-van.jpg'],
      },
    ],
  };
}

Map<String, dynamic> _limousineSection({
  required Map<String, dynamic> working,
  required Map<String, dynamic> published,
  Map<String, String> title = const <String, String>{'nl': 'Limousines Maison'},
  Map<String, String> description = const <String, String>{
    'nl': 'Voor elke gelegenheid',
  },
}) {
  return limousinePublicDisplayPayload(
    publish: false,
    title: title,
    description: description,
    hero: working,
    publishedTitle: title,
    publishedDescription: description,
    publishedHero: published,
    taxiHeroUrls: <String>[_kTaxiTesla, _kTaxiTeslaLater],
  );
}

Map<String, dynamic> _publicPartner({
  required Map<String, dynamic> taxi,
  required Map<String, dynamic> limousine,
}) {
  return <String, dynamic>{
    ...taxi,
    'limousine': limousine,
    ...limousine,
    'limousine_vehicles': <Map<String, dynamic>>[
      <String, dynamic>{
        'vehicle_id': 'vh_hummer',
        'service_category': 'limousine',
        'service_class_id': 'hummer',
        'photo_url': _kVehicleGallery,
        'gallery_photo_urls': <String>[_kVehicleGallery],
      },
    ],
  };
}

void main() {
  test('1 taxi Tesla and limousine Hummer stay on separate objects', () {
    expect(limousineUrlLooksLikeTaxiCompanyHero(_kTaxiTesla), isTrue);
    expect(limousineUrlLooksLikeTaxiCompanyHero(_kLimousineHummer), isFalse);
    expect(limousineSamePublicMediaObject(_kTaxiTesla, _kTaxiTeslaLater), isTrue);
    expect(
      limousineSamePublicMediaObject(_kTaxiTesla, _kLimousineHummer),
      isFalse,
    );
    final payload = _limousineSection(
      working: _cover(_kLimousineHummer),
      published: _cover(_kLimousineHummer),
    );
    expect(payload[kLimousineProfileCoverKey], _cover(_kLimousineHummer));
    expect(payload['publicHeroPhotoUrl'], isNull);
    expect(payload['hero_photo_url'], isNull);
  });

  test('2 changing limousine cover does not mutate taxi draft', () {
    final taxi = _taxiDraft();
    final pricing = <String, dynamic>{'limousine': <String, dynamic>{}};
    final nextPricing = limousineReplacePricingSection(
      pricingDocument: pricing,
      limousineSection: _limousineSection(
        working: _cover(_kLimousineHummer),
        published: const <String, dynamic>{},
      ),
    );
    expect(taxi['publicHeroPhotoUrl'], _kTaxiTesla);
    expect(nextPricing.containsKey('publicHeroPhotoUrl'), isFalse);
    expect(
      (nextPricing['limousine'] as Map)[kLimousineProfileCoverKey],
      _cover(_kLimousineHummer),
    );
  });

  test('3 saving a limousine draft does not mutate taxi draft', () {
    var taxi = _taxiDraft();
    var pricing = <String, dynamic>{'currency': 'EUR'};
    final draft = limousinePublicDisplayPayload(
      publish: false,
      title: const <String, String>{'nl': 'Draft title'},
      description: const <String, String>{'nl': 'Draft text'},
      hero: _cover(_kLimousineHummer),
      publishedTitle: const <String, String>{'nl': 'Live'},
      publishedDescription: const <String, String>{'nl': 'Live text'},
      publishedHero: _cover('https://cdn.example/old-limo.jpg'),
      taxiHeroUrls: <String>[taxi['publicHeroPhotoUrl'] as String],
    );
    pricing = limousineReplacePricingSection(
      pricingDocument: pricing,
      limousineSection: draft,
    );
    expect(taxi['publicHeroPhotoUrl'], _kTaxiTesla);
    expect(draft['published_limousine_profile_cover'], isNot(draft[kLimousineProfileCoverKey]));
    expect((pricing['limousine'] as Map)['public_title'], <String, String>{
      'nl': 'Draft title',
    });
  });

  test('4 publishing limousine does not mutate published taxi profile', () {
    final taxiPublished = _taxiPublished();
    final published = limousinePublicDisplayPayload(
      publish: true,
      title: const <String, String>{'nl': 'Limousines Maison'},
      description: const <String, String>{'nl': 'Hummer night'},
      hero: _cover(_kLimousineHummer),
      publishedTitle: const <String, String>{'nl': 'Old'},
      publishedDescription: const <String, String>{'nl': 'Old text'},
      publishedHero: const <String, dynamic>{},
      taxiHeroUrls: <String>[_kTaxiTesla],
    );
    expect(taxiPublished['publicHeroPhotoUrl'], _kTaxiTesla);
    expect(
      (taxiPublished['media'] as Map)['hero_photo_url'],
      _kTaxiTesla,
    );
    expect(published[kLimousinePublishedProfileCoverKey], _cover(_kLimousineHummer));
    expect(published.containsKey('publicHeroPhotoUrl'), isFalse);
    expect(published.containsKey('hero_photo_url'), isFalse);
  });

  test('5 changing taxi hero does not mutate limousine concept', () {
    final limousine = _limousineSection(
      working: _cover(_kLimousineHummer),
      published: _cover(_kLimousineHummer),
    );
    final taxi = taxiReplaceBusinessHero(
      businessProfile: _taxiDraft(),
      heroUrl: _kTaxiTeslaLater,
    );
    expect(taxi['publicHeroPhotoUrl'], _kTaxiTeslaLater);
    expect(limousine[kLimousineProfileCoverKey], _cover(_kLimousineHummer));
    expect(taxi.containsKey(kLimousineProfileCoverKey), isFalse);
    expect(taxi.containsKey('limousine_hero'), isFalse);
  });

  test('6 publishing taxi does not mutate published limousine profile', () {
    final limousine = _limousineSection(
      working: _cover(_kLimousineHummer),
      published: _cover(_kLimousineHummer),
    );
    final taxiMedia = taxiPublishedPartnerMedia(heroUrl: _kTaxiTeslaLater);
    expect(taxiMedia['hero_photo_url'], _kTaxiTeslaLater);
    expect(limousine[kLimousinePublishedProfileCoverKey], _cover(_kLimousineHummer));
    expect(taxiMedia.containsKey(kLimousinePublishedProfileCoverKey), isFalse);
  });

  test('7 taxi partner profile shows only the red Tesla', () {
    final partner = _publicPartner(
      taxi: _taxiPublished(),
      limousine: _limousineSection(
        working: _cover(_kLimousineHummer),
        published: _cover(_kLimousineHummer),
      ),
    );
    final catalog = selectPublicPartnerMarketCatalog(
      profile: partner,
      market: PublicPartnerMarket.taxi,
    );
    expect(catalog.heroPhotoUrl, _kTaxiTesla);
    expect(catalog.heroPhotoUrl.contains('profile-cover'), isFalse);
    expect(catalog.heroPhotoUrl.contains('hummer'), isFalse);
  });

  test('8 limousine profile shows only the Hummer', () {
    final partner = _publicPartner(
      taxi: _taxiPublished(),
      limousine: _limousineSection(
        working: _cover(_kLimousineHummer),
        published: _cover(_kLimousineHummer),
      ),
    );
    final catalog = selectPublicPartnerMarketCatalog(
      profile: partner,
      market: PublicPartnerMarket.limousine,
    );
    final cover = limousineDiscoveryPublishedCover(partner);
    final showroom = buildLimousineProviderShowroomData(profile: partner);
    expect(catalog.heroPhotoUrl, _kLimousineHummer);
    expect(cover.photoUrl, _kLimousineHummer);
    expect(showroom.heroPhotoUrl, _kLimousineHummer);
    expect(catalog.heroPhotoUrl.contains('/company/hero'), isFalse);
    expect(showroom.heroPhotoUrl.contains('Tesla'), isFalse);
  });

  test('9 reopening the app keeps both photos on their own channel', () {
    final taxi = _taxiDraft();
    final limousine = _limousineSection(
      working: _cover(_kLimousineHummer),
      published: _cover(_kLimousineHummer),
    );
    final encoded = jsonEncode(<String, dynamic>{
      'taxi': taxi,
      'limousine': limousine,
    });
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    final taxiReloaded = Map<String, dynamic>.from(decoded['taxi'] as Map);
    final limoReloaded = Map<String, dynamic>.from(decoded['limousine'] as Map);
    expect(taxiReloaded['publicHeroPhotoUrl'], _kTaxiTesla);
    expect(
      limousineHeroFromSection(limoReloaded).photoUrl,
      _kLimousineHummer,
    );
    expect(
      limousineSanitizeProfileCoverUrl(
        (limoReloaded[kLimousineProfileCoverKey] as Map)['photo_url'] as String,
        taxiHeroUrls: <String>[taxiReloaded['publicHeroPhotoUrl'] as String],
      ),
      _kLimousineHummer,
    );
  });

  test('10 old payload without limousine_profile_cover stays compatible', () {
    final uniqueLegacy = <String, dynamic>{
      'limousine_hero': _cover('https://cdn.example/legacy-limo.jpg'),
      'published_limousine_hero': _cover('https://cdn.example/legacy-limo.jpg'),
      'hero_photo_url': _kTaxiTesla,
      'publicHeroPhotoUrl': _kTaxiTesla,
    };
    expect(
      limousineHeroFromSection(uniqueLegacy).photoUrl,
      'https://cdn.example/legacy-limo.jpg',
    );
    expect(limousineCollectTaxiHeroUrls(uniqueLegacy), contains(_kTaxiTesla));
    final sharedLegacy = <String, dynamic>{
      'limousine_hero': _cover(_kTaxiTesla),
      'published_limousine_hero': _cover(_kTaxiTesla),
      'publicHeroPhotoUrl': _kTaxiTesla,
    };
    expect(limousineHeroFromSection(sharedLegacy).photoUrl, isEmpty);
    expect(publicPartnerTaxiHeroUrl(sharedLegacy), _kTaxiTesla);
  });

  test('11 missing limousine cover does not overwrite or mutate taxi hero', () {
    final taxi = _taxiDraft();
    final empty = limousinePublicDisplayPayload(
      publish: true,
      title: const <String, String>{'nl': 'Maison'},
      description: const <String, String>{'nl': 'Tekst'},
      hero: const <String, dynamic>{},
      publishedTitle: const <String, String>{'nl': 'Maison'},
      publishedDescription: const <String, String>{'nl': 'Tekst'},
      publishedHero: const <String, dynamic>{},
      taxiHeroUrls: <String>[_kTaxiTesla],
    );
    expect(taxi['publicHeroPhotoUrl'], _kTaxiTesla);
    expect(
      ((empty[kLimousineProfileCoverKey] as Map)['photo_url'] ?? '').toString(),
      isEmpty,
    );
    expect(empty['publicHeroPhotoUrl'], isNull);
    final partner = _publicPartner(taxi: _taxiPublished(), limousine: empty);
    expect(
      selectPublicPartnerMarketCatalog(
        profile: partner,
        market: PublicPartnerMarket.taxi,
      ).heroPhotoUrl,
      _kTaxiTesla,
    );
    expect(limousineDiscoveryPublishedCover(partner).photoUrl, isEmpty);
  });

  test('12 vehicle galleries stay unchanged when covers are saved', () {
    final vehicles = <Map<String, dynamic>>[
      <String, dynamic>{
        'vehicle_id': 'vh_hummer',
        'gallery_photo_urls': <String>[_kVehicleGallery],
        'photo_url': _kVehicleGallery,
      },
    ];
    final before = jsonEncode(vehicles);
    limousinePublicDisplayPayload(
      publish: true,
      title: const <String, String>{'nl': 'Maison'},
      description: const <String, String>{'nl': 'Tekst'},
      hero: _cover(_kLimousineHummer),
      publishedTitle: const <String, String>{'nl': 'Maison'},
      publishedDescription: const <String, String>{'nl': 'Tekst'},
      publishedHero: _cover(_kLimousineHummer),
      taxiHeroUrls: <String>[_kTaxiTesla],
    );
    taxiReplaceBusinessHero(businessProfile: _taxiDraft(), heroUrl: _kTaxiTeslaLater);
    expect(jsonEncode(vehicles), before);
    expect(vehicles.single['gallery_photo_urls'], <String>[_kVehicleGallery]);
  });

  test('title and description already use separate limousine keys', () {
    final payload = limousinePublicDisplayPayload(
      publish: true,
      title: const <String, String>{'nl': 'Limousines Maison'},
      description: const <String, String>{'nl': 'Hummer night'},
      hero: _cover(_kLimousineHummer),
      publishedTitle: const <String, String>{},
      publishedDescription: const <String, String>{},
      publishedHero: const <String, dynamic>{},
    );
    expect(payload['public_title'], <String, String>{'nl': 'Limousines Maison'});
    expect(payload['public_description'], <String, String>{'nl': 'Hummer night'});
    expect(payload.containsKey('about_short'), isFalse);
    expect(payload.containsKey('tagline'), isFalse);
    final taxi = taxiReplaceBusinessHero(
      businessProfile: _taxiDraft(),
      heroUrl: _kTaxiTesla,
    );
    expect(taxi['tagline'], 'Taxi tagline');
    expect(taxi['about_short'], 'Taxi about');
    expect(taxi.containsKey('public_title'), isFalse);
    expect(taxi.containsKey('published_public_title'), isFalse);
  });

  test('shared company/hero object is kept as taxi and stripped from limousine', () {
    final shared = limousinePublicDisplayPayload(
      publish: true,
      title: const <String, String>{'nl': 'Maison'},
      description: const <String, String>{'nl': 'Tekst'},
      hero: _cover(_kTaxiTesla),
      publishedTitle: const <String, String>{'nl': 'Maison'},
      publishedDescription: const <String, String>{'nl': 'Tekst'},
      publishedHero: _cover(_kTaxiTesla),
      taxiHeroUrls: <String>[_kTaxiTeslaLater],
    );
    expect((shared[kLimousineProfileCoverKey] as Map)['photo_url'], isEmpty);
    expect((shared['limousine_hero'] as Map)['photo_url'], isEmpty);
    expect(publicPartnerTaxiHeroUrl(_taxiPublished()), _kTaxiTesla);
  });

  test('setup upload uses a dedicated media type, not company_hero', () {
    final setup = File(
      'lib/limousine/limousine_business_setup_page.dart',
    ).readAsStringSync();
    expect(setup.contains('kLimousineProfileCoverMediaType'), isTrue);
    expect(
      setup.contains("mediaType: 'company_hero'"),
      isFalse,
    );
    final taxiSettings = File('lib/business_settings_page.dart').readAsStringSync();
    expect(taxiSettings.contains("mediaType: 'company_hero'"), isTrue);
    final worker = File(
      'workers/booking/fluxidi_booking_worker.js',
    ).readAsStringSync();
    expect(worker.contains('limousine_profile_cover'), isTrue);
    expect(worker.contains('limousine/profile-cover.'), isTrue);
    expect(setup.contains('kLimousineProfileLogoMediaType'), isTrue);
    expect(setup.contains("mediaType: 'company_logo'"), isFalse);
    expect(worker.contains('limousine_profile_logo'), isTrue);
    expect(worker.contains('limousine/profile-logo.'), isTrue);
  });
}
