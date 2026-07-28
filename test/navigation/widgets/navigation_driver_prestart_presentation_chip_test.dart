import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_prestart_presentation.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_prestart_presentation_chip.dart';

// NAV-PRESTART-FIELD-BLOCKER-3 (Problem C + D) widget tests.
//
// Pins the visual + interaction contract of the pre-start-only camera preset
// chip. The chip must render, expose the correct toggle, use the cube glyph
// so it stays distinct from the map style chip (which now uses the apartment
// glyph for 3D-buildings), and emit the opposite mode on tap.

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: child),
    ),
  );
}

void main() {
  group('NavigationDriverPreStartPresentationChip', () {
    testWidgets('renders outlined cube in overview mode', (tester) async {
      await tester.pumpWidget(
        _wrap(
          NavigationDriverPreStartPresentationChip(
            mode: NavPreviewPresentationMode.overview,
            onModeChanged: (_) {},
            accentColor: const Color(0xFFE5B641),
            textColor: Colors.white,
            surfaceColor: const Color(0xCC0B1326),
            tooltipOverview: 'Overview',
            tooltipStreetlevel: 'Street level',
          ),
        ),
      );
      expect(find.byIcon(Icons.view_in_ar_outlined), findsOneWidget);
      expect(find.byIcon(Icons.view_in_ar), findsNothing);
    });

    testWidgets('renders filled cube in streetlevel mode', (tester) async {
      await tester.pumpWidget(
        _wrap(
          NavigationDriverPreStartPresentationChip(
            mode: NavPreviewPresentationMode.streetLevel,
            onModeChanged: (_) {},
            accentColor: const Color(0xFFE5B641),
            textColor: Colors.white,
            surfaceColor: const Color(0xCC0B1326),
            tooltipOverview: 'Overview',
            tooltipStreetlevel: 'Street level',
          ),
        ),
      );
      expect(find.byIcon(Icons.view_in_ar), findsOneWidget);
      expect(find.byIcon(Icons.view_in_ar_outlined), findsNothing);
    });

    testWidgets('does NOT use the apartment icon reserved for map style',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          NavigationDriverPreStartPresentationChip(
            mode: NavPreviewPresentationMode.overview,
            onModeChanged: (_) {},
            accentColor: const Color(0xFFE5B641),
            textColor: Colors.white,
            surfaceColor: const Color(0xCC0B1326),
            tooltipOverview: 'Overview',
            tooltipStreetlevel: 'Street level',
          ),
        ),
      );
      expect(find.byIcon(Icons.apartment_outlined), findsNothing);
    });

    testWidgets('tapping overview chip emits streetLevel', (tester) async {
      NavPreviewPresentationMode? seen;
      await tester.pumpWidget(
        _wrap(
          NavigationDriverPreStartPresentationChip(
            mode: NavPreviewPresentationMode.overview,
            onModeChanged: (next) => seen = next,
            accentColor: const Color(0xFFE5B641),
            textColor: Colors.white,
            surfaceColor: const Color(0xCC0B1326),
            tooltipOverview: 'Overview',
            tooltipStreetlevel: 'Street level',
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.view_in_ar_outlined));
      await tester.pump();
      expect(seen, NavPreviewPresentationMode.streetLevel);
    });

    testWidgets('tapping streetlevel chip emits overview', (tester) async {
      NavPreviewPresentationMode? seen;
      await tester.pumpWidget(
        _wrap(
          NavigationDriverPreStartPresentationChip(
            mode: NavPreviewPresentationMode.streetLevel,
            onModeChanged: (next) => seen = next,
            accentColor: const Color(0xFFE5B641),
            textColor: Colors.white,
            surfaceColor: const Color(0xCC0B1326),
            tooltipOverview: 'Overview',
            tooltipStreetlevel: 'Street level',
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.view_in_ar));
      await tester.pump();
      expect(seen, NavPreviewPresentationMode.overview);
    });

    testWidgets('honours the requested button size (touch target)',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          NavigationDriverPreStartPresentationChip(
            mode: NavPreviewPresentationMode.overview,
            onModeChanged: (_) {},
            accentColor: const Color(0xFFE5B641),
            textColor: Colors.white,
            surfaceColor: const Color(0xCC0B1326),
            tooltipOverview: 'Overview',
            tooltipStreetlevel: 'Street level',
            buttonSize: 44,
            iconSize: 22,
          ),
        ),
      );
      final inkWellSize = tester.getSize(find.byType(InkWell));
      expect(inkWellSize.width, 44);
      expect(inkWellSize.height, 44);
      final iconWidget = tester.widget<Icon>(
        find.byIcon(Icons.view_in_ar_outlined),
      );
      expect(iconWidget.size, 22);
    });
  });
}
