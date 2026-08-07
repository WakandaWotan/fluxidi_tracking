// MOLLIE-TERMINAL-UNLINK-AND-EXCLUSION-P1 — localized unlink/relink copy.
// Fluxidi app language remains source of truth (nl/en/fr/es).

String mollieTerminalLinkCopy({
  required String key,
  required String lang,
}) {
  final l = lang.trim().toLowerCase();
  String pick(String nl, String en, String fr, String es) {
    switch (l) {
      case 'nl':
        return nl;
      case 'fr':
        return fr;
      case 'es':
        return es;
      case 'en':
      default:
        return en;
    }
  }

  switch (key) {
    case 'unlink':
      return pick('Ontkoppelen', 'Unlink', 'Déconnecter', 'Desvincular');
    case 'relink':
      return pick(
        'Opnieuw koppelen',
        'Reconnect',
        'Reconnecter',
        'Volver a vincular',
      );
    case 'unlinked_section':
      return pick(
        'Ontkoppelde terminals',
        'Unlinked terminals',
        'Terminaux déconnectés',
        'Terminales desvinculados',
      );
    case 'unlinked_snack':
      return pick(
        'Terminal ontkoppeld',
        'Terminal unlinked',
        'Terminal déconnecté',
        'Terminal desvinculado',
      );
    case 'relinked_snack':
      return pick(
        'Terminal opnieuw gekoppeld',
        'Terminal reconnected',
        'Terminal reconnecté',
        'Terminal vuelto a vincular',
      );
    case 'unlink_blocked_pending':
      return pick(
        'Kan niet ontkoppelen zolang een betaling actief is',
        'Cannot unlink while a payment is still active',
        'Impossible de déconnecter tant qu’un paiement est actif',
        'No se puede desvincular mientras un pago esté activo',
      );
    default:
      return '';
  }
}
