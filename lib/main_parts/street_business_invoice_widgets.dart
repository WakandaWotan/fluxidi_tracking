import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/main_parts/street_business_invoice_support.dart';

/// Presentational theme for [StreetBusinessInvoiceActionView]. Plain color
/// values so the widget can be rendered/tested without the app's private
/// company-bookings theme tokens.
@immutable
class StreetInvoiceActionTheme {
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color danger;
  final Color paidText;
  final Color unpaidText;
  final Color surface;

  /// Slightly-recessed input background (form fields). Falls back to [surface]
  /// when a caller doesn't distinguish the two.
  final Color surfaceAlt;

  /// Hairline/border color used for field outlines and the sheet grabber.
  final Color border;

  const StreetInvoiceActionTheme({
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.danger,
    required this.paidText,
    required this.unpaidText,
    required this.surface,
    Color? surfaceAlt,
    Color? border,
  }) : surfaceAlt = surfaceAlt ?? surface,
       border = border ?? textTertiary;
}

String _tl(
  AppLanguage lang, {
  required String nl,
  required String en,
  required String fr,
  required String es,
}) {
  switch (lang) {
    case AppLanguage.en:
      return en;
    case AppLanguage.fr:
      return fr;
    case AppLanguage.es:
      return es;
    case AppLanguage.nl:
      return nl;
    case AppLanguage.de:
      return en;
  }
}

/// Language-independent short key for a language (nl/en/fr/es), used only for
/// bounded diagnostics logging (1C).
String _langKey(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.nl:
      return 'nl';
    case AppLanguage.en:
      return 'en';
    case AppLanguage.fr:
      return 'fr';
    case AppLanguage.es:
      return 'es';
    case AppLanguage.de:
      return 'de';
  }
}

/// Normalizes an arbitrary locale string (e.g. `nl-BE`, `nl_BE`, `NL`, `fr-FR`)
/// to an [AppLanguage] (STREET-BUSINESS-INVOICE-PDF-PAYMENT-SYNC-1C).
///
/// This only affects WHICH translation is shown — it can NEVER change the
/// semantic [StreetInvoiceInvoicePaymentStatus]. An unknown/empty locale falls
/// back to English (the app default), consistent with [appLanguageNotifier].
AppLanguage streetInvoiceLanguageFromLocale(String? locale) {
  final primary = (locale ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('_', '-')
      .split('-')
      .first;
  switch (primary) {
    case 'nl':
      return AppLanguage.nl;
    case 'fr':
      return AppLanguage.fr;
    case 'es':
      return AppLanguage.es;
    case 'en':
      return AppLanguage.en;
    default:
      return AppLanguage.en;
  }
}

/// Bounded de-dup guard so the presentation log only fires when the
/// (surface, lang, semanticStatus, label) tuple actually changes.
final Set<String> _streetInvoicePresentationLogSeen = <String>{};

/// Emits the single-line bounded runtime proof requested by 1C. Carries no PII
/// or tokens — only ride/Billit booleans, the sync token, the semantic status
/// key, and the (already public) rendered label. Both the main card and the
/// detail modal call this with the SAME [StreetInvoicePaymentDiagnostics], so
/// the log proves NL/EN/FR/ES resolve to an identical `semanticStatus`.
void logStreetInvoicePaymentPresentation({
  required String surface,
  required AppLanguage lang,
  required StreetInvoicePaymentDiagnostics diagnostics,
  required String renderedLabel,
}) {
  final statusKey = diagnostics.semanticStatusKey;
  final dedupeKey = '$surface|${_langKey(lang)}|$statusKey|$renderedLabel';
  if (!_streetInvoicePresentationLogSeen.add(dedupeKey)) return;
  if (_streetInvoicePresentationLogSeen.length > 64) {
    _streetInvoicePresentationLogSeen.clear();
    _streetInvoicePresentationLogSeen.add(dedupeKey);
  }
  final sync = diagnostics.billitPaymentSyncStatus.isEmpty
      ? '(empty)'
      : diagnostics.billitPaymentSyncStatus;
  debugPrint(
    '[STREET_INVOICE_PAYMENT_PRESENTATION] '
    'surface=$surface '
    'lang=${_langKey(lang)} '
    'ridePaid=${diagnostics.ridePaid} '
    'billitPaid=${diagnostics.billitPaid} '
    'syncStatus=$sync '
    'billitUpdating=${diagnostics.billitUpdating} '
    'semanticStatus=$statusKey '
    'labelKey=$statusKey '
    'renderedLabel=$renderedLabel',
  );
}

String _streetInvoiceProcessingLabel(
  AppLanguage lang,
  StreetInvoiceProcessingStatus status,
) {
  switch (status) {
    case StreetInvoiceProcessingStatus.requested:
      return _tl(
        lang,
        nl: 'Factuur aangevraagd',
        en: 'Invoice requested',
        fr: 'Facture demandée',
        es: 'Factura solicitada',
      );
    case StreetInvoiceProcessingStatus.created:
      return _tl(
        lang,
        nl: 'Factuur aangemaakt',
        en: 'Invoice created',
        fr: 'Facture créée',
        es: 'Factura creada',
      );
    case StreetInvoiceProcessingStatus.billitUpdating:
      return _tl(
        lang,
        nl: 'Billit wordt bijgewerkt',
        en: 'Billit is being updated',
        fr: 'Billit est en cours de mise à jour',
        es: 'Billit se está actualizando',
      );
    case StreetInvoiceProcessingStatus.sent:
      return _tl(
        lang,
        nl: 'Factuur verzonden',
        en: 'Invoice sent',
        fr: 'Facture envoyée',
        es: 'Factura enviada',
      );
    case StreetInvoiceProcessingStatus.peppolSent:
      return _tl(
        lang,
        nl: 'Factuur verzonden (Peppol)',
        en: 'Peppol sent',
        fr: 'Envoyée via Peppol',
        es: 'Enviada por Peppol',
      );
    case StreetInvoiceProcessingStatus.pdfReady:
      return _tl(
        lang,
        nl: 'Factuur-PDF beschikbaar',
        en: 'Invoice PDF available',
        fr: 'PDF de facture disponible',
        es: 'PDF de factura disponible',
      );
  }
}

String _streetInvoicePdfStatusLabel(
  AppLanguage lang,
  StreetInvoicePdfAvailabilityState state,
) {
  switch (state) {
    case StreetInvoicePdfAvailabilityState.available:
      return _tl(
        lang,
        nl: 'Factuur-PDF beschikbaar',
        en: 'Invoice PDF available',
        fr: 'PDF de facture disponible',
        es: 'PDF de factura disponible',
      );
    case StreetInvoicePdfAvailabilityState.retryableError:
      return _tl(
        lang,
        nl: 'Factuurstatus kon niet worden vernieuwd',
        en: 'Invoice status could not be refreshed',
        fr: 'Le statut de la facture n’a pas pu être actualisé',
        es: 'No se pudo actualizar el estado de la factura',
      );
    case StreetInvoicePdfAvailabilityState.unavailable:
      return _tl(
        lang,
        nl: 'Factuur-PDF nog niet beschikbaar',
        en: 'Invoice PDF not yet available',
        fr: 'PDF de facture pas encore disponible',
        es: 'PDF de factura aún no disponible',
      );
    case StreetInvoicePdfAvailabilityState.preparing:
      return _tl(
        lang,
        nl: 'Factuur-PDF wordt voorbereid',
        en: 'Invoice PDF is being prepared',
        fr: 'Le PDF de la facture est en préparation',
        es: 'El PDF de la factura se está preparando',
      );
  }
}

/// STREET-BUSINESS-INVOICE-PDF-PAYMENT-SYNC-1B — single label mapper for the
/// semantic invoice payment status. Used by the main card AND the detail modal
/// so NL/EN/FR/ES never diverge by re-branching on booleans.
String streetInvoicePaymentStatusLabel(
  AppLanguage lang,
  StreetInvoiceInvoicePaymentStatus status,
) {
  switch (status) {
    case StreetInvoiceInvoicePaymentStatus.paid:
      return _tl(
        lang,
        nl: 'Factuur betaald',
        en: 'Invoice paid',
        fr: 'Facture payée',
        es: 'Factura pagada',
      );
    case StreetInvoiceInvoicePaymentStatus.syncInProgress:
      return _tl(
        lang,
        nl: 'Betalingssynchronisatie bezig',
        en: 'Payment synchronization in progress',
        fr: 'Synchronisation du paiement en cours',
        es: 'Sincronización del pago en curso',
      );
    case StreetInvoiceInvoicePaymentStatus.syncFailed:
      return _tl(
        lang,
        nl: 'Betalingssynchronisatie mislukt — opnieuw proberen',
        en: 'Payment synchronization failed — retry',
        fr: 'Échec de la synchronisation du paiement — réessayer',
        es: 'Falló la sincronización del pago — reintentar',
      );
    case StreetInvoiceInvoicePaymentStatus.notLinkedToBillit:
      return _tl(
        lang,
        nl: 'Koppel handmatig in Billit (auto-aanmaak staat uit)',
        en: 'Link manually in Billit (auto-create is off)',
        fr: 'Lier manuellement dans Billit (création auto désactivée)',
        es: 'Vincular manualmente en Billit (creación automática desactivada)',
      );
    case StreetInvoiceInvoicePaymentStatus.outstanding:
      return _tl(
        lang,
        nl: 'Factuur openstaand',
        en: 'Invoice outstanding',
        fr: 'Facture en attente',
        es: 'Factura pendiente',
      );
  }
}

Color streetInvoicePaymentStatusColor(
  StreetInvoiceActionTheme theme,
  StreetInvoiceInvoicePaymentStatus status,
) {
  switch (status) {
    case StreetInvoiceInvoicePaymentStatus.paid:
      return theme.paidText;
    case StreetInvoiceInvoicePaymentStatus.syncInProgress:
    case StreetInvoiceInvoicePaymentStatus.syncFailed:
    case StreetInvoiceInvoicePaymentStatus.notLinkedToBillit:
      return theme.textSecondary;
    case StreetInvoiceInvoicePaymentStatus.outstanding:
      return theme.unpaidText;
  }
}

/// Public, side-effect-light presentational widget for the company street-ride
/// business-invoice action. It renders purely from a
/// [StreetBusinessInvoiceController] and delegates all navigation/networking to
/// [onRequest] / [onView] callbacks, which makes it fully widget-testable.
class StreetBusinessInvoiceActionView extends StatefulWidget {
  const StreetBusinessInvoiceActionView({
    super.key,
    required this.controller,
    required this.theme,
    required this.language,
    required this.onRequest,
    required this.onView,
    this.showBillitAndPeppol = true,
    this.receiptPaymentStyle = false,
    this.onViewPdf,
    this.onSharePdf,
  });

  final StreetBusinessInvoiceController controller;
  final StreetInvoiceActionTheme theme;
  final AppLanguage language;
  final VoidCallback onRequest;
  final VoidCallback onView;

  /// When false, the inline issued block shows only the invoice reference and
  /// paid/outstanding status (compact company card). The detailed Billit/Peppol
  /// lines are then owned by the expanded Documents card below the action.
  /// The driver receipt (no Documents card) keeps this true.
  final bool showBillitAndPeppol;

  /// When true, the request action matches the driver-receipt Payment card
  /// buttons (full-width filled, short "Business invoice" label) instead of
  /// the compact company accent chip.
  final bool receiptPaymentStyle;

  /// Optional invoice-PDF actions (distinct from the ride receipt PDF).
  final VoidCallback? onViewPdf;
  final VoidCallback? onSharePdf;

  @override
  State<StreetBusinessInvoiceActionView> createState() =>
      _StreetBusinessInvoiceActionViewState();
}

class _StreetBusinessInvoiceActionViewState
    extends State<StreetBusinessInvoiceActionView> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant StreetBusinessInvoiceActionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  AppLanguage get _lang => widget.language;

  @override
  Widget build(BuildContext context) {
    switch (widget.controller.state) {
      case StreetBusinessInvoiceUiState.unavailable:
        return const SizedBox.shrink();
      case StreetBusinessInvoiceUiState.eligibleNoInvoice:
        return _buildRequestButton(busy: false);
      case StreetBusinessInvoiceUiState.submitting:
        return _buildRequestButton(busy: true);
      case StreetBusinessInvoiceUiState.issuedFromResponse:
      case StreetBusinessInvoiceUiState.issuedIndexed:
      case StreetBusinessInvoiceUiState.visibilityDelayed:
        return _buildIssuedBlock();
      case StreetBusinessInvoiceUiState.error:
        return _buildErrorBlock();
    }
  }

  Widget _buildRequestButton({required bool busy}) {
    final theme = widget.theme;
    final receiptStyle = widget.receiptPaymentStyle;
    final label = busy
        ? _tl(
            _lang,
            nl: 'Factuur wordt aangemaakt…',
            en: 'Creating invoice…',
            fr: 'Création de la facture…',
            es: 'Creando factura…',
          )
        : receiptStyle
        ? _tl(
            _lang,
            nl: 'Zakelijke factuur',
            en: 'Business invoice',
            fr: 'Facture professionnelle',
            es: 'Factura comercial',
          )
        : _tl(
            _lang,
            nl: 'Zakelijke factuur aanvragen',
            en: 'Request business invoice',
            fr: 'Demander une facture professionnelle',
            es: 'Solicitar factura comercial',
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            receiptStyle ||
            streetInvoiceActionIsNarrowLayout(constraints.maxWidth);
        final button = FilledButton.icon(
          onPressed: busy ? null : widget.onRequest,
          style: receiptStyle
              ? null
              : FilledButton.styleFrom(
                  backgroundColor: theme.accent.withOpacity(0.14),
                  foregroundColor: theme.accent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  minimumSize: Size(narrow ? double.infinity : 0, 38),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: theme.accent.withOpacity(0.42)),
                  ),
                ),
          icon: busy
              ? SizedBox(
                  width: receiptStyle ? 18 : 14,
                  height: receiptStyle ? 18 : 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      receiptStyle
                          ? Theme.of(context).colorScheme.onPrimary
                          : theme.accent,
                    ),
                  ),
                )
              : Icon(
                  Icons.request_page_outlined,
                  size: receiptStyle ? 22 : 16,
                  color: receiptStyle ? null : theme.accent,
                ),
          label: Text(
            label,
            style: TextStyle(
              fontSize: receiptStyle ? 14 : 12.1,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
        return narrow
            ? SizedBox(width: double.infinity, child: button)
            : Align(alignment: Alignment.centerLeft, child: button);
      },
    );
  }

  Widget _buildIssuedBlock() {
    final theme = widget.theme;
    final controller = widget.controller;
    final ref = controller.displayInvoiceReference;
    // One semantic status for card + modal; translate only after resolve.
    final paymentStatus = controller.displayInvoicePaymentStatus;
    final paymentText = streetInvoicePaymentStatusLabel(_lang, paymentStatus);
    final paymentColor = streetInvoicePaymentStatusColor(theme, paymentStatus);
    logStreetInvoicePaymentPresentation(
      surface: 'card',
      lang: _lang,
      diagnostics: controller.paymentDiagnostics,
      renderedLabel: paymentText,
    );
    final peppolSent = controller.displayPeppolSent;
    final hasBillit = controller.hasBillitLink;
    final pdf = controller.pdfAvailability;
    final delayed =
        controller.state == StreetBusinessInvoiceUiState.visibilityDelayed;
    final lifecycle = (controller.indexedInvoice?.lifecycleState ?? '')
        .trim()
        .toLowerCase();
    final receiptStyle = widget.receiptPaymentStyle;

    final invoiceLifecycleText = peppolSent
        ? _tl(
            _lang,
            nl: 'Factuur verzonden (Peppol)',
            en: 'Peppol sent',
            fr: 'Envoyée via Peppol',
            es: 'Enviada por Peppol',
          )
        : delayed
        ? _tl(
            _lang,
            nl: 'Factuur aangevraagd',
            en: 'Invoice requested',
            fr: 'Facture demandée',
            es: 'Factura solicitada',
          )
        : lifecycle == 'sent' || lifecycle == 'ready_to_send'
        ? _tl(
            _lang,
            nl: 'Factuur verzonden',
            en: 'Invoice sent',
            fr: 'Facture envoyée',
            es: 'Factura enviada',
          )
        : _tl(
            _lang,
            nl: 'Factuur aangemaakt',
            en: 'Invoice created',
            fr: 'Facture créée',
            es: 'Factura creada',
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _tl(
            _lang,
            nl: 'Zakelijke factuur',
            en: 'Business invoice',
            fr: 'Facture professionnelle',
            es: 'Factura comercial',
          ),
          style: TextStyle(
            color: theme.textPrimary,
            fontSize: receiptStyle ? 13.2 : 12.1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow =
                receiptStyle ||
                streetInvoiceActionIsNarrowLayout(constraints.maxWidth);
            final viewButton = OutlinedButton.icon(
              onPressed: widget.onView,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.accent.withOpacity(0.96),
                side: BorderSide(color: theme.accent.withOpacity(0.42)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                minimumSize: Size(narrow ? double.infinity : 0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(
                Icons.description_outlined,
                size: 16,
                color: theme.accent.withOpacity(0.96),
              ),
              label: Text(
                _tl(
                  _lang,
                  nl: 'Factuur bekijken',
                  en: 'View invoice',
                  fr: 'Voir la facture',
                  es: 'Ver factura',
                ),
                style: const TextStyle(
                  fontSize: 11.6,
                  fontWeight: FontWeight.w800,
                ),
              ),
            );
            return narrow
                ? SizedBox(width: double.infinity, child: viewButton)
                : Align(alignment: Alignment.centerLeft, child: viewButton);
          },
        ),
        // PDF actions: only active when a real PDF artifact is confirmed.
        // Preparing / retryable never show a dead active View/Share button.
        if (widget.onViewPdf != null || widget.onSharePdf != null) ...[
          const SizedBox(height: 6),
          if (pdf.canViewOrShare) ...[
            if (widget.onViewPdf != null)
              OutlinedButton.icon(
                onPressed: widget.onViewPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text(
                  _tl(
                    _lang,
                    nl: 'Factuur-PDF bekijken',
                    en: 'View invoice PDF',
                    fr: 'Voir le PDF de la facture',
                    es: 'Ver PDF de factura',
                  ),
                ),
              ),
            if (widget.onSharePdf != null) ...[
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: widget.onSharePdf,
                icon: const Icon(Icons.share_outlined, size: 18),
                label: Text(
                  _tl(
                    _lang,
                    nl: 'Factuur delen',
                    en: 'Share invoice',
                    fr: 'Partager la facture',
                    es: 'Compartir factura',
                  ),
                ),
              ),
            ],
          ] else ...[
            Text(
              pdf.isRetryable
                  ? _tl(
                      _lang,
                      nl: 'Factuurstatus kon niet worden vernieuwd',
                      en: 'Invoice status could not be refreshed',
                      fr: 'Le statut de la facture n’a pas pu être actualisé',
                      es: 'No se pudo actualizar el estado de la factura',
                    )
                  : _tl(
                      _lang,
                      nl: 'Factuur-PDF wordt voorbereid',
                      en: 'Invoice PDF is being prepared',
                      fr: 'Le PDF de la facture est en préparation',
                      es: 'El PDF de la factura se está preparando',
                    ),
              style: TextStyle(
                color: theme.textSecondary,
                fontSize: 11.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () => unawaited(controller.refreshStatus()),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(
                _tl(
                  _lang,
                  nl: 'Opnieuw controleren',
                  en: 'Check again',
                  fr: 'Vérifier à nouveau',
                  es: 'Comprobar de nuevo',
                ),
              ),
            ),
          ],
        ],
        const SizedBox(height: 6),
        if (ref.isNotEmpty)
          Text(
            ref,
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 12.1,
              fontWeight: FontWeight.w800,
            ),
          ),
        const SizedBox(height: 2),
        Text(
          invoiceLifecycleText,
          style: TextStyle(
            color: theme.textSecondary,
            fontSize: 11.4,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          paymentText,
          style: TextStyle(
            color: paymentColor,
            fontSize: 11.4,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (widget.showBillitAndPeppol) ...[
          const SizedBox(height: 2),
          Text(
            hasBillit
                ? _tl(
                    _lang,
                    nl: 'Aangemaakt in Billit',
                    en: 'Created in Billit',
                    fr: 'Créée dans Billit',
                    es: 'Creada en Billit',
                  )
                : _tl(
                    _lang,
                    nl: 'Billit wordt bijgewerkt',
                    en: 'Billit is being updated',
                    fr: 'Billit est en cours de mise à jour',
                    es: 'Billit se está actualizando',
                  ),
            style: TextStyle(color: theme.textSecondary, fontSize: 10.8),
          ),
          if (!peppolSent)
            Text(
              _tl(
                _lang,
                nl: 'Niet verstuurd via Peppol',
                en: 'Not sent via Peppol',
                fr: 'Non envoyée via Peppol',
                es: 'No enviada por Peppol',
              ),
              style: TextStyle(color: theme.textSecondary, fontSize: 10.8),
            ),
        ],
        if (delayed) ...[
          const SizedBox(height: 4),
          Text(
            _tl(
              _lang,
              nl: 'Factuur aangemaakt. Documenten worden nog bijgewerkt.',
              en: 'Invoice created. Documents are still updating.',
              fr:
                  'Facture créée. Les documents sont encore en cours de mise à '
                  'jour.',
              es: 'Factura creada. Los documentos aún se están actualizando.',
            ),
            style: TextStyle(
              color: theme.textTertiary,
              fontSize: 10.6,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildErrorBlock() {
    final theme = widget.theme;
    final kind =
        widget.controller.errorKind ?? StreetBusinessInvoiceErrorKind.unknown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          streetBusinessInvoiceErrorText(kind, _lang),
          style: TextStyle(
            color: theme.danger,
            fontSize: 11.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: widget.onRequest,
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.accent,
              side: BorderSide(color: theme.accent.withOpacity(0.42)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: Icon(Icons.refresh, size: 16, color: theme.accent),
            label: Text(
              _tl(
                _lang,
                nl: 'Opnieuw proberen',
                en: 'Retry',
                fr: 'Réessayer',
                es: 'Reintentar',
              ),
              style: const TextStyle(
                fontSize: 11.4,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Localized, non-technical message for a request error kind. Shared by the
/// action view and the request form so tests and UI agree.
String streetBusinessInvoiceErrorText(
  StreetBusinessInvoiceErrorKind kind,
  AppLanguage lang,
) {
  switch (kind) {
    case StreetBusinessInvoiceErrorKind.identityConflict:
      return _tl(
        lang,
        nl:
            'Voor deze rit bestaat al een factuuraanvraag met andere '
            'bedrijfsgegevens.',
        en:
            'A business invoice with different company details already exists '
            'for this ride.',
        fr:
            'Une demande de facture avec d\'autres données d\'entreprise existe '
            'déjà pour cette course.',
        es:
            'Ya existe una solicitud de factura con otros datos de empresa para '
            'este trayecto.',
      );
    case StreetBusinessInvoiceErrorKind.accessDenied:
      return _tl(
        lang,
        nl: 'Geen toegang.',
        en: 'Access denied.',
        fr: 'Accès refusé.',
        es: 'Acceso denegado.',
      );
    case StreetBusinessInvoiceErrorKind.driverNotAuthorized:
      return _tl(
        lang,
        nl: 'Je bent niet gemachtigd voor deze rit.',
        en: 'The driver is not authorized for this ride.',
        fr: 'Le chauffeur n\'est pas autorisé pour cette course.',
        es: 'El conductor no está autorizado para este trayecto.',
      );
    case StreetBusinessInvoiceErrorKind.notCompletedStreet:
      return _tl(
        lang,
        nl: 'Deze actie is alleen beschikbaar voor voltooide straatritten.',
        en: 'This action is only available for completed street rides.',
        fr:
            'Cette action n\'est disponible que pour les courses de rue '
            'terminées.',
        es:
            'Esta acción solo está disponible para trayectos de calle '
            'completados.',
      );
    case StreetBusinessInvoiceErrorKind.readiness:
      return _tl(
        lang,
        nl: 'Vul de bedrijfsnaam en het volledige facturatieadres in.',
        en: 'Enter the company name and the complete billing address.',
        fr:
            'Saisissez le nom de l\'entreprise et l\'adresse de facturation '
            'complète.',
        es:
            'Introduce el nombre de la empresa y la dirección de facturación '
            'completa.',
      );
    case StreetBusinessInvoiceErrorKind.network:
      return _tl(
        lang,
        nl:
            'De factuuraanvraag kon niet worden gecontroleerd. Controleer je '
            'verbinding en probeer opnieuw.',
        en:
            'The invoice request could not be verified. Check your connection '
            'and try again.',
        fr:
            'La demande de facture n\'a pas pu être vérifiée. Vérifiez votre '
            'connexion et réessayez.',
        es:
            'No se pudo verificar la solicitud de factura. Comprueba tu '
            'conexión e inténtalo de nuevo.',
      );
    case StreetBusinessInvoiceErrorKind.alreadyExists:
    case StreetBusinessInvoiceErrorKind.unknown:
      return _tl(
        lang,
        nl: 'Factuur kon niet worden aangemaakt. Probeer opnieuw.',
        en: 'The invoice could not be created. Please try again.',
        fr: 'La facture n\'a pas pu être créée. Réessayez.',
        es: 'No se pudo crear la factura. Inténtalo de nuevo.',
      );
  }
}

/// Shared, keyboard/SafeArea-correct request form used by BOTH the company
/// booking card and the driver receipt. Themed via [StreetInvoiceActionTheme]
/// and localized via [AppLanguage] so there is a SINGLE form implementation.
///
/// Opens as a scroll-controlled bottom sheet and completes with the entered
/// buyer identity, or null when cancelled/invalid.
Future<StreetBusinessInvoiceBuyerInput?> showStreetBusinessInvoiceForm({
  required BuildContext context,
  required StreetInvoiceActionTheme theme,
  required AppLanguage language,
  required bool isPaidBooking,
  required StreetBusinessInvoiceBuyerInput initial,
  bool convertFromConsumerSale = false,
}) {
  return showModalBottomSheet<StreetBusinessInvoiceBuyerInput>(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => StreetBusinessInvoiceForm(
      theme: theme,
      language: language,
      isPaidBooking: isPaidBooking,
      initial: initial,
      convertFromConsumerSale: convertFromConsumerSale,
    ),
  );
}

/// Public request form (also usable directly in widget tests).
class StreetBusinessInvoiceForm extends StatefulWidget {
  const StreetBusinessInvoiceForm({
    super.key,
    required this.theme,
    required this.language,
    required this.isPaidBooking,
    required this.initial,
    this.convertFromConsumerSale = false,
  });

  final StreetInvoiceActionTheme theme;
  final AppLanguage language;
  final bool isPaidBooking;
  final StreetBusinessInvoiceBuyerInput initial;

  /// CONSUMER-SALE-LATE-BUSINESS-INVOICE-ACTION-P0-3: credit-first conversion.
  final bool convertFromConsumerSale;

  @override
  State<StreetBusinessInvoiceForm> createState() =>
      _StreetBusinessInvoiceFormState();
}

class _StreetBusinessInvoiceFormState extends State<StreetBusinessInvoiceForm> {
  late final TextEditingController _legalName;
  late final TextEditingController _street;
  late final TextEditingController _postalCode;
  late final TextEditingController _city;
  late final TextEditingController _country;
  late final TextEditingController _vat;
  late final TextEditingController _reg;
  late final TextEditingController _email;
  late final TextEditingController _reference;
  bool _showErrors = false;

  AppLanguage get _lang => widget.language;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _legalName = TextEditingController(text: i.legalName);
    _street = TextEditingController(text: i.street);
    _postalCode = TextEditingController(text: i.postalCode);
    _city = TextEditingController(text: i.city);
    _country = TextEditingController(
      text: i.country.trim().isEmpty ? 'BE' : i.country.trim().toUpperCase(),
    );
    _vat = TextEditingController(text: i.vatNumber);
    _reg = TextEditingController(text: i.companyRegistrationNumber);
    _email = TextEditingController(text: i.contactEmail);
    _reference = TextEditingController(text: i.buyerReference);
  }

  @override
  void dispose() {
    _legalName.dispose();
    _street.dispose();
    _postalCode.dispose();
    _city.dispose();
    _country.dispose();
    _vat.dispose();
    _reg.dispose();
    _email.dispose();
    _reference.dispose();
    super.dispose();
  }

  StreetBusinessInvoiceBuyerInput _current() => StreetBusinessInvoiceBuyerInput(
    legalName: _legalName.text,
    street: _street.text,
    postalCode: _postalCode.text,
    city: _city.text,
    country: _country.text,
    vatNumber: _vat.text,
    companyRegistrationNumber: _reg.text,
    contactEmail: _email.text,
    buyerReference: _reference.text,
  );

  void _submit() {
    final input = _current();
    final validation = validateStreetBusinessInvoiceForm(input);
    if (!validation.isValid) {
      setState(() => _showErrors = true);
      return;
    }
    Navigator.of(context).pop(input);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final media = MediaQuery.of(context);
    final viewInsets = media.viewInsets.bottom;
    final validation = _showErrors
        ? validateStreetBusinessInvoiceForm(_current())
        : null;

    InputDecoration decoration(String label, {bool required = false}) {
      return InputDecoration(
        labelText: required ? '$label *' : label,
        labelStyle: TextStyle(color: theme.textSecondary, fontSize: 12.6),
        filled: true,
        fillColor: theme.surfaceAlt.withOpacity(0.6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.border.withOpacity(0.6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.border.withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.accent.withOpacity(0.7)),
        ),
      );
    }

    Widget field(
      TextEditingController controller,
      String label, {
      bool required = false,
      bool missing = false,
      bool invalid = false,
      TextInputType? keyboardType,
    }) {
      String? errorText;
      if (missing) {
        errorText = _tl(
          _lang,
          nl: 'Verplicht veld',
          en: 'Required field',
          fr: 'Champ obligatoire',
          es: 'Campo obligatorio',
        );
      } else if (invalid) {
        errorText = _tl(
          _lang,
          nl: 'Ongeldig btw-/ondernemingsnummer',
          en: 'Invalid VAT / company number',
          fr: 'Numéro de TVA / d\'entreprise invalide',
          es: 'Número de IVA / empresa no válido',
        );
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              keyboardType: keyboardType,
              style: TextStyle(color: theme.textPrimary, fontSize: 13.6),
              decoration: decoration(label, required: required),
            ),
            if (errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 4),
                child: Text(
                  errorText,
                  style: TextStyle(color: theme.danger, fontSize: 10.8),
                ),
              ),
          ],
        ),
      );
    }

    // Bounded sheet height so tablet portrait/landscape never fills the screen,
    // and the fixed action bar below is always reachable above the system
    // navigation/gesture area and the keyboard.
    final maxSheetHeight = media.size.height * 0.9;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.border.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _tl(
                          _lang,
                          nl: 'Zakelijke factuur aanvragen',
                          en: 'Request business invoice',
                          fr: 'Demander une facture professionnelle',
                          es: 'Solicitar factura comercial',
                        ),
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.convertFromConsumerSale
                            ? _tl(
                                _lang,
                                nl:
                                    'De particuliere verkoop wordt eerst '
                                    'gecrediteerd. Daarna wordt een nieuwe '
                                    'zakelijke factuur aangemaakt. Bedrag en '
                                    'btw blijven gelijk. Peppol geldt alleen '
                                    'voor de nieuwe zakelijke factuur.',
                                en:
                                    'The private sale is credited first. Then '
                                    'a new business invoice is created. Amount '
                                    'and VAT stay the same. Peppol applies only '
                                    'to the new business invoice.',
                                fr:
                                    'La vente particulière est d’abord '
                                    'créditée. Ensuite une nouvelle facture '
                                    'professionnelle est créée. Montant et TVA '
                                    'restent identiques. Peppol s’applique '
                                    'uniquement à la nouvelle facture.',
                                es:
                                    'Primero se acredita la venta particular. '
                                    'Después se crea una nueva factura '
                                    'comercial. Importe e IVA se mantienen. '
                                    'Peppol solo aplica a la nueva factura.',
                              )
                            : _tl(
                                _lang,
                                nl:
                                    'De factuur wordt aangemaakt voor deze '
                                    'bestaande straatrit. De ritprijs en '
                                    'betaalstatus worden niet gewijzigd.',
                                en:
                                    'The invoice is created for this existing '
                                    'street ride. The ride price and payment '
                                    'status are not changed.',
                                fr:
                                    'La facture est créée pour cette course de '
                                    'rue existante. Le prix de la course et le '
                                    'statut de paiement ne sont pas modifiés.',
                                es:
                                    'La factura se crea para este trayecto de '
                                    'calle existente. El precio del trayecto y '
                                    'el estado de pago no se modifican.',
                              ),
                        style: TextStyle(
                          color: theme.textSecondary,
                          fontSize: 12.2,
                        ),
                      ),
                      if (!widget.isPaidBooking) ...[
                        const SizedBox(height: 6),
                        Text(
                          _tl(
                            _lang,
                            nl:
                                'Deze factuur blijft openstaand tot de betaling '
                                'is geregistreerd.',
                            en:
                                'This invoice remains outstanding until payment '
                                'is registered.',
                            fr:
                                'Cette facture reste en attente jusqu\'à '
                                'l\'enregistrement du paiement.',
                            es:
                                'Esta factura permanece pendiente hasta que se '
                                'registre el pago.',
                          ),
                          style: TextStyle(
                            color: theme.unpaidText,
                            fontSize: 11.8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      field(
                        _legalName,
                        _tl(
                          _lang,
                          nl: 'Bedrijfsnaam',
                          en: 'Company name',
                          fr: 'Nom de l\'entreprise',
                          es: 'Nombre de la empresa',
                        ),
                        required: true,
                        missing: validation?.legalNameMissing ?? false,
                      ),
                      field(
                        _street,
                        _tl(
                          _lang,
                          nl: 'Straat en nummer',
                          en: 'Street and number',
                          fr: 'Rue et numéro',
                          es: 'Calle y número',
                        ),
                        required: true,
                        missing: validation?.streetMissing ?? false,
                      ),
                      field(
                        _postalCode,
                        _tl(
                          _lang,
                          nl: 'Postcode',
                          en: 'Postal code',
                          fr: 'Code postal',
                          es: 'Código postal',
                        ),
                        required: true,
                        missing: validation?.postalCodeMissing ?? false,
                      ),
                      field(
                        _city,
                        _tl(
                          _lang,
                          nl: 'Plaats',
                          en: 'City',
                          fr: 'Ville',
                          es: 'Ciudad',
                        ),
                        required: true,
                        missing: validation?.cityMissing ?? false,
                      ),
                      field(
                        _country,
                        _tl(
                          _lang,
                          nl: 'Land',
                          en: 'Country',
                          fr: 'Pays',
                          es: 'País',
                        ),
                        required: true,
                        missing: validation?.countryMissing ?? false,
                      ),
                      field(
                        _vat,
                        _tl(
                          _lang,
                          nl: 'Btw-/ondernemingsnummer',
                          en: 'VAT / company number',
                          fr: 'Numéro de TVA / d\'entreprise',
                          es: 'Número de IVA / empresa',
                        ),
                        invalid: validation?.vatInvalid ?? false,
                      ),
                      field(
                        _reg,
                        _tl(
                          _lang,
                          nl: 'Ondernemingsnummer',
                          en: 'Company registration number',
                          fr: 'Numéro d\'entreprise',
                          es: 'Número de registro de empresa',
                        ),
                        invalid:
                            validation?.companyRegistrationInvalid ?? false,
                      ),
                      field(
                        _email,
                        _tl(
                          _lang,
                          nl: 'E-mailadres',
                          en: 'Email address',
                          fr: 'Adresse e-mail',
                          es: 'Correo electrónico',
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      field(
                        _reference,
                        _tl(
                          _lang,
                          nl: 'Referentie van de klant',
                          en: 'Customer reference',
                          fr: 'Référence du client',
                          es: 'Referencia del cliente',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Fixed, always-reachable action bar (inside SafeArea).
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.textSecondary,
                          side: BorderSide(
                            color: theme.border.withOpacity(0.6),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          _tl(
                            _lang,
                            nl: 'Annuleren',
                            en: 'Cancel',
                            fr: 'Annuler',
                            es: 'Cancelar',
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.accent,
                          foregroundColor: theme.surface,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          _tl(
                            _lang,
                            nl: 'Factuur aanvragen',
                            en: 'Request invoice',
                            fr: 'Demander la facture',
                            es: 'Solicitar factura',
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared invoice detail sheet used by both company and driver flows. Shows only
/// safe, non-PII lifecycle fields and stays honest about Billit linkage.
///
/// Payment status uses the same semantic enum + [streetInvoicePaymentStatusLabel]
/// as the main card (1B) — never re-derives outstanding from booleans.
Future<void> showStreetInvoiceDetailSheet({
  required BuildContext context,
  required StreetInvoiceActionTheme theme,
  required AppLanguage language,
  required String reference,
  required StreetInvoiceInvoicePaymentStatus invoicePaymentStatus,
  required bool peppolSent,
  required bool hasBillitLink,
  StreetInvoicePdfAvailabilityState pdfState =
      StreetInvoicePdfAvailabilityState.preparing,
  StreetInvoiceProcessingStatus processingStatus =
      StreetInvoiceProcessingStatus.created,
  StreetInvoicePaymentDiagnostics? diagnostics,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: StreetInvoiceDetailSheetBody(
          theme: theme,
          language: language,
          reference: reference,
          invoicePaymentStatus: invoicePaymentStatus,
          peppolSent: peppolSent,
          hasBillitLink: hasBillitLink,
          pdfState: pdfState,
          processingStatus: processingStatus,
          diagnostics: diagnostics,
          onClose: () => Navigator.of(ctx).pop(),
        ),
      ),
    ),
  );
}

/// Responsive, testable content for the invoice detail sheet
/// (STREET-BUSINESS-INVOICE-PDF-PAYMENT-SYNC-1C).
///
/// Extracted from [showStreetInvoiceDetailSheet] so it can be widget-tested at
/// narrow (stacked) and wide (two-column) widths without driving a modal route.
///
/// The payment status is rendered ONLY from the semantic
/// [StreetInvoiceInvoicePaymentStatus] via [streetInvoicePaymentStatusLabel] —
/// there is no local boolean branching, so NL/EN/FR/ES can never diverge.
class StreetInvoiceDetailSheetBody extends StatelessWidget {
  const StreetInvoiceDetailSheetBody({
    super.key,
    required this.theme,
    required this.language,
    required this.reference,
    required this.invoicePaymentStatus,
    required this.peppolSent,
    required this.hasBillitLink,
    this.pdfState = StreetInvoicePdfAvailabilityState.preparing,
    this.processingStatus = StreetInvoiceProcessingStatus.created,
    this.diagnostics,
    this.onClose,
  });

  final StreetInvoiceActionTheme theme;
  final AppLanguage language;
  final String reference;
  final StreetInvoiceInvoicePaymentStatus invoicePaymentStatus;
  final bool peppolSent;
  final bool hasBillitLink;
  final StreetInvoicePdfAvailabilityState pdfState;
  final StreetInvoiceProcessingStatus processingStatus;
  final StreetInvoicePaymentDiagnostics? diagnostics;
  final VoidCallback? onClose;

  /// Below this content width the label sits ABOVE the value (phones); at or
  /// above it a flexible two-column layout is used. There is no fixed label
  /// width, so long Dutch labels like "Verwerkingsstatus" or "Factuurnummer"
  /// wrap only at word boundaries and never break mid-word.
  static const double stackBelowWidth = 360;

  Widget _row(String label, String value, {Color? valueColor}) {
    final labelStyle = TextStyle(color: theme.textSecondary, fontSize: 12.2);
    final valueStyle = TextStyle(
      color: valueColor ?? theme.textPrimary,
      fontSize: 12.6,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < stackBelowWidth;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle, softWrap: true),
                const SizedBox(height: 2),
                Text(value, style: valueStyle, softWrap: true),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Text(label, style: labelStyle, softWrap: true),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Text(value, style: valueStyle, softWrap: true),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paymentLabel = streetInvoicePaymentStatusLabel(
      language,
      invoicePaymentStatus,
    );
    final diag = diagnostics;
    if (diag != null) {
      logStreetInvoicePaymentPresentation(
        surface: 'modal',
        lang: language,
        diagnostics: diag,
        renderedLabel: paymentLabel,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.border.withOpacity(0.6),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _tl(
              language,
              nl: 'Factuur',
              en: 'Invoice',
              fr: 'Facture',
              es: 'Factura',
            ),
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 16.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          _row(
            _tl(
              language,
              nl: 'Factuurnummer',
              en: 'Invoice number',
              fr: 'Numéro de facture',
              es: 'Número de factura',
            ),
            reference.isNotEmpty ? reference : '—',
          ),
          _row(
            _tl(
              language,
              nl: 'Verwerkingsstatus',
              en: 'Invoice processing status',
              fr: 'Statut de traitement',
              es: 'Estado de procesamiento',
            ),
            _streetInvoiceProcessingLabel(language, processingStatus),
          ),
          _row(
            _tl(
              language,
              nl: 'Betaalstatus factuur',
              en: 'Invoice payment status',
              fr: 'Statut de paiement',
              es: 'Estado de pago',
            ),
            paymentLabel,
            valueColor: streetInvoicePaymentStatusColor(
              theme,
              invoicePaymentStatus,
            ),
          ),
          _row(
            _tl(
              language,
              nl: 'Billit-status',
              en: 'Billit status',
              fr: 'Statut Billit',
              es: 'Estado de Billit',
            ),
            hasBillitLink
                ? _tl(
                    language,
                    nl: 'Aangemaakt in Billit',
                    en: 'Created in Billit',
                    fr: 'Créée dans Billit',
                    es: 'Creada en Billit',
                  )
                : _tl(
                    language,
                    nl: 'Billit wordt bijgewerkt',
                    en: 'Billit is being updated',
                    fr: 'Billit est en cours de mise à jour',
                    es: 'Billit se está actualizando',
                  ),
          ),
          _row(
            _tl(
              language,
              nl: 'PDF-status',
              en: 'PDF status',
              fr: 'Statut PDF',
              es: 'Estado del PDF',
            ),
            _streetInvoicePdfStatusLabel(language, pdfState),
          ),
          _row(
            _tl(
              language,
              nl: 'Peppol-status',
              en: 'Peppol status',
              fr: 'Statut Peppol',
              es: 'Estado de Peppol',
            ),
            peppolSent
                ? _tl(
                    language,
                    nl: 'Verstuurd via Peppol',
                    en: 'Sent via Peppol',
                    fr: 'Envoyée via Peppol',
                    es: 'Enviada por Peppol',
                  )
                : _tl(
                    language,
                    nl: 'Niet verstuurd via Peppol',
                    en: 'Not sent via Peppol',
                    fr: 'Non envoyée via Peppol',
                    es: 'No enviada por Peppol',
                  ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: onClose,
              style: FilledButton.styleFrom(
                backgroundColor: theme.accent,
                foregroundColor: theme.surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 11,
                ),
              ),
              child: Text(
                _tl(
                  language,
                  nl: 'Sluiten',
                  en: 'Close',
                  fr: 'Fermer',
                  es: 'Cerrar',
                ),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
