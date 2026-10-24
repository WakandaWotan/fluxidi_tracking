import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_references.dart';
import 'package:fluxidi_tracking/customer_booking/customer_payment_display.dart';
import 'package:fluxidi_tracking/customer_bookings_store.dart';
import 'package:fluxidi_tracking/payment/payment_method_catalog.dart';

void main() {
  group('resolveCustomerPaymentDisplayToken', () {
    test('in-vehicle unpaid is pay in the vehicle, not online pending', () {
      expect(
        resolveCustomerPaymentDisplayToken(
          paymentStatus: 'pending',
          paymentMethod: PaymentMethodIds.inVehicleCard,
          paymentProvider: 'manual',
          paymentMode: 'manual',
        ),
        CustomerPaymentDisplayTokens.payInCar,
      );
    });

    test('QR unpaid uses the same customer text as in-vehicle', () {
      expect(
        resolveCustomerPaymentDisplayToken(
          paymentStatus: 'unpaid',
          paymentMethod: PaymentMethodIds.qrCode,
          paymentProvider: 'manual',
          paymentMode: 'manual',
        ),
        CustomerPaymentDisplayTokens.payInCar,
      );
      expect(
        customerPaymentStatusLabel(CustomerPaymentDisplayTokens.payInCar).nl,
        'Te betalen in het voertuig',
      );
      expect(
        isPaidCustomerPaymentDisplayToken(CustomerPaymentDisplayTokens.payInCar),
        isFalse,
      );
    });

    test('missing method does not become in-vehicle or online pending', () {
      expect(
        resolveCustomerPaymentDisplayToken(
          paymentStatus: 'pending',
        ),
        CustomerPaymentDisplayTokens.unknown,
      );
      expect(
        resolveCustomerPaymentDisplayToken(
          paymentStatus: 'unpaid',
          paymentProvider: 'manual',
          paymentMode: 'manual',
        ),
        CustomerPaymentDisplayTokens.unknown,
      );
    });

    test('payment booking id is not used as a Mollie signal', () {
      final channel = extractCustomerPaymentChannel(<Map<String, dynamic>>[
        <String, dynamic>{
          'payment_booking_id': 'pay_abc123',
          'payment_status': 'pending',
        },
      ]);
      expect(channel.provider, isEmpty);
      expect(channel.method, isEmpty);
      expect(
        resolveCustomerPaymentDisplayToken(
          paymentStatus: 'pending',
          paymentProvider: channel.provider,
          paymentMode: channel.mode,
          paymentMethod: channel.method,
        ),
        CustomerPaymentDisplayTokens.unknown,
      );
    });

    test('paid is only a confirmed payment status', () {
      expect(
        resolveCustomerPaymentDisplayToken(
          paymentStatus: 'paid',
          paymentMethod: PaymentMethodIds.qrCode,
        ),
        CustomerPaymentDisplayTokens.paid,
      );
      expect(
        resolveCustomerPaymentDisplayToken(
          paymentStatus: 'confirmed',
          paymentMethod: PaymentMethodIds.bancontact,
        ),
        isNot(CustomerPaymentDisplayTokens.paid),
      );
    });

    test('Bancontact pending is online outstanding', () {
      expect(
        resolveCustomerPaymentDisplayToken(
          paymentStatus: 'pending',
          paymentMethod: PaymentMethodIds.bancontact,
        ),
        CustomerPaymentDisplayTokens.onlinePending,
      );
    });
  });

  group('customerPaymentStatusLabel', () {
    test('list and detail share the same copy', () {
      expect(
        customerPaymentStatusLabel(CustomerPaymentDisplayTokens.payInCar).nl,
        'Te betalen in het voertuig',
      );
      expect(
        customerPaymentStatusLabel(CustomerPaymentDisplayTokens.qrChosen).nl,
        'Te betalen in het voertuig',
      );
      expect(
        customerPaymentStatusLabel(CustomerPaymentDisplayTokens.onlinePending).nl,
        'Online betaling openstaand',
      );
      expect(
        customerPaymentStatusLabel(CustomerPaymentDisplayTokens.unknown).nl,
        'Onbekend',
      );
    });
  });

  group('StoredCustomerBooking payment persistence', () {
    test('fromBookSuccess keeps the chosen method from the request', () {
      final inVehicle = StoredCustomerBooking.fromBookSuccess(
        response: <String, dynamic>{
          'booking_id': '2026-09-069',
          'payment_booking_id': 'pay_vehicle',
          'payment_status': 'pending',
          'status': 'CONFIRMED',
          'booking': <String, dynamic>{'booking_id': '2026-09-069'},
        },
        requestPayload: <String, dynamic>{
          'payment_method': PaymentMethodIds.inVehicleCard,
          'payment_mode': 'manual',
          'payment_provider': 'manual',
          'pax': '2',
          'bags': '1',
          'quote': <String, dynamic>{'price_incl_vat': 122.5},
        },
        customerName: 'Test Klant',
        customerPhone: '+32000000000',
        customerEmail: 'hidden@example.test',
      );
      expect(inVehicle.paymentMethod, PaymentMethodIds.inVehicleCard);
      expect(inVehicle.paymentProvider, 'manual');
      expect(inVehicle.pax, '2');
      expect(inVehicle.bags, '1');
      expect(inVehicle.customerName, 'Test Klant');
      expect(
        resolveCustomerPaymentDisplayToken(
          paymentStatus: inVehicle.paymentStatus,
          paymentMethod: inVehicle.paymentMethod,
          paymentProvider: inVehicle.paymentProvider,
          paymentMode: inVehicle.paymentMode,
        ),
        CustomerPaymentDisplayTokens.payInCar,
      );

      final qr = StoredCustomerBooking.fromBookSuccess(
        response: <String, dynamic>{
          'booking_id': '2026-09-070',
          'payment_booking_id': 'pay_qr',
          'payment_status': 'unpaid',
          'status': 'CONFIRMED',
          'booking': <String, dynamic>{'booking_id': '2026-09-070'},
        },
        requestPayload: <String, dynamic>{
          'payment_method': PaymentMethodIds.qrCode,
          'payment_mode': 'manual',
          'payment_provider': 'manual',
          'quote': <String, dynamic>{'price_incl_vat': 143.9},
        },
        customerName: 'Test Klant',
        customerPhone: '+32000000000',
        customerEmail: 'hidden@example.test',
      );
      expect(qr.paymentMethod, PaymentMethodIds.qrCode);
      expect(
        resolveCustomerPaymentDisplayToken(
          paymentStatus: qr.paymentStatus,
          paymentMethod: qr.paymentMethod,
          paymentProvider: qr.paymentProvider,
          paymentMode: qr.paymentMode,
        ),
        CustomerPaymentDisplayTokens.payInCar,
      );
      expect(qr.toJson()['payment_method'], PaymentMethodIds.qrCode);
      expect(
        StoredCustomerBooking.fromJson(qr.toJson()).paymentMethod,
        PaymentMethodIds.qrCode,
      );
    });

    test('authoritative response keeps method and does not invent Mollie', () {
      final stored = StoredCustomerBooking.fromAuthoritativeResponse(
        bookingId: '2026-09-069',
        response: <String, dynamic>{
          'ok': true,
          'booking_id': '2026-09-069',
          'record': <String, dynamic>{
            'booking_id': '2026-09-069',
            'payment_status': 'pending',
            'payment_booking_id': 'pay_vehicle',
            'payment_method': PaymentMethodIds.inVehicleCard,
            'booking': <String, dynamic>{
              'customer_name': 'Test Klant',
              'pax': '2',
              'bags': '1',
            },
          },
        },
      );
      expect(stored.paymentMethod, PaymentMethodIds.inVehicleCard);
      expect(stored.customerName, 'Test Klant');
      expect(stored.pax, '2');
      expect(stored.quote['payment_method'], PaymentMethodIds.inVehicleCard);
    });
  });

  group('public customer reference', () {
    test('fromJson drops a public id that is only the internal booking id', () {
      final stored = StoredCustomerBooking.fromJson(<String, dynamic>{
        'booking_id': '2026-09-069',
        'public_booking_id': '2026-09-069',
        'public_booking_reference': '2026-09-069',
        'status': 'CONFIRMED',
        'payment_status': 'unpaid',
      });
      expect(stored.bookingId, '2026-09-069');
      expect(stored.publicBookingId, isEmpty);
      expect(stored.publicReference, isEmpty);
      expect(
        customerFacingBookingReference(
          bookingId: stored.bookingId,
          publicCandidates: <String>[
            stored.publicBookingId,
            stored.publicReference,
          ],
        ),
        '2026-09-069',
      );
    });

    test('does not treat the internal booking id as the customer ref', () {
      expect(
        distinctPublicCustomerReference(
          bookingId: '2026-09-069',
          candidates: const <String>['2026-09-069', '', '2026-09-000050'],
        ),
        '2026-09-000050',
      );
      expect(
        customerFacingBookingReference(
          bookingId: '2026-09-070',
          publicCandidates: const <String>['2026-09-070'],
        ),
        '2026-09-070',
      );
      expect(
        customerFacingBookingReference(
          bookingId: '2026-09-070',
          publicCandidates: const <String>['2026-09-000051'],
        ),
        '2026-09-000051',
      );
    });
  });

  group('hydrate older local bookings', () {
    test('fills public ref, method, unpaid and pending without duplicating', () {
      final stale = StoredCustomerBooking(
        bookingId: '2026-09-069',
        publicBookingId: '2026-09-069',
        publicReference: '2026-09-069',
        paymentBookingId: 'pay_vehicle',
        paymentStatus: 'pending',
        status: 'CONFIRMED',
        customerName: '',
        pax: '',
        bags: '',
        price: 122.5,
      );
      final hydrated = StoredCustomerBooking.fromAuthoritativeResponse(
        bookingId: stale.bookingId,
        response: <String, dynamic>{
          'ok': true,
          'status': 'PENDING',
          'record': <String, dynamic>{
            'public_booking_reference': '2026-09-000050',
            'booking_reference': '2026-09-000050',
            'payment_status': 'unpaid',
            'payment_method': PaymentMethodIds.inVehicleCard,
            'payment_provider': 'manual',
            'booking': <String, dynamic>{
              'customer_name': 'Test Klant',
              'pax': '2',
              'bags': '1',
            },
          },
        },
        fallback: stale,
      );
      expect(hydrated.bookingId, '2026-09-069');
      expect(hydrated.publicBookingId, '2026-09-000050');
      expect(hydrated.paymentMethod, PaymentMethodIds.inVehicleCard);
      expect(hydrated.paymentStatus, 'unpaid');
      expect(hydrated.status, 'PENDING');
      expect(hydrated.customerName, 'Test Klant');
      expect(hydrated.pax, '2');
      expect(hydrated.bags, '1');
      expect(
        customerFacingBookingReference(
          bookingId: hydrated.bookingId,
          publicCandidates: <String>[
            hydrated.publicBookingId,
            hydrated.publicReference,
          ],
        ),
        '2026-09-000050',
      );
      expect(
        resolveCustomerPaymentDisplayToken(
          paymentStatus: hydrated.paymentStatus,
          paymentMethod: hydrated.paymentMethod,
          paymentProvider: hydrated.paymentProvider,
        ),
        CustomerPaymentDisplayTokens.payInCar,
      );
    });

    test('QR method stays qr_code while the customer text is in-vehicle', () {
      final stale = StoredCustomerBooking(
        bookingId: '2026-09-070',
        publicBookingId: '2026-09-070',
        paymentStatus: 'unpaid',
        status: 'CONFIRMED',
      );
      final hydrated = StoredCustomerBooking.fromAuthoritativeResponse(
        bookingId: stale.bookingId,
        response: <String, dynamic>{
          'ok': true,
          'status': 'PENDING',
          'record': <String, dynamic>{
            'public_booking_reference': '2026-09-000051',
            'payment_status': 'unpaid',
            'payment_method': PaymentMethodIds.qrCode,
            'payment_provider': 'manual',
          },
        },
        fallback: stale,
      );
      expect(hydrated.bookingId, '2026-09-070');
      expect(hydrated.publicBookingId, '2026-09-000051');
      expect(hydrated.paymentMethod, PaymentMethodIds.qrCode);
      expect(hydrated.status, 'PENDING');
      expect(
        resolveCustomerPaymentDisplayToken(
          paymentStatus: hydrated.paymentStatus,
          paymentMethod: hydrated.paymentMethod,
          paymentProvider: hydrated.paymentProvider,
        ),
        CustomerPaymentDisplayTokens.payInCar,
      );
    });

    test('failed refresh keeps known local fields', () {
      final known = StoredCustomerBooking(
        bookingId: '2026-09-069',
        publicBookingId: '2026-09-000050',
        paymentMethod: PaymentMethodIds.inVehicleCard,
        paymentStatus: 'unpaid',
        status: 'PENDING',
        customerName: 'Test Klant',
        pax: '2',
      );
      final afterFailedRefresh = known.copyWith();
      expect(afterFailedRefresh.publicBookingId, '2026-09-000050');
      expect(afterFailedRefresh.paymentMethod, PaymentMethodIds.inVehicleCard);
      expect(afterFailedRefresh.customerName, 'Test Klant');
      expect(afterFailedRefresh.pax, '2');
      expect(afterFailedRefresh.status, isNot('CONFIRMED'));
    });
  });
}
