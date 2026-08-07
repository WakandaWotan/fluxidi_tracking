// MOLLIE-TERMINAL-UNLINK-AND-EXCLUSION-P1 / MOLLIE-TERMINAL-FORGET-FROM-FLUXIDI-P1
// Localized unlink / relink / forget copy. Fluxidi app language is source of truth.

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
    case 'forget':
      return pick(
        'Verwijderen uit Fluxidi',
        'Remove from Fluxidi',
        'Supprimer de Fluxidi',
        'Eliminar de Fluxidi',
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
    case 'forgotten_snack':
      return pick(
        'Terminal verwijderd uit Fluxidi',
        'Terminal removed from Fluxidi',
        'Terminal supprimé de Fluxidi',
        'Terminal eliminado de Fluxidi',
      );
    case 'forget_confirm_title':
      return pick(
        'Terminal verwijderen uit Fluxidi?',
        'Remove terminal from Fluxidi?',
        'Supprimer le terminal de Fluxidi ?',
        '¿Eliminar el terminal de Fluxidi?',
      );
    case 'forget_confirm_body':
      return pick(
        'Deze terminal wordt alleen uit Fluxidi verwijderd. De terminal blijft bestaan in je Mollie-account.',
        'This terminal will only be removed from Fluxidi. The terminal will remain in your Mollie account.',
        'Ce terminal sera uniquement supprimé de Fluxidi. Le terminal restera dans votre compte Mollie.',
        'Este terminal solo se eliminará de Fluxidi. El terminal seguirá existiendo en tu cuenta de Mollie.',
      );
    case 'forget_confirm_action':
      return pick(
        'Verwijderen uit Fluxidi',
        'Remove from Fluxidi',
        'Supprimer de Fluxidi',
        'Eliminar de Fluxidi',
      );
    case 'forget_cancel':
      return pick('Annuleren', 'Cancel', 'Annuler', 'Cancelar');
    case 'unlink_blocked_pending':
      return pick(
        'Kan niet ontkoppelen zolang een betaling actief is',
        'Cannot unlink while a payment is still active',
        'Impossible de déconnecter tant qu’un paiement est actif',
        'No se puede desvincular mientras un pago esté activo',
      );
    case 'forget_blocked_pending':
      return pick(
        'Kan niet verwijderen zolang een betaling actief is',
        'Cannot remove while a payment is still active',
        'Impossible de supprimer tant qu’un paiement est actif',
        'No se puede eliminar mientras un pago esté activo',
      );
    default:
      return '';
  }
}
