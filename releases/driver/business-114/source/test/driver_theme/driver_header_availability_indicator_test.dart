import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/driver_theme/driver_header_availability_indicator.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';

ActiveDriverSession actor({
  String driver = 'christophe-fixture',
  String tenant = 'own-tenant',
  String company = 'own-company',
  String vehicle = 'red-fixture',
  String token = 'fixture-bearer',
  String? expiry,
}) => ActiveDriverSession(
  driverId: driver,
  tenantId: tenant,
  companyId: company,
  assignedVehicleId: vehicle,
  driverSessionToken: token,
  driverSessionExpiresAtUtc: expiry,
  employeeNumber: '',
  fullName: 'Fixture',
  phone: '',
  loggedInAt: '',
  updatedAt: '',
);

void main() {
  final owner = actor();
  DriverHeaderAvailabilityStatus display(
    String raw, {
    ActiveDriverSession? as,
  }) => DriverHeaderAvailabilityConfirmation(
    owner: owner,
    driverId: owner.driverId,
    rawStatus: raw,
  ).forDisplay(session: as ?? owner, displayedDriverId: (as ?? owner).driverId);

  test(
    'confirmed statuses never turn pause, offline, inactive or busy green',
    () {
      expect(display('available'), DriverHeaderAvailabilityStatus.available);
      expect(display('paused'), DriverHeaderAvailabilityStatus.paused);
      expect(display('offline'), DriverHeaderAvailabilityStatus.offline);
      expect(display('inactive'), DriverHeaderAvailabilityStatus.inactive);
      expect(display('on_trip'), DriverHeaderAvailabilityStatus.busy);
      expect(display(''), DriverHeaderAvailabilityStatus.unknown);
      expect(
        display('unexpected-status'),
        DriverHeaderAvailabilityStatus.unknown,
      );
    },
  );

  for (final other in [
    actor(driver: 'testdriver-fixture'),
    actor(tenant: 'foreign-tenant'),
    actor(company: 'foreign-company'),
    actor(vehicle: 'black-fixture'),
    actor(token: 'replacement-fixture-bearer'),
    actor(token: ''),
    actor(company: ''),
    actor(expiry: '2020-01-01T00:00:00Z'),
  ]) {
    test(
      'confirmation cannot transfer to ${other.driverId}/${other.tenantId}/${other.companyId}/${other.assignedVehicleId}/${other.driverSessionToken}',
      () {
        expect(
          display('available', as: other),
          DriverHeaderAvailabilityStatus.unknown,
        );
      },
    );
  }

  test('missing session or different preview chauffeur remains unknown', () {
    final confirmation = DriverHeaderAvailabilityConfirmation(
      owner: owner,
      driverId: owner.driverId,
      rawStatus: 'available',
    );
    expect(
      confirmation.forDisplay(session: null, displayedDriverId: owner.driverId),
      DriverHeaderAvailabilityStatus.unknown,
    );
    expect(
      confirmation.forDisplay(
        session: owner,
        displayedDriverId: 'testdriver-fixture',
      ),
      DriverHeaderAvailabilityStatus.unknown,
    );
  });

  for (final variant in DriverThemeVariant.values) {
    testWidgets('real dot reflects status and theme changes: $variant', (
      tester,
    ) async {
      final palette = paletteForDriverTheme(variant);
      Future<BoxDecoration> show(DriverHeaderAvailabilityStatus status) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DriverHeaderAvailabilityIndicator(
                status: status,
                palette: palette,
                label: 'Laatst bevestigde chauffeurstatus: $status',
              ),
            ),
          ),
        );
        final dot = tester.widget<Container>(
          find.byKey(const ValueKey('driver-header-availability-dot')),
        );
        expect(dot.constraints!.maxWidth, 12);
        final decoration = dot.decoration! as BoxDecoration;
        final ring = (decoration.border! as Border).top.color;
        expect(
          brandSignatureContrastRatio(ring, decoration.color!),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          find.byTooltip('Laatst bevestigde chauffeurstatus: $status'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        return decoration;
      }

      expect(
        (await show(DriverHeaderAvailabilityStatus.available)).color,
        palette.success,
      );
      expect(
        (await show(DriverHeaderAvailabilityStatus.offline)).color,
        palette.isDark ? Colors.grey.shade400 : Colors.grey.shade700,
      );
      expect(
        (await show(DriverHeaderAvailabilityStatus.inactive)).color,
        palette.danger,
      );
      expect(
        (await show(DriverHeaderAvailabilityStatus.paused)).color,
        isNot(palette.success),
      );
      expect(
        (await show(DriverHeaderAvailabilityStatus.busy)).color,
        isNot(palette.success),
      );
      expect(
        (await show(DriverHeaderAvailabilityStatus.unknown)).color,
        palette.textMuted,
      );
    });
  }

  testWidgets('status is announced without depending on color', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: DriverHeaderAvailabilityIndicator(
          status: DriverHeaderAvailabilityStatus.offline,
          palette: paletteForDriverTheme(DriverThemeVariant.lightEmerald),
          label: 'Laatst bevestigde chauffeurstatus: Offline',
        ),
      ),
    );
    expect(
      find.bySemanticsLabel('Laatst bevestigde chauffeurstatus: Offline'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  test(
    'released header now uses confirmed status; no unconditional green dot',
    () {
      final source = File(
        'lib/main_parts/driver_home_page_state.dart',
      ).readAsStringSync();
      final start = source.indexOf('  Widget _buildDriverHeaderActionCluster(');
      final end = source.indexOf(
        '  Widget _buildChauffeurBrandSignatureGoldHeader(',
        start,
      );
      final header = source.substring(start, end);
      expect(header, contains('DriverHeaderAvailabilityIndicator('));
      expect(header, contains('_headerAvailabilityConfirmation?.forDisplay('));
      expect(
        header,
        contains(
          '_driverAvailabilitySaving || _standaloneDriverSwitchInProgress',
        ),
      );
      expect(header, isNot(contains('Color(0xFF2ECC71)')));
      expect(header, isNot(contains("fallback: 'available'")));
    },
  );
}
