part of '../main.dart';

/// Full-screen Bookings Hub opened from the drawer.
/// Keeps the map screen clean: operations live here.
class _TripHistoryPage extends StatefulWidget {
  final String workerBaseUrl;
  final String tenantId;
  final String companyId;
  final String driverId;
  final Map<String, String> headers;
  final Map<String, Map<String, dynamic>> bookingDetailsById;

  const _TripHistoryPage({
    required this.workerBaseUrl,
    required this.tenantId,
    required this.companyId,
    required this.driverId,
    required this.headers,
    this.bookingDetailsById = const <String, Map<String, dynamic>>{},
  });

  @override
  State<_TripHistoryPage> createState() => _TripHistoryPageState();
}

enum _TripHistoryFilter { all, completed, cancelled }

class _TripHistoryPageState extends State<_TripHistoryPage> {
  late Future<List<_TripHistoryItem>> _future;
  _TripHistoryFilter _activeFilter = _TripHistoryFilter.all;

  _TripHistoryItem _enrichTripHistoryItemWithBusinessRefs(
    _TripHistoryItem item, {
    required String sourceTag,
  }) {
    final bookingId = item.bookingId?.trim() ?? '';
    if (bookingId.isEmpty) return item;
    final authoritative = widget.bookingDetailsById[bookingId];
    if (authoritative == null || authoritative.isEmpty) return item;

    final mergedRawSource = _mergeBusinessReferencesIntoSource(
      source: Map<String, dynamic>.from(item.rawSource),
      authoritative: authoritative,
      canonicalBookingId: item.bookingId,
      tripId: item.tripId,
      sourceTag: sourceTag,
    );
    final mergedBookingDetails = _mergeBusinessReferencesIntoSource(
      source: Map<String, dynamic>.from(item.bookingDetails),
      authoritative: authoritative,
      canonicalBookingId: item.bookingId,
      tripId: item.tripId,
      sourceTag: '${sourceTag}_booking_details',
    );
    if (mergedBookingDetails.isNotEmpty) {
      mergedRawSource['booking_details'] = mergedBookingDetails;
      mergedRawSource['bookingDetails'] = mergedBookingDetails;
    }

    return item.copyWith(
      rawSource: mergedRawSource,
      bookingDetails: mergedBookingDetails,
    );
  }

  ({bool hasPlanning, bool hasPublicBooking, bool hasRealReceipt})
  _referencePresenceForItem(_TripHistoryItem item) {
    final maps = _referenceLookupMaps(<Map<String, dynamic>>[
      item.rawSource,
      item.bookingDetails,
    ]);
    final refs = _extractBusinessReferenceAliasesFromMaps(maps);
    final canonicalBookingId =
        _cleanBusinessReferenceText(item.bookingId) ??
        _pickReferenceAliasFromMaps(maps, const <List<String>>[
          <String>['booking_id'],
          <String>['bookingId'],
          <String>['id'],
          <String>['booking', 'booking_id'],
          <String>['booking', 'bookingId'],
          <String>['record', 'booking_id'],
          <String>['record', 'bookingId'],
        ]);
    final effectiveTripId =
        _cleanBusinessReferenceText(item.tripId) ??
        _pickReferenceAliasFromMaps(maps, const <List<String>>[
          <String>['trip_id'],
          <String>['tripId'],
        ]);
    final hasRealReceipt =
        refs.receipt != null &&
        _isRealReceiptReference(
          candidate: refs.receipt!,
          canonicalBookingId: canonicalBookingId,
          tripId: effectiveTripId,
          planningReference: refs.planning,
          publicBookingReference: refs.publicBooking,
          legacyTripReceiptNumber: effectiveTripId == null
              ? null
              : _legacyTripReceiptNumber(effectiveTripId),
        );
    return (
      hasPlanning: refs.planning != null,
      hasPublicBooking:
          refs.publicBooking != null ||
          refs.booking != null ||
          refs.publicRef != null,
      hasRealReceipt: hasRealReceipt,
    );
  }

  String _canonicalBookingIdFromItem(_TripHistoryItem item) {
    final direct = _cleanBusinessReferenceText(item.bookingId) ?? '';
    if (direct.isNotEmpty) return direct;
    final maps = _referenceLookupMaps(<Map<String, dynamic>>[
      item.rawSource,
      item.bookingDetails,
    ]);
    return _pickReferenceAliasFromMaps(maps, const <List<String>>[
          <String>['booking_id'],
          <String>['bookingId'],
          <String>['id'],
          <String>['booking', 'booking_id'],
          <String>['booking', 'bookingId'],
          <String>['record', 'booking_id'],
          <String>['record', 'bookingId'],
          <String>['record', 'booking', 'booking_id'],
          <String>['record', 'booking', 'bookingId'],
          <String>['payload', 'booking_id'],
          <String>['payload', 'bookingId'],
          <String>['payload', 'booking', 'booking_id'],
          <String>['payload', 'booking', 'bookingId'],
        ]) ??
        '';
  }

  Future<_TripHistoryItem> _enrichTripHistoryItemForReceipt(
    _TripHistoryItem item,
  ) async {
    var enriched = _enrichTripHistoryItemWithBusinessRefs(
      item,
      sourceTag: 'trip_history_open_receipt_cache',
    );
    final before = _referencePresenceForItem(enriched);
    if (before.hasPlanning ||
        before.hasPublicBooking ||
        before.hasRealReceipt) {
      debugPrint(
        '[DRIVER_HISTORY][REF_FETCH] booking=${_safeRefPreview(_canonicalBookingIdFromItem(enriched))} foundPlanning=${before.hasPlanning} foundPublic=${before.hasPublicBooking} foundReceipt=${before.hasRealReceipt} source=already_present',
      );
      return enriched;
    }

    final bookingId = _canonicalBookingIdFromItem(enriched);
    if (bookingId.isEmpty) {
      debugPrint(
        '[DRIVER_HISTORY][REF_FETCH] booking= foundPlanning=false foundPublic=false foundReceipt=false source=skipped_no_booking',
      );
      return enriched;
    }

    try {
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/bookings/${Uri.encodeComponent(bookingId)}',
      );
      final res = await http
          .get(uri, headers: widget.headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        debugPrint(
          '[DRIVER_HISTORY][REF_FETCH] booking=${_safeRefPreview(bookingId)} foundPlanning=false foundPublic=false foundReceipt=false source=fetch_failed',
        );
        return enriched;
      }
      final decodedRaw = jsonDecode(utf8.decode(res.bodyBytes));
      if (decodedRaw is! Map || decodedRaw['ok'] != true) {
        debugPrint(
          '[DRIVER_HISTORY][REF_FETCH] booking=${_safeRefPreview(bookingId)} foundPlanning=false foundPublic=false foundReceipt=false source=fetch_failed',
        );
        return enriched;
      }
      final decoded = Map<String, dynamic>.from(decodedRaw);
      final record = decoded['record'];
      final booking = record is Map ? record['booking'] : null;
      final authoritative = <String, dynamic>{
        ...decoded,
        if (record is Map) 'record': Map<String, dynamic>.from(record),
        if (booking is Map) 'booking': Map<String, dynamic>.from(booking),
        'booking_id': bookingId,
        'bookingId': bookingId,
      };
      final authoritativePresence = _extractBusinessReferenceAliasesFromMaps(
        _referenceLookupMaps(<Map<String, dynamic>>[authoritative]),
      );
      final mergedRawSource = _mergeBusinessReferencesIntoSource(
        source: Map<String, dynamic>.from(enriched.rawSource),
        authoritative: authoritative,
        canonicalBookingId: bookingId,
        tripId: enriched.tripId,
        sourceTag: 'trip_history_open_receipt_booking_detail_fetch',
      );
      final mergedBookingDetails = _mergeBusinessReferencesIntoSource(
        source: Map<String, dynamic>.from(enriched.bookingDetails),
        authoritative: authoritative,
        canonicalBookingId: bookingId,
        tripId: enriched.tripId,
        sourceTag: 'trip_history_open_receipt_booking_detail_fetch_details',
      );
      if (mergedBookingDetails.isNotEmpty) {
        mergedRawSource['booking_details'] = mergedBookingDetails;
        mergedRawSource['bookingDetails'] = mergedBookingDetails;
      }
      enriched = enriched.copyWith(
        rawSource: mergedRawSource,
        bookingDetails: mergedBookingDetails,
      );
      final after = _referencePresenceForItem(enriched);
      debugPrint(
        '[DRIVER_HISTORY][REF_FETCH] booking=${_safeRefPreview(bookingId)} foundPlanning=${authoritativePresence.planning != null || after.hasPlanning} foundPublic=${authoritativePresence.publicBooking != null || authoritativePresence.booking != null || authoritativePresence.publicRef != null || after.hasPublicBooking} foundReceipt=${authoritativePresence.receipt != null || after.hasRealReceipt} source=booking_detail_fetch',
      );
      return enriched;
    } catch (_) {
      debugPrint(
        '[DRIVER_HISTORY][REF_FETCH] booking=${_safeRefPreview(bookingId)} foundPlanning=false foundPublic=false foundReceipt=false source=fetch_failed',
      );
      return enriched;
    }
  }

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<_TripHistoryItem>> _fetch() async {
    DateTime? parseIso(String? iso) {
      final text = iso?.trim();
      if (text == null || text.isEmpty) return null;
      return DateTime.tryParse(text);
    }

    void sortNewestFirst(List<_TripHistoryItem> items) {
      items.sort((a, b) {
        final aStopped = parseIso(a.stoppedAt);
        final bStopped = parseIso(b.stoppedAt);
        if (aStopped != null && bStopped != null) {
          final c = bStopped.compareTo(aStopped);
          if (c != 0) return c;
        } else if (aStopped == null && bStopped != null) {
          return 1;
        } else if (aStopped != null && bStopped == null) {
          return -1;
        }
        final aStarted = parseIso(a.startedAt);
        final bStarted = parseIso(b.startedAt);
        if (aStarted != null && bStarted != null) {
          final c = bStarted.compareTo(aStarted);
          if (c != 0) return c;
        } else if (aStarted == null && bStarted != null) {
          return 1;
        } else if (aStarted != null && bStarted == null) {
          return -1;
        }
        return b.tripId.compareTo(a.tripId);
      });
    }

    Future<List<_TripHistoryItem>> readLocalItems() async {
      final localRecords = await _LocalDirectTripHistoryStore.readFor(
        tenantId: widget.tenantId,
        companyId: widget.companyId,
        driverId: widget.driverId,
        limit: 120,
      );
      return localRecords
          .map(_TripHistoryItem.fromJson)
          .where((e) => e.tripId.trim().isNotEmpty)
          .toList(growable: false);
    }

    late final List<_TripHistoryItem> backendItems;
    try {
      final uri = Uri.parse(
        '${widget.workerBaseUrl}$kTripsHistoryPath'
        '?tenant_id=${Uri.encodeQueryComponent(widget.tenantId)}'
        '&company_id=${Uri.encodeQueryComponent(widget.companyId)}'
        '&tenantId=${Uri.encodeQueryComponent(widget.tenantId)}'
        '&companyId=${Uri.encodeQueryComponent(widget.companyId)}'
        '&driver_id=${Uri.encodeQueryComponent(widget.driverId)}'
        '&limit=100',
      );
      final res = await http
          .get(uri, headers: widget.headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['ok'] != true) {
        throw Exception('Ongeldig antwoord van Worker');
      }
      final trips = decoded['trips'];
      backendItems = trips is! List
          ? <_TripHistoryItem>[]
          : trips
                .whereType<Map>()
                .map(
                  (e) =>
                      _TripHistoryItem.fromJson(Map<String, dynamic>.from(e)),
                )
                .where((e) => e.tripId.trim().isNotEmpty)
                .toList(growable: false);
    } catch (_) {
      final localItems = await readLocalItems();
      if (localItems.isEmpty) rethrow;
      sortNewestFirst(localItems);
      return localItems;
    }

    final localItems = await readLocalItems();
    final mergedByTripId = <String, _TripHistoryItem>{};
    for (final item in backendItems) {
      mergedByTripId[item.tripId.trim()] = item;
    }
    for (final item in localItems) {
      mergedByTripId.putIfAbsent(item.tripId.trim(), () => item);
    }
    final merged = mergedByTripId.values
        .map(
          (item) => _enrichTripHistoryItemWithBusinessRefs(
            item,
            sourceTag: 'trip_history_fetch_merge',
          ),
        )
        .toList(growable: false);
    sortNewestFirst(merged);
    return merged;
  }

  void _refresh() {
    setState(() {
      _future = _fetch();
    });
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(dt.day)}-${two(dt.month)}-${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  String _formatWait(int seconds) {
    if (seconds <= 0) return '0 min';
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    if (min <= 0) return '${sec}s';
    if (sec == 0) return '$min min';
    return '$min min ${sec}s';
  }

  Future<void> _openReceipt(_TripHistoryItem item) async {
    final enrichedItem = await _enrichTripHistoryItemForReceipt(item);
    if (!mounted) return;
    if (!enrichedItem.isCompletedForReceipt) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('receiptUnavailable'))),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _RideReceiptPage(item: enrichedItem)),
    );
  }

  Future<void> _archiveTrip(_TripHistoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_receiptText('archiveTripTitle')),
        content: Text(_receiptText('archiveTripBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_receiptText('archiveTripCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_receiptText('archiveTripConfirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final scopeQuery = <String, String>{
        'tenant_id': widget.tenantId,
        'company_id': widget.companyId,
        'tenantId': widget.tenantId,
        'companyId': widget.companyId,
      };
      final res = await http
          .post(
            Uri.parse(
              '${widget.workerBaseUrl}$kTripsArchivePath',
            ).replace(queryParameters: scopeQuery),
            headers: widget.headers,
            body: jsonEncode({
              'tenant_id': widget.tenantId,
              'company_id': widget.companyId,
              'tenantId': widget.tenantId,
              'companyId': widget.companyId,
              'driver_id': widget.driverId,
              'trip_id': item.tripId,
              'archived': true,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final decoded = jsonDecode(res.body);
      if (res.statusCode != 200 || decoded is! Map || decoded['ok'] != true) {
        throw Exception('archive_failed');
      }
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('archiveTripSuccess'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('archiveTripFailed'))),
      );
    }
  }

  bool _isCompletedStatus(String? raw) {
    final status = (raw ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    return status == 'stopped' ||
        status == 'completed' ||
        status == 'complete' ||
        status == 'done' ||
        status == 'finished' ||
        status == 'finalized';
  }

  bool _isCancelledStatus(String? raw) {
    final status = (raw ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    return status == 'cancelled' || status == 'canceled';
  }

  String _normalizePaymentStatus(_TripHistoryItem item) {
    String? from(dynamic v) {
      final text = v?.toString().trim().toLowerCase();
      if (text == null || text.isEmpty || text == 'null') return null;
      return text.replaceAll('-', '_').replaceAll(' ', '_');
    }

    final detail = item.bookingDetails;
    final raw = item.rawSource;
    final candidates = <String?>[
      from(detail['payment_status']),
      from(detail['paymentStatus']),
      from(raw['payment_status']),
      from(raw['paymentStatus']),
      from(raw['payment'] is Map ? (raw['payment'] as Map)['status'] : null),
      from(
        detail['payment'] is Map ? (detail['payment'] as Map)['status'] : null,
      ),
    ];
    final normalized = candidates.firstWhere(
      (e) => e != null && e.isNotEmpty,
      orElse: () => null,
    );
    if (normalized == null) return 'unknown';
    if (normalized == 'paid' ||
        normalized == 'settled' ||
        normalized == 'confirmed' ||
        normalized == 'completed' ||
        normalized == 'succeeded' ||
        normalized == 'success') {
      return 'paid';
    }
    if (normalized == 'unpaid' ||
        normalized == 'not_paid' ||
        normalized == 'open' ||
        normalized == 'pending' ||
        normalized == 'authorized' ||
        normalized == 'authorised' ||
        normalized == 'processing') {
      return 'unpaid';
    }
    if (normalized == 'cancelled' || normalized == 'canceled') {
      return 'cancelled';
    }
    if (normalized == 'failed' ||
        normalized == 'error' ||
        normalized == 'declined') {
      return 'failed';
    }
    return 'unknown';
  }

  String _formatEur(double value) {
    return '€${value.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  List<_TripHistoryItem> _applyFilter(List<_TripHistoryItem> items) {
    switch (_activeFilter) {
      case _TripHistoryFilter.completed:
        return items.where((item) => _isCompletedStatus(item.status)).toList();
      case _TripHistoryFilter.cancelled:
        return items.where((item) => _isCancelledStatus(item.status)).toList();
      case _TripHistoryFilter.all:
        return items;
    }
  }

  ({int total, int completed, int cancelled, double revenue}) _summary(
    List<_TripHistoryItem> items,
  ) {
    var completed = 0;
    var cancelled = 0;
    var revenue = 0.0;
    for (final item in items) {
      if (_isCancelledStatus(item.status)) {
        cancelled++;
        continue;
      }
      if (_isCompletedStatus(item.status)) {
        completed++;
        final payment = _normalizePaymentStatus(item);
        final canInclude = payment != 'unpaid';
        if (canInclude && item.totalEur != null) {
          revenue += item.totalEur!;
        }
      }
    }
    return (
      total: items.length,
      completed: completed,
      cancelled: cancelled,
      revenue: revenue,
    );
  }

  String _dateOnly(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}-${two(local.month)}-${local.year}';
  }

  String _timeOnly(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  String _statusChipText(_TripHistoryItem item) {
    if (_isCancelledStatus(item.status)) {
      return _tr(
        nl: 'Geannuleerd',
        en: 'Cancelled',
        fr: 'Annulée',
        es: 'Cancelada',
      );
    }
    if (_isCompletedStatus(item.status)) {
      return _tr(
        nl: 'Voltooid',
        en: 'Completed',
        fr: 'Terminée',
        es: 'Completada',
      );
    }
    return _tr(nl: 'Onbekend', en: 'Unknown', fr: 'Inconnu', es: 'Desconocido');
  }

  Color _statusChipColor(_TripHistoryItem item) {
    if (_isCancelledStatus(item.status)) return const Color(0xFFF97373);
    if (_isCompletedStatus(item.status)) return const Color(0xFF4ADE80);
    return const Color(0xFFA3A3A3);
  }

  String _paymentChipText(_TripHistoryItem item) {
    final payment = _normalizePaymentStatus(item);
    if (payment == 'paid') {
      return _tr(nl: 'Betaald', en: 'Paid', fr: 'Payé', es: 'Pagado');
    }
    if (payment == 'unpaid') {
      return _tr(nl: 'Onbetaald', en: 'Unpaid', fr: 'Impayé', es: 'No pagado');
    }
    return '';
  }

  bool _looksLikeRawCoordinatePair(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return false;
    final match = RegExp(
      r'^([+-]?\d{1,3}(?:\.\d+)?)\s*[,;\s]\s*([+-]?\d{1,3}(?:\.\d+)?)$',
    ).firstMatch(text);
    if (match == null) return false;
    final first = double.tryParse(match.group(1)!);
    final second = double.tryParse(match.group(2)!);
    if (first == null || second == null) return false;
    final firstInLatLon = first.abs() <= 90.0 && second.abs() <= 180.0;
    final secondInLatLon = first.abs() <= 180.0 && second.abs() <= 90.0;
    return firstInLatLon || secondInLatLon;
  }

  String _displayHistoryOrigin(String rawOrigin) {
    final trimmed = rawOrigin.trim();
    if (_looksLikeRawCoordinatePair(trimmed)) {
      return _tr(
        nl: 'Startlocatie',
        en: 'Start location',
        fr: 'Point de départ',
        es: 'Punto de inicio',
      );
    }
    return trimmed.isEmpty ? '—' : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF07080C),
        appBar: AppBar(
          backgroundColor: const Color(0xFF07080C),
          elevation: 0,
          title: Text(
            _tr(
              nl: 'Historiek',
              en: 'History',
              fr: 'Historique',
              es: 'Historial',
            ),
          ),
          actions: [
            IconButton(
              tooltip: _receiptText('refresh'),
              onPressed: _refresh,
              icon: Icon(
                Icons.refresh,
                color: kFluxidiYellow.withOpacity(0.95),
              ),
            ),
          ],
        ),
        body: FutureBuilder<List<_TripHistoryItem>>(
          future: _future,
          builder: (context, snapshot) {
            final tabLabels = <_TripHistoryFilter, String>{
              _TripHistoryFilter.all: _tr(
                nl: 'Alle ritten',
                en: 'All rides',
                fr: 'Toutes',
                es: 'Todas',
              ),
              _TripHistoryFilter.completed: _tr(
                nl: 'Voltooid',
                en: 'Completed',
                fr: 'Terminées',
                es: 'Completadas',
              ),
              _TripHistoryFilter.cancelled: _tr(
                nl: 'Geannuleerd',
                en: 'Cancelled',
                fr: 'Annulées',
                es: 'Canceladas',
              ),
            };

            Widget metric({
              required String label,
              required String value,
              required IconData icon,
              required Color accentColor,
              Color valueColor = Colors.white,
            }) {
              return Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF101010),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kFluxidiYellow.withOpacity(0.24)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accentColor.withOpacity(0.16),
                            border: Border.all(
                              color: accentColor.withOpacity(0.52),
                            ),
                          ),
                          child: Icon(icon, size: 13.5, color: accentColor),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.64),
                              fontSize: 10.6,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: valueColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
              );
            }

            Widget historyCard(_TripHistoryItem item) {
              final startedIso = (item.startedAt ?? '').trim().isNotEmpty
                  ? item.startedAt
                  : item.stoppedAt;
              final km = item.kmTotal == null
                  ? '—'
                  : '${item.kmTotal!.toStringAsFixed(1)} km';
              final total = item.totalEur == null
                  ? '€ —'
                  : _formatEur(item.totalEur!);
              final statusColor = _statusChipColor(item);
              final paymentChip = _paymentChipText(item);
              final originText = _displayHistoryOrigin(item.origin);
              final kindOrCustomer = (item.customerName ?? '').trim().isNotEmpty
                  ? item.customerName!.trim()
                  : '${item.kindLabel}${item.isLocalOnlyDirectFallback ? ' • Lokaal' : ''}';
              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF101113),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kFluxidiYellow.withOpacity(0.28)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _openReceipt(item),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          padding: const EdgeInsets.only(top: 3),
                          child: Column(
                            children: [
                              Icon(
                                Icons.radio_button_checked,
                                size: 12.5,
                                color: statusColor,
                              ),
                              Container(
                                width: 2,
                                height: 76,
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                  color: kFluxidiYellow.withOpacity(0.28),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${_dateOnly(startedIso)} • ${_timeOnly(startedIso)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: kFluxidiYellow.withOpacity(0.95),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF17120A),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: kFluxidiYellow.withOpacity(0.45),
                                      ),
                                    ),
                                    child: Text(
                                      total,
                                      style: TextStyle(
                                        color: kFluxidiYellow.withOpacity(0.98),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.my_location_rounded,
                                    size: 14,
                                    color: Color(0xFFEAB308),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      originText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.2,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_outlined,
                                    size: 14,
                                    color: Color(0xFFEAB308),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      item.destination,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.2,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              Text(
                                '$kindOrCustomer • $km • ${_receiptText('waitingCompact')} ${_formatWait(item.waitSecondsTotal)}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.70),
                                  fontSize: 11.2,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 7,
                                runSpacing: 7,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: statusColor.withOpacity(0.55),
                                      ),
                                    ),
                                    child: Text(
                                      _statusChipText(item),
                                      style: TextStyle(
                                        color: statusColor,
                                        fontSize: 10.8,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (paymentChip.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF161616),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: kFluxidiYellow.withOpacity(
                                            0.42,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        paymentChip,
                                        style: TextStyle(
                                          color: kFluxidiYellow.withOpacity(
                                            0.95,
                                          ),
                                          fontSize: 10.8,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.end,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => _archiveTrip(item),
                                      icon: const Icon(
                                        Icons.archive_outlined,
                                        size: 17,
                                      ),
                                      label: Text(
                                        _receiptText('archiveTripLabel'),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white70,
                                        side: BorderSide(
                                          color: kFluxidiYellow.withOpacity(
                                            0.35,
                                          ),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                    FilledButton.icon(
                                      onPressed: () => _openReceipt(item),
                                      icon: const Icon(
                                        Icons.receipt_long,
                                        size: 17,
                                      ),
                                      label: Text(_receiptText('receiptTitle')),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: kFluxidiYellow,
                                        foregroundColor: const Color(
                                          0xFF101010,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                  ],
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

            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: CircularProgressIndicator(color: kFluxidiYellow),
              );
            }
            if (snapshot.hasError) {
              return Center(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101113),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kFluxidiYellow.withOpacity(0.30)),
                  ),
                  child: Text(
                    '${_receiptText('historyLoadFailed')}\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.78)),
                  ),
                ),
              );
            }
            final items = snapshot.data ?? const <_TripHistoryItem>[];
            final filteredItems = _applyFilter(items);
            final summary = _summary(items);
            if (items.isEmpty) {
              return Center(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101113),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kFluxidiYellow.withOpacity(0.30)),
                  ),
                  child: Text(
                    _receiptText('historyEmpty'),
                    style: TextStyle(color: Colors.white.withOpacity(0.78)),
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101113),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kFluxidiYellow.withOpacity(0.30)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _tr(
                          nl: 'Overzicht',
                          en: 'Overview',
                          fr: 'Aperçu',
                          es: 'Resumen',
                        ),
                        style: TextStyle(
                          color: kFluxidiYellow.withOpacity(0.98),
                          fontWeight: FontWeight.w800,
                          fontSize: 14.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _tr(
                          nl: 'Laatste ritten',
                          en: 'Recent rides',
                          fr: 'Courses récentes',
                          es: 'Viajes recientes',
                        ),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.62),
                          fontSize: 11.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 380;
                          if (compact) {
                            return Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: metric(
                                        label: _tr(
                                          nl: 'Totaal ritten',
                                          en: 'Total rides',
                                          fr: 'Total courses',
                                          es: 'Total viajes',
                                        ),
                                        value: summary.total.toString(),
                                        icon: Icons.list_alt_rounded,
                                        accentColor: const Color(0xFF60A5FA),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: metric(
                                        label: _tr(
                                          nl: 'Voltooid',
                                          en: 'Completed',
                                          fr: 'Terminées',
                                          es: 'Completados',
                                        ),
                                        value: summary.completed.toString(),
                                        icon:
                                            Icons.check_circle_outline_rounded,
                                        accentColor: const Color(0xFF4ADE80),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: metric(
                                        label: _tr(
                                          nl: 'Geannuleerd',
                                          en: 'Cancelled',
                                          fr: 'Annulées',
                                          es: 'Cancelados',
                                        ),
                                        value: summary.cancelled.toString(),
                                        icon: Icons.cancel_outlined,
                                        accentColor: const Color(0xFFF97373),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: metric(
                                        label: _tr(
                                          nl: 'Omzet',
                                          en: 'Revenue',
                                          fr: 'Revenus',
                                          es: 'Ingresos',
                                        ),
                                        value: _formatEur(summary.revenue),
                                        icon: Icons.euro_rounded,
                                        accentColor: kFluxidiYellow,
                                        valueColor: kFluxidiYellow,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(
                                child: metric(
                                  label: _tr(
                                    nl: 'Totaal ritten',
                                    en: 'Total rides',
                                    fr: 'Total courses',
                                    es: 'Total viajes',
                                  ),
                                  value: summary.total.toString(),
                                  icon: Icons.list_alt_rounded,
                                  accentColor: const Color(0xFF60A5FA),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: metric(
                                  label: _tr(
                                    nl: 'Voltooid',
                                    en: 'Completed',
                                    fr: 'Terminées',
                                    es: 'Completados',
                                  ),
                                  value: summary.completed.toString(),
                                  icon: Icons.check_circle_outline_rounded,
                                  accentColor: const Color(0xFF4ADE80),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: metric(
                                  label: _tr(
                                    nl: 'Geannuleerd',
                                    en: 'Cancelled',
                                    fr: 'Annulées',
                                    es: 'Cancelados',
                                  ),
                                  value: summary.cancelled.toString(),
                                  icon: Icons.cancel_outlined,
                                  accentColor: const Color(0xFFF97373),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: metric(
                                  label: _tr(
                                    nl: 'Omzet',
                                    en: 'Revenue',
                                    fr: 'Revenus',
                                    es: 'Ingresos',
                                  ),
                                  value: _formatEur(summary.revenue),
                                  icon: Icons.euro_rounded,
                                  accentColor: kFluxidiYellow,
                                  valueColor: kFluxidiYellow,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _TripHistoryFilter.values
                        .map((filter) {
                          final active = _activeFilter == filter;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () =>
                                  setState(() => _activeFilter = filter),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: active
                                      ? const Color(0xFF17120A)
                                      : const Color(0xFF111214),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: active
                                        ? kFluxidiYellow.withOpacity(0.7)
                                        : Colors.white.withOpacity(0.14),
                                  ),
                                ),
                                child: Text(
                                  tabLabels[filter]!,
                                  style: TextStyle(
                                    color: active
                                        ? kFluxidiYellow.withOpacity(0.98)
                                        : Colors.white.withOpacity(0.76),
                                    fontSize: 11.8,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _tr(
                    nl: 'Rit geschiedenis',
                    en: 'Ride history',
                    fr: 'Historique des courses',
                    es: 'Historial de viajes',
                  ),
                  style: TextStyle(
                    color: kFluxidiYellow.withOpacity(0.95),
                    fontWeight: FontWeight.w800,
                    fontSize: 13.8,
                  ),
                ),
                const SizedBox(height: 8),
                if (filteredItems.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101113),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: kFluxidiYellow.withOpacity(0.28),
                      ),
                    ),
                    child: Text(
                      _receiptText('historyEmpty'),
                      style: TextStyle(color: Colors.white.withOpacity(0.72)),
                    ),
                  )
                else
                  ...filteredItems.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: historyCard(item),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
