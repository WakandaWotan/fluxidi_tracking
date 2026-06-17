part of '../main.dart';

class CustomerSavedBookingsPage extends StatefulWidget {
  const CustomerSavedBookingsPage({super.key});

  @override
  State<CustomerSavedBookingsPage> createState() =>
      _CustomerSavedBookingsPageState();
}

class _CustomerSavedBookingsPageState extends State<CustomerSavedBookingsPage> {
  bool _loading = true;
  String? _error;
  List<CustomerSavedBooking> _bookings = const <CustomerSavedBooking>[];
  Map<String, String> _paymentOverlayByBookingId = const <String, String>{};
  // G3-N: see customer_bookings_page.dart for rationale.
  final Set<String> _optimisticallyPaidBookingIds = <String>{};
  CustomerThemePalette get _palette =>
      paletteForCustomerTheme(customerThemeNotifier.value);
  bool get _isDarkTheme => _palette.isDark;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void initState() {
    super.initState();
    unawaited(_loadLocal());
    fluxidiPendingPaymentNotifier.addListener(
      _onPendingPaymentNotifierChangedForCustomerSavedList,
    );
  }

  @override
  void dispose() {
    fluxidiPendingPaymentNotifier.removeListener(
      _onPendingPaymentNotifierChangedForCustomerSavedList,
    );
    super.dispose();
  }

  // G3-N: pending-payment notifier hook. Same semantics as the active-list
  // page; we optimistically mark the matching saved booking as paid so the
  // UI does not flash "Pay in car" after a successful resumed Mollie
  // payment. We do not write to the saved-bookings store from here; the
  // background re-load via _loadLocal() picks up the canonical state.
  void _onPendingPaymentNotifierChangedForCustomerSavedList() {
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
    CustomerSavedBooking? matched;
    for (final booking in _bookings) {
      final aliases = _overlayAliasesForSavedBooking(booking);
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
      if (canonicalHit.isNotEmpty && booking.bookingId.trim() == canonicalHit) {
        matched = booking;
        break;
      }
    }
    if (matched == null) return;
    final bookingId = matched.bookingId.trim();
    if (bookingId.isEmpty) return;
    if (_optimisticallyPaidBookingIds.contains(bookingId)) return;
    debugPrint(
      '[CUSTOMER_BOOKINGS][PAYMENT_STATUS_PATCHED] booking=${_safeRefPreview(bookingId)} paymentBooking=${_safeRefPreview(paymentBookingIdHit)} from=${matched.paymentStatus.isEmpty ? "-" : matched.paymentStatus} to=paid source=saved_list_notifier',
    );
    debugPrint(
      '[PAYMENT_RETURN][CUSTOMER_REFRESH] surface=saved_list booking=${_safeRefPreview(bookingId)} paymentBooking=${_safeRefPreview(paymentBookingIdHit)} status=${pending.status.name}',
    );
    setState(() {
      _optimisticallyPaidBookingIds.add(bookingId);
    });
    if (!_loading) {
      unawaited(_loadLocal());
    }
  }

  Future<void> _loadLocal({
    bool showLoading = true,
    bool runBootstrap = true,
  }) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      if (runBootstrap) {
        await _bootstrapCustomerSessionAndMergeBookings(
          reason: 'customer_saved_bookings',
        );
      }
      final items = await CustomerBookingStore.instance.loadAll();
      final visible = await _filterActiveNonHiddenSavedCustomerBookings(items);
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
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        if (showLoading) {
          _loading = false;
        }
        _paymentOverlayByBookingId = const <String, String>{};
        _error = _t(
          nl: 'Laden mislukt.',
          en: 'Loading failed.',
          fr: 'Chargement echoue.',
          es: 'Error al cargar.',
        );
      });
    }
  }

  void _applySavedBookingListRemoval({
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
              _aliasesForSavedBooking(item),
              aliases,
            ),
          )
          .toList(growable: false);
    });
    debugPrint(
      '[CUSTOMER_BOOKING_CANCEL][LIST_APPLY_RESULT] action=$action booking=${_safeRefPreview(bookingForLog)} aliases=${aliases.length} before=$beforeCount after=${_bookings.length}',
    );
  }

  Set<String> _aliasesForSavedBooking(CustomerSavedBooking booking) {
    return _customerBookingDeleteAliases(
      bookingId: booking.bookingId,
      publicBookingReference: booking.publicReference,
      bookingReference: booking.publicReference,
      publicReference: booking.publicReference,
      source: booking.rawSnapshot,
    );
  }

  Map<String, String> _savedBookingScopeQuery(CustomerSavedBooking booking) {
    final tenantFromBooking = booking.tenantId.trim();
    final companyFromBooking = booking.companyId.trim();
    if (tenantFromBooking.isNotEmpty && companyFromBooking.isNotEmpty) {
      return <String, String>{
        'tenant_id': tenantFromBooking,
        'company_id': companyFromBooking,
        'tenantId': tenantFromBooking,
        'companyId': companyFromBooking,
      };
    }
    final tenantFromRaw =
        (booking.rawSnapshot['tenant_id'] ??
                booking.rawSnapshot['tenantId'] ??
                '')
            .toString()
            .trim();
    final companyFromRaw =
        (booking.rawSnapshot['company_id'] ??
                booking.rawSnapshot['companyId'] ??
                '')
            .toString()
            .trim();
    if (tenantFromRaw.isNotEmpty && companyFromRaw.isNotEmpty) {
      return <String, String>{
        'tenant_id': tenantFromRaw,
        'company_id': companyFromRaw,
        'tenantId': tenantFromRaw,
        'companyId': companyFromRaw,
      };
    }
    return _activeBookingScopeQuery();
  }

  String _formatPickup(String iso) {
    if (iso.trim().isEmpty) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    String two(int n) => n.toString().padLeft(2, '0');
    final local = dt.toLocal();
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String _formatPrice(CustomerSavedBooking booking) {
    final amount =
        _savedBookingView(booking).customerDisplayCardAmount ?? booking.price;
    if (amount == null) return '-';
    final currency = booking.currency.toUpperCase().trim();
    final symbol = currency.isEmpty || currency == 'EUR' ? '€' : '$currency ';
    return '$symbol${amount.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  CustomerBookingView _savedBookingView(CustomerSavedBooking booking) {
    final snapshotQuote = booking.rawSnapshot['quote'];
    final quote = snapshotQuote is Map
        ? Map<String, dynamic>.from(snapshotQuote)
        : Map<String, dynamic>.from(booking.rawSnapshot);
    return CustomerBookingView.fromStored(
      StoredCustomerBooking(
        bookingId: booking.bookingId,
        from: booking.from,
        to: booking.to,
        pickupIso: booking.pickupIso,
        price: booking.price,
        currency: booking.currency,
        paymentStatus: booking.paymentStatus,
        status: booking.bookingStatus,
        quote: quote,
      ),
    );
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

  Widget? _roundtripCancelledLegChip(CustomerSavedBooking booking) {
    final token = _savedBookingView(booking).roundtripCancelledLegChipToken;
    if (token == null) return null;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: _palette.gold.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _palette.gold.withOpacity(0.35)),
      ),
      child: Text(
        _roundtripCancelledLegChipLabel(token),
        style: TextStyle(
          color: _palette.gold.withOpacity(0.95),
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

  String _formatCardAmount(double? amount, String currency) {
    if (amount == null) return '-';
    final normalizedCurrency = currency.toUpperCase().trim();
    final symbol = normalizedCurrency.isEmpty || normalizedCurrency == 'EUR'
        ? '€'
        : '$normalizedCurrency ';
    return '$symbol${amount.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  Widget _roundtripLegCard({
    required CustomerSavedBooking booking,
    required CustomerRoundtripLegCardView leg,
  }) {
    final statusColor = leg.isCancelled ? _palette.bronze : _palette.gold;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _palette.surfaceAlt.withOpacity(_palette.isDark ? 0.48 : 0.72),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _palette.border.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _roundtripLegTitle(leg.legType),
                style: TextStyle(
                  color: _palette.textPrimary,
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
                  border: Border.all(color: statusColor.withOpacity(0.34)),
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
                  color: _palette.gold.withOpacity(0.96),
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
              color: _palette.textMuted.withOpacity(0.9),
              fontSize: 11.1,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (leg.isActive)
                OutlinedButton(
                  onPressed: () =>
                      _cancelSavedFromCard(booking, legType: leg.legType),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _palette.danger.withOpacity(0.95),
                    side: BorderSide(color: _palette.danger.withOpacity(0.45)),
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
                onPressed: () =>
                    _openSavedBooking(booking, legType: leg.legType),
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

  String _displayPaymentStatusToken(CustomerSavedBooking booking) {
    final channel = _customerPaymentChannelFieldsFromSavedBooking(booking);
    final bookingId = booking.bookingId.trim();
    String token;
    if (bookingId.isNotEmpty &&
        _paymentOverlayByBookingId.containsKey(bookingId)) {
      token = _classifyCustomerPaymentDisplayToken(
        aliases: _overlayAliasesForSavedBooking(booking),
        fallbackToken: _paymentOverlayByBookingId[bookingId]!,
        paymentProvider: channel.provider,
        paymentMode: channel.mode,
        paymentMethod: channel.method,
      );
    } else {
      token = _classifyCustomerPaymentDisplayToken(
        aliases: _overlayAliasesForSavedBooking(booking),
        fallbackToken: booking.paymentStatus,
        paymentProvider: channel.provider,
        paymentMode: channel.mode,
        paymentMethod: channel.method,
      );
    }
    if (bookingId.isNotEmpty &&
        _optimisticallyPaidBookingIds.contains(bookingId) &&
        !_isPaidCustomerPaymentDisplayToken(token)) {
      debugPrint(
        '[CUSTOMER_BOOKINGS][STALE_PAYMENT_LABEL_GUARD] booking=${_safeRefPreview(bookingId)} backendToken=$token overrideTo=paid surface=saved_list',
      );
      return 'paid';
    }
    return token;
  }

  bool _displayPaymentKnownPaid(CustomerSavedBooking booking) {
    final token = _displayPaymentStatusToken(booking);
    return _isPaidCustomerPaymentDisplayToken(token);
  }

  Set<String> _overlayAliasesForSavedBooking(CustomerSavedBooking booking) {
    final aliases = <String>{};
    void addAlias(String value) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty) return;
      aliases.add(normalized);
    }

    for (final alias in _aliasesForSavedBooking(booking)) {
      addAlias(alias);
    }
    addAlias(booking.bookingId);
    addAlias(booking.publicReference);
    addAlias((booking.rawSnapshot['parent_booking_id'] ?? '').toString());
    addAlias((booking.rawSnapshot['parentBookingId'] ?? '').toString());
    addAlias((booking.rawSnapshot['original_booking_id'] ?? '').toString());
    addAlias((booking.rawSnapshot['originalBookingId'] ?? '').toString());
    addAlias((booking.rawSnapshot['booking_id'] ?? '').toString());
    addAlias((booking.rawSnapshot['bookingId'] ?? '').toString());
    addAlias((booking.rawSnapshot['public_booking_id'] ?? '').toString());
    addAlias((booking.rawSnapshot['publicBookingId'] ?? '').toString());
    addAlias(
      (booking.rawSnapshot['public_booking_reference'] ?? '').toString(),
    );
    addAlias((booking.rawSnapshot['publicBookingReference'] ?? '').toString());
    addAlias((booking.rawSnapshot['booking_reference'] ?? '').toString());
    addAlias((booking.rawSnapshot['bookingReference'] ?? '').toString());
    addAlias((booking.rawSnapshot['public_reference'] ?? '').toString());
    addAlias((booking.rawSnapshot['publicReference'] ?? '').toString());
    addAlias((booking.rawSnapshot['planning_reference'] ?? '').toString());
    addAlias((booking.rawSnapshot['planningReference'] ?? '').toString());
    addAlias((booking.rawSnapshot['payment_booking_id'] ?? '').toString());
    addAlias((booking.rawSnapshot['paymentBookingId'] ?? '').toString());
    return aliases;
  }

  Future<Map<String, String>> _buildPaymentOverlayForBookings(
    List<CustomerSavedBooking> bookings, {
    required String source,
  }) async {
    if (bookings.isEmpty) return const <String, String>{};

    String tenantId = '';
    String companyId = '';
    var scopeSource = 'missing';

    for (final booking in bookings) {
      final bookingTenant = booking.tenantId.trim();
      final bookingCompany = booking.companyId.trim();
      if (bookingTenant.isNotEmpty && bookingCompany.isNotEmpty) {
        tenantId = bookingTenant;
        companyId = bookingCompany;
        scopeSource = 'booking_list_scope';
        break;
      }
      final rawTenant =
          (booking.rawSnapshot['tenant_id'] ??
                  booking.rawSnapshot['tenantId'] ??
                  '')
              .toString()
              .trim();
      final rawCompany =
          (booking.rawSnapshot['company_id'] ??
                  booking.rawSnapshot['companyId'] ??
                  '')
              .toString()
              .trim();
      if (rawTenant.isNotEmpty && rawCompany.isNotEmpty) {
        tenantId = rawTenant;
        companyId = rawCompany;
        scopeSource = 'raw_booking_scope';
        break;
      }
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
      '[CUSTOMER_SAVED_BOOKINGS][PAYMENT_OVERLAY][SCOPE] source=$scopeSource tenant=${_maskLocalScopeId(tenantId)} company=${_maskLocalScopeId(companyId)}',
    );

    if (tenantId.isEmpty || companyId.isEmpty) {
      debugPrint(
        '[CUSTOMER_SAVED_BOOKINGS][PAYMENT_OVERLAY][WARN] status=skip reason=missing_scope source=$source',
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
      diagTag: 'CUSTOMER_SAVED_BOOKINGS',
      limit: 200,
    );
    final matcher = _TrackingPaymentOverlayMatcher(trips);
    final overlay = <String, String>{};
    var matchedParents = 0;
    var partial = 0;
    var paid = 0;

    for (final booking in bookings) {
      final bookingId = booking.bookingId.trim();
      if (bookingId.isEmpty) continue;
      final aliases = _overlayAliasesForSavedBooking(booking);
      final aggregate = matcher.aggregateOperationalLegsForParentAliases(
        aliases,
      );
      final channel = _customerPaymentChannelFieldsFromSavedBooking(booking);
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
        final ref = booking.publicReference.trim().isNotEmpty
            ? booking.publicReference.trim()
            : bookingId;
        debugPrint(
          '[CUSTOMER_SAVED_BOOKINGS][PAYMENT_OVERLAY][KEYS] ref=${_safeRefPreview(ref)} keys=$keys matched=${aggregate.totalLegs}',
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
      '[CUSTOMER_SAVED_BOOKINGS][PAYMENT_OVERLAY] bookings=${bookings.length} matchedParents=$matchedParents partial=$partial paid=$paid',
    );
    return overlay;
  }

  String _paymentLabel(CustomerSavedBooking booking) {
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
        p == 'pending' ||
        p == 'unpaid' ||
        p == 'pay_in_car') {
      return _t(
        nl: 'Te betalen in de wagen',
        en: 'Pay in the car',
        fr: 'À payer dans le véhicule',
        es: 'Pagar en el vehículo',
      );
    }
    return p.isEmpty
        ? '-'
        : _t(nl: 'Onbekend', en: 'Unknown', fr: 'Inconnu', es: 'Desconocido');
  }

  String _bookingStatusLabel(CustomerSavedBooking booking) {
    final status = _normalizeCustomerLifecycleStatus(booking.bookingStatus);
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

  Color _savedStatusColor(CustomerSavedBooking booking) {
    switch (_normalizeCustomerLifecycleStatus(booking.bookingStatus)) {
      case 'CONFIRMED':
        return _palette.gold;
      case 'COMPLETED':
        return _palette.gold;
      case 'PENDING':
        return _palette.gold;
      case 'CANCELLED':
        return _palette.bronze;
      default:
        return _palette.textMuted;
    }
  }

  Widget _savedPremiumBookingCard(CustomerSavedBooking booking) {
    final palette = _palette;
    final isDark = palette.isDark;
    final cardGradientColors = isDark
        ? <Color>[palette.surface, palette.surfaceAlt, palette.background]
        : <Color>[palette.surface, palette.surfaceAlt, palette.surface];
    final cardBorderColor = isDark
        ? palette.gold.withOpacity(0.24)
        : palette.border.withOpacity(0.9);
    final cardShadowColor = isDark
        ? Colors.black.withOpacity(0.28)
        : palette.shadow.withOpacity(0.22);
    final primaryTextColor = isDark ? Colors.white : palette.textPrimary;
    final secondaryTextColor = isDark
        ? Colors.white.withOpacity(0.86)
        : palette.textMuted;
    final tertiaryTextColor = isDark
        ? Colors.white.withOpacity(0.66)
        : palette.textMuted.withOpacity(0.86);
    final statusColor = _savedStatusColor(booking);
    final paid = _displayPaymentKnownPaid(booking);
    final isTerminal = _isCustomerBookingTerminalStatus(booking.bookingStatus);
    final reference = booking.publicReference.trim().isNotEmpty
        ? booking.publicReference.trim()
        : booking.bookingId.trim();
    final hasIdentity =
        reference.isNotEmpty || booking.bookingStatus.trim().isNotEmpty;
    final hasFrom = booking.from.trim().isNotEmpty;
    final hasTo = booking.to.trim().isNotEmpty;
    final hasPrice = booking.price != null;
    final cancelledLegChip = _roundtripCancelledLegChip(booking);
    final roundtripLegs = _savedBookingView(booking).roundtripLegCardViews;
    final showPartialLoading = hasIdentity && (!hasFrom || !hasTo || !hasPrice);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: cardGradientColors,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorderColor),
        boxShadow: [
          BoxShadow(
            color: cardShadowColor,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openSavedBooking(booking),
        child: Padding(
          padding: const EdgeInsets.all(12),
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
                      _bookingStatusLabel(booking),
                      style: TextStyle(
                        color: statusColor.withOpacity(0.98),
                        fontSize: 11.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (!showPartialLoading || hasPrice)
                    Text(
                      _formatPrice(booking),
                      style: TextStyle(
                        color: palette.gold.withOpacity(0.98),
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
                  color: secondaryTextColor,
                  fontSize: 12.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (cancelledLegChip != null) cancelledLegChip,
              if (showPartialLoading) ...[
                const SizedBox(height: 8),
                Text(
                  _t(
                    nl: 'Boekingsgegevens laden...',
                    en: 'Loading booking details...',
                    fr: 'Chargement des détails de réservation...',
                    es: 'Cargando detalles de la reserva...',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tertiaryTextColor, fontSize: 11.4),
                ),
              ] else ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Icon(
                          Icons.radio_button_checked,
                          size: 11.5,
                          color: palette.gold.withOpacity(0.94),
                        ),
                        Container(
                          width: 1.8,
                          height: 30,
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          color: palette.gold.withOpacity(0.35),
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
                            booking.from,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: primaryTextColor,
                              fontSize: 12.8,
                              fontWeight: FontWeight.w600,
                              height: 1.24,
                            ),
                          ),
                          const SizedBox(height: 15),
                          Text(
                            booking.to,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: secondaryTextColor,
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
              ],
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
                      color: paid
                          ? (isDark
                                ? palette.surfaceAlt.withOpacity(0.9)
                                : palette.surfaceAlt.withOpacity(0.95))
                          : palette.gold.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: paid
                            ? palette.gold.withOpacity(0.45)
                            : palette.gold.withOpacity(0.35),
                      ),
                    ),
                    child: Text(
                      _paymentLabel(booking),
                      style: TextStyle(
                        color: paid
                            ? palette.bronze.withOpacity(0.98)
                            : palette.gold.withOpacity(0.97),
                        fontSize: 11.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${_t(nl: 'Ref', en: 'Ref', fr: 'Ref', es: 'Ref')}: $reference',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tertiaryTextColor, fontSize: 10.8),
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
                      onPressed: () => _removeSavedFromMyBookings(booking),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryTextColor.withOpacity(0.9),
                        side: BorderSide(
                          color: palette.border.withOpacity(0.6),
                        ),
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
                      onPressed: () => _cancelSavedFromCard(booking),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.danger.withOpacity(0.95),
                        side: BorderSide(
                          color: palette.danger.withOpacity(0.55),
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
                    onPressed: () => _openSavedBooking(booking),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.gold.withOpacity(0.97),
                      side: BorderSide(color: palette.gold.withOpacity(0.4)),
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
        ),
      ),
    );
  }

  Future<void> _cancelSavedFromCard(
    CustomerSavedBooking booking, {
    String? legType,
  }) async {
    final id = booking.bookingId.trim();
    if (id.isEmpty) return;
    debugPrint(
      '[CUSTOMER_BOOKING_CARD][ACTION] action=cancel booking=${_safeRefPreview(id)} leg=${legType ?? "-"} status=${booking.bookingStatus.isEmpty ? "-" : booking.bookingStatus}',
    );
    debugPrint(
      '[CUSTOMER_BOOKING_CANCEL][CARD_ROUTE] booking=${_safeRefPreview(id)} route=detail_pending_action',
    );
    await _openSavedBooking(
      booking,
      pendingAction: kCustomerDetailPendingActionCancel,
      legType: legType,
    );
  }

  Future<void> _removeSavedFromMyBookings(CustomerSavedBooking booking) async {
    final bookingId = booking.bookingId.trim();
    if (bookingId.isEmpty) return;
    debugPrint(
      '[CUSTOMER_BOOKING_CARD][ACTION] action=local_hide booking=${_safeRefPreview(bookingId)} status=${booking.bookingStatus.isEmpty ? "-" : booking.bookingStatus}',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _t(
            nl: 'Boeking verwijderen?',
            en: 'Remove booking?',
            fr: 'Supprimer la reservation ?',
            es: '¿Eliminar reserva?',
          ),
        ),
        content: Text(
          _t(
            nl: 'Deze boeking wordt alleen uit jouw lokale overzicht verwijderd. De bedrijfsadministratie en ritgeschiedenis blijven bewaard.',
            en: 'This booking will only be removed from your local overview. Company administration and ride history remain stored.',
            fr: 'Cette reservation sera supprimee uniquement de votre apercu local. L administration et l historique des trajets restent conserves.',
            es: 'Esta reserva solo se eliminara de tu vista local. La administracion de la empresa y el historial de viajes se conservan.',
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
    if (confirmed != true || !mounted) return;
    final aliases = _aliasesForSavedBooking(booking);
    _applySavedBookingListRemoval(
      aliases: aliases,
      bookingForLog: bookingId,
      action: _customerDetailResultRemovedLocal,
    );
    final result = await _optimisticHideCustomerBookingForCancelOrRemove(
      bookingForLog: bookingId,
      aliases: aliases,
      reason: 'remove',
    );
    await _loadLocal(showLoading: false, runBootstrap: false);
    if (!mounted) return;
    final message = result.removed
        ? _t(
            nl: 'Boeking verwijderd uit je lokale overzicht.',
            en: 'Booking removed from your local overview.',
            fr: 'Reservation supprimee de votre apercu local.',
            es: 'Reserva eliminada de tu vista local.',
          )
        : _t(
            nl: 'Boeking niet gevonden in lokale opslag.',
            en: 'Booking not found in local storage.',
            fr: 'Reservation introuvable dans le stockage local.',
            es: 'Reserva no encontrada en el almacenamiento local.',
          );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openSavedBooking(
    CustomerSavedBooking booking, {
    String? pendingAction,
    String? legType,
  }) async {
    final id = booking.bookingId.trim();
    if (id.isEmpty) return;
    final beforeCount = _bookings.length;
    final aliases = _aliasesForSavedBooking(booking);
    try {
      final proof = await _customerOwnershipProof(
        bookingId: id,
        aliases: aliases,
        source: booking.rawSnapshot,
      );
      final scope = _savedBookingScopeQuery(booking);
      final uri =
          Uri.parse(
            '$kBookingBaseUrl/bookings/${Uri.encodeComponent(id)}',
          ).replace(
            queryParameters: <String, String>{
              ...scope,
              if (proof.isNotEmpty) ...proof,
            },
          );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, dynamic> && decoded['ok'] == true) {
          final view = CustomerBookingView.fromResponse(id, decoded);
          if (!mounted) return;
          final result = await Navigator.of(context).push<dynamic>(
            MaterialPageRoute(
              builder: (_) => CustomerBookingDetailPage(
                bookingId: id,
                initialView: view,
                startsFromLocalCache: false,
                pendingAction: pendingAction,
                initialLegType: legType,
              ),
            ),
          );
          final action = _customerDetailResultAction(result);
          if (action == _customerDetailResultRemovedLocal ||
              action == _customerDetailResultCancelledServer) {
            _applySavedBookingListRemoval(
              aliases: aliases,
              bookingForLog: id,
              action: action!,
            );
            await _loadLocal(showLoading: false, runBootstrap: false);
          }
          if (mounted) {
            debugPrint(
              '[CUSTOMER_BOOKINGS][DETAIL_RETURN] action=${action ?? "-"} beforeCount=$beforeCount afterCount=${_bookings.length}',
            );
          }
          return;
        }
      }
    } catch (_) {
      // fall back to local-safe minimal view
    }

    final fallback = StoredCustomerBooking(
      bookingId: id,
      tenantId: booking.tenantId,
      companyId: booking.companyId,
      publicBookingId: booking.publicReference.trim().isNotEmpty
          ? booking.publicReference.trim()
          : id,
      customerName: '',
      customerPhone: '',
      customerEmail: '',
      from: booking.from,
      to: booking.to,
      pickupIso: booking.pickupIso,
      price: booking.price,
      currency: booking.currency,
      paymentStatus: booking.paymentStatus,
      status: booking.bookingStatus,
      createdAt: booking.createdAt,
      updatedAt: booking.createdAt,
    );
    if (!mounted) return;
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => CustomerBookingDetailPage(
          bookingId: id,
          initialView: CustomerBookingView.fromStored(fallback),
          startsFromLocalCache: true,
          pendingAction: pendingAction,
          initialLegType: legType,
        ),
      ),
    );
    final action = _customerDetailResultAction(result);
    if (action == _customerDetailResultLegCancelledServer) {
      await _loadLocal(showLoading: false, runBootstrap: false);
      if (mounted) {
        debugPrint(
          '[CUSTOMER_BOOKINGS][DETAIL_RETURN] action=$action beforeCount=$beforeCount afterCount=${_bookings.length}',
        );
      }
      return;
    }
    if (action == _customerDetailResultRemovedLocal ||
        action == _customerDetailResultCancelledServer) {
      _applySavedBookingListRemoval(
        aliases: aliases,
        bookingForLog: id,
        action: action!,
      );
      await _loadLocal(showLoading: false, runBootstrap: false);
    }
    if (mounted) {
      debugPrint(
        '[CUSTOMER_BOOKINGS][DETAIL_RETURN] action=${action ?? "-"} beforeCount=$beforeCount afterCount=${_bookings.length}',
      );
    }
  }

  Future<void> _clearAllLocalBookings() async {
    debugPrint('[CUSTOMER_BOOKINGS][CLEAR_ALL_REQ] count=${_bookings.length}');
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
      '[CUSTOMER_BOOKINGS][DELETE_CONFIRM] action=clear_all confirmed=${confirmed == true} count=${_bookings.length}',
    );
    if (confirmed != true) return;
    try {
      final aliases = <String>{};
      for (final booking in _bookings) {
        aliases.addAll(_aliasesForSavedBooking(booking));
      }
      await CustomerBookingsStore.instance.markHiddenByAnyReferenceAliases(
        aliases,
      );
      await CustomerBookingsStore.instance
          .removeByAnyReferenceAliasesAcrossKnownCustomerScopesForDisplayOnly(
            aliases,
          );
      if (!mounted) return;
      setState(() {
        _bookings = const <CustomerSavedBooking>[];
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
    return ValueListenableBuilder<CustomerThemeVariant>(
      valueListenable: customerThemeNotifier,
      builder: (context, themeVariant, __) {
        final palette = paletteForCustomerTheme(themeVariant);
        final isDark = palette.isDark;
        final appBarForeground = isDark ? Colors.white : palette.textPrimary;
        final appBarBackground = palette.background;
        final scaffoldBackground = palette.background;
        final mutedTextColor = isDark ? Colors.white70 : palette.textMuted;
        final emptyStateBg = isDark ? const Color(0xFF141B2F) : palette.surface;
        final emptyStateBorder = isDark
            ? palette.gold.withOpacity(0.18)
            : palette.border.withOpacity(0.92);
        final searchButtonForeground = palette.gold.withOpacity(0.98);
        final searchButtonBackground = isDark
            ? const Color(0xFF111214)
            : palette.surfaceAlt;
        final searchButtonBorder = isDark
            ? palette.gold.withOpacity(0.42)
            : palette.border.withOpacity(0.95);
        return ValueListenableBuilder<AppLanguage>(
          valueListenable: appLanguageNotifier,
          builder: (context, _, __) {
            debugPrint(
              '[CUSTOMER_BOOKINGS][VISIBLE_BUILD] count=${_bookings.length}',
            );
            return Scaffold(
              backgroundColor: scaffoldBackground,
              appBar: AppBar(
                backgroundColor: appBarBackground,
                foregroundColor: appBarForeground,
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
                    tooltip: _t(
                      nl: 'Alles verwijderen',
                      en: 'Remove all',
                      fr: 'Tout supprimer',
                      es: 'Eliminar todo',
                    ),
                    onPressed: _bookings.isEmpty
                        ? null
                        : _clearAllLocalBookings,
                    icon: const Icon(Icons.delete_sweep),
                  ),
                  IconButton(
                    tooltip: _t(
                      nl: 'Vernieuwen',
                      en: 'Refresh',
                      fr: 'Actualiser',
                      es: 'Actualizar',
                    ),
                    onPressed: _loadLocal,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: palette.danger.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: palette.danger.withOpacity(0.4),
                          ),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Color(0xFFFFB4B4)),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
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
                          color: emptyStateBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: emptyStateBorder),
                        ),
                        child: Text(
                          _t(
                            nl: 'Nog geen boekingen op dit toestel.',
                            en: 'No bookings on this device yet.',
                            fr: 'Aucune réservation sur cet appareil pour le moment.',
                            es: 'Aún no hay reservas en este dispositivo.',
                          ),
                          style: TextStyle(color: mutedTextColor),
                        ),
                      )
                    else
                      ..._bookings.map(_savedPremiumBookingCard),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.search_outlined),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: searchButtonForeground,
                          backgroundColor: searchButtonBackground,
                          side: BorderSide(color: searchButtonBorder),
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CustomerBookingLookupPage(),
                          ),
                        ),
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
            );
          },
        );
      },
    );
  }
}
