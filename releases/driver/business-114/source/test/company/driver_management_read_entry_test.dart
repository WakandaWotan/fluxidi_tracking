import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/driver_management_host_entry.dart';
import 'package:fluxidi_tracking/company/driver_management_read_entry.dart';

void main() {
  Map<String, Object?> contract() => {
    'ok': true, 'ready': true, 'read_only': true,
    'contract': 'fluxidi-driver-management-read-v1',
    'operator': {'company_id': 'own-company', 'tenant_id': 'own-tenant'},
    'capabilities': {'drivers_read': true, 'export_csv': true,
      'partner_write': false, 'settlement_write': false,
      'import_write': false, 'bulk_assign': false},
  };
  Future<bool> ready(Map<String, Object?> data, {int status = 200, bool unchanged = true}) =>
      driverManagementReadReady(entry: DriverManagementHostEntry('https://operator.test'),
        companyId: 'own-company', get: (uri) async {
          expect(uri.toString(), 'https://operator.test/driver-management/readiness');
          return (status: status, body: jsonEncode(data));
        }, sessionUnchanged: () async => unchanged);
  test('readiness requires authenticated exact company and read-only contract', () async {
    expect(await ready(contract()), isTrue);
    expect(await ready(contract(), status: 404), isFalse);
    expect(await ready(contract(), status: 401), isFalse);
    expect(await ready(contract(), unchanged: false), isFalse);
    for (final key in ['ok', 'ready', 'read_only']) {
      expect(await ready({...contract(), key: false}), isFalse);
    }
    expect(await ready({...contract(), 'contract': 'unverified'}), isFalse);
    expect(await ready({...contract(), 'operator': {'company_id': 'foreign', 'tenant_id': 'own'}}), isFalse);
    for (final key in ['partner_write', 'settlement_write', 'import_write', 'bulk_assign']) {
      final data = contract();
      data['capabilities'] = {...data['capabilities'] as Map, key: true};
      expect(await ready(data), isFalse);
    }
  });
  test('network and malformed readiness never reveal entry', () async {
    for (final body in ['not-json', '[]', '{}']) {
      expect(await driverManagementReadReady(entry: DriverManagementHostEntry('https://operator.test'),
        companyId: 'own-company', get: (_) async => (status: 200, body: body),
        sessionUnchanged: () async => true), isFalse);
    }
    expect(await driverManagementReadReady(entry: DriverManagementHostEntry('https://operator.test'),
      companyId: 'own-company', get: (_) => throw TimeoutException('offline'),
      sessionUnchanged: () async => true), isFalse);
  });
  testWidgets('default disabled build makes no probe and keeps original management visible', (tester) async {
    final session = ValueNotifier<Object?>('own-session');
    var probes = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
      const Text('Bestaand chauffeurbeheer'),
      DriverManagementReadEntryButton(session: session, probe: () async { probes++; return true; },
        open: () async {}, tooltip: 'Uitgebreid overzicht'),
    ]))));
    expect(find.text('Bestaand chauffeurbeheer'), findsOneWidget);
    expect(find.byKey(const ValueKey('driver-management-read-entry')), findsNothing);
    expect(probes, 0);
    session.dispose();
  });
  testWidgets('enabled entry appears only after readiness and opens once', (tester) async {
    final session = ValueNotifier<Object?>('own-session');
    final probe = Completer<bool>(), open = Completer<void>();
    var opens = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      DriverManagementReadEntryButton(session: session, enabled: true,
        probe: () => probe.future, open: () { opens++; return open.future; }, tooltip: 'Overzicht'))));
    expect(tester.widget<TextButton>(find.byKey(const ValueKey('driver-management-read-entry'))).onPressed, isNull);
    probe.complete(true); await tester.pump();
    await tester.tap(find.byType(IconButton)); await tester.pump();
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    expect(opens, 1); open.complete(); await tester.pump();
    await tester.pumpWidget(const SizedBox()); session.dispose();
  });
  testWidgets('company switch hides immediately and ignores the previous readiness', (tester) async {
    final session = ValueNotifier<Object?>('company-one');
    final old = Completer<bool>(), current = Completer<bool>();
    var probes = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      DriverManagementReadEntryButton(session: session, enabled: true,
        probe: () => ++probes == 1 ? old.future : current.future,
        open: () async {}, tooltip: 'Overzicht'))));
    session.value = 'company-two'; await tester.pump();
    old.complete(true); await tester.pump();
    expect(tester.widget<TextButton>(find.byKey(const ValueKey('driver-management-read-entry'))).onPressed, isNull);
    current.complete(false); await tester.pump();
    expect(tester.widget<TextButton>(find.byKey(const ValueKey('driver-management-read-entry'))).onPressed, isNull);
    await tester.pumpWidget(const SizedBox()); session.dispose();
  });
  testWidgets('logout removes visible entry and blocks stale results', (tester) async {
    final session = ValueNotifier<Object?>('own-session');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      DriverManagementReadEntryButton(session: session, enabled: true,
        probe: () async => true, open: () async {}, tooltip: 'Overzicht'))));
    await tester.pump(); expect(find.byType(IconButton), findsOneWidget);
    session.value = null; await tester.pump();
    expect(tester.widget<TextButton>(find.byKey(const ValueKey('driver-management-read-entry'))).onPressed, isNull);
    await tester.pumpWidget(const SizedBox()); session.dispose();
  });
  for (final width in [360.0, 800.0, 1280.0]) {
    testWidgets('labelled safe entry opens at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = ValueNotifier<Object?>('own-session');
      var opens = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        DriverManagementReadEntryButton(session: session, enabled: true,
          label: 'Nieuw overzicht', tooltip: 'Uitgebreid chauffeursoverzicht',
          probe: () async => true, open: () async { opens++; }))));
      await tester.pump();
      expect(find.text('Nieuw overzicht'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('driver-management-read-entry')));
      await tester.pump();
      expect(opens, 1);
      expect(tester.takeException(), isNull);
      session.value = null; await tester.pump();
      expect(find.text('Nieuw overzicht'), findsOneWidget);
      expect(tester.widget<TextButton>(find.byKey(const ValueKey('driver-management-read-entry'))).onPressed, isNull);
      await tester.pumpWidget(const SizedBox()); session.dispose();
    });
  }

}
