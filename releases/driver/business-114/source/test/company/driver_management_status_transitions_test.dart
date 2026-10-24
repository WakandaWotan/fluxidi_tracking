import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/company/driver_management_native_page.dart';
import 'package:fluxidi_tracking/company/driver_management_native_repository.dart';

import 'driver_management_native_test_support.dart';

// Contract fixtures, never actual driver accounts or live acceptance evidence.
class StatusFixture extends NativeDriverFixture {
  final statuses = <String, String>{
    'christophe': 'offline',
    'testdriver': 'online',
  };
  Completer<DriverManagementResponse>? delayed;
  DriverManagementResponse? captured;
  bool holdNext = false;
  bool contradictoryAvailability = false;

  @override
  Future<DriverManagementResponse> get(
    Uri uri,
    Map<String, String> headers,
  ) async {
    if (uri.path != '/driver-management/api/drivers')
      return super.get(uri, headers);
    requests.add(uri);
    final response = (
      status: 200,
      body: jsonEncode({
        'ok': true,
        'items': statuses.entries
            .map(
              (entry) => {
                ...driver,
                'driver_id': entry.key,
                'display_name': entry.key == 'christophe'
                    ? 'Christophe fixture'
                    : 'TestDriver fixture',
                'status': entry.value,
                // Presence alone must not turn a server-projected pause green.
                'live_connected': true,
                'availability_status': contradictoryAvailability
                    ? 'paused'
                    : entry.value,
              },
            )
            .toList(),
        'total': statuses.length,
        'offset': 0,
        'limit': 25,
        'next_cursor': null,
      }),
    );
    if (holdNext) {
      holdNext = false;
      captured = response;
      delayed = Completer<DriverManagementResponse>();
      return delayed!.future;
    }
    return response;
  }
}

void main() {
  Future<void> open(
    WidgetTester tester,
    StatusFixture fixture, {
    BusinessThemePalette? palette,
  }) async {
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = ValueNotifier<Object?>(Object());
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: DriverManagementNativePage(
          palette: palette,
          connect: () async => fixture.repository(),
          session: session,
          openLegacy: () {},
          manageDriver: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder card(String id) => find.byKey(ValueKey('native-driver-detail-$id'));
  void label(String id, String value) => expect(
    find.descendant(of: card(id), matching: find.text(value)),
    findsOneWidget,
  );
  Color? dot(WidgetTester tester, String id) => tester
      .widget<Icon>(
        find.descendant(of: card(id), matching: find.byIcon(Icons.circle)),
      )
      .color;
  Future<void> refresh(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Vernieuwen'));
    await tester.pumpAndSettle();
  }

  for (final variant in BusinessThemeVariant.values) {
    testWidgets(
      'server status colors remain readable and distinct in $variant',
      (tester) async {
        final palette = paletteForBusinessTheme(variant);
        final fixture = StatusFixture();
        await open(tester, fixture, palette: palette);
        label('christophe', 'Offline');
        expect(
          dot(tester, 'christophe'),
          palette.isDark ? Colors.grey.shade400 : Colors.grey.shade700,
        );
        expect(
          brandSignatureContrastRatio(
            dot(tester, 'christophe')!,
            palette.surface,
          ),
          greaterThanOrEqualTo(3),
        );
        label('testdriver', 'Online');
        expect(dot(tester, 'testdriver'), palette.success);
        fixture.statuses['testdriver'] = 'paused';
        await refresh(tester);
        label('testdriver', 'Pauze');
        expect(
          dot(tester, 'testdriver'),
          palette.isDark ? Colors.orange.shade300 : Colors.orange.shade900,
        );
        expect(
          brandSignatureContrastRatio(
            dot(tester, 'testdriver')!,
            palette.surface,
          ),
          greaterThanOrEqualTo(3),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'each driver preserves online-pause-online-offline server transitions after refresh',
    (tester) async {
      final fixture = StatusFixture();
      await open(tester, fixture);
      label('christophe', 'Offline');
      label('testdriver', 'Online');
      for (final id in ['christophe', 'testdriver']) {
        fixture.statuses[id] = 'online';
        await refresh(tester);
        label(id, 'Online');
        final green = dot(tester, id);
        fixture.statuses[id] = 'paused';
        await refresh(tester);
        label(id, 'Pauze');
        expect(dot(tester, id), isNot(green));
        await refresh(tester);
        label(id, 'Pauze');
        fixture.statuses[id] = 'online';
        await refresh(tester);
        label(id, 'Online');
        expect(dot(tester, id), green);
        fixture.statuses[id] = 'offline';
        await refresh(tester);
        label(id, 'Offline');
        expect(dot(tester, id), isNot(green));
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'list uses server status DTO; contradictory raw availability is not silently reinterpreted',
    (tester) async {
      final fixture = StatusFixture()..contradictoryAvailability = true;
      await open(tester, fixture);
      // Diagnostic: if the backend returns online despite a pause, this UI
      // reproduces online. It is not proof that such a live response was received.
      label('testdriver', 'Online');
      fixture.statuses['testdriver'] = 'paused';
      await refresh(tester);
      label('testdriver', 'Pauze');
      label('christophe', 'Offline');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('late online response cannot overwrite a newer paused query', (
    tester,
  ) async {
    final fixture = StatusFixture();
    await open(tester, fixture);
    fixture.holdNext = true;
    await tester.tap(find.byTooltip('Vernieuwen'));
    await tester.pump();
    fixture.statuses['testdriver'] = 'paused';
    await tester.enterText(find.byType(TextField).first, 'Test');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    label('testdriver', 'Pauze');
    fixture.delayed!.complete(fixture.captured!);
    await tester.pumpAndSettle();
    label('testdriver', 'Pauze');
    label('christophe', 'Offline');
    await tester.pumpWidget(const SizedBox());
  });
}
