// CHIRON-RELEASE-PRESENTATION-REPAIR-1 — source-contract tests for release
// hygiene, dead UI, sync presentation, and P0-2A non-regression.
//
// Run:
//   flutter test test/security/chiron_release_presentation_repair_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

String _stripComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlock
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
}

/// True when [onPressedNeedle] appears inside an `if (!kReleaseMode)` branch
/// that also mentions [callbackNeedle] (the destructive callback owner).
bool _callbackIsReleaseGated(
  String src, {
  required String callbackNeedle,
  required String onPressedNeedle,
}) {
  final onPressedIdx = src.indexOf(onPressedNeedle);
  if (onPressedIdx < 0) return false;
  // Walk backwards from the onPressed site to the nearest `if (!kReleaseMode)`.
  final before = src.substring(0, onPressedIdx);
  final gateIdx = before.lastIndexOf('if (!kReleaseMode)');
  if (gateIdx < 0) return false;
  final window = src.substring(gateIdx, onPressedIdx + onPressedNeedle.length);
  if (!window.contains(callbackNeedle)) return false;
  // Ensure no intervening `if (kReleaseMode)` flips the polarity.
  final nestedRelease = window.lastIndexOf('if (kReleaseMode)');
  if (nestedRelease > 0) return false;
  return true;
}

void main() {
  const dashboard = 'lib/chiron_compliance_dashboard_page.dart';

  test('16. local clear buttons are gated behind !kReleaseMode', () {
    final src = _read(dashboard);
    final clearTestIdx = src.indexOf("en: 'Clear local test data'");
    final clearCustIdx = src.indexOf("en: 'Clear local customer bookings'");
    expect(clearTestIdx, greaterThan(0));
    expect(clearCustIdx, greaterThan(clearTestIdx));
    final gateIdx = src.lastIndexOf('if (!kReleaseMode)', clearTestIdx);
    expect(gateIdx, greaterThan(0));
    final end = (clearCustIdx + 600).clamp(0, src.length);
    final gateWindow = src.substring(gateIdx, end);
    expect(gateWindow.contains('_clearLocalTestData'), isTrue);
    expect(gateWindow.contains('_clearLocalCustomerBookings'), isTrue);
  });

  test('17. backend wipe + testflow reset remain !kReleaseMode', () {
    final src = _stripComments(_read(dashboard));
    // Structural contract: the onPressed owners that invoke destructive
    // callbacks must sit inside an `if (!kReleaseMode)` branch. Do not
    // anchor on dialog-title copy (that text lives in ungated dialog
    // classes reachable only after the gated button).
    expect(
      _callbackIsReleaseGated(
        src,
        callbackNeedle: '_resetTestflow',
        onPressedNeedle: 'onPressed: _resettingTestflow ? null : _resetTestflow',
      ),
      isTrue,
      reason: 'Testflow reset button must be wrapped in if (!kReleaseMode)',
    );
    expect(
      _callbackIsReleaseGated(
        src,
        callbackNeedle: '_resetRemoteComplianceEvents',
        onPressedNeedle: ': _resetRemoteComplianceEvents',
      ),
      isTrue,
      reason:
          'Clear backend test events control must be wrapped in if (!kReleaseMode)',
    );
    // Dialog title strings alone must not imply release exposure.
    expect(src.contains("en: 'Reset testflow'"), isTrue);
    expect(src.contains("en: 'Clear backend test events'"), isTrue);
  });

  test('18. ACC connection test retained with company-admin labelling + safe errors', () {
    final src = _read(dashboard);
    expect(src.contains("'/admin/chiron/connection/test'"), isTrue);
    expect(src.contains('_releaseSafeWorkerError'), isTrue);
    final lower = src.toLowerCase();
    expect(
      lower.contains('company administrator') ||
          lower.contains('bedrijfsbeheerder'),
      isTrue,
      reason: 'Connection-test UI must be labelled for company admins.',
    );
  });

  test('19. dead score/readiness widgets remain unmounted', () {
    final src = _read(dashboard);
    final scoreCalls = RegExp(r'_ChironScoreSummaryPanel\s*\(')
        .allMatches(src)
        .where((m) {
      final start = (m.start - 30).clamp(0, src.length);
      final w = src.substring(start, m.end + 5);
      return !w.contains('const _ChironScoreSummaryPanel({') &&
          !w.contains('class _ChironScoreSummaryPanel');
    });
    final readinessCalls = RegExp(r'_ChironReadinessPanel\s*\(')
        .allMatches(src)
        .where((m) {
      final start = (m.start - 30).clamp(0, src.length);
      final w = src.substring(start, m.end + 5);
      return !w.contains('const _ChironReadinessPanel({') &&
          !w.contains('class _ChironReadinessPanel');
    });
    expect(scoreCalls, isEmpty);
    expect(readinessCalls, isEmpty);
  });

  test('20. no Flutter Chiron request emits ADMIN_TOKEN / x-admin-token', () {
    final bodies = [
      _stripComments(_read(dashboard)),
      _stripComments(_read('lib/main_parts/chiron_context_hydration_retry.dart')),
      _stripComments(_read('lib/main_parts/chiron_dossier_grouping.dart')),
      _stripComments(_read('lib/main_parts/chiron_sync_status_presentation.dart')),
    ];
    for (final body in bodies) {
      expect(body.contains('ADMIN_TOKEN'), isFalse);
      expect(body.contains('x-admin-token'), isFalse);
      expect(body.contains('String.fromEnvironment'), isFalse);
    }
  });

  test('synthetic not_configured export wording absent from UI labels', () {
    final src = _read(dashboard);
    expect(src.contains('External Chiron export not configured'), isFalse);
    expect(src.contains('Externe Chiron-export niet ingesteld'), isFalse);
  });

  test('dashboard uses groupChironDossiers + classifyChironSyncState + load coordinator', () {
    final src = _read(dashboard);
    expect(src.contains('groupChironDossiers'), isTrue);
    expect(src.contains('classifyChironSyncState'), isTrue);
    expect(src.contains('ChironContextLoadCoordinator'), isTrue);
  });
}
