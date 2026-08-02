part of '../main.dart';

class CompanyBookingsOverviewPage extends StatefulWidget {
  const CompanyBookingsOverviewPage({super.key});

  @override
  State<CompanyBookingsOverviewPage> createState() =>
      _CompanyBookingsOverviewPageState();
}

class _CompanyBookingsOverviewPageState
    extends State<CompanyBookingsOverviewPage> {
  bool _loading = true;
  String? _errorCode;
  List<_CompanyBookingOverviewItem> _all =
      const <_CompanyBookingOverviewItem>[];
  _CompanyBookingsFilter _filter = _CompanyBookingsFilter.open;
  final Set<String> _archivingBookingIds = <String>{};
  final Set<String> _cancellingBookingIds = <String>{};
  final Set<String> _decidingCreditBookingIds = <String>{};
  final Set<String> _refundingBookingIds = <String>{};
  bool _bulkArchiving = false;
  bool _creditAuthAdminToken = false;
  bool _creditAuthCompanySession = false;
  bool _creditAuthEnabled = false;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  _CompanyBookingsThemeTokens _themeTokensFor(BusinessThemeVariant variant) {
    final palette = paletteForBusinessTheme(variant);
    final isExecutiveGold = variant == BusinessThemeVariant.executiveGold;
    final isClean = variant == BusinessThemeVariant.cleanProfessional;
    final cardGradient = isClean
        ? <Color>[palette.surface, palette.surface, palette.surfaceAlt]
        : <Color>[palette.surface, palette.background, palette.surfaceAlt];
    final legAccent = isExecutiveGold
        ? const Color(0xFF52B6FF)
        : palette.accent;
    return _CompanyBookingsThemeTokens(
      palette: palette,
      background: palette.background,
      appBar: palette.background,
      cardGradient: cardGradient,
      cardBorder: palette.border.withOpacity(isClean ? 0.95 : 0.58),
      shadow: Colors.black.withOpacity(isClean ? 0.08 : 0.26),
      accent: palette.accent,
      legAccent: legAccent,
      textPrimary: palette.textPrimary,
      textSecondary: palette.textMuted,
      textTertiary: palette.textMuted.withOpacity(isClean ? 0.88 : 0.74),
      chipSelectedBg: palette.accent.withOpacity(isClean ? 0.14 : 0.16),
      chipUnselectedBg: palette.surfaceAlt.withOpacity(isClean ? 0.9 : 0.78),
      chipSelectedBorder: palette.accent.withOpacity(0.62),
      chipUnselectedBorder: palette.border.withOpacity(isClean ? 0.84 : 0.42),
      chipSelectedText: palette.accent,
      chipUnselectedText: palette.textMuted,
      paidBg: palette.success.withOpacity(isClean ? 0.12 : 0.14),
      paidBorder: palette.success.withOpacity(0.45),
      paidText: palette.success,
      unpaidBg: palette.accent.withOpacity(isClean ? 0.12 : 0.13),
      unpaidBorder: palette.accent.withOpacity(0.42),
      unpaidText: palette.accent,
      warningText: const Color(0xFFF6B94D),
      danger: palette.danger,
      reviewPrimaryText: isClean ? palette.textPrimary : palette.textPrimary,
      reviewSecondaryText: isClean
          ? palette.textMuted.withOpacity(0.96)
          : palette.textMuted.withOpacity(0.9),
      reviewPlaceholderText: isClean
          ? palette.textMuted.withOpacity(0.98)
          : palette.textMuted.withOpacity(0.92),
      reviewWarningText: isClean
          ? const Color(0xFF8A5A00)
          : const Color(0xFFF6B94D),
    );
  }

  bool _isMissingValue(String value) {
    final text = value.trim();
    return text.isEmpty || text == '—' || text == '-';
  }

  bool _isCancellingBooking(String busyKey) {
    return _cancellingBookingIds.contains(busyKey);
  }

  String _cancelBusyKey(_CompanyBookingOverviewItem item) {
    final bookingId = item.bookingId.trim();
    final legId = item.legId.trim();
    if (legId.isEmpty) return bookingId;
    return '$bookingId::$legId';
  }

  bool _isRoundtripLegCancelEligible(_CompanyBookingOverviewItem item) {
    return item.isOperationalLeg &&
        item.isRoundtripParent &&
        item.legId.trim().isNotEmpty;
  }

  bool _canApplyCreditDecisions() => _creditAuthEnabled;

  Future<void> _refreshCreditAuthState() async {
    // SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Phase C): credit-decision
    // auth is now company-session only; the platform admin token is no
    // longer available client-side.
    final resolved = await CompanySessionStore.instance
        .resolveBackendUsableCompanyContext();
    final companySession = resolved.ok;
    if (!mounted) return;
    setState(() {
      _creditAuthAdminToken = false;
      _creditAuthCompanySession = companySession;
      _creditAuthEnabled = companySession;
    });
    debugPrint(
      '[COMPANY_BOOKINGS][CREDIT_AUTH] admin_token=false company_session=$companySession enabled=$companySession',
    );
  }

  Future<Map<String, String>> _creditDecisionHeaders() async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final resolved = await CompanySessionStore.instance
        .resolveBackendUsableCompanyContext();
    if (resolved.ok) {
      final tokenResolved = await CompanySessionStore.instance
          .resolveCompanyBootstrapToken();
      final token = (tokenResolved.token ?? '').trim();
      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  bool _isDecidingCredit(String bookingId) {
    return _decidingCreditBookingIds.contains(bookingId);
  }

  bool _isRefundingBooking(String bookingId) {
    return _refundingBookingIds.contains(bookingId);
  }

  bool _canShowMollieRefundAction(_CompanyBookingOverviewItem item) {
    return _canApplyCreditDecisions() &&
        _CompanyBookingOverviewItem.canShowMollieRefundAction(item);
  }

  bool _canShowMollieRefundAuditResyncAction(_CompanyBookingOverviewItem item) {
    return _canApplyCreditDecisions() &&
        _CompanyBookingOverviewItem.canShowMollieRefundAuditResyncAction(item);
  }

  bool _canShowMollieRefundStatusRefreshAction(
    _CompanyBookingOverviewItem item,
  ) {
    return _canApplyCreditDecisions() &&
        _CompanyBookingOverviewItem.canShowMollieRefundStatusRefreshAction(
          item,
        );
  }

  bool _shouldShowMollieRefundStatus(_CompanyBookingOverviewItem item) {
    return _CompanyBookingOverviewItem.shouldShowMollieRefundStatus(item);
  }

  String _localizedMollieRefundStatus(_CompanyBookingOverviewItem item) {
    if (_CompanyBookingOverviewItem.isMollieRefundDisplayPending(item)) {
      return _t(
        nl: 'Terugbetaling in behandeling',
        en: 'Refund pending',
        fr: 'Remboursement en attente',
        es: 'Reembolso pendiente',
      );
    }
    if (_CompanyBookingOverviewItem.isMollieRefundDisplayRefunded(item)) {
      return _t(
        nl: 'Terugbetaald',
        en: 'Refunded',
        fr: 'Remboursé',
        es: 'Reembolsado',
      );
    }
    if (_CompanyBookingOverviewItem.isMollieRefundStatusFailed(
      item.mollieRefundStatus,
    )) {
      return _t(
        nl: 'Terugbetaling mislukt',
        en: 'Refund failed',
        fr: 'Remboursement échoué',
        es: 'Reembolso fallido',
      );
    }
    return _t(
      nl: 'Niet terugbetaald',
      en: 'Not refunded',
      fr: 'Non remboursé',
      es: 'No reembolsado',
    );
  }

  Color _mollieRefundStatusColor(
    _CompanyBookingOverviewItem item,
    _CompanyBookingsThemeTokens tokens,
  ) {
    if (_CompanyBookingOverviewItem.isMollieRefundDisplayRefunded(item)) {
      return tokens.paidText;
    }
    if (_CompanyBookingOverviewItem.isMollieRefundDisplayPending(item)) {
      return tokens.warningText;
    }
    if (_CompanyBookingOverviewItem.isMollieRefundStatusFailed(
      item.mollieRefundStatus,
    )) {
      return tokens.danger;
    }
    return tokens.textSecondary;
  }

  String _mollieRefundCreditedAmountLabel(_CompanyBookingOverviewItem item) {
    if (item.creditedAmountCents != null && item.creditedAmountCents! > 0) {
      return _moneyLabelFromAmount(
        item.creditedAmountCents! / 100,
        item.currency,
      );
    }
    return _moneyLabel(item);
  }

  Future<({bool ok, String error, bool auditResync})> _applyMollieRefundById({
    required String bookingId,
    String? legId,
    String? legType,
    String refundScope = 'full_parent',
  }) async {
    final id = bookingId.trim();
    if (id.isEmpty) {
      return (ok: false, error: 'missing_booking_id', auditResync: false);
    }
    final safeLegId = (legId ?? '').trim();
    final safeLegType = (legType ?? '').trim();
    final scopeQuery = _activeBookingScopeQuery();
    final uri = _withActiveBookingScope(
      kBookingBaseUrl,
      '$kBookingMollieRefundPath/${Uri.encodeComponent(id)}/mollie-refund',
    );
    const actorRole = 'company';
    final payload = <String, dynamic>{
      'booking_id': id,
      'actor_role': actorRole,
      'actorRole': actorRole,
      'refund_scope': refundScope,
      'refundScope': refundScope,
      if (safeLegId.isNotEmpty) 'leg_id': safeLegId,
      if (safeLegId.isNotEmpty) 'legId': safeLegId,
      if (safeLegType.isNotEmpty) 'leg_type': safeLegType,
      if (safeLegType.isNotEmpty) 'legType': safeLegType,
      if (scopeQuery['tenant_id'] != null) 'tenant_id': scopeQuery['tenant_id'],
      if (scopeQuery['company_id'] != null)
        'company_id': scopeQuery['company_id'],
      if (scopeQuery['tenantId'] != null) 'tenantId': scopeQuery['tenantId'],
      if (scopeQuery['companyId'] != null) 'companyId': scopeQuery['companyId'],
    };
    try {
      debugPrint(
        '[COMPANY_BOOKINGS][MOLLIE_REFUND][REQ] booking=$id leg=${safeLegId.isEmpty ? "-" : safeLegId} scope=$refundScope',
      );
      debugPrint(
        '[LEG_REFUND][TARGET] booking=$id leg=${safeLegId.isEmpty ? "-" : safeLegId} scope=$refundScope',
      );
      final res = await http
          .post(
            uri,
            headers: await _creditDecisionHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        decoded = null;
      }
      final auditResync =
          decoded is Map<String, dynamic> &&
          (decoded['compliance_backfill_ok'] == true ||
              decoded['compliance_final_backfill_ok'] == true);
      final ok =
          decoded is Map<String, dynamic> &&
          (res.statusCode == 200 && decoded['ok'] == true || auditResync);
      final err = decoded is Map<String, dynamic>
          ? (decoded['error'] ?? '').toString().trim()
          : 'invalid_payload';
      final refundStatus = decoded is Map<String, dynamic>
          ? (decoded['refund_status'] ?? decoded['refundStatus'] ?? '')
                .toString()
                .trim()
          : '';
      debugPrint(
        '[COMPANY_BOOKINGS][MOLLIE_REFUND][RES] booking=$id status=${res.statusCode} ok=$ok error=${err.isEmpty ? "-" : err} refund_status=${refundStatus.isEmpty ? "-" : refundStatus} audit_resync=$auditResync',
      );
      if (decoded is! Map<String, dynamic>) {
        return (ok: false, error: 'invalid_payload', auditResync: false);
      }
      if (auditResync) {
        return (ok: true, error: '', auditResync: true);
      }
      if (res.statusCode != 200 || decoded['ok'] != true) {
        final err = (decoded['error'] ?? '').toString().trim();
        final mollieErr = (decoded['mollie_error'] ?? '').toString().trim();
        if (err.isEmpty) {
          return (
            ok: false,
            error: 'http_${res.statusCode}',
            auditResync: false,
          );
        }
        if (mollieErr.isNotEmpty) {
          return (ok: false, error: '$err ($mollieErr)', auditResync: false);
        }
        return (ok: false, error: err, auditResync: false);
      }
      return (ok: true, error: '', auditResync: false);
    } catch (_) {
      debugPrint(
        '[COMPANY_BOOKINGS][MOLLIE_REFUND][RES] booking=$id status=- ok=false error=request_failed refund_status=- audit_resync=false',
      );
      return (ok: false, error: 'request_failed', auditResync: false);
    }
  }

  Future<
    ({
      bool ok,
      String error,
      String refundStatus,
      String mollieRefundStatus,
      bool complianceEmitOk,
    })
  >
  _applyMollieRefundStatusRefreshById({
    required String bookingId,
    String? legId,
    String? legType,
    String refundScope = 'full_parent',
    String? mollieRefundId,
  }) async {
    final id = bookingId.trim();
    if (id.isEmpty) {
      return (
        ok: false,
        error: 'missing_booking_id',
        refundStatus: '',
        mollieRefundStatus: '',
        complianceEmitOk: false,
      );
    }
    final safeLegId = (legId ?? '').trim();
    final safeLegType = (legType ?? '').trim();
    final safeRefundId = (mollieRefundId ?? '').trim();
    final scopeQuery = _activeBookingScopeQuery();
    final uri = _withActiveBookingScope(
      kBookingBaseUrl,
      '$kBookingMollieRefundStatusRefreshPath/${Uri.encodeComponent(id)}/mollie-refund/status-refresh',
    );
    const actorRole = 'company';
    final payload = <String, dynamic>{
      'booking_id': id,
      'actor_role': actorRole,
      'actorRole': actorRole,
      'refund_scope': refundScope,
      'refundScope': refundScope,
      if (safeLegId.isNotEmpty) 'leg_id': safeLegId,
      if (safeLegId.isNotEmpty) 'legId': safeLegId,
      if (safeLegType.isNotEmpty) 'leg_type': safeLegType,
      if (safeLegType.isNotEmpty) 'legType': safeLegType,
      if (safeRefundId.isNotEmpty) 'mollie_refund_id': safeRefundId,
      if (safeRefundId.isNotEmpty) 'mollieRefundId': safeRefundId,
      if (scopeQuery['tenant_id'] != null) 'tenant_id': scopeQuery['tenant_id'],
      if (scopeQuery['company_id'] != null)
        'company_id': scopeQuery['company_id'],
      if (scopeQuery['tenantId'] != null) 'tenantId': scopeQuery['tenantId'],
      if (scopeQuery['companyId'] != null) 'companyId': scopeQuery['companyId'],
    };
    try {
      debugPrint('[COMPANY_BOOKINGS][MOLLIE_REFUND_STATUS][REQ] booking=$id');
      debugPrint(
        '[LEG_REFUND_STATUS][TARGET] booking=$id leg=${safeLegId.isEmpty ? "-" : safeLegId} '
        'scope=$refundScope refund_id=${safeRefundId.isEmpty ? "empty" : "present"}',
      );
      // Visibility into what we actually transmit — useful when triaging
      // missing_mollie_refund_id without leaking PII because the masked id
      // presence is enough for diagnosis.
      debugPrint(
        '[LEG_REFUND_STATUS][PAYLOAD] booking=$id leg=${safeLegId.isEmpty ? "-" : safeLegId} '
        'leg_type=${safeLegType.isEmpty ? "-" : safeLegType} '
        'scope=$refundScope refund_id=${safeRefundId.isEmpty ? "empty" : "present"} '
        'actor_role=$actorRole '
        'body_keys=${payload.keys.toList()}',
      );
      final res = await http
          .post(
            uri,
            headers: await _creditDecisionHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        decoded = null;
      }
      final ok =
          decoded is Map<String, dynamic> &&
          res.statusCode == 200 &&
          decoded['ok'] == true;
      final err = decoded is Map<String, dynamic>
          ? (decoded['error'] ?? '').toString().trim()
          : 'invalid_payload';
      final refundStatus = decoded is Map<String, dynamic>
          ? (decoded['refund_status'] ?? decoded['refundStatus'] ?? '')
                .toString()
                .trim()
          : '';
      final mollieRefundStatus = decoded is Map<String, dynamic>
          ? (decoded['mollie_refund_status'] ??
                    decoded['mollieRefundStatus'] ??
                    '')
                .toString()
                .trim()
          : '';
      final complianceEmitOk =
          decoded is Map<String, dynamic> &&
          (decoded['compliance_emit_ok'] == true ||
              decoded['complianceEmitOk'] == true);
      debugPrint(
        '[COMPANY_BOOKINGS][MOLLIE_REFUND_STATUS][RES] booking=$id status=${res.statusCode} ok=$ok error=${err.isEmpty ? "-" : err} refund_status=${refundStatus.isEmpty ? "-" : refundStatus} mollie_refund_status=${mollieRefundStatus.isEmpty ? "-" : mollieRefundStatus} compliance_emit_ok=$complianceEmitOk',
      );
      debugPrint(
        '[LEG_REFUND_STATUS][RES] booking=$id leg=${safeLegId.isEmpty ? "-" : safeLegId} '
        'scope=$refundScope http=${res.statusCode} ok=$ok '
        'error=${err.isEmpty ? "-" : err} '
        'refund_status=${refundStatus.isEmpty ? "-" : refundStatus} '
        'mollie_refund_status=${mollieRefundStatus.isEmpty ? "-" : mollieRefundStatus}',
      );
      if (decoded is! Map<String, dynamic>) {
        return (
          ok: false,
          error: 'invalid_payload',
          refundStatus: '',
          mollieRefundStatus: '',
          complianceEmitOk: false,
        );
      }
      if (!ok) {
        if (err.isEmpty) {
          return (
            ok: false,
            error: 'http_${res.statusCode}',
            refundStatus: refundStatus,
            mollieRefundStatus: mollieRefundStatus,
            complianceEmitOk: false,
          );
        }
        return (
          ok: false,
          error: err,
          refundStatus: refundStatus,
          mollieRefundStatus: mollieRefundStatus,
          complianceEmitOk: false,
        );
      }
      return (
        ok: true,
        error: '',
        refundStatus: refundStatus,
        mollieRefundStatus: mollieRefundStatus,
        complianceEmitOk: complianceEmitOk,
      );
    } catch (_) {
      debugPrint(
        '[COMPANY_BOOKINGS][MOLLIE_REFUND_STATUS][RES] booking=$id status=- ok=false error=request_failed refund_status=- mollie_refund_status=- compliance_emit_ok=false',
      );
      debugPrint(
        '[LEG_REFUND_STATUS][RES] booking=$id leg=${safeLegId.isEmpty ? "-" : safeLegId} '
        'scope=$refundScope http=- ok=false error=request_failed',
      );
      return (
        ok: false,
        error: 'request_failed',
        refundStatus: '',
        mollieRefundStatus: '',
        complianceEmitOk: false,
      );
    }
  }

  Future<void> _runMollieRefundStatusRefresh(
    _CompanyBookingOverviewItem item,
  ) async {
    if (!_canShowMollieRefundStatusRefreshAction(item)) return;
    // Hard runtime guard: never POST to the status-refresh endpoint when this
    // exact row/leg has no refund id we can refresh. The helper already hides
    // the button when [mollieRefundId] is empty; this defends against stale
    // taps (e.g. background refresh after the id was cleared).
    if (item.mollieRefundId.trim().isEmpty) {
      final bookingRefDiag = item.referenceText.trim().isNotEmpty
          ? item.referenceText.trim()
          : item.bookingId.trim();
      debugPrint(
        '[REFUND_STATUS_BUTTON][HIDDEN_NO_REFUND_ID] booking=$bookingRefDiag '
        'leg=${item.legId.trim().isEmpty ? "-" : item.legId.trim()} '
        'reason=runtime_guard',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Geen geldig terugbetaal-ID gevonden voor deze rit.',
              en: 'No valid refund id available for this ride.',
              fr: 'Aucun identifiant de remboursement valide pour ce trajet.',
              es: 'No hay un identificador de reembolso válido para este viaje.',
            ),
          ),
        ),
      );
      return;
    }
    final target = _CompanyBookingOverviewItem.resolveMollieRefundTarget(item);
    final bookingId = target.bookingId.isNotEmpty
        ? target.bookingId
        : _creditDecisionTargetBookingId(item);
    if (bookingId.isEmpty || _isRefundingBooking(bookingId)) return;
    setState(() {
      _refundingBookingIds.add(bookingId);
    });
    final out = await _applyMollieRefundStatusRefreshById(
      bookingId: bookingId,
      legId: target.legId.isEmpty ? null : target.legId,
      legType: target.legType.isEmpty ? null : target.legType,
      refundScope: target.refundScope,
      mollieRefundId: item.mollieRefundId,
    );
    if (!mounted) return;
    setState(() {
      _refundingBookingIds.remove(bookingId);
    });
    if (out.ok) {
      await _loadBookings();
      if (!mounted) return;
      final isRefunded =
          _CompanyBookingOverviewItem.isRefundStatusRefundedOrComplete(
            out.refundStatus,
          ) ||
          _CompanyBookingOverviewItem.isMollieRefundStatusRefunded(
            out.mollieRefundStatus,
          );
      final isPending =
          !isRefunded &&
          (_CompanyBookingOverviewItem.isRefundStatusPending(
                out.refundStatus,
              ) ||
              _CompanyBookingOverviewItem.isMollieRefundStatusPending(
                out.mollieRefundStatus,
              ));
      final isFailed =
          !isRefunded &&
          !isPending &&
          (_CompanyBookingOverviewItem.isMollieRefundStatusFailed(
                out.mollieRefundStatus,
              ) ||
              out.refundStatus.trim().toUpperCase().contains('FAIL') ||
              out.refundStatus.trim().toUpperCase().contains('CANCEL'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRefunded
                ? _t(
                    nl: 'Terugbetaling bevestigd.',
                    en: 'Refund confirmed.',
                    fr: 'Remboursement confirmé.',
                    es: 'Reembolso confirmado.',
                  )
                : isPending
                ? _t(
                    nl: 'Terugbetaling is nog in behandeling.',
                    en: 'Refund is still pending.',
                    fr: 'Le remboursement est encore en attente.',
                    es: 'El reembolso sigue pendiente.',
                  )
                : isFailed
                ? _t(
                    nl: 'Terugbetalingsstatuscontrole mislukt.',
                    en: 'Refund status check failed.',
                    fr: 'Échec de la vérification du remboursement.',
                    es: 'Falló la comprobación del reembolso.',
                  )
                : _t(
                    nl: 'Terugbetalingsstatus bijgewerkt.',
                    en: 'Refund status updated.',
                    fr: 'Statut de remboursement mis à jour.',
                    es: 'Estado de reembolso actualizado.',
                  ),
          ),
        ),
      );
      return;
    }
    await _loadBookings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Terugbetalingsstatuscontrole mislukt (${out.error}).',
            en: 'Refund status check failed (${out.error}).',
            fr: 'Échec de la vérification du remboursement (${out.error}).',
            es: 'Falló la comprobación del reembolso (${out.error}).',
          ),
        ),
      ),
    );
  }

  Future<void> _runMollieRefund(
    _CompanyBookingOverviewItem item, {
    required String successMessage,
  }) async {
    if (!_canShowMollieRefundAction(item)) return;
    final target = _CompanyBookingOverviewItem.resolveMollieRefundTarget(item);
    if (target.bookingId.isEmpty || _isRefundingBooking(target.bookingId))
      return;
    setState(() {
      _refundingBookingIds.add(target.bookingId);
    });
    final out = await _applyMollieRefundById(
      bookingId: target.bookingId,
      legId: target.legId.isEmpty ? null : target.legId,
      legType: target.legType.isEmpty ? null : target.legType,
      refundScope: target.refundScope,
    );
    if (!mounted) return;
    setState(() {
      _refundingBookingIds.remove(target.bookingId);
    });
    if (out.ok) {
      await _loadBookings();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
      return;
    }
    if (out.error == 'booking_not_cancelled' && target.legId.isNotEmpty) {
      debugPrint(
        '[LEG_REFUND][BLOCKED] booking=${target.bookingId} leg=${target.legId} reason=${out.error}',
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Mollie-terugbetaling mislukt (${out.error}).',
            en: 'Mollie refund failed (${out.error}).',
            fr: 'Remboursement Mollie échoué (${out.error}).',
            es: 'Reembolso Mollie fallido (${out.error}).',
          ),
        ),
      ),
    );
  }

  Future<void> _runMollieRefundAuditResync(
    _CompanyBookingOverviewItem item,
  ) async {
    if (!_canShowMollieRefundAuditResyncAction(item)) return;
    final target = _CompanyBookingOverviewItem.resolveMollieRefundTarget(item);
    if (target.bookingId.isEmpty || _isRefundingBooking(target.bookingId))
      return;
    setState(() {
      _refundingBookingIds.add(target.bookingId);
    });
    final out = await _applyMollieRefundById(
      bookingId: target.bookingId,
      legId: target.legId.isEmpty ? null : target.legId,
      legType: target.legType.isEmpty ? null : target.legType,
      refundScope: target.refundScope,
    );
    if (!mounted) return;
    setState(() {
      _refundingBookingIds.remove(target.bookingId);
    });
    if (out.ok && out.auditResync) {
      await _loadBookings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Chiron-audit voor Mollie-terugbetaling gesynchroniseerd.',
              en: 'Chiron audit for Mollie refund synchronized.',
              fr: 'Audit Chiron pour remboursement Mollie synchronisé.',
              es: 'Auditoría Chiron para reembolso Mollie sincronizada.',
            ),
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Chiron-auditsync mislukt (${out.error}).',
            en: 'Chiron audit sync failed (${out.error}).',
            fr: 'Synchronisation audit Chiron échouée (${out.error}).',
            es: 'Sincronización de auditoría Chiron fallida (${out.error}).',
          ),
        ),
      ),
    );
  }

  Future<
    ({
      String mollieMode,
      String paymentCredentialSource,
      String paymentOwnerMode,
      bool paymentDemoMode,
    })
  >
  _fetchMollieRefundSafetyContext(_CompanyBookingOverviewItem item) async {
    const unknown = (
      mollieMode: 'unknown',
      paymentCredentialSource: '',
      paymentOwnerMode: '',
      paymentDemoMode: false,
    );
    final target = _CompanyBookingOverviewItem.resolveMollieRefundTarget(item);
    final id = target.bookingId.trim();
    if (id.isEmpty) return unknown;
    final safeLegId = target.legId.trim();
    final safeLegType = target.legType.trim();
    final scopeQuery = _activeBookingScopeQuery();
    final uri = _withActiveBookingScope(
      kBookingBaseUrl,
      '$kBookingMollieRefundPath/${Uri.encodeComponent(id)}/mollie-refund/status-snapshot',
    );
    const actorRole = 'company';
    final payload = <String, dynamic>{
      'booking_id': id,
      'actor_role': actorRole,
      'actorRole': actorRole,
      if (safeLegId.isNotEmpty) 'leg_id': safeLegId,
      if (safeLegId.isNotEmpty) 'legId': safeLegId,
      if (safeLegType.isNotEmpty) 'leg_type': safeLegType,
      if (safeLegType.isNotEmpty) 'legType': safeLegType,
      if (scopeQuery['tenant_id'] != null) 'tenant_id': scopeQuery['tenant_id'],
      if (scopeQuery['company_id'] != null)
        'company_id': scopeQuery['company_id'],
      if (scopeQuery['tenantId'] != null) 'tenantId': scopeQuery['tenantId'],
      if (scopeQuery['companyId'] != null) 'companyId': scopeQuery['companyId'],
    };
    try {
      final res = await http
          .post(
            uri,
            headers: await _creditDecisionHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));
      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        return unknown;
      }
      if (decoded is! Map<String, dynamic> ||
          res.statusCode != 200 ||
          decoded['ok'] != true) {
        return unknown;
      }
      final safety = decoded['payment_safety'];
      if (safety is! Map<String, dynamic>) return unknown;
      final rawMode = (safety['mollie_mode'] ?? safety['mollieMode'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final mollieMode = rawMode == 'test' || rawMode == 'live'
          ? rawMode
          : 'unknown';
      final credentialSource =
          (safety['payment_credential_source'] ??
                  safety['paymentCredentialSource'] ??
                  '')
              .toString()
              .trim();
      final ownerMode =
          (safety['payment_owner_mode'] ?? safety['paymentOwnerMode'] ?? '')
              .toString()
              .trim();
      final demoMode =
          safety['payment_demo_mode'] == true ||
          safety['paymentDemoMode'] == true;
      return (
        mollieMode: mollieMode,
        paymentCredentialSource: credentialSource,
        paymentOwnerMode: ownerMode,
        paymentDemoMode: demoMode,
      );
    } catch (_) {
      return unknown;
    }
  }

  String _mollieRefundSafetyModeTitle(String mollieMode) {
    switch (mollieMode) {
      case 'test':
        return _t(
          nl: 'Mollie-modus: TEST',
          en: 'Mollie mode: TEST',
          fr: 'Mode Mollie : TEST',
          es: 'Modo Mollie: PRUEBA',
        );
      case 'live':
        return _t(
          nl: 'Mollie-modus: LIVE',
          en: 'Mollie mode: LIVE',
          fr: 'Mode Mollie : LIVE',
          es: 'Modo Mollie: EN VIVO',
        );
      default:
        return _t(
          nl: 'Mollie-modus: onbekend',
          en: 'Mollie mode: unknown',
          fr: 'Mode Mollie : inconnu',
          es: 'Modo Mollie: desconocido',
        );
    }
  }

  String _mollieRefundSafetyModeDetail(String mollieMode) {
    switch (mollieMode) {
      case 'test':
        return _t(
          nl: 'Dit is een testterugbetaling. Er wordt geen echt geld teruggestort.',
          en: 'This is a test refund. No real money will be returned.',
          fr: 'Ceci est un remboursement test. Aucun argent réel ne sera remboursé.',
          es: 'Este es un reembolso de prueba. No se devolverá dinero real.',
        );
      case 'live':
        return _t(
          nl: 'Dit voert een echte terugbetaling uit naar de klant.',
          en: 'This will execute a real refund to the customer.',
          fr: 'Ceci exécutera un remboursement réel vers le client.',
          es: 'Esto ejecutará un reembolso real al cliente.',
        );
      default:
        return _t(
          nl: 'De Mollie-modus kon niet worden gecontroleerd.',
          en: 'The Mollie mode could not be verified.',
          fr: 'Le mode Mollie n\'a pas pu être vérifié.',
          es: 'No se pudo verificar el modo Mollie.',
        );
    }
  }

  Color _mollieRefundSafetyBadgeColor(
    String mollieMode,
    _CompanyBookingsThemeTokens tokens,
  ) {
    switch (mollieMode) {
      case 'test':
        return tokens.warningText;
      case 'live':
        return tokens.danger;
      default:
        return tokens.textSecondary;
    }
  }

  Future<void> _confirmMollieRefund(_CompanyBookingOverviewItem item) async {
    if (!_canShowMollieRefundAction(item)) return;
    final tokens = _themeTokensFor(businessThemeNotifier.value);
    final creditedAmountLabel = _mollieRefundCreditedAmountLabel(item);
    final safety = await _fetchMollieRefundSafetyContext(item);
    if (!mounted) return;
    final badgeColor = _mollieRefundSafetyBadgeColor(safety.mollieMode, tokens);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          _t(
            nl: 'Mollie-terugbetaling uitvoeren',
            en: 'Execute Mollie refund',
            fr: 'Exécuter le remboursement Mollie',
            es: 'Ejecutar reembolso Mollie',
          ),
          style: TextStyle(color: tokens.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: badgeColor.withValues(alpha: 0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _mollieRefundSafetyModeTitle(safety.mollieMode),
                    style: TextStyle(
                      color: badgeColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _mollieRefundSafetyModeDetail(safety.mollieMode),
                    style: TextStyle(
                      color: tokens.textSecondary,
                      height: 1.35,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _t(
                nl: 'Boeking: ${_shortBookingReference(item)}\n\nBedrag: $creditedAmountLabel\n\nDeze actie kan geld terugstorten naar de klant en mag alleen worden gebruikt na controle van de creditbeslissing.',
                en: 'Booking: ${_shortBookingReference(item)}\n\nAmount: $creditedAmountLabel\n\nThis action may transfer money back to the customer and should only be used after reviewing the credit decision.',
                fr: 'Réservation : ${_shortBookingReference(item)}\n\nMontant : $creditedAmountLabel\n\nCette action peut renvoyer de l\'argent au client et ne doit être utilisée qu\'après examen de la décision de crédit.',
                es: 'Reserva: ${_shortBookingReference(item)}\n\nImporte: $creditedAmountLabel\n\nEsta acción puede devolver dinero al cliente y solo debe usarse tras revisar la decisión de crédito.',
              ),
              style: TextStyle(color: tokens.textSecondary, height: 1.35),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
              style: TextStyle(color: tokens.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _t(
                nl: 'Terugbetaling uitvoeren',
                en: 'Execute refund',
                fr: 'Exécuter le remboursement',
                es: 'Ejecutar reembolso',
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runMollieRefund(
      item,
      successMessage: _t(
        nl: 'Mollie-terugbetaling uitgevoerd.',
        en: 'Mollie refund executed.',
        fr: 'Remboursement Mollie exécuté.',
        es: 'Reembolso Mollie ejecutado.',
      ),
    );
  }

  String _creditDecisionTargetBookingId(_CompanyBookingOverviewItem item) {
    if (!_CompanyBookingOverviewItem.canExecuteCompanyBookingMoneyAction(
      item,
    )) {
      return '';
    }
    final parent = item.parentBookingId.trim();
    if (parent.isNotEmpty) return parent;
    return item.bookingId.trim();
  }

  String _creditDecisionBusyKey(_CompanyBookingOverviewItem item) =>
      _CompanyBookingOverviewItem.creditDecisionBusyKey(item);

  num? _creditDecisionFullAmount(_CompanyBookingOverviewItem item) =>
      _CompanyBookingOverviewItem.creditDecisionMaxAmount(item);

  Future<({bool ok, String error})> _applyCreditDecisionById({
    required String bookingId,
    required String creditDecision,
    int? partialAmountCents,
    String? legId,
    String? legType,
    _AdminCreditScope creditScope = _AdminCreditScope.fullParent,
  }) async {
    final id = bookingId.trim();
    if (id.isEmpty) return (ok: false, error: 'missing_booking_id');
    final safeLegId = (legId ?? '').trim();
    final safeLegType = (legType ?? '').trim();
    final scopeQuery = _activeBookingScopeQuery();
    final uri = _withActiveBookingScope(
      kBookingBaseUrl,
      '$kBookingCreditDecisionPath/${Uri.encodeComponent(id)}/credit-decision',
    );
    const actorRole = 'company';
    final scopeToken = creditScope == _AdminCreditScope.legOnly
        ? 'leg_only'
        : 'full_parent';
    final payload = <String, dynamic>{
      'booking_id': id,
      'credit_decision': creditDecision,
      'creditDecision': creditDecision,
      'actor_role': actorRole,
      'actorRole': actorRole,
      'credit_scope': scopeToken,
      'creditScope': scopeToken,
      if (partialAmountCents != null)
        'partial_amount_cents': partialAmountCents,
      if (partialAmountCents != null) 'partialAmountCents': partialAmountCents,
      if (safeLegId.isNotEmpty) 'leg_id': safeLegId,
      if (safeLegId.isNotEmpty) 'legId': safeLegId,
      if (safeLegType.isNotEmpty) 'leg_type': safeLegType,
      if (safeLegType.isNotEmpty) 'legType': safeLegType,
      if (scopeQuery['tenant_id'] != null) 'tenant_id': scopeQuery['tenant_id'],
      if (scopeQuery['company_id'] != null)
        'company_id': scopeQuery['company_id'],
      if (scopeQuery['tenantId'] != null) 'tenantId': scopeQuery['tenantId'],
      if (scopeQuery['companyId'] != null) 'companyId': scopeQuery['companyId'],
    };
    debugPrint(
      '[CREDIT_SCOPE][${creditScope == _AdminCreditScope.legOnly ? "LEG_ONLY" : "FULL_PARENT"}] booking=$id leg=${safeLegId.isEmpty ? "-" : safeLegId} '
      'leg_type=${safeLegType.isEmpty ? "-" : safeLegType} decision=$creditDecision',
    );
    try {
      final res = await http
          .post(
            uri,
            headers: await _creditDecisionHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));
      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        decoded = null;
      }
      if (decoded is! Map<String, dynamic>) {
        return (ok: false, error: 'invalid_payload');
      }
      if (res.statusCode != 200 || decoded['ok'] != true) {
        final err = (decoded['error'] ?? '').toString().trim();
        return (ok: false, error: err.isEmpty ? 'http_${res.statusCode}' : err);
      }
      return (ok: true, error: '');
    } catch (_) {
      return (ok: false, error: 'request_failed');
    }
  }

  Future<void> _runCreditDecision(
    _CompanyBookingOverviewItem item,
    String creditDecision, {
    int? partialAmountCents,
    required String successMessage,
  }) async {
    if (!_canApplyCreditDecisions()) return;
    if (!_CompanyBookingOverviewItem.canExecuteCompanyBookingMoneyAction(
      item,
    )) {
      return;
    }
    final bookingId = _creditDecisionTargetBookingId(item);
    final busyKey = _creditDecisionBusyKey(item);
    if (bookingId.isEmpty || _isDecidingCredit(busyKey)) return;
    final creditScope = _CompanyBookingOverviewItem.creditScopeForItem(item);
    setState(() {
      _decidingCreditBookingIds.add(busyKey);
    });
    final out = await _applyCreditDecisionById(
      bookingId: bookingId,
      creditDecision: creditDecision,
      partialAmountCents: partialAmountCents,
      legId: item.legId,
      legType: item.legType,
      creditScope: creditScope,
    );
    if (!mounted) return;
    setState(() {
      _decidingCreditBookingIds.remove(busyKey);
    });
    if (out.ok) {
      debugPrint(
        '[CREDIT_DECISION][STATE] booking=$bookingId leg=${item.legId.trim().isEmpty ? "-" : item.legId.trim()} '
        'decision=$creditDecision ok=true',
      );
      await _loadBookings();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
      return;
    }
    // Stale UI race: the row was tapped after the backend (or another
    // operator) already recorded a credit decision for this booking/leg.
    // The backend signals this via `credit_decision_not_pending`. Treat it
    // as a benign already-recorded outcome: refresh the list so the row
    // re-renders with its current decision and show a passive confirmation
    // instead of a scary failure dialog.
    if (out.error == 'credit_decision_not_pending') {
      debugPrint(
        '[CREDIT_DECISION][ALREADY_RECORDED_REFRESH] booking=$bookingId '
        'leg=${item.legId.trim().isEmpty ? "-" : item.legId.trim()} '
        'attempted_decision=$creditDecision existing_decision=${item.creditDecision.trim().isEmpty ? "-" : item.creditDecision.trim()}',
      );
      await _loadBookings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Creditbeslissing is al geregistreerd.',
              en: 'Credit decision is already recorded.',
              fr: 'La décision de crédit est déjà enregistrée.',
              es: 'La decisión de crédito ya está registrada.',
            ),
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Creditbeslissing mislukt (${out.error}).',
            en: 'Credit decision failed (${out.error}).',
            fr: 'Décision de crédit échouée (${out.error}).',
            es: 'Decisión de crédito fallida (${out.error}).',
          ),
        ),
      ),
    );
  }

  Future<void> _confirmFullCredit(_CompanyBookingOverviewItem item) async {
    await _runCreditDecision(
      item,
      'full_credit',
      successMessage: _t(
        nl: 'Volledige credit geregistreerd.',
        en: 'Full credit recorded.',
        fr: 'Crédit complet enregistré.',
        es: 'Crédito total registrado.',
      ),
    );
  }

  Future<void> _confirmPartialCredit(_CompanyBookingOverviewItem item) async {
    final fullAmount = _creditDecisionFullAmount(item);
    if (fullAmount == null || fullAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Boekingsbedrag ontbreekt voor gedeeltelijke credit.',
              en: 'Booking amount missing for partial credit.',
              fr: 'Montant de réservation manquant pour crédit partiel.',
              es: 'Falta el importe de la reserva para crédito parcial.',
            ),
          ),
        ),
      );
      return;
    }
    final legScoped = _CompanyBookingOverviewItem.isRoundtripOperationalLegRow(
      item,
    );
    final legLabel = legScoped ? _companyLegLabel(item) : '';
    final controller = TextEditingController();
    final tokens = _themeTokensFor(businessThemeNotifier.value);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          _t(
            nl: 'Gedeeltelijke credit',
            en: 'Partial credit',
            fr: 'Crédit partiel',
            es: 'Crédito parcial',
          ),
          style: TextStyle(color: tokens.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              legScoped
                  ? _t(
                      nl: 'Maximaal ${_moneyLabelFromAmount(fullAmount, item.currency)} voor $legLabel. Voer een lager bedrag in.',
                      en: 'Maximum ${_moneyLabelFromAmount(fullAmount, item.currency)} for $legLabel. Enter a lower amount.',
                      fr: 'Maximum ${_moneyLabelFromAmount(fullAmount, item.currency)} pour $legLabel. Saisissez un montant inférieur.',
                      es: 'Máximo ${_moneyLabelFromAmount(fullAmount, item.currency)} para $legLabel. Introduce un importe menor.',
                    )
                  : _t(
                      nl: 'Maximaal ${_moneyLabelFromAmount(fullAmount, item.currency)}. Voer een lager bedrag in.',
                      en: 'Maximum ${_moneyLabelFromAmount(fullAmount, item.currency)}. Enter a lower amount.',
                      fr: 'Maximum ${_moneyLabelFromAmount(fullAmount, item.currency)}. Saisissez un montant inférieur.',
                      es: 'Máximo ${_moneyLabelFromAmount(fullAmount, item.currency)}. Introduce un importe menor.',
                    ),
              style: TextStyle(color: tokens.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 12),
            _buildPartialCreditAmountInputField(
              controller: controller,
              tokens: tokens,
              hintText: _moneyLabelFromAmount(fullAmount, item.currency),
              labelText: _t(
                nl: 'Creditbedrag',
                en: 'Credit amount',
                fr: 'Montant crédit',
                es: 'Importe crédito',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
              style: TextStyle(color: tokens.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _t(
                nl: 'Bevestigen',
                en: 'Confirm',
                fr: 'Confirmer',
                es: 'Confirmar',
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final parsed = num.tryParse(controller.text.trim().replaceAll(',', '.'));
    if (parsed == null) {
      debugPrint(
        '[CREDIT_DECISION][VALIDATION] booking=${_creditDecisionTargetBookingId(item)} '
        'leg=${item.legId.trim().isEmpty ? "-" : item.legId.trim()} result=invalid_parse',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Voer een geldig bedrag in.',
              en: 'Enter a valid amount.',
              fr: 'Saisissez un montant valide.',
              es: 'Introduce un importe válido.',
            ),
          ),
        ),
      );
      return;
    }
    if (parsed <= 0) {
      debugPrint(
        '[CREDIT_DECISION][VALIDATION] booking=${_creditDecisionTargetBookingId(item)} '
        'leg=${item.legId.trim().isEmpty ? "-" : item.legId.trim()} result=invalid_non_positive',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Voer een bedrag groter dan 0 in.',
              en: 'Enter an amount greater than 0.',
              fr: 'Saisissez un montant supérieur à 0.',
              es: 'Introduce un importe mayor que 0.',
            ),
          ),
        ),
      );
      return;
    }
    if (parsed >= fullAmount) {
      debugPrint(
        '[CREDIT_DECISION][VALIDATION] booking=${_creditDecisionTargetBookingId(item)} '
        'leg=${item.legId.trim().isEmpty ? "-" : item.legId.trim()} amount=$parsed max=$fullAmount result=use_full_credit',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Gebruik volledige terugbetaling voor het volledige bedrag.',
              en: 'Use full credit for the full amount.',
              fr: 'Utilisez le crédit complet pour le montant total.',
              es: 'Usa el crédito total para el importe completo.',
            ),
          ),
        ),
      );
      return;
    }
    final partialAmountCents = (parsed * 100).round();
    debugPrint(
      '[CREDIT_AMOUNT][${_CompanyBookingOverviewItem.isRoundtripOperationalLegRow(item) ? "LEG" : "PARENT"}] '
      'booking=${_creditDecisionTargetBookingId(item)} leg=${item.legId.trim().isEmpty ? "-" : item.legId.trim()} '
      'cents=$partialAmountCents',
    );
    await _runCreditDecision(
      item,
      'partial_credit',
      partialAmountCents: partialAmountCents,
      successMessage: _t(
        nl: 'Gedeeltelijke credit geregistreerd.',
        en: 'Partial credit recorded.',
        fr: 'Crédit partiel enregistré.',
        es: 'Crédito parcial registrado.',
      ),
    );
  }

  Future<void> _confirmNoRefund(_CompanyBookingOverviewItem item) async {
    final tokens = _themeTokensFor(businessThemeNotifier.value);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          _t(
            nl: 'Geen terugbetaling?',
            en: 'No refund?',
            fr: 'Pas de remboursement ?',
            es: '¿Sin reembolso?',
          ),
          style: TextStyle(color: tokens.textPrimary),
        ),
        content: Text(
          _t(
            nl: 'Deze betaalde geannuleerde rit wordt gemarkeerd als geen terugbetaling. Er wordt geen automatische Mollie-terugbetaling uitgevoerd.',
            en: 'This paid cancelled ride will be marked as no refund. No automatic Mollie refund will be executed.',
            fr: 'Ce trajet payé annulé sera marqué sans remboursement. Aucun remboursement Mollie automatique ne sera exécuté.',
            es: 'Este viaje pagado cancelado se marcará como sin reembolso. No se ejecutará ningún reembolso automático de Mollie.',
          ),
          style: TextStyle(color: tokens.textSecondary, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
              style: TextStyle(color: tokens.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _t(
                nl: 'Bevestigen',
                en: 'Confirm',
                fr: 'Confirmer',
                es: 'Confirmar',
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runCreditDecision(
      item,
      'no_refund',
      successMessage: _t(
        nl: 'Geen terugbetaling geregistreerd.',
        en: 'No refund recorded.',
        fr: 'Pas de remboursement enregistré.',
        es: 'Sin reembolso registrado.',
      ),
    );
  }

  Future<void> _confirmHandledManually(_CompanyBookingOverviewItem item) async {
    final tokens = _themeTokensFor(businessThemeNotifier.value);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          _t(
            nl: 'Handmatig afgehandeld?',
            en: 'Mark handled manually?',
            fr: 'Traité manuellement ?',
            es: '¿Marcar gestionado manualmente?',
          ),
          style: TextStyle(color: tokens.textPrimary),
        ),
        content: Text(
          _t(
            nl: 'De creditcase wordt gemarkeerd als handmatig afgehandeld buiten het systeem om.',
            en: 'The credit case will be marked as handled manually outside the system.',
            fr: 'Le dossier crédit sera marqué comme traité manuellement en dehors du système.',
            es: 'El caso de crédito se marcará como gestionado manualmente fuera del sistema.',
          ),
          style: TextStyle(color: tokens.textSecondary, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
              style: TextStyle(color: tokens.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _t(
                nl: 'Bevestigen',
                en: 'Confirm',
                fr: 'Confirmer',
                es: 'Confirmar',
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runCreditDecision(
      item,
      'handled_manually',
      successMessage: _t(
        nl: 'Handmatig afgehandeld geregistreerd.',
        en: 'Handled manually recorded.',
        fr: 'Traité manuellement enregistré.',
        es: 'Gestionado manualmente registrado.',
      ),
    );
  }

  bool _shouldShowAdminCancelPaidAction(_CompanyBookingOverviewItem item) {
    if (_filter != _CompanyBookingsFilter.open) return false;
    if (item.bucket != _CompanyBookingsFilter.open) return false;
    return _CompanyBookingOverviewItem.isPaidPaymentStatus(item.paymentStatus);
  }

  Future<({bool ok, String error})> _cancelPaidBookingAsAdminById(
    String bookingId, {
    String? legId,
    String? legType,
    String? parentBookingId,
    _AdminCancelPaidScope scope = _AdminCancelPaidScope.fullRoundtrip,
  }) async {
    final parentId = (parentBookingId ?? bookingId).trim();
    final id = parentId.isNotEmpty ? parentId : bookingId.trim();
    if (id.isEmpty) return (ok: false, error: 'missing_booking_id');
    final safeLegId = (legId ?? '').trim();
    final safeLegType = (legType ?? '').trim();
    final cancelSingleLeg =
        scope == _AdminCancelPaidScope.singleLeg && safeLegId.isNotEmpty;
    final scopeQuery = _activeBookingScopeQuery();
    final path = cancelSingleLeg
        ? '$kUpdateBookingStatusPath/${Uri.encodeComponent(id)}/legs/${Uri.encodeComponent(safeLegId)}/status'
        : '$kUpdateBookingStatusPath/${Uri.encodeComponent(id)}/status';
    final uri = _withActiveBookingScope(kBookingBaseUrl, path);
    final payload = <String, dynamic>{
      'booking_id': id,
      'parent_booking_id': id,
      'parentBookingId': id,
      'status': 'CANCELLED',
      'actor_role': 'admin',
      'actorRole': 'admin',
      if (cancelSingleLeg) ...<String, dynamic>{
        'leg_id': safeLegId,
        'legId': safeLegId,
        if (safeLegType.isNotEmpty) 'leg_type': safeLegType,
        if (safeLegType.isNotEmpty) 'legType': safeLegType,
        'cancel_scope': 'single_leg',
        'cancelScope': 'single_leg',
      } else ...<String, dynamic>{
        'cancel_scope': 'full_roundtrip',
        'cancelScope': 'full_roundtrip',
      },
      if (scopeQuery['tenant_id'] != null) 'tenant_id': scopeQuery['tenant_id'],
      if (scopeQuery['company_id'] != null)
        'company_id': scopeQuery['company_id'],
      if (scopeQuery['tenantId'] != null) 'tenantId': scopeQuery['tenantId'],
      if (scopeQuery['companyId'] != null) 'companyId': scopeQuery['companyId'],
    };
    debugPrint(
      '[ROUNDTRIP_CANCEL][${cancelSingleLeg ? "LEG_ONLY" : "FULL_PARENT"}] parent=$id '
      'leg=${cancelSingleLeg ? safeLegId : "-"} '
      'leg_type=${safeLegType.isEmpty ? "-" : safeLegType}',
    );
    try {
      final res = await http
          .post(
            uri,
            headers: await _companyOwnerHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));
      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        decoded = null;
      }
      if (decoded is! Map<String, dynamic>) {
        return (ok: false, error: 'invalid_payload');
      }
      if (res.statusCode != 200 || decoded['ok'] != true) {
        final err = (decoded['error'] ?? '').toString().trim();
        return (ok: false, error: err.isEmpty ? 'http_${res.statusCode}' : err);
      }
      return (ok: true, error: '');
    } catch (_) {
      return (ok: false, error: 'request_failed');
    }
  }

  /// Leg-row cancellation confirmation.
  ///
  /// Company overview is now leg-first: each row represents one operational
  /// leg. We therefore only confirm cancellation of the selected leg. Full
  /// roundtrip cancellation must be triggered from the parent booking detail
  /// surface, not from a row action, so we no longer offer that option here.
  Future<bool> _showLegCancelPaidDialog(
    _CompanyBookingOverviewItem item,
    _CompanyBookingsThemeTokens tokens,
  ) async {
    debugPrint(
      '[COMPANY_LEG_CANCEL][DIALOG] parent=${item.parentBookingId.trim().isNotEmpty ? item.parentBookingId.trim() : item.bookingId.trim()} '
      'leg=${item.legId.trim().isEmpty ? "-" : item.legId.trim()} '
      'leg_type=${item.legType.trim().isEmpty ? "-" : item.legType.trim()} '
      'mode=leg_only',
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          _t(
            nl: 'Deze rit annuleren?',
            en: 'Cancel this ride?',
            fr: 'Annuler ce trajet ?',
            es: '¿Cancelar este viaje?',
          ),
          style: TextStyle(color: tokens.textPrimary),
        ),
        content: Text(
          _t(
            nl: 'Alleen deze rit wordt geannuleerd. De andere rit blijft ongewijzigd.',
            en: 'Only this ride will be cancelled. The other ride remains unchanged.',
            fr: 'Seul ce trajet sera annulé. L’autre trajet reste inchangé.',
            es: 'Solo se cancelará este viaje. El otro viaje permanece sin cambios.',
          ),
          style: TextStyle(color: tokens.textSecondary, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t(
                nl: 'Behouden',
                en: 'Keep booking',
                fr: 'Conserver la réservation',
                es: 'Mantener reserva',
              ),
              style: TextStyle(color: tokens.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: tokens.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _t(
                nl: 'Rit annuleren',
                en: 'Cancel ride',
                fr: 'Annuler le trajet',
                es: 'Cancelar viaje',
              ),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _cancelPaidBookingAsAdmin(
    _CompanyBookingOverviewItem item,
  ) async {
    if (_bulkArchiving) return;
    final bookingId = item.bookingId.trim();
    final busyKey = _cancelBusyKey(item);
    if (bookingId.isEmpty || _isCancellingBooking(busyKey)) return;
    final tokens = _themeTokensFor(businessThemeNotifier.value);
    final isRoundtripLeg = _isRoundtripLegCancelEligible(item);
    if (isRoundtripLeg) {
      final confirmed = await _showLegCancelPaidDialog(item, tokens);
      if (!confirmed || !mounted) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: tokens.palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            _t(
              nl: 'Betaalde rit annuleren?',
              en: 'Cancel paid ride?',
              fr: 'Annuler le trajet payé ?',
              es: '¿Cancelar viaje pagado?',
            ),
            style: TextStyle(color: tokens.textPrimary),
          ),
          content: Text(
            _t(
              nl: 'De rit wordt geannuleerd en verdwijnt uit planning en chauffeursweergave. De boeking komt in Geannuleerd en Te crediteren. Er wordt nog geen automatische terugbetaling uitgevoerd.',
              en: 'The ride will be cancelled and removed from planning and the driver view. The booking will appear in Cancelled and To credit. No automatic refund will be executed yet.',
              fr: 'Le trajet sera annulé et retiré de la planification et de la vue chauffeur. La réservation apparaîtra dans Annulées et À créditer. Aucun remboursement automatique ne sera exécuté pour l’instant.',
              es: 'El viaje se cancelará y desaparecerá de la planificación y de la vista del conductor. La reserva aparecerá en Canceladas y Por abonar. Aún no se ejecutará ningún reembolso automático.',
            ),
            style: TextStyle(color: tokens.textSecondary, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                _t(
                  nl: 'Annuleren',
                  en: 'Cancel',
                  fr: 'Annuler',
                  es: 'Cancelar',
                ),
                style: TextStyle(color: tokens.textSecondary),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: tokens.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                _t(
                  nl: 'Annuleer betaalde rit',
                  en: 'Cancel paid ride',
                  fr: 'Annuler le trajet payé',
                  es: 'Cancelar viaje pagado',
                ),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final cancelScope = isRoundtripLeg
        ? _AdminCancelPaidScope.singleLeg
        : _AdminCancelPaidScope.fullRoundtrip;
    debugPrint(
      '[COMPANY_LEG_CANCEL][TARGET] parent=${item.parentBookingId.trim().isNotEmpty ? item.parentBookingId.trim() : bookingId} '
      'leg=${item.legId.trim().isEmpty ? "-" : item.legId.trim()} '
      'leg_type=${item.legType.trim().isEmpty ? "-" : item.legType.trim()} '
      'scope=${cancelScope == _AdminCancelPaidScope.singleLeg ? "single_leg" : "full_parent"}',
    );
    setState(() {
      _cancellingBookingIds.add(busyKey);
    });
    final cancelOut = await _cancelPaidBookingAsAdminById(
      bookingId,
      legId: item.legId,
      legType: item.legType,
      parentBookingId: item.parentBookingId,
      scope: cancelScope,
    );
    if (!mounted) return;
    setState(() {
      _cancellingBookingIds.remove(busyKey);
    });
    if (cancelOut.ok) {
      await _loadBookings();
      if (!mounted) return;
      final successMessage = cancelScope == _AdminCancelPaidScope.singleLeg
          ? _t(
              nl: 'Deze rit is geannuleerd. De andere rit blijft gepland.',
              en: 'This leg was cancelled. The other leg remains scheduled.',
              fr: 'Ce trajet a été annulé. L’autre trajet reste planifié.',
              es: 'Este tramo se canceló. El otro tramo sigue programado.',
            )
          : _t(
              nl: 'Betaalde rit geannuleerd. De boeking staat nu in Geannuleerd en Te crediteren.',
              en: 'Paid ride cancelled. The booking is now in Cancelled and To credit.',
              fr: 'Trajet payé annulé. La réservation figure maintenant dans Annulées et À créditer.',
              es: 'Viaje pagado cancelado. La reserva está ahora en Canceladas y Por abonar.',
            );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Annuleren mislukt. Probeer opnieuw.',
            en: 'Cancellation failed. Please try again.',
            fr: 'Échec de l’annulation. Réessayez.',
            es: 'No se pudo cancelar. Vuelve a intentarlo.',
          ),
        ),
      ),
    );
  }

  // SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1 (Phase C): _adminHeaders removed;
  // company-owner surfaces now authenticate exclusively via the company
  // session bearer through _companyOwnerHeaders.

  Future<Map<String, String>> _companyOwnerHeaders() async {
    final auth = await resolveCompanyOwnerAuthHeaders();
    return auth.headers;
  }

  bool _isArchivingBooking(String bookingId) {
    return _archivingBookingIds.contains(bookingId);
  }

  Future<({bool ok, String error})> _hideBookingFromCompanyOverviewById(
    String bookingId,
  ) async {
    final id = bookingId.trim();
    if (id.isEmpty) return (ok: false, error: 'missing_booking_id');
    final scopeQuery = _activeBookingScopeQuery();
    final uri = _withActiveBookingScope(
      kBookingBaseUrl,
      '$kListBookingsPath/${Uri.encodeComponent(id)}/company-hide',
    );
    final payload = <String, dynamic>{
      'booking_id': id,
      'reason': 'company_admin_list_cleanup',
      if (scopeQuery['tenant_id'] != null) 'tenant_id': scopeQuery['tenant_id'],
      if (scopeQuery['company_id'] != null)
        'company_id': scopeQuery['company_id'],
      if (scopeQuery['tenantId'] != null) 'tenantId': scopeQuery['tenantId'],
      if (scopeQuery['companyId'] != null) 'companyId': scopeQuery['companyId'],
    };
    try {
      final res = await http
          .post(
            uri,
            headers: await _companyOwnerHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));
      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        decoded = null;
      }
      if (decoded is! Map<String, dynamic>) {
        return (ok: false, error: 'invalid_payload');
      }
      if (res.statusCode != 200) {
        final err = (decoded['error'] ?? '').toString().trim();
        return (ok: false, error: err.isEmpty ? 'http_${res.statusCode}' : err);
      }
      return (ok: decoded['ok'] == true, error: '');
    } catch (_) {
      return (ok: false, error: 'request_failed');
    }
  }

  Future<void> _hideSingleBooking(_CompanyBookingOverviewItem item) async {
    if (_bulkArchiving) return;
    final bookingId = item.bookingId.trim();
    if (bookingId.isEmpty) return;
    final tokens = _themeTokensFor(businessThemeNotifier.value);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          _t(
            nl: 'Boeking verbergen?',
            en: 'Hide booking?',
            fr: 'Masquer la réservation ?',
            es: '¿Ocultar reserva?',
          ),
          style: TextStyle(color: tokens.textPrimary),
        ),
        content: Text(
          _t(
            nl: 'Deze boeking wordt alleen uit dit bedrijfsboekingenoverzicht verborgen. Facturen, betalingen, klantgeschiedenis en auditgegevens blijven bewaard.',
            en: 'This booking will be hidden only from this company bookings overview. Invoices, payments, customer history and audit data remain preserved.',
            fr: 'Cette réservation sera masquée uniquement de cet aperçu des réservations de l’entreprise. Les factures, paiements, l’historique client et les données d’audit restent conservés.',
            es: 'Esta reserva se ocultará solo de esta vista de reservas de la empresa. Las facturas, pagos, historial del cliente y datos de auditoría se conservan.',
          ),
          style: TextStyle(color: tokens.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
              style: TextStyle(color: tokens.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: tokens.accent,
              foregroundColor: tokens.palette.isDark
                  ? const Color(0xFF0B0B0B)
                  : Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _t(nl: 'Verberg', en: 'Hide', fr: 'Masquer', es: 'Ocultar'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _archivingBookingIds.add(bookingId);
    });
    final hideOut = await _hideBookingFromCompanyOverviewById(bookingId);
    final ok = hideOut.ok;
    if (!mounted) return;
    setState(() {
      _archivingBookingIds.remove(bookingId);
      if (ok) {
        _all = _all
            .where((entry) => entry.bookingId.trim() != bookingId)
            .toList(growable: false);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? _t(
                  nl: 'Boeking verborgen.',
                  en: 'Booking hidden.',
                  fr: 'Réservation masquée.',
                  es: 'Reserva ocultada.',
                )
              : _t(
                  nl: hideOut.error == 'active_booking_cannot_be_hidden'
                      ? 'Actieve boekingen kun je niet verbergen. Annuleer ze later via de annuleeractie.'
                      : 'Verbergen mislukt. Probeer opnieuw.',
                  en: hideOut.error == 'active_booking_cannot_be_hidden'
                      ? 'Active bookings cannot be hidden. Cancel them later using the cancel action.'
                      : 'Hide failed. Please try again.',
                  fr: hideOut.error == 'active_booking_cannot_be_hidden'
                      ? 'Les réservations actives ne peuvent pas être masquées. Annulez-les ensuite via l’action d’annulation.'
                      : 'Échec du masquage. Réessayez.',
                  es: hideOut.error == 'active_booking_cannot_be_hidden'
                      ? 'Las reservas activas no se pueden ocultar. Cáncelalas después usando la acción de cancelación.'
                      : 'No se pudo ocultar. Inténtalo de nuevo.',
                ),
        ),
      ),
    );
  }

  Future<void> _hideAllVisiblePageBookings() async {
    if (_bulkArchiving || _filter == _CompanyBookingsFilter.open) return;
    final visibleItems = _filteredItems;
    if (visibleItems.isEmpty) return;
    final count = visibleItems.length;
    final tokens = _themeTokensFor(businessThemeNotifier.value);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          _t(
            nl: 'Zichtbare boekingen verbergen?',
            en: 'Hide visible bookings?',
            fr: 'Masquer les réservations visibles ?',
            es: '¿Ocultar reservas visibles?',
          ),
          style: TextStyle(color: tokens.textPrimary),
        ),
        content: Text(
          _t(
            nl: 'Je verbergt $count boekingen uit deze lijst. Facturen, betalingen, klantgeschiedenis en auditgegevens blijven bewaard.',
            en: 'You are hiding $count bookings from this list. Invoices, payments, customer history and audit data remain preserved.',
            fr: 'Vous masquez $count réservations de cette liste. Les factures, paiements, l’historique client et les données d’audit restent conservés.',
            es: 'Ocultarás $count reservas de esta lista. Las facturas, pagos, historial del cliente y datos de auditoría se conservan.',
          ),
          style: TextStyle(color: tokens.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
              style: TextStyle(color: tokens.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: tokens.accent,
              foregroundColor: tokens.palette.isDark
                  ? const Color(0xFF0B0B0B)
                  : Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _t(
                nl: 'Verberg alles',
                en: 'Hide all',
                fr: 'Tout masquer',
                es: 'Ocultar todo',
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _bulkArchiving = true;
    });
    var success = 0;
    var failed = 0;
    final successfulIds = <String>{};
    for (final item in visibleItems) {
      final bookingId = item.bookingId.trim();
      if (bookingId.isEmpty) {
        failed += 1;
        continue;
      }
      final hideOut = await _hideBookingFromCompanyOverviewById(bookingId);
      if (hideOut.ok) {
        success += 1;
        successfulIds.add(bookingId);
      } else {
        failed += 1;
      }
    }
    if (!mounted) return;
    setState(() {
      _bulkArchiving = false;
      if (successfulIds.isNotEmpty) {
        _all = _all
            .where((entry) => !successfulIds.contains(entry.bookingId.trim()))
            .toList(growable: false);
      }
    });
    final message = failed == 0
        ? _t(
            nl: '$success boekingen verborgen.',
            en: '$success bookings hidden.',
            fr: '$success réservations masquées.',
            es: '$success reservas ocultadas.',
          )
        : _t(
            nl: '$success verborgen, $failed mislukt.',
            en: '$success hidden, $failed failed.',
            fr: '$success masquées, $failed échecs.',
            es: '$success ocultadas, $failed fallaron.',
          );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void initState() {
    super.initState();
    unawaited(_refreshCreditAuthState());
    unawaited(_loadBookings());
  }

  Future<void> _loadBookings() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _errorCode = null;
    });
    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        kListBookingsPath,
        extraQuery: <String, String>{
          'limit': '200',
          'include_history': '1',
          't': '${DateTime.now().millisecondsSinceEpoch}',
        },
      );
      final res = await http
          .get(uri, headers: await _companyOwnerHeaders())
          .timeout(const Duration(seconds: 12));
      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        decoded = null;
      }

      if (res.statusCode != 200) {
        final apiError = (decoded is Map<String, dynamic>)
            ? (decoded['error']?.toString().trim() ?? '')
            : '';
        if (apiError.isNotEmpty) {
          throw _CompanyBookingsLoadException(apiError);
        }
        throw _CompanyBookingsLoadException('http_${res.statusCode}');
      }
      if (decoded is! Map<String, dynamic>) {
        throw _CompanyBookingsLoadException('invalid_payload');
      }
      if (decoded['ok'] != true) {
        final apiError = (decoded['error']?.toString().trim() ?? '').isNotEmpty
            ? decoded['error'].toString().trim()
            : 'bookings_not_ok';
        throw _CompanyBookingsLoadException(apiError);
      }
      final scopeQuery = _activeBookingScopeQuery();
      final overlayTrips = await _fetchTrackingOverlayTrips(
        scopeQuery: scopeQuery,
        diagTag: 'COMPANY_BOOKINGS',
        limit: 200,
      );
      final overlayMatcher = _TrackingPaymentOverlayMatcher(overlayTrips);
      final rawItems = (decoded['items'] is List)
          ? (decoded['items'] as List)
          : const <dynamic>[];
      var overlayMatched = 0;
      var overlayPaid = 0;
      final mappedItems = rawItems
          .whereType<Map>()
          .map((entry) => entry.cast<String, dynamic>())
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(growable: false);
      for (final entry in mappedItems) {
        final probe = _CompanyBookingOverviewItem.fromMap(entry);
        if (!probe.isOperationalLeg) continue;
        final matches = overlayMatcher.matchOperationalLeg(
          bookingId: probe.bookingId,
          parentBookingId: probe.parentBookingId,
          legId: probe.legId,
          legType: probe.legType,
        );
        if (matches.isEmpty) continue;
        overlayMatched += 1;
        final anyPaid = matches.any((trip) => trip.isPaid);
        final overlayStatuses = matches
            .map(
              (trip) => trip.paymentStatus.trim().isEmpty
                  ? '-'
                  : trip.paymentStatus.trim(),
            )
            .join('|');
        debugPrint(
          '[PAYMENT_OVERLAY][STATUS] booking=${probe.referenceText.trim().isNotEmpty ? probe.referenceText.trim() : probe.bookingId} '
          'parent=${probe.parentReferenceText.trim().isNotEmpty ? probe.parentReferenceText.trim() : probe.parentBookingId} '
          'leg=${probe.legType.isEmpty ? "-" : probe.legType} raw_status=$overlayStatuses isPaid=$anyPaid',
        );
        if (anyPaid) {
          overlayPaid += 1;
          entry['payment_status'] = 'paid';
          entry['paymentStatus'] = 'paid';
        } else {
          entry['payment_status'] = 'unpaid';
          entry['paymentStatus'] = 'unpaid';
        }
      }
      debugPrint(
        '[COMPANY_BOOKINGS][PAYMENT_OVERLAY] totalTrips=${overlayMatcher.totalTrips} matched=$overlayMatched paid=$overlayPaid',
      );
      final parsed = sortCompanyBookingsNewestCreatedFirst(
        mappedItems
            .map((entry) => _CompanyBookingOverviewItem.fromMap(entry))
            .where((entry) => entry.bookingId.trim().isNotEmpty),
        (item) => CompanyBookingCreatedSortFields(
          bookingId: item.bookingId,
          createdAtIso: item.createdAtIso,
          legId: item.legId,
        ),
      );
      final roundtripLegRows = parsed.where((item) => item.isOperationalLeg);
      final roundtripOpenLegs = roundtripLegRows
          .where((item) => item.bucket == _CompanyBookingsFilter.open)
          .length;
      final roundtripCancelledLegs = roundtripLegRows
          .where((item) => item.bucket == _CompanyBookingsFilter.cancelled)
          .length;
      debugPrint(
        '[ROUNDTRIP_LEG_UI][COMPANY_FILTER] total=${parsed.length} operational_legs=${roundtripLegRows.length} open_legs=$roundtripOpenLegs cancelled_legs=$roundtripCancelledLegs',
      );
      for (final item in roundtripLegRows) {
        if (item.bucket == _CompanyBookingsFilter.open) {
          debugPrint(
            '[ROUNDTRIP_LEG_UI][ACTIVE_LEG_VISIBLE] parent=${_safeRefPreview(item.parentBookingId)} leg=${_safeRefPreview(item.legId)} type=${item.legType.isEmpty ? "-" : item.legType} status=${item.statusText}',
          );
        }
      }
      for (final item in parsed) {
        if (item.bucket != _CompanyBookingsFilter.cancelled) continue;
        if (_CompanyBookingOverviewItem.shouldShowMollieRefundStatus(item)) {
          _CompanyBookingOverviewItem.logRefundStateDiagnostic(item);
        }
        if (_CompanyBookingOverviewItem.isPaidPaymentStatus(
          item.paymentStatus,
        )) {
          _CompanyBookingOverviewItem.logRefundBucketStateDiagnostic(item);
        }
        _CompanyBookingOverviewItem.logRefundQueueDiagnostic(item);
        if (!item.isPendingCredit &&
            _CompanyBookingOverviewItem.isPaidPaymentStatus(
              item.paymentStatus,
            )) {
          debugPrint(
            '[COMPANY_BOOKINGS][TO_CREDIT_MISSING_FIELDS] booking=${item.referenceText.trim().isNotEmpty ? item.referenceText.trim() : item.bookingId} paid=true cancelled=true refund_required=${item.refundRequired}',
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _all = parsed;
        _loading = false;
      });
      unawaited(_refreshCreditAuthState());
    } on _CompanyBookingsLoadException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorCode = e.code;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorCode = 'load_failed';
        _loading = false;
      });
    }
  }

  String _friendlyError(String? code) {
    switch ((code ?? '').trim()) {
      case 'company_bookings_list_index_unavailable':
        return _t(
          nl: 'Boekingenoverzicht is tijdelijk niet beschikbaar. Index wordt voorbereid. Probeer straks opnieuw.',
          en: 'Bookings overview is temporarily unavailable. Index is being prepared. Please try again soon.',
          fr: 'L’aperçu des réservations est temporairement indisponible. L’index est en préparation. Réessayez bientôt.',
          es: 'La vista de reservas no está disponible temporalmente. El índice se está preparando. Inténtalo de nuevo pronto.',
        );
      case 'company_bookings_list_index_stale':
        return _t(
          nl: 'Boekingenoverzicht wordt vernieuwd. Probeer binnen enkele ogenblikken opnieuw.',
          en: 'Bookings overview is being refreshed. Please try again shortly.',
          fr: 'L’aperçu des réservations est en cours d’actualisation. Réessayez dans un instant.',
          es: 'La vista de reservas se está actualizando. Vuelve a intentarlo en breve.',
        );
      default:
        return _t(
          nl: 'Boekingen laden is mislukt. Controleer je verbinding en probeer opnieuw.',
          en: 'Failed to load bookings. Check your connection and try again.',
          fr: 'Le chargement des réservations a échoué. Vérifiez votre connexion et réessayez.',
          es: 'Error al cargar reservas. Revisa tu conexión y vuelve a intentarlo.',
        );
    }
  }

  List<_CompanyBookingOverviewItem> get _filteredItems {
    switch (_filter) {
      case _CompanyBookingsFilter.open:
        return _all
            .where((item) => item.bucket == _CompanyBookingsFilter.open)
            .toList(growable: false);
      case _CompanyBookingsFilter.completed:
        return _all
            .where((item) => item.bucket == _CompanyBookingsFilter.completed)
            .toList(growable: false);
      case _CompanyBookingsFilter.cancelled:
        return _all
            .where(_CompanyBookingOverviewItem.isCancelledBucketVisible)
            .toList(growable: false);
      case _CompanyBookingsFilter.toCredit:
        return _all
            .where(_CompanyBookingOverviewItem.isToCreditBucketVisible)
            .toList(growable: false);
      case _CompanyBookingsFilter.refundPending:
        return _all
            .where(_CompanyBookingOverviewItem.isRefundLifecyclePending)
            .toList(growable: false);
      case _CompanyBookingsFilter.refunded:
        return _all
            .where(_CompanyBookingOverviewItem.isRefundLifecycleRefunded)
            .toList(growable: false);
      case _CompanyBookingsFilter.refundFailed:
        return _all
            .where(_CompanyBookingOverviewItem.isRefundLifecycleFailed)
            .toList(growable: false);
    }
  }

  String _countText(_CompanyBookingsFilter filter) {
    switch (filter) {
      case _CompanyBookingsFilter.cancelled:
        return _all
            .where(_CompanyBookingOverviewItem.isCancelledBucketVisible)
            .length
            .toString();
      case _CompanyBookingsFilter.toCredit:
        return _all
            .where(_CompanyBookingOverviewItem.isToCreditBucketVisible)
            .length
            .toString();
      case _CompanyBookingsFilter.refundPending:
        return _all
            .where(_CompanyBookingOverviewItem.isRefundLifecyclePending)
            .length
            .toString();
      case _CompanyBookingsFilter.refunded:
        return _all
            .where(_CompanyBookingOverviewItem.isRefundLifecycleRefunded)
            .length
            .toString();
      case _CompanyBookingsFilter.refundFailed:
        return _all
            .where(_CompanyBookingOverviewItem.isRefundLifecycleFailed)
            .length
            .toString();
      default:
        return _all.where((item) => item.bucket == filter).length.toString();
    }
  }

  String _formatPickup(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '—';
    final dt = DateTime.tryParse(text);
    if (dt == null) return text;
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  bool _looksLikeUuid(String value) {
    final text = value.trim();
    if (text.length < 24) return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}$',
    ).hasMatch(text);
  }

  String _shortBookingReference(_CompanyBookingOverviewItem item) {
    final preferred = item.referenceText.trim();
    if (preferred.isNotEmpty && !_looksLikeUuid(preferred)) return preferred;
    final bookingId = item.bookingId.trim();
    if (bookingId.isEmpty) return '—';
    final suffix = bookingId.length <= 5
        ? bookingId
        : bookingId.substring(bookingId.length - 5);
    return '…$suffix';
  }

  String _localizedBookingStatus(String raw) {
    final normalized = raw.trim().toUpperCase();
    if (normalized.isEmpty) return '—';
    if (normalized == 'PENDING') {
      return _t(
        nl: 'In afwachting',
        en: 'Pending',
        fr: 'En attente',
        es: 'Pendiente',
      );
    }
    // STREET-RIDE-DURABLE-COMPLETION-2: a live street/direct ride projects as
    // ACTIVE (not generic PENDING) so it reads as an active ride, not "pending".
    if (normalized == 'ACTIVE' || normalized == 'IN_PROGRESS') {
      return _t(
        nl: 'Rit actief',
        en: 'Ride active',
        fr: 'Course active',
        es: 'Viaje activo',
      );
    }
    if (normalized == 'COMPLETED' ||
        normalized == 'DONE' ||
        normalized == 'FINISHED') {
      return _t(
        nl: 'Afgerond',
        en: 'Completed',
        fr: 'Terminée',
        es: 'Finalizada',
      );
    }
    if (normalized == 'CANCELLED' ||
        normalized == 'CANCELED' ||
        normalized == 'DELETED') {
      return _t(
        nl: 'Geannuleerd',
        en: 'Cancelled',
        fr: 'Annulée',
        es: 'Cancelada',
      );
    }
    if (normalized == 'CONFIRMED') {
      return _t(
        nl: 'Bevestigd',
        en: 'Confirmed',
        fr: 'Confirmée',
        es: 'Confirmada',
      );
    }
    return normalized.replaceAll('_', ' ');
  }

  String _localizedPaymentStatus(String raw) {
    final normalized = raw.trim().toUpperCase();
    if (normalized.isEmpty)
      return _t(
        nl: 'Onbekend',
        en: 'Unknown',
        fr: 'Inconnu',
        es: 'Desconocido',
      );
    if (normalized == 'PAID' ||
        normalized == 'SUCCESS' ||
        normalized == 'CONFIRMED') {
      return _t(nl: 'Betaald', en: 'Paid', fr: 'Payé', es: 'Pagado');
    }
    if (normalized == 'UNPAID' ||
        normalized == 'PENDING' ||
        normalized == 'PAY_IN_CAR' ||
        normalized == 'OPEN') {
      return _t(nl: 'Onbetaald', en: 'Unpaid', fr: 'Non payé', es: 'No pagado');
    }
    return normalized.replaceAll('_', ' ');
  }

  String _localizedCreditStatus(String raw) {
    final normalized = raw.trim().toUpperCase();
    if (normalized.isEmpty || normalized == 'PENDING_CREDIT') {
      return _t(
        nl: 'In afwachting',
        en: 'Pending',
        fr: 'En attente',
        es: 'Pendiente',
      );
    }
    if (normalized == 'CREDITED') {
      return _t(
        nl: 'Gecrediteerd',
        en: 'Credited',
        fr: 'Crédité',
        es: 'Acreditado',
      );
    }
    if (normalized == 'PARTIAL_CREDIT') {
      return _t(
        nl: 'Gedeeltelijke credit',
        en: 'Partial credit',
        fr: 'Crédit partiel',
        es: 'Crédito parcial',
      );
    }
    if (normalized == 'NO_REFUND') {
      return _t(
        nl: 'Geen terugbetaling',
        en: 'No refund',
        fr: 'Pas de remboursement',
        es: 'Sin reembolso',
      );
    }
    if (normalized == 'HANDLED_MANUALLY') {
      return _t(
        nl: 'Handmatig afgehandeld',
        en: 'Handled manually',
        fr: 'Traité manuellement',
        es: 'Gestionado manualmente',
      );
    }
    return normalized.replaceAll('_', ' ');
  }

  String _localizedCreditDecisionRecordedChip(
    _CompanyBookingOverviewItem item,
  ) {
    final amountLabel = item.creditedAmountCents != null
        ? _moneyLabelFromAmount(item.creditedAmountCents! / 100, item.currency)
        : '';
    switch (item.creditDecision.trim().toUpperCase()) {
      case 'FULL_CREDIT':
        final base = _t(
          nl: 'Volledige credit geregistreerd',
          en: 'Full credit recorded',
          fr: 'Crédit complet enregistré',
          es: 'Crédito total registrado',
        );
        return amountLabel.isNotEmpty ? '$base · $amountLabel' : base;
      case 'PARTIAL_CREDIT':
        final base = _t(
          nl: 'Gedeeltelijke credit geregistreerd',
          en: 'Partial credit recorded',
          fr: 'Crédit partiel enregistré',
          es: 'Crédito parcial registrado',
        );
        return amountLabel.isNotEmpty ? '$base · $amountLabel' : base;
      case 'NO_REFUND':
        return _t(
          nl: 'Geen terugbetaling',
          en: 'No refund',
          fr: 'Pas de remboursement',
          es: 'Sin reembolso',
        );
      case 'HANDLED_MANUALLY':
        return _t(
          nl: 'Handmatig afgehandeld',
          en: 'Handled manually',
          fr: 'Traité manuellement',
          es: 'Gestionado manualmente',
        );
      default:
        return _localizedCreditDecision(item.creditDecision);
    }
  }

  String _localizedCreditDecision(String raw) {
    switch (raw.trim().toUpperCase()) {
      case 'FULL_CREDIT':
        return _t(
          nl: 'Volledige credit',
          en: 'Full credit',
          fr: 'Crédit complet',
          es: 'Crédito total',
        );
      case 'PARTIAL_CREDIT':
        return _t(
          nl: 'Gedeeltelijke credit',
          en: 'Partial credit',
          fr: 'Crédit partiel',
          es: 'Crédito parcial',
        );
      case 'NO_REFUND':
        return _t(
          nl: 'Geen terugbetaling',
          en: 'No refund',
          fr: 'Pas de remboursement',
          es: 'Sin reembolso',
        );
      case 'HANDLED_MANUALLY':
        return _t(
          nl: 'Handmatig afgehandeld',
          en: 'Handled manually',
          fr: 'Traité manuellement',
          es: 'Gestionado manualmente',
        );
      default:
        return raw.trim().isEmpty ? '—' : raw.replaceAll('_', ' ');
    }
  }

  Color _statusColor(
    _CompanyBookingOverviewItem item,
    _CompanyBookingsThemeTokens tokens,
  ) {
    switch (item.bucket) {
      case _CompanyBookingsFilter.completed:
        return tokens.palette.success;
      case _CompanyBookingsFilter.cancelled:
        return tokens.danger;
      case _CompanyBookingsFilter.toCredit:
        return tokens.warningText;
      case _CompanyBookingsFilter.refundPending:
        return tokens.warningText;
      case _CompanyBookingsFilter.refunded:
        return tokens.palette.success;
      case _CompanyBookingsFilter.refundFailed:
        return tokens.danger;
      case _CompanyBookingsFilter.open:
        if (item.statusText.trim().toUpperCase() == 'CONFIRMED') {
          return tokens.palette.success;
        }
        return tokens.accent;
    }
  }

  String _moneyLabelFromAmount(num? amount, String rawCurrency) {
    if (amount == null) return '';
    final currency = rawCurrency.trim().toUpperCase();
    final symbol = currency.isEmpty || currency == 'EUR' ? '€' : '$currency ';
    final value = amount.toStringAsFixed(2).replaceAll('.', ',');
    return '$symbol$value';
  }

  String _moneyLabel(_CompanyBookingOverviewItem item) {
    return _moneyLabelFromAmount(item.amount, item.currency);
  }

  Widget _buildPartialCreditAmountInputField({
    required TextEditingController controller,
    required _CompanyBookingsThemeTokens tokens,
    required String hintText,
    required String labelText,
  }) {
    final variant = businessThemeNotifier.value;
    final isClean = variant == BusinessThemeVariant.cleanProfessional;
    final inputTextColor = isClean
        ? const Color(0xFF1C2430)
        : tokens.textPrimary;
    final inputLabelColor = isClean
        ? const Color(0xFF2D3A4C)
        : tokens.textSecondary;
    final inputHintColor = isClean
        ? const Color(0xFF5F6B7A)
        : tokens.textTertiary;
    final inputFillColor = isClean
        ? const Color(0xFFFFFFFF)
        : tokens.palette.surfaceAlt;
    final inputBorderColor = isClean
        ? const Color(0xFFB7C4D3)
        : tokens.cardBorder;
    final inputFocusColor = isClean ? const Color(0xFF3B82F6) : tokens.accent;
    debugPrint(
      '[REFUND_INPUT_THEME][CONTRAST] variant=${variant.name} is_clean=$isClean '
      'text=0x${inputTextColor.value.toRadixString(16)} '
      'fill=0x${inputFillColor.value.toRadixString(16)} '
      'border=0x${inputBorderColor.value.toRadixString(16)}',
    );
    return Theme(
      data: Theme.of(context).copyWith(
        brightness: tokens.palette.isDark ? Brightness.dark : Brightness.light,
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: inputFocusColor,
          selectionColor: inputFocusColor.withOpacity(0.28),
          selectionHandleColor: inputFocusColor,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: inputFillColor,
        ),
      ),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: TextStyle(
          color: inputTextColor,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        cursorColor: inputFocusColor,
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: TextStyle(color: inputLabelColor),
          hintText: hintText,
          hintStyle: TextStyle(color: inputHintColor),
          filled: true,
          fillColor: inputFillColor,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: inputBorderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: inputFocusColor, width: 1.4),
          ),
        ),
      ),
    );
  }

  String _companyLegLabel(_CompanyBookingOverviewItem item) {
    final type = item.legType.trim().toLowerCase();
    if (type == 'return') {
      return _t(
        nl: 'Terugrit',
        en: 'Return leg',
        fr: 'Trajet retour',
        es: 'Tramo de vuelta',
      );
    }
    if (type == 'outbound') {
      return _t(
        nl: 'Heenrit',
        en: 'Outbound leg',
        fr: 'Trajet aller',
        es: 'Tramo de ida',
      );
    }
    return _t(nl: 'Rit', en: 'Ride leg', fr: 'Trajet', es: 'Tramo');
  }

  Widget _buildCompanyBookingPremiumCard(
    _CompanyBookingOverviewItem item,
    _CompanyBookingsThemeTokens tokens,
  ) {
    final isToCredit = item.isPendingCredit;
    final showCreditDecisionActions =
        _CompanyBookingOverviewItem.canShowCreditDecisionActions(item);
    final legScopedCredit =
        _CompanyBookingOverviewItem.isRoundtripOperationalLegRow(item);
    final creditDecisionRecordedChip =
        _CompanyBookingOverviewItem.hasCreditDecisionRecorded(item)
        ? _localizedCreditDecisionRecordedChip(item)
        : '';
    final fullCreditButtonLabel = legScopedCredit && item.amount != null
        ? _t(
            nl: 'Volledige credit (${_moneyLabelFromAmount(item.amount, item.currency)})',
            en: 'Full credit (${_moneyLabelFromAmount(item.amount, item.currency)})',
            fr: 'Crédit complet (${_moneyLabelFromAmount(item.amount, item.currency)})',
            es: 'Crédito total (${_moneyLabelFromAmount(item.amount, item.currency)})',
          )
        : _t(
            nl: 'Volledige credit',
            en: 'Full credit',
            fr: 'Crédit complet',
            es: 'Crédito total',
          );
    final showCreditDecisionBadge = creditDecisionRecordedChip.isNotEmpty;
    final creditTargetId = _creditDecisionTargetBookingId(item);
    final creditBusyKey = _creditDecisionBusyKey(item);
    final creditBusy = _isDecidingCredit(creditBusyKey);
    final creditActionsEnabled =
        _canApplyCreditDecisions() &&
        !creditBusy &&
        _CompanyBookingOverviewItem.canExecuteCompanyBookingMoneyAction(item);
    final showMollieRefundStatus = _shouldShowMollieRefundStatus(item);
    final showMollieRefundAction = _canShowMollieRefundAction(item);
    final showMollieRefundStatusRefresh =
        !showMollieRefundAction &&
        _canShowMollieRefundStatusRefreshAction(item);
    final showMollieRefundAuditResync =
        !showMollieRefundAction &&
        !showMollieRefundStatusRefresh &&
        _canShowMollieRefundAuditResyncAction(item);
    final showCreditNotePdfAction =
        _CompanyBookingOverviewItem.canShowCreditNotePdfAction(item);
    final showRefundProofPdfAction =
        _CompanyBookingOverviewItem.canShowRefundProofPdfAction(item);
    final mollieRefundTargetId = creditTargetId;
    final mollieRefundBusy = _isRefundingBooking(mollieRefundTargetId);
    final localizedMollieRefund = _localizedMollieRefundStatus(item);
    final mollieRefundStatusColor = _mollieRefundStatusColor(item, tokens);
    final statusColor = _statusColor(item, tokens);
    final localizedStatus = _localizedBookingStatus(item.statusText);
    final localizedPayment = _localizedPaymentStatus(item.paymentStatus);
    final localizedCredit = _localizedCreditStatus(item.creditStatus);
    final isPaid =
        localizedPayment ==
        _t(nl: 'Betaald', en: 'Paid', fr: 'Payé', es: 'Pagado');
    final amountText = _moneyLabel(item);
    final parentAmountText = _moneyLabelFromAmount(
      item.parentAmount,
      item.currency,
    );
    final legLabel = _companyLegLabel(item);
    final pickupText = _formatPickup(item.pickupIso);
    final customerMissing = _isMissingValue(item.customerName);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: tokens.cardGradient,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.cardBorder),
        boxShadow: [
          BoxShadow(
            color: tokens.shadow,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (item.isOperationalLeg && item.isRoundtripParent)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.legAccent.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: tokens.legAccent.withOpacity(0.45),
                      ),
                    ),
                    child: Text(
                      legLabel,
                      style: TextStyle(
                        color: tokens.legAccent.withOpacity(0.95),
                        fontSize: 11.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: statusColor.withOpacity(0.45)),
                  ),
                  child: Text(
                    localizedStatus,
                    style: TextStyle(
                      color: statusColor.withOpacity(0.98),
                      fontSize: 11.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (item.isStreetRide)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: tokens.accent.withOpacity(0.4)),
                    ),
                    child: Text(
                      _t(
                        nl: 'Straatrit',
                        en: 'Street ride',
                        fr: 'Course directe',
                        es: 'Viaje directo',
                      ),
                      style: TextStyle(
                        color: tokens.accent.withOpacity(0.98),
                        fontSize: 11.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                const Spacer(),
                if (amountText.isNotEmpty)
                  Text(
                    amountText,
                    style: TextStyle(
                      color: tokens.accent.withOpacity(0.98),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
              ],
            ),
            if (item.isOperationalLeg && item.isRoundtripParent) ...[
              const SizedBox(height: 8),
              Text(
                '${_t(nl: 'Parent', en: 'Parent', fr: 'Parent', es: 'Padre')}: ${item.parentReferenceText.isEmpty ? item.referenceText : item.parentReferenceText}',
                style: TextStyle(
                  color: tokens.textTertiary,
                  fontSize: 11.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (parentAmountText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '${_t(nl: 'Totaal parent', en: 'Parent total', fr: 'Total parent', es: 'Total padre')}: $parentAmountText',
                    style: TextStyle(
                      color: tokens.textTertiary.withOpacity(0.9),
                      fontSize: 10.8,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 10),
            Text(
              '${_t(nl: 'Geplande ophaal', en: 'Scheduled pickup', fr: 'Prise en charge prévue', es: 'Recogida programada')}: $pickupText',
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 12.1,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Icon(
                      Icons.radio_button_checked,
                      size: 11.5,
                      color: tokens.accent.withOpacity(0.94),
                    ),
                    Container(
                      width: 1.8,
                      height: 30,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: tokens.accent.withOpacity(0.35),
                    ),
                    Icon(
                      Icons.location_on,
                      size: 13.5,
                      color: tokens.palette.success,
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.fromAddress,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 12.8,
                          fontWeight: FontWeight.w600,
                          height: 1.24,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        item.toAddress,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 12.8,
                          fontWeight: FontWeight.w600,
                          height: 1.24,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (item.customerName.trim().isNotEmpty)
                  Text(
                    '${_t(nl: 'Klant', en: 'Customer', fr: 'Client', es: 'Cliente')}: ${item.customerName}',
                    style: TextStyle(
                      color: customerMissing
                          ? tokens.textTertiary
                          : tokens.textSecondary,
                      fontSize: 11.4,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  '${_t(nl: 'Chauffeur', en: 'Driver', fr: 'Chauffeur', es: 'Conductor')}: ${item.assignedDriverText}',
                  style: TextStyle(color: tokens.textTertiary, fontSize: 11.4),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_t(nl: 'Voertuig', en: 'Vehicle', fr: 'Véhicule', es: 'Vehículo')}: ${item.assignedVehicleText}',
                  style: TextStyle(color: tokens.textTertiary, fontSize: 11.4),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isPaid ? tokens.paidBg : tokens.unpaidBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isPaid ? tokens.paidBorder : tokens.unpaidBorder,
                    ),
                  ),
                  child: Text(
                    localizedPayment,
                    style: TextStyle(
                      color: isPaid ? tokens.paidText : tokens.unpaidText,
                      fontSize: 11.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isToCredit)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.warningText.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: tokens.warningText.withOpacity(0.42),
                      ),
                    ),
                    child: Text(
                      '${_t(nl: 'Creditstatus', en: 'Credit status', fr: 'Statut crédit', es: 'Estado crédito')}: $localizedCredit',
                      style: TextStyle(
                        color: tokens.warningText.withOpacity(0.98),
                        fontSize: 11.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (showCreditDecisionBadge)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.textSecondary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: tokens.textSecondary.withOpacity(0.35),
                      ),
                    ),
                    child: Text(
                      creditDecisionRecordedChip,
                      style: TextStyle(
                        color: tokens.textSecondary.withOpacity(0.98),
                        fontSize: 11.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (showMollieRefundStatus)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: mollieRefundStatusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: mollieRefundStatusColor.withOpacity(0.42),
                      ),
                    ),
                    child: Text(
                      '${_t(nl: 'Terugbetalingsstatus', en: 'Refund status', fr: 'Statut remboursement', es: 'Estado reembolso')}: $localizedMollieRefund',
                      style: TextStyle(
                        color: mollieRefundStatusColor.withOpacity(0.98),
                        fontSize: 11.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                Text(
                  '${_t(nl: 'Ref', en: 'Ref', fr: 'Ref', es: 'Ref')}: ${_shortBookingReference(item)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tokens.textTertiary, fontSize: 10.8),
                ),
                if (_filter != _CompanyBookingsFilter.open)
                  OutlinedButton(
                    onPressed:
                        (_bulkArchiving || _isArchivingBooking(item.bookingId))
                        ? null
                        : () => _hideSingleBooking(item),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: tokens.accent.withOpacity(0.96),
                      side: BorderSide(color: tokens.accent.withOpacity(0.42)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      _isArchivingBooking(item.bookingId)
                          ? _t(
                              nl: 'Bezig...',
                              en: 'Working...',
                              fr: 'En cours...',
                              es: 'Procesando...',
                            )
                          : _t(
                              nl: 'Verberg',
                              en: 'Hide',
                              fr: 'Masquer',
                              es: 'Ocultar',
                            ),
                      style: const TextStyle(
                        fontSize: 11.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            if (_shouldShowAdminCancelPaidAction(item)) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isCancellingBooking(_cancelBusyKey(item))
                      ? null
                      : () => _cancelPaidBookingAsAdmin(item),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.danger.withOpacity(0.96),
                    side: BorderSide(color: tokens.danger.withOpacity(0.45)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  icon: _isCancellingBooking(_cancelBusyKey(item))
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              tokens.danger.withOpacity(0.9),
                            ),
                          ),
                        )
                      : Icon(
                          Icons.cancel_schedule_send_rounded,
                          size: 18,
                          color: tokens.danger.withOpacity(0.96),
                        ),
                  label: Text(
                    _isCancellingBooking(_cancelBusyKey(item))
                        ? _t(
                            nl: 'Bezig met annuleren...',
                            en: 'Cancelling...',
                            fr: 'Annulation en cours...',
                            es: 'Cancelando...',
                          )
                        : _t(
                            nl: 'Annuleer betaalde rit',
                            en: 'Cancel paid ride',
                            fr: 'Annuler le trajet payé',
                            es: 'Cancelar viaje pagado',
                          ),
                    style: const TextStyle(
                      fontSize: 12.1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
            if (showCreditDecisionActions) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: creditActionsEnabled
                        ? () => _confirmFullCredit(item)
                        : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: tokens.accent.withOpacity(0.96),
                      side: BorderSide(color: tokens.accent.withOpacity(0.42)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      creditBusy
                          ? _t(
                              nl: 'Bezig...',
                              en: 'Working...',
                              fr: 'En cours...',
                              es: 'Procesando...',
                            )
                          : fullCreditButtonLabel,
                      style: const TextStyle(
                        fontSize: 11.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: creditActionsEnabled
                        ? () => _confirmPartialCredit(item)
                        : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: tokens.accent.withOpacity(0.96),
                      side: BorderSide(color: tokens.accent.withOpacity(0.42)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      _t(
                        nl: 'Gedeeltelijke credit',
                        en: 'Partial credit',
                        fr: 'Crédit partiel',
                        es: 'Crédito parcial',
                      ),
                      style: const TextStyle(
                        fontSize: 11.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: creditActionsEnabled
                        ? () => _confirmNoRefund(item)
                        : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: tokens.textSecondary,
                      side: BorderSide(color: tokens.cardBorder),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      _t(
                        nl: 'Geen terugbetaling',
                        en: 'No refund',
                        fr: 'Pas de remboursement',
                        es: 'Sin reembolso',
                      ),
                      style: const TextStyle(
                        fontSize: 11.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: creditActionsEnabled
                        ? () => _confirmHandledManually(item)
                        : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: tokens.textSecondary,
                      side: BorderSide(color: tokens.cardBorder),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      _t(
                        nl: 'Handmatig afgehandeld',
                        en: 'Mark handled manually',
                        fr: 'Traité manuellement',
                        es: 'Marcar gestionado manualmente',
                      ),
                      style: const TextStyle(
                        fontSize: 11.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (showMollieRefundAction) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (mollieRefundBusy || creditBusy)
                      ? null
                      : () => _confirmMollieRefund(item),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.accent.withOpacity(0.96),
                    side: BorderSide(color: tokens.accent.withOpacity(0.45)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  icon: mollieRefundBusy
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              tokens.accent.withOpacity(0.9),
                            ),
                          ),
                        )
                      : Icon(
                          Icons.replay_rounded,
                          size: 18,
                          color: tokens.accent.withOpacity(0.96),
                        ),
                  label: Text(
                    mollieRefundBusy
                        ? _t(
                            nl: 'Bezig...',
                            en: 'Working...',
                            fr: 'En cours...',
                            es: 'Procesando...',
                          )
                        : _t(
                            nl: 'Terugbetalen via Mollie',
                            en: 'Refund via Mollie',
                            fr: 'Rembourser via Mollie',
                            es: 'Reembolsar vía Mollie',
                          ),
                    style: const TextStyle(
                      fontSize: 12.1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
            if (showMollieRefundStatusRefresh) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (mollieRefundBusy || creditBusy)
                      ? null
                      : () => _runMollieRefundStatusRefresh(item),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.warningText.withOpacity(0.96),
                    side: BorderSide(
                      color: tokens.warningText.withOpacity(0.45),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  icon: mollieRefundBusy
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              tokens.warningText.withOpacity(0.9),
                            ),
                          ),
                        )
                      : Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: tokens.warningText.withOpacity(0.96),
                        ),
                  label: Text(
                    mollieRefundBusy
                        ? _t(
                            nl: 'Bezig...',
                            en: 'Working...',
                            fr: 'En cours...',
                            es: 'Procesando...',
                          )
                        : _t(
                            nl: 'Controleer terugbetalingsstatus',
                            en: 'Check refund status',
                            fr: 'Vérifier le statut du remboursement',
                            es: 'Comprobar estado del reembolso',
                          ),
                    style: const TextStyle(
                      fontSize: 12.1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
            if (showMollieRefundAuditResync) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (mollieRefundBusy || creditBusy)
                      ? null
                      : () => _runMollieRefundAuditResync(item),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.textSecondary.withOpacity(0.96),
                    side: BorderSide(
                      color: tokens.textSecondary.withOpacity(0.35),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  icon: mollieRefundBusy
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              tokens.textSecondary.withOpacity(0.9),
                            ),
                          ),
                        )
                      : Icon(
                          Icons.sync_rounded,
                          size: 18,
                          color: tokens.textSecondary.withOpacity(0.96),
                        ),
                  label: Text(
                    mollieRefundBusy
                        ? _t(
                            nl: 'Bezig...',
                            en: 'Working...',
                            fr: 'En cours...',
                            es: 'Procesando...',
                          )
                        : _t(
                            nl: 'Chiron-audit synchroniseren',
                            en: 'Sync Chiron audit',
                            fr: 'Synchroniser l\'audit Chiron',
                            es: 'Sincronizar auditoría Chiron',
                          ),
                    style: const TextStyle(
                      fontSize: 12.1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
            if (showCreditNotePdfAction || showRefundProofPdfAction) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (showCreditNotePdfAction)
                    OutlinedButton.icon(
                      onPressed: () =>
                          _CompanyBookingCreditRefundPdfActionRunner.previewCreditNotePdf(
                            context: context,
                            item: item,
                          ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: tokens.accent.withOpacity(0.96),
                        side: BorderSide(
                          color: tokens.accent.withOpacity(0.42),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: Icon(
                        Icons.description_outlined,
                        size: 16,
                        color: tokens.accent.withOpacity(0.96),
                      ),
                      label: Text(
                        _t(
                          nl: 'Creditnota PDF',
                          en: 'Credit note PDF',
                          fr: 'PDF note de crédit',
                          es: 'PDF nota de crédito',
                        ),
                        style: const TextStyle(
                          fontSize: 11.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (showRefundProofPdfAction)
                    OutlinedButton.icon(
                      onPressed: () =>
                          _CompanyBookingCreditRefundPdfActionRunner.previewRefundProofPdf(
                            context: context,
                            item: item,
                          ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: tokens.accent.withOpacity(0.96),
                        side: BorderSide(
                          color: tokens.accent.withOpacity(0.42),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: Icon(
                        Icons.receipt_long_outlined,
                        size: 16,
                        color: tokens.accent.withOpacity(0.96),
                      ),
                      label: Text(
                        _t(
                          nl: 'Terugbetalingsbewijs PDF',
                          en: 'Refund proof PDF',
                          fr: 'PDF preuve de remboursement',
                          es: 'PDF comprobante de reembolso',
                        ),
                        style: const TextStyle(
                          fontSize: 11.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (_isStreetBusinessInvoiceEligible(item)) ...[
              const SizedBox(height: 10),
              _StreetBusinessInvoiceAction(
                // Keyed by the canonical street booking id so the per-booking
                // invoice lifecycle controller (state + bounded polling)
                // survives list rebuilds and never leaks across bookings.
                key: ValueKey(
                  'street-business-invoice-${_documentsBookingId(item)}',
                ),
                bookingId: _documentsBookingId(item),
                isPaidBooking: _isBookingPaidForStreetInvoice(item),
                tokens: tokens,
              ),
            ],
            if (_documentsBookingId(item).isNotEmpty) ...[
              const SizedBox(height: 10),
              _BookingDocumentsSection(
                // Key by canonical booking + leg identity so switching tabs or
                // scrolling never reuses another leg's filtered documents state.
                key: ValueKey(
                  'booking-documents-${_documentsBookingId(item)}-'
                  '${item.legId.trim()}-${item.legType.trim().toLowerCase()}',
                ),
                bookingId: _documentsBookingId(item),
                sourceLegId:
                    _CompanyBookingOverviewItem.isRoundtripOperationalLegRow(
                      item,
                    )
                    ? item.legId
                    : null,
                sourceLegType:
                    _CompanyBookingOverviewItem.isRoundtripOperationalLegRow(
                      item,
                    )
                    ? item.legType
                    : null,
                tokens: tokens,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Canonical (parent) booking id used to list issued documents for a card.
  /// Delegates to the shared 3-tier resolver so this lookup uses the same
  /// canonical id the credit-note issue action uses (2G-S-B2 hardening: never
  /// the operational leg id).
  String _documentsBookingId(_CompanyBookingOverviewItem item) {
    return _resolveCompanyBookingDocumentsCanonicalId(item);
  }

  /// True when the company business-invoice action may be shown for [item]:
  /// a canonical, COMPLETED street/direct ride (paid or unpaid). Planned,
  /// customer, cancelled, refunded/credited and non-street rows resolve to a
  /// non-completed bucket and are excluded. Delegates the street + status test
  /// to the pure, unit-tested helper in `street_business_invoice_support.dart`.
  bool _isStreetBusinessInvoiceEligible(_CompanyBookingOverviewItem item) {
    // Bucket already segregates cancelled/refunded/credited/to-credit rows, so
    // only the completed bucket reaches the strict predicate. Canonical street
    // identity (never ride_type == direct alone) is required.
    if (item.bucket != _CompanyBookingsFilter.completed) return false;
    return isStreetRideBusinessInvoiceEligible(
      bookingId: _documentsBookingId(item),
      source: item.isCanonicalStreetRide ? kStreetRideBookingSource : null,
      bookingSource: item.isCanonicalStreetRide
          ? kStreetRideBookingSource
          : null,
      rideType: null,
      status: 'COMPLETED',
      isCancelled: false,
      isRefunded: false,
      isCredited: false,
    );
  }

  /// Booking-level paid signal used only to tailor the invoice request copy and
  /// the initial displayed status. The authoritative paid state always comes
  /// from the backend response / documents (never overwritten by this hint).
  bool _isBookingPaidForStreetInvoice(_CompanyBookingOverviewItem item) {
    return item.paymentStatus.trim().toLowerCase() == 'paid';
  }

  Widget _filterChip(
    _CompanyBookingsFilter filter,
    String label,
    _CompanyBookingsThemeTokens tokens,
  ) {
    final selected = _filter == filter;
    return ChoiceChip(
      label: Text('$label (${_countText(filter)})'),
      selected: selected,
      onSelected: (_) => setState(() => _filter = filter),
      selectedColor: tokens.chipSelectedBg,
      backgroundColor: tokens.chipUnselectedBg,
      side: BorderSide(
        color: selected
            ? tokens.chipSelectedBorder
            : tokens.chipUnselectedBorder,
      ),
      labelStyle: TextStyle(
        color: selected ? tokens.chipSelectedText : tokens.chipUnselectedText,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }

  // Phone-portrait variant of [_filterChip] used inside the compact horizontal
  // scroll filter bar. Same selection state, callbacks, colors and label
  // semantics as the wide-layout chip; only the density / padding / tap
  // target are reduced so booking cards become visible higher on the screen.
  // Keeping a separate widget (instead of mutating [_filterChip]) preserves
  // the approved tablet/desktop appearance exactly as-is.
  Widget _filterChipCompact(
    _CompanyBookingsFilter filter,
    String label,
    _CompanyBookingsThemeTokens tokens,
  ) {
    final selected = _filter == filter;
    return ChoiceChip(
      label: Text('$label (${_countText(filter)})'),
      selected: selected,
      onSelected: (_) => setState(() => _filter = filter),
      selectedColor: tokens.chipSelectedBg,
      backgroundColor: tokens.chipUnselectedBg,
      side: BorderSide(
        color: selected
            ? tokens.chipSelectedBorder
            : tokens.chipUnselectedBorder,
      ),
      labelStyle: TextStyle(
        color: selected ? tokens.chipSelectedText : tokens.chipUnselectedText,
        fontWeight: FontWeight.w700,
        fontSize: 12.4,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;
    return ValueListenableBuilder<BusinessThemeVariant>(
      valueListenable: businessThemeNotifier,
      builder: (context, themeVariant, _) {
        final tokens = _themeTokensFor(themeVariant);
        return Scaffold(
          backgroundColor: tokens.background,
          appBar: AppBar(
            backgroundColor: tokens.appBar,
            title: Text(
              _t(
                nl: 'Boekingen',
                en: 'Bookings',
                fr: 'Réservations',
                es: 'Reservas',
              ),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: tokens.textPrimary,
              ),
            ),
            iconTheme: IconThemeData(color: tokens.textPrimary),
            actions: [
              IconButton(
                tooltip: _t(
                  nl: 'Vernieuwen',
                  en: 'Refresh',
                  fr: 'Actualiser',
                  es: 'Actualizar',
                ),
                onPressed: _loadBookings,
                icon: Icon(
                  Icons.refresh_rounded,
                  color: tokens.accent.withOpacity(0.96),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Phone-portrait / narrow-screen UX polish:
                  //   * width < 600 → render the same filter set in a compact
                  //     horizontally scrolling row, plus a more compact
                  //     "Verberg alles op deze pagina" button. This frees up
                  //     vertical space so booking cards become visible much
                  //     higher on the screen.
                  //   * width >= 600 → keep the approved tablet/desktop
                  //     layout (Wrap + standard hide-all button) unchanged.
                  // Filter semantics, selection state, counts and callbacks
                  // are identical across both branches — only chip density
                  // and layout differ.
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 600;
                      final filterDefs =
                          <({_CompanyBookingsFilter filter, String label})>[
                            (
                              filter: _CompanyBookingsFilter.open,
                              label: _t(
                                nl: 'Open / gepland',
                                en: 'Open / scheduled',
                                fr: 'Ouvertes / planifiées',
                                es: 'Abiertas / planificadas',
                              ),
                            ),
                            (
                              filter: _CompanyBookingsFilter.completed,
                              label: _t(
                                nl: 'Afgerond / voltooid',
                                en: 'Completed',
                                fr: 'Terminées',
                                es: 'Completadas',
                              ),
                            ),
                            (
                              filter: _CompanyBookingsFilter.cancelled,
                              label: _t(
                                nl: 'Geannuleerd',
                                en: 'Cancelled',
                                fr: 'Annulées',
                                es: 'Canceladas',
                              ),
                            ),
                            (
                              filter: _CompanyBookingsFilter.toCredit,
                              label: _t(
                                nl: 'Te crediteren',
                                en: 'To credit',
                                fr: 'À créditer',
                                es: 'Por abonar',
                              ),
                            ),
                            (
                              filter: _CompanyBookingsFilter.refundPending,
                              label: _t(
                                nl: 'Terugbetaling bezig',
                                en: 'Refund pending',
                                fr: 'Remboursement en cours',
                                es: 'Reembolso en curso',
                              ),
                            ),
                            (
                              filter: _CompanyBookingsFilter.refunded,
                              label: _t(
                                nl: 'Terugbetaald',
                                en: 'Refunded',
                                fr: 'Remboursées',
                                es: 'Reembolsadas',
                              ),
                            ),
                            (
                              filter: _CompanyBookingsFilter.refundFailed,
                              label: _t(
                                nl: 'Terugbetaling mislukt',
                                en: 'Refund failed',
                                fr: 'Remboursement échoué',
                                es: 'Reembolso fallido',
                              ),
                            ),
                          ];
                      if (isNarrow) {
                        final showHideAll =
                            items.isNotEmpty &&
                            _filter != _CompanyBookingsFilter.open;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 36,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                padding: EdgeInsets.zero,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    for (var i = 0; i < filterDefs.length; i++)
                                      Padding(
                                        padding: EdgeInsets.only(
                                          right: i == filterDefs.length - 1
                                              ? 0
                                              : 6,
                                        ),
                                        child: _filterChipCompact(
                                          filterDefs[i].filter,
                                          filterDefs[i].label,
                                          tokens,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (showHideAll) ...[
                              const SizedBox(height: 6),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _bulkArchiving
                                      ? null
                                      : _hideAllVisiblePageBookings,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: tokens.accent.withOpacity(
                                      0.96,
                                    ),
                                    side: BorderSide(
                                      color: tokens.accent.withOpacity(0.42),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    minimumSize: const Size(0, 34),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: const Icon(
                                    Icons.visibility_off_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    _bulkArchiving
                                        ? _t(
                                            nl: 'Bezig met verbergen...',
                                            en: 'Hiding...',
                                            fr: 'Masquage en cours...',
                                            es: 'Ocultando...',
                                          )
                                        : _t(
                                            nl: 'Verberg alles op deze pagina',
                                            en: 'Hide all on this page',
                                            fr: 'Tout masquer sur cette page',
                                            es: 'Ocultar todo en esta página',
                                          ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12.4,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      }
                      // Tablet / wide / desktop: preserve the approved layout.
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final def in filterDefs)
                                _filterChip(def.filter, def.label, tokens),
                            ],
                          ),
                          if (items.isNotEmpty &&
                              _filter != _CompanyBookingsFilter.open) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _bulkArchiving
                                    ? null
                                    : _hideAllVisiblePageBookings,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: tokens.accent.withOpacity(
                                    0.96,
                                  ),
                                  side: BorderSide(
                                    color: tokens.accent.withOpacity(0.42),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.visibility_off_outlined,
                                  size: 18,
                                ),
                                label: Text(
                                  _bulkArchiving
                                      ? _t(
                                          nl: 'Bezig met verbergen...',
                                          en: 'Hiding...',
                                          fr: 'Masquage en cours...',
                                          es: 'Ocultando...',
                                        )
                                      : _t(
                                          nl: 'Verberg alles op deze pagina',
                                          en: 'Hide all on this page',
                                          fr: 'Tout masquer sur cette page',
                                          es: 'Ocultar todo en esta página',
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _loading
                        ? Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                tokens.accent,
                              ),
                            ),
                          )
                        : (_errorCode != null)
                        ? Center(
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: tokens.palette.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: tokens.accent.withOpacity(0.34),
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _friendlyError(_errorCode),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: tokens.textPrimary,
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed: _loadBookings,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: tokens.accent
                                          .withOpacity(0.95),
                                      side: BorderSide(
                                        color: tokens.accent.withOpacity(0.42),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      _t(
                                        nl: 'Opnieuw proberen',
                                        en: 'Try again',
                                        fr: 'Réessayer',
                                        es: 'Intentar de nuevo',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : items.isEmpty
                        ? Center(
                            child: Text(
                              _t(
                                nl: 'Geen boekingen gevonden voor deze filter.',
                                en: 'No bookings found for this filter.',
                                fr: 'Aucune réservation trouvée pour ce filtre.',
                                es: 'No se encontraron reservas para este filtro.',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: tokens.textSecondary),
                            ),
                          )
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) =>
                                _buildCompanyBookingPremiumCard(
                                  items[index],
                                  tokens,
                                ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CompanyBookingsThemeTokens {
  const _CompanyBookingsThemeTokens({
    required this.palette,
    required this.background,
    required this.appBar,
    required this.cardGradient,
    required this.cardBorder,
    required this.shadow,
    required this.accent,
    required this.legAccent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.chipSelectedBg,
    required this.chipUnselectedBg,
    required this.chipSelectedBorder,
    required this.chipUnselectedBorder,
    required this.chipSelectedText,
    required this.chipUnselectedText,
    required this.paidBg,
    required this.paidBorder,
    required this.paidText,
    required this.unpaidBg,
    required this.unpaidBorder,
    required this.unpaidText,
    required this.warningText,
    required this.danger,
    required this.reviewPrimaryText,
    required this.reviewSecondaryText,
    required this.reviewPlaceholderText,
    required this.reviewWarningText,
  });

  final BusinessThemePalette palette;
  final Color background;
  final Color appBar;
  final List<Color> cardGradient;
  final Color cardBorder;
  final Color shadow;
  final Color accent;
  final Color legAccent;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color chipSelectedBg;
  final Color chipUnselectedBg;
  final Color chipSelectedBorder;
  final Color chipUnselectedBorder;
  final Color chipSelectedText;
  final Color chipUnselectedText;
  final Color paidBg;
  final Color paidBorder;
  final Color paidText;
  final Color unpaidBg;
  final Color unpaidBorder;
  final Color unpaidText;
  final Color warningText;
  final Color danger;
  final Color reviewPrimaryText;
  final Color reviewSecondaryText;
  final Color reviewPlaceholderText;
  final Color reviewWarningText;
}
