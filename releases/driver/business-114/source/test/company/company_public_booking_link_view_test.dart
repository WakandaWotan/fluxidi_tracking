import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_public_booking_link.dart';
import 'package:fluxidi_tracking/company/company_public_booking_link_view.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'company_public_booking_link_fixtures.dart';

void main() {
  for (final row in [
    (company: marioCompanyId, slug: 'taxi-mario', name: 'Taxi Mario'),
    (company: fluxidiCompanyId, slug: 'fluxidi-taxi', name: 'Fluxidi'),
  ]) {
    testWidgets('${row.name}: QR/open/copy/share use one exact URL', (
      tester,
    ) async {
      final captured = <String, String>{};
      Uint8List? qrPng;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CompanyPublicBookingLinkView(
                loader: () => testBookingLink(
                  company: row.company,
                  slug: row.slug,
                  name: row.name,
                ),
                copyLink: (url) async {
                  captured['copy'] = url;
                },
                openLink: (uri) async {
                  captured['open'] = uri.toString();
                  return true;
                },
                shareLink: (url) async {
                  captured['share'] = url;
                },
                shareQr: (png, url, name) async {
                  captured['qr'] = url;
                  expect(name, row.name);
                  qrPng = png;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final url = 'https://booking.fluxidi.com/${row.slug}';
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.textContaining('FLX-'), findsNothing);
      expect(find.textContaining('workers.dev'), findsNothing);
      expect(find.textContaining('Aangedreven'), findsNothing);
      for (final key in [
        companyBookingCopyKey,
        companyBookingOpenKey,
        companyBookingShareKey,
      ]) {
        await tester.ensureVisible(find.byKey(key));
        await tester.tap(find.byKey(key));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byKey(companyBookingShareQrKey));
      await tester.tap(find.byKey(companyBookingShareQrKey));
      await tester.pump();
      await tester.runAsync(() async {
        for (var i = 0; qrPng == null && i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      expect(captured, {'copy': url, 'open': url, 'share': url, 'qr': url});
      expect(qrPng?.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final evidence = Platform.environment['BUSINESS_QR_EVIDENCE_DIR'];
      if (evidence != null) {
        await tester.runAsync(() async {
          await Directory(evidence).create(recursive: true);
          await File(
            '$evidence/${row.slug}-business-qr.png',
          ).writeAsBytes(qrPng!);
        });
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'unavailable company shows a friendly state and no link/QR/actions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompanyPublicBookingLinkView(
              loader: () async => throw const CompanyBookingLinkUnavailable(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('nog niet beschikbaar'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.byKey(companyBookingOpenKey), findsNothing);
      expect(find.textContaining('workers.dev'), findsNothing);
      expect(find.textContaining('FLX-'), findsNothing);
    },
  );

  testWidgets('a company change blocks an already displayed share action', (
    tester,
  ) async {
    var current = true;
    var shared = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyPublicBookingLinkView(
            loader: testBookingLink,
            scopeIsCurrent: () => current,
            shareLink: (_) async {
              shared = true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    current = false;
    await tester.tap(find.byKey(companyBookingShareKey));
    await tester.pumpAndSettle();
    expect(shared, isFalse);
    expect(find.byType(QrImageView), findsNothing);
  });
}
