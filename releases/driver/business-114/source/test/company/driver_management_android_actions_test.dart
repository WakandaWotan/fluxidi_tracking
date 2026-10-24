import 'dart:io';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/main.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/vehicle_management_page.dart';
import 'driver_management_native_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Real company entry accepts server-valid session with old local expiry and opens management actions',
    (tester) async {
      final dir = Directory(
        'D:/Projecten/outputs/business98_final_management_20261013/native-session-fixture',
      )..createSync(recursive: true);
      appLanguageNotifier.value = AppLanguage.nl;
      FlutterSecureStorage.setMockInitialValues({});
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => dir.path,
      );
      final f = NativeDriverFixture(company: 'company-action-acceptance');
      final requests = <String>[];
      await http.runWithClient(
        () async {
          await tester.runAsync(
            () =>
                CompanySessionStore.instance.saveVerifiedCompanyPairingSession(
                  tenantId: f.company,
                  companyId: f.company,
                  companyName: 'Eigen bedrijf',
                  countryCode: 'BE',
                  companySessionToken: 'local-test',
                  expiresAtUtc: DateTime.utc(2020),
                  linkMethod: 'public_company_pairing',
                ),
          );
          driversNotifier.value = [
            DriverProfile(
              id: 'driver-1',
              companyId: f.company,
              fullName: 'Eigen chauffeur',
              employeeNumber: 'own',
              phone: '',
              isActive: true,
            ),
          ];
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            const MaterialApp(home: CompanyDriverManagementPage()),
          );
          for (var i = 0; i < 30; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)),
            );
            await tester.pump(const Duration(milliseconds: 30));
            if (find
                .byKey(const ValueKey('native-driver-count'))
                .evaluate()
                .isNotEmpty)
              break;
          }
          expect(
            find.byKey(const ValueKey('native-driver-error')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('native-driver-count')),
            findsOneWidget,
          );
          expect(requests, contains('/driver-management/api/drivers'));
          for (final label in ['Documenten', 'Codes & QR']) {
            final target = find.text(label).first;
            await tester.ensureVisible(target);
            await tester.tap(target);
            await tester.pumpAndSettle();
            expect(
              find.text(
                label == 'Documenten'
                    ? 'Kies chauffeur voor documenten'
                    : 'Kies chauffeur voor codes & QR',
              ),
              findsOneWidget,
            );
            expect(find.text('Eigen chauffeur'), findsOneWidget);
            await tester.tap(find.text('Eigen chauffeur'));
            for (var i = 0; i < 12; i++) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 30)),
              );
              await tester.pump(const Duration(milliseconds: 100));
            }
            await tester.pumpAndSettle();
            final expected = label == 'Documenten'
                ? 'Document toevoegen'
                : 'Tijdelijke koppel-QR';
            expect(find.text(expected), findsOneWidget);
            Navigator.of(tester.element(find.text(expected))).pop();
            await tester.pumpAndSettle();
          }
          // A stale/foreign selection must report refusal, never open another
          // company's documents or silently do nothing.
          await tester.ensureVisible(find.text('Documenten').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Documenten').first);
          await tester.pumpAndSettle();
          final ownDrivers = driversNotifier.value;
          driversNotifier.value = [];
          await tester.tap(find.text('Eigen chauffeur'));
          for (var i = 0; i < 12; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)),
            );
            await tester.pump(const Duration(milliseconds: 50));
          }
          await tester.pumpAndSettle();
          expect(
            find.text(
              'Vernieuw het beheer om deze chauffeur veilig te beheren.',
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('native-driver-count')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('native-driver-error')),
            findsNothing,
          );
          driversNotifier.value = ownDrivers;
          await tester.pump(const Duration(seconds: 5));
          // Vehicle-page layout belongs to the separate vehicle-card owner.
          // Verify the real route here on tablet; handset overflow is recorded
          // separately, without modifying the other owner's source file.
          tester.view.physicalSize = const Size(800, 1280);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Voertuigen').first);
          await tester.tap(find.text('Voertuigen').first);
          await tester.pumpAndSettle();
          expect(find.byType(VehicleManagementPage), findsOneWidget);
          expect(requests.where((p) => p.contains('export')), isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pageBack();
          await tester.pumpAndSettle();
          // Old local expiry is accepted only when the server accepts the bearer.
          f.denied = 401;
          await tester.tap(find.byTooltip('Vernieuwen'));
          for (var i = 0; i < 20; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)),
            );
            await tester.pump(const Duration(milliseconds: 50));
          }
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('native-driver-error')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('native-driver-count')),
            findsNothing,
          );
          for (final action in ['vehicles', 'documents', 'codes']) {
            expect(
              find.byKey(ValueKey('management-action-$action')),
              findsNothing,
            );
          }
          expect(find.textContaining('PRIVATE SERVER ERROR'), findsNothing);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        },
        () => MockClient((request) async {
          requests.add(request.url.path);
          if (request.url.path.startsWith('/driver-management/')) {
            expect(
              request.method,
              'GET',
              reason: 'No real writes in acceptance',
            );
            final response = await f.get(request.url, {
              'Authorization': request.headers['authorization'] ?? '',
            });
            return http.Response(
              response.body,
              response.status,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            '{"ok":false}',
            503,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
    },
  );
}
