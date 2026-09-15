import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_address_field.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

void main() {
  test('Koekamerstraat 48A stays a full street address, not Maarkedal', () {
    const address = CompanyCustomerAddress(
      label: 'Thuis',
      line1: 'Koekamerstraat 48A',
      city: 'Schorisse',
      postalCode: '9688',
      countryCode: 'BE',
      lat: 50.77,
      lon: 3.61,
    );
    final value = companyAddressValueFromSaved(address);
    expect(value.displayText, contains('Koekamerstraat 48A'));
    expect(value.displayText, contains('9688'));
    expect(value.displayText, contains('Schorisse'));
    expect(value.displayText.contains('Maarkedal'), isFalse);
    expect(value.lat, 50.77);
    expect(value.lon, 3.61);
    final parsed = parseCompanyPlanCanonicalAddress(value.displayText);
    expect(parsed.street, 'Koekamerstraat');
    expect(parsed.houseNumber, '48A');
    expect(parsed.postalCode, '9688');
    expect(parsed.city, 'Schorisse');
    expect(
      limousineAddressIsMoreSpecific(
        'Koekamerstraat 48A, 9688 Schorisse',
        '9688, Maarkedal',
      ),
      isTrue,
    );
    expect(
      limousinePreferCanonicalLabel(
        original: 'Koekamerstraat 48A, 9688 Schorisse',
        suggestion: '9688, Maarkedal, Oost-Vlaanderen, België',
      ),
      'Koekamerstraat 48A, 9688 Schorisse',
    );
  });

  test('stored incomplete text stays incomplete, complete manual stays manual', () {
    final gent = companyAddressValueFromStored(text: 'gent');
    expect(gent.acceptance, LimousineAddressAcceptance.incomplete);
    expect(companyAddressIsComplete(gent), isFalse);
    final manual = companyAddressValueFromStored(text: 'Korenmarkt 1, Gent');
    expect(manual.acceptance, LimousineAddressAcceptance.manualFallback);
    expect(companyAddressIsComplete(manual), isTrue);
    final selected = companyAddressValueFromStored(
      text: 'Kunstlaan 44, 1000 Brussel, België',
      lat: 50.843,
      lon: 4.368,
      placeId: 'place.kunstlaan',
    );
    expect(selected.acceptance, LimousineAddressAcceptance.selected);
    expect(companyAddressReviewLine(gent, AppLanguage.nl), contains('Onvolledig'));
    expect(companyAddressReviewLine(manual, AppLanguage.nl), contains('Handmatig'));
    expect(companyAddressReviewLine(selected, AppLanguage.nl), contains('voorstel'));
  });

  test('saved Spanish customer address does not become a country filter', () {
    const address = CompanyCustomerAddress(
      label: 'Kantoor',
      line1: 'Paseo de la Castellana 12',
      postalCode: '28046',
      city: 'Madrid',
      countryCode: 'ES',
    );
    final value = companyAddressValueFromSaved(address);
    expect(value.acceptance, LimousineAddressAcceptance.manualFallback);
    expect(value.displayText.contains('ES'), isTrue);
    final uri = limousineMapboxPlacesUri(
      query: 'gent',
      token: 'token',
      country: '',
    );
    expect(uri.queryParameters.containsKey('country'), isFalse);
    expect(uri.toString().contains('country=es'), isFalse);
    expect(uri.toString().contains('proximity='), isFalse);
  });

  test('saved customer addresses stay structured and unverified', () {
    const address = CompanyCustomerAddress(
      label: 'Thuis',
      line1: 'Kunstlaan 44',
      postalCode: '1000',
      city: 'Brussel',
      countryCode: 'BE',
    );
    final value = companyAddressValueFromSaved(address);
    expect(value.displayText.contains('Kunstlaan 44'), isTrue);
    expect(value.displayText.contains('1000'), isTrue);
    expect(value.acceptance, LimousineAddressAcceptance.manualFallback);
    expect(value.lat, isNull);
    expect(value.lon, isNull);
  });

  test('editing after a selected suggestion drops old coordinates', () async {
    final lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async {
        return const LimousinePlaceLookupResult(
          suggestions: <LimousinePlaceSuggestion>[
            LimousinePlaceSuggestion(
              label: 'Kunstlaan 44, 1000 Brussel, België',
              lat: 50.843,
              lon: 4.368,
              placeId: 'place.kunstlaan',
            ),
          ],
        );
      },
    );
    addTearDown(lookup.dispose);
    final controller = LimousineAddressFieldController(
      lookup: lookup,
      fieldId: 'quote_pickup',
      debounce: Duration.zero,
    );
    addTearDown(controller.dispose);
    controller.selectSuggestion(
      const LimousinePlaceSuggestion(
        label: 'Kunstlaan 44, 1000 Brussel, België',
        lat: 50.843,
        lon: 4.368,
        placeId: 'place.kunstlaan',
      ),
    );
    expect(controller.value.acceptance, LimousineAddressAcceptance.selected);
    expect(controller.value.lat, 50.843);
    controller.onTextChanged('Kunstlaan 44 gewijzigd');
    expect(controller.value.acceptance, LimousineAddressAcceptance.incomplete);
    expect(controller.value.lat, isNull);
    expect(controller.value.placeId, isNull);
  });

  testWidgets('saved addresses stay hidden until the field is focused', (
    tester,
  ) async {
    final lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async {
        return const LimousinePlaceLookupResult();
      },
    );
    addTearDown(lookup.dispose);
    final controller = LimousineAddressFieldController(
      lookup: lookup,
      fieldId: 'quote_pickup',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyAddressField(
            controller: controller,
            label: 'Vertrek',
            language: AppLanguage.nl,
            savedAddresses: const [
              CompanyCustomerAddress(
                label: 'Thuis',
                line1: 'Koekamerstraat 48A',
                city: 'Schorisse',
                postalCode: '9688',
                countryCode: 'BE',
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text(kCompanySavedAddresses.of(AppLanguage.nl)), findsNothing);
    expect(find.textContaining('Koekamerstraat 48A'), findsNothing);
    await tester.tap(find.byKey(limousineAddressInputKey('quote_pickup')));
    await tester.pumpAndSettle();
    expect(find.text(kCompanySavedAddresses.of(AppLanguage.nl)), findsNothing);
    expect(find.textContaining('Koekamerstraat 48A'), findsOneWidget);
  });

  testWidgets('search distinguishes loading, empty and error', (tester) async {
    var fail = true;
    final lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (fail) {
          return const LimousinePlaceLookupResult(hadError: true);
        }
        return const LimousinePlaceLookupResult();
      },
    );
    addTearDown(lookup.dispose);
    final controller = LimousineAddressFieldController(
      lookup: lookup,
      fieldId: 'quote_pickup',
      debounce: Duration.zero,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyAddressField(
            controller: controller,
            label: 'Vertrek',
            language: AppLanguage.nl,
          ),
        ),
      ),
    );
    controller.textController.text = 'abcstraat 1';
    controller.onTextChanged('abcstraat 1');
    await tester.pump();
    await tester.pump(Duration.zero);
    expect(find.byKey(limousineAddressLoadingKey('quote_pickup')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 30));
    expect(controller.hadError, isTrue);
    expect(find.byKey(limousineAddressNoResultKey('quote_pickup')), findsOneWidget);
    expect(find.byKey(limousineAddressRetryKey('quote_pickup')), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(limousineAddressRetryKey('quote_pickup')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(controller.hadError, isFalse);
    expect(find.byKey(limousineAddressNoResultKey('quote_pickup')), findsOneWidget);
    expect(find.byKey(limousineAddressRetryKey('quote_pickup')), findsOneWidget);
  });
}
