part of '../main.dart';

class CustomerBookingsPage extends StatefulWidget {
  const CustomerBookingsPage({super.key});

  @override
  State<CustomerBookingsPage> createState() => _CustomerBookingsPageState();
}

class _CustomerBookingsPageState extends State<CustomerBookingsPage> {
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  DateTime? _lastUpdated;
  List<StoredCustomerBooking> _bookings = const <StoredCustomerBooking>[];
  Map<String, String> _paymentOverlayByBookingId = const <String, String>{};
  // G3-N: canonical / payment booking ids whose payment_return.dart notifier
  // transitioned to paid/confirmed while this list was visible. Used to
  // upgrade the displayed token to "paid" even before the next authoritative
  // refresh round-trips, so resumed Mollie payments do not flicker as
  // "Pay in car" on the way back from the Mollie checkout.
  final Set<String> _optimisticallyPaidBookingIds = <String>{};
  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  void _applyCustomerBookingListRemoval({
    required Set<String> aliases,
    required String bookingForLog,
    required String action,
  }) {
    if (!mounted) return;
    final beforeCount = _bookings.length;
    setState(() {
      _bookings = _bookings
          .where(
            (item) => !_customerAliasesIntersect(
              _customerBookingAliasesFromStored(item),
              aliases,
            ),
          )
          .toList(growable: false);
    });
    debugPrint(
      '[CUSTOMER_BOOKING_CANCEL][LIST_APPLY_RESULT] action=$action booking=${_safeRefPreview(bookingForLog)} aliases=${aliases.length} before=$beforeCount after=${_bookings.length}',
    );
  }

  @override
  void initState() {
    super.initState();
    _loadLocal();
    fluxidiPendingPaymentNotifier.addListener(
      _onPendingPaymentNotifierChangedForCustomerList,
    );
  }

  @override
  void dispose() {
    fluxidiPendingPaymentNotifier.removeListener(
      _onPendingPaymentNotifierChangedForCustomerList,
    );
    super.dispose();
  }

  // G3-N: pending-payment notifier hook. When /pay/status confirms a resumed
  // Mollie payment as paid/confirmed, the Mollie webhook + pay-status both
  // run finalizeResumePaidPaymentToCanonical synchronously, so the canonical
  // record is already paid by the time we observe paid/confirmed here. We
  // optimistically mark the matching local list entry as paid (so the UI
  // does not show "Pay in car" briefly), persist the patched paymentStatus
  // to the local store, and trigger a single background _refreshAuthoritative
  // to pick up the rest of the canonical state.
  void _onPendingPaymentNotifierChangedForCustomerList() {
    if (!mounted) return;
    final pending = fluxidiPendingPaymentNotifier.value;
    if (pending == null) return;
    if (pending.status != FluxidiPaymentStatus.paid &&
        pending.status != FluxidiPaymentStatus.confirmed) {
      return;
    }
    final paymentBookingIdHit = pending.paymentBookingId.trim();
    final canonicalHit = (pending.publicBookingId ?? '').trim();
    if (paymentBookingIdHit.isEmpty && canonicalHit.isEmpty) return;
    StoredCustomerBooking? matched;
    for (final booking in _bookings) {
      final aliases = _overlayAliasesForBooking(booking);
      if (paymentBookingIdHit.isNotEmpty &&
          aliases.contains(paymentBookingIdHit.toLowerCase())) {
        matched = booking;
        break;
      }
      if (canonicalHit.isNotEmpty &&
          aliases.contains(canonicalHit.toLowerCase())) {
        matched = booking;
        break;
      }
      if (canonicalHit.isNotEmpty &&
          booking.canonicalBookingId.trim() == canonicalHit) {
        matched = booking;
        break;
      }
    }
    if (matched == null) return;
    final canonicalId = matched.canonicalBookingId.trim();
    if (canonicalId.isEmpty) return;
    if (_optimisticallyPaidBookingIds.contains(canonicalId)) return;
    debugPrint(
      '[CUSTOMER_BOOKINGS][PAYMENT_STATUS_PATCHED] booking=${_safeRefPreview(canonicalId)} paymentBooking=${_safeRefPreview(paymentBookingIdHit)} from=${matched.paymentStatus.isEmpty ? "-" : matched.paymentStatus} to=paid source=list_notifier',
    );
    debugPrint(
      '[PAYMENT_RETURN][CUSTOMER_REFRESH] surface=list booking=${_safeRefPreview(canonicalId)} paymentBooking=${_safeRefPreview(paymentBookingIdHit)} status=${pending.status.name}',
    );
    _optimisticallyPaidBookingIds.add(canonicalId);
    final updated = matched.copyWith(paymentStatus: 'paid');
    setState(() {
      _bookings = _bookings
          .map((b) => b.canonicalBookingId.trim() == canonicalId ? updated : b)
          .toList(growable: false);
    });
    unawaited(CustomerBookingsStore.instance.upsert(updated));
    if (!_refreshing) {
      unawaited(_refreshAuthoritative());
    }
  }

  Future<void> _loadLocal({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = await CustomerBookingsStore.instance.loadAll();
      final visible = await _filterActiveNonHiddenStoredCustomerBookings(items);
      if (!mounted) return;
      final overlay = await _buildPaymentOverlayForBookings(
        visible,
        source: 'load_local',
      );
      if (!mounted) return;
      setState(() {
        _bookings = visible;
        _paymentOverlayByBookingId = overlay;
        if (showLoading) {
          _loading = false;
        }
        _lastUpdated = DateTime.now();
      });
      debugPrint(
        '[CUSTOMER_BOOKINGS][RELOAD_AFTER_DELETE] count=${visible.length} showLoading=$showLoading',
      );
    } catch (err) {
      if (!mounted) return;
      setState(() {
        if (showLoading) {
          _loading = false;
        }
        _error = _t(
          nl: 'Laden mislukt.',
          en: 'Loading failed.',
          fr: 'Chargement echoue.',
          es: 'Error al cargar.',
        );
      });
      debugPrint('[CUSTOMER_BOOKINGS][LOAD_SCREEN_ERROR] $err');
    }
  }

  Future<void> _refreshAuthoritative() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final snapshot = await CustomerBookingsStore.instance.loadAll();
      for (final item in snapshot) {
        final id = item.canonicalBookingId.trim();
        if (id.isEmpty) continue;
        final itemAliases = _customerBookingAliasesFromStored(item);
        if (await CustomerBookingsStore.instance.isAnyReferenceAliasHidden(
          itemAliases,
        )) {
          continue;
        }
        try {
          final proof = await _customerOwnershipProof(
            bookingId: id,
            fallbackEmail: item.customerEmail,
            fallbackPhone: item.customerPhone,
          );
          final uri = _withActiveBookingScope(
            kBookingBaseUrl,
            '/bookings/${Uri.encodeComponent(id)}',
            extraQuery: proof.isEmpty ? null : proof,
          );
          final res = await http.get(uri).timeout(const Duration(seconds: 12));
          if (res.statusCode != 200) continue;
          final decoded = jsonDecode(utf8.decode(res.bodyBytes));
          if (decoded is! Map<String, dynamic> || decoded['ok'] != true)
            continue;
          final authoritativeView = CustomerBookingView.fromResponse(
            id,
            decoded,
          );
          final stored = StoredCustomerBooking.fromAuthoritativeResponse(
            bookingId: id,
            response: decoded,
            fallback: item,
          );
          await CustomerBookingsStore.instance.upsert(
            authoritativeView.mergeRoundtripSnapshotIntoStored(
              _hydrateStoredCustomerBookingFromView(
                stored: stored,
                view: authoritativeView,
                source: 'customer_list_refresh',
              ),
            ),
          );
        } catch (_) {
          // Keep refresh resilient: skip individual booking failures.
        }
      }
      final refreshed = await CustomerBookingsStore.instance.loadAll();
      final visible = await _filterActiveNonHiddenStoredCustomerBookings(
        refreshed,
      );
      if (!mounted) return;
      final overlay = await _buildPaymentOverlayForBookings(
        visible,
        source: 'refresh_authoritative',
      );
      if (!mounted) return;
      setState(() {
        _bookings = visible;
        _paymentOverlayByBookingId = overlay;
        _refreshing = false;
        _lastUpdated = DateTime.now();
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _paymentOverlayByBookingId = const <String, String>{};
        _error = _t(
          nl: 'Vernieuwen mislukt.',
          en: 'Refresh failed.',
          fr: "Echec de l'actualisation.",
          es: 'Error al actualizar.',
        );
      });
      debugPrint('[CUSTOMER_BOOKINGS][REFRESH_ERROR] $err');
    }
  }

  String _displayPaymentStatusToken(StoredCustomerBooking booking) {
    final channel = _customerPaymentChannelFieldsFromStoredBooking(booking);
    final bookingId = booking.canonicalBookingId.trim();
    String token;
    if (bookingId.isNotEmpty &&
        _paymentOverlayByBookingId.containsKey(bookingId)) {
      token = _classifyCustomerPaymentDisplayToken(
        aliases: _overlayAliasesForBooking(booking),
        fallbackToken: _paymentOverlayByBookingId[bookingId]!,
        paymentProvider: channel.provider,
        paymentMode: channel.mode,
        paymentMethod: channel.method,
      );
    } else {
      token = _classifyCustomerPaymentDisplayToken(
        aliases: _overlayAliasesForBooking(booking),
        fallbackToken: booking.paymentStatus,
        paymentProvider: channel.provider,
        paymentMode: channel.mode,
        paymentMethod: channel.method,
      );
    }
    // G3-N: stale-label guard. If the pending-payment notifier already
    // confirmed paid for this canonical booking but the cached token has not
    // been refreshed yet, force the displayed token to "paid".
    if (bookingId.isNotEmpty &&
        _optimisticallyPaidBookingIds.contains(bookingId) &&
        !_isPaidCustomerPaymentDisplayToken(token)) {
      debugPrint(
        '[CUSTOMER_BOOKINGS][STALE_PAYMENT_LABEL_GUARD] booking=${_safeRefPreview(bookingId)} backendToken=$token overrideTo=paid surface=list',
      );
      return 'paid';
    }
    return token;
  }

  bool _displayPaymentKnownPaid(StoredCustomerBooking booking) {
    final token = _displayPaymentStatusToken(booking);
    return _isPaidCustomerPaymentDisplayToken(token);
  }

  Set<String> _overlayAliasesForBooking(StoredCustomerBooking booking) {
    final aliases = <String>{..._customerBookingAliasesFromStored(booking)};
    void addAlias(String value) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty) return;
      aliases.add(normalized);
    }

    addAlias(booking.canonicalBookingId);
    addAlias(booking.bookingId);
    addAlias(booking.publicBookingId);
    addAlias(booking.bookingReference);
    addAlias(booking.publicReference);
    addAlias(booking.planningReference);
    addAlias(booking.paymentBookingId);
    addAlias((booking.quote['parent_booking_id'] ?? '').toString());
    addAlias((booking.quote['parentBookingId'] ?? '').toString());
    addAlias((booking.quote['original_booking_id'] ?? '').toString());
    addAlias((booking.quote['originalBookingId'] ?? '').toString());
    return aliases;
  }

  Future<Map<String, String>> _buildPaymentOverlayForBookings(
    List<StoredCustomerBooking> bookings, {
    required String source,
  }) async {
    if (bookings.isEmpty) return const <String, String>{};
    String tenantId = '';
    String companyId = '';
    var scopeSource = 'missing';

    for (final booking in bookings) {
      final bookingTenant = booking.tenantId.trim();
      final bookingCompany = booking.companyId.trim();
      if (bookingTenant.isEmpty || bookingCompany.isEmpty) continue;
      tenantId = bookingTenant;
      companyId = bookingCompany;
      scopeSource = 'booking_list_scope';
      break;
    }

    if (tenantId.isEmpty || companyId.isEmpty) {
      final customerSession = await CustomerSessionStore.instance
          .loadValidSession();
      final sessionTenant = (customerSession?.defaultTenantId ?? '').trim();
      final sessionCompany = (customerSession?.defaultCompanyId ?? '').trim();
      if (sessionTenant.isNotEmpty && sessionCompany.isNotEmpty) {
        tenantId = sessionTenant;
        companyId = sessionCompany;
        scopeSource = 'customer_session_scope';
      }
    }

    if (tenantId.isEmpty || companyId.isEmpty) {
      final strictScope = _strictActiveLocalScopeIds();
      if (strictScope != null) {
        tenantId = strictScope.tenantId.trim();
        companyId = strictScope.companyId.trim();
        scopeSource = 'strict_scope';
      }
    }

    debugPrint(
      '[CUSTOMER_BOOKINGS][PAYMENT_OVERLAY][SCOPE] source=$scopeSource tenant=${_maskLocalScopeId(tenantId)} company=${_maskLocalScopeId(companyId)}',
    );

    if (tenantId.isEmpty || companyId.isEmpty) {
      debugPrint(
        '[CUSTOMER_BOOKINGS][PAYMENT_OVERLAY][WARN] status=skip reason=missing_scope source=$source',
      );
      return const <String, String>{};
    }
    final scopeQuery = <String, String>{
      'tenant_id': tenantId,
      'company_id': companyId,
      'tenantId': tenantId,
      'companyId': companyId,
    };
    final trips = await _fetchTrackingOverlayTrips(
      scopeQuery: scopeQuery,
      diagTag: 'CUSTOMER_BOOKINGS',
      limit: 200,
    );
    final matcher = _TrackingPaymentOverlayMatcher(trips);
    final overlay = <String, String>{};
    var matchedParents = 0;
    var partial = 0;
    var paid = 0;
    for (final booking in bookings) {
      final bookingId = booking.canonicalBookingId.trim();
      if (bookingId.isEmpty) continue;
      final aliases = _overlayAliasesForBooking(booking);
      final aggregate = matcher.aggregateOperationalLegsForParentAliases(
        aliases,
      );
      final channel = _customerPaymentChannelFieldsFromStoredBooking(booking);
      final token = _classifyCustomerPaymentDisplayToken(
        aliases: aliases,
        fallbackToken: booking.paymentStatus,
        matcher: matcher,
        paymentProvider: channel.provider,
        paymentMode: channel.mode,
        paymentMethod: channel.method,
      );
      final shouldLogKeys =
          aggregate.totalLegs >= 2 || aggregate.totalLegs == 0;
      if (shouldLogKeys) {
        final aliasPreview = aliases.toList(growable: false)..sort();
        final keys = aliasPreview.take(6).join(',');
        debugPrint(
          '[CUSTOMER_BOOKINGS][PAYMENT_OVERLAY][KEYS] booking=${_safeRefPreview(bookingId)} keys=$keys matched=${aggregate.totalLegs}',
        );
      }
      if (aggregate.totalLegs >= 2) {
        matchedParents += 1;
      }
      if (token == 'paid') {
        overlay[bookingId] = token;
        paid += 1;
      } else if (token == 'partially_paid') {
        overlay[bookingId] = token;
        partial += 1;
      }
    }
    debugPrint(
      '[CUSTOMER_BOOKINGS][PAYMENT_OVERLAY] bookings=${bookings.length} matchedParents=$matchedParents partial=$partial paid=$paid',
    );
    return overlay;
  }

  String _formatPickup(String iso) {
    if (iso.trim().isEmpty) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String _formatPrice(StoredCustomerBooking booking) {
    final view = CustomerBookingView.fromStored(booking);
    final amount = view.customerDisplayCardAmount ?? booking.price;
    if (amount == null) return '-';
    final currency = booking.currency.toUpperCase().trim();
    final symbol = currency.isEmpty || currency == 'EUR' ? '€' : '$currency ';
    return '$symbol${amount.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _statusLabel(StoredCustomerBooking booking) {
    final status = _normalizeCustomerLifecycleStatus(booking.status);
    if (status == 'PENDING') {
      return _t(
        nl: 'In behandeling',
        en: 'Pending',
        fr: 'En cours',
        es: 'Pendiente',
      );
    }
    if (status == 'CONFIRMED') {
      return _t(
        nl: 'Bevestigd',
        en: 'Confirmed',
        fr: 'Confirmee',
        es: 'Confirmada',
      );
    }
    if (status == 'COMPLETED') {
      return _t(
        nl: 'Voltooid',
        en: 'Completed',
        fr: 'Terminee',
        es: 'Finalizada',
      );
    }
    if (status == 'CANCELLED') {
      return _t(
        nl: 'Geannuleerd',
        en: 'Cancelled',
        fr: 'Annulee',
        es: 'Cancelada',
      );
    }
    return status.isEmpty
        ? '-'
        : _t(nl: 'Onbekend', en: 'Unknown', fr: 'Inconnu', es: 'Desconocido');
  }

  String _paymentLabel(StoredCustomerBooking booking) {
    final p = _displayPaymentStatusToken(booking);
    if (_isPaidCustomerPaymentDisplayToken(p)) {
      return _t(nl: 'Betaald', en: 'Paid', fr: 'Paye', es: 'Pagado');
    }
    if (_isPartialCustomerPaymentDisplayToken(p)) {
      return _t(
        nl: 'Deels betaald',
        en: 'Partially paid',
        fr: 'Partiellement payé',
        es: 'Parcialmente pagado',
      );
    }
    if (_isOnlinePendingCustomerPaymentDisplayToken(p)) {
      return _t(
        nl: 'Online betaling openstaand',
        en: 'Online payment pending',
        fr: 'Paiement en ligne en attente',
        es: 'Pago online pendiente',
      );
    }
    if (_isPayInCarCustomerPaymentDisplayToken(p) ||
        p == 'unpaid' ||
        p == 'pending' ||
        p == 'pay_in_car') {
      return _t(
        nl: 'Te betalen in de wagen',
        en: 'Pay in the car',
        fr: 'À payer dans le véhicule',
        es: 'Pagar en el vehículo',
      );
    }
    return _t(
      nl: 'Te betalen in de wagen',
      en: 'Pay in the car',
      fr: 'À payer dans le véhicule',
      es: 'Pagar en el vehículo',
    );
  }

  String _formatLastUpdated() {
    final value = _lastUpdated;
    if (value == null) return '-';
    String two(int n) => n.toString().padLeft(2, '0');
    final local = value.toLocal();
    return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }

  Color _statusColor(StoredCustomerBooking booking) {
    switch (_normalizeCustomerLifecycleStatus(booking.status)) {
      case 'CONFIRMED':
        return const Color(0xFF34D29A);
      case 'COMPLETED':
        return const Color(0xFF66D9A8);
      case 'PENDING':
        return kFluxidiYellow;
      case 'CANCELLED':
        return const Color(0xFFE88989);
      default:
        return Colors.white70;
    }
  }

  String _roundtripCancelledLegChipLabel(String legToken) {
    if (legToken == 'return') {
      return _t(
        nl: 'Terugrit geannuleerd',
        en: 'Return cancelled',
        fr: 'Retour annule',
        es: 'Regreso cancelado',
      );
    }
    return _t(
      nl: 'Heenrit geannuleerd',
      en: 'Outbound cancelled',
      fr: 'Aller annule',
      es: 'Ida cancelada',
    );
  }

  Widget? _roundtripCancelledLegChip(StoredCustomerBooking booking) {
    final token = CustomerBookingView.fromStored(
      booking,
    ).roundtripCancelledLegChipToken;
    if (token == null) return null;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Text(
        _roundtripCancelledLegChipLabel(token),
        style: TextStyle(
          color: Colors.white.withOpacity(0.82),
          fontSize: 10.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _roundtripLegTitle(String legType) {
    if (legType == 'return') {
      return _t(nl: 'Terugrit', en: 'Return', fr: 'Retour', es: 'Regreso');
    }
    return _t(nl: 'Heenrit', en: 'Outbound', fr: 'Aller', es: 'Ida');
  }

  Widget _roundtripLegCard({
    required StoredCustomerBooking booking,
    required CustomerRoundtripLegCardView leg,
  }) {
    final statusColor = leg.isCancelled
        ? const Color(0xFFE88989)
        : const Color(0xFF34D29A);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withOpacity(0.13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _roundtripLegTitle(leg.legType),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.4,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusColor.withOpacity(0.36)),
                ),
                child: Text(
                  leg.isCancelled
                      ? _t(
                          nl: 'Geannuleerd',
                          en: 'Cancelled',
                          fr: 'Annule',
                          es: 'Cancelado',
                        )
                      : _t(
                          nl: 'Gepland',
                          en: 'Scheduled',
                          fr: 'Planifie',
                          es: 'Programado',
                        ),
                  style: TextStyle(
                    color: statusColor.withOpacity(0.98),
                    fontSize: 10.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _formatCardAmount(leg.priceInclVat, booking.currency),
                style: TextStyle(
                  color: kFluxidiYellow.withOpacity(0.96),
                  fontSize: 12.4,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_formatPickup(leg.pickupIso)} · ${leg.from.isEmpty ? '-' : leg.from} → ${leg.to.isEmpty ? '-' : leg.to}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 11.1,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (leg.isActive)
                OutlinedButton(
                  onPressed: () =>
                      _cancelFromCard(booking, legType: leg.legType),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE88989),
                    side: BorderSide(
                      color: const Color(0xFFE88989).withOpacity(0.45),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    minimumSize: const Size(48, 38),
                  ),
                  child: Text(
                    _t(
                      nl: 'Rit annuleren',
                      en: 'Cancel leg',
                      fr: 'Annuler trajet',
                      es: 'Cancelar tramo',
                    ),
                  ),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => _openDetails(booking, legType: leg.legType),
                child: Text(
                  _t(
                    nl: 'Rit bekijken',
                    en: 'View leg',
                    fr: 'Voir trajet',
                    es: 'Ver tramo',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatCardAmount(double? amount, String currency) {
    if (amount == null) return '-';
    final normalizedCurrency = currency.toUpperCase().trim();
    final symbol = normalizedCurrency.isEmpty || normalizedCurrency == 'EUR'
        ? '€'
        : '$normalizedCurrency ';
    return '$symbol${amount.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  Widget _premiumBookingCard(StoredCustomerBooking booking) {
    final statusColor = _statusColor(booking);
    final paymentKnownPaid = _displayPaymentKnownPaid(booking);
    final isTerminal = _isCustomerBookingTerminalStatus(booking.status);
    final cancelledLegChip = _roundtripCancelledLegChip(booking);
    final roundtripLegs = CustomerBookingView.fromStored(
      booking,
    ).roundtripLegCardViews;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
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
                  _statusLabel(booking),
                  style: TextStyle(
                    color: statusColor.withOpacity(0.98),
                    fontSize: 11.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _formatPrice(booking),
                style: TextStyle(
                  color: kFluxidiYellow.withOpacity(0.98),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${_t(nl: 'Geplande ophaal', en: 'Scheduled pickup', fr: 'Prise en charge prevue', es: 'Recogida programada')}: ${_formatPickup(booking.pickupIso)}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.86),
              fontSize: 12.1,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (cancelledLegChip != null) cancelledLegChip,
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
                      booking.from.isEmpty ? '-' : booking.from,
                      maxLines: 2,
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
                      booking.to.isEmpty ? '-' : booking.to,
                      maxLines: 2,
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
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: paymentKnownPaid
                      ? const Color(0xFF34D29A).withOpacity(0.14)
                      : kFluxidiYellow.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: paymentKnownPaid
                        ? const Color(0xFF34D29A).withOpacity(0.4)
                        : kFluxidiYellow.withOpacity(0.35),
                  ),
                ),
                child: Text(
                  _paymentLabel(booking),
                  style: TextStyle(
                    color: paymentKnownPaid
                        ? const Color(0xFF9DF2CF)
                        : kFluxidiYellow.withOpacity(0.97),
                    fontSize: 11.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${_t(nl: 'Ref', en: 'Ref', fr: 'Ref', es: 'Ref')}: ${booking.publicBookingReference.isEmpty ? booking.bookingId : booking.publicBookingReference}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.58),
                  fontSize: 10.8,
                ),
              ),
            ],
          ),
          if (roundtripLegs.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...roundtripLegs.map(
              (leg) => _roundtripLegCard(booking: booking, leg: leg),
            ),
          ],
          const SizedBox(height: 10),
          _CustomerBookingCardActionsLayout(
            children: [
              if (isTerminal)
                OutlinedButton(
                  onPressed: () => _removeFromMyBookings(booking),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white.withOpacity(0.9),
                    side: BorderSide(color: Colors.white.withOpacity(0.22)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: const Size(64, 44),
                  ),
                  child: Text(
                    _t(
                      nl: 'Verwijderen',
                      en: 'Remove',
                      fr: 'Supprimer',
                      es: 'Eliminar',
                    ),
                  ),
                )
              else if (roundtripLegs.isEmpty)
                OutlinedButton(
                  onPressed: () => _cancelFromCard(booking),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE88989),
                    side: BorderSide(
                      color: const Color(0xFFE88989).withOpacity(0.55),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: const Size(64, 44),
                  ),
                  child: Text(
                    _t(
                      nl: 'Boeking annuleren',
                      en: 'Cancel booking',
                      fr: 'Annuler la reservation',
                      es: 'Cancelar reserva',
                    ),
                  ),
                ),
              OutlinedButton(
                onPressed: () => _openDetails(booking),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kFluxidiYellow.withOpacity(0.97),
                  side: BorderSide(color: kFluxidiYellow.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  minimumSize: const Size(64, 44),
                ),
                child: Text(
                  _t(
                    nl: 'Boeking bekijken',
                    en: 'View booking',
                    fr: 'Voir la reservation',
                    es: 'Ver reserva',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _cancelFromCard(
    StoredCustomerBooking booking, {
    String? legType,
  }) async {
    final id = booking.canonicalBookingId.trim();
    if (id.isEmpty) return;
    debugPrint(
      '[CUSTOMER_BOOKING_CARD][ACTION] action=cancel booking=${_safeRefPreview(id)} leg=${legType ?? "-"} status=${booking.status.isEmpty ? "-" : booking.status}',
    );
    debugPrint(
      '[CUSTOMER_BOOKING_CANCEL][CARD_ROUTE] booking=${_safeRefPreview(id)} route=detail_pending_action',
    );
    await _openDetails(
      booking,
      pendingAction: kCustomerDetailPendingActionCancel,
      legType: legType,
    );
  }

  Future<void> _openDetails(
    StoredCustomerBooking booking, {
    String? pendingAction,
    String? legType,
  }) async {
    final id = booking.canonicalBookingId.trim();
    if (id.isEmpty) return;
    final aliases = _customerBookingAliasesFromStored(booking);
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => CustomerBookingDetailPage(
          bookingId: id,
          initialView: CustomerBookingView.fromStored(booking),
          startsFromLocalCache: true,
          pendingAction: pendingAction,
          initialLegType: legType,
        ),
      ),
    );
    final action = _customerDetailResultAction(result);
    if (action == _customerDetailResultLegCancelledServer) {
      await _loadLocal(showLoading: false);
      return;
    }
    if (action == _customerDetailResultRemovedLocal ||
        action == _customerDetailResultCancelledServer) {
      _applyCustomerBookingListRemoval(
        aliases: aliases,
        bookingForLog: id,
        action: action!,
      );
      await _loadLocal(showLoading: false);
      if (!mounted) return;
      if (action == _customerDetailResultRemovedLocal) {
        final message = _t(
          nl: 'Boeking verwijderd uit je lokale overzicht.',
          en: 'Booking removed from your local overview.',
          fr: 'Réservation supprimée de votre aperçu local.',
          es: 'Reserva eliminada de tu vista local.',
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }
    await _loadLocal();
  }

  Future<void> _removeFromMyBookings(StoredCustomerBooking booking) async {
    final bookingId = booking.canonicalBookingId.trim();
    if (bookingId.isEmpty) return;
    debugPrint(
      '[CUSTOMER_BOOKING_CARD][ACTION] action=local_hide booking=${_safeRefPreview(bookingId)} status=${booking.status.isEmpty ? "-" : booking.status}',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _t(
            nl: 'Boeking verwijderen?',
            en: 'Remove booking?',
            fr: 'Supprimer la réservation ?',
            es: '¿Eliminar reserva?',
          ),
        ),
        content: Text(
          _t(
            nl: 'Deze boeking wordt alleen uit jouw lokale overzicht verwijderd. De bedrijfsadministratie en ritgeschiedenis blijven bewaard.',
            en: 'This booking will only be removed from your local overview. Company administration and ride history remain stored.',
            fr: 'Cette réservation sera supprimée uniquement de votre aperçu local. L’administration de l’entreprise et l’historique des trajets restent conservés.',
            es: 'Esta reserva solo se eliminará de tu vista local. La administración de la empresa y el historial del viaje se conservan.',
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
                nl: 'Verwijderen',
                en: 'Remove',
                fr: 'Supprimer',
                es: 'Eliminar',
              ),
            ),
          ),
        ],
      ),
    );
    debugPrint(
      '[CUSTOMER_BOOKINGS][DELETE_CONFIRM] action=remove_one confirmed=${confirmed == true} booking=${_safeRefPreview(bookingId)}',
    );
    if (confirmed != true || !mounted) return;
    final aliases = _customerBookingDeleteAliases(
      bookingId: booking.bookingId,
      publicBookingReference: booking.publicBookingReference,
      bookingReference: booking.bookingReference,
      publicReference: booking.publicReference,
      planningReference: booking.planningReference,
      receiptReference: booking.receiptReference,
      paymentBookingId: booking.paymentBookingId,
    );
    _applyCustomerBookingListRemoval(
      aliases: aliases,
      bookingForLog: bookingId,
      action: _customerDetailResultRemovedLocal,
    );
    final result = await _optimisticHideCustomerBookingForCancelOrRemove(
      bookingForLog: bookingId,
      aliases: aliases,
      reason: 'remove',
    );
    await _loadLocal(showLoading: false);
    if (!mounted) return;
    final message = result.removed
        ? _t(
            nl: 'Boeking verwijderd uit je lokale overzicht.',
            en: 'Booking removed from your local overview.',
            fr: 'Réservation supprimée de votre aperçu local.',
            es: 'Reserva eliminada de tu vista local.',
          )
        : _t(
            nl: 'Boeking niet gevonden in lokale opslag.',
            en: 'Booking not found in local storage.',
            fr: 'Réservation introuvable dans le stockage local.',
            es: 'Reserva no encontrada en el almacenamiento local.',
          );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _removeAllFromMyBookings() async {
    debugPrint('[CUSTOMER_BOOKINGS][CLEAR_ALL_REQ]');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _t(
            nl: 'Alle boekingen verwijderen?',
            en: 'Remove all bookings?',
            fr: 'Supprimer toutes les réservations ?',
            es: '¿Eliminar todas las reservas?',
          ),
        ),
        content: Text(
          _t(
            nl: 'Hiermee verwijder je alleen de boekingen uit je lokale overzicht op dit toestel. De bedrijfsadministratie, ritgeschiedenis en betalingen blijven bewaard.',
            en: 'This only removes the bookings from your local overview on this device. Company records, ride history and payments remain stored.',
            fr: 'Cela supprime uniquement les réservations de votre aperçu local sur cet appareil. L’administration, l’historique des trajets et les paiements restent conservés.',
            es: 'Esto solo elimina las reservas de tu vista local en este dispositivo. La administración de la empresa, el historial de viajes y los pagos se conservan.',
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
                nl: 'Alles verwijderen',
                en: 'Remove all',
                fr: 'Tout supprimer',
                es: 'Eliminar todo',
              ),
            ),
          ),
        ],
      ),
    );
    debugPrint(
      '[CUSTOMER_BOOKINGS][DELETE_CONFIRM] action=remove_all confirmed=${confirmed == true} count=${_bookings.length}',
    );
    if (confirmed != true) return;
    try {
      final aliases = <String>{};
      for (final booking in _bookings) {
        aliases.addAll(_customerBookingAliasesFromStored(booking));
      }
      await CustomerBookingsStore.instance.markHiddenByAnyReferenceAliases(
        aliases,
      );
      await CustomerBookingStore.instance.clearLocalTestData();
      if (!mounted) return;
      setState(() {
        _bookings = const <StoredCustomerBooking>[];
        _lastUpdated = DateTime.now();
      });
      await _loadLocal();
      if (!mounted) return;
      debugPrint(
        '[CUSTOMER_BOOKINGS][CLEAR_ALL_OK] remaining=${_bookings.length}',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Alle lokale boekingen zijn verwijderd.',
              en: 'All local bookings have been removed.',
              fr: 'Toutes les réservations locales ont été supprimées.',
              es: 'Todas las reservas locales han sido eliminadas.',
            ),
          ),
        ),
      );
    } catch (err) {
      debugPrint('[CUSTOMER_BOOKINGS][CLEAR_ALL_ERROR] err=$err');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF07080C),
        appBar: AppBar(
          backgroundColor: const Color(0xFF07080C),
          surfaceTintColor: Colors.transparent,
          title: Text(
            _t(
              nl: 'Mijn boekingen',
              en: 'My bookings',
              fr: 'Mes reservations',
              es: 'Mis reservas',
            ),
          ),
          actions: [
            IconButton(
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF111214),
                foregroundColor: kFluxidiYellow.withOpacity(0.98),
                side: BorderSide(color: kFluxidiYellow.withOpacity(0.3)),
              ),
              tooltip: _t(
                nl: 'Vernieuwen',
                en: 'Refresh',
                fr: 'Actualiser',
                es: 'Actualizar',
              ),
              onPressed: _refreshing ? null : _refreshAuthoritative,
              icon: _refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
            const SizedBox(width: 6),
            IconButton(
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF111214),
                foregroundColor: Colors.white.withOpacity(0.9),
                side: BorderSide(color: Colors.white.withOpacity(0.22)),
              ),
              tooltip: _t(
                nl: 'Alles verwijderen',
                en: 'Remove all',
                fr: 'Tout supprimer',
                es: 'Eliminar todo',
              ),
              onPressed: _bookings.isEmpty ? null : _removeAllFromMyBookings,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refreshAuthoritative,
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Text(
                  '${_t(nl: 'Laatst bijgewerkt', en: 'Last updated', fr: 'Derniere mise a jour', es: 'Ultima actualizacion')}: ${_formatLastUpdated()}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.62),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A1114),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFCD5C6C)),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFFFB4B4)),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_bookings.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF121212), Color(0xFF0B0C0E)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: kFluxidiYellow.withOpacity(0.2),
                      ),
                    ),
                    child: Text(
                      _t(
                        nl: 'Geen boekingen gevonden.',
                        en: 'No bookings found.',
                        fr: 'Aucune reservation trouvee.',
                        es: 'No se encontraron reservas.',
                      ),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  )
                else
                  ..._bookings.map(_premiumBookingCard),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.search_outlined),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kFluxidiYellow.withOpacity(0.98),
                      side: BorderSide(color: kFluxidiYellow.withOpacity(0.42)),
                      backgroundColor: const Color(0xFF111214),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CustomerBookingLookupPage(),
                        ),
                      );
                      await _loadLocal();
                    },
                    label: Text(
                      _t(
                        nl: 'Boeking handmatig zoeken',
                        en: 'Find booking manually',
                        fr: 'Rechercher une réservation manuellement',
                        es: 'Buscar reserva manualmente',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<List<StoredCustomerBooking>>
_filterActiveNonHiddenStoredCustomerBookings(
  List<StoredCustomerBooking> items,
) async {
  final visible = <StoredCustomerBooking>[];
  for (final item in items) {
    if (!_isActiveCustomerLifecycleStatus(item.status)) continue;
    final aliases = _customerBookingAliasesFromStored(item);
    if (await CustomerBookingsStore.instance.isAnyReferenceAliasHidden(
      aliases,
    )) {
      continue;
    }
    visible.add(item);
  }
  return visible;
}

Future<List<CustomerSavedBooking>> _filterActiveNonHiddenSavedCustomerBookings(
  List<CustomerSavedBooking> items,
) async {
  final visible = <CustomerSavedBooking>[];
  for (final item in items) {
    if (!_isActiveCustomerLifecycleStatus(item.bookingStatus)) continue;
    final aliases = _customerBookingDeleteAliases(
      bookingId: item.bookingId,
      publicBookingReference: item.publicReference,
      bookingReference: item.publicReference,
      publicReference: item.publicReference,
      source: item.rawSnapshot,
    );
    if (await CustomerBookingsStore.instance.isAnyReferenceAliasHidden(
      aliases,
    )) {
      continue;
    }
    visible.add(item);
  }
  return visible;
}

Future<({bool removed, bool storeA, bool storeB, int remaining})>
_optimisticHideCustomerBookingForCancelOrRemove({
  required String bookingForLog,
  required Set<String> aliases,
  required String reason,
}) async {
  final tag = reason == 'remove'
      ? '[CUSTOMER_BOOKING_REMOVE][OPTIMISTIC_HIDE]'
      : '[CUSTOMER_BOOKING_CANCEL][OPTIMISTIC_HIDE]';
  debugPrint(
    '$tag booking=${_safeRefPreview(bookingForLog)} aliases=${aliases.length}',
  );
  await CustomerBookingsStore.instance.markHiddenByAnyReferenceAliases(aliases);
  final activeResult = await CustomerBookingsStore.instance
      .removeByAnyReferenceAliases(aliases);
  final crossScopeResult = await CustomerBookingsStore.instance
      .removeByAnyReferenceAliasesAcrossKnownCustomerScopesForDisplayOnly(
        aliases,
      );
  final removed = activeResult.removed || crossScopeResult.removed;
  debugPrint(
    '[CUSTOMER_BOOKING][HIDE_PERSIST] booking=${_safeRefPreview(bookingForLog)} activeRemoved=${activeResult.removedCount} crossRemoved=${crossScopeResult.removedCount}',
  );
  return (
    removed: removed,
    storeA: activeResult.removed,
    storeB: crossScopeResult.removed,
    remaining: activeResult.remaining,
  );
}

class _CustomerBookingCardActionsLayout extends StatelessWidget {
  const _CustomerBookingCardActionsLayout({required this.children});

  final List<Widget> children;

  static const double _stackBreakpoint = 520;
  static const double _gap = 9;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackVertically = constraints.maxWidth < _stackBreakpoint;
        if (stackVertically) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: _gap),
                SizedBox(width: double.infinity, child: children[i]),
              ],
            ],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              children[i],
            ],
          ],
        );
      },
    );
  }
}
