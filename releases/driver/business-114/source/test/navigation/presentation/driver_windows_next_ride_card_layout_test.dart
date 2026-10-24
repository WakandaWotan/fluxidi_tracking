import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_windows_map_slot.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required Size surface,
    required double paneHeight,
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: surface),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: surface.width * 0.6,
                height: paneHeight,
                child: Column(
                  children: [
                    const SizedBox(
                      height: 80,
                      child: ColoredBox(color: Color(0xFFEEEEEE)),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Column(
                        children: [
                          const SizedBox(
                            height: 148,
                            child: ColoredBox(color: Color(0xFFDDDDDD)),
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return ColoredBox(
                                  key: const ValueKey<String>(
                                    'driver_windows_next_ride_map',
                                  ),
                                  color: const Color(0xFF111111),
                                  child: SizedBox.expand(
                                    child: Text(
                                      constraints.maxHeight.toStringAsFixed(0),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(
                            key: ValueKey<String>(
                              'driver_windows_next_ride_actions',
                            ),
                            height: 48,
                            child: ColoredBox(color: Color(0xFF228866)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('1524x869 map grows and buttons sit on the card bottom', (
    tester,
  ) async {
    const surface = Size(kDriverWindowsWideWidth, kDriverWindowsWideHeight);
    const pane = 520.0;
    await pumpCard(tester, surface: surface, paneHeight: pane);
    expect(tester.takeException(), isNull);
    final map = tester.getRect(
      find.byKey(const ValueKey<String>('driver_windows_next_ride_map')),
    );
    final buttons = tester.getRect(
      find.byKey(const ValueKey<String>('driver_windows_next_ride_actions')),
    );
    expect(map.height, greaterThan(220));
    expect(buttons.top, closeTo(map.bottom, 1));
    expect(
      tester.getRect(find.byType(Scaffold)).bottom - buttons.bottom,
      greaterThan(0),
    );
  });

  testWidgets('1100x720 map fills leftover height without overflow', (
    tester,
  ) async {
    const surface = Size(
      kDriverWindowsCompactWidth,
      kDriverWindowsCompactHeight,
    );
    const pane = 480.0;
    await pumpCard(tester, surface: surface, paneHeight: pane);
    expect(tester.takeException(), isNull);
    final map = tester.getSize(
      find.byKey(const ValueKey<String>('driver_windows_next_ride_map')),
    );
    expect(map.height, greaterThan(180));
    expect(map.height + 80 + 10 + 148 + 48, closeTo(pane, 1));
  });
}
