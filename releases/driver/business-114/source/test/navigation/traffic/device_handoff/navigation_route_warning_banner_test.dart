import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_route_warning_banner.dart';
import 'package:fluxidi_tracking/navigation/traffic/navigation_route_warnings.dart';

void main() {
  final cloud =
      jsonDecode(File('test/navigation/traffic/device_handoff/cloud-results.json').readAsStringSync()) as Map;
  for (final r in cloud['results'] as List) {
    if (r['action'] != 'warnings') continue;
    final dto = Map<String, dynamic>.from(r['warnings']), raw = r['rawRoute'];
    final geometry = [
      for (final p in raw['geometry'] as List)
        [p['longitude'] as num, p['latitude'] as num],
    ];
    final now = DateTime.fromMillisecondsSinceEpoch(
      dto['generatedAt'],
      isUtc: true,
    );
    final snapshot = decodeRouteWarnings(
      dto: dto,
      geometry: geometry,
      tenantId: dto['tenant_id'],
      companyId: dto['company_id'],
      graphVersion: dto['graphVersion'],
      manifestSha256: dto['manifestSha256'],
      evidenceRevision: dto['evidenceRevision'],
      routeEvidenceId: dto['routeEvidenceId'],
      now: now,
    );
    final kind = r['run'].toString().split('-')[1];
    for (final dark in [false, true])
      for (final width in [280.0, 600.0]) {
        testWidgets(
          'real $kind banner, width $width, dark $dark, expiry and passed route',
          (tester) async {
            Future<void> show({
              DateTime? clock,
              double progress = 0,
              bool trusted = true,
            }) => tester.pumpWidget(
              MaterialApp(
                theme: dark ? ThemeData.dark() : ThemeData.light(),
                home: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: width,
                      child: NavigationRouteWarningBanner(
                        snapshot: snapshot,
                        progressMeters: progress,
                        progressTrusted: trusted,
                        now: clock ?? now,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await show();
            expect(find.byType(Text), findsOneWidget);
            expect(tester.takeException(), isNull);
            expect(find.textContaining('+'), findsNothing);
            expect(find.textContaining('min'), findsNothing);
            await show(trusted: false);
            expect(find.byType(Text), findsNothing);
            await show(clock: now.add(const Duration(minutes: 4)));
            expect(find.byType(Text), findsNothing);
            await show(progress: snapshot.items.last.end + 1);
            expect(find.byType(Text), findsNothing);
          },
        );
      }
  }
}
