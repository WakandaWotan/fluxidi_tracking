import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_booking_list_item.dart';

void main() {
  test('accepted quote booking lands in the open filter', () {
    final item = CompanyBookingListItem.fromMap(<String, dynamic>{
      'booking_id': 'cqb_ae3b84ee25e4f6505adc0b076192d394',
      'customer_name': 'Ada Lovelace',
      'from': 'Brussel-Zuid',
      'to': 'Antwerpen-Centraal',
      'status': 'PENDING',
      'quote_id': 'cqq_711fd5c7c0095f21764a542d8b55b846',
      'created_at': '2026-09-20T09:00:00.000Z',
    });
    expect(item.bucket, CompanyBookingListBucket.open);
    expect(item.quoteId, 'cqq_711fd5c7c0095f21764a542d8b55b846');
    expect(item.routeLabel, 'Brussel-Zuid → Antwerpen-Centraal');
  });

  test('company list index uses planning_reference as the quote id', () {
    final item = CompanyBookingListItem.fromMap(<String, dynamic>{
      'booking_id': 'cqb_ae3b84ee25e4f6505adc0b076192d394',
      'status': 'PENDING',
      'planning_reference': 'cqq_711fd5c7c0095f21764a542d8b55b846',
      'pickup_iso': '2026-09-20T09:00:00.000Z',
    });
    expect(item.quoteId, 'cqq_711fd5c7c0095f21764a542d8b55b846');
    expect(item.bucket, CompanyBookingListBucket.open);
  });

  test('completed and cancelled follow the existing street-ride buckets', () {
    expect(
      CompanyBookingListItem.fromMap(<String, dynamic>{
        'booking_id': 'b1',
        'status': 'COMPLETED',
      }).bucket,
      CompanyBookingListBucket.completed,
    );
    expect(
      CompanyBookingListItem.fromMap(<String, dynamic>{
        'booking_id': 'b2',
        'status': 'CANCELLED',
      }).bucket,
      CompanyBookingListBucket.cancelled,
    );
  });
}
