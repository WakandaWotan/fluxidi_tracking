import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/booking_list_page_repository.dart';
import 'package:fluxidi_tracking/company/company_booking_detail_page.dart';
import 'package:fluxidi_tracking/company/company_bookings_page.dart';

void main() {
  testWidgets('bookings list opens accepted quote detail and pops back', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1440, 900)),
        child: MaterialApp(
          home: CompanyBookingsPage(
            language: AppLanguage.nl,
            pageLoader: ({cursor = '', forceRefresh = false}) async {
              return BookingListPageResult(
                scopeKey: 'company|demo|demo|||active|',
                cacheKey: 'company|demo|demo|||active||',
                contract: BookingListContractKind.legacy,
                items: const <Map<String, dynamic>>[
                  <String, dynamic>{
                    'booking_id': 'cqb_ae3b84ee25e4f6505adc0b076192d394',
                    'customer_name': 'Ada Lovelace',
                    'from': 'Brussel-Zuid',
                    'to': 'Antwerpen-Centraal',
                    'status': 'PENDING',
                    'quote_id': 'cqq_711fd5c7c0095f21764a542d8b55b846',
                  },
                ],
                count: 1,
                hasMore: false,
              );
            },
            detailLoader: (bookingId) async => <String, dynamic>{
              'ok': true,
              'status': 'PENDING',
              'record': <String, dynamic>{
                'booking_id': bookingId,
                'customer_name': 'Ada Lovelace',
                'from': 'Brussel-Zuid',
                'to': 'Antwerpen-Centraal',
                'quote_id': 'cqq_711fd5c7c0095f21764a542d8b55b846',
              },
            },
            driversLoader: () async => const <Map<String, dynamic>>[],
            vehiclesLoader: () async => const <Map<String, dynamic>>[],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyBookingsPageKey), findsOneWidget);
    expect(find.textContaining('Ada Lovelace'), findsWidgets);
    await tester.tap(find.text('Brussel-Zuid → Antwerpen-Centraal'));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyBookingDetailPageKey), findsOneWidget);
    expect(find.textContaining('Terug gaat naar de boekingenlijst'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyBookingsPageKey), findsOneWidget);
  });

  testWidgets('phone width keeps filters and the list reachable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: MaterialApp(
          home: CompanyBookingsPage(
            language: AppLanguage.nl,
            pageLoader: ({cursor = '', forceRefresh = false}) async {
              return const BookingListPageResult(
                scopeKey: 's',
                cacheKey: 's|',
                contract: BookingListContractKind.legacy,
                items: <Map<String, dynamic>>[],
                count: 0,
                hasMore: false,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyBookingsFilterOpenKey), findsOneWidget);
    expect(find.text('Geen open boekingen voor dit bedrijf.'), findsOneWidget);
  });
}
