import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_profile_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_detail_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_persist.dart';
import 'package:fluxidi_tracking/partner_public_profile_page.dart';
import 'package:fluxidi_tracking/vehicle_gallery_contract.dart';

VehicleProfile _vehicle({
  required String id,
  required String name,
  String category = 'limousine',
  String classId = 'stretch_limousine',
  List<String> gallery = const <String>[],
  String photo = 'https://cdn.example/main.jpg',
}) {
  return VehicleProfile(
    id: id,
    vehicleName: name,
    brandModel: name,
    licensePlate: '1-ABC-123',
    color: 'white',
    passengerCapacity: 8,
    luggageCapacity: 4,
    tierId: 'premium',
    isActive: true,
    driverId: null,
    primaryPhotoRef: photo,
    galleryPhotoRefs: gallery,
    publicPhotoUrl: photo,
    serviceCategory: category,
    serviceClassId: classId,
  );
}

Map<String, dynamic> _publicVehicle({
  required String name,
  required List<String> photos,
}) {
  return <String, dynamic>{
    'name': name,
    'service_category': 'limousine',
    'service_class': 'stretch_limousine',
    'is_active': true,
    'pax': 8,
    'luggage': 4,
    'photo_url': photos.first,
    'primary_photo_url': photos.first,
    'gallery_photo_urls': photos,
  };
}

Widget _app(Widget child, {Size size = kLimousinePhonePortrait}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    appLanguageNotifier.value = AppLanguage.nl;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  test('selected vehicle ids survive save, dispose and bootstrap reload', () {
    final before = <VehicleProfile>[
      _vehicle(id: 'vh_party', name: 'Party Limo'),
      _vehicle(id: 'vh_hummer', name: 'Hummer white', classId: 'luxury_van'),
      _vehicle(id: 'vh_taxi', name: 'Taxi Van', category: '', classId: ''),
    ];
    expect(limousineSelectedVehicleIds(before), <String>[
      'vh_party',
      'vh_hummer',
    ]);
    final remoteBare = VehicleProfile(
      id: 'vh_party',
      vehicleName: 'Party Limo',
      brandModel: 'Party Limo',
      licensePlate: '1-ABC-123',
      color: 'white',
      passengerCapacity: 8,
      luggageCapacity: 4,
      tierId: 'premium',
      isActive: true,
      driverId: null,
      primaryPhotoRef: 'https://cdn.example/main.jpg',
      galleryPhotoRefs: const <String>[],
    );
    final mergedParty = mergeBootstrapVehicleClassification(
      remote: remoteBare,
      local: before.first,
    );
    final parsedHummer = parseLimousineVehicleClassification(<String, dynamic>{
      'service_category': 'limousine',
      'service_class': 'luxury_van',
    });
    final after = <VehicleProfile>[
      mergedParty,
      before[1].copyWith(
        serviceCategory: parsedHummer.serviceCategory,
        serviceClassId: parsedHummer.serviceClassId,
      ),
      before[2],
    ];
    expect(
      limousineSelectionSurvivesReload(before: before, after: after),
      isTrue,
    );
    expect(mergedParty.serviceCategory, 'limousine');
    expect(mergedParty.serviceClassId, 'stretch_limousine');
    expect(after[1].serviceClassId, 'luxury_van');
    final readiness = limousineBusinessSetupReadiness(
      vehicles: after,
      offers: <Map<String, dynamic>>[
        <String, dynamic>{
          'offer_id': 'off_1',
          'enabled': true,
          'published': true,
          'target_type': LimousineOfferTarget.serviceClass,
          'service_class_id': 'stretch_limousine',
          'price_presentation': LimousinePricePresentation.quoteRequired,
          'currency': 'EUR',
          'title': <String, String>{'nl': 'Avond'},
          'description': <String, String>{'nl': 'Avondrit'},
          'hourly': <String, dynamic>{'enabled': false, 'currency': 'EUR'},
          'distance_time': <String, dynamic>{
            'enabled': false,
            'currency': 'EUR',
          },
        },
      ],
      publicTitle: const <String, String>{'nl': 'Maison'},
      publicDescription: const <String, String>{'nl': 'Limousines'},
      knownClassIds: const <String>['stretch_limousine', 'luxury_van'],
      entryEnabled: true,
      sectionEnabled: true,
    );
    expect(readiness.progress, 1.0);
    expect(readiness.canPublish, isTrue);
    final restored = restoreLimousineSelectionFromIds(
      vehicles: <VehicleProfile>[
        remoteBare,
        before[1].copyWith(serviceCategory: '', serviceClassId: ''),
        before[2],
      ],
      selectedIds: parsePersistedLimousineVehicleIds(<String>[
        'vh_party',
        'vh_hummer',
      ]),
      fallbackClassId: 'stretch_limousine',
    );
    expect(limousineSelectedVehicleIds(restored), <String>[
      'vh_party',
      'vh_hummer',
    ]);
  });

  test('gallery order keeps one primary and never duplicates it', () {
    final urls = orderPublicVehicleGalleryUrls(
      primaryUrl: 'https://cdn.example/party-ext.jpg',
      galleryUrls: <String>[
        'https://cdn.example/party-ext.jpg',
        'https://cdn.example/party-int.jpg',
        'file:///tmp/local.jpg',
        'https://cdn.example/party-int.jpg',
      ],
    );
    expect(urls, <String>[
      'https://cdn.example/party-ext.jpg',
      'https://cdn.example/party-int.jpg',
    ]);
    expect(urls.length, lessThanOrEqualTo(kVehicleGalleryMaxPhotos));
    expect(kVehicleGalleryMaxPhotos, 10);
  });

  test('Party Limo two public photos become two parsed media items', () {
    final vehicle = tryParseLimousineShowroomVehicle(
      _publicVehicle(
        name: 'Party Limo',
        photos: const <String>[
          'https://cdn.example/party-ext.jpg',
          'https://cdn.example/party-int.jpg',
        ],
      ),
      index: 0,
    );
    expect(vehicle, isNotNull);
    expect(vehicle!.photoUrls, hasLength(2));
    expect(vehicle.primaryPhotoUrl, 'https://cdn.example/party-ext.jpg');
    expect(vehicle.photoUrls.last, 'https://cdn.example/party-int.jpg');
  });

  test('discovery and showroom covers use only the primary photo', () {
    final partner = <String, dynamic>{
      'partner_id': 'limo_1',
      'company_name': 'Maison Noire',
      'is_active': true,
      'profile_enabled': true,
      'limousine_available': true,
      'limousine_service_enabled': true,
      'public_city': 'Gent',
      'hero_photo_url': 'https://cdn.example/taxi-cover.jpg',
      'limousine_vehicles': <Map<String, dynamic>>[
        <String, dynamic>{
          'service_category': 'limousine',
          'service_class_id': 'stretch_limousine',
          'primary_photo_url': 'https://cdn.example/party-ext.jpg',
          'photo_url': 'https://cdn.example/party-ext.jpg',
          'gallery_photo_urls': <String>[
            'https://cdn.example/party-ext.jpg',
            'https://cdn.example/party-int.jpg',
          ],
          'passenger_capacity': 8,
        },
      ],
      'limousine_price_presentation': 'quote_required',
      'test_preview': true,
    };
    final card = tryParseLimousineDiscoveryCard(partner);
    expect(card?.coverImageUrl, isEmpty);
    expect(card?.coverIsPlaceholder, isTrue);
    expect(card?.coverImageUrl.contains('party-ext'), isFalse);
    expect(card?.coverImageUrl.contains('party-int'), isFalse);
    expect(card?.coverImageUrl.contains('taxi-cover'), isFalse);
    final showroom = buildLimousineProviderShowroomData(
      profile: <String, dynamic>{
        'partner_id': 'limo_1',
        'company_name': 'Maison Noire',
        'limousine_available': true,
        'hero_photo_url': 'https://cdn.example/taxi-cover.jpg',
        'vehicles': <Map<String, dynamic>>[
          _publicVehicle(
            name: 'Party Limo',
            photos: const <String>[
              'https://cdn.example/party-ext.jpg',
              'https://cdn.example/party-int.jpg',
            ],
          ),
          <String, dynamic>{
            'name': 'Taxi Van',
            'service_category': 'taxi',
            'photo_url': 'https://cdn.example/taxi-van.jpg',
            'is_active': true,
          },
        ],
      },
    );
    expect(showroom.heroPhotoUrl, isEmpty);
    expect(showroom.heroPhotoUrl.contains('party-ext'), isFalse);
    expect(showroom.vehicles, hasLength(1));
    expect(showroom.vehicles.single.displayName, 'Party Limo');
  });

  testWidgets(
    'detail shows both photos and hides carousel for a single photo',
    (tester) async {
      final two = tryParseLimousineShowroomVehicle(
        _publicVehicle(
          name: 'Party Limo',
          photos: const <String>[
            'https://cdn.example/party-ext.jpg',
            'https://cdn.example/party-int.jpg',
          ],
        ),
        index: 0,
      )!;
      await tester.pumpWidget(
        _app(
          LimousineVehicleDetailPage(
            vehicle: two,
            companyName: 'Maison Noire',
            partnerId: 'limo_1',
          ),
          size: kLimousineSmX400Portrait,
        ),
      );
      await tester.pump();
      expect(find.byKey(kLimousineDetailGalleryKey), findsOneWidget);
      expect(find.byKey(kLimousineDetailGalleryCounterKey), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.byKey(kLimousineDetailGalleryThumbsKey), findsOneWidget);
      expect(find.byKey(kLimousineDetailGalleryPrevKey), findsOneWidget);
      expect(find.byKey(kLimousineDetailGalleryNextKey), findsOneWidget);
      expect(find.text('Vraag offerte aan'), findsNothing);

      final one = tryParseLimousineShowroomVehicle(
        _publicVehicle(
          name: 'Hummer white',
          photos: const <String>['https://cdn.example/hummer.jpg'],
        ),
        index: 0,
      )!;
      await tester.pumpWidget(
        _app(
          LimousineVehicleDetailPage(
            vehicle: one,
            companyName: 'Maison Noire',
            partnerId: 'limo_1',
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(kLimousineDetailGalleryKey), findsNothing);
      expect(find.byKey(kLimousineDetailGalleryCounterKey), findsNothing);
      expect(find.byKey(kLimousineDetailGalleryThumbsKey), findsNothing);
      expect(find.byKey(kLimousineDetailGalleryPrevKey), findsNothing);
    },
  );

  test('public gallery payload never leaks private fields', () {
    final urls = orderPublicVehicleGalleryUrls(
      primaryUrl: 'https://cdn.example/ok.jpg',
      galleryUrls: const <String>[
        'file:///tmp/secret.jpg',
        'https://cdn.example/ok.jpg',
        '/r2/object-key',
      ],
    );
    final payload = <String, dynamic>{
      'photo_url': urls.first,
      'primary_photo_url': urls.first,
      'gallery_photo_urls': urls,
    };
    expect(limousineShowroomPayloadLeaksPrivate(payload), isFalse);
    expect(jsonEncode(payload).contains('tenant_id'), isFalse);
    expect(jsonEncode(payload).contains('license_plate'), isFalse);
    expect(jsonEncode(payload).contains('file://'), isFalse);
  });

  testWidgets(
    'publish persists selected vehicles before offers and keeps them',
    (tester) async {
      final persisted = <List<String>>[];
      final saves = <Map<String, dynamic>>[];
      final vehicles = <VehicleProfile>[
        _vehicle(id: 'vh_party', name: 'Party Limo'),
        _vehicle(id: 'vh_hummer', name: 'Hummer white', classId: 'luxury_van'),
      ];
      await tester.pumpWidget(
        _app(
          LimousineBusinessSetupPage(
            loadPricing: () async => <String, dynamic>{
              'limousine': <String, dynamic>{
                'enabled': true,
                'source_revision': 3,
                'offers': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'offer_id': 'off_1',
                    'enabled': true,
                    'published': true,
                    'target_type': LimousineOfferTarget.serviceClass,
                    'service_class_id': 'stretch_limousine',
                    'price_presentation':
                        LimousinePricePresentation.quoteRequired,
                    'currency': 'EUR',
                    'title': <String, String>{
                      'nl': 'Avond',
                      'en': 'Evening',
                      'fr': 'Soiree',
                      'es': 'Noche',
                    },
                    'description': <String, String>{
                      'nl': 'Avondrit',
                      'en': 'Evening ride',
                      'fr': 'Soiree',
                      'es': 'Noche',
                    },
                    'hourly': <String, dynamic>{
                      'enabled': false,
                      'currency': 'EUR',
                    },
                    'distance_time': <String, dynamic>{
                      'enabled': false,
                      'currency': 'EUR',
                    },
                  },
                ],
              },
            },
            savePricing: (section) async {
              saves.add(Map<String, dynamic>.from(section));
              return <String, dynamic>{
                'limousine': <String, dynamic>{
                  'source_revision': 4,
                  'offers': section['offers'],
                  'enabled': section['enabled'],
                  'selected_vehicle_ids': section['selected_vehicle_ids'],
                },
              };
            },
            persistVehicles: (rows) async {
              persisted.add(limousineSelectedVehicleIds(rows));
            },
            vehicles: vehicles,
            knownClassIds: const <String>['stretch_limousine', 'luxury_van'],
            entryEnabled: true,
            language: AppLanguage.nl,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Party Limo'), findsWidgets);
      expect(find.text('Hummer white'), findsWidgets);
      tester
          .widget<ButtonStyleButton>(
            find.byKey(kLimousineBusinessSetupPublishKey),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(persisted, isNotEmpty);
      expect(persisted.first, <String>['vh_party', 'vh_hummer']);
      expect(saves, hasLength(1));
      expect(saves.single['enabled'], isTrue);
      expect(saves.single['source_revision'], 3);
      expect(
        (saves.single['offers'] as List).cast<Map>().every(
          (offer) => offer['published'] == true,
        ),
        isTrue,
      );
      expect(saves.single['selected_vehicle_ids'], <String>[
        'vh_party',
        'vh_hummer',
      ]);
      expect(find.text('Party Limo'), findsWidgets);
      expect(find.text('Hummer white'), findsWidgets);
      expect(find.text('Foto’s beheren'), findsWidgets);
    },
  );

  testWidgets(
    'dirty back navigation shows save or discard instead of dropping',
    (tester) async {
      await tester.pumpWidget(
        _app(
          LimousineBusinessSetupPage(
            loadPricing: () async => <String, dynamic>{
              'limousine': <String, dynamic>{
                'enabled': true,
                'offers': <Map<String, dynamic>>[],
              },
            },
            savePricing: (_) async => <String, dynamic>{},
            vehicles: <VehicleProfile>[
              _vehicle(
                id: 'vh_party',
                name: 'Party Limo',
                category: '',
                classId: '',
              ),
            ],
            knownClassIds: const <String>['stretch_limousine'],
            language: AppLanguage.nl,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byKey(kLimousineBusinessSetupLeaveDialogKey), findsOneWidget);
      expect(find.text('Party Limo'), findsWidgets);
    },
  );

  testWidgets('phone detail keeps swipe chrome and hides tablet arrows', (
    tester,
  ) async {
    final two = tryParseLimousineShowroomVehicle(
      _publicVehicle(
        name: 'Party Limo',
        photos: const <String>[
          'https://cdn.example/party-ext.jpg',
          'https://cdn.example/party-int.jpg',
        ],
      ),
      index: 0,
    )!;
    await tester.pumpWidget(
      _app(
        LimousineVehicleDetailPage(
          vehicle: two,
          companyName: 'Maison Noire',
          partnerId: 'limo_1',
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineDetailGalleryKey), findsOneWidget);
    expect(find.byKey(kLimousineDetailGalleryCounterKey), findsOneWidget);
    expect(find.byKey(kLimousineDetailGalleryPrevKey), findsNothing);
    expect(find.byKey(kLimousineDetailGalleryNextKey), findsNothing);
  });

  testWidgets('limousine pages stay off the taxi partner profile', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LimousineProviderShowroomPage(
          partnerId: 'limo_1',
          profile: <String, dynamic>{
            'partner_id': 'limo_1',
            'company_name': 'Maison Noire',
            'vehicles': <Map<String, dynamic>>[
              _publicVehicle(
                name: 'Party Limo',
                photos: const <String>['https://cdn.example/party-ext.jpg'],
              ),
            ],
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(LimousineProviderShowroomPage), findsOneWidget);
    expect(find.byType(PartnerPublicProfilePage), findsNothing);
    await tester.pumpWidget(
      _app(
        LimousinePublicProfilePage(
          partnerId: 'limo_1',
          profile: <String, dynamic>{
            'partner_id': 'limo_1',
            'company_name': 'Maison Noire',
            'vehicles': <Map<String, dynamic>>[
              _publicVehicle(
                name: 'Party Limo',
                photos: const <String>['https://cdn.example/party-ext.jpg'],
              ),
            ],
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(LimousinePublicProfilePage), findsOneWidget);
    expect(find.byType(LimousineProviderShowroomPage), findsNothing);
    expect(find.byType(PartnerPublicProfilePage), findsNothing);
  });

  testWidgets('general taxi and airport profiles still use the taxi page', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        PartnerPublicProfilePage(
          partnerId: 'taxi_1',
          companyNameFallback: 'City Taxi',
          customerHomeBuilder: (_) => const SizedBox.shrink(),
          limousineShowroomEnabled: false,
          profileOverride: <String, dynamic>{
            'partner_id': 'taxi_1',
            'company_name': 'City Taxi',
            'profile_enabled': true,
            'services': <String>['taxi_vvb', 'airport_transfer'],
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(PartnerPublicProfilePage), findsOneWidget);
    expect(find.byType(LimousinePublicProfilePage), findsNothing);
    expect(find.byType(LimousineProviderShowroomPage), findsNothing);
  });
}
