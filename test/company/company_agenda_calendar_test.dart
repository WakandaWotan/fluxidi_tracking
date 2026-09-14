import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_agenda_calendar.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_agenda_models.dart';
import 'package:fluxidi_tracking/company/company_customer_models.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';

CompanyAgendaRide _ride({
  required String id,
  required String name,
  required DateTime pickupLocal,
  int? durationMin,
  bool durationUnknown = false,
  String driverId = '',
}) {
  return CompanyAgendaRide(
    bookingId: id,
    customerId: 'cus_$id',
    customerName: name,
    fromAddress: 'Kunstlaan 44, Brussel',
    toAddress: 'Antwerpen Centraal',
    pickupIso: pickupLocal.toUtc().toIso8601String(),
    status: 'PENDING',
    assignedDriverId: driverId,
    assignedVehicleId: driverId.isEmpty ? '' : 'vh_1',
    durationUnknown: durationUnknown,
    durationMin: durationMin,
  );
}

void main() {
  final wednesday = DateTime(2026, 9, 9);
  final period = companyAgendaPeriodFor(
    view: CompanyAgendaView.week,
    anchorLocal: DateTime(2026, 9, 9, 12),
  );

  test('unknown duration is a compact marker without an end time', () {
    final ride = _ride(
      id: 'unknown',
      name: 'Ada Lovelace',
      pickupLocal: DateTime(2026, 9, 10, 20),
      durationUnknown: true,
    );
    final layout = companyAgendaRideLayout(ride, DateTime(2026, 9, 10));
    expect(layout, isNotNull);
    expect(layout!.compactMarker, isTrue);
    expect(layout.height, kCompanyAgendaUnknownDurationHeight);
    expect(layout.height < kCompanyAgendaHourHeight, isTrue);
    final summary = companyAgendaRideSummary(ride, AppLanguage.nl);
    expect(summary.time, '20:00');
    expect(summary.time.contains('–'), isFalse);
    expect(
      summary.extras,
      contains(kCompanyAgendaDurationUnknown.of(AppLanguage.nl)),
    );
  });

  test('short known rides keep their true duration on the time scale', () {
    final ride = _ride(
      id: 'short',
      name: 'Pending',
      pickupLocal: DateTime(2026, 9, 7, 11),
      durationMin: 15,
    );
    final layout = companyAgendaRideLayout(ride, DateTime(2026, 9, 7));
    expect(layout, isNotNull);
    expect(layout!.compactMarker, isFalse);
    expect(layout.height, closeTo(15 / 60 * kCompanyAgendaHourHeight, 0.1));
    expect(layout.height < 32, isTrue);
  });

  test('card content drops route and extras before it can overflow', () {
    final compact = companyAgendaRideBlockContent(
      maxHeight: 12,
      maxWidth: 80,
      textScale: 1.3,
      hasRoute: true,
      hasExtras: true,
      hasDriver: true,
    );
    expect(compact.compact, isTrue);
    expect(compact.showAvatar, isFalse);
    expect(compact.showRoute, isFalse);
    expect(compact.showExtras, isFalse);
    expect(compact.showDriverLine, isFalse);

    final roomy = companyAgendaRideBlockContent(
      maxHeight: 80,
      maxWidth: 180,
      textScale: 1,
      hasRoute: true,
      hasExtras: true,
      hasDriver: true,
    );
    expect(roomy.compact, isFalse);
    expect(roomy.showRoute, isTrue);
    expect(roomy.showExtras, isTrue);
    expect(roomy.showAvatar, isTrue);
    expect(roomy.showDriverInline, isFalse);

    final stacked = companyAgendaRideBlockContent(
      maxHeight: 120,
      maxWidth: 64,
      textScale: 1,
      hasRoute: true,
      hasExtras: true,
      hasDriver: true,
    );
    expect(stacked.compact, isFalse);
    expect(stacked.showCustomer, isTrue);
    expect(stacked.showDriverLine, isTrue);
    expect(stacked.showRoute, isFalse);
    expect(stacked.showExtras, isFalse);
    expect(stacked.showAvatar, isFalse);
    expect(stacked.splitTime, isTrue);
  });

  test('abutting rides are not packed as an overlap', () {
    expect(companyAgendaIntervalsOverlap(0, 72, 72, 144), isFalse);
    expect(companyAgendaIntervalsOverlap(0, 72, 71.9, 144), isTrue);
    final first = _ride(
      id: 'a',
      name: 'Ada Lovelace',
      pickupLocal: DateTime(2026, 9, 9, 9),
      durationMin: 60,
      driverId: 'drv_karel',
    );
    final second = _ride(
      id: 'b',
      name: 'Grace Hopper',
      pickupLocal: DateTime(2026, 9, 9, 10),
      durationMin: 60,
      driverId: 'drv_amira',
    );
    final pack = companyAgendaPackDayRides(
      rides: <CompanyAgendaRide>[first, second],
      day: DateTime(2026, 9, 9),
      columnWidth: 220,
    );
    expect(pack.visible, hasLength(2));
    expect(pack.overflows, isEmpty);
    expect(pack.visible[0].columnIndex, 0);
    expect(pack.visible[1].columnIndex, 0);
  });

  test('a night ride keeps a continuation label on the next day', () {
    final ride = _ride(
      id: 'night',
      name: 'Airport',
      pickupLocal: DateTime(2026, 9, 11, 23),
      durationMin: 180,
    );
    final startDay = companyAgendaRideLayout(ride, DateTime(2026, 9, 11));
    final nextDay = companyAgendaRideLayout(ride, DateTime(2026, 9, 12));
    expect(startDay!.continuesFromPreviousDay, isFalse);
    expect(nextDay!.continuesFromPreviousDay, isTrue);
    expect(
      companyAgendaRideSummary(
        ride,
        AppLanguage.nl,
        continuesFromPreviousDay: true,
      ).extras,
      contains(kCompanyAgendaContinues.of(AppLanguage.nl)),
    );
  });

  testWidgets('week cards and sticky day headers stay inside their space', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(980, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final rides = <CompanyAgendaRide>[
      _ride(
        id: 'short',
        name: 'Pending',
        pickupLocal: DateTime(2026, 9, 7, 11),
        durationMin: 15,
      ),
      _ride(
        id: 'grace',
        name: 'Grace Hopper',
        pickupLocal: DateTime(2026, 9, 8, 14),
        durationMin: 75,
        driverId: 'drv_karel',
      ),
      _ride(
        id: 'overlap',
        name: 'DEMO Wolkenhof',
        pickupLocal: DateTime(2026, 9, 11, 19),
        durationMin: 20,
      ),
      _ride(
        id: 'unknown',
        name: 'Ada Lovelace',
        pickupLocal: DateTime(2026, 9, 10, 20),
        durationUnknown: true,
      ),
      _ride(
        id: 'midnight',
        name: 'Airport',
        pickupLocal: DateTime(2026, 9, 11, 23),
        durationMin: 180,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(980, 720),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Scaffold(
            body: CompanyAgendaCalendar(
              period: period,
              rides: rides,
              language: AppLanguage.nl,
              drivers: const <Map<String, dynamic>>[
                <String, dynamic>{
                  'driver_id': 'drv_karel',
                  'display_name': 'Karel Peeters',
                  'agenda_color': '#C9A227',
                },
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(kCompanyAgendaDayHeaderRowKey), findsOneWidget);
    expect(find.text('Ma'), findsOneWidget);
    expect(find.text('7/9'), findsOneWidget);
    final headerTop = tester.getTopLeft(
      find.byKey(kCompanyAgendaDayHeaderRowKey),
    );
    await tester.drag(
      find.byKey(kCompanyAgendaCalendarKey),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(kCompanyAgendaDayHeaderRowKey)).dy,
      headerTop.dy,
    );
    expect(find.text('Ma'), findsOneWidget);
    expect(find.text('7/9'), findsOneWidget);
    expect(find.text('Zo'), findsOneWidget);
    expect(find.text('13/9'), findsOneWidget);
    expect(find.textContaining('20:00'), findsWidgets);
    expect(find.textContaining('20:00–'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overlapping wednesday cards keep separate tap targets', (
    tester,
  ) async {
    CompanyAgendaRide? selected;
    await tester.binding.setSurfaceSize(const Size(1600, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1600, 720)),
          child: Scaffold(
            body: CompanyAgendaCalendar(
              period: period,
              rides: <CompanyAgendaRide>[
                _ride(
                  id: 'ada',
                  name: 'Ada Lovelace',
                  pickupLocal: DateTime(2026, 9, 9, 9),
                  durationMin: 120,
                  driverId: 'drv_karel',
                ),
                _ride(
                  id: 'grace',
                  name: 'Grace Hopper',
                  pickupLocal: DateTime(2026, 9, 9, 10),
                  durationMin: 90,
                  driverId: 'drv_amira',
                ),
              ],
              language: AppLanguage.nl,
              drivers: const <Map<String, dynamic>>[
                <String, dynamic>{
                  'driver_id': 'drv_karel',
                  'display_name': 'Karel Peeters',
                },
                <String, dynamic>{
                  'driver_id': 'drv_amira',
                  'display_name': 'Amira Benali',
                },
              ],
              onSelectRide: (value) => selected = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(Key(companyAgendaRideKey('ada'))));
    await tester.ensureVisible(find.byKey(Key(companyAgendaRideKey('grace'))));
    await tester.pumpAndSettle();
    final ada = tester.getRect(find.byKey(Key(companyAgendaRideKey('ada'))));
    final grace = tester.getRect(find.byKey(Key(companyAgendaRideKey('grace'))));
    expect(ada.overlaps(grace), isFalse);
    expect(grace.left, greaterThan(ada.right - 0.5));
    expect(find.textContaining('09:00'), findsWidgets);
    expect(find.text('Ada Lovelace'), findsWidgets);
    expect(find.textContaining('10:00'), findsWidgets);
    expect(find.text('Grace Hopper'), findsWidgets);
    await tester.tap(find.byKey(Key(companyAgendaRideKey('grace'))));
    await tester.pumpAndSettle();
    expect(selected?.bookingId, 'grace');
  });

  testWidgets('narrow overlapping wednesday rides stay reachable via summary', (
    tester,
  ) async {
    CompanyAgendaRide? selected;
    await tester.binding.setSurfaceSize(const Size(980, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(980, 720)),
          child: Scaffold(
            body: CompanyAgendaCalendar(
              period: period,
              rides: <CompanyAgendaRide>[
                _ride(
                  id: 'ada',
                  name: 'Ada Lovelace',
                  pickupLocal: DateTime(2026, 9, 9, 9),
                  durationMin: 120,
                  driverId: 'drv_karel',
                ),
                _ride(
                  id: 'grace',
                  name: 'Grace Hopper',
                  pickupLocal: DateTime(2026, 9, 9, 10),
                  durationMin: 90,
                  driverId: 'drv_amira',
                ),
              ],
              language: AppLanguage.nl,
              drivers: const <Map<String, dynamic>>[
                <String, dynamic>{
                  'driver_id': 'drv_karel',
                  'display_name': 'Karel Peeters',
                },
                <String, dynamic>{
                  'driver_id': 'drv_amira',
                  'display_name': 'Amira Benali',
                },
              ],
              onSelectRide: (value) => selected = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 gelijktijdige ritten'), findsOneWidget);
    await tester.ensureVisible(find.text('2 gelijktijdige ritten'));
    await tester.tap(find.text('2 gelijktijdige ritten'));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaMoreSheetKey), findsOneWidget);
    expect(find.textContaining('Ada Lovelace'), findsWidgets);
    expect(find.textContaining('Grace Hopper'), findsWidgets);
    await tester.tap(find.textContaining('Grace Hopper'));
    await tester.pumpAndSettle();
    expect(selected?.bookingId, 'grace');
  });

  testWidgets('spacious hours keep the same drop slot as compact hours', (
    tester,
  ) async {
    DateTime? dropped;
    await tester.binding.setSurfaceSize(const Size(980, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(980, 720)),
          child: Scaffold(
            body: Column(
              children: [
                Draggable<CompanyCustomerListItem>(
                  data: const CompanyCustomerListItem(
                    customerId: 'cus_1',
                    displayName: 'Ada Lovelace',
                    companyName: '',
                    phoneMasked: '',
                    emailMasked: '',
                    status: 'active',
                    updatedAt: '',
                  ),
                  feedback: const SizedBox(width: 20, height: 20),
                  child: const Text('DRAGME'),
                ),
                Expanded(
                  child: CompanyAgendaCalendar(
                    period: period,
                    rides: const <CompanyAgendaRide>[],
                    language: AppLanguage.nl,
                    hourHeight: kCompanyAgendaHourHeightSpacious,
                    onAcceptCustomer: (customer, pickup) async {
                      dropped = pickup;
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final slot = find.byKey(
      Key(companyAgendaSlotKey(DateTime(2026, 9, 9, 10))),
    );
    expect(tester.getSize(slot).height, kCompanyAgendaHourHeightSpacious);
    await tester.ensureVisible(slot);
    await tester.drag(
      find.text('DRAGME'),
      tester.getCenter(slot) - tester.getCenter(find.text('DRAGME')),
    );
    await tester.pumpAndSettle();
    expect(dropped, DateTime(2026, 9, 9, 10));
  });

  testWidgets('+meer keeps hidden overlapping rides reachable', (tester) async {
    CompanyAgendaRide? selected;
    await tester.binding.setSurfaceSize(const Size(980, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(980, 720)),
          child: Scaffold(
            body: CompanyAgendaCalendar(
              period: period,
              rides: <CompanyAgendaRide>[
                for (var i = 0; i < 5; i += 1)
                  _ride(
                    id: 'crowd_$i',
                    name: 'Klant $i',
                    pickupLocal: DateTime(2026, 9, 9, 10),
                    durationMin: 60,
                    driverId: 'drv_$i',
                  ),
              ],
              language: AppLanguage.nl,
              onSelectRide: (value) => selected = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('5 gelijktijdige ritten'), findsOneWidget);
    await tester.ensureVisible(find.text('5 gelijktijdige ritten'));
    await tester.tap(find.text('5 gelijktijdige ritten'));
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaMoreSheetKey), findsOneWidget);
    await tester.tap(find.textContaining('Klant 4'));
    await tester.pumpAndSettle();
    expect(selected?.bookingId, 'crowd_4');
  });

  testWidgets('tapping a ride card selects it without a drag', (tester) async {
    CompanyAgendaRide? selected;
    final ride = _ride(
      id: 'tap_me',
      name: 'Grace Hopper',
      pickupLocal: DateTime(2026, 9, 8, 9),
      durationMin: 75,
    );
    await tester.binding.setSurfaceSize(const Size(980, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(980, 720)),
          child: Scaffold(
            body: CompanyAgendaCalendar(
              period: period,
              rides: <CompanyAgendaRide>[ride],
              language: AppLanguage.nl,
              drivers: const <Map<String, dynamic>>[],
              onSelectRide: (value) => selected = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(Key(companyAgendaRideKey('tap_me'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(companyAgendaRideKey('tap_me'))));
    await tester.pumpAndSettle();
    expect(selected?.bookingId, 'tap_me');
  });

  testWidgets('dragging a ride onto another hour keeps tap-open working', (
    tester,
  ) async {
    CompanyAgendaRide? selected;
    CompanyAgendaRide? dropped;
    DateTime? droppedAt;
    final dayPeriod = companyAgendaPeriodFor(
      view: CompanyAgendaView.day,
      anchorLocal: DateTime(2026, 9, 12, 12),
    );
    final ride = _ride(
      id: 'drag_me',
      name: 'Ada Lovelace',
      pickupLocal: DateTime(2026, 9, 12, 11),
      durationMin: 60,
    );
    await tester.binding.setSurfaceSize(const Size(980, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(980, 720)),
          child: Scaffold(
            body: CompanyAgendaCalendar(
              period: dayPeriod,
              rides: <CompanyAgendaRide>[ride],
              language: AppLanguage.nl,
              onSelectRide: (value) => selected = value,
              onAcceptRide: (value, pickup) async {
                dropped = value;
                droppedAt = pickup;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final card = find.byKey(Key(companyAgendaRideKey('drag_me')));
    final target = find.byKey(
      Key(companyAgendaSlotKey(DateTime(2026, 9, 12, 12))),
    );
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.drag(
      card,
      tester.getCenter(target) - tester.getCenter(card),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(dropped?.bookingId, 'drag_me');
    expect(droppedAt?.hour, 12);
    expect(selected, isNull);
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(selected?.bookingId, 'drag_me');
  });

  testWidgets('tooltip keeps the full ride text for a compact card', (
    tester,
  ) async {
    final ride = _ride(
      id: 'short',
      name: 'Pending',
      pickupLocal: wednesday.add(const Duration(hours: 11)),
      durationMin: 15,
    );
    final text = companyAgendaRideTooltip(
      ride,
      AppLanguage.nl,
      const CompanyAgendaDriverLook(
        driverId: '',
        displayName: '',
        color: Color(0xFF335577),
      ),
    );
    expect(text.contains('11:00'), isTrue);
    expect(text.contains('Pending'), isTrue);
    expect(text.contains('Kunstlaan 44, Brussel'), isTrue);
  });

  test('week columns fill the space between gutter and dossier', () {
    final wide = companyAgendaColumnLayout(
      availableWidth: 958,
      columnCount: 7,
      byDriver: false,
    );
    expect(wide.overflows, isFalse);
    expect(wide.gutterWidth, kCompanyAgendaTimeGutterWidth);
    expect(
      wide.columnWidth * 7,
      closeTo(958 - kCompanyAgendaTimeGutterWidth, 0.01),
    );
    expect(wide.columnWidth, lessThan(148));

    final tight = companyAgendaColumnLayout(
      availableWidth: 420,
      columnCount: 7,
      byDriver: false,
    );
    expect(tight.overflows, isTrue);
    expect(tight.columnWidth, kCompanyAgendaWeekMinColumnWidth);
  });

  testWidgets('week headers and Sunday slots share the same columns', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(958, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(958, 720)),
          child: Scaffold(
            body: CompanyAgendaCalendar(
              period: period,
              rides: const <CompanyAgendaRide>[],
              language: AppLanguage.nl,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final sunday = DateTime(2026, 9, 13);
    final header = tester.getRect(
      find.byKey(companyAgendaDayHeaderKey(sunday)),
    );
    final slot = tester.getRect(
      find.byKey(Key(companyAgendaSlotKey(DateTime(2026, 9, 13, 0)))),
    );
    expect(find.text('Zo'), findsOneWidget);
    expect(find.text('13/9'), findsOneWidget);
    expect(header.left, closeTo(slot.left, 0.5));
    expect(header.width, closeTo(slot.width, 0.5));
    expect(header.right, lessThan(959));
    expect(slot.right, lessThan(959));
  });

  testWidgets('narrow week keeps Sunday reachable by horizontal scroll', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    DateTime? dropped;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(420, 720)),
          child: Scaffold(
            body: Column(
              children: [
                Draggable<CompanyCustomerListItem>(
                  data: const CompanyCustomerListItem(
                    customerId: 'cus_1',
                    displayName: 'Ada Lovelace',
                    companyName: '',
                    phoneMasked: '',
                    emailMasked: '',
                    status: 'active',
                    updatedAt: '',
                  ),
                  feedback: const SizedBox(width: 20, height: 20),
                  child: const Text('DRAGME'),
                ),
                Expanded(
                  child: CompanyAgendaCalendar(
                    period: period,
                    rides: const <CompanyAgendaRide>[],
                    language: AppLanguage.nl,
                    onAcceptCustomer: (customer, pickup) async {
                      dropped = pickup;
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaWeekHScrollKey), findsOneWidget);
    final sundayHeader = find.byKey(
      companyAgendaDayHeaderKey(DateTime(2026, 9, 13)),
    );
    await tester.ensureVisible(sundayHeader);
    await tester.pumpAndSettle();
    final sunday = find.byKey(
      Key(companyAgendaSlotKey(DateTime(2026, 9, 13, 0))),
    );
    expect(sunday, findsOneWidget);
    await tester.ensureVisible(sunday);
    await tester.drag(
      find.text('DRAGME'),
      tester.getCenter(sunday) - tester.getCenter(find.text('DRAGME')),
    );
    await tester.pumpAndSettle();
    expect(dropped, DateTime(2026, 9, 13, 0));
  });

  testWidgets(
    'short desktop viewport can reach 12:00, 18:00 and 23:00 and scroll back',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 520));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      ScrollableState verticalScroll() {
        return tester.state<ScrollableState>(
          find.descendant(
            of: find.byKey(kCompanyAgendaWeekVScrollKey),
            matching: find.byType(Scrollable),
          ).first,
        );
      }

      Future<void> pumpView({
        required CompanyAgendaView view,
        required double hourHeight,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(size: Size(1280, 520)),
              child: Scaffold(
                body: CompanyAgendaCalendar(
                  period: companyAgendaPeriodFor(
                    view: view,
                    anchorLocal: DateTime(2026, 9, 9, 12),
                  ),
                  rides: <CompanyAgendaRide>[
                    _ride(
                      id: 'noon',
                      name: 'Middag',
                      pickupLocal: DateTime(2026, 9, 9, 12),
                      durationMin: 30,
                      driverId: 'drv_karel',
                    ),
                    _ride(
                      id: 'evening',
                      name: 'Avond',
                      pickupLocal: DateTime(2026, 9, 9, 18),
                      durationMin: 30,
                      driverId: 'drv_amira',
                    ),
                  ],
                  language: AppLanguage.nl,
                  hourHeight: hourHeight,
                  drivers: const <Map<String, dynamic>>[
                    <String, dynamic>{
                      'driver_id': 'drv_karel',
                      'display_name': 'Karel',
                    },
                    <String, dynamic>{
                      'driver_id': 'drv_amira',
                      'display_name': 'Amira',
                    },
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> expectHoursReachable() async {
        Finder hourLabel(String hour) {
          return find.descendant(
            of: find.byKey(kCompanyAgendaTimeGutterKey),
            matching: find.text(hour),
          );
        }

        expect(find.byKey(kCompanyAgendaWeekVScrollKey), findsOneWidget);
        expect(hourLabel('00:00'), findsOneWidget);
        final start = verticalScroll();
        start.position.jumpTo(0);
        await tester.pumpAndSettle();
        final headerBefore = tester.getRect(
          find.byKey(kCompanyAgendaDayHeaderRowKey),
        );
        expect(start.position.maxScrollExtent, greaterThan(800));
        expect(start.position.pixels, 0);

        for (final hour in <String>['12:00', '18:00', '23:00']) {
          await tester.ensureVisible(hourLabel(hour));
          await tester.pumpAndSettle();
          expect(hourLabel(hour).hitTestable(), findsOneWidget);
        }
        expect(verticalScroll().position.pixels, greaterThan(800));

        await tester.ensureVisible(hourLabel('00:00'));
        await tester.pumpAndSettle();
        expect(hourLabel('00:00').hitTestable(), findsOneWidget);
        expect(verticalScroll().position.pixels, lessThan(16));

        await tester.drag(hourLabel('00:00'), const Offset(0, -240));
        await tester.pumpAndSettle();
        expect(verticalScroll().position.pixels, greaterThan(80));
        expect(
          tester.getRect(find.byKey(kCompanyAgendaDayHeaderRowKey)),
          headerBefore,
        );
      }

      for (final view in <CompanyAgendaView>[
        CompanyAgendaView.week,
        CompanyAgendaView.day,
        CompanyAgendaView.byDriver,
      ]) {
        for (final hourHeight in <double>[
          kCompanyAgendaHourHeightCompact,
          kCompanyAgendaHourHeightSpacious,
        ]) {
          await pumpView(view: view, hourHeight: hourHeight);
          await expectHoursReachable();
        }
      }
    },
  );

  test('overlapping wednesday rides sit side by side on the true duration', () {
    final ada = _ride(
      id: 'ada',
      name: 'Ada Lovelace',
      pickupLocal: DateTime(2026, 9, 9, 9),
      durationMin: 120,
      driverId: 'drv_karel',
    );
    final grace = _ride(
      id: 'grace',
      name: 'Grace Hopper',
      pickupLocal: DateTime(2026, 9, 9, 10),
      durationMin: 90,
      driverId: 'drv_amira',
    );
    final pack = companyAgendaPackDayRides(
      rides: <CompanyAgendaRide>[ada, grace],
      day: DateTime(2026, 9, 9),
      columnWidth: 220,
    );
    expect(pack.visible, hasLength(2));
    expect(pack.overflows, isEmpty);
    final first = pack.visible.firstWhere((item) => item.ride.bookingId == 'ada');
    final second = pack.visible.firstWhere(
      (item) => item.ride.bookingId == 'grace',
    );
    expect(first.columnIndex, 0);
    expect(second.columnIndex, 1);
    expect(first.columnCount, 2);
    expect(second.columnCount, 2);
    expect(first.height, closeTo(120 / 60 * kCompanyAgendaHourHeight, 0.1));
    expect(second.height, closeTo(90 / 60 * kCompanyAgendaHourHeight, 0.1));
    expect(second.top, closeTo(10 * kCompanyAgendaHourHeight, 0.1));
    final firstRect = companyAgendaPackedRideRect(
      packed: first,
      columnWidth: 220,
      reserveMoreRail: false,
    );
    final secondRect = companyAgendaPackedRideRect(
      packed: second,
      columnWidth: 220,
      reserveMoreRail: false,
    );
    expect(firstRect.overlaps(secondRect), isFalse);
    expect(secondRect.left, greaterThan(firstRect.right));
    expect(firstRect.width, greaterThanOrEqualTo(80));
    final tight = companyAgendaPackDayRides(
      rides: <CompanyAgendaRide>[ada, grace],
      day: DateTime(2026, 9, 9),
      columnWidth: kCompanyAgendaWeekMinColumnWidth,
    );
    expect(tight.visible, isEmpty);
    expect(tight.overflows, hasLength(1));
    expect(tight.overflows.single.all, hasLength(2));
  });

  test('hour density scales drawing without stretching a short ride', () {
    final ride = _ride(
      id: 'short',
      name: 'Pending',
      pickupLocal: DateTime(2026, 9, 7, 11),
      durationMin: 15,
    );
    final compact = companyAgendaRideLayout(ride, DateTime(2026, 9, 7));
    final spacious = companyAgendaRideLayout(
      ride,
      DateTime(2026, 9, 7),
      hourHeight: kCompanyAgendaHourHeightSpacious,
    );
    expect(compact!.height, closeTo(15 / 60 * kCompanyAgendaHourHeight, 0.1));
    expect(
      spacious!.height,
      closeTo(15 / 60 * kCompanyAgendaHourHeightSpacious, 0.1),
    );
    expect(spacious.height / compact.height, closeTo(120 / 72, 0.01));
  });

  test('many simultaneous rides keep a +meer overflow', () {
    final rides = <CompanyAgendaRide>[
      for (var i = 0; i < 5; i += 1)
        _ride(
          id: 'crowd_$i',
          name: 'Klant $i',
          pickupLocal: DateTime(2026, 9, 9, 10),
          durationMin: 60,
          driverId: 'drv_$i',
        ),
    ];
    final pack = companyAgendaPackDayRides(
      rides: rides,
      day: DateTime(2026, 9, 9),
      columnWidth: 80,
    );
    expect(companyAgendaMaxVisibleOverlapColumns(80), 1);
    expect(pack.visible, isEmpty);
    expect(pack.overflows, hasLength(1));
    expect(pack.overflows.single.hidden, hasLength(5));
    expect(
      companyAgendaMoreLabel(3, AppLanguage.nl),
      '3 gelijktijdige ritten',
    );
    final wide = companyAgendaPackDayRides(
      rides: rides,
      day: DateTime(2026, 9, 9),
      columnWidth: 220,
    );
    expect(companyAgendaMaxVisibleOverlapColumns(220), 2);
    expect(wide.visible, hasLength(2));
    expect(wide.overflows.single.hidden, hasLength(3));
  });

  testWidgets('phone day list shows time customer and assignment', (
    tester,
  ) async {
    CompanyAgendaRide? selected;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Scaffold(
            body: CompanyAgendaPhoneDayPane(
              anchor: DateTime(2026, 9, 9, 12),
              rides: <CompanyAgendaRide>[
                _ride(
                  id: 'ada',
                  name: 'Ada Lovelace',
                  pickupLocal: DateTime(2026, 9, 9, 9),
                  durationMin: 120,
                ),
                _ride(
                  id: 'grace',
                  name: 'Grace Hopper',
                  pickupLocal: DateTime(2026, 9, 9, 10),
                  durationMin: 90,
                  driverId: 'drv_amira',
                ),
              ],
              language: AppLanguage.nl,
              drivers: const <Map<String, dynamic>>[
                <String, dynamic>{
                  'driver_id': 'drv_amira',
                  'display_name': 'Amira Benali',
                },
              ],
              onSelectRide: (value) => selected = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kCompanyAgendaWeekStripKey), findsOneWidget);
    expect(find.byKey(kCompanyAgendaPhoneDayListKey), findsOneWidget);
    expect(find.textContaining('09:00–11:00'), findsWidgets);
    expect(find.textContaining('Ada Lovelace'), findsWidgets);
    expect(
      find.textContaining(kCompanyAgendaUnassignedLane.of(AppLanguage.nl)),
      findsWidgets,
    );
    expect(find.textContaining('Amira Benali'), findsWidgets);
    await tester.tap(find.byKey(Key(companyAgendaRideKey('ada'))));
    await tester.pumpAndSettle();
    expect(selected?.bookingId, 'ada');
  });

  test('driver filter keeps only that chauffeur\'s rides', () {
    final karel = _ride(
      id: 'karel',
      name: 'Ada Lovelace',
      pickupLocal: DateTime(2026, 9, 9, 10),
      durationMin: 60,
      driverId: 'drv_karel',
    );
    final amira = _ride(
      id: 'amira',
      name: 'Grace Hopper',
      pickupLocal: DateTime(2026, 9, 9, 11),
      durationMin: 60,
      driverId: 'drv_amira',
    );
    expect(
      companyAgendaRidesAssignedTo(
        rides: <CompanyAgendaRide>[karel, amira],
        driverId: 'drv_karel',
      ),
      <CompanyAgendaRide>[karel],
    );
    expect(
      companyAgendaRidesAssignedTo(rides: <CompanyAgendaRide>[karel, amira]),
      <CompanyAgendaRide>[karel, amira],
    );
  });

  test('day column keeps a single ride at a readable max width', () {
    final ride = _ride(
      id: 'solo',
      name: 'Ada Lovelace',
      pickupLocal: DateTime(2026, 9, 12, 11),
      durationMin: 60,
    );
    final packed = CompanyAgendaPackedRide(
      ride: ride,
      top: 11 * kCompanyAgendaHourHeight,
      height: kCompanyAgendaHourHeight,
      columnIndex: 0,
      columnCount: 1,
    );
    final wide = companyAgendaPackedRideRect(
      packed: packed,
      columnWidth: 980,
      reserveMoreRail: false,
    );
    expect(companyAgendaShouldCapRideWidth(980), isTrue);
    expect(wide.width, kCompanyAgendaDayRideMaxWidth);
    expect(wide.width, lessThan(400));
    expect(wide.height, closeTo(kCompanyAgendaHourHeight - 2, 0.1));
    expect(wide.left, kCompanyAgendaRideInset);
    final week = companyAgendaPackedRideRect(
      packed: packed,
      columnWidth: 148,
      reserveMoreRail: false,
    );
    expect(companyAgendaShouldCapRideWidth(148), isFalse);
    expect(week.width, closeTo(148 - kCompanyAgendaRideInset * 2, 0.1));
  });

  test('four consecutive 15-minute rides stack on their exact times', () {
    final rides = <CompanyAgendaRide>[
      for (var i = 0; i < 4; i += 1)
        _ride(
          id: 'q$i',
          name: 'Klant $i',
          pickupLocal: DateTime(2026, 9, 12, 10, i * 15),
          durationMin: 15,
          driverId: 'drv_$i',
        ),
    ];
    final pack = companyAgendaPackDayRides(
      rides: rides,
      day: DateTime(2026, 9, 12),
      columnWidth: 980,
    );
    expect(pack.visible, hasLength(4));
    expect(pack.overflows, isEmpty);
    for (var i = 0; i < 4; i += 1) {
      final item = pack.visible.firstWhere(
        (ride) => ride.ride.bookingId == 'q$i',
      );
      expect(item.columnIndex, 0);
      expect(item.columnCount, 1);
      expect(
        item.top,
        closeTo((10 + i * 0.25) * kCompanyAgendaHourHeight, 0.1),
      );
      expect(item.height, closeTo(15 / 60 * kCompanyAgendaHourHeight, 0.1));
      expect(item.height < 22, isTrue);
    }
  });

  test('three simultaneous short rides stay side by side in a day column', () {
    final rides = <CompanyAgendaRide>[
      _ride(
        id: 'karel',
        name: 'Ada Lovelace',
        pickupLocal: DateTime(2026, 9, 12, 10),
        durationMin: 15,
        driverId: 'drv_karel',
      ),
      _ride(
        id: 'amira',
        name: 'Grace Hopper',
        pickupLocal: DateTime(2026, 9, 12, 10),
        durationMin: 15,
        driverId: 'drv_amira',
      ),
      _ride(
        id: 'tom',
        name: 'Marie Curie',
        pickupLocal: DateTime(2026, 9, 12, 10),
        durationMin: 15,
        driverId: 'drv_tom',
      ),
    ];
    final day = companyAgendaPackDayRides(
      rides: rides,
      day: DateTime(2026, 9, 12),
      columnWidth: 980,
    );
    expect(day.visible, hasLength(3));
    expect(day.overflows, isEmpty);
    final widths = <double>[];
    for (final packed in day.visible) {
      expect(packed.columnCount, 3);
      expect(packed.height, closeTo(15 / 60 * kCompanyAgendaHourHeight, 0.1));
      final rect = companyAgendaPackedRideRect(
        packed: packed,
        columnWidth: 980,
        reserveMoreRail: false,
      );
      widths.add(rect.width);
      expect(rect.width, greaterThanOrEqualTo(80));
      expect(rect.width, lessThanOrEqualTo(kCompanyAgendaDayRideMaxWidth + 0.1));
    }
    expect(widths[1], closeTo(widths[0], 0.5));
    final week = companyAgendaPackDayRides(
      rides: rides,
      day: DateTime(2026, 9, 12),
      columnWidth: kCompanyAgendaWeekMinColumnWidth,
    );
    expect(week.visible, isEmpty);
    expect(week.overflows, hasLength(1));
    expect(week.overflows.single.all, hasLength(3));
  });

  testWidgets('day view draws quarter-hour guides and a bounded ride card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(980, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dayPeriod = companyAgendaPeriodFor(
      view: CompanyAgendaView.day,
      anchorLocal: DateTime(2026, 9, 12, 12),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(980, 720)),
          child: Scaffold(
            body: CompanyAgendaCalendar(
              period: dayPeriod,
              rides: <CompanyAgendaRide>[
                _ride(
                  id: 'solo',
                  name: 'Ada Lovelace',
                  pickupLocal: DateTime(2026, 9, 12, 11),
                  durationMin: 60,
                ),
              ],
              language: AppLanguage.nl,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final slot = DateTime(2026, 9, 12, 11);
    expect(find.byKey(companyAgendaQuarterLineKey(slot, 1)), findsOneWidget);
    expect(find.byKey(companyAgendaQuarterLineKey(slot, 2)), findsOneWidget);
    expect(find.byKey(companyAgendaQuarterLineKey(slot, 3)), findsOneWidget);
    final card = tester.getRect(find.byKey(Key(companyAgendaRideKey('solo'))));
    expect(card.width, lessThanOrEqualTo(kCompanyAgendaDayRideMaxWidth + 1));
    expect(card.width, greaterThan(200));
    expect(card.height, closeTo(kCompanyAgendaHourHeight - 2, 2));
  });

  testWidgets('by driver keeps three simultaneous short rides on their hour', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final period = companyAgendaPeriodFor(
      view: CompanyAgendaView.byDriver,
      anchorLocal: DateTime(2026, 9, 12, 12),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1100, 720)),
          child: Scaffold(
            body: CompanyAgendaCalendar(
              period: period,
              rides: <CompanyAgendaRide>[
                _ride(
                  id: 'karel',
                  name: 'Ada Lovelace',
                  pickupLocal: DateTime(2026, 9, 12, 10),
                  durationMin: 15,
                  driverId: 'drv_karel',
                ),
                _ride(
                  id: 'amira',
                  name: 'Grace Hopper',
                  pickupLocal: DateTime(2026, 9, 12, 10),
                  durationMin: 15,
                  driverId: 'drv_amira',
                ),
                _ride(
                  id: 'tom',
                  name: 'Marie Curie',
                  pickupLocal: DateTime(2026, 9, 12, 10),
                  durationMin: 15,
                  driverId: 'drv_tom',
                ),
              ],
              language: AppLanguage.nl,
              drivers: const <Map<String, dynamic>>[
                <String, dynamic>{
                  'driver_id': 'drv_karel',
                  'display_name': 'Karel Peeters',
                },
                <String, dynamic>{
                  'driver_id': 'drv_amira',
                  'display_name': 'Amira Benali',
                },
                <String, dynamic>{
                  'driver_id': 'drv_tom',
                  'display_name': 'Tom Janssen',
                },
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(Key(companyAgendaRideKey('karel'))));
    await tester.ensureVisible(find.byKey(Key(companyAgendaRideKey('amira'))));
    await tester.ensureVisible(find.byKey(Key(companyAgendaRideKey('tom'))));
    await tester.pumpAndSettle();
    final karel = tester.getRect(find.byKey(Key(companyAgendaRideKey('karel'))));
    final amira = tester.getRect(find.byKey(Key(companyAgendaRideKey('amira'))));
    final tom = tester.getRect(find.byKey(Key(companyAgendaRideKey('tom'))));
    expect(karel.height, closeTo(15 / 60 * kCompanyAgendaHourHeight, 3));
    expect(amira.left, greaterThan(karel.right - 0.5));
    expect(tom.left, greaterThan(amira.right - 0.5));
    expect((karel.top - amira.top).abs(), lessThan(1));
  });
}
