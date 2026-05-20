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

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  Future<void> _loadLocal() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await CustomerBookingsStore.instance.loadAll();
      final visible = items
          .where((item) => _isActiveCustomerLifecycleStatus(item.status))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _bookings = visible;
        _loading = false;
        _lastUpdated = DateTime.now();
      });
      debugPrint(
        '[CUSTOMER_BOOKINGS][RELOAD_AFTER_DELETE] count=${visible.length}',
      );
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
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
            _hydrateStoredCustomerBookingFromView(
              stored: stored,
              view: authoritativeView,
              source: 'customer_list_refresh',
            ),
          );
        } catch (_) {
          // Keep refresh resilient: skip individual booking failures.
        }
      }
      final refreshed = await CustomerBookingsStore.instance.loadAll();
      final visible = refreshed
          .where((item) => _isActiveCustomerLifecycleStatus(item.status))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _bookings = visible;
        _refreshing = false;
        _lastUpdated = DateTime.now();
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
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

  String _formatPickup(String iso) {
    if (iso.trim().isEmpty) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String _formatPrice(StoredCustomerBooking booking) {
    final amount = booking.price;
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
    final p = booking.paymentStatus.toLowerCase().trim();
    if (p == 'paid' || p == 'confirmed' || p == 'success' || p == 'completed') {
      return _t(nl: 'Betaald', en: 'Paid', fr: 'Paye', es: 'Pagado');
    }
    if (p == 'unpaid' || p == 'pending' || p == 'pay_in_car') {
      return _t(
        nl: 'Te betalen in de wagen',
        en: 'To pay in the vehicle',
        fr: 'A payer dans le vehicule',
        es: 'A pagar en el vehiculo',
      );
    }
    return _t(
      nl: 'Te betalen in de wagen',
      en: 'To pay in the vehicle',
      fr: 'A payer dans le vehicule',
      es: 'A pagar en el vehiculo',
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

  Widget _premiumBookingCard(StoredCustomerBooking booking) {
    final statusColor = _statusColor(booking);
    final paymentKnownPaid =
        booking.paymentStatus.toLowerCase().trim() == 'paid' ||
        booking.paymentStatus.toLowerCase().trim() == 'confirmed' ||
        booking.paymentStatus.toLowerCase().trim() == 'success' ||
        booking.paymentStatus.toLowerCase().trim() == 'completed';
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
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => _removeFromMyBookings(booking),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white.withOpacity(0.9),
                  side: BorderSide(color: Colors.white.withOpacity(0.22)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                child: Text(
                  _t(
                    nl: 'Verwijderen',
                    en: 'Remove',
                    fr: 'Supprimer',
                    es: 'Eliminar',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _openDetails(booking),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kFluxidiYellow.withOpacity(0.97),
                  side: BorderSide(color: kFluxidiYellow.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
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

  Future<void> _openDetails(StoredCustomerBooking booking) async {
    final id = booking.canonicalBookingId.trim();
    if (id.isEmpty) return;
    final aliases = _customerBookingAliasesFromStored(booking);
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => CustomerBookingDetailPage(
          bookingId: id,
          initialView: CustomerBookingView.fromStored(booking),
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
                  _customerBookingAliasesFromStored(item),
                  aliases,
                ),
              )
              .toList(growable: false);
        });
      }
      await _loadLocal();
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
    final result = await _removeLocalCustomerBookingEverywhere(
      bookingForLog: bookingId,
      aliases: _customerBookingDeleteAliases(
        bookingId: booking.bookingId,
        publicBookingReference: booking.publicBookingReference,
        bookingReference: booking.bookingReference,
        publicReference: booking.publicReference,
        planningReference: booking.planningReference,
        receiptReference: booking.receiptReference,
        paymentBookingId: booking.paymentBookingId,
      ),
    );
    await _loadLocal();
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
