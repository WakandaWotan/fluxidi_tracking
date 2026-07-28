import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/main_parts/chiron_sync_status_presentation.dart';

void main() {
  group('classifyChironSyncState', () {
    test('14. synthetic not_configured is hidden (not external-export fact)', () {
      final p = classifyChironSyncState('not_configured');
      expect(p.kind, ChironSyncStatusKind.synthetic);
      expect(p.showChip, isFalse);
      expect(p.neutralLabelKey, 'status_unavailable');
    });

    test('unknown / empty are not converted to failed or not_configured', () {
      for (final raw in ['unknown', '', null]) {
        final p = classifyChironSyncState(raw);
        expect(p.kind, ChironSyncStatusKind.unknown);
        expect(p.showChip, isFalse);
        expect(p.authoritativeLabelKey, isNull);
      }
    });

    test('15. authoritative external sync status remains visible', () {
      for (final raw in ['synced', 'pending', 'failed']) {
        final p = classifyChironSyncState(raw);
        expect(p.kind, ChironSyncStatusKind.authoritative);
        expect(p.showChip, isTrue);
        expect(p.authoritativeLabelKey, raw);
      }
    });
  });
}
