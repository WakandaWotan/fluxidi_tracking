import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/* CHIRON-P0-2A follow-up C tests: source-contract proofs for the Chiron
 * dashboard sync-state chip hiding and dev/test-only control gating.
 *
 * These are static source-contract checks (grep-shaped assertions) that
 * do not require the widget tree to be built. They prove the runtime
 * behavior contract by reading the shipped source directly.
 */

String _readSource(String relPath) {
  final file = File(relPath);
  if (!file.existsSync()) {
    fail('missing source file: $relPath');
  }
  return file.readAsStringSync();
}

/// Strip Dart // and /* ... */ comments so grep assertions on shipped
/// code do not misfire on documentation text.
String _stripDartComments(String source) {
  final buffer = StringBuffer();
  var i = 0;
  final length = source.length;
  while (i < length) {
    if (i + 1 < length && source[i] == '/' && source[i + 1] == '/') {
      while (i < length && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (i + 1 < length && source[i] == '/' && source[i + 1] == '*') {
      i += 2;
      while (i + 1 < length && !(source[i] == '*' && source[i + 1] == '/')) {
        i++;
      }
      i += 2;
      continue;
    }
    buffer.write(source[i]);
    i++;
  }
  return buffer.toString();
}

void main() {
  group('Chiron dashboard sync-state chip contract', () {
    late String dashboardSource;
    late String strippedSource;

    setUpAll(() {
      dashboardSource = _readSource('lib/chiron_compliance_dashboard_page.dart');
      strippedSource = _stripDartComments(dashboardSource);
    });

    test('_renderableSyncStateChipLabel helper accepts nullable input and '
        'delegates hide/show to classifyChironSyncState', () {
      // Product contract: String? raw — null/empty/unknown hide via classifier.
      expect(
        strippedSource.contains(
          'String? _renderableSyncStateChipLabel(String? raw)',
        ),
        isTrue,
        reason:
            '_renderableSyncStateChipLabel must accept nullable sync state',
      );
      final helperStart = strippedSource.indexOf(
        'String? _renderableSyncStateChipLabel',
      );
      final helperEnd = strippedSource.indexOf(
        '\n  }',
        helperStart,
      );
      final helperBody = strippedSource.substring(helperStart, helperEnd);
      expect(helperBody.contains('classifyChironSyncState(raw)'), isTrue);
      expect(helperBody.contains('if (!presentation.showChip) return null'),
          isTrue);
      // No local switch that could diverge from the shared classifier.
      expect(helperBody.contains("case 'not_configured'"), isFalse);
      expect(helperBody.contains("case 'unknown'"), isFalse);
      expect(helperBody.contains("case 'synced'"), isFalse);
    });

    test(
      'no direct call to _localizedSyncStateLabel remains in a rendered chip; '
      'audit-chip renderers switch to _renderableSyncStateChipLabel',
      () {
        // The dashboard once had `_chip('Synchronisatie: ${_localizedSyncStateLabel(...)}')`
        // pattern rendering the misleading `not_configured` on every event/aggregate.
        // The follow-up contract renders sync chips only via the renderable
        // helper (which returns null for hide-cases).
        expect(
          strippedSource.contains('_localizedSyncStateLabel(e.syncState)}'),
          isFalse,
          reason:
              'audit-chip rendering must not call _localizedSyncStateLabel on '
              'the event syncState anymore',
        );
        expect(
          strippedSource.contains(
            '_localizedSyncStateLabel(latest.syncState)}',
          ),
          isFalse,
          reason:
              'aggregate rendering must not call _localizedSyncStateLabel on '
              'the latest event syncState anymore',
        );
        // The helper for the diagnostic log line (display: ...) may still use
        // _localizedSyncStateLabel; that is not rendered to the user.
      },
    );

    test('audit-chip renderers accept aggregateSyncChipLabel and skip when '
        'the event value matches or is not renderable', () {
      // Signature contract: renderers now take the aggregate label.
      expect(
        strippedSource.contains(
          'List<Widget> _paymentUpdateAuditChips(',
        ),
        isTrue,
      );
      expect(
        strippedSource.contains(
          'List<Widget> _cancellationAuditChips(',
        ),
        isTrue,
      );
      expect(
        strippedSource.contains('String? aggregateSyncChipLabel'),
        isTrue,
        reason:
            'audit-chip functions must accept aggregateSyncChipLabel so the '
            'per-row chip can be de-duplicated against the aggregate',
      );
      // The de-dup check must exist somewhere:
      expect(
        strippedSource.contains('syncLabel != aggregateSyncChipLabel'),
        isTrue,
      );
    });

    test('aggregate sync chip is only rendered when '
        '_aggregateSyncStateChipLabel returns non-null', () {
      expect(
        strippedSource.contains(
          'final aggregateSyncChipLabel = _aggregateSyncStateChipLabel(sorted)',
        ),
        isTrue,
      );
      expect(
        strippedSource.contains(
          'if (aggregateSyncChipLabel != null)',
        ),
        isTrue,
      );
    });
  });

  group('Chiron dashboard destructive/test-only controls', () {
    late String source;
    late String stripped;

    setUpAll(() {
      source = _readSource('lib/chiron_compliance_dashboard_page.dart');
      stripped = _stripDartComments(source);
    });

    test('reset compliance events control remains hidden in release mode', () {
      // Structural: IconButton onPressed owner sits inside if (!kReleaseMode).
      final onPressedNeedle = ': _resetRemoteComplianceEvents';
      final onPressedIdx = stripped.indexOf(onPressedNeedle);
      expect(
        onPressedIdx > 0,
        isTrue,
        reason: 'reset compliance events onPressed owner must remain',
      );
      final before = stripped.substring(0, onPressedIdx);
      final gateIdx = before.lastIndexOf('if (!kReleaseMode)');
      expect(gateIdx, greaterThan(0));
      final window = stripped.substring(gateIdx, onPressedIdx + onPressedNeedle.length);
      expect(
        window.contains('_resetRemoteComplianceEvents'),
        isTrue,
        reason:
            'reset compliance events button must remain gated by !kReleaseMode',
      );
      expect(window.contains('if (kReleaseMode)'), isFalse);
    });

    test('Chiron testflow reset control remains hidden in release mode', () {
      // Structural: OutlinedButton onPressed owner sits inside if (!kReleaseMode).
      // Do not anchor on dialog-title / button-label copy (fragile lookback).
      const onPressedNeedle =
          'onPressed: _resettingTestflow ? null : _resetTestflow';
      final onPressedIdx = stripped.indexOf(onPressedNeedle);
      expect(
        onPressedIdx > 0,
        isTrue,
        reason: 'Testflow reset onPressed owner must remain',
      );
      final before = stripped.substring(0, onPressedIdx);
      final gateIdx = before.lastIndexOf('if (!kReleaseMode)');
      expect(gateIdx, greaterThan(0));
      final window = stripped.substring(gateIdx, onPressedIdx + onPressedNeedle.length);
      expect(
        window.contains('_resetTestflow'),
        isTrue,
        reason:
            'Chiron testflow reset control must remain gated by !kReleaseMode',
      );
      expect(window.contains('if (kReleaseMode)'), isFalse);
    });
  });

  group('Chiron dashboard uses the pure dossier grouper', () {
    late String source;
    late String stripped;

    setUpAll(() {
      source = _readSource('lib/chiron_compliance_dashboard_page.dart');
      stripped = _stripDartComments(source);
    });

    test('groupChironDossiers is the grouping call site', () {
      expect(
        stripped.contains('groupChironDossiers<RemoteComplianceEvent>('),
        isTrue,
      );
    });

    test('the previous _dossierGroupKey per-event helper is no longer '
        'referenced from executable code', () {
      // The helper was removed to prevent the one-key grouping from ever
      // re-entering the rendering path. Only comments may mention it.
      expect(
        stripped.contains('_dossierGroupKey('),
        isFalse,
        reason:
            'The old _dossierGroupKey grouping helper must not be called '
            'from executable code (it was replaced by the pure equivalence '
            'grouper)',
      );
    });
  });
}
