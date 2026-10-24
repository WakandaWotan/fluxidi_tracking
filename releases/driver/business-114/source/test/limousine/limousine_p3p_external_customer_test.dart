import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_external_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_external_quote_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_external_quote_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_respond_form.dart';
import 'package:fluxidi_tracking/limousine/limousine_taxi_qr_isolation.dart';

VehicleProfile _vehicle({
  required String id,
  required String name,
  String category = '',
}) {
  return VehicleProfile(
    id: id,
    vehicleName: name,
    brandModel: name,
    licensePlate: '9-LMO-001',
    color: 'black',
    passengerCapacity: 8,
    luggageCapacity: 4,
    tierId: 'comfort',
    isActive: true,
    driverId: null,
    companyId: 'company_limo_p3p',
    primaryPhotoRef: '',
    galleryPhotoRefs: const <String>[],
    serviceCategory: category,
  );
}

Map<String, dynamic> _quoteOffer() {
  return <String, dynamic>{
    'offer_id': 'off_quote',
    'enabled': true,
    'published': true,
    'vehicle_id': 'veh_limo',
    'target_type': LimousineOfferTarget.vehicle,
    'price_presentation': LimousinePricePresentation.quoteRequired,
    'currency': 'EUR',
  };
}

Map<String, dynamic> _item({
  String id = 'limq_ext',
  String state = 'quoted',
  Map<String, dynamic>? extra,
}) {
  return <String, dynamic>{
    'quote_request_id': id,
    'state': state,
    'revision': 2,
    'origin_channel': kLimousineExternalOriginChannel,
    'external_delivery': <String, dynamic>{
      'invitation_state': 'link_created',
      'link_created_at': '2026-08-23T10:00:00.000Z',
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
              'link_created_at': '2026-08-23T10:00:00.000Z',
              'shared_at': '2026-08-23T10:05:00.000Z',
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
      displayName: 'Ada',
      mail: 'ada@example.test',
      locale: 'nl',
    );
  }
}

Widget _app(Widget child, {Size size = const Size(390, 844)}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    appLanguageNotifier.value = AppLanguage.nl;
  });

  test('contact PII is stripped from quote projection', () {
    final record = LimousineQuoteRequest.fromJson(_item());
    expect(record.originChannel, kLimousineExternalOriginChannel);
    expect(record.externalDelivery.invitationState, 'link_created');
    expect(limousineQuoteProjectionLeaksForbidden(_item()), isTrue);
    expect(record.quoteRequestId, 'limq_ext');
  });

  test('taxi QR stays in taxi context and is hidden for limousine-only', () {
    final taxi = _vehicle(id: 'veh_taxi', name: 'Taxi');
    final limo = _vehicle(id: 'veh_limo', name: 'Limo', category: 'limousine');
    expect(companyShouldShowTaxiBookingQr(vehicles: [taxi]), isTrue);
    expect(companyShouldShowTaxiBookingQr(vehicles: [taxi, limo]), isTrue);
    expect(companyShouldShowTaxiBookingQr(vehicles: [limo]), isFalse);
    expect(
      companyShouldShowTaxiBookingQr(
        vehicles: [taxi, limo],
        limousineContext: true,
      ),
      isFalse,
    );
    expect(
      File('lib/main_parts/business_home_page_state.dart').readAsStringSync(),
      contains("actionKey: 'booking_link'"),
    );
  });

  test('labels stay in one language and use Bekeken', () {
    expect(kLimousineExternalQuoteCreateAction.nl, 'Offerte voor eigen klant');
    expect(kLimousineExternalBekeken.nl, 'Bekeken');
    expect(kLimousineExternalBekeken.nl.contains('Gelezen'), isFalse);
    expect(
      limousineExternalDeliveryLabel(
        LimousineExternalDeliveryState.customerOpened,
        AppLanguage.nl,
      ),
      'Bekeken',
    );
    expect(kLimousineExternalQuoteCreateAction.en.isNotEmpty, isTrue);
    expect(kLimousineExternalQuoteCreateAction.fr.isNotEmpty, isTrue);
    expect(kLimousineExternalQuoteCreateAction.es.isNotEmpty, isTrue);
  });

  testWidgets('inbox shows Offerte voor eigen klant', (tester) async {
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
  });

  testWidgets('contact form, quote form reuse, copy and share', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
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
            _vehicle(id: 'veh_limo', name: 'Party', category: 'limousine'),
          ],
          copy: (url) async => copied = url,
          share: (url) async => shared = url,
          quoteDraft: const LimousineCompanyQuoteDraft(
            totalInclVatCents: 80000,
            currency: 'EUR',
            vatTreatment: 'excl',
            expiresAt: '2099-01-01T00:00:00Z',
          ),
        ),
        size: const Size(430, 1600),
      ),
    );
    expect(find.byKey(kLimousineExternalQuotePageKey), findsOneWidget);
    expect(find.byKey(kLimousineExternalContactNameKey), findsOneWidget);
    expect(find.byKey(kLimousineExternalPickupKey), findsOneWidget);
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
    await tester.ensureVisible(find.byKey(kLimousineExternalSubmitKey));
    await tester.tap(find.byKey(kLimousineExternalSubmitKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineQuoteEditorPageKey), findsNothing);
    expect(find.byKey(kLimousineExternalPreviewKey), findsOneWidget);
    await tester.ensureVisible(find.byKey(kLimousineExternalPreviewSendKey));
    await tester.tap(find.byKey(kLimousineExternalPreviewSendKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineExternalCopyLinkKey), findsOneWidget);
    expect(find.byKey(kLimousineExternalShareLinkKey), findsOneWidget);
    expect(find.byKey(kLimousineExternalTimelineKey), findsOneWidget);
    await tester.tap(find.byKey(kLimousineExternalCopyLinkKey));
    await tester.pump();
    await tester.tap(find.byKey(kLimousineExternalShareLinkKey));
    await tester.pump();
    expect(copied, contains('/l/i/'));
    expect(shared, contains('/l/i/'));
    expect(gateway.invitationActions, containsAll(<String>['copy', 'share']));
  });

  testWidgets('quote editor remains the reused quote form', (tester) async {
    await tester.pumpWidget(
      _app(
        LimousineQuoteEditorPage(
          record: LimousineQuoteRequest.fromJson(_item()),
        ),
      ),
    );
    expect(find.byKey(kLimousineQuoteEditorPageKey), findsOneWidget);
    expect(find.byKey(kLimousineQuoteTotalFieldKey), findsOneWidget);
    expect(find.byKey(kLimousineQuoteVatFieldKey), findsOneWidget);
  });
}
