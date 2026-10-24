import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_customer/screens/customer_home_screen.dart';
import 'package:fluxidi_customer_core/fluxidi_customer_core.dart';
import 'package:http/http.dart' as http;

FluxidiAddressSearchClient _client({int count = 2}) {
  return FluxidiAddressSearchClient(
    token: 'test-token',
    httpGet: (uri) async {
      final features = <Map<String, dynamic>>[
        for (var i = 0; i < count; i++)
          <String, dynamic>{
            'id': 'address.ronse.$i',
            'place_type': <String>['address'],
            'place_name': 'Ronse result $i, Oost-Vlaanderen, België',
            'text': 'Ronse $i',
            'center': <double>[3.605 + i * 0.01, 50.746],
          },
      ];
      return http.Response(
        jsonEncode(<String, dynamic>{'features': features}),
        200,
      );
    },
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  double keyboard = 0,
  int suggestionCount = 2,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        resizeToAvoidBottomInset: true,
        body: CustomerHomeScreen(addressClient: _client(count: suggestionCount)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('suggestions sit under the field and stay in the inset body', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(800, 1280),
      keyboard: 420,
      suggestionCount: 8,
    );
    await tester.enterText(
      find.byKey(const Key('customer_home_destination')),
      'ronse',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    final field = tester.getRect(
      find.byKey(const Key('customer_home_destination')),
    );
    final suggestions = tester.getRect(
      find.byKey(const Key('customer_home_suggestions')),
    );
    final book = tester.getRect(find.byKey(const Key('customer_home_book_taxi')));
    expect(suggestions.top, greaterThan(field.bottom - 1));
    expect(book.top, greaterThan(suggestions.bottom - 1));
    expect(suggestions.height, lessThanOrEqualTo(241));
  });

  testWidgets('picking a suggestion keeps the typed label', (tester) async {
    await _pump(tester, size: const Size(390, 844), keyboard: 320);
    await tester.enterText(
      find.byKey(const Key('customer_home_destination')),
      'ronse',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final tile = find
        .descendant(
          of: find.byKey(const Key('customer_home_suggestions')),
          matching: find.byType(ListTile),
        )
        .first;
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('customer_home_suggestions')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('customer_home_destination')))
          .controller
          ?.text,
      isNotEmpty,
    );
  });
}
