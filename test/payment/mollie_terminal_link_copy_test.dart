import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/payment/card_terminal_payment.dart';
import 'package:fluxidi_tracking/payment/mollie_capability_status.dart';
import 'package:fluxidi_tracking/payment/mollie_terminal_link_copy.dart';

void main() {
  group('MOLLIE-TERMINAL-UNLINK-AND-EXCLUSION-P1 copy', () {
    test('NL/EN/FR/ES presentation for required keys', () {
      const keys = <String>[
        'unlink',
        'relink',
        'unlinked_section',
        'unlinked_snack',
        'relinked_snack',
        'unlink_blocked_pending',
      ];
      for (final key in keys) {
        for (final lang in ['nl', 'en', 'fr', 'es']) {
          final text = mollieTerminalLinkCopy(key: key, lang: lang);
          expect(text, isNotEmpty, reason: '$key/$lang');
        }
      }
      expect(mollieTerminalLinkCopy(key: 'unlink', lang: 'nl'), 'Ontkoppelen');
      expect(
        mollieTerminalLinkCopy(key: 'unlinked_section', lang: 'nl'),
        'Ontkoppelde terminals',
      );
      expect(
        mollieTerminalLinkCopy(key: 'unlink_blocked_pending', lang: 'nl'),
        'Kan niet ontkoppelen zolang een betaling actief is',
      );
    });
  });

  group('Tap to Pay selectable filter', () {
    test('excluded terminal is not selectable and capability ignores it', () {
      final snapshot = <String, dynamic>{
        'status': 'synced',
        'synced_at': DateTime.now().toUtc().toIso8601String(),
        'terminals': [
          {
            'id': 'term_old4',
            'status': 'active',
            'excluded': true,
            'linked': false,
          },
          {
            'id': 'term_new',
            'status': 'active',
            'excluded': false,
            'linked': true,
          },
        ],
      };
      final selectable = selectableMollieTerminalsFromSnapshot(snapshot);
      expect(selectable.map((t) => t['id']), ['term_new']);
      expect(
        resolveTapToPayStatusFromTerminalsSnapshot(snapshot),
        InPersonTerminalStatus.activeTerminal,
      );
      expect(shouldShowTapToPayAction(
        resolveTapToPayStatusFromTerminalsSnapshot(snapshot),
      ), isTrue);
    });

    test('only excluded active terminals -> connectedNoActiveTerminal', () {
      final snapshot = <String, dynamic>{
        'status': 'synced',
        'synced_at': DateTime.now().toUtc().toIso8601String(),
        'terminals': [
          {
            'id': 'term_old3',
            'status': 'active',
            'excluded': true,
            'linked': false,
          },
        ],
      };
      expect(selectableMollieTerminalsFromSnapshot(snapshot), isEmpty);
      expect(
        resolveTapToPayStatusFromTerminalsSnapshot(snapshot),
        InPersonTerminalStatus.connectedNoActiveTerminal,
      );
    });
  });
}
