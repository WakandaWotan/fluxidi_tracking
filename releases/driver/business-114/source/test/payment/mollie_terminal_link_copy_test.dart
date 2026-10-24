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
        'forget',
        'unlinked_section',
        'unlinked_snack',
        'relinked_snack',
        'forgotten_snack',
        'forget_confirm_title',
        'forget_confirm_body',
        'forget_confirm_action',
        'forget_cancel',
        'unlink_blocked_pending',
        'forget_blocked_pending',
      ];
      for (final key in keys) {
        for (final lang in ['nl', 'en', 'fr', 'es']) {
          final text = mollieTerminalLinkCopy(key: key, lang: lang);
          expect(text, isNotEmpty, reason: '$key/$lang');
        }
      }
      expect(mollieTerminalLinkCopy(key: 'unlink', lang: 'nl'), 'Ontkoppelen');
      expect(
        mollieTerminalLinkCopy(key: 'forget', lang: 'nl'),
        'Verwijderen uit Fluxidi',
      );
      expect(
        mollieTerminalLinkCopy(key: 'forget_confirm_body', lang: 'nl'),
        'Deze terminal wordt alleen uit Fluxidi verwijderd. De terminal blijft bestaan in je Mollie-account.',
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
      expect(
        shouldShowTapToPayAction(
          resolveTapToPayStatusFromTerminalsSnapshot(snapshot),
        ),
        isTrue,
      );
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

    test('forgotten terminal is not selectable for Tap to Pay', () {
      final snapshot = <String, dynamic>{
        'status': 'synced',
        'synced_at': DateTime.now().toUtc().toIso8601String(),
        'terminals': [
          {
            'id': 'term_old4',
            'status': 'active',
            'excluded': true,
            'forgotten': true,
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
      expect(
        selectableMollieTerminalsFromSnapshot(snapshot).map((t) => t['id']),
        ['term_new'],
      );
      expect(isMollieTerminalForgottenInSnapshot(snapshot['terminals'][0]), isTrue);
    });
  });
}
