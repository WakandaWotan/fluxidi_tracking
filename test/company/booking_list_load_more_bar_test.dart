import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/booking_list_page_labels.dart';
import 'package:fluxidi_tracking/company/booking_list_page_repository.dart';
import 'package:fluxidi_tracking/widgets/booking_list_load_more_bar.dart';

void main() {
  testWidgets('first page rows render and has_more exposes load-more', (
    tester,
  ) async {
    var loadMoreTaps = 0;
    final items = <String>['Alpha ride', 'Beta ride'];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              for (final item in items) ListTile(title: Text(item)),
              BookingListLoadMoreBar(
                visible: bookingListShowsLoadMore(
                  contract: BookingListContractKind.projected,
                  hasMore: true,
                  nextCursor: 'cursor-2',
                ),
                loading: false,
                enabled: true,
                label: kBookingPageLoadMoreLabel.en,
                semanticsLabel: kBookingPageLoadMoreSemantics.en,
                onPressed: () => loadMoreTaps += 1,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Alpha ride'), findsOneWidget);
    expect(find.text('Beta ride'), findsOneWidget);
    expect(find.text(kBookingPageLoadMoreLabel.en), findsOneWidget);
    await tester.tap(find.text(kBookingPageLoadMoreLabel.en));
    expect(loadMoreTaps, 1);
  });

  testWidgets('has_more=false hides load-more', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BookingListLoadMoreBar(
            visible: false,
            loading: false,
            enabled: false,
            label: 'Load more',
            semanticsLabel: 'Load more',
            onPressed: null,
          ),
        ),
      ),
    );
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets('page error keeps retry without draining', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingListLoadMoreBar(
            visible: false,
            loading: false,
            enabled: false,
            label: kBookingPageLoadMoreLabel.en,
            semanticsLabel: kBookingPageLoadMoreSemantics.en,
            onPressed: () {},
            errorText: kBookingPageNextPageFailedLabel.en,
            retryLabel: kBookingPageRetryPageLabel.en,
            retrySemanticsLabel: kBookingPageRetryPageSemantics.en,
            onRetry: () => retries += 1,
          ),
        ),
      ),
    );
    expect(find.text(kBookingPageNextPageFailedLabel.en), findsOneWidget);
    await tester.tap(find.text(kBookingPageRetryPageLabel.en));
    expect(retries, 1);
    expect(bookingListAllowsAutomaticDrain(), isFalse);
  });
}
