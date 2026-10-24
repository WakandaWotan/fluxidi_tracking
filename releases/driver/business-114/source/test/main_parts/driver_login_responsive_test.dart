import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company/company_ops_identity.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/main.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'driver_company_device_separation_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Roboto')..addFont(
          Future.value(
            ByteData.sublistView(
              File('C:/Windows/Fonts/arial.ttf').readAsBytesSync(),
            ),
          ),
        ))
        .load();
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                'C:/dev/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        ))
        .load();
  });
  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('fluxidi-login-ui-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temp.path,
        );
    FlutterSecureStorage.setMockInitialValues({
      fixtures.bindingKey: jsonEncode(fixtures.binding()),
    });
    activeCompanySessionNotifier.value = null;
    companyProfileNotifier.value = null;
    companyOpsLocalSessionNotifier.value = null;
    activeDriverSessionNotifier.value = null;
    nativeDriverDutySessionNotifier.value = null;
    appLanguageNotifier.value = AppLanguage.nl;
    resetBusinessThemePersistenceLatchForTest();
  });
  tearDown(() async {
    await flushLocalTenantStateWrites();
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (!temp.absolute.path.startsWith(Directory.systemTemp.absolute.path))
      throw StateError('outside temp');
    await temp.delete(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    double keyboard = 0,
    bool retained = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ChauffeurLoginPage(retainedCompanyScope: retained ? (tenantId: fixtures.tenant, companyId: fixtures.tenant, companyCode: 'FLX-90001') : null),
      ),
    );
    await tester.pumpAndSettle();
  }

  http.Client client({
    bool reject = false,
    String code = 'FLX-90001',
    bool longNames = false,
  }) => MockClient((request) async {
    if (request.url.path == '/public/company/resolve') {
      expect(request.headers.containsKey('authorization'), isFalse);
      return http.Response(
        jsonEncode({
          'ok': true,
          'company_code': code,
          'display_name': longNames
              ? 'Internationaal vervoer en persoonlijke chauffeurs voor een white-labelbedrijf'
              : 'Fixture vervoer',
        }),
        200,
      );
    }
    expect(request.url.path, '/public/vehicle-device/drivers');
    final rows = fixtures.directory();
    if (longNames)
      rows['drivers'] = [
        {
          'driver_id': 'driver-a',
          'name':
              'Chauffeur met een bijzonder lange samengestelde weergavenaam',
        },
      ];
    return reject
        ? http.Response('{"ok":false}', 403)
        : http.Response(jsonEncode(rows), 200);
  });

  testWidgets('device unlink confirmation names company and vehicle; cancel makes no mutation', (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('driver_unlink_device')));
      await tester.tap(find.byKey(const ValueKey('driver_unlink_device')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.descendant(of:find.byType(AlertDialog),matching:find.textContaining('Fixture vervoer')),findsOneWidget);
      expect(find.descendant(of:find.byType(AlertDialog),matching:find.textContaining('Fixture shared vehicle')),findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog),findsNothing);
      expect(await const FlutterSecureStorage().read(key:fixtures.bindingKey),isNotNull);
    }, client);
  });

  testWidgets(
    'verified vehicle context and inline six digit PIN replace the old instruction blocks',
    (tester) async {
      await http.runWithClient(() async {
        await mount(tester);
        expect(
          find.byKey(const ValueKey('driver_verified_vehicle')),
          findsOneWidget,
        );
        expect(find.text('Fixture vervoer'), findsOneWidget);
        expect(find.byKey(const ValueKey('driver_login_pin')), findsOneWidget);
        expect(
          find.textContaining('Handmatig inloggen is alleen'),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('driver_pair_vehicle')), findsNothing);
        final button = tester.widget<FilledButton>(
          find.byKey(const ValueKey('vehicle_pin_login')),
        );
        expect(button.onPressed, isNull);
        await tester.pumpWidget(const SizedBox());
      }, client);
    },
  );

  testWidgets(
    'driver selection plus six digits required; missing PIN never creates a session',
    (tester) async {
      await http.runWithClient(() async {
        await mount(tester);
        await tester.tap(find.byKey(const ValueKey('vehicle_driver_choice')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Fixture A').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('driver_login_pin')),
          '12345',
        );
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('vehicle_pin_login')),
              )
              .onPressed,
          isNull,
        );
        await tester.enterText(
          find.byKey(const ValueKey('driver_login_pin')),
          '123456',
        );
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('vehicle_pin_login')),
              )
              .onPressed,
          isNotNull,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('vehicle_pin_login')),
        );
        await tester.tap(find.byKey(const ValueKey('vehicle_pin_login')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Meld je eerst één keer aan'),
          findsOneWidget,
        );
        expect(activeDriverSessionNotifier.value, isNull);
        await tester.pumpWidget(const SizedBox());
      }, client);
    },
  );

  testWidgets(
    'failed directory cannot expose names or claim a verified vehicle',
    (tester) async {
      await http.runWithClient(() async {
        await mount(tester);
        expect(
          find.byKey(const ValueKey('driver_verified_vehicle')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('vehicle_driver_choice')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('driver_directory_retry')),
          findsOneWidget,
        );
        expect(activeDriverSessionNotifier.value, isNull);
        await tester.pumpWidget(const SizedBox());
      }, () => client(reject: true));
    },
  );

  testWidgets('foreign public branding cannot replace the verified company', (
    tester,
  ) async {
    await http.runWithClient(() async {
      await mount(tester);
      expect(find.text('Fixture vervoer'), findsNothing);
      expect(find.text('FLX-90001'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('driver_verified_vehicle')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    }, () => client(code: 'FLX-99999'));
  });

  testWidgets(
    'long company and driver names remain usable at double text size',
    (tester) async {
      await http.runWithClient(() async {
        await mount(tester, size: const Size(320, 700), scale: 2);
        await tester.ensureVisible(
          find.byKey(const ValueKey('vehicle_driver_choice')),
        );
        await tester.tap(find.byKey(const ValueKey('vehicle_driver_choice')));
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .text(
                'Chauffeur met een bijzonder lange samengestelde weergavenaam',
              )
              .last,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }, () => client(longNames: true));
    },
  );

  testWidgets(
    'branding timeout never authorizes or retries; ordinary rebuild adds no requests',
    (tester) async {
      var directories = 0, branding = 0;
      await http.runWithClient(
        () async {
          await mount(tester);
          expect(
            find.byKey(const ValueKey('driver_verified_vehicle')),
            findsOneWidget,
          );
          expect(find.text('FLX-90001'), findsOneWidget);
          await tester.enterText(
            find.byKey(const ValueKey('driver_login_pin')),
            '123',
          );
          await tester.pump();
          expect(directories, 1);
          expect(branding, 1);
          expect(activeDriverSessionNotifier.value, isNull);
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((request) async {
          if (request.url.path == '/public/company/resolve') {
            branding++;
            throw TimeoutException('synthetic');
          }
          expect(request.url.path, '/public/vehicle-device/drivers');
          directories++;
          return http.Response(jsonEncode(fixtures.directory()), 200);
        }),
      );
    },
  );

  for(final language in AppLanguage.values) {
    for(final size in [const Size(320,640),const Size(390,844),const Size(900,1300)]) {
      testWidgets('transition actions ${language.name} ${size.width}',(tester) async {
        appLanguageNotifier.value=language;
        await http.runWithClient(()async {
          await mount(tester,size:size,scale:1.3);
          expect(find.byKey(const ValueKey('driver_switch_vehicle')),findsOneWidget);
          expect(find.byKey(const ValueKey('driver_unlink_device')),findsOneWidget);
          expect(tester.takeException(),isNull);
          if(language==AppLanguage.de)expect(find.text('Fahrzeug wechseln'),findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        },client);
      });
    }
  }

  for (final sample in [
    (const Size(320, 640), 1.0, 0.0),
    (const Size(360, 780), 2.0, 300.0),
    (const Size(800, 1280), 1.5, 0.0),
    (const Size(1280, 800), 2.0, 280.0),
  ]) {
    testWidgets(
      'real login layout: ${sample.$1} scale ${sample.$2} keyboard ${sample.$3}',
      (tester) async {
        await http.runWithClient(() async {
          await mount(
            tester,
            size: sample.$1,
            scale: sample.$2,
            keyboard: sample.$3,
          );
          expect(
            find.byKey(const ValueKey('driver_login_pin')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(
            find.byKey(const ValueKey('driver_login_help')),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }, client);
      },
    );
  }

  final palettes = <(String, BusinessThemeVariant, Color?)>[
    for (final variant in BusinessThemeVariant.values)
      (variant.name, variant, null),
    for (final color in [
      0xfffafafa,
      0xff050505,
      0xff1c5fca,
      0xffee6241,
      0xff8c29af,
      0xff28c59d,
      0xff868686,
    ])
      (
        'custom-${color.toRadixString(16)}',
        BusinessThemeVariant.brandSignatureGold,
        Color(color),
      ),
  ];
  for (final sample in palettes) {
    testWidgets('actual company login theme and AA contrast: ${sample.$1}', (
      tester,
    ) async {
      await tester.runAsync(
        () => hydrateBusinessThemeFromCompanyProfile(
          companyId: fixtures.tenant,
          profile: {
            'business_theme': {
              'variant': sample.$2.name,
              'updatedAt': '2026-10-21T10:00:00Z',
              if (sample.$3 != null)
                'brandSignaturePalette': BrandSignaturePalette.fromColor(
                  sample.$3!,
                ).toJson(),
            },
          },
        ),
      );
      final document = encodeBusinessThemeForCompanyProfile(fixtures.tenant);
      await http.runWithClient(() async {
        await mount(tester, size: const Size(390, 844), scale: 1.4);
        final context = tester.element(
          find.byKey(const ValueKey('driver_login_pin')),
        );
        final theme = Theme.of(context);
        final palette = sample.$2 == BusinessThemeVariant.brandSignatureGold
            ? brandSignatureBusinessPalette(
                resolveStoredBrandSignaturePalette(fixtures.tenant),
              )
            : paletteForBusinessTheme(sample.$2);
        expect(theme.scaffoldBackgroundColor, palette.background);
        expect(
          theme.colorScheme.primary,
          palette.accent,
          reason: 'Stored company accent stays unchanged',
        );
        void ratio(Color fg, Color bg, double minimum) => expect(
          brandSignatureContrastRatio(fg, bg),
          greaterThanOrEqualTo(minimum - .001),
        );
        ratio(theme.textTheme.bodyMedium!.color!, palette.background, 4.5);
        ratio(
          theme.inputDecorationTheme.labelStyle!.color!,
          palette.background,
          4.5,
        );
        ratio(theme.colorScheme.onPrimary, palette.accent, 4.5);
        ratio(theme.colorScheme.outline, palette.background, 3);
        ratio(
          theme.colorScheme.onErrorContainer,
          theme.colorScheme.errorContainer,
          4.5,
        );
        final style = theme.filledButtonTheme.style!;
        ratio(
          style.foregroundColor!.resolve({WidgetState.disabled})!,
          style.backgroundColor!.resolve({WidgetState.disabled})!,
          4.5,
        );
        expect(tester.takeException(), isNull);
        expect(
          encodeBusinessThemeForCompanyProfile(fixtures.tenant),
          document,
          reason: 'Presentation must not rewrite stored company colors',
        );
        await tester.pumpWidget(const SizedBox());
      }, client);
    });
  }

  testWidgets('compact phone keeps controls and help inside the initial viewport', (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      expect(tester.getSize(find.byKey(const ValueKey('driver_verified_vehicle'))).height, lessThanOrEqualTo(140));
      expect(tester.getSize(find.byKey(const ValueKey('driver_login_pin'))).height, lessThanOrEqualTo(56));
      expect(tester.getBottomRight(find.byKey(const ValueKey('driver_login_help'))).dy, lessThanOrEqualTo(844));
      await tester.pumpWidget(const SizedBox());
    }, client);
  });

  testWidgets('verified retained company code resolves branding when directory omits optional code', (tester) async {
    var brandingReads = 0;
    await http.runWithClient(() async {
      await mount(tester, retained: true);
      expect(brandingReads, 1);
      expect(find.text('Fixture retained brand'), findsOneWidget);
      expect(find.byKey(const ValueKey('driver_company_logo')), findsOneWidget);
      final image = tester.widget<Image>(find.byKey(const ValueKey('driver_company_logo')));
      expect((image.image as NetworkImage).url, 'https://fixture.invalid/brand.png');
      expect(activeCompanySessionNotifier.value, isNull);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((request) async {
      if (request.url.path == '/public/company/resolve') {
        brandingReads++;
        return http.Response(jsonEncode({'ok': true, 'company_code': 'FLX-90001', 'display_name': 'Fixture retained brand', 'logo_url': 'https://fixture.invalid/brand.png'}), 200);
      }
      final rows = fixtures.directory()..remove('company_code');
      return http.Response(jsonEncode(rows), 200);
    }));
  });

  testWidgets('contradictory public company scope cannot supply presentation', (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      expect(find.text('Foreign presentation'), findsNothing);
      expect(find.text('FLX-90001'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((request) async => http.Response(jsonEncode(request.url.path == '/public/company/resolve'
      ? {'ok': true, 'company_code': 'FLX-90001', 'company_id': 'foreign', 'tenant_id': 'foreign', 'display_name': 'Foreign presentation'}
      : fixtures.directory()), 200)));
  });

  testWidgets('binding changed while branding loads discards the late presentation', (tester) async {
    final pending = Completer<http.Response>();
    await http.runWithClient(() async {
      await mount(tester);
      FlutterSecureStorage.setMockInitialValues({fixtures.bindingKey: jsonEncode({...fixtures.binding(), 'vehicle_id': 'other-vehicle'})});
      pending.complete(http.Response(jsonEncode({'ok': true, 'company_code': 'FLX-90001', 'display_name': 'Late presentation'}), 200));
      await tester.pumpAndSettle();
      expect(find.text('Late presentation'), findsNothing);
      expect(activeDriverSessionNotifier.value, isNull);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((request) async => request.url.path == '/public/company/resolve'
        ? pending.future : http.Response(jsonEncode(fixtures.directory()), 200)));
  });

  testWidgets('verified directory without branding keeps a neutral linked company label', (tester) async {
    await http.runWithClient(() async {
      await mount(tester);
      expect(find.text('Gekoppeld bedrijf'), findsOneWidget);
      expect(find.text('Bedrijf nog niet bevestigd'), findsNothing);
      expect(find.byIcon(Icons.business_outlined), findsOneWidget);
      expect(find.byKey(const ValueKey('driver_verified_vehicle')), findsOneWidget);
      expect(activeCompanySessionNotifier.value, isNull);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((request) async {
      expect(request.url.path, '/public/vehicle-device/drivers');
      return http.Response(jsonEncode(fixtures.directory()..remove('company_code')), 200);
    }));
  });

  // Reproducible Flutter renders, not Android/device or release-artifact proof.
  for (final sample in [
    ('phone-dark', const Size(390, 844), BusinessThemeVariant.executiveGold),
    ('phone-ready', const Size(390, 844), BusinessThemeVariant.executiveGold),
    (
      'tablet-light',
      const Size(900, 1300),
      BusinessThemeVariant.cleanProfessional,
    ),
  ]) {
    testWidgets('local render ${sample.$1}', (tester) async {
      await tester.runAsync(
        () => hydrateBusinessThemeFromCompanyProfile(
          companyId: fixtures.tenant,
          profile: {
            'business_theme': {'variant': sample.$3.name},
          },
        ),
      );
      await http.runWithClient(() async {
        await mount(tester, size: sample.$2);
        if (sample.$1 == 'phone-ready') {
          await tester.tap(find.byKey(const ValueKey('vehicle_driver_choice')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Fixture A').last);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('driver_login_pin')),
            '123456',
          );
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
        }
        debugPrint('LOGIN_LAYOUT ${jsonEncode({'render': sample.$1, 'width': sample.$2.width, 'height': sample.$2.height,
          'cardHeight': tester.getSize(find.byKey(const ValueKey('driver_verified_vehicle'))).height,
          'pinHeight': tester.getSize(find.byKey(const ValueKey('driver_login_pin'))).height,
          'helpBottom': tester.getBottomRight(find.byKey(const ValueKey('driver_login_help'))).dy})}', wrapWidth: 2000);
        await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile(
            Uri.file(
              '${const String.fromEnvironment('LOGIN_RENDER_DIR', defaultValue: 'D:/Projecten/outputs/b108_login_visual_finish_20261022/after')}/${sample.$1}.png',
            ),
          ),
        );
        await tester.pumpWidget(const SizedBox());
      }, client);
    });
  }
}
