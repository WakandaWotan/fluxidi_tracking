import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_bookings_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_operational_handoff.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_unified_intent.dart';

void main() {
  test('quote inbox keeps limousine service type, occasion and from-price', () {
    final record = LimousineQuoteRequest.fromJson(<String, dynamic>{
      'quote_request_id': 'limq_1',
      'state': 'requested',
      'revision': 1,
      'offer_id': 'off_1',
      'service_class_id': 'executive_sedan',
      'vehicle_id': 'veh_1',
      'service_type': 'limousine',
      'pricing_mode': 'from_price',
      'occasion': 'wedding',
      'scheduled_pickup_iso': '2026-09-01T10:00:00Z',
      'fulfilment': <String, dynamic>{
        'from': 'Gent',
        'to': 'Brussel',
        'requested_duration_minutes': 180,
      },
      'pricing_snapshot': <String, dynamic>{
        'from_price_cents': 12000,
        'pricing_mode': 'from_price',
        'service_type': 'limousine',
      },
    });
    expect(record.serviceType, kLimousineServiceType);
    expect(record.pricingMode, 'from_price');
    expect(record.occasion, 'wedding');
    expect(record.fulfilment?.requestedDurationMinutes, 180);
    expect(limousineSnapshotFromPriceCents(record.pricingSnapshot), 12000);
    expect(
      limousinePricingModeLabel(record.pricingMode, AppLanguage.nl),
      kLimousinePricingModeFromPrice.nl,
    );
  });

  test('company booking row maps request fields and confirm action', () {
    final item = LimousineCompanyBookingPresentation.fromMap(<String, dynamic>{
      'booking_id': '2026-08-301',
      'status': 'PENDING',
      'from': 'Gent',
      'to': 'Brussel',
      'pickup_iso': '2026-08-20T10:00:00Z',
      'customer_name': 'Anna',
      'service_type': 'limousine',
      'pricing_mode': 'exact_fixed',
      'occasion': 'gala',
      'requested_duration_minutes': 180,
      'company_confirmation_required': true,
      'limousine_accepted_price': <String, dynamic>{
        'amount_cents': 25000,
        'service_type': 'limousine',
      },
    });
    expect(item.serviceType, 'limousine');
    expect(item.pricingMode, 'exact_fixed');
    expect(item.occasion, 'gala');
    expect(item.requestedDurationMinutes, 180);
    expect(item.companyConfirmationRequired, isTrue);
    expect(item.canConfirmOnExistingStatus, isTrue);
    expect(item.pricingSnapshot['amount_cents'], 25000);
  });

  test('customer authoritative response keeps limousine and pending request', () {
    final stored = StoredCustomerBooking.fromAuthoritativeResponse(
      bookingId: '2026-08-305',
      response: <String, dynamic>{
        'ok': true,
        'booking_id': '2026-08-305',
        'status': 'PENDING',
        'record': <String, dynamic>{
          'service_type': 'limousine',
          'company_confirmation_required': true,
          'booking': <String, dynamic>{
            'service_type': 'limousine',
            'company_confirmation_required': true,
            'from': 'Gent',
            'to': 'Brussel',
          },
        },
      },
    );
    expect(stored.service, 'limousine');
    expect(stored.quote['company_confirmation_required'], isTrue);
    expect(stored.quote['service_type'], 'limousine');
  });

  test('customer create body still has no tenant, company or total', () {
    final body = limousineCustomerCreateBody(
      const LimousineQuoteCreateDraft(
        publicPartnerId: 'prt_1',
        offerId: 'off_1',
        from: 'Gent',
        to: 'Brussel',
        scheduledPickupIso: '2026-09-01T10:00:00Z',
        occasion: 'wedding',
        requestedDurationMinutes: 180,
      ),
    );
    expect(body.containsKey('tenant_id'), isFalse);
    expect(body.containsKey('company_id'), isFalse);
    expect(body.containsKey('total_incl_vat_cents'), isFalse);
    expect(body['occasion'], 'wedding');
  });

  test('app resume does not auto-submit a quote or booking request', () {
    final source = File(
      'lib/limousine/limousine_customer_quote_page.dart',
    ).readAsStringSync();
    expect(source.contains('void initState()'), isTrue);
    expect(source.contains('submitRequest()'), isTrue);
    expect(source.contains('AppLifecycleState.resumed'), isTrue);
    final resumeHandler = source.substring(
      source.indexOf('void didChangeAppLifecycleState'),
      source.indexOf('void dispose()'),
    );
    expect(resumeHandler.contains('resumePolling()'), isTrue);
    expect(resumeHandler.contains('submitRequest()'), isFalse);
  });

  test('from-price stays informational and never becomes a booking total', () {
    expect(limousineSnapshotFromPriceCents({'from_price_cents': 12000}), 12000);
    expect(
      limousinePricingModeLabel('from_price', AppLanguage.nl),
      isNot(contains('€0')),
    );
    final item = LimousineCompanyBookingPresentation.fromMap(<String, dynamic>{
      'service_type': 'limousine',
      'pricing_mode': 'from_price',
      'company_confirmation_required': true,
      'pricing_snapshot': <String, dynamic>{
        'from_price_cents': 12000,
        'service_type': 'limousine',
      },
    });
    expect(item.pricingSnapshot['amount_cents'], isNull);
    expect(limousineSnapshotFromPriceCents(item.pricingSnapshot), 12000);
  });
}
