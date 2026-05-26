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
  bool _bulkArchiving = false;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  Map<String, String> _adminHeaders() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = kAdminToken.trim();
    if (token.isNotEmpty) {
      headers['x-admin-token'] = token;
    }
    return headers;
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
          .post(uri, headers: _adminHeaders(), body: jsonEncode(payload))
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _t(
            nl: 'Boeking verbergen?',
            en: 'Hide booking?',
            fr: 'Masquer la réservation ?',
            es: '¿Ocultar reserva?',
          ),
        ),
        content: Text(
          _t(
            nl: 'Deze boeking wordt alleen uit dit bedrijfsboekingenoverzicht verborgen. Facturen, betalingen, klantgeschiedenis en auditgegevens blijven bewaard.',
            en: 'This booking will be hidden only from this company bookings overview. Invoices, payments, customer history and audit data remain preserved.',
            fr: 'Cette réservation sera masquée uniquement de cet aperçu des réservations de l’entreprise. Les factures, paiements, l’historique client et les données d’audit restent conservés.',
            es: 'Esta reserva se ocultará solo de esta vista de reservas de la empresa. Las facturas, pagos, historial del cliente y datos de auditoría se conservan.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
            ),
          ),
          FilledButton(
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _t(
            nl: 'Zichtbare boekingen verbergen?',
            en: 'Hide visible bookings?',
            fr: 'Masquer les réservations visibles ?',
            es: '¿Ocultar reservas visibles?',
          ),
        ),
        content: Text(
          _t(
            nl: 'Je verbergt $count boekingen uit deze lijst. Facturen, betalingen, klantgeschiedenis en auditgegevens blijven bewaard.',
            en: 'You are hiding $count bookings from this list. Invoices, payments, customer history and audit data remain preserved.',
            fr: 'Vous masquez $count réservations de cette liste. Les factures, paiements, l’historique client et les données d’audit restent conservés.',
            es: 'Ocultarás $count reservas de esta lista. Las facturas, pagos, historial del cliente y datos de auditoría se conservan.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar'),
            ),
          ),
          FilledButton(
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
          .get(uri, headers: _adminHeaders())
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
      final parsed = mappedItems
          .map((entry) => _CompanyBookingOverviewItem.fromMap(entry))
          .where((entry) => entry.bookingId.trim().isNotEmpty)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _all = parsed;
        _loading = false;
      });
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
            .where((item) => item.bucket == _CompanyBookingsFilter.cancelled)
            .toList(growable: false);
      case _CompanyBookingsFilter.review:
        return _all
            .where((item) => item.bucket == _CompanyBookingsFilter.review)
            .toList(growable: false);
    }
  }

  String _countText(_CompanyBookingsFilter filter) {
    return _all.where((item) => item.bucket == filter).length.toString();
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

  Color _statusColor(_CompanyBookingOverviewItem item) {
    switch (item.bucket) {
      case _CompanyBookingsFilter.completed:
        return const Color(0xFF66D9A8);
      case _CompanyBookingsFilter.cancelled:
        return const Color(0xFFE88989);
      case _CompanyBookingsFilter.review:
        return const Color(0xFFF6B94D);
      case _CompanyBookingsFilter.open:
        if (item.statusText.trim().toUpperCase() == 'CONFIRMED') {
          return const Color(0xFF34D29A);
        }
        return kFluxidiYellow;
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

  Widget _buildCompanyBookingPremiumCard(_CompanyBookingOverviewItem item) {
    final statusColor = _statusColor(item);
    final localizedStatus = _localizedBookingStatus(item.statusText);
    final localizedPayment = _localizedPaymentStatus(item.paymentStatus);
    final isPaid =
        localizedPayment ==
        _t(nl: 'Betaald', en: 'Paid', fr: 'Payé', es: 'Pagado');
    final amountText = _moneyLabel(item);
    final parentAmountText = _moneyLabelFromAmount(
      item.parentAmount,
      item.currency,
    );
    final legLabel = _companyLegLabel(item);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF121212), Color(0xFF0A0A0B), Color(0xFF080809)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kFluxidiYellow.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
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
                      color: const Color(0xFF52B6FF).withOpacity(0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0xFF52B6FF).withOpacity(0.45),
                      ),
                    ),
                    child: Text(
                      legLabel,
                      style: const TextStyle(
                        color: Color(0xFF9DD8FF),
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
                const Spacer(),
                if (amountText.isNotEmpty)
                  Text(
                    amountText,
                    style: TextStyle(
                      color: kFluxidiYellow.withOpacity(0.98),
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
                  color: Colors.white.withOpacity(0.62),
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
                      color: Colors.white.withOpacity(0.56),
                      fontSize: 10.8,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 10),
            Text(
              '${_t(nl: 'Geplande ophaal', en: 'Scheduled pickup', fr: 'Prise en charge prévue', es: 'Recogida programada')}: ${_formatPickup(item.pickupIso)}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.86),
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
                      color: kFluxidiYellow.withOpacity(0.94),
                    ),
                    Container(
                      width: 1.8,
                      height: 30,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: kFluxidiYellow.withOpacity(0.35),
                    ),
                    const Icon(
                      Icons.location_on,
                      size: 13.5,
                      color: Color(0xFF34D29A),
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
                        style: const TextStyle(
                          color: Colors.white,
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
                          color: Colors.white.withOpacity(0.9),
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
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 11.4,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  '${_t(nl: 'Chauffeur', en: 'Driver', fr: 'Chauffeur', es: 'Conductor')}: ${item.assignedDriverText}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.64),
                    fontSize: 11.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_t(nl: 'Voertuig', en: 'Vehicle', fr: 'Véhicule', es: 'Vehículo')}: ${item.assignedVehicleText}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.64),
                    fontSize: 11.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.bucket == _CompanyBookingsFilter.review)
                  Text(
                    _t(
                      nl: 'Oude/onvolledige boeking',
                      en: 'Old/incomplete booking',
                      fr: 'Réservation ancienne/incomplète',
                      es: 'Reserva antigua/incompleta',
                    ),
                    style: TextStyle(
                      color: const Color(0xFFF6B94D).withOpacity(0.9),
                      fontSize: 11.1,
                      fontWeight: FontWeight.w600,
                    ),
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
                    color: isPaid
                        ? const Color(0xFF34D29A).withOpacity(0.14)
                        : kFluxidiYellow.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isPaid
                          ? const Color(0xFF34D29A).withOpacity(0.4)
                          : kFluxidiYellow.withOpacity(0.35),
                    ),
                  ),
                  child: Text(
                    localizedPayment,
                    style: TextStyle(
                      color: isPaid
                          ? const Color(0xFF9DF2CF)
                          : kFluxidiYellow.withOpacity(0.97),
                      fontSize: 11.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${_t(nl: 'Ref', en: 'Ref', fr: 'Ref', es: 'Ref')}: ${_shortBookingReference(item)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.58),
                    fontSize: 10.8,
                  ),
                ),
                if (_filter != _CompanyBookingsFilter.open)
                  OutlinedButton(
                    onPressed:
                        (_bulkArchiving || _isArchivingBooking(item.bookingId))
                        ? null
                        : () => _hideSingleBooking(item),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kFluxidiYellow.withOpacity(0.96),
                      side: BorderSide(color: kFluxidiYellow.withOpacity(0.35)),
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
          ],
        ),
      ),
    );
  }

  Widget _filterChip(_CompanyBookingsFilter filter, String label) {
    final selected = _filter == filter;
    return ChoiceChip(
      label: Text('$label (${_countText(filter)})'),
      selected: selected,
      onSelected: (_) => setState(() => _filter = filter),
      selectedColor: const Color(0xFF2A2410),
      backgroundColor: const Color(0xFF111318),
      side: BorderSide(
        color: selected
            ? kFluxidiYellow.withOpacity(0.65)
            : kFluxidiYellow.withOpacity(0.24),
      ),
      labelStyle: TextStyle(
        color: selected ? kFluxidiYellow.withOpacity(0.95) : Colors.white70,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;
    return Scaffold(
      backgroundColor: const Color(0xFF07080C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF07080C),
        title: Text(
          _t(
            nl: 'Boekingen',
            en: 'Bookings',
            fr: 'Réservations',
            es: 'Reservas',
          ),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
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
              color: kFluxidiYellow.withOpacity(0.96),
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _filterChip(
                    _CompanyBookingsFilter.open,
                    _t(
                      nl: 'Open / gepland',
                      en: 'Open / scheduled',
                      fr: 'Ouvertes / planifiées',
                      es: 'Abiertas / planificadas',
                    ),
                  ),
                  _filterChip(
                    _CompanyBookingsFilter.completed,
                    _t(
                      nl: 'Afgerond / voltooid',
                      en: 'Completed',
                      fr: 'Terminées',
                      es: 'Completadas',
                    ),
                  ),
                  _filterChip(
                    _CompanyBookingsFilter.cancelled,
                    _t(
                      nl: 'Geannuleerd',
                      en: 'Cancelled',
                      fr: 'Annulées',
                      es: 'Canceladas',
                    ),
                  ),
                  _filterChip(
                    _CompanyBookingsFilter.review,
                    _t(
                      nl: 'Nazicht',
                      en: 'Review',
                      fr: 'À vérifier',
                      es: 'Revisión',
                    ),
                  ),
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
                      foregroundColor: kFluxidiYellow.withOpacity(0.96),
                      side: BorderSide(color: kFluxidiYellow.withOpacity(0.35)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    icon: const Icon(Icons.visibility_off_outlined, size: 18),
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
              const SizedBox(height: 10),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : (_errorCode != null)
                    ? Center(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF101113),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: kFluxidiYellow.withOpacity(0.28),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _friendlyError(_errorCode),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.88),
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: _loadBookings,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: kFluxidiYellow.withOpacity(
                                    0.95,
                                  ),
                                  side: BorderSide(
                                    color: kFluxidiYellow.withOpacity(0.38),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
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
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.72),
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _buildCompanyBookingPremiumCard(items[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
