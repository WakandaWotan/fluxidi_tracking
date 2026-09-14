import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:fluxidi_tracking/main.dart' as app;
import 'package:fluxidi_tracking/nearby/public_fixed_prices.dart';
import 'package:fluxidi_tracking/nearby/stap3_flow_keys.dart';
import 'package:fluxidi_tracking/partner_public_profile_page.dart';

const _worker = 'http://127.0.0.1:8788';
const _companyId = 'demo_company_p0';
const _token = 'cst_local_demo_synthetic';
const _markerPath = '.qa-local/stap3/it_maarkedal_ronse_booking_id.txt';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'desktop IT: public Maarkedal–Ronse fare books €35 on the local Worker',
    (tester) async {
      final existing = await _existingStap3Booking();
      await app.main();
      await tester.pump(const Duration(milliseconds: 500));
      await _pumpUntilAny(
        tester,
        <Finder>[
          find.byKey(kFluxidiBackToStartKey, skipOffstage: false),
          find.byKey(kRoleEntryCustomerKey),
          find.byKey(const Key('business_home_page')),
          find.textContaining('Klantenbeheer'),
          find.textContaining('Customer management'),
          find.textContaining('Bedrijfsdashboard'),
          find.textContaining('Company dashboard'),
        ],
        timeout: const Duration(seconds: 30),
        failOnFrameworkError: false,
        failOnVisibleError: false,
      );

      if (existing != null) {
        await _openCompanyBooking(tester, existing);
        _assertCompanyBookingDetail(tester);
        return;
      }

      if (find.byKey(kRoleEntryCustomerKey).evaluate().isEmpty) {
        await _goToRoleEntryFromCompanyHome(tester);
      }

      await tester.tap(find.byKey(kRoleEntryCustomerKey));
      await _pumpUntil(tester, find.byKey(kCustomerEntryNewKey));
      await tester.tap(find.byKey(kCustomerEntryNewKey));
      await _pumpUntil(tester, find.byKey(kCustomerOnboardingLaterKey));
      await tester.tap(find.byKey(kCustomerOnboardingLaterKey));
      await _pumpUntil(tester, find.byKey(kCustomerHomeTaxisNavKey));
      await tester.tap(find.byKey(kCustomerHomeTaxisNavKey));
      await _pumpUntil(tester, find.byKey(kNearbyPostalCodeFieldKey));

      await tester.enterText(find.byKey(kNearbyPostalCodeFieldKey), '9688');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(kNearbySearchPartnersKey));
      await _pumpUntil(
        tester,
        find.byKey(nearbyPartnerProfileKey(kStap3LocalPartnerId)),
      );
      await tester.tap(find.byKey(nearbyPartnerProfileKey(kStap3LocalPartnerId)));
      await _pumpUntil(tester, find.byType(PartnerPublicProfilePage));

      final bookKey = publicFixedPriceBookKey(kStap3MaarkedalRonseRuleId);
      await _reveal(tester, find.byKey(bookKey));
      await tester.tap(find.byKey(bookKey).hitTestable());
      await _pumpUntil(tester, find.byKey(kCalculatorFromFieldKey));

      await _reveal(tester, find.byKey(kCalculatorFromFieldKey));
      await tester.enterText(
        find.byKey(kCalculatorFromFieldKey),
        kStap3DesktopItPickupQuery,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await _pumpUntil(
        tester,
        find.textContaining('Koekamerstraat'),
        timeout: const Duration(seconds: 20),
      );
      final suggestion = find.byWidgetPredicate((widget) {
        return widget is ListTile &&
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith(
              'calculator_place_suggestion_',
            );
      });
      expect(
        suggestion,
        findsWidgets,
        reason: 'Mapbox must return a real address suggestion',
      );
      await tester.tap(suggestion.first);
      await tester.pump(const Duration(milliseconds: 300));

      await _pickFuturePickup(tester);

      await _reveal(tester, find.byKey(kCalculatorTierFieldKey));
      await tester.tap(find.byKey(kCalculatorTierFieldKey).hitTestable());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Premium').last);
      await tester.pump(const Duration(milliseconds: 300));

      await _reveal(tester, find.byKey(kCalculatorQuoteKey));
      await tester.tap(find.byKey(kCalculatorQuoteKey).hitTestable());
      await _pumpUntil(
        tester,
        find.textContaining('35'),
        timeout: const Duration(seconds: 25),
      );
      expect(find.textContaining('35'), findsWidgets);
      expect(
        find.byKey(kCalculatorBookKey, skipOffstage: false),
        findsOneWidget,
      );
      if (find.textContaining('No vehicle').evaluate().isNotEmpty ||
          find.textContaining('Geen voertuig').evaluate().isNotEmpty) {
        fail(
          '€35 quote is not bookable at the chosen pickup. ${await _visibleTreeSummary(tester)}',
        );
      }

      var bookingId = existing;
      if (bookingId == null) {
        await _reveal(
          tester,
          find.byKey(kCalculatorBookKey, skipOffstage: false),
        );
        await tester.tap(find.byKey(kCalculatorBookKey).hitTestable());
        await _pumpUntil(
          tester,
          find.byKey(kBookingConfirmButtonKey, skipOffstage: false),
        );
        await _reveal(
          tester,
          find.byKey(kBookingConfirmNameKey, skipOffstage: false),
        );
        await tester.enterText(
          find.byKey(kBookingConfirmNameKey, skipOffstage: false),
          kStap3DesktopItCustomerName,
        );
        await tester.enterText(
          find.byKey(kBookingConfirmPhoneKey, skipOffstage: false),
          kStap3DesktopItPhone,
        );
        await tester.enterText(
          find.byKey(kBookingConfirmEmailKey, skipOffstage: false),
          kStap3DesktopItEmail,
        );
        await _reveal(
          tester,
          find.byKey(kBookingConfirmButtonKey, skipOffstage: false),
        );
        await tester.tap(find.byKey(kBookingConfirmButtonKey).hitTestable());
        await tester.pump(const Duration(seconds: 2));
        for (var i = 0; i < 20; i += 1) {
          await tester.pump(const Duration(milliseconds: 300));
          _failIfVisibleError(tester);
          bookingId = await _existingStap3Booking();
          if (bookingId != null) break;
        }
        expect(
          bookingId,
          isNotNull,
          reason: 'Local Worker did not create the €35 Maarkedal–Ronse booking',
        );
        await _writeMarker(bookingId!);
      }

      await _openCompanyBooking(tester, bookingId!);
      _assertCompanyBookingDetail(tester);
    },
  );
}

void _assertCompanyBookingDetail(WidgetTester tester) {
  expect(
    find.byKey(kCompanyBookingDetailRouteKey, skipOffstage: false),
    findsOneWidget,
  );
  final route = tester.widget<Text>(
    find.byKey(kCompanyBookingDetailRouteKey, skipOffstage: false),
  );
  expect(route.data, contains('Ronse'));
  expect(
    find.byKey(kCompanyBookingDetailAmountKey, skipOffstage: false),
    findsOneWidget,
  );
  final amount = tester.widget<Text>(
    find.byKey(kCompanyBookingDetailAmountKey, skipOffstage: false),
  );
  expect(amount.data, contains('35'));
}

Future<void> _goToRoleEntryFromCompanyHome(WidgetTester tester) async {
  final back = find.byKey(kFluxidiBackToStartKey, skipOffstage: false);
  if (back.evaluate().isEmpty) {
    fail(
      'Company home opened but back-to-start was missing. ${await _visibleTreeSummary(tester)}',
    );
  }
  await _reveal(tester, back);
  await tester.tap(back.first);
  await _pumpUntil(tester, find.byKey(kRoleEntryCustomerKey));
}

Future<void> _pickFuturePickup(WidgetTester tester) async {
  await _reveal(tester, find.byKey(kCalculatorPickupTimeKey));
  await tester.tap(find.byKey(kCalculatorPickupTimeKey).hitTestable());
  await tester.pump(const Duration(milliseconds: 500));
  final now = DateTime.now();
  final target = DateTime(now.year, now.month, now.day).add(
    const Duration(days: 1),
  );
  if (find.byType(DatePickerDialog).evaluate().isNotEmpty) {
    if (target.month != now.month) {
      final nextMonth = <Finder>[
        find.byTooltip('Next month'),
        find.byTooltip('Volgende maand'),
        find.byTooltip('Mois suivant'),
        find.byTooltip('Mes siguiente'),
      ].firstWhere(
        (finder) => finder.evaluate().isNotEmpty,
        orElse: () => find.byIcon(Icons.chevron_right),
      );
      await tester.tap(nextMonth.last);
      await tester.pump(const Duration(milliseconds: 300));
    }
    final day = find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.text('${target.day}'),
    );
    if (day.evaluate().isEmpty) {
      fail('Date picker did not show ${target.day}. ${await _visibleTreeSummary(tester)}');
    }
    await tester.tap(day.first);
    await tester.pump(const Duration(milliseconds: 200));
  }
  final ok = find.widgetWithText(TextButton, 'OK');
  if (ok.evaluate().isNotEmpty) {
    await tester.tap(ok.last);
    await tester.pump(const Duration(milliseconds: 400));
  }
  if (find.byType(TimePickerDialog).evaluate().isNotEmpty &&
      ok.evaluate().isNotEmpty) {
    await tester.tap(ok.last);
    await tester.pump(const Duration(milliseconds: 400));
  }
}

Future<void> _tapReachable(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  final hit = finder.hitTestable();
  if (hit.evaluate().isNotEmpty) {
    await tester.tap(hit);
    return;
  }
  await tester.tap(finder.first, warnIfMissed: false);
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    fail('Nothing to reveal for $finder. ${await _visibleTreeSummary(tester)}');
  }
  final element = finder.evaluate().first;
  final scrollable = Scrollable.maybeOf(element);
  if (scrollable != null) {
    final box = tester.renderObject(finder.first);
    await scrollable.position.ensureVisible(box, alignment: 0.35);
    await tester.pump();
    for (var i = 0; i < 10; i += 1) {
      if (finder.hitTestable().evaluate().isNotEmpty) {
        return;
      }
      final next = (scrollable.position.pixels + 240).clamp(
        scrollable.position.minScrollExtent,
        scrollable.position.maxScrollExtent,
      );
      if (next == scrollable.position.pixels) break;
      await scrollable.position.moveTo(next);
      await tester.pump();
    }
  }
  await tester.ensureVisible(finder.first);
  await tester.pump();
}

Future<String> _visibleTreeSummary(WidgetTester tester) async {
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
      .where((value) => value.trim().isNotEmpty)
      .take(40)
      .join(' | ');
  return 'Visible text: $texts';
}

Future<void> _openCompanyBooking(WidgetTester tester, String bookingId) async {
  final planningKey = const Key('brand_signature_action_planning');
  if (find.byKey(planningKey, skipOffstage: false).evaluate().isEmpty) {
  for (var i = 0; i < 8; i += 1) {
    if (find.byKey(kRoleEntryBusinessKey).evaluate().isNotEmpty) {
      break;
    }
    if (find.byIcon(Icons.keyboard_return_rounded).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.keyboard_return_rounded));
      await tester.pump(const Duration(milliseconds: 500));
      continue;
    }
    if (find.byKey(kFluxidiBackToStartKey, skipOffstage: false).evaluate().isNotEmpty) {
      await _goToRoleEntryFromCompanyHome(tester);
      break;
    }
    final back = find.byIcon(Icons.arrow_back);
    if (back.evaluate().isEmpty) {
      break;
    }
    await tester.tap(back.first);
    await tester.pump(const Duration(milliseconds: 400));
  }
  await _pumpUntilAny(
    tester,
    <Finder>[
      find.byKey(kFluxidiBackToStartKey, skipOffstage: false),
      find.byKey(kRoleEntryBusinessKey),
      find.byKey(planningKey, skipOffstage: false),
    ],
    failOnFrameworkError: false,
    failOnVisibleError: false,
  );
  if (find.byKey(planningKey, skipOffstage: false).evaluate().isEmpty) {
    if (find.byKey(kRoleEntryBusinessKey).evaluate().isEmpty) {
      await _goToRoleEntryFromCompanyHome(tester);
    }
    await tester.tap(find.byKey(kRoleEntryBusinessKey));
  }
  }
  await _pumpUntil(
    tester,
    find.byKey(const Key('brand_signature_action_planning'), skipOffstage: false),
    failOnFrameworkError: false,
    failOnVisibleError: false,
  );
  await _reveal(
    tester,
    find.byKey(const Key('brand_signature_action_planning'), skipOffstage: false),
  );
  await _tapReachable(
    tester,
    find.byKey(const Key('brand_signature_action_planning'), skipOffstage: false),
  );
  final row = find.byKey(companyBookingRowKey(bookingId), skipOffstage: false);
  final open = find.byKey(
    Key('company_booking_overview_open_$bookingId'),
    skipOffstage: false,
  );
  await _pumpUntilAny(
    tester,
    <Finder>[
      row,
      open,
      find.textContaining(kStap3DesktopItCustomerName),
    ],
    timeout: const Duration(seconds: 30),
    failOnFrameworkError: false,
    failOnVisibleError: false,
  );
  final target = open.evaluate().isNotEmpty
      ? open
      : find.textContaining(kStap3DesktopItCustomerName);
  if (target.evaluate().isEmpty) {
    fail(
      'Company bookings list did not show $bookingId. ${await _visibleTreeSummary(tester)}',
    );
  }
  await _reveal(tester, target);
  await _tapReachable(tester, open.evaluate().isNotEmpty ? open : target);
  await _pumpUntil(
    tester,
    find.byKey(kCompanyBookingDetailAmountKey, skipOffstage: false),
    failOnFrameworkError: false,
    failOnVisibleError: false,
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  bool failOnFrameworkError = true,
  bool failOnVisibleError = true,
}) {
  return _pumpUntilAny(
    tester,
    <Finder>[finder],
    timeout: timeout,
    failOnFrameworkError: failOnFrameworkError,
    failOnVisibleError: failOnVisibleError,
  );
}

Future<void> _pumpUntilAny(
  WidgetTester tester,
  List<Finder> finders, {
  Duration timeout = const Duration(seconds: 20),
  bool failOnFrameworkError = true,
  bool failOnVisibleError = true,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    _failIfVisibleError(
      tester,
      failOnFrameworkError: failOnFrameworkError,
      failOnVisibleError: failOnVisibleError,
    );
    for (final finder in finders) {
      if (finder.evaluate().isNotEmpty) return;
    }
  }
  fail(
    'Timed out waiting for $finders. Last exception: ${tester.takeException()}. ${await _visibleTreeSummary(tester)}',
  );
}

void _failIfVisibleError(
  WidgetTester tester, {
  bool failOnFrameworkError = true,
  bool failOnVisibleError = true,
}) {
  final thrown = tester.takeException();
  if (thrown != null) {
    // ignore: avoid_print
    print('IT Flutter exception: $thrown');
    File('.qa-local/stap3/it_last_exception.txt').writeAsStringSync('$thrown');
    if (failOnFrameworkError) {
      fail('Unexpected Flutter exception: $thrown');
    }
  }
  if (!failOnVisibleError) {
    return;
  }
  final errorTexts = find.byWidgetPredicate((widget) {
    if (widget is! Text) return false;
    final value = widget.data ?? '';
    return value.contains('Exception') ||
        value.contains('fixed_price_needs_more_detail') ||
        value.startsWith('Fout') ||
        value.contains('Error:');
  });
  if (errorTexts.evaluate().isNotEmpty) {
    final text = tester.widget<Text>(errorTexts.first);
    fail('Unexpected visible error: ${text.data}');
  }
}

Future<void> _assertWorkerUp() async {
  Object? lastError;
  for (var i = 0; i < 8; i += 1) {
    try {
      final res = await http
          .get(Uri.parse('$_worker/local/health'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200 && res.body.contains('"ok":true')) {
        return;
      }
      lastError = 'health ${res.statusCode} ${res.body}';
    } catch (error) {
      lastError = error;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  fail('Local Worker on $_worker is not reachable: $lastError');
}

Future<String?> _existingStap3Booking() async {
  await _assertWorkerUp();
  final marked = await _readMarker();
  if (marked != null) {
    final one = await http
        .get(
          Uri.parse('$_worker/bookings/$marked').replace(
            queryParameters: <String, String>{
              'tenant_id': _companyId,
              'company_id': _companyId,
            },
          ),
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $_token',
          },
        )
        .timeout(const Duration(seconds: 8));
    if (one.statusCode == 200 && one.body.contains('35')) {
      return marked;
    }
  }
  final res = await http
      .get(
        Uri.parse('$_worker/bookings').replace(
          queryParameters: <String, String>{
            'tenant_id': _companyId,
            'company_id': _companyId,
            'limit': '80',
            'include_history': '1',
          },
        ),
        headers: <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer $_token',
        },
      )
      .timeout(const Duration(seconds: 8));
  if (res.statusCode != 200) {
    fail('Local Worker bookings list failed: ${res.statusCode} ${res.body}');
  }
  final decoded = jsonDecode(res.body);
  final items = decoded is Map ? decoded['items'] : decoded;
  if (items is! List) return null;
  for (final raw in items) {
    if (raw is! Map) continue;
    final name = '${raw['customer_name'] ?? raw['customerName'] ?? ''}';
    final from = '${raw['from'] ?? raw['from_address'] ?? ''}';
    final to = '${raw['to'] ?? raw['to_address'] ?? ''}';
    final price = '${raw['price_incl_vat'] ?? raw['price'] ?? raw['amount'] ?? ''}';
    final id = '${raw['booking_id'] ?? raw['id'] ?? ''}';
    if (name.contains(kStap3DesktopItCustomerName) &&
        price.contains('35') &&
        (from.contains('Maarkedal') ||
            from.contains('Schorisse') ||
            from.contains('9688')) &&
        to.contains('Ronse') &&
        id.isNotEmpty) {
      await _writeMarker(id);
      return id;
    }
  }
  return null;
}

Future<String?> _readMarker() async {
  final file = File(_markerPath);
  if (!file.existsSync()) return null;
  final id = file.readAsStringSync().trim();
  return id.isEmpty ? null : id;
}

Future<void> _writeMarker(String bookingId) async {
  final file = File(_markerPath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(bookingId);
}
