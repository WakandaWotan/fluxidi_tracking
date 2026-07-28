/* CHIRON-RELEASE-PRESENTATION-REPAIR-1 C:
 * Truthful sync_state presentation — never treat synthetic/unknown defaults
 * as an established external-export fact.
 */

enum ChironSyncStatusKind {
  /// Real export/sync outcome from an external path (synced/pending/failed).
  authoritative,

  /// Hardcoded/default append placeholder (e.g. not_configured).
  synthetic,

  /// Empty or unrecognized.
  unknown,
}

class ChironSyncStatusPresentation {
  const ChironSyncStatusPresentation({
    required this.kind,
    required this.raw,
    required this.showChip,
    this.neutralLabelKey,
    this.authoritativeLabelKey,
  });

  final ChironSyncStatusKind kind;
  final String raw;

  /// When false, UI must hide the sync chip entirely.
  final bool showChip;

  /// Localization key hint for neutral copy ("status unavailable").
  final String? neutralLabelKey;

  /// Localization key hint for authoritative states.
  final String? authoritativeLabelKey;
}

/// Classify a compliance-event sync_state for UI.
ChironSyncStatusPresentation classifyChironSyncState(String? raw) {
  final token = (raw ?? '').trim().toLowerCase();
  switch (token) {
    case 'synced':
      return const ChironSyncStatusPresentation(
        kind: ChironSyncStatusKind.authoritative,
        raw: 'synced',
        showChip: true,
        authoritativeLabelKey: 'synced',
      );
    case 'pending':
      return const ChironSyncStatusPresentation(
        kind: ChironSyncStatusKind.authoritative,
        raw: 'pending',
        showChip: true,
        authoritativeLabelKey: 'pending',
      );
    case 'failed':
      return const ChironSyncStatusPresentation(
        kind: ChironSyncStatusKind.authoritative,
        raw: 'failed',
        showChip: true,
        authoritativeLabelKey: 'failed',
      );
    case 'not_configured':
      // Synthetic append default — never "external export not configured".
      return const ChironSyncStatusPresentation(
        kind: ChironSyncStatusKind.synthetic,
        raw: 'not_configured',
        showChip: false,
        neutralLabelKey: 'status_unavailable',
      );
    case 'unknown':
    case '':
      return ChironSyncStatusPresentation(
        kind: ChironSyncStatusKind.unknown,
        raw: token,
        showChip: false,
        neutralLabelKey: 'status_unavailable',
      );
    default:
      return ChironSyncStatusPresentation(
        kind: ChironSyncStatusKind.unknown,
        raw: token,
        showChip: false,
        neutralLabelKey: 'status_unavailable',
      );
  }
}
