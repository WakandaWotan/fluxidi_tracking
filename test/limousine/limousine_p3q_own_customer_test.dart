import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_external_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_external_quote_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_external_quote_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_presentation.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_presentation.dart';
import 'package:fluxidi_tracking/limousine/limousine_taxi_qr_isolation.dart';

VehicleProfile _vehicle({
  required String id,
  required String name,
  String category = '',
  int pax = 8,
}) {
  return VehicleProfile(
    id: id,
    vehicleName: name,
    brandModel: name,
    licensePlate: '9-LMO-001',
    color: 'black',
    passengerCapacity: pax,
    luggageCapacity: 4,
    tierId: 'comfort',
    isActive: true,
    driverId: null,
    companyId: 'company_limo_p3q',
    primaryPhotoRef: '',
    galleryPhotoRefs: const <String>[],
    serviceCategory: category,
    serviceClassId: category == 'limousine' ? 'stretch_limousine' : '',
  );
}

Map<String, dynamic> _quoteOffer() {
  return <String, dynamic>{
    'offer_id': 'off_quote',
    'enabled': true,
    'published': true,
    'vehicle_id': 'veh_limo',
    'service_class_id': 'stretch_limousine',
    'target_type': LimousineOfferTarget.vehicle,
    'price_presentation': LimousinePricePresentation.quoteRequired,
    'currency': 'EUR',
    'paid_extras': <Map<String, dynamic>>[
      <String, dynamic>{'extra_id': 'extra_red_carpet', 'label': 'Red carpet'},
    ],
  };
}

Map<String, dynamic> _item({
  String id = 'limq_own',
  String state = 'customer_acceptance_required',
  Map<String, dynamic>? extra,
}) {
  return <String, dynamic>{
    'quote_request_id': id,
    'state': state,
    'revision': 3,
    'origin_channel': kLimousineExternalOriginChannel,
    'contact_display_name': 'Ada Lovelace',
    'vehicle_snapshot': <String, dynamic>{'public_name': 'Party Limo'},
    'scheduled_pickup_iso': '2026-10-01T16:00:00Z',
    'fulfilment': <String, dynamic>{
      'from': 'Korenmarkt 1, Gent',
      'to': 'Graslei, Gent',
    },
    'quotation_total_incl_vat_cents': 106000,
    'quotation_currency': 'EUR',
    'quote': <String, dynamic>{
      'total_incl_vat_cents': 106000,
      'total_ex_vat_cents': 100000,
      'vat_amount_cents': 6000,
      'currency': 'EUR',
      'vat_treatment': 'excl',
      'vat_rate': 0.06,
      'expires_at': '2099-01-01T00:00:00Z',
      'terms_revision': 3,
    },
    'external_delivery': <String, dynamic>{
      'invitation_state': 'link_created',
      'link_created_at': '2026-08-24T10:00:00.000Z',
    },
    'email': 'hidden@example.test',
    'phone': '+32470000000',
    'customer_name': 'Ada',
    ...?extra,
  };
}

class _FakeGateway
    implements LimousineQuoteInboxGateway, LimousineExternalQuoteGateway {
  _FakeGateway({this.record});

  LimousineQuoteRequest? record;
  int createCalls = 0;
  LimousineExternalJourneyDraft? lastJourney;
  LimousineExternalContactSummary? lastContact;
  final List<String> invitationActions = <String>[];
  String? lastSharedUrl;
  String? lastCopiedUrl;

  @override
  Future<LimousineQuoteInboxPageData> list({
    int pageSize = kLimousineQuoteInboxPageDefault,
    String? state,
    String? cursor,
    String? updatedSince,
    String? tenantId,
    String? companyId,
  }) async {
    return LimousineQuoteInboxPageData(
      items: record == null
          ? const <LimousineQuoteRequest>[]
          : <LimousineQuoteRequest>[record!],
    );
  }

  @override
  Future<LimousineQuoteRequest> detail(
    String quoteRequestId, {
    String? tenantId,
    String? companyId,
  }) async {
    return record ?? LimousineQuoteRequest.fromJson(_item(id: quoteRequestId));
  }

  @override
  Future<LimousineQuoteRespondResult> respond({
    required String quoteRequestId,
    required String action,
    required int expectedRevision,
    Map<String, dynamic>? quote,
    LimousineDeclineDraft? decline,
    String? tenantId,
    String? companyId,
  }) async {
    return LimousineQuoteRespondResult(record: record);
  }

  @override
  Future<Uint8List> fetchQuotationPdf({
    required String quoteRequestId,
    required int revision,
    String? tenantId,
    String? companyId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<LimousineExternalQuoteCreateResult> createExternal({
    required LimousineExternalContactSummary contact,
    required LimousineExternalJourneyDraft request,
    required Map<String, dynamic> quote,
    String? tenantId,
    String? companyId,
  }) async {
    createCalls += 1;
    lastContact = contact;
    lastJourney = request;
    record = LimousineQuoteRequest.fromJson(_item());
    return LimousineExternalQuoteCreateResult(
      record: record!,
      invitationUrl: 'https://booking.internal/l/i/liminv1.testtoken',
      contact: contact,
    );
  }

  @override
  Future<LimousineExternalInvitationResult> invitation({
    required String quoteRequestId,
    required String action,
    String? tenantId,
    String? companyId,
  }) async {
    invitationActions.add(action);
    return LimousineExternalInvitationResult(
      record: LimousineQuoteRequest.fromJson(
        _item(
          extra: <String, dynamic>{
            'external_delivery': <String, dynamic>{
              'invitation_state': 'invitation_shared',
              'link_created_at': '2026-08-24T10:00:00.000Z',
              'shared_at': '2026-08-24T10:05:00.000Z',
            },
          },
        ),
      ),
      invitationUrl: 'https://booking.internal/l/i/liminv1.testtoken',
    );
  }

  @override
  Future<LimousineExternalContactSummary> contact({
    required String quoteRequestId,
    String? tenantId,
    String? companyId,
  }) async {
    return const LimousineExternalContactSummary(
      displayName: 'Ada Lovelace',
      mail: 'ada@example.test',
      locale: 'nl',
    );
  }
}

const LimousineCompanyQuoteDraft _draft = LimousineCompanyQuoteDraft(
  totalInclVatCents: 100000,
  currency: 'EUR',
  vatTreatment: 'excl',
  vatRate: 0.06,
  expiresAt: '2099-01-01T00:00:00Z',
  cancellationDeadlineHours: 24,
  cancellationPenaltyPercent: 25,
  waitingTimeIncludedMinutes: 15,
  noShowPenaltyPercent: 100,
  overtimeCentsPerHour: 9000,
);

Widget _app(
  Widget child, {
  Size size = const Size(390, 844),
  EdgeInsets padding = EdgeInsets.zero,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        padding: padding,
        viewPadding: padding,
      ),
      child: child,
    ),
  );
}

Widget _ownCustomerForm({
  Size size = const Size(390, 1800),
  EdgeInsets padding = EdgeInsets.zero,
  List<VehicleProfile>? vehicles,
}) {
  return _app(
    LimousineExternalQuoteCreatePage(
      gateway: _FakeGateway(),
      offers: <Map<String, dynamic>>[_quoteOffer()],
      vehicles:
          vehicles ??
          <VehicleProfile>[
            _vehicle(id: 'veh_limo', name: 'Party Limo', category: 'limousine'),
            _vehicle(
              id: 'veh_limo_2',
              name: 'Wedding Limo',
              category: 'limousine',
            ),
          ],
      quoteDraft: _draft,
    ),
    size: size,
    padding: padding,
  );
}

Future<void> _pumpForm(
  WidgetTester tester, {
  Size size = const Size(390, 1800),
  EdgeInsets padding = EdgeInsets.zero,
  List<VehicleProfile>? vehicles,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _ownCustomerForm(size: size, padding: padding, vehicles: vehicles),
  );
  await tester.pump();
}

Future<void> _reveal(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.scrollUntilVisible(
    finder,
    280,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

Future<void> _revealAndTap(WidgetTester tester, Key key) async {
  await _reveal(tester, key);
  await tester.tap(find.byKey(key));
  await tester.pump();
}

Future<void> _fillRequiredJourney(WidgetTester tester) async {
  await tester.enterText(find.byKey(kLimousineExternalContactNameKey), 'Ada');
  await tester.enterText(
    find.byKey(kLimousineExternalContactEmailKey),
    'ada@example.test',
  );
  await tester.enterText(
    find.byKey(kLimousineExternalPickupKey),
    'Korenmarkt 1, Gent',
  );
  await tester.enterText(
    find.byKey(kLimousineExternalDestinationKey),
    'Graslei, Gent',
  );
  await tester.enterText(find.byKey(kLimousineExternalPaxKey), '8');
  await tester.enterText(find.byKey(kLimousineExternalBagsKey), '2');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    appLanguageNotifier.value = AppLanguage.nl;
    businessThemeNotifier.value = BusinessThemeVariant.cleanProfessional;
  });

  test('own-customer labels and origin stay in one language', () {
    expect(kLimousineExternalQuoteCreateAction.nl, 'Offerte voor eigen klant');
    expect(kLimousineExternalQuoteCreateAction.en, 'Quote for own customer');
    expect(
      kLimousineExternalQuoteCreateAction.fr,
      'Devis pour votre propre client',
    );
    expect(
      kLimousineExternalQuoteCreateAction.es,
      'Presupuesto para cliente propio',
    );
    expect(kLimousineOwnCustomerOrigin.nl, 'Eigen klant');
    expect(kLimousineOwnCustomerOrigin.en, 'Own customer');
    expect(kLimousineOwnCustomerOrigin.fr, 'Client propre');
    expect(kLimousineOwnCustomerOrigin.es, 'Cliente propio');
    expect(
      limousineExternalDeliveryLabel(
        LimousineExternalDeliveryState.invitationShared,
        AppLanguage.nl,
      ),
      'Link gedeeld',
    );
    expect(
      limousineExternalDeliveryLabel(
        LimousineExternalDeliveryState.quotationAccepted,
        AppLanguage.nl,
      ),
      'Geaccepteerd',
    );
    expect(
      kLimousineExternalQuoteCreateAction.nl.contains('Handmatige'),
      isFalse,
    );
  });

  test('contact, pax, bags and VAT preview stay practical', () {
    expect(
      validateOwnCustomerContactForm(name: 'Ada', email: '', mobile: '').ok,
      isFalse,
    );
    expect(
      validateOwnCustomerContactForm(
        name: 'Ada',
        email: 'ada@example.test',
        mobile: '',
      ).ok,
      isTrue,
    );
    expect(
      validateOwnCustomerContactForm(
        name: 'Ada',
        email: '',
        mobile: '+32 470 00 00 00',
      ).ok,
      isTrue,
    );
    expect(limousineOwnCustomerPaxOk(8), isTrue);
    expect(limousineOwnCustomerPaxOk(0), isFalse);
    expect(limousineOwnCustomerPaxOk(17), isFalse);
    expect(limousineOwnCustomerBagsOk(2), isTrue);
    expect(limousineOwnCustomerBagsOk(100), isFalse);
    expect(normalizeLimousineQuoteLocale('nl-BE'), 'nl');
    expect(normalizeLimousineQuoteLocale('FR'), 'fr');
    final money = previewOwnCustomerQuoteMoney(
      enteredCents: 100000,
      vatTreatment: 'excl',
      vatRate: 0.06,
    );
    expect(money.netCents, 100000);
    expect(money.vatCents, 6000);
    expect(money.grossCents, 106000);
    expect(ownCustomerVatPercentLabel(0.06), '6%');
  });

  test('CTA lives only in the limousine company inbox', () {
    expect(
      File('lib/limousine/limousine_quote_inbox_page.dart').readAsStringSync(),
      contains('kLimousineExternalQuoteCreateActionKey'),
    );
    expect(
      File('lib/main_parts/business_home_page_state.dart').readAsStringSync(),
      isNot(contains('kLimousineExternalQuoteCreateActionKey')),
    );
    expect(
      File(
        'lib/limousine/limousine_external_quote_page.dart',
      ).readAsStringSync(),
      isNot(contains('booking_link')),
    );
  });

  test('taxi QR stays out of limousine context', () {
    final taxi = _vehicle(id: 'veh_taxi', name: 'Taxi');
    final limo = _vehicle(
      id: 'veh_limo',
      name: 'Party Limo',
      category: 'limousine',
    );
    expect(companyShouldShowTaxiBookingQr(vehicles: [limo]), isFalse);
    expect(
      companyShouldShowTaxiBookingQr(
        vehicles: [taxi, limo],
        limousineContext: true,
      ),
      isFalse,
    );
    expect(companyShouldShowTaxiBookingQr(vehicles: [taxi]), isTrue);
  });

  testWidgets('CTA is visible in the limousine inbox and origin badge shows', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      record: LimousineQuoteRequest.fromJson(_item()),
    );
    await tester.pumpWidget(
      _app(LimousineQuoteInboxPage(gateway: gateway, entitled: true)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(kLimousineExternalQuoteCreateActionKey), findsOneWidget);
    expect(
      find.text(kLimousineExternalQuoteCreateAction.of(AppLanguage.nl)),
      findsWidgets,
    );
    expect(find.byKey(kLimousineExternalOriginBadgeKey), findsOneWidget);
    expect(find.text('Eigen klant'), findsWidgets);
    expect(find.text('Ada Lovelace'), findsWidgets);
    expect(find.text('Party Limo'), findsWidgets);
    expect(
      find.byKey(limousineQuoteInboxActionKey('limq_own', 'editQuote')),
      findsOneWidget,
    );
  });

  testWidgets('accepted quote does not offer edit on the accepted revision', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      record: LimousineQuoteRequest.fromJson(_item(state: 'accepted')),
    );
    await tester.pumpWidget(
      _app(LimousineQuoteInboxPage(gateway: gateway, entitled: true)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.byKey(limousineQuoteInboxActionKey('limq_own', 'editQuote')),
      findsNothing,
    );
    expect(
      limousineQuoteInboxCardActions(gateway.record!).any((action) {
        return action == LimousineQuoteInboxCardAction.editQuote;
      }),
      isFalse,
    );
  });

  testWidgets('contact and journey validation block send', (tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gateway = _FakeGateway();
    await tester.pumpWidget(
      _app(
        LimousineExternalQuoteCreatePage(
          gateway: gateway,
          offers: <Map<String, dynamic>>[_quoteOffer()],
          vehicles: <VehicleProfile>[
            _vehicle(id: 'veh_limo', name: 'Party Limo', category: 'limousine'),
            _vehicle(id: 'veh_taxi', name: 'Street Taxi'),
          ],
          quoteDraft: _draft,
        ),
        size: const Size(430, 1600),
      ),
    );
    expect(find.byKey(kLimousineExternalContactNameKey), findsOneWidget);
    expect(find.byKey(kLimousineExternalPickupKey), findsOneWidget);
    expect(find.byKey(kLimousineExternalWhenKey), findsOneWidget);
    expect(find.byKey(kLimousineExternalReturnKey), findsOneWidget);
    expect(find.byKey(kLimousineExternalPaxKey), findsOneWidget);
    expect(find.byKey(kLimousineExternalBagsKey), findsOneWidget);
    expect(find.byKey(kLimousineExternalVehicleKey), findsOneWidget);
    expect(find.byKey(kLimousineExternalExtrasKey), findsOneWidget);
    expect(find.text('Party Limo'), findsWidgets);
    expect(find.text('Street Taxi'), findsNothing);
    await _revealAndTap(tester, kLimousineExternalSubmitKey);
    expect(
      find.text(kLimousineExternalContactRequired.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(gateway.createCalls, 0);
    await tester.enterText(find.byKey(kLimousineExternalContactNameKey), 'Ada');
    await tester.enterText(
      find.byKey(kLimousineExternalContactEmailKey),
      'ada@example.test',
    );
    await tester.enterText(
      find.byKey(kLimousineExternalPickupKey),
      'Korenmarkt',
    );
    await tester.enterText(
      find.byKey(kLimousineExternalDestinationKey),
      'Graslei',
    );
    await tester.enterText(find.byKey(kLimousineExternalPaxKey), '17');
    await _revealAndTap(tester, kLimousineExternalSubmitKey);
    expect(
      find.text(kLimousineExternalPaxRange.of(AppLanguage.nl)),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(kLimousineExternalPaxKey), '8');
    await tester.enterText(find.byKey(kLimousineExternalBagsKey), '100');
    await _revealAndTap(tester, kLimousineExternalSubmitKey);
    expect(
      find.text(kLimousineExternalBagsRange.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(gateway.createCalls, 0);
  });

  testWidgets('preview, VAT, terms, send, copy and share', (tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gateway = _FakeGateway();
    String? copied;
    String? shared;
    await tester.pumpWidget(
      _app(
        LimousineExternalQuoteCreatePage(
          gateway: gateway,
          offers: <Map<String, dynamic>>[_quoteOffer()],
          vehicles: <VehicleProfile>[
            _vehicle(id: 'veh_limo', name: 'Party Limo', category: 'limousine'),
          ],
          copy: (url) async => copied = url,
          share: (url) async => shared = url,
          quoteDraft: _draft,
        ),
        size: const Size(430, 1600),
      ),
    );
    await _fillRequiredJourney(tester);
    await _revealAndTap(tester, kLimousineExternalSubmitKey);
    await tester.pumpAndSettle();
    expect(gateway.createCalls, 0);
    expect(find.byKey(kLimousineExternalPreviewKey), findsOneWidget);
    expect(find.byKey(kLimousineExternalPreviewMoneyKey), findsOneWidget);
    expect(find.textContaining('EUR 1000.00'), findsWidgets);
    expect(find.textContaining('6%'), findsWidgets);
    expect(find.textContaining('EUR 60.00'), findsWidgets);
    expect(find.textContaining('EUR 1060.00'), findsWidgets);
    expect(find.textContaining('24h'), findsWidgets);
    expect(find.textContaining('25%'), findsWidgets);
    expect(find.textContaining('100%'), findsWidgets);
    expect(find.byKey(kLimousineQuoteEditorPageKey), findsNothing);
    await tester.tap(find.byKey(kLimousineExternalPreviewEditKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineQuoteEditorPageKey), findsOneWidget);
    expect(find.byKey(kLimousineQuoteTotalFieldKey), findsOneWidget);
    expect(find.byKey(kLimousineQuoteVatFieldKey), findsOneWidget);
    expect(find.byKey(kLimousineQuoteCompanyVatRateKey), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kLimousineExternalPreviewSendKey));
    await tester.pumpAndSettle();
    expect(gateway.createCalls, 1);
    expect(gateway.lastJourney?.pax, 8);
    expect(gateway.lastJourney?.bags, 2);
    expect(gateway.lastContact?.locale, 'nl');
    expect(find.byKey(kLimousineExternalCopyLinkKey), findsOneWidget);
    expect(find.byKey(kLimousineExternalShareLinkKey), findsOneWidget);
    await tester.tap(find.byKey(kLimousineExternalCopyLinkKey));
    await tester.pump();
    await tester.tap(find.byKey(kLimousineExternalShareLinkKey));
    await tester.pump();
    expect(copied, contains('/l/i/'));
    expect(shared, contains('/l/i/'));
    expect(gateway.invitationActions, containsAll(<String>['copy', 'share']));
    expect(find.textContaining('Link gedeeld'), findsWidgets);
  });

  testWidgets('light and dark themes keep readable contrast', (tester) async {
    final gateway = _FakeGateway();
    for (final variant in <BusinessThemeVariant>[
      BusinessThemeVariant.cleanProfessional,
      BusinessThemeVariant.executiveGold,
    ]) {
      businessThemeNotifier.value = variant;
      final palette = paletteForBusinessTheme(variant);
      await tester.pumpWidget(
        _app(
          LimousineExternalQuoteCreatePage(
            gateway: gateway,
            offers: <Map<String, dynamic>>[_quoteOffer()],
            vehicles: <VehicleProfile>[
              _vehicle(
                id: 'veh_limo',
                name: 'Party Limo',
                category: 'limousine',
              ),
            ],
            quoteDraft: _draft,
          ),
        ),
      );
      final scaffold = tester.widget<Scaffold>(
        find.byKey(kLimousineExternalQuotePageKey),
      );
      expect(scaffold.backgroundColor, palette.background);
      expect(scaffold.backgroundColor, isNot(palette.textPrimary));
    }
  });

  testWidgets('phone and tablet widths keep the form', (tester) async {
    final gateway = _FakeGateway();
    for (final size in <Size>[
      const Size(360, 1400),
      const Size(390, 1400),
      const Size(430, 1400),
      const Size(800, 1280),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        _app(
          LimousineExternalQuoteCreatePage(
            gateway: gateway,
            offers: <Map<String, dynamic>>[_quoteOffer()],
            vehicles: <VehicleProfile>[
              _vehicle(
                id: 'veh_limo',
                name: 'Party Limo',
                category: 'limousine',
              ),
            ],
            quoteDraft: _draft,
          ),
          size: size,
        ),
      );
      await tester.pump();
      expect(find.byKey(kLimousineExternalQuotePageKey), findsOneWidget);
      expect(
        find.byKey(kLimousineExternalContactNameKey, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(kLimousineExternalPickupKey, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(kLimousineExternalVehicleKey, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(kLimousineExternalSubmitKey, skipOffstage: false),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    addTearDown(tester.view.reset);
  });

  test('own-customer date/time is localized without raw DateTime text', () {
    final when = DateTime(2026, 8, 27, 8, 51);
    expect(
      formatLimousineOwnCustomerDateTime(when, AppLanguage.nl),
      '27 augustus 2026 · 08:51',
    );
    expect(
      formatLimousineOwnCustomerDateTime(when, AppLanguage.en),
      '27 August 2026 · 08:51',
    );
    expect(
      formatLimousineOwnCustomerDateTime(when, AppLanguage.fr),
      '27 août 2026 · 08:51',
    );
    expect(
      formatLimousineOwnCustomerDateTime(when, AppLanguage.es),
      '27 de agosto de 2026 · 08:51',
    );
    expect(
      limousineLooksLikeRawDartDateTime('2026-08-27 08:51:32.025250'),
      isTrue,
    );
    expect(
      limousineLooksLikeRawDartDateTime('27 augustus 2026 · 08:51'),
      isFalse,
    );
  });

  testWidgets('form fields keep a visual gap and do not overflow', (
    tester,
  ) async {
    const sizes = <Size>[
      Size(360, 1800),
      Size(390, 1800),
      Size(430, 1800),
      Size(800, 1800),
    ];
    for (final language in <AppLanguage>[
      AppLanguage.nl,
      AppLanguage.en,
      AppLanguage.fr,
      AppLanguage.es,
    ]) {
      appLanguageNotifier.value = language;
      businessThemeNotifier.value = BusinessThemeVariant.brandSignatureGold;
      for (final size in sizes) {
        await _pumpForm(tester, size: size);
        expect(tester.takeException(), isNull);
        final company = tester.getRect(
          find.byKey(kLimousineExternalContactCompanyKey),
        );
        final locale = tester.getRect(
          find.byKey(kLimousineExternalContactLocaleKey),
        );
        final occasion = tester.getRect(
          find.byKey(kLimousineExternalOccasionKey),
        );
        final offer = tester.getRect(find.byKey(kLimousineExternalOfferKey));
        final contact = tester.getRect(
          find.byKey(kLimousineExternalContactSectionKey),
        );
        final journey = tester.getRect(
          find.byKey(kLimousineExternalJourneySectionKey),
        );
        final vehicle = tester.getRect(
          find.byKey(kLimousineExternalVehicleSectionKey),
        );
        expect(locale.top, greaterThanOrEqualTo(company.bottom + 12));
        expect(offer.top, greaterThanOrEqualTo(occasion.bottom + 12));
        expect(journey.top, greaterThanOrEqualTo(locale.bottom + 20));
        expect(vehicle.top, greaterThanOrEqualTo(offer.bottom + 20));
        expect(contact.top, greaterThan(0));
        expect(
          find.byKey(kLimousineExternalSubmitKey, skipOffstage: false),
          findsOneWidget,
        );
      }
    }
  });

  testWidgets('phone widths keep long Spanish and French labels', (
    tester,
  ) async {
    const sizes = <Size>[
      Size(360, 800),
      Size(390, 844),
      Size(430, 932),
      Size(800, 1280),
    ];
    final cases = <AppLanguage, Map<Key, String>>{
      AppLanguage.es: <Key, String>{
        kLimousineExternalContactCompanyKey:
            kLimousineExternalContactCompany.es,
        kLimousineExternalContactLocaleKey: kLimousineExternalContactLocale.es,
        kLimousineExternalOccasionKey: kLimousineQuoteImportantInfo.es,
        kLimousineExternalOfferKey: kLimousineQuoteOffer.es,
      },
      AppLanguage.fr: <Key, String>{
        kLimousineExternalContactCompanyKey:
            kLimousineExternalContactCompany.fr,
        kLimousineExternalContactLocaleKey: kLimousineExternalContactLocale.fr,
        kLimousineExternalOccasionKey: kLimousineQuoteImportantInfo.fr,
        kLimousineExternalOfferKey: kLimousineQuoteOffer.fr,
      },
    };
    for (final entry in cases.entries) {
      appLanguageNotifier.value = entry.key;
      businessThemeNotifier.value = BusinessThemeVariant.brandSignatureGold;
      for (final size in sizes) {
        await _pumpForm(tester, size: size);
        for (final labeled in entry.value.entries) {
          await _reveal(tester, labeled.key);
          expect(find.text(labeled.value), findsWidgets);
        }
        await _reveal(tester, kLimousineExternalSubmitKey);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('pickup date uses localized display instead of DateTime text', (
    tester,
  ) async {
    for (final language in <AppLanguage>[
      AppLanguage.nl,
      AppLanguage.en,
      AppLanguage.fr,
      AppLanguage.es,
    ]) {
      appLanguageNotifier.value = language;
      await _pumpForm(tester, size: const Size(390, 1800));
      final tile = tester.widget<ListTile>(
        find.byKey(kLimousineExternalWhenKey),
      );
      final shown = (tile.subtitle as Text).data ?? '';
      expect(shown, isNotEmpty);
      expect(limousineLooksLikeRawDartDateTime(shown), isFalse);
      expect(shown, contains(' · '));
      if (language == AppLanguage.es) {
        expect(RegExp(r'^\d{1,2} de .+ de \d{4} · \d{2}:\d{2}$').hasMatch(shown), isTrue);
      } else {
        expect(RegExp(r'^\d{1,2} .+ \d{4} · \d{2}:\d{2}$').hasMatch(shown), isTrue);
      }
    }
  });

  testWidgets('selected vehicle has accent chrome and a check', (tester) async {
    businessThemeNotifier.value = BusinessThemeVariant.brandSignatureGold;
    final palette = paletteForBusinessTheme(
      BusinessThemeVariant.brandSignatureGold,
    );
    await _pumpForm(tester, size: const Size(430, 1800));
    await tester.ensureVisible(
      find.byKey(limousineExternalVehicleCardKey('veh_limo')),
    );
    final selected = tester.widget<AnimatedContainer>(
      find.byKey(limousineExternalVehicleCardKey('veh_limo')),
    );
    final decoration = selected.decoration! as BoxDecoration;
    expect((decoration.border as Border).top.color, palette.accent);
    expect((decoration.border as Border).top.width, 2);
    expect(find.byKey(kLimousineExternalVehicleSelectedIconKey), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(limousineExternalVehicleCardKey('veh_limo_2')),
    );
    await tester.tap(find.byKey(limousineExternalVehicleCardKey('veh_limo_2')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(limousineExternalVehicleCardKey('veh_limo_2')),
        matching: find.byKey(kLimousineExternalVehicleSelectedIconKey),
      ),
      findsOneWidget,
    );
    final next = tester.widget<AnimatedContainer>(
      find.byKey(limousineExternalVehicleCardKey('veh_limo_2')),
    );
    expect(((next.decoration! as BoxDecoration).border as Border).top.width, 2);
    expect(find.text('Party Limo'), findsOneWidget);
    expect(find.text('Wedding Limo'), findsOneWidget);
  });

  testWidgets('Offerte opstellen stays above the system navigation inset', (
    tester,
  ) async {
    const size = Size(390, 844);
    const navInset = 48.0;
    businessThemeNotifier.value = BusinessThemeVariant.brandSignatureGold;
    await _pumpForm(
      tester,
      size: size,
      padding: const EdgeInsets.only(bottom: navInset),
    );
    expect(find.byKey(kLimousineExternalQuoteSafeAreaKey), findsOneWidget);
    await _reveal(tester, kLimousineExternalSubmitKey);
    final button = tester.getRect(find.byKey(kLimousineExternalSubmitKey));
    expect(button.bottom, lessThanOrEqualTo(size.height - navInset));
    expect(button.bottom, lessThan(size.height));
    expect(tester.takeException(), isNull);
  });
}
