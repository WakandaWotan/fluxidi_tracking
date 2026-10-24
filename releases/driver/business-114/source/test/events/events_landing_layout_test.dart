import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/events/event_data_source.dart';
import 'package:fluxidi_tracking/events/events_page.dart';

void main() {
  testWidgets('desktop categories fill the remaining page without scrolling', (
    tester,
  ) async {
    appLanguageNotifier.value = AppLanguage.en;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EventsPage(dataSource: const EmptyEventDataSource()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('events_landing_category_grid')), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Sport'), findsOneWidget);
    expect(find.text('Culture'), findsOneWidget);
    final grid = tester.getRect(
      find.byKey(const Key('events_landing_category_grid')),
    );
    expect(grid.height, greaterThan(360));
    expect(grid.bottom, greaterThan(820));
  });
}
