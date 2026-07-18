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

  /// Effective chauffeur-theme source for this History view. Mirrors the
  /// pattern used by [CalculatorPage] and [_BookingsHubPage]: when omitted we
  /// fall back to the global [driverThemeNotifier] (standalone personal
  /// driver), and when provided we follow the caller's active driver-theme
  /// listenable. From Driver Home this is `_activeDriverThemeListenable`,
  /// which resolves to `companyDriverViewThemeNotifier` in the business /
  /// admin chauffeur view and to `driverAppThemeNotifier` in the standalone
  /// driver app. Using a single shared listenable keeps the page in sync with
  /// the same theme the Driver Home renders with, so opening History from a
  /// Midnight Blue / Midday Gold chauffeur view no longer falls back to Night
  /// Gold accents.
  final ValueListenable<DriverThemeVariant>? driverThemeListenable;

  const _TripHistoryPage({
    required this.workerBaseUrl,
    required this.tenantId,
    required this.companyId,
    required this.driverId,
    required this.headers,
    this.bookingDetailsById = const <String, Map<String, dynamic>>{},
    this.driverThemeListenable,
  });

  @override
  State<_TripHistoryPage> createState() => _TripHistoryPageState();
}

enum _TripHistoryFilter { all, completed, cancelled }

/// Visual chauffeur-theme tokens for the Driver History page.
///
/// Mirrors the local-token pattern already used by [_BookingsHubPage]
/// (`_BookingsHubThemeTokens`) and [DriverMyDocumentsPage]
/// (`_DriverDocumentsThemeTokens`) so all three pages render with consistent
/// chauffeur palettes per variant:
///
/// - Night Gold keeps the existing production look (same values as
///   `paletteForDriverTheme(DriverThemeVariant.nightGold)`).
/// - Midnight Blue keeps the existing palette values (blue/cyan, no regression).
/// - Midday Gold (`DriverThemeVariant.highContrast`) is realigned with the
///   Documents/Bookings reference pages so titles, borders, chips, the price
///   pill, the receipt button and timeline accents use soft warm champagne
///   over warm espresso, instead of the dimmer values that previously made
///   the page read as Night Gold.
class _TripHistoryThemeTokens {
  const _TripHistoryThemeTokens({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.accent,
    required this.textPrimary,
    required this.textMuted,
    required this.accentForeground,
    this.pageGradient,
    this.overviewGradient,
    this.overviewBorder,
    this.tileGradient,
    this.tileBorder,
    this.cardGradient,
    this.cardBorder,
    this.selectedChipGradient,
    this.selectedChipBorder,
    this.selectedChipTextColor,
    this.softBorder,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color accent;
  final Color textPrimary;
  final Color textMuted;

  /// Foreground color used on top of [accent] for filled buttons/pills
  /// (e.g. the Receipt button). Mirrors the values used by other chauffeur
  /// surfaces (driver documents, cockpit) so each theme keeps its own
  /// readable contrast pair.
  final Color accentForeground;

  // Optional Midday Gold visual enhancements. All `null` for the Night Gold
  // and Midnight Blue branches so those variants fall through to the
  // original flat-color rendering and accent-derived outlines and therefore
  // do not regress.
  //
  // - [pageGradient] backs the entire Scaffold body
  //   (BookingsHub `_BookingsHubThemeTokens.pageGradient` for highContrast).
  // - [overviewGradient] / [overviewBorder] decorate the "Overview / Recent
  //   rides" panel (Documents `_DriverDocumentsThemeTokens.panelGradient` +
  //   `panelBorder` for highContrast).
  // - [tileGradient] / [tileBorder] decorate the inner KPI tiles inside the
  //   overview panel (Documents `cardGradient` + `cardBorder`).
  // - [cardGradient] / [cardBorder] decorate the ride history cards as well
  //   as the empty / error / filtered-empty cards that share the same
  //   surface treatment (BookingsHub `surfaceGradient` + `surfaceBorder`).
  // - [selectedChipGradient] / [selectedChipBorder] / [selectedChipTextColor]
  //   render the selected filter chip with Driver Home's existing
  //   `_middayGoldSelectedSurfaceGradient` + `_middayGoldBorderColor(0.72)`
  //   + `_middayGoldTextOnSelected()` styling.
  // - [softBorder] is a low-emphasis outline used by inactive filter chips
  //   and matches Driver Home's `_middayGoldBorderColor(0.24)`.
  final Gradient? pageGradient;
  final Gradient? overviewGradient;
  final Color? overviewBorder;
  final Gradient? tileGradient;
  final Color? tileBorder;
  final Gradient? cardGradient;
  final Color? cardBorder;
  final Gradient? selectedChipGradient;
  final Color? selectedChipBorder;
  final Color? selectedChipTextColor;
  final Color? softBorder;
}

_TripHistoryThemeTokens _tripHistoryThemeForVariant(
  DriverThemeVariant variant,
) {
  switch (variant) {
    case DriverThemeVariant.midnightBlue:
      // Identical to `paletteForDriverTheme(midnightBlue)` so the existing
      // blue/cyan look is preserved exactly. No gradients here on purpose:
      // the Midnight Blue surfaces in History are intentionally flat to
      // match the existing production look.
      return const _TripHistoryThemeTokens(
        background: Color(0xFF08142D),
        surface: Color(0xFF101E3A),
        surfaceAlt: Color(0xFF0F1A2F),
        border: Color(0xFF2D8CFF),
        accent: Color(0xFF4DA3FF),
        textPrimary: Color(0xFFF4F8FF),
        textMuted: Color(0xFFB6C4DA),
        accentForeground: Color(0xFF04172C),
      );
    case DriverThemeVariant.highContrast:
      // Aligned with `_DriverDocumentsThemeTokens` (highContrast),
      // `_BookingsHubThemeTokens` (highContrast) and Driver Home's
      // `_middayGold*` helpers so the History page visually matches the
      // other Midday Gold chauffeur pages with warm-espresso/champagne
      // gradients instead of flat dark gold (which previously read as
      // Night Gold).
      return _TripHistoryThemeTokens(
        background: const Color(0xFF171108),
        surface: const Color(0xFF22170C),
        surfaceAlt: const Color(0xFF362510),
        border: const Color(0xFFE8C57E),
        accent: const Color(0xFFFFDFA3),
        textPrimary: const Color(0xFFFFF0D0),
        textMuted: const Color(0xFFE1CCA0),
        accentForeground: const Color(0xFF3A2406),
        // BookingsHub `pageGradient` (highContrast).
        pageGradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF100B06), Color(0xFF17110A), Color(0xFF2C2113)],
        ),
        // Documents `panelGradient` + `panelBorder` (highContrast).
        overviewGradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5D4321), Color(0xFF362510)],
        ),
        overviewBorder: const Color(0x99FFDFA3),
        // Documents `cardGradient` + `cardBorder` (highContrast) for the
        // inner KPI tiles inside the overview panel.
        tileGradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A2B17), Color(0xFF22170C)],
        ),
        tileBorder: const Color(0x66E8C57E),
        // BookingsHub `surfaceGradient` + `surfaceBorder` (highContrast)
        // for the history ride cards and the message cards (empty / error
        // / filtered-empty) that share the same surface treatment.
        cardGradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B2B17), Color(0xFF22170C)],
        ),
        cardBorder: const Color(0x99E8C57E),
        // Driver Home `_middayGoldSelectedSurfaceGradient()` + selected
        // border (`_middayGoldBorderColor(0.72)`) + dark on-selected text
        // (`_middayGoldTextOnSelected()`) for the active filter chip.
        selectedChipGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFF6E8C2).withOpacity(0.96),
            const Color(0xFFD8BF7B).withOpacity(0.88),
            const Color(0xFF8D7448).withOpacity(0.72),
            const Color(0xFF3A2A10).withOpacity(0.80),
          ],
        ),
        selectedChipBorder: const Color(0xFFFFDFA3).withOpacity(0.72),
        selectedChipTextColor: const Color(0xFF2B2113),
        // Driver Home `_middayGoldBorderColor(0.24)` for low-emphasis
        // outlines (inactive filter chip).
        softBorder: const Color(0xFFFFDFA3).withOpacity(0.24),
      );
    case DriverThemeVariant.nightGold:
      // Identical to `paletteForDriverTheme(nightGold)` so the production
      // gold/black look stays unchanged. No gradients here on purpose.
      return const _TripHistoryThemeTokens(
        background: Color(0xFF07080C),
        surface: Color(0xFF101113),
        surfaceAlt: Color(0xFF16120A),
        border: Color(0xFF3B2C14),
        accent: Color(0xFFE5B641),
        textPrimary: Color(0xFFFFFFFF),
        textMuted: Color(0xFFB4B4B4),
        accentForeground: Color(0xFF101010),
      );
  }
}

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
    // STREET-RIDE-HISTORY-DUPLICATE-ZERO-BOOKING-1A: worker canonical contract
    // version, read from the `X-Fluxidi-History-Canonical` header or the
    // `canonical_version` body field. `null` => stale worker (no dedupe at src).
    String? workerCanonicalVersion;
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
      workerCanonicalVersion =
          (res.headers['x-fluxidi-history-canonical'] ??
                  decoded['canonical_version'])
              ?.toString()
              .trim();
      if (workerCanonicalVersion != null && workerCanonicalVersion.isEmpty) {
        workerCanonicalVersion = null;
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
    final usedLocalFallback = backendItems.isEmpty && localItems.isNotEmpty;
    final mergedByTripId = <String, _TripHistoryItem>{};
    for (final item in backendItems) {
      mergedByTripId[item.tripId.trim()] = item;
    }
    for (final item in localItems) {
      mergedByTripId.putIfAbsent(item.tripId.trim(), () => item);
    }
    final beforeItems = mergedByTripId.values.toList(growable: false);
    // STREET-RIDE-HISTORY-DUPLICATE-ZERO-BOOKING-1A: collapse the planned
    // operational-leg shadow of a linked street-ride direct trip so one
    // physical ride shows exactly one canonical row. Relational-id only:
    // honours the worker `is_operational_shadow` hint when present, otherwise
    // re-derives from booking_id + parent_booking_id + operational-leg flags.
    final canonical = canonicalizeStreetHistory<_TripHistoryItem>(
      beforeItems,
      tripId: (item) => item.tripId,
      kind: (item) => item.kind,
      bookingId: (item) => item.bookingId ?? '',
      parentBookingId: (item) => item.parentBookingId,
      linkedTrackingTripId: (item) => item.linkedTrackingTripId,
      isOperationalLeg: (item) => item.isOperationalLeg,
      workerShadowHint: (item) => item.workerOperationalShadowHint,
      onLog: (log) => debugPrint(log.toLogLine()),
    );
    debugPrint(
      '[STREET_HISTORY_RUNTIME] source=client '
      'workerCanonicalVersion=${workerCanonicalVersion ?? 'absent'} '
      'clientCanonicalVersion=$kStreetHistoryClientCanonicalVersion '
      'rowsBefore=${beforeItems.length} rowsAfter=${canonical.length} '
      'cacheUsed=$usedLocalFallback',
    );
    final merged = canonical
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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _RideReceiptPage(
          item: enrichedItem,
          driverThemeListenable:
              widget.driverThemeListenable ?? driverThemeNotifier,
        ),
      ),
    );
    if (!mounted) return;
    _refresh();
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
      from(raw['payment_status']),
      from(raw['paymentStatus']),
      from(raw['payment'] is Map ? (raw['payment'] as Map)['status'] : null),
      from(detail['payment_status']),
      from(detail['paymentStatus']),
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

  String? _historyLegTypeToken(_TripHistoryItem item) {
    String? pick(List<List<String>> paths) {
      for (final path in paths) {
        dynamic current = item.bookingDetails;
        for (final key in path) {
          if (current is Map && current.containsKey(key)) {
            current = current[key];
          } else {
            current = null;
            break;
          }
        }
        final text = current?.toString().trim();
        if (text != null && text.isNotEmpty) return text;
      }
      return null;
    }

    final raw = pick(const [
      ['leg_type'],
      ['legType'],
      ['details', 'leg_type'],
      ['details', 'legType'],
      ['booking', 'leg_type'],
      ['booking', 'legType'],
      ['booking_details', 'leg_type'],
      ['booking_details', 'legType'],
    ])?.toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    if (raw.contains('return') || raw.contains('terug')) return 'return';
    if (raw.contains('outbound') || raw.contains('heen')) return 'outbound';
    return null;
  }

  String? _historyLegBadgeText(_TripHistoryItem item) {
    final token = _historyLegTypeToken(item);
    if (token == null) return null;
    if (token == 'return') {
      return _tr(nl: 'Terugrit', en: 'Return', fr: 'Retour', es: 'Vuelta');
    }
    return _tr(nl: 'Heenrit', en: 'Outbound', fr: 'Aller', es: 'Ida');
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
    final ValueListenable<DriverThemeVariant> themeListenable =
        widget.driverThemeListenable ?? driverThemeNotifier;
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => ValueListenableBuilder<DriverThemeVariant>(
        valueListenable: themeListenable,
        builder: (context, themeVariant, ___) {
          final tokens = _tripHistoryThemeForVariant(themeVariant);
          final accent = tokens.accent;
          final accentForeground = tokens.accentForeground;
          final background = tokens.background;
          final surface = tokens.surface;
          final surfaceAlt = tokens.surfaceAlt;
          final textPrimary = tokens.textPrimary;
          final textMuted = tokens.textMuted;
          final paletteBorder = tokens.border;

          // Gradient-aware decoration helpers. For Night Gold and Midnight
          // Blue the optional gradient/border tokens are null, so each
          // helper falls back to the existing flat-color surface and
          // accent-derived outline (no regression). For Midday Gold the
          // helpers paint the warm-espresso/champagne gradients copied from
          // Documents / BookingsHub / Driver Home.
          BoxDecoration overviewDecoration() => BoxDecoration(
            color: tokens.overviewGradient == null ? surface : null,
            gradient: tokens.overviewGradient,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: tokens.overviewBorder ?? accent.withOpacity(0.30),
            ),
          );
          BoxDecoration tileDecoration() => BoxDecoration(
            color: tokens.tileGradient == null ? surface : null,
            gradient: tokens.tileGradient,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: tokens.tileBorder ?? accent.withOpacity(0.24),
            ),
          );
          BoxDecoration cardDecoration({double fallbackBorderOpacity = 0.28}) =>
              BoxDecoration(
                color: tokens.cardGradient == null ? surface : null,
                gradient: tokens.cardGradient,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color:
                      tokens.cardBorder ??
                      accent.withOpacity(fallbackBorderOpacity),
                ),
              );
          BoxDecoration filterChipDecoration({required bool active}) =>
              BoxDecoration(
                color: active
                    ? (tokens.selectedChipGradient == null ? surfaceAlt : null)
                    : surface,
                gradient: active ? tokens.selectedChipGradient : null,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: active
                      ? (tokens.selectedChipBorder ?? accent.withOpacity(0.7))
                      : (tokens.softBorder ?? paletteBorder.withOpacity(0.45)),
                ),
              );
          Color filterChipTextColor({required bool active}) => active
              ? (tokens.selectedChipTextColor ?? accent.withOpacity(0.98))
              : textMuted;
          return Scaffold(
            backgroundColor: background,
            appBar: AppBar(
              backgroundColor: background,
              elevation: 0,
              iconTheme: IconThemeData(color: textPrimary),
              titleTextStyle: TextStyle(
                color: textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
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
                  icon: Icon(Icons.refresh, color: accent.withOpacity(0.95)),
                ),
              ],
            ),
            body: Container(
              // For Night Gold and Midnight Blue this is a flat
              // [background] paint (no behavioural change). For Midday Gold
              // [tokens.pageGradient] paints BookingsHub's vertical
              // warm-espresso gradient behind the whole list, so the
              // History scaffold reads as Midday Gold instead of flat
              // dark gold.
              decoration: BoxDecoration(
                color: background,
                gradient: tokens.pageGradient,
              ),
              child: FutureBuilder<List<_TripHistoryItem>>(
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
                    Color? valueColor,
                  }) {
                    final resolvedValueColor = valueColor ?? textPrimary;
                    return Container(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      decoration: tileDecoration(),
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
                                child: Icon(
                                  icon,
                                  size: 13.5,
                                  color: accentColor,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textMuted,
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
                              color: resolvedValueColor,
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
                    final legBadgeText = _historyLegBadgeText(item);
                    final originText = _displayHistoryOrigin(item.origin);
                    final kindOrCustomer =
                        (item.customerName ?? '').trim().isNotEmpty
                        ? item.customerName!.trim()
                        : '${item.kindLabel}${item.isLocalOnlyDirectFallback ? ' • Lokaal' : ''}';
                    return Container(
                      decoration: cardDecoration(),
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
                                        color: accent.withOpacity(0.28),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${_dateOnly(startedIso)} • ${_timeOnly(startedIso)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: accent.withOpacity(0.95),
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
                                            color: surfaceAlt,
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: accent.withOpacity(0.45),
                                            ),
                                          ),
                                          child: Text(
                                            total,
                                            style: TextStyle(
                                              color: accent.withOpacity(0.98),
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
                                        Icon(
                                          Icons.my_location_rounded,
                                          size: 14,
                                          color: accent,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            originText,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: textPrimary,
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
                                        Icon(
                                          Icons.location_on_outlined,
                                          size: 14,
                                          color: accent,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            item.destination,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: textPrimary,
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
                                        color: textMuted,
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
                                            color: statusColor.withOpacity(
                                              0.15,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: statusColor.withOpacity(
                                                0.55,
                                              ),
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
                                              color: surfaceAlt,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              border: Border.all(
                                                color: accent.withOpacity(0.42),
                                              ),
                                            ),
                                            child: Text(
                                              paymentChip,
                                              style: TextStyle(
                                                color: accent.withOpacity(0.95),
                                                fontSize: 10.8,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        if (legBadgeText != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: surfaceAlt,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              border: Border.all(
                                                color: paletteBorder
                                                    .withOpacity(0.55),
                                              ),
                                            ),
                                            child: Text(
                                              legBadgeText,
                                              style: TextStyle(
                                                color: textPrimary,
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
                                              foregroundColor: textMuted,
                                              side: BorderSide(
                                                color: accent.withOpacity(0.35),
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          ),
                                          FilledButton.icon(
                                            onPressed: () => _openReceipt(item),
                                            icon: const Icon(
                                              Icons.receipt_long,
                                              size: 17,
                                            ),
                                            label: Text(
                                              _receiptText('receiptTitle'),
                                            ),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: accent,
                                              foregroundColor: accentForeground,
                                              visualDensity:
                                                  VisualDensity.compact,
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
                      child: CircularProgressIndicator(color: accent),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: cardDecoration(fallbackBorderOpacity: 0.30),
                        child: Text(
                          '${_receiptText('historyLoadFailed')}\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textMuted),
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
                        decoration: cardDecoration(fallbackBorderOpacity: 0.30),
                        child: Text(
                          _receiptText('historyEmpty'),
                          style: TextStyle(color: textMuted),
                        ),
                      ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                        decoration: overviewDecoration(),
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
                                color: accent.withOpacity(0.98),
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
                                color: textMuted,
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
                                              accentColor: const Color(
                                                0xFF60A5FA,
                                              ),
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
                                              value: summary.completed
                                                  .toString(),
                                              icon: Icons
                                                  .check_circle_outline_rounded,
                                              accentColor: const Color(
                                                0xFF4ADE80,
                                              ),
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
                                              value: summary.cancelled
                                                  .toString(),
                                              icon: Icons.cancel_outlined,
                                              accentColor: const Color(
                                                0xFFF97373,
                                              ),
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
                                              value: _formatEur(
                                                summary.revenue,
                                              ),
                                              icon: Icons.euro_rounded,
                                              accentColor: accent,
                                              valueColor: accent,
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
                                        icon:
                                            Icons.check_circle_outline_rounded,
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
                                        accentColor: accent,
                                        valueColor: accent,
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
                                      decoration: filterChipDecoration(
                                        active: active,
                                      ),
                                      child: Text(
                                        tabLabels[filter]!,
                                        style: TextStyle(
                                          color: filterChipTextColor(
                                            active: active,
                                          ),
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
                          color: accent.withOpacity(0.95),
                          fontWeight: FontWeight.w800,
                          fontSize: 13.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (filteredItems.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: cardDecoration(),
                          child: Text(
                            _receiptText('historyEmpty'),
                            style: TextStyle(color: textMuted),
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
        },
      ),
    );
  }
}
