import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_vehicles.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_flow.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote.dart';
import 'package:fluxidi_tracking/customer_profile_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_current_location.dart';
import 'package:http/http.dart' as http;

const _cadillac = 'vh_cadillac';
const _driver = 'drv_wotan';

LimousinePlaceLookup _formLookup() {
  return LimousinePlaceLookup(
    searchOverride: (query, language) async {
      final q = query.toLowerCase();
      if (q.contains('gent') || q.contains('ghent')) {
        return const LimousinePlaceLookupResult(
          suggestions: <LimousinePlaceSuggestion>[
            LimousinePlaceSuggestion(
              label: 'Gent, Oost-Vlaanderen, België',
              lat: 51.0543,
              lon: 3.7174,
              placeType: 'place',
              locality: 'Gent',
            ),
          ],
        );
      }
      return const LimousinePlaceLookupResult(
        suggestions: <LimousinePlaceSuggestion>[
          LimousinePlaceSuggestion(
            label: 'Koekamerstraat 48, 9688 Maarkedal, België',
            lat: 50.77205,
            lon: 3.66942,
            placeType: 'address',
            postcode: '9688',
            locality: 'Maarkedal',
          ),
          LimousinePlaceSuggestion(
            label: 'Koekamerstraat - Rue Cocambre 48a, 9600 Ronse, België',
            lat: 50.770403,
            lon: 3.672568,
            placeType: 'address',
            postcode: '9600',
            locality: 'Ronse',
          ),
        ],
      );
    },
    reverseOverride: (lat, lon, language) async {
      return const LimousinePlaceLookupResult();
    },
  );
}

CustomerProfile _profile() {
  return CustomerProfile(
    customerId: 'cus_form',
    name: 'Christophe',
    phone: '+32469788891',
    email: 'c@example.com',
    preferredPostcode: '9688',
    companyName: '',
    vatNumber: '',
    billingStreet: 'Koekamerstraat 48A',
    billingPostalCode: '9688',
    billingCity: 'Schorisse',
    billingCountry: 'BE',
    createdAt: '2026-01-01',
    updatedAt: '2026-01-01',
  );
}

CustomerBookingCompany _company() {
  return const CustomerBookingCompany(
    partnerId: 'company:TA:CA',
    tenantId: 'TA',
    companyId: 'CA',
    companyCode: 'FLX-00099',
    companyName: 'Fluxidi Isolated',
    vehicles: <Map<String, dynamic>>[
      <String, dynamic>{
        'vehicle_id': _cadillac,
        'name': 'Cadillac',
        'vehicle_type': 'sedan',
        'tier': 'premium',
        'seats': 3,
      },
    ],
  );
}

CustomerBookingQuoteClient _quotes(
  List<Map<String, dynamic>> posts, {
  Object? Function(int bookCount, Map<String, dynamic> body)? bookOverride,
}) {
  var books = 0;
  return CustomerBookingQuoteClient(
    bookingBaseUrl: 'http://127.0.0.1:8788',
    httpPost: (url, headers, body) async {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      posts.add(<String, dynamic>{'path': url.path, 'body': decoded});
      if (url.path.endsWith('/book')) {
        books += 1;
        final override = bookOverride?.call(books, decoded);
        if (override is http.Response) return override;
        if (override is Exception) throw override;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'bookingId': 'bk_form_$books',
            'assigned_vehicle_id': decoded['vehicle_id'],
            'assigned_driver_id': decoded['assigned_driver_id'],
            'pickup_iso': decoded['pickup_iso'],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode(<String, dynamic>{
          'ok': true,
          'price_available': true,
          'price_incl_vat': 80.6,
          'total_price_incl_vat': 80.6,
          'distance_km': 40.6,
          'duration_min': 41,
          'currency': 'EUR',
          'pickup_lat': decoded['from_lat'] ?? decoded['pickup_lat'],
          'pickup_lon': decoded['from_lng'] ?? decoded['pickup_lon'],
          'dropoff_lat': decoded['to_lat'] ?? decoded['dropoff_lat'],
          'dropoff_lon': decoded['to_lng'] ?? decoded['dropoff_lon'],
        }),
        200,
      );
    },
  );
}

CustomerBookingProfileGet _availabilityGet() {
  return (uri) async {
    if (uri.path.contains('availability')) {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'ok': true,
          'vehicles': <Map<String, dynamic>>[
            <String, dynamic>{
              'vehicle_id': _cadillac,
              'available': true,
              'driver_id': _driver,
              'public_display_name': 'Wotan',
            },
          ],
        }),
        200,
      );
    }
    return http.Response('skipped', 404);
  };
}

Future<void> _pumpForm(
  WidgetTester tester, {
  required CustomerBookingEntryContext entry,
  required CustomerBookingQuoteClient quotes,
  Size size = const Size(1400, 1800),
}) async {
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        home: CustomerBookingFlow(
          entry: entry,
          language: AppLanguage.nl,
          lookup: _formLookup(),
          locationPlatform: LimousineCurrentLocationPlatform(
            isLocationServiceEnabled: () async => false,
          ),
          quoteClient: quotes,
          autoResolveGps: false,
          profile: _profile(),
          profileGet: _availabilityGet(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _maybeConfirmPickup(WidgetTester tester) async {
  expect(find.textContaining('48A'), findsWidgets);
  Finder confirm = find.byKey(kCustomerBookingAddressConfirmKey);
  for (var i = 0; i < 10 && confirm.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    confirm = find.byKey(kCustomerBookingAddressConfirmKey);
  }
  if (confirm.evaluate().isEmpty) {
    confirm = find.byKey(kCustomerBookingAddressConfirmMapKey);
  }
  expect(
    confirm,
    findsWidgets,
    reason: 'pickup confirm control missing for 48A',
  );
  await tester.tap(confirm.first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  if (find.byKey(kCustomerBookingConfirmPickupBannerKey).evaluate().isNotEmpty) {
    await tester.tap(confirm.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
  expect(find.textContaining('48A'), findsWidgets);
  expect(find.textContaining('Ronse'), findsNothing);
  expect(find.byKey(kCustomerBookingConfirmPickupBannerKey), findsNothing);
}

Future<void> _selectCadillac(WidgetTester tester) async {
  Finder cadillac = find.byKey(customerBookingVehicleKey(_cadillac));
  for (var i = 0; i < 8 && cadillac.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    cadillac = find.byKey(customerBookingVehicleKey(_cadillac));
  }
  expect(
    cadillac,
    findsOneWidget,
    reason: 'Cadillac offer missing after profile address and destination',
  );
  await tester.tap(cadillac);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _payAndBook(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(kCustomerBookingConfirmKey));
  await tester.tap(find.byKey(kCustomerBookingConfirmKey));
  await tester.pumpAndSettle();
  if (find.byKey(kCustomerBookingPaymentPageKey).evaluate().isEmpty) {
    final error = find.byKey(kCustomerBookingSubmitErrorKey);
    final bits = tester.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').where((t) => t.trim().isNotEmpty).take(20).join(' | ');
    fail(
      'payment page missing; submitError=${error.evaluate().isNotEmpty} texts=$bits',
    );
  }
  await tester.ensureVisible(find.byKey(kCustomerBookingPaymentConfirmKey));
  await tester.tap(find.byKey(kCustomerBookingPaymentConfirmKey));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fluxidi_form_chain_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('taxi form sends its own 48A pin, Cadillac and one idempotency key', (
    tester,
  ) async {
    final posts = <Map<String, dynamic>>[];
    String? firstKey;
    await _pumpForm(
      tester,
      entry: CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        company: _company(),
        lockCompany: true,
        destination: const CustomerBookingPlace(
          address: 'Gent, Oost-Vlaanderen, België',
          latitude: 51.0543,
          longitude: 3.7174,
        ),
      ),
      quotes: _quotes(
        posts,
        bookOverride: (count, body) {
          firstKey ??= (body['idempotency_key'] ?? '').toString();
          if (count == 1) {
            return http.ClientException('connection refused');
          }
          return null;
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await _maybeConfirmPickup(tester);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.textContaining('48A'), findsWidgets);
    expect(find.textContaining('Ronse'), findsNothing);
    await _selectCadillac(tester);
    await _payAndBook(tester);
    expect(find.byKey(kCustomerBookingSubmitErrorKey), findsOneWidget);
    await _payAndBook(tester);
    final books = posts
        .where((item) => (item['path'] as String).endsWith('/book'))
        .map((item) => item['body'] as Map<String, dynamic>)
        .toList();
    expect(books, hasLength(2));
    for (final body in books) {
      expect(body['from'], contains('48A'));
      expect(body['from'].toString().contains('Ronse'), isFalse);
      expect(body['to'].toString().toLowerCase(), contains('gent'));
      expect(body['vehicle_id'] ?? body['preferred_vehicle_id'], _cadillac);
      expect(body['from_lat'], isNotNull);
      expect(body['from_lat'], isNot(50.770403));
      expect(body['from_lng'] ?? body['from_lon'], isNot(3.672568));
      expect(body['idempotency_key'], firstKey);
      expect(body['idempotency_key'], isNotEmpty);
    }
    expect(find.byKey(kCustomerBookingSuccessKey), findsOneWidget);
    expect(find.textContaining('bk_form_2'), findsWidgets);
  });

  testWidgets('changed pickup does not keep the previous quote coordinates', (
    tester,
  ) async {
    final posts = <Map<String, dynamic>>[];
    await _pumpForm(
      tester,
      entry: CustomerBookingEntryContext(
        kind: CustomerBookingKind.taxi,
        company: _company(),
        lockCompany: true,
        destination: const CustomerBookingPlace(
          address: 'Gent, Oost-Vlaanderen, België',
          latitude: 51.0543,
          longitude: 3.7174,
        ),
      ),
      quotes: _quotes(posts),
    );
    await _maybeConfirmPickup(tester);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(kCustomerBookingPickupKey), findsOneWidget);
    await tester.enterText(
      find.byKey(kCustomerBookingPickupKey),
      'Grote Markt 1, 9600 Ronse',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.ensureVisible(find.byKey(kCustomerBookingConfirmKey));
    await tester.tap(find.byKey(kCustomerBookingConfirmKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kCustomerBookingPaymentPageKey), findsNothing);
    expect(
      posts.where((item) => (item['path'] as String).endsWith('/book')),
      isEmpty,
    );
  });

  testWidgets('airport form keeps 48A and writes the catalog airport', (
    tester,
  ) async {
    final posts = <Map<String, dynamic>>[];
    await _pumpForm(
      tester,
      entry: CustomerBookingEntryContext(
        kind: CustomerBookingKind.airport,
        company: _company(),
        lockCompany: true,
      ),
      quotes: _quotes(posts),
    );
    expect(find.byKey(kCustomerBookingAirplaneVisualKey), findsOneWidget);
    expect(find.textContaining('48A'), findsWidgets);
    await _maybeConfirmPickup(tester);
    expect(find.byKey(customerBookingAirportCardKey('BRU')), findsOneWidget);
    await tester.tap(find.byKey(customerBookingAirportCardKey('BRU')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await _selectCadillac(tester);
    await _payAndBook(tester);
    final books = posts
        .where((item) => (item['path'] as String).endsWith('/book'))
        .map((item) => item['body'] as Map<String, dynamic>)
        .toList();
    expect(books, isNotEmpty);
    final body = books.last;
    expect(body['from'], contains('48A'));
    expect(body['from'].toString().contains('Ronse'), isFalse);
    expect(body['from_lat'], isNot(50.770403));
    expect(body['vehicle_id'] ?? body['preferred_vehicle_id'], _cadillac);
    expect(
      body['airport_iata'] == 'BRU' ||
          body['to'].toString().contains('BRU') ||
          body['to'].toString().toLowerCase().contains('brussel'),
      isTrue,
    );
  });
}
