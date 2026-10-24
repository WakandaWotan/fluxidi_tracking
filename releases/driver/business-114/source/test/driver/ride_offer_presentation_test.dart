import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart' show VehicleProfile;
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer_panel.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer_presentation.dart';
import 'fixtures/driver_ride_offer_panel_before.dart' as before;

const vehicleId = 'vh_fixture_internal';
const pickup = 'Koekamerstraat 48 bus A, 9688 Schorisse';
const destination = 'Broeke 98, appartement 12 bus B, 9600 Ronse';
DriverRideOffer offer({
  double? price = 125,
  int passengers = 1,
  String from = pickup,
}) => DriverRideOffer(
  id: 'private_offer_fixture',
  version: 1,
  vehicleId: vehicleId,
  deadlineMs: 30000,
  pickup: from,
  destination: destination,
  requestedVehicleLabel: vehicleId,
  pickupTime: DateTime.utc(2026, 10, 16, 9, 27),
  requirements: {'passengers': passengers, 'luggage': 0},
  price: price,
);
ActiveDriverSession owner({String company = 'C', String vehicle = vehicleId}) =>
    ActiveDriverSession(
      driverId: 'D',
      employeeNumber: '',
      fullName: 'Fixture',
      phone: '',
      loggedInAt: '',
      updatedAt: '',
      tenantId: 'T',
      companyId: company,
      assignedVehicleId: vehicle,
      linkMethod: 'standalone_driver',
    );
VehicleProfile vehicle({
  String? company = 'C',
  String name = 'Mercedes Vito',
  int capacity = 8,
}) => VehicleProfile(
  id: vehicleId,
  vehicleName: name,
  brandModel: name,
  licensePlate: 'FIXTURE',
  color: '',
  passengerCapacity: capacity,
  luggageCapacity: 0,
  tierId: '',
  isActive: true,
  driverId: 'D',
  companyId: company,
  primaryPhotoRef: '',
  galleryPhotoRefs: const [],
);

const known = DriverRideOfferVehiclePresentation(
  name: 'Mercedes Vito',
  capacity: 8,
);
final theme = ThemeData(
  brightness: Brightness.dark,
  fontFamily: 'Roboto',
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFFE6B940),
    onPrimary: Colors.black,
    surface: Color(0xFF111214),
    onSurface: Colors.white,
  ),
);
Future<void> pump(
  WidgetTester tester,
  Widget panel, {
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RepaintBoundary(key: const Key('render'), child: panel),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() async {
    for (final file in {
      'Roboto': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      final loader = FontLoader(file.key)
        ..addFont(
          File(
            'C:/dev/flutter/bin/cache/artifacts/material_fonts/${file.value}',
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    }
  });
  test(
    'only exact company and active-session vehicle metadata is displayed',
    () {
      final result = driverRideOfferVehiclePresentation(
        vehicleId: vehicleId,
        session: owner(),
        vehicles: [vehicle()],
      );
      expect(result.name, 'Mercedes Vito');
      expect(result.capacity, 8);
      for (final vehicles in [
        [vehicle(company: 'FOREIGN')],
        [vehicle(company: null)],
        [vehicle(), vehicle()],
      ]) {
        expect(
          driverRideOfferVehiclePresentation(
            vehicleId: vehicleId,
            session: owner(),
            vehicles: vehicles,
          ).name,
          isNull,
        );
      }
      expect(
        driverRideOfferVehiclePresentation(
          vehicleId: vehicleId,
          session: owner(vehicle: 'OTHER'),
          vehicles: [vehicle()],
        ).name,
        isNull,
      );
      expect(
        driverRideOfferVehiclePresentation(
          vehicleId: vehicleId,
          session: null,
          vehicles: [vehicle()],
        ).name,
        isNull,
      );
      expect(
        driverRideOfferVehiclePresentation(
          vehicleId: vehicleId,
          session: owner(),
          vehicles: [vehicle(name: vehicleId)],
        ).name,
        isNull,
      );
    },
  );
  for (final price in [null, -1.0, double.nan, double.infinity]) {
    testWidgets('missing or invalid display price remains unconfirmed $price', (
      tester,
    ) async {
      await pump(
        tester,
        DriverRideOfferPanel(
          offer: offer(price: price),
          nowMs: 0,
          onDecision: (_) {},
        ),
      );
      expect(find.text('Prijs nog niet bevestigd'), findsOneWidget);
      expect(find.text('Prijs op aanvraag'), findsNothing);
      expect(find.text('Inclusief btw'), findsNothing);
    });
  }
  testWidgets(
    'explicit server zero remains valid without a numeric zero fallback',
    (tester) async {
      await pump(
        tester,
        DriverRideOfferPanel(
          offer: offer(price: 0),
          nowMs: 0,
          onDecision: (_) {},
        ),
      );
      expect(find.text('Kosteloze rit'), findsOneWidget);
      expect(find.textContaining('€ 0'), findsNothing);
      expect(find.text('Prijs nog niet bevestigd'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('accept_ride')))
            .onPressed,
        isNotNull,
      );
    },
  );
  for (final passengers in [1, 2]) {
    testWidgets(
      'passenger singular/plural $passengers and zero luggage hidden',
      (tester) async {
        await pump(
          tester,
          DriverRideOfferPanel(
            offer: offer(passengers: passengers),
            nowMs: 0,
            vehiclePresentation: known,
            onDecision: (_) {},
          ),
        );
        expect(
          find.text(passengers == 1 ? '1 persoon' : '2 personen'),
          findsOneWidget,
        );
        expect(find.textContaining('0 koffer'), findsNothing);
        expect(find.text('Mercedes Vito · 8 personen'), findsOneWidget);
        expect(find.text('€ 125,00'), findsOneWidget);
        expect(find.text('Inclusief btw'), findsOneWidget);
        expect(find.textContaining(vehicleId), findsNothing);
      },
    );
  }
  testWidgets(
    'unknown name does not expose requested or assigned technical id',
    (tester) async {
      await pump(
        tester,
        DriverRideOfferPanel(offer: offer(), nowMs: 0, onDecision: (_) {}),
      );
      expect(find.text('Voertuig'), findsOneWidget);
      expect(find.textContaining(vehicleId), findsNothing);
      expect(find.textContaining('Requested vehicle'), findsNothing);
    },
  );
  for (final size in [
    const Size(320, 568),
    const Size(430, 932),
    const Size(900, 1200),
  ]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('long full addresses and pinned actions $size scale=$scale', (
        tester,
      ) async {
        final long =
            '$pickup, toegang via de hoofdingang achter het gebouw bij de vaste oprit';
        final actions = <String>[];
        await pump(
          tester,
          DriverRideOfferPanel(
            offer: offer(from: long),
            nowMs: 0,
            vehiclePresentation: known,
            onDecision: actions.add,
          ),
          size: size,
          scale: scale,
        );
        for (final key in ['accept_ride', 'decline_ride', 'offer_deadline']) {
          final rect = tester.getRect(find.byKey(ValueKey(key)));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(size.height));
        }
        final scroll = find.descendant(
          of: find.byKey(const ValueKey('ride_offer_content')),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('offer_pickup')),
          80,
          scrollable: scroll,
        );
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('offer_pickup'))).data,
          long,
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('offer_pickup')))
              .maxLines,
          isNull,
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('offer_destination')),
          80,
          scrollable: scroll,
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('offer_destination')))
              .data,
          destination,
        );
        await tester.tap(find.byKey(const ValueKey('accept_ride')));
        await tester.tap(find.byKey(const ValueKey('decline_ride')));
        expect(actions, ['accept', 'decline']);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('same timer boundaries and opposite-pending/busy guards', (
    tester,
  ) async {
    for (final now in [0, 10000, 29999, 30000]) {
      await pump(
        tester,
        DriverRideOfferPanel(offer: offer(), nowMs: now, onDecision: (_) {}),
      );
      final remaining = offer().secondsRemaining(now);
      expect(
        find.text(
          remaining > 0
              ? 'Beslistijd · $remaining s'
              : 'Reactietijd verstreken',
        ),
        findsOneWidget,
      );
      expect(
        tester
                .widget<FilledButton>(find.byKey(const ValueKey('accept_ride')))
                .onPressed ==
            null,
        now >= 30000,
      );
    }
    for (final pending in ['accept', 'decline']) {
      await pump(
        tester,
        DriverRideOfferPanel(
          offer: offer(),
          nowMs: 0,
          pendingAction: pending,
          onDecision: (_) {},
        ),
      );
      final forbidden = pending == 'accept'
          ? find.byKey(const ValueKey('decline_ride'))
          : find.byKey(const ValueKey('accept_ride'));
      expect(
        pending == 'accept'
            ? tester.widget<OutlinedButton>(forbidden).onPressed
            : tester.widget<FilledButton>(forbidden).onPressed,
        isNull,
      );
    }
    await pump(
      tester,
      DriverRideOfferPanel(
        offer: offer(),
        nowMs: 0,
        busy: true,
        onDecision: (_) => fail('busy'),
      ),
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('accept_ride')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('decline_ride')))
          .onPressed,
      isNull,
    );
  });
  for (final size in [const Size(390, 844), const Size(900, 1200)]) {
    for (final original in [true, false]) {
      testWidgets('render ${original ? 'before' : 'after'} width=${size.width}', (
        tester,
      ) async {
        final fixture = offer(price: null);
        await pump(
          tester,
          original
              ? before.DriverRideOfferPanel(
                  offer: fixture,
                  nowMs: 0,
                  onDecision: (_) {},
                )
              : DriverRideOfferPanel(
                  offer: fixture,
                  nowMs: 0,
                  vehiclePresentation: known,
                  onDecision: (_) {},
                ),
          size: size,
        );
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('render')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'D:/Projecten/outputs/business_driver_offer_ui_20261014/screens/${original ? 'before' : 'after'}-${size.width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}
