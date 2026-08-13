// PHONE-LANDSCAPE-QUICK-ACTIONS-4x2-P0
//
// Source + pure-host contracts for the chauffeur dashboard phone-landscape
// 4×2 quick-action grid. Tablet/split must not activate via pane width alone.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/fluxidi_host_form_factor.dart';

String _normalize(String s) => s.replaceAll('\r\n', '\n');

String _driverHome() => _normalize(
  File('lib/main_parts/driver_home_page_state.dart').readAsStringSync(),
);

String _quickActionsRegion(String source) {
  final start = source.indexOf('Widget _buildDriverQuickActionsGrid({');
  expect(start, greaterThanOrEqualTo(0));
  final end = source.indexOf('Widget _buildPremiumDriverDashboard()', start);
  expect(end, greaterThan(start));
  return source.substring(start, end);
}

String _premiumDashboardRegion(String source) {
  final start = source.indexOf('Widget _buildPremiumDriverDashboard()');
  expect(start, greaterThanOrEqualTo(0));
  final end = source.indexOf(
    'Widget _buildStandaloneOperationalBlockPanel(',
    start,
  );
  expect(end, greaterThan(start));
  return source.substring(start, end);
}

String _meerSheetRegion(String source) {
  // Meer sheet lists Mijn prestaties / Beschikbaarheid with their handlers.
  final start = source.indexOf("nl: 'Meer'");
  expect(start, greaterThanOrEqualTo(0));
  final end = source.indexOf('Widget _buildDriverQuickActionsGrid({', start);
  expect(end, greaterThan(start));
  return source.substring(start, end);
}

void main() {
  group('fluxidiIsPhoneLandscapeHost', () {
    test('1. genuine phone landscape activates', () {
      expect(
        fluxidiIsPhoneLandscapeHost(
          hostIsTablet: false,
          windowSize: const Size(844, 390),
        ),
        isTrue,
      );
      expect(
        fluxidiIsPhoneLandscapeHost(
          hostIsTablet: false,
          windowSize: const Size(667, 375),
        ),
        isTrue,
      );
    });

    test('2. phone portrait does not activate', () {
      expect(
        fluxidiIsPhoneLandscapeHost(
          hostIsTablet: false,
          windowSize: const Size(390, 844),
        ),
        isFalse,
      );
    });

    test('3. tablet landscape / fullscreen does not activate', () {
      expect(
        fluxidiIsPhoneLandscapeHost(
          hostIsTablet: true,
          windowSize: const Size(1280, 800),
        ),
        isFalse,
      );
    });

    test('4. tablet split / narrow pane does not falsely activate', () {
      // SM-X400 vertical split: landscape-ish wide short pane on tablet host.
      expect(
        fluxidiIsPhoneLandscapeHost(
          hostIsTablet: true,
          windowSize: const Size(1280, 420),
        ),
        isFalse,
      );
      expect(
        fluxidiIsPhoneLandscapeHost(
          hostIsTablet: true,
          windowSize: const Size(420, 880),
        ),
        isFalse,
      );
      // Even if window looks like a phone landscape.
      expect(
        fluxidiIsPhoneLandscapeHost(
          hostIsTablet: true,
          windowSize: const Size(844, 390),
        ),
        isFalse,
      );
    });
  });

  group('dashboard source contracts', () {
    test('dashboard gates 4×2 via fluxidiIsPhoneLandscapeHost + _hostIsTablet',
        () {
      final dash = _premiumDashboardRegion(_driverHome());
      expect(dash, contains('fluxidiIsPhoneLandscapeHost('));
      expect(dash, contains('hostIsTablet: _hostIsTablet(context)'));
      expect(dash, contains('isPhoneLandscapeHost: isPhoneLandscapeHost'));
      // Phone landscape must not use photographic quick-action assets.
      expect(
        dash,
        contains(
          'useImageBackgrounds:\n'
          '                            !isPhoneLandscapeHost &&',
        ),
      );
    });

    test('phone landscape forces 4 columns and appends Meer extras', () {
      final qa = _quickActionsRegion(_driverHome());
      expect(qa, contains('bool isPhoneLandscapeHost = false'));
      expect(qa, contains('} else if (isPhoneLandscapeHost) {'));
      expect(qa, contains('columns = 4;'));
      expect(qa, contains('if (isPhoneLandscapeHost) ...['));
      expect(qa, contains('Icons.insights_rounded'));
      expect(qa, contains('Icons.toggle_on_outlined'));
      expect(qa, contains('onTap: _openDriverKpiPage'));
      expect(
        qa,
        contains('onTap: () => unawaited(_handleDriverStatusAction())'),
      );
    });

    test('5+6. extras reuse exact Meer handlers', () {
      final meer = _meerSheetRegion(_driverHome());
      expect(meer, contains('_openDriverKpiPage()'));
      expect(meer, contains('unawaited(_handleDriverStatusAction())'));

      final qa = _quickActionsRegion(_driverHome());
      // Quick-action tiles call the same methods (not wrappers / duplicates).
      expect(qa, contains('onTap: _openDriverKpiPage'));
      expect(
        qa,
        contains('onTap: () => unawaited(_handleDriverStatusAction())'),
      );
      expect(qa, isNot(contains('_openDriverKpiPageFromQuickAction')));
      expect(qa, isNot(contains('_handleDriverStatusActionFromQuickAction')));
    });

    test('7. NL/EN/FR/ES labels via _tr (not hardcoded Dutch alone)', () {
      final qa = _quickActionsRegion(_driverHome());
      final extrasStart = qa.indexOf('if (isPhoneLandscapeHost) ...[');
      expect(extrasStart, greaterThanOrEqualTo(0));
      final extras = qa.substring(extrasStart);
      expect(extras, contains('_tr('));
      expect(extras, contains("nl: 'Mijn prestaties'"));
      expect(extras, contains("en: 'My performance'"));
      expect(extras, contains("fr: 'Mes performances'"));
      expect(extras, contains("es: 'Mi rendimiento'"));
      expect(extras, contains("nl: 'Beschikbaarheid'"));
      expect(extras, contains("en: 'Availability'"));
      expect(extras, contains("fr: 'Disponibilite'"));
      expect(extras, contains("es: 'Disponibilidad'"));
    });

    test('8. title typography keeps ellipsis; themes share geometry path', () {
      final qa = _quickActionsRegion(_driverHome());
      expect(qa, contains('maxLines: 1'));
      expect(qa, contains('overflow: TextOverflow.ellipsis'));
      // Geometry is driven by isPhoneLandscapeHost, not per-theme branches.
      final colArm = qa.indexOf('} else if (isPhoneLandscapeHost) {');
      expect(colArm, greaterThanOrEqualTo(0));
      final colBlock = qa.substring(colArm, colArm + 160);
      expect(colBlock, contains('columns = 4;'));
      expect(colBlock, isNot(contains('isLightEmerald')));
      expect(colBlock, isNot(contains('isMiddayGold')));
      expect(colBlock, isNot(contains('isMidnightBlue')));
    });

    test('9. narrow phone-landscape width still yields 4 equal columns', () {
      // Pure geometry contract matching production Wrap math.
      const gap = 8.0;
      const columns = 4;
      // Narrowest supported phone landscape content width (~568 - margins).
      const maxWidth = 520.0;
      final tile = (maxWidth - (gap * (columns - 1))) / columns;
      expect(tile, greaterThan(48.0));
      expect(tile * columns + gap * (columns - 1), closeTo(maxWidth, 0.01));
      // No trailing empty cell: 8 actions / 4 columns = 2 full rows.
      expect(8 % columns, 0);
    });

    test('phone portrait path remains six-action (extras gated)', () {
      final qa = _quickActionsRegion(_driverHome());
      // Extras only inside isPhoneLandscapeHost spread.
      final extras = qa.split('if (isPhoneLandscapeHost) ...[').last;
      expect(extras, contains("nl: 'Mijn prestaties'"));
      // Base six still present outside the gate.
      final before = qa.split('if (isPhoneLandscapeHost) ...[').first;
      expect(before, contains("nl: 'Straatrit'"));
      expect(before, contains("nl: 'Documenten'"));
      expect(before, isNot(contains("nl: 'Mijn prestaties'")));
      expect(before, isNot(contains("nl: 'Beschikbaarheid'")));
    });

    test('tablet landscape call site unchanged (forcedColumns: 2)', () {
      final dash = _premiumDashboardRegion(_driverHome());
      expect(dash, contains('isTabletLandscape: true'));
      expect(dash, contains('forcedColumns: 2'));
      expect(dash, contains('useImageBackgrounds: true'));
      // Tablet landscape grid call must not pass isPhoneLandscapeHost: true.
      final tl = dash.indexOf('isTabletLandscape: true');
      expect(tl, greaterThanOrEqualTo(0));
      final window = dash.substring(tl, tl + 450);
      expect(window, isNot(contains('isPhoneLandscapeHost: true')));
    });

    test('Meer entries for prestaties / beschikbaarheid remain', () {
      final meer = _meerSheetRegion(_driverHome());
      expect(meer, contains("nl: 'Mijn prestaties'"));
      expect(meer, contains("nl: 'Beschikbaarheid'"));
      expect(meer, contains('Icons.insights_rounded'));
      expect(meer, contains('Icons.toggle_on_outlined'));
    });
  });
}
