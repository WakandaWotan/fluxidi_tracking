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
  }

  Future<void> _loadLocal() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _bootstrapCustomerSessionAndMergeBookings(
        reason: 'customer_saved_bookings',
      );
      final items = await CustomerBookingStore.instance.loadAll();
      final visible = items
          .where((item) => _isActiveCustomerLifecycleStatus(item.bookingStatus))
          .toList(growable: false);
      if (!mounted) return;
      final overlay = await _buildPaymentOverlayForBookings(
        visible,
        source: 'load_local',
      );
      if (!mounted) return;
      setState(() {
        _bookings = visible;
        _paymentOverlayByBookingId = overlay;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
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
    final amount = booking.price;
    if (amount == null) return '-';
    final currency = booking.currency.toUpperCase().trim();
    final symbol = currency.isEmpty || currency == 'EUR' ? '€' : '$currency ';
    return '$symbol${amount.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _displayPaymentStatusToken(CustomerSavedBooking booking) {
    final bookingId = booking.bookingId.trim();
    if (bookingId.isNotEmpty &&
        _paymentOverlayByBookingId.containsKey(bookingId)) {
      return _classifyCustomerPaymentDisplayToken(
        aliases: _overlayAliasesForSavedBooking(booking),
        fallbackToken: _paymentOverlayByBookingId[bookingId]!,
      );
    }
    return _classifyCustomerPaymentDisplayToken(
      aliases: _overlayAliasesForSavedBooking(booking),
      fallbackToken: booking.paymentStatus,
    );
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
      final token = _classifyCustomerPaymentDisplayToken(
        aliases: aliases,
        fallbackToken: booking.paymentStatus,
        matcher: matcher,
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
    if (p == 'pending' || p == 'unpaid' || p == 'pay_in_car') {
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
    final reference = booking.publicReference.trim().isNotEmpty
        ? booking.publicReference.trim()
        : booking.bookingId.trim();
    final hasIdentity =
        reference.isNotEmpty || booking.bookingStatus.trim().isNotEmpty;
    final hasFrom = booking.from.trim().isNotEmpty;
    final hasTo = booking.to.trim().isNotEmpty;
    final hasPrice = booking.price != null;
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
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSavedBooking(CustomerSavedBooking booking) async {
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
              ),
            ),
          );
          final action = _customerDetailResultAction(result);
          if (action == _customerDetailResultRemovedLocal ||
              action == _customerDetailResultCancelledServer) {
            if (mounted) {
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
            }
            await _loadLocal();
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
        ),
      ),
    );
    final action = _customerDetailResultAction(result);
    if (action == _customerDetailResultRemovedLocal ||
        action == _customerDetailResultCancelledServer) {
      if (mounted) {
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
      }
      await _loadLocal();
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
