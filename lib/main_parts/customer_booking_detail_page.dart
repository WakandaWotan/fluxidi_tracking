part of '../main.dart';

/// Customer-facing booking detail screen. Read-only; pull-to-refresh re-fetches
/// the same `GET /bookings/{id}` endpoint. Does not expose driver/admin data
/// or modify any backend state.
class CustomerBookingDetailPage extends StatefulWidget {
  const CustomerBookingDetailPage({
    super.key,
    required this.bookingId,
    required this.initialView,
    this.startsFromLocalCache = false,
  });

  final String bookingId;
  final CustomerBookingView initialView;
  final bool startsFromLocalCache;

  @override
  State<CustomerBookingDetailPage> createState() =>
      _CustomerBookingDetailPageState();
}

class _CustomerBookingDetailPageState extends State<CustomerBookingDetailPage> {
  late CustomerBookingView _view = widget.initialView;
  late String _derivedPaymentDisplayToken =
      _classifyCustomerPaymentDisplayToken(
        aliases: _paymentAliasesForView(widget.initialView),
        fallbackToken: widget.initialView.rawPaymentStatus,
      );
  bool _refreshing = false;
  bool _cancelling = false;
  bool _ratingSubmitting = false;
  bool _ratingSessionChecked = false;
  bool _hasValidRatingSession = false;
  String? _refreshError;
  late bool _usingLocalCache = widget.startsFromLocalCache;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void initState() {
    super.initState();
    unawaited(_refreshRatingSessionState());
    unawaited(_refreshDerivedPaymentClassification(view: _view));
    unawaited(_refresh());
  }

  Future<void> _refreshRatingSessionState() async {
    final session = await CustomerSessionStore.instance.loadValidSession();
    final token = (session?.customerSessionToken ?? '').trim();
    if (!mounted) return;
    setState(() {
      _ratingSessionChecked = true;
      _hasValidRatingSession = token.isNotEmpty;
    });
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _refreshError = null;
    });
    try {
      final aliases = _customerBookingDeleteAliases(
        bookingId: widget.bookingId,
        publicBookingReference: _view.publicBookingReference,
        bookingReference: _view.publicBookingReference,
        publicReference: _view.publicBookingReference,
        planningReference: _view.planningReference,
        receiptReference: _view.receiptReference,
        source: _view.source,
      );
      final proof = await _customerOwnershipProof(
        bookingId: widget.bookingId,
        aliases: aliases,
        fallbackEmail: _view.customerEmail,
        fallbackPhone: _view.customerPhone,
        source: _view.source,
      );
      final scopeSource = <String, dynamic>{
        ..._view.source,
        'record': _view.record,
        'booking': _view.booking,
      };
      final tenantFromStored = _cancelScopeFirstNonEmpty(scopeSource, const [
        'tenant_id',
        'tenantId',
        'record.tenant_id',
        'record.tenantId',
        'record.booking.tenant_id',
        'record.booking.tenantId',
        'record.payload.tenant_id',
        'record.payload.tenantId',
        'booking.tenant_id',
        'booking.tenantId',
        'payload.tenant_id',
        'payload.tenantId',
        'data.tenant_id',
        'data.tenantId',
        'data.record.tenant_id',
        'data.record.tenantId',
      ]);
      final companyFromStored = _cancelScopeFirstNonEmpty(scopeSource, const [
        'company_id',
        'companyId',
        'record.company_id',
        'record.companyId',
        'record.booking.company_id',
        'record.booking.companyId',
        'record.payload.company_id',
        'record.payload.companyId',
        'booking.company_id',
        'booking.companyId',
        'payload.company_id',
        'payload.companyId',
        'data.company_id',
        'data.companyId',
        'data.record.company_id',
        'data.record.companyId',
      ]);
      final refreshScope =
          tenantFromStored.isNotEmpty && companyFromStored.isNotEmpty
          ? <String, String>{
              'tenant_id': tenantFromStored,
              'company_id': companyFromStored,
              'tenantId': tenantFromStored,
              'companyId': companyFromStored,
            }
          : _activeBookingScopeQuery();
      final uri = Uri.parse(
        '$kBookingBaseUrl/bookings/${Uri.encodeComponent(widget.bookingId)}',
      ).replace(queryParameters: <String, String>{...refreshScope, ...proof});
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, dynamic> && decoded['ok'] == true) {
          final authoritativeView = CustomerBookingView.fromResponse(
            widget.bookingId,
            decoded,
          );
          final sourceTag = (authoritativeView.record['quote'] is Map)
              ? 'record.quote'
              : ((authoritativeView.source['quote'] is Map)
                    ? 'quote'
                    : 'record.booking');
          debugPrint(
            '[BOOKING_DETAIL][HYDRATE] fromFound=${authoritativeView.fromAddress.trim().isNotEmpty} toFound=${authoritativeView.toAddress.trim().isNotEmpty} priceFound=${authoritativeView.totalAmount != null} source=$sourceTag',
          );
          final view = authoritativeView.mergedWithExisting(_view);
          final localFallback = StoredCustomerBooking(
            bookingId: _view.bookingId,
            publicBookingId: _view.bookingId,
            customerName: _view.customerName,
            customerPhone: _view.customerPhone,
            customerEmail: _view.customerEmail,
            from: _view.fromAddress,
            to: _view.toAddress,
            pickupIso: _view.pickupIso,
            price: _view.totalAmount,
            currency: _view.currency,
            service: _view.service,
            tier: _view.tier,
            pax: _view.pax,
            bags: _view.bags,
            paymentStatus: _view.rawPaymentStatus,
            status: _view.lifecycleStatus,
            createdAt: DateTime.now().toIso8601String(),
            updatedAt: DateTime.now().toIso8601String(),
          );
          final stored = StoredCustomerBooking.fromAuthoritativeResponse(
            bookingId: widget.bookingId,
            response: decoded,
            fallback: localFallback,
          );
          await CustomerBookingsStore.instance.upsert(
            _hydrateStoredCustomerBookingFromView(
              stored: stored,
              view: view,
              source: 'customer_detail_refresh',
            ),
          );
          final derivedPaymentToken = await _derivePaymentDisplayToken(
            view: view,
            preferredScopeQuery: refreshScope,
          );
          if (!mounted) return;
          setState(() {
            _view = view;
            _derivedPaymentDisplayToken = derivedPaymentToken;
            _usingLocalCache = false;
            _refreshing = false;
          });
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _usingLocalCache = true;
        _refreshError = _t(
          nl: 'Vernieuwen mislukt.',
          en: 'Refresh failed.',
          fr: "Echec de l'actualisation.",
          es: 'Error al actualizar.',
        );
      });
    } catch (err) {
      if (!mounted) return;
      debugPrint(
        '[CUSTOMER_DETAIL][REFRESH_ERROR] bookingId=${widget.bookingId} error=$err',
      );
      setState(() {
        _refreshing = false;
        _usingLocalCache = true;
        _refreshError = _t(
          nl: 'Verbinding mislukt. Probeer het opnieuw.',
          en: 'Connection failed. Please try again.',
          fr: 'Connexion echouee. Veuillez reessayer.',
          es: 'Conexion fallida. Intentalo de nuevo.',
        );
      });
    }
  }

  static Set<String> _paymentAliasesForView(CustomerBookingView view) {
    final paymentBookingId =
        _customerBookingAliasFirstNonEmpty(view.source, const <String>[
          'payment_booking_id',
          'paymentBookingId',
          'record.payment_booking_id',
          'record.paymentBookingId',
          'record.booking.payment_booking_id',
          'record.booking.paymentBookingId',
          'booking.payment_booking_id',
          'booking.paymentBookingId',
          'payload.payment_booking_id',
          'payload.paymentBookingId',
          'payload.booking.payment_booking_id',
          'payload.booking.paymentBookingId',
        ]);
    final bookingReference =
        _customerBookingAliasFirstNonEmpty(view.source, const <String>[
          'booking_reference',
          'bookingReference',
          'record.booking_reference',
          'record.bookingReference',
          'record.booking.booking_reference',
          'record.booking.bookingReference',
          'booking.booking_reference',
          'booking.bookingReference',
          'payload.booking_reference',
          'payload.bookingReference',
          'payload.booking.booking_reference',
          'payload.booking.bookingReference',
        ]);
    final publicReference =
        _customerBookingAliasFirstNonEmpty(view.source, const <String>[
          'public_reference',
          'publicReference',
          'record.public_reference',
          'record.publicReference',
          'record.booking.public_reference',
          'record.booking.publicReference',
          'booking.public_reference',
          'booking.publicReference',
          'payload.public_reference',
          'payload.publicReference',
          'payload.booking.public_reference',
          'payload.booking.publicReference',
        ]);
    final parentBookingId =
        _customerBookingAliasFirstNonEmpty(view.source, const <String>[
          'parent_booking_id',
          'parentBookingId',
          'record.parent_booking_id',
          'record.parentBookingId',
          'record.booking.parent_booking_id',
          'record.booking.parentBookingId',
          'booking.parent_booking_id',
          'booking.parentBookingId',
          'payload.parent_booking_id',
          'payload.parentBookingId',
          'payload.booking.parent_booking_id',
          'payload.booking.parentBookingId',
        ]);
    final originalBookingId =
        _customerBookingAliasFirstNonEmpty(view.source, const <String>[
          'original_booking_id',
          'originalBookingId',
          'record.original_booking_id',
          'record.originalBookingId',
          'record.booking.original_booking_id',
          'record.booking.originalBookingId',
          'booking.original_booking_id',
          'booking.originalBookingId',
          'payload.original_booking_id',
          'payload.originalBookingId',
          'payload.booking.original_booking_id',
          'payload.booking.originalBookingId',
        ]);
    return _customerBookingDeleteAliases(
      bookingId: view.internalBookingId,
      publicBookingReference: view.publicBookingReference,
      bookingReference: bookingReference,
      publicReference: publicReference,
      planningReference: view.planningReference,
      receiptReference: view.receiptReference,
      paymentBookingId: paymentBookingId,
      parentBookingId: parentBookingId,
      originalBookingId: originalBookingId,
      source: view.source,
    );
  }

  static dynamic _customerBookingAliasValueAtPath(
    Map<String, dynamic> source,
    String path,
  ) {
    dynamic current = source;
    for (final segment in path.split('.')) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }

  static String _customerBookingAliasFirstNonEmpty(
    Map<String, dynamic> source,
    List<String> paths,
  ) {
    for (final path in paths) {
      final raw = _customerBookingAliasValueAtPath(source, path);
      final text = raw?.toString().trim() ?? '';
      if (text.isNotEmpty &&
          text.toLowerCase() != 'null' &&
          text.toLowerCase() != 'undefined') {
        return text;
      }
    }
    return '';
  }

  Future<String> _derivePaymentDisplayToken({
    required CustomerBookingView view,
    Map<String, String>? preferredScopeQuery,
  }) async {
    final aliases = _paymentAliasesForView(view);
    final fallbackToken = view.rawPaymentStatus;
    final scopeQuery = preferredScopeQuery ?? _selectedCancelScopeQuery();
    if (scopeQuery == null || scopeQuery.isEmpty) {
      return _classifyCustomerPaymentDisplayToken(
        aliases: aliases,
        fallbackToken: fallbackToken,
      );
    }
    try {
      final trips = await _fetchTrackingOverlayTrips(
        scopeQuery: scopeQuery,
        diagTag: 'CUSTOMER_PAYMENT',
        limit: 200,
      );
      final matcher = _TrackingPaymentOverlayMatcher(trips);
      final token = _classifyCustomerPaymentDisplayToken(
        aliases: aliases,
        fallbackToken: fallbackToken,
        matcher: matcher,
      );
      debugPrint(
        '[CUSTOMER_PAYMENT][DETAIL_CLASSIFY] booking=${_safeRefPreview(view.internalBookingId)} token=$token aliases=${aliases.length}',
      );
      return token;
    } catch (err) {
      debugPrint('[CUSTOMER_PAYMENT][DETAIL_CLASSIFY] fallback error=$err');
      return _classifyCustomerPaymentDisplayToken(
        aliases: aliases,
        fallbackToken: fallbackToken,
      );
    }
  }

  Future<void> _refreshDerivedPaymentClassification({
    required CustomerBookingView view,
    Map<String, String>? preferredScopeQuery,
  }) async {
    final token = await _derivePaymentDisplayToken(
      view: view,
      preferredScopeQuery: preferredScopeQuery,
    );
    if (!mounted) return;
    setState(() {
      _derivedPaymentDisplayToken = token;
    });
  }

  String _formatPickup(String iso) {
    if (iso.isEmpty) return '-';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final local = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String _formatPrice(double? amount, String currency) {
    if (amount == null) return '-';
    final cur = currency.toUpperCase();
    final symbol = cur.isEmpty || cur == 'EUR' ? '€' : '$cur ';
    final formatted = amount.toStringAsFixed(2).replaceAll('.', ',');
    return '$symbol$formatted';
  }

  String _notFilled() => _t(
    nl: 'Nog niet ingevuld',
    en: 'Not filled in yet',
    fr: 'Pas encore renseigne',
    es: 'Aún no completado',
  );

  ({String label, String value, String? internalSecondary})
  _customerBookingReferenceDisplay(CustomerBookingView view) {
    final publicRef = view.publicBookingReference.trim();
    final planningRef = view.planningReference.trim();
    final receiptRef = view.receiptReference.trim();
    final internalRef = view.internalBookingId.trim();

    final selectedValue = publicRef.isNotEmpty
        ? publicRef
        : (receiptRef.isNotEmpty
              ? receiptRef
              : (planningRef.isNotEmpty
                    ? planningRef
                    : (internalRef.isNotEmpty ? internalRef : '-')));
    final selectedLabel = publicRef.isNotEmpty
        ? _t(
            nl: 'Boekingsnummer',
            en: 'Booking no.',
            fr: 'N° de réservation',
            es: 'N.º de reserva',
          )
        : (receiptRef.isNotEmpty
              ? _t(
                  nl: 'Bonnummer',
                  en: 'Receipt no.',
                  fr: 'N° de reçu',
                  es: 'N.º de recibo',
                )
              : (planningRef.isNotEmpty
                    ? _t(
                        nl: 'Planningnummer',
                        en: 'Planning no.',
                        fr: 'N° de planning',
                        es: 'N.º de planificación',
                      )
                    : _t(
                        nl: 'Interne boeking',
                        en: 'Internal booking',
                        fr: 'Réservation interne',
                        es: 'Reserva interna',
                      )));
    final internalSecondary =
        internalRef.isNotEmpty && internalRef != selectedValue
        ? internalRef
        : null;

    debugPrint(
      '[CUSTOMER_BOOKING][REF_SELECTED] booking=${_safeRefPreview(internalRef)} public=$publicRef planning=$planningRef receipt=$receiptRef selected=$selectedValue',
    );
    return (
      label: selectedLabel,
      value: selectedValue,
      internalSecondary: internalSecondary,
    );
  }

  Future<void> _openExternalUrl(BuildContext context, String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Kon link niet openen.',
              en: 'Could not open link.',
              fr: "Impossible d'ouvrir le lien.",
              es: 'No se pudo abrir el enlace.',
            ),
          ),
        ),
      );
    }
  }

  bool get _canRateCompletedBooking {
    final normalized = _normalizeCustomerLifecycleStatus(_view.lifecycleStatus);
    return normalized == 'COMPLETED';
  }

  Map<String, dynamic>? _existingCustomerRatingBlock() {
    final candidates = <dynamic>[
      _cancelScopeValueAtPath(_view.source, 'customer_rating'),
      _cancelScopeValueAtPath(_view.source, 'customerRating'),
      _cancelScopeValueAtPath(_view.source, 'record.customer_rating'),
      _cancelScopeValueAtPath(_view.source, 'record.customerRating'),
      _cancelScopeValueAtPath(_view.source, 'record.booking.customer_rating'),
      _cancelScopeValueAtPath(_view.source, 'record.booking.customerRating'),
      _cancelScopeValueAtPath(_view.source, 'booking.customer_rating'),
      _cancelScopeValueAtPath(_view.source, 'booking.customerRating'),
    ];
    for (final raw in candidates) {
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    }
    return null;
  }

  int? _existingCustomerRatingValue() {
    final block = _existingCustomerRatingBlock();
    if (block == null) return null;
    final raw = block['rating'] ?? block['stars'];
    if (raw is int && raw >= 1 && raw <= 5) return raw;
    if (raw is num) {
      final rounded = raw.round();
      if (rounded >= 1 && rounded <= 5) return rounded;
    }
    final parsed = int.tryParse((raw ?? '').toString().trim());
    if (parsed == null || parsed < 1 || parsed > 5) return null;
    return parsed;
  }

  String _existingCustomerRatingComment() {
    final block = _existingCustomerRatingBlock();
    if (block == null) return '';
    return (block['comment'] ?? block['review'] ?? '').toString().trim();
  }

  String _customerRatingErrorMessage(String code) {
    switch (code) {
      case 'unauthorized':
        return _t(
          nl: 'Verifieer je klantprofiel om deze rit te beoordelen.',
          en: 'Verify your customer profile to rate this ride.',
          fr: 'Reconnectez-vous pour évaluer votre course.',
          es: 'Vuelve a iniciar sesión para valorar tu viaje.',
        );
      case 'booking_not_completed':
        return _t(
          nl: 'Je kunt alleen een voltooide rit beoordelen.',
          en: 'You can only rate a completed ride.',
          fr: 'Vous pouvez uniquement évaluer une course terminée.',
          es: 'Solo puedes valorar un viaje completado.',
        );
      case 'forbidden':
        return _t(
          nl: 'Deze rit hoort niet bij het actieve klantprofiel. Verifieer je boeking opnieuw.',
          en: 'This ride does not belong to the active customer profile. Verify your booking again.',
          fr: 'Vous pouvez uniquement évaluer votre propre course.',
          es: 'Solo puedes valorar tu propio viaje.',
        );
      case 'invalid_rating':
        return _t(
          nl: 'Kies een beoordeling tussen 1 en 5 sterren.',
          en: 'Choose a rating between 1 and 5 stars.',
          fr: 'Choisissez une note entre 1 et 5 étoiles.',
          es: 'Elige una valoración entre 1 y 5 estrellas.',
        );
      default:
        return _t(
          nl: 'Beoordeling opslaan is mislukt. Probeer opnieuw.',
          en: 'Saving your rating failed. Please try again.',
          fr: "L'enregistrement de votre évaluation a échoué. Réessayez.",
          es: 'No se pudo guardar tu valoración. Inténtalo de nuevo.',
        );
    }
  }

  String _ratingUiSafeError(dynamic value) {
    final raw = (value ?? '').toString();
    final compact = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) return 'unknown';
    return compact.length > 120 ? compact.substring(0, 120) : compact;
  }

  Future<Map<String, dynamic>?> _openCustomerRatingSheet({
    required int initialRating,
    required String initialComment,
  }) async {
    final controller = TextEditingController(text: initialComment);
    var selectedRating = initialRating.clamp(1, 5);
    try {
      return await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF101113),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              return Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 14,
                  bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t(
                        nl: 'Beoordeel rit',
                        en: 'Rate ride',
                        fr: 'Évaluer la course',
                        es: 'Valorar viaje',
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: List<Widget>.generate(5, (index) {
                        final star = index + 1;
                        return IconButton(
                          onPressed: () {
                            setModalState(() {
                              selectedRating = star;
                            });
                          },
                          icon: Icon(
                            selectedRating >= star
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: const Color(0xFFE5B641),
                            size: 28,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: controller,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 500,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: _t(
                          nl: 'Opmerking (optioneel)',
                          en: 'Comment (optional)',
                          fr: 'Commentaire (optionnel)',
                          es: 'Comentario (opcional)',
                        ),
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: const Color(0xFF16120A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: kFluxidiYellow.withOpacity(0.22),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop(<String, dynamic>{
                            'rating': selectedRating,
                            'comment': controller.text.trim(),
                          });
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: kFluxidiYellow,
                          foregroundColor: Colors.black,
                        ),
                        child: Text(
                          _t(
                            nl: 'Beoordeling opslaan',
                            en: 'Save rating',
                            fr: "Enregistrer l'évaluation",
                            es: 'Guardar valoración',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _openRatingFlow() async {
    if (!_canRateCompletedBooking || _ratingSubmitting) return;
    final initialRating = _existingCustomerRatingValue() ?? 5;
    final initialComment = _existingCustomerRatingComment();
    final draft = await _openCustomerRatingSheet(
      initialRating: initialRating,
      initialComment: initialComment,
    );
    if (draft == null || !mounted) return;
    final rating = (draft['rating'] is num)
        ? (draft['rating'] as num).toInt()
        : int.tryParse((draft['rating'] ?? '').toString().trim());
    if (rating == null || rating < 1 || rating > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_customerRatingErrorMessage('invalid_rating'))),
      );
      return;
    }
    final comment = (draft['comment'] ?? '').toString().trim();
    final bookingId = widget.bookingId.trim();
    if (bookingId.isEmpty) return;
    final session = await CustomerSessionStore.instance.loadValidSession();
    final token = (session?.customerSessionToken ?? '').trim();
    debugPrint(
      '[CUSTOMER_RATING_UI][SUBMIT_START] booking=${_safeRefPreview(bookingId)} completed=${_canRateCompletedBooking ? 'true' : 'false'} has_session=${token.isNotEmpty ? 'true' : 'false'}',
    );
    if (session == null || token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_customerRatingErrorMessage('unauthorized'))),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _ratingSubmitting = true;
    });
    try {
      final uri = Uri.parse(
        '$kBookingBaseUrl/public/customer/bookings/${Uri.encodeComponent(bookingId)}/rating',
      );
      final res = await http
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(<String, dynamic>{
              'rating': rating,
              if (comment.isNotEmpty) 'comment': comment,
            }),
          )
          .timeout(const Duration(seconds: 15));
      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        decoded = null;
      }
      final map = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : const <String, dynamic>{};
      final ok =
          res.statusCode >= 200 && res.statusCode < 300 && map['ok'] == true;
      debugPrint(
        '[CUSTOMER_RATING_UI][SUBMIT_RESULT] status=${res.statusCode} ok=${ok ? 'true' : 'false'} error=${_ratingUiSafeError(map['error'])}',
      );
      if (!ok) {
        final errorCode = (map['error'] ?? 'unknown').toString().trim();
        throw Exception(errorCode.isEmpty ? 'unknown' : errorCode);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Bedankt voor je beoordeling.',
              en: 'Thanks for your rating.',
              fr: 'Merci pour votre évaluation.',
              es: 'Gracias por tu valoración.',
            ),
          ),
        ),
      );
      await _refresh();
    } catch (err) {
      debugPrint(
        '[CUSTOMER_RATING_UI][SUBMIT_ERROR] error=${_ratingUiSafeError(err)}',
      );
      if (!mounted) return;
      final errorText = err.toString();
      String errorCode = 'unknown';
      if (errorText.contains('booking_not_completed')) {
        errorCode = 'booking_not_completed';
      } else if (errorText.contains('unauthorized')) {
        errorCode = 'unauthorized';
      } else if (errorText.contains('forbidden')) {
        errorCode = 'forbidden';
      } else if (errorText.contains('invalid_rating')) {
        errorCode = 'invalid_rating';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_customerRatingErrorMessage(errorCode))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _ratingSubmitting = false;
        });
      }
    }
  }

  _TripHistoryItem _asTripHistoryItem() {
    final publicRef = _view.publicBookingReference.trim();
    final planningRef = _view.planningReference.trim();
    final receiptRef = _view.receiptReference.trim();
    final refs = <String, dynamic>{};
    void setRef(String key, String value) {
      if (value.isEmpty) return;
      refs[key] = value;
    }

    setRef('public_booking_reference', publicRef);
    setRef('publicBookingReference', publicRef);
    setRef('booking_reference', publicRef);
    setRef('bookingReference', publicRef);
    setRef('public_reference', publicRef);
    setRef('publicReference', publicRef);
    setRef('planning_reference', planningRef);
    setRef('planningReference', planningRef);
    setRef('receipt_reference', receiptRef);
    setRef('receiptReference', receiptRef);

    final bookingDetails = <String, dynamic>{
      ..._view.source,
      'booking_id': _view.bookingId,
      'bookingId': _view.bookingId,
      ...refs,
      'customer_name': _view.customerName,
      'customer_phone': _view.customerPhone,
      'customer_email': _view.customerEmail,
      'from': _view.fromAddress,
      'to': _view.toAddress,
      'service_type': _view.service,
      'tier': _view.tier,
      'passengers': _view.pax,
      'luggage_count': _view.bags,
      'distance_km': _view.distanceKm,
      'duration_min': _view.durationMin,
      'booking_total_eur': _view.totalAmount,
      'currency': _view.currency,
      'payment_status': _view.rawPaymentStatus,
      'payment_method': _view.paymentMethod,
      'company_name': _view.companyName,
      'vat_number': _view.vatNumber,
      'invoice_email': _view.invoiceEmail,
      'invoice_address': _view.invoiceAddress,
      'extras': _view.extraOptions,
      'scheduled_pickup_at': _view.pickupIso,
      'references': refs,
      'booking': <String, dynamic>{
        ...refs,
        'booking_id': _view.bookingId,
        'bookingId': _view.bookingId,
        'customer_name': _view.customerName,
        'customer_phone': _view.customerPhone,
        'customer_email': _view.customerEmail,
        'from': _view.fromAddress,
        'to': _view.toAddress,
        'service_type': _view.service,
        'tier': _view.tier,
        'payment_status': _view.rawPaymentStatus,
      },
    };

    return _TripHistoryItem.fromJson(<String, dynamic>{
      'trip_id': _view.bookingId,
      'booking_id': _view.bookingId,
      'kind': 'planned',
      'status': _view.lifecycleStatus,
      'started_at': _view.pickupIso,
      'stopped_at': _view.pickupIso,
      'origin': _view.fromAddress,
      'destination': _view.toAddress,
      'wait_seconds_total': 0,
      'total_eur': _view.totalAmount,
      'currency': _view.currency,
      'booking_details': bookingDetails,
    });
  }

  Future<void> _openReceiptAction(
    BuildContext context,
    _ReceiptQuickAction action,
  ) async {
    final item = _asTripHistoryItem();
    switch (action) {
      case _ReceiptQuickAction.viewPdf:
        await _ReceiptPdfActionRunner.previewPdf(context: context, item: item);
        break;
      case _ReceiptQuickAction.sharePdf:
        await _ReceiptPdfActionRunner.sharePdf(context: context, item: item);
        break;
      case _ReceiptQuickAction.whatsappPdf:
        await _ReceiptPdfActionRunner.sharePdfViaWhatsApp(
          context: context,
          item: item,
        );
        break;
      case _ReceiptQuickAction.emailPdf:
        await _ReceiptPdfActionRunner.sharePdfViaEmail(
          context: context,
          item: item,
        );
        break;
      case _ReceiptQuickAction.printPdf:
        await _ReceiptPdfActionRunner.printPdf(context: context, item: item);
        break;
    }
  }

  Future<void> _removeFromMyBookings() async {
    final bookingId = widget.bookingId.trim();
    if (bookingId.isEmpty) return;
    if (!_canLocalRemoveBookingOnly) {
      debugPrint(
        '[CUSTOMER_BOOKINGS][ACTIVE_REMOVE_REDIRECT_CANCEL] booking=${_safeRefPreview(bookingId)}',
      );
      await _cancelBookingServerSide();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _t(
            nl: 'Verwijderen uit mijn lijst?',
            en: 'Remove from my list?',
            fr: 'Supprimer de ma liste ?',
            es: '¿Eliminar de mi lista?',
          ),
        ),
        content: Text(
          _t(
            nl: 'Deze boeking wordt alleen uit je lijst verwijderd.',
            en: 'This booking will only be removed from your list.',
            fr: 'Cette réservation sera uniquement supprimée de votre liste.',
            es: 'Esta reserva solo se eliminará de tu lista.',
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
                nl: 'Verwijderen uit mijn lijst',
                en: 'Remove from my list',
                fr: 'Supprimer de ma liste',
                es: 'Eliminar de mi lista',
              ),
            ),
          ),
        ],
      ),
    );
    debugPrint(
      '[CUSTOMER_BOOKINGS][DELETE_CONFIRM] action=detail_remove_one confirmed=${confirmed == true} booking=${_safeRefPreview(bookingId)}',
    );
    if (confirmed != true || !mounted) return;
    final result = await _removeLocalCustomerBookingEverywhere(
      bookingForLog: bookingId,
      aliases: _customerBookingDeleteAliases(
        bookingId: bookingId,
        publicBookingReference: _view.publicBookingReference,
        bookingReference: _view.publicBookingReference,
        publicReference: _view.publicBookingReference,
        planningReference: _view.planningReference,
        receiptReference: _view.receiptReference,
        source: _view.source,
      ),
    );
    final aliases = _customerBookingDeleteAliases(
      bookingId: bookingId,
      publicBookingReference: _view.publicBookingReference,
      bookingReference: _view.publicBookingReference,
      publicReference: _view.publicBookingReference,
      planningReference: _view.planningReference,
      receiptReference: _view.receiptReference,
      source: _view.source,
    );
    final localAfterDelete = await CustomerBookingsStore.instance.loadAll();
    final stillExists = localAfterDelete.any(
      (entry) => _customerAliasesIntersect(
        _customerBookingAliasesFromStored(entry),
        aliases,
      ),
    );
    if (!mounted) return;
    if (result.removed || !stillExists) {
      debugPrint(
        '[CUSTOMER_BOOKING][DELETE_POP] booking=${_safeRefPreview(bookingId)} reason=${result.removed ? 'removed' : 'already_absent'}',
      );
      Navigator.of(
        context,
      ).pop(<String, dynamic>{'action': _customerDetailResultRemovedLocal});
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            nl: 'Boeking niet gevonden in lokale opslag.',
            en: 'Booking not found in local storage.',
            fr: 'Réservation introuvable dans le stockage local.',
            es: 'Reserva no encontrada en el almacenamiento local.',
          ),
        ),
      ),
    );
  }

  Map<String, String> _cancelHeaders() {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (kAdminToken.trim().isNotEmpty) {
      h['x-admin-token'] = kAdminToken.trim();
    }
    return h;
  }

  dynamic _cancelScopeValueAtPath(Map<String, dynamic> source, String path) {
    dynamic current = source;
    for (final segment in path.split('.')) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }

  String _cancelScopeFirstNonEmpty(
    Map<String, dynamic> source,
    List<String> paths,
  ) {
    for (final path in paths) {
      final raw = _cancelScopeValueAtPath(source, path);
      final text = raw?.toString().trim() ?? '';
      if (text.isNotEmpty &&
          text.toLowerCase() != 'null' &&
          text.toLowerCase() != 'undefined') {
        return text;
      }
    }
    return '';
  }

  bool _isUnsafeDefaultCancelScope({
    required String tenantId,
    required String companyId,
  }) {
    final fallback = kTenantId.trim().toLowerCase();
    final tenant = tenantId.trim().toLowerCase();
    final company = companyId.trim().toLowerCase();
    return tenant.isNotEmpty &&
        company.isNotEmpty &&
        tenant == fallback &&
        company == fallback;
  }

  Map<String, String> _scopeQueryFromTenantCompany({
    required String tenantId,
    required String companyId,
  }) {
    return <String, String>{
      'tenant_id': tenantId,
      'company_id': companyId,
      'tenantId': tenantId,
      'companyId': companyId,
    };
  }

  Map<String, String>? _strictActiveCustomerBookingScopeQuery() {
    final strictScope = _strictActiveLocalScopeIds();
    if (strictScope == null) return null;
    final tenantId = strictScope.tenantId.trim();
    final companyId = strictScope.companyId.trim();
    if (tenantId.isEmpty || companyId.isEmpty) return null;
    if (_isUnsafeDefaultCancelScope(tenantId: tenantId, companyId: companyId)) {
      debugPrint(
        '[CUSTOMER_BOOKING][CANCEL_SCOPE][SKIP] reason=unsafe_default_scope source=strict_active_scope tenant=$tenantId company=$companyId',
      );
      return null;
    }
    return _scopeQueryFromTenantCompany(
      tenantId: tenantId,
      companyId: companyId,
    );
  }

  Map<String, String>? _selectedCancelScopeQuery() {
    final storedScopeSource = <String, dynamic>{
      'record': _view.record,
      'booking': _view.booking,
    };
    final tenantFromStoredBooking =
        _cancelScopeFirstNonEmpty(storedScopeSource, const [
          'tenant_id',
          'tenantId',
          'record.tenant_id',
          'record.tenantId',
          'record.booking.tenant_id',
          'record.booking.tenantId',
          'booking.tenant_id',
          'booking.tenantId',
        ]);
    final companyFromStoredBooking =
        _cancelScopeFirstNonEmpty(storedScopeSource, const [
          'company_id',
          'companyId',
          'record.company_id',
          'record.companyId',
          'record.booking.company_id',
          'record.booking.companyId',
          'booking.company_id',
          'booking.companyId',
        ]);
    if (tenantFromStoredBooking.isNotEmpty &&
        companyFromStoredBooking.isNotEmpty) {
      if (_isUnsafeDefaultCancelScope(
        tenantId: tenantFromStoredBooking,
        companyId: companyFromStoredBooking,
      )) {
        debugPrint(
          '[CUSTOMER_BOOKING][CANCEL_SCOPE][SKIP] reason=unsafe_default_scope source=stored_booking_scope tenant=$tenantFromStoredBooking company=$companyFromStoredBooking',
        );
      } else {
        debugPrint(
          '[CUSTOMER_BOOKING][CANCEL_SCOPE] tenant=$tenantFromStoredBooking company=$companyFromStoredBooking source=booking_scope',
        );
        return _scopeQueryFromTenantCompany(
          tenantId: tenantFromStoredBooking,
          companyId: companyFromStoredBooking,
        );
      }
    }
    final scopeSource = <String, dynamic>{
      ..._view.source,
      'record': _view.record,
      'booking': _view.booking,
    };
    final tenantFromBooking = _cancelScopeFirstNonEmpty(scopeSource, const [
      'tenant_id',
      'tenantId',
      'tenant',
      'record.tenant_id',
      'record.tenantId',
      'record.tenant',
      'record.booking.tenant_id',
      'record.booking.tenantId',
      'record.booking.tenant',
      'record.payload.tenant_id',
      'record.payload.tenantId',
      'record.payload.tenant',
      'booking.tenant_id',
      'booking.tenantId',
      'booking.tenant',
      'payload.tenant_id',
      'payload.tenantId',
      'payload.tenant',
      'data.tenant_id',
      'data.tenantId',
      'data.tenant',
      'data.record.tenant_id',
      'data.record.tenantId',
      'data.record.tenant',
      'data.record.booking.tenant_id',
      'data.record.booking.tenantId',
      'data.record.booking.tenant',
      'data.record.payload.tenant_id',
      'data.record.payload.tenantId',
      'data.record.payload.tenant',
    ]);
    final companyFromBooking = _cancelScopeFirstNonEmpty(scopeSource, const [
      'company_id',
      'companyId',
      'company',
      'record.company_id',
      'record.companyId',
      'record.company',
      'record.booking.company_id',
      'record.booking.companyId',
      'record.booking.company',
      'record.payload.company_id',
      'record.payload.companyId',
      'record.payload.company',
      'booking.company_id',
      'booking.companyId',
      'booking.company',
      'payload.company_id',
      'payload.companyId',
      'payload.company',
      'data.company_id',
      'data.companyId',
      'data.company',
      'data.record.company_id',
      'data.record.companyId',
      'data.record.company',
      'data.record.booking.company_id',
      'data.record.booking.companyId',
      'data.record.booking.company',
      'data.record.payload.company_id',
      'data.record.payload.companyId',
      'data.record.payload.company',
    ]);
    if (tenantFromBooking.isNotEmpty && companyFromBooking.isNotEmpty) {
      if (_isUnsafeDefaultCancelScope(
        tenantId: tenantFromBooking,
        companyId: companyFromBooking,
      )) {
        debugPrint(
          '[CUSTOMER_BOOKING][CANCEL_SCOPE][SKIP] reason=unsafe_default_scope source=booking_scope tenant=$tenantFromBooking company=$companyFromBooking',
        );
      } else {
        debugPrint(
          '[CUSTOMER_BOOKING][CANCEL_SCOPE] tenant=$tenantFromBooking company=$companyFromBooking source=booking_scope',
        );
        return _scopeQueryFromTenantCompany(
          tenantId: tenantFromBooking,
          companyId: companyFromBooking,
        );
      }
    }
    final strictScope = _strictActiveCustomerBookingScopeQuery();
    if (strictScope != null) {
      debugPrint(
        '[CUSTOMER_BOOKING][CANCEL_SCOPE] tenant=${strictScope['tenant_id']} company=${strictScope['company_id']} source=strict_active_scope',
      );
      return strictScope;
    }
    debugPrint(
      '[CUSTOMER_BOOKING][CANCEL_SCOPE][SKIP] reason=missing_strict_scope',
    );
    return null;
  }

  bool get _canCancelBooking {
    return !_isCustomerBookingTerminalStatus(_view.lifecycleStatus);
  }

  bool get _canLocalRemoveBookingOnly {
    return _isCustomerBookingTerminalStatus(_view.lifecycleStatus);
  }

  List<String> _cancelBookingIdCandidates(String primaryBookingId) {
    final candidates = <String>[];
    void addCandidate(String raw) {
      final text = raw.trim();
      if (text.isEmpty) return;
      if (candidates.contains(text)) return;
      candidates.add(text);
    }

    addCandidate(primaryBookingId);
    addCandidate(_view.bookingId);
    addCandidate(_view.publicBookingReference);
    addCandidate(_view.planningReference);
    addCandidate(_view.receiptReference);
    final source = <String, dynamic>{
      ..._view.source,
      'record': _view.record,
      'booking': _view.booking,
    };
    addCandidate(
      _cancelScopeFirstNonEmpty(source, const [
        'booking_id',
        'bookingId',
        'public_booking_id',
        'publicBookingId',
        'id',
        'record.booking_id',
        'record.bookingId',
        'record.public_booking_id',
        'record.publicBookingId',
        'record.id',
        'record.booking.booking_id',
        'record.booking.bookingId',
        'record.booking.public_booking_id',
        'record.booking.publicBookingId',
        'booking.booking_id',
        'booking.bookingId',
        'booking.public_booking_id',
        'booking.publicBookingId',
      ]),
    );
    return candidates;
  }

  bool _isCancellationTransportError(Object err) {
    final text = err.toString().toLowerCase();
    return text.contains('clientsoftware caused connection abort') ||
        text.contains('connection abort') ||
        text.contains('connection reset') ||
        text.contains('socketexception') ||
        text.contains('timeoutexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('uri=https://');
  }

  String _normalizeCancellationFailureReason(String raw) {
    final token = raw.trim().toLowerCase().replaceAll('-', '_');
    if (token.isEmpty) return 'unknown_failure';
    if (token == 'cancellation_window_closed') return token;
    if (token == 'booking_not_found') return token;
    if (token == 'network_error' || token == 'http_0') return 'network_error';
    return token;
  }

  int _cancellationFailurePriority(String reason) {
    switch (_normalizeCancellationFailureReason(reason)) {
      case 'cancellation_window_closed':
        return 4;
      case 'booking_not_found':
        return 3;
      case 'network_error':
        return 2;
      default:
        return 1;
    }
  }

  String _pickStrongerCancellationFailure(String current, String next) {
    final currentReason = _normalizeCancellationFailureReason(current);
    final nextReason = _normalizeCancellationFailureReason(next);
    return _cancellationFailurePriority(nextReason) >
            _cancellationFailurePriority(currentReason)
        ? nextReason
        : currentReason;
  }

  bool _looksLikeCancellationWindowClosed({
    required int statusCode,
    required String errorCode,
    required String reasonCode,
    required String message,
  }) {
    if (statusCode == 409) return true;
    final merged = [
      errorCode,
      reasonCode,
      message,
    ].join(' ').toLowerCase().replaceAll('-', '_');
    return merged.contains('cancellation_window_closed') ||
        merged.contains('annulatietermijn') ||
        merged.contains('cancellation window') ||
        merged.contains('window has passed') ||
        merged.contains('delai d annulation est depasse') ||
        merged.contains('plazo de cancelacion ha vencido');
  }

  ({
    String title,
    String message,
    bool allowRefresh,
    Color accent,
    IconData icon,
  })
  _customerCancellationFailureUi(String reason) {
    switch (reason) {
      case 'cancellation_window_closed':
        return (
          title: _t(
            nl: 'Annuleren niet meer mogelijk',
            en: 'Cancellation no longer possible',
            fr: 'Annulation impossible',
            es: 'Cancelacion no disponible',
          ),
          message: _t(
            nl: 'Deze boeking kan niet meer online geannuleerd worden omdat de annulatietermijn verlopen is. Neem contact op met het taxibedrijf als je hulp nodig hebt.',
            en: 'This booking can no longer be cancelled online because the cancellation window has passed. Please contact the taxi company if you need help.',
            fr: 'Cette reservation ne peut plus etre annulee en ligne car le delai d annulation est depasse. Contactez la compagnie de taxi si vous avez besoin d aide.',
            es: 'Esta reserva ya no puede cancelarse en linea porque el plazo de cancelacion ha vencido. Contacta con la empresa de taxi si necesitas ayuda.',
          ),
          allowRefresh: false,
          accent: const Color(0xFFE76F51),
          icon: Icons.block_rounded,
        );
      case 'booking_not_found':
        return (
          title: _t(
            nl: 'Boeking niet gevonden',
            en: 'Booking not found',
            fr: 'Reservation introuvable',
            es: 'Reserva no encontrada',
          ),
          message: _t(
            nl: 'We konden deze boeking niet opnieuw ophalen. Vernieuw de lijst en probeer opnieuw.',
            en: 'We could not reload this booking. Refresh the list and try again.',
            fr: 'Nous n avons pas pu recharger cette reservation. Actualisez la liste et reessayez.',
            es: 'No pudimos volver a cargar esta reserva. Actualiza la lista e intentalo de nuevo.',
          ),
          allowRefresh: true,
          accent: const Color(0xFFF4C95D),
          icon: Icons.search_off_rounded,
        );
      case 'network_error':
        return (
          title: _t(
            nl: 'Geen verbinding',
            en: 'No connection',
            fr: 'Pas de connexion',
            es: 'Sin conexion',
          ),
          message: _t(
            nl: 'Controleer je internetverbinding en probeer opnieuw.',
            en: 'Check your internet connection and try again.',
            fr: 'Verifiez votre connexion internet et reessayez.',
            es: 'Comprueba tu conexion a internet e intentalo de nuevo.',
          ),
          allowRefresh: true,
          accent: const Color(0xFFF4C95D),
          icon: Icons.wifi_off_rounded,
        );
      default:
        return (
          title: _t(
            nl: 'Annuleren mislukt',
            en: 'Cancellation failed',
            fr: 'Echec de l annulation',
            es: 'No se pudo cancelar',
          ),
          message: _t(
            nl: 'We konden deze boeking niet annuleren. Probeer later opnieuw.',
            en: 'We could not cancel this booking. Please try again later.',
            fr: 'Nous n avons pas pu annuler cette reservation. Reessayez plus tard.',
            es: 'No pudimos cancelar esta reserva. Intentalo de nuevo mas tarde.',
          ),
          allowRefresh: false,
          accent: const Color(0xFFE76F51),
          icon: Icons.error_outline_rounded,
        );
    }
  }

  Future<void> _showCustomerCancellationFailureDialog({
    required String reason,
  }) async {
    if (!mounted) return;
    final ui = _customerCancellationFailureUi(reason);
    final shouldRefresh = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF10141E),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: ui.accent.withValues(alpha: 0.55)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.40),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: ui.accent.withValues(alpha: 0.20),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(ui.icon, color: ui.accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        ui.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  ui.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.90),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (ui.allowRefresh) ...[
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text(
                          _t(
                            nl: 'Vernieuwen',
                            en: 'Refresh',
                            fr: 'Actualiser',
                            es: 'Actualizar',
                          ),
                          style: TextStyle(
                            color: const Color(
                              0xFFF4C95D,
                            ).withValues(alpha: 0.95),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: ui.accent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(
                        _t(
                          nl: 'Begrepen',
                          en: 'Understood',
                          fr: 'Compris',
                          es: 'Entendido',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (shouldRefresh == true && mounted) {
      await _refresh();
    }
  }

  Future<bool> _verifyCancellationServerState({
    required String bookingId,
    required Map<String, String> proof,
    required Map<String, String> cancelScope,
  }) async {
    try {
      final scopedQuery = <String, String>{...cancelScope, ...proof};
      final uri = Uri.parse(
        '$kBookingBaseUrl$kListBookingsPath/${Uri.encodeComponent(bookingId)}',
      ).replace(queryParameters: scopedQuery);
      final res = await http
          .get(uri, headers: _cancelHeaders())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) return false;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return false;
      final body = Map<String, dynamic>.from(decoded);
      final status =
          (body['status'] ??
                  (body['record'] is Map ? body['record']['status'] : null) ??
                  (body['record'] is Map && body['record']['booking'] is Map
                      ? body['record']['booking']['status']
                      : null) ??
                  '')
              .toString()
              .trim()
              .toUpperCase();
      return status == 'CANCELLED' || status == 'CANCELED';
    } catch (_) {
      return false;
    }
  }

  Future<void> _cancelBookingServerSide() async {
    final bookingId = widget.bookingId.trim();
    if (bookingId.isEmpty || _cancelling || !_canCancelBooking) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _t(
            nl: 'Boeking annuleren',
            en: 'Cancel booking',
            fr: 'Annuler la réservation',
            es: 'Cancelar reserva',
          ),
        ),
        content: Text(
          _t(
            nl: 'Deze boeking wordt geannuleerd. De chauffeur en agenda worden bijgewerkt.',
            en: 'This booking will be cancelled. The driver and calendar will be updated.',
            fr: 'Cette réservation sera annulée. Le chauffeur et l’agenda seront mis à jour.',
            es: 'Esta reserva se cancelará. El conductor y el calendario se actualizarán.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              _t(
                nl: 'Niet annuleren',
                en: 'Keep booking',
                fr: 'Garder',
                es: 'Mantener',
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              _t(
                nl: 'Annuleren',
                en: 'Cancel booking',
                fr: 'Annuler',
                es: 'Cancelar',
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() {
      _cancelling = true;
      _refreshError = null;
    });
    final scope = _selectedCancelScopeQuery();
    if (scope == null) {
      if (mounted) {
        setState(() => _cancelling = false);
        await _showCustomerCancellationFailureDialog(reason: 'unknown_failure');
      }
      debugPrint(
        '[CUSTOMER_BOOKING][CANCEL_SCOPE][WARN] reason=missing_strict_scope booking=${_safeRefPreview(bookingId)}',
      );
      return;
    }
    final aliases = _customerBookingDeleteAliases(
      bookingId: bookingId,
      publicBookingReference: _view.publicBookingReference,
      bookingReference: _view.publicBookingReference,
      publicReference: _view.publicBookingReference,
      planningReference: _view.planningReference,
      receiptReference: _view.receiptReference,
      source: _view.source,
    );
    final proof = await _customerOwnershipProof(
      bookingId: bookingId,
      aliases: aliases,
      fallbackEmail: _view.customerEmail,
      fallbackPhone: _view.customerPhone,
      source: _view.source,
    );
    final cancelCandidates = _cancelBookingIdCandidates(bookingId);
    debugPrint(
      '[CUSTOMER_BOOKING][CANCEL_REQ] booking=${_safeRefPreview(bookingId)} candidates=${cancelCandidates.map(_safeRefPreview).join(",")}',
    );
    try {
      String? successfulBookingId;
      String strongestFailureReason = 'unknown_failure';
      for (final candidateId in cancelCandidates) {
        final payload = <String, dynamic>{
          'booking_id': candidateId,
          'status': 'CANCELLED',
          'tenant_id': scope['tenant_id'],
          'company_id': scope['company_id'],
          'tenantId': scope['tenantId'],
          'companyId': scope['companyId'],
          'actor_role': 'customer',
          'actorRole': 'customer',
          if (proof['customer_email'] != null)
            'customer_email': proof['customer_email'],
          if (proof['customer_phone'] != null)
            'customer_phone': proof['customer_phone'],
        };
        final scopedQuery = <String, String>{...scope, ...proof};
        final uri = Uri.parse(
          '$kBookingBaseUrl$kUpdateBookingStatusPath/${Uri.encodeComponent(candidateId)}/status',
        ).replace(queryParameters: scopedQuery);
        final res = await http
            .post(uri, headers: _cancelHeaders(), body: jsonEncode(payload))
            .timeout(const Duration(seconds: 15));
        dynamic decoded;
        try {
          decoded = jsonDecode(utf8.decode(res.bodyBytes));
        } catch (_) {
          decoded = null;
        }
        final decodedMap = decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : const <String, dynamic>{};
        final ok = decodedMap['ok'] == true;
        final reasonCode = (decodedMap['reason'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final errorCode = (decodedMap['error'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final errorMessage = (decodedMap['message'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        debugPrint(
          '[CUSTOMER_BOOKING][CANCEL_RES] candidate=${_safeRefPreview(candidateId)} code=${res.statusCode} ok=$ok error=${(reasonCode.isNotEmpty ? reasonCode : errorCode).isEmpty ? "-" : (reasonCode.isNotEmpty ? reasonCode : errorCode)}',
        );
        if (res.statusCode >= 200 && res.statusCode < 300 && ok) {
          successfulBookingId = candidateId;
          break;
        }
        if (_looksLikeCancellationWindowClosed(
          statusCode: res.statusCode,
          errorCode: errorCode,
          reasonCode: reasonCode,
          message: errorMessage,
        )) {
          await _showCustomerCancellationFailureDialog(
            reason: 'cancellation_window_closed',
          );
          return;
        }
        final normalizedReason = _normalizeCancellationFailureReason(
          reasonCode.isNotEmpty
              ? reasonCode
              : (errorCode.isNotEmpty ? errorCode : 'http_${res.statusCode}'),
        );
        strongestFailureReason = _pickStrongerCancellationFailure(
          strongestFailureReason,
          normalizedReason,
        );
      }
      if (successfulBookingId == null) {
        await _showCustomerCancellationFailureDialog(
          reason: strongestFailureReason,
        );
        return;
      }
      final bookingIdForRemoval = successfulBookingId;

      final aliases = _customerBookingDeleteAliases(
        bookingId: bookingIdForRemoval,
        publicBookingReference: _view.publicBookingReference,
        bookingReference: _view.publicBookingReference,
        publicReference: _view.publicBookingReference,
        planningReference: _view.planningReference,
        receiptReference: _view.receiptReference,
        source: _view.source,
      );
      final localResult = await _removeLocalCustomerBookingEverywhere(
        bookingForLog: bookingIdForRemoval,
        aliases: aliases,
      );
      debugPrint(
        '[CUSTOMER_BOOKING][CANCEL_LOCAL_UPDATE] booking=${_safeRefPreview(bookingIdForRemoval)} removed=${localResult.removed} remaining=${localResult.remaining}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              nl: 'Boeking geannuleerd.',
              en: 'Booking cancelled.',
              fr: 'Réservation annulée.',
              es: 'Reserva cancelada.',
            ),
          ),
        ),
      );
      Navigator.of(
        context,
      ).pop(<String, dynamic>{'action': _customerDetailResultCancelledServer});
    } catch (err) {
      debugPrint(
        '[CUSTOMER_BOOKING][CANCEL_ERROR] booking=${_safeRefPreview(bookingId)} error=$err',
      );
      if (!mounted) return;
      if (_isCancellationTransportError(err)) {
        final cancelled = await _verifyCancellationServerState(
          bookingId: bookingId,
          proof: proof,
          cancelScope: scope,
        );
        if (cancelled) {
          final localResult = await _removeLocalCustomerBookingEverywhere(
            bookingForLog: bookingId,
            aliases: aliases,
          );
          debugPrint(
            '[CUSTOMER_BOOKING][CANCEL_VERIFY_OK] booking=${_safeRefPreview(bookingId)} removed=${localResult.removed}',
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _t(
                  nl: 'Boeking geannuleerd.',
                  en: 'Booking cancelled.',
                  fr: 'Réservation annulée.',
                  es: 'Reserva cancelada.',
                ),
              ),
            ),
          );
          Navigator.of(context).pop(<String, dynamic>{
            'action': _customerDetailResultCancelledServer,
          });
          return;
        }
        await _showCustomerCancellationFailureDialog(reason: 'network_error');
      } else {
        final errorText = err.toString().toLowerCase();
        String reason = 'unknown_failure';
        final codeMatch = RegExp(
          r'code=([a-z0-9_:-]+)',
          caseSensitive: false,
        ).firstMatch(errorText);
        if (codeMatch != null) {
          reason = _normalizeCancellationFailureReason(
            codeMatch.group(1) ?? '',
          );
        }
        await _showCustomerCancellationFailureDialog(reason: reason);
      }
    } finally {
      if (mounted) {
        setState(() => _cancelling = false);
      }
    }
  }

  String _lifecycleLabel(String s) {
    final normalized = _normalizeCustomerLifecycleStatus(s);
    switch (normalized) {
      case 'COMPLETED':
        return _t(
          nl: 'Voltooid',
          en: 'Completed',
          fr: 'Terminee',
          es: 'Finalizada',
        );
      case 'CANCELLED':
        return _t(
          nl: 'Geannuleerd',
          en: 'Cancelled',
          fr: 'Annulee',
          es: 'Cancelada',
        );
      case 'PENDING':
        return _t(
          nl: 'In behandeling',
          en: 'Pending',
          fr: 'En cours',
          es: 'Pendiente',
        );
      case 'CONFIRMED':
        return _t(
          nl: 'Bevestigd',
          en: 'Confirmed',
          fr: 'Confirmee',
          es: 'Confirmada',
        );
      default:
        return normalized.isEmpty ? '-' : normalized;
    }
  }

  String _tokenLabel(String value) {
    final text = value.trim();
    if (text.isEmpty) return '-';
    final normalized = text.replaceAll('_', ' ').replaceAll('-', ' ');
    return normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) => part.length == 1
              ? part.toUpperCase()
              : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _serviceLabel(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return '-';
    if (value == '-' || value == 'null' || value == 'undefined') return '-';
    if (value == 'passenger' || value == 'personenvervoer') {
      return _t(
        nl: 'Personenvervoer',
        en: 'Passenger transport',
        fr: 'Transport de passagers',
        es: 'Transporte de pasajeros',
      );
    }
    if (value == 'business' || value == 'zakelijk') {
      return _t(
        nl: 'Zakelijke rit',
        en: 'Business ride',
        fr: "Course d'affaires",
        es: 'Viaje de negocios',
      );
    }
    if (value == 'airport' || value == 'luchthaven') {
      return _t(
        nl: 'Luchthavenvervoer',
        en: 'Airport transfer',
        fr: 'Transfert aeroport',
        es: 'Traslado al aeropuerto',
      );
    }
    if (value.startsWith('airport') ||
        value.contains('luchthaven') ||
        value == 'airport_transfer' ||
        value == 'airport_transfer_roundtrip' ||
        value == 'luchthavenvervoer') {
      return _t(
        nl: 'Luchthavenvervoer',
        en: 'Airport transfer',
        fr: 'Transfert aeroport',
        es: 'Traslado al aeropuerto',
      );
    }
    return _tokenLabel(raw);
  }

  String _tierLabel(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return '-';
    if (value == 'comfort')
      return _t(nl: 'Comfort', en: 'Comfort', fr: 'Confort', es: 'Confort');
    if (value == 'private')
      return _t(nl: 'Private', en: 'Private', fr: 'Prive', es: 'Privado');
    if (value == 'premium')
      return _t(nl: 'Premium', en: 'Premium', fr: 'Premium', es: 'Premium');
    return _tokenLabel(raw);
  }

  Widget _section({required String title, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
            color: Colors.black.withOpacity(0.26),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14.4,
                color: kFluxidiYellow.withOpacity(0.98),
              ),
            ),
            const SizedBox(height: 9),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kv(
    String label,
    String value, {
    bool stacked = false,
    String? emptyText,
  }) {
    final v = value.trim().isEmpty ? (emptyText ?? '-') : value.trim();
    return LayoutBuilder(
      builder: (context, constraints) {
        final useStacked = stacked || constraints.maxWidth < 380;
        if (useStacked) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.74),
                    fontSize: 12.1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  v,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.8,
                    height: 1.28,
                  ),
                  softWrap: true,
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 128,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.74),
                    fontSize: 12.2,
                    height: 1.25,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  v,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.8,
                    height: 1.28,
                  ),
                  softWrap: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) {
        final v = _view;
        final paymentToken = _classifyCustomerPaymentDisplayToken(
          aliases: _paymentAliasesForView(v),
          fallbackToken: _derivedPaymentDisplayToken.isNotEmpty
              ? _derivedPaymentDisplayToken
              : v.rawPaymentStatus,
        );
        final paid = _isPaidCustomerPaymentDisplayToken(paymentToken);
        final partiallyPaid = _isPartialCustomerPaymentDisplayToken(
          paymentToken,
        );
        final paymentStatusLabel = paid
            ? _t(nl: 'Betaald', en: 'Paid', fr: 'Paye', es: 'Pagado')
            : (partiallyPaid
                  ? _t(
                      nl: 'Deels betaald',
                      en: 'Partially paid',
                      fr: 'Partiellement paye',
                      es: 'Parcialmente pagado',
                    )
                  : _t(
                      nl: 'Te betalen in de wagen',
                      en: 'To pay in the vehicle',
                      fr: 'A payer dans le vehicule',
                      es: 'A pagar en el vehiculo',
                    ));
        final paymentStatusDescription = paid
            ? _t(
                nl: 'Je betaling is bevestigd.',
                en: 'Your payment has been confirmed.',
                fr: 'Votre paiement est confirme.',
                es: 'Tu pago esta confirmado.',
              )
            : (partiallyPaid
                  ? _t(
                      nl: 'Een deel is betaald, resterend bedrag staat nog open.',
                      en: 'Part of this booking is paid, remaining amount is still open.',
                      fr: 'Une partie est payee, le montant restant est encore ouvert.',
                      es: 'Una parte esta pagada, el monto restante sigue abierto.',
                    )
                  : _t(
                      nl: 'Voldoe het bedrag bij de chauffeur.',
                      en: 'Pay the driver during your ride.',
                      fr: 'Reglez le chauffeur pendant la course.',
                      es: 'Paga al conductor durante el viaje.',
                    ));
        final business = v.businessCustomer;
        final isRoundtrip = v.isRoundtrip;
        final showRoundtripPricing =
            isRoundtrip &&
            (v.priceInclVatMain != null ||
                v.priceInclVatReturn != null ||
                v.priceInclVatTotal != null);
        final serviceText = _serviceLabel(v.service);
        final tierText = _tierLabel(v.tier);
        final hasServiceText =
            serviceText.trim().isNotEmpty && serviceText != '-';
        final hasTierText = tierText.trim().isNotEmpty && tierText != '-';
        final invoiceEmail = v.invoiceEmail.trim().isEmpty
            ? _notFilled()
            : v.invoiceEmail.trim();
        final invoiceAddress = v.invoiceAddress.trim().isEmpty
            ? _notFilled()
            : v.invoiceAddress.trim();
        final invoiceFieldsExist =
            v.companyName.isNotEmpty ||
            v.vatNumber.isNotEmpty ||
            v.invoiceEmail.isNotEmpty ||
            v.invoiceAddress.isNotEmpty;
        final showInvoiceSection = business || invoiceFieldsExist;

        return Scaffold(
          backgroundColor: const Color(0xFF0B1020),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0B1020),
            title: Text(
              _t(
                nl: 'Boekingsdetail',
                en: 'Booking detail',
                fr: 'Detail de reservation',
                es: 'Detalle de reserva',
              ),
            ),
            actions: [
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF111214),
                  foregroundColor: _canCancelBooking
                      ? const Color(0xFFFFC1C1)
                      : Colors.white38,
                  side: BorderSide(
                    color: _canCancelBooking
                        ? const Color(0xFFCD5C6C).withOpacity(0.6)
                        : Colors.white24,
                  ),
                ),
                tooltip: _t(
                  nl: 'Boeking annuleren',
                  en: 'Cancel booking',
                  fr: 'Annuler la réservation',
                  es: 'Cancelar reserva',
                ),
                onPressed: (!_canCancelBooking || _cancelling)
                    ? null
                    : _cancelBookingServerSide,
                icon: _cancelling
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cancel_outlined),
              ),
              if (_canLocalRemoveBookingOnly)
                IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF111214),
                    foregroundColor: Colors.white.withOpacity(0.9),
                    side: BorderSide(color: Colors.white.withOpacity(0.22)),
                  ),
                  tooltip: _t(
                    nl: 'Verwijderen uit mijn lijst',
                    en: 'Remove from my list',
                    fr: 'Supprimer de ma liste',
                    es: 'Eliminar de mi lista',
                  ),
                  onPressed: _removeFromMyBookings,
                  icon: const Icon(Icons.delete_outline),
                ),
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
                onPressed: _refreshing ? null : _refresh,
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_outlined),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (_refreshError != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.4)),
                      ),
                      child: Text(
                        _refreshError!,
                        style: const TextStyle(color: Color(0xFFFFB4B4)),
                      ),
                    ),
                  if (_usingLocalCache)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2410),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5B641)),
                      ),
                      child: Text(
                        _t(
                          nl: 'Je ziet lokale gegevens. Vernieuwen voor de laatste status.',
                          en: 'Showing local data. Refresh for the latest status.',
                          fr: 'Donnees locales affichees. Actualisez pour le statut le plus recent.',
                          es: 'Mostrando datos locales. Actualiza para ver el estado mas reciente.',
                        ),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  if (_canCancelBooking) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _cancelling
                            ? null
                            : _cancelBookingServerSide,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFFCDCD),
                          side: BorderSide(
                            color: const Color(0xFFCD5C6C).withOpacity(0.72),
                          ),
                          backgroundColor: const Color(0xFF2A1114),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: _cancelling
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cancel_outlined),
                        label: Text(
                          _t(
                            nl: 'Boeking annuleren',
                            en: 'Cancel booking',
                            fr: 'Annuler la réservation',
                            es: 'Cancelar reserva',
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_canRateCompletedBooking) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_existingCustomerRatingValue() != null) ...[
                            Text(
                              _t(
                                nl: 'Jouw beoordeling: ${_existingCustomerRatingValue()}/5',
                                en: 'Your rating: ${_existingCustomerRatingValue()}/5',
                                fr: 'Votre évaluation : ${_existingCustomerRatingValue()}/5',
                                es: 'Tu valoración: ${_existingCustomerRatingValue()}/5',
                              ),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.84),
                                fontSize: 12.4,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (_existingCustomerRatingComment()
                                .isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                _existingCustomerRatingComment(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.66),
                                  fontSize: 11.8,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _ratingSubmitting
                                  ? null
                                  : _openRatingFlow,
                              style: FilledButton.styleFrom(
                                backgroundColor: kFluxidiYellow,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 11,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: _ratingSubmitting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.star_rounded),
                              label: Text(
                                _t(
                                  nl: 'Beoordeel rit',
                                  en: 'Rate ride',
                                  fr: 'Évaluer la course',
                                  es: 'Valorar viaje',
                                ),
                              ),
                            ),
                          ),
                          if (_ratingSessionChecked &&
                              !_hasValidRatingSession) ...[
                            const SizedBox(height: 8),
                            Text(
                              _t(
                                nl: 'Verifieer je klantprofiel om deze rit te beoordelen.',
                                en: 'Verify your customer profile to rate this ride.',
                                fr: 'Vérifiez votre profil client pour évaluer cette course.',
                                es: 'Verifica tu perfil de cliente para valorar este viaje.',
                              ),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 11.8,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: paid
                            ? const [Color(0xFF103325), Color(0xFF0A1E16)]
                            : (partiallyPaid
                                  ? const [Color(0xFF3A2A12), Color(0xFF1E1409)]
                                  : const [
                                      Color(0xFF2A2410),
                                      Color(0xFF161109),
                                    ]),
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: paid
                            ? const Color(0xFF34D29A)
                            : (partiallyPaid
                                  ? const Color(0xFFFFC857)
                                  : const Color(0xFFE5B641)),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          paid
                              ? Icons.verified_outlined
                              : Icons.payments_outlined,
                          color: paid
                              ? const Color(0xFF34D29A)
                              : (partiallyPaid
                                    ? const Color(0xFFFFC857)
                                    : const Color(0xFFE5B641)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _t(
                                  nl: 'Betaalstatus',
                                  en: 'Payment status',
                                  fr: 'Statut de paiement',
                                  es: 'Estado de pago',
                                ),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.72),
                                  fontSize: 11.1,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                paymentStatusLabel,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                paymentStatusDescription,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isRoundtrip)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2410),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: kFluxidiYellow.withOpacity(0.5),
                        ),
                      ),
                      child: Text(
                        _t(
                          nl: 'Heen-en-terug luchthavenrit',
                          en: 'Roundtrip airport ride',
                          fr: 'Trajet aeroport aller-retour',
                          es: 'Traslado de aeropuerto ida y vuelta',
                        ),
                        style: TextStyle(
                          color: kFluxidiYellow.withOpacity(0.98),
                          fontSize: 11.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  _section(
                    title: _t(
                      nl: 'Boeking',
                      en: 'Booking',
                      fr: 'Reservation',
                      es: 'Reserva',
                    ),
                    children: [
                      (() {
                        final bookingRef = _customerBookingReferenceDisplay(v);
                        return Column(
                          children: [
                            _kv(bookingRef.label, bookingRef.value),
                            if (bookingRef.internalSecondary != null)
                              _kv(
                                _t(
                                  nl: 'Interne boeking',
                                  en: 'Internal booking',
                                  fr: 'Réservation interne',
                                  es: 'Reserva interna',
                                ),
                                bookingRef.internalSecondary!,
                              ),
                          ],
                        );
                      })(),
                      _kv(
                        _t(
                          nl: 'Status',
                          en: 'Status',
                          fr: 'Statut',
                          es: 'Estado',
                        ),
                        _lifecycleLabel(v.lifecycleStatus),
                      ),
                      _kv(
                        _t(
                          nl: 'Betaalstatus',
                          en: 'Payment status',
                          fr: 'Statut de paiement',
                          es: 'Estado de pago',
                        ),
                        paymentStatusLabel,
                      ),
                    ],
                  ),
                  _section(
                    title: _t(
                      nl: 'Route',
                      en: 'Route',
                      fr: 'Itineraire',
                      es: 'Ruta',
                    ),
                    children: [
                      if (!isRoundtrip) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              children: [
                                Icon(
                                  Icons.radio_button_checked,
                                  size: 12,
                                  color: kFluxidiYellow.withOpacity(0.95),
                                ),
                                Container(
                                  width: 2,
                                  height: 34,
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  color: kFluxidiYellow.withOpacity(0.34),
                                ),
                                const Icon(
                                  Icons.location_on,
                                  size: 14,
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
                                    _t(
                                      nl: 'Ophaaladres',
                                      en: 'Pickup',
                                      fr: 'Prise en charge',
                                      es: 'Recogida',
                                    ),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 11.8,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    v.fromAddress.trim().isEmpty
                                        ? _notFilled()
                                        : v.fromAddress.trim(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.8,
                                      height: 1.26,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _t(
                                      nl: 'Bestemming',
                                      en: 'Destination',
                                      fr: 'Destination',
                                      es: 'Destino',
                                    ),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 11.8,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    v.toAddress.trim().isEmpty
                                        ? _notFilled()
                                        : v.toAddress.trim(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.8,
                                      height: 1.26,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _kv(
                          _t(
                            nl: 'Geplande ophaal',
                            en: 'Scheduled pickup',
                            fr: 'Prise en charge prevue',
                            es: 'Recogida programada',
                          ),
                          _formatPickup(v.pickupIso),
                        ),
                      ] else ...[
                        _kv(
                          _t(
                            nl: 'Heenrit van',
                            en: 'Outbound from',
                            fr: 'Aller depuis',
                            es: 'Ida desde',
                          ),
                          v.fromAddress.trim().isEmpty
                              ? _notFilled()
                              : v.fromAddress.trim(),
                          stacked: true,
                        ),
                        _kv(
                          _t(
                            nl: 'Heenrit naar',
                            en: 'Outbound to',
                            fr: 'Aller vers',
                            es: 'Ida hacia',
                          ),
                          v.toAddress.trim().isEmpty
                              ? _notFilled()
                              : v.toAddress.trim(),
                          stacked: true,
                        ),
                        _kv(
                          _t(
                            nl: 'Heenrit datum en tijd',
                            en: 'Outbound date and time',
                            fr: "Date et heure de l'aller",
                            es: 'Fecha y hora de ida',
                          ),
                          _formatPickup(v.pickupIso),
                          stacked: true,
                        ),
                        _kv(
                          _t(
                            nl: 'Terugrit van',
                            en: 'Return from',
                            fr: 'Retour depuis',
                            es: 'Regreso desde',
                          ),
                          v.returnFrom.trim().isEmpty
                              ? _notFilled()
                              : v.returnFrom.trim(),
                          stacked: true,
                        ),
                        _kv(
                          _t(
                            nl: 'Terugrit naar',
                            en: 'Return to',
                            fr: 'Retour vers',
                            es: 'Regreso hacia',
                          ),
                          v.returnTo.trim().isEmpty
                              ? _notFilled()
                              : v.returnTo.trim(),
                          stacked: true,
                        ),
                        _kv(
                          _t(
                            nl: 'Terugrit datum en tijd',
                            en: 'Return date and time',
                            fr: 'Date et heure du retour',
                            es: 'Fecha y hora de regreso',
                          ),
                          _formatPickup(v.returnPickupIso),
                          stacked: true,
                        ),
                      ],
                    ],
                  ),
                  _section(
                    title: _t(
                      nl: 'Klantgegevens',
                      en: 'Customer',
                      fr: 'Client',
                      es: 'Cliente',
                    ),
                    children: [
                      _kv(
                        _t(nl: 'Naam', en: 'Name', fr: 'Nom', es: 'Nombre'),
                        v.customerName,
                      ),
                      _kv(
                        _t(
                          nl: 'Telefoon',
                          en: 'Phone',
                          fr: 'Téléphone',
                          es: 'Teléfono',
                        ),
                        v.customerPhone,
                      ),
                      _kv(
                        _t(
                          nl: 'E-mail',
                          en: 'Email',
                          fr: 'E-mail',
                          es: 'Email',
                        ),
                        v.customerEmail,
                        stacked: true,
                      ),
                    ],
                  ),
                  _section(
                    title: _t(
                      nl: 'Rit details',
                      en: 'Ride details',
                      fr: 'Details de course',
                      es: 'Detalles del viaje',
                    ),
                    children: [
                      if (hasServiceText)
                        _kv(
                          _t(
                            nl: 'Service',
                            en: 'Service',
                            fr: 'Service',
                            es: 'Servicio',
                          ),
                          serviceText,
                        ),
                      if (hasTierText)
                        _kv(
                          _t(
                            nl: 'Tier',
                            en: 'Tier',
                            fr: 'Categorie',
                            es: 'Categoria',
                          ),
                          tierText,
                        ),
                      _kv(
                        _t(
                          nl: 'Passagiers',
                          en: 'Passengers',
                          fr: 'Passagers',
                          es: 'Pasajeros',
                        ),
                        v.pax,
                      ),
                      _kv(
                        _t(
                          nl: 'Bagage',
                          en: 'Bags',
                          fr: 'Bagages',
                          es: 'Equipaje',
                        ),
                        v.bags,
                      ),
                      _kv(
                        _t(
                          nl: 'Extra opties',
                          en: 'Extra options',
                          fr: 'Options supplementaires',
                          es: 'Opciones extra',
                        ),
                        v.extraOptions.isEmpty
                            ? _t(
                                nl: 'Geen extra opties',
                                en: 'No extra options',
                                fr: 'Aucune option supplementaire',
                                es: 'Sin opciones extra',
                              )
                            : _tokenLabel(v.extraOptions),
                      ),
                    ],
                  ),
                  _section(
                    title: _t(
                      nl: 'Prijs',
                      en: 'Price',
                      fr: 'Prix',
                      es: 'Precio',
                    ),
                    children: [
                      if (!showRoundtripPricing) ...[
                        _kv(
                          _t(
                            nl: 'Totaal',
                            en: 'Total',
                            fr: 'Total',
                            es: 'Total',
                          ),
                          _formatPrice(v.totalAmount, v.currency),
                        ),
                      ] else ...[
                        _kv(
                          _t(
                            nl: 'Heenrit prijs incl. btw',
                            en: 'Outbound price incl. VAT',
                            fr: "Prix aller TVAC",
                            es: 'Precio ida con IVA',
                          ),
                          _formatPrice(v.priceInclVatMain, v.currency),
                          stacked: true,
                        ),
                        _kv(
                          _t(
                            nl: 'Terugrit prijs incl. btw',
                            en: 'Return price incl. VAT',
                            fr: 'Prix retour TVAC',
                            es: 'Precio regreso con IVA',
                          ),
                          _formatPrice(v.priceInclVatReturn, v.currency),
                          stacked: true,
                        ),
                        _kv(
                          _t(
                            nl: 'Totaal heen-en-terug incl. btw',
                            en: 'Roundtrip total incl. VAT',
                            fr: 'Total aller-retour TVAC',
                            es: 'Total ida y vuelta con IVA',
                          ),
                          _formatPrice(
                            v.priceInclVatTotal ?? v.totalAmount,
                            v.currency,
                          ),
                          stacked: true,
                        ),
                        if (v.fixedFareAppliedMain && v.fixedFareAppliedReturn)
                          Container(
                            margin: const EdgeInsets.only(top: 2, bottom: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: kFluxidiYellow.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: kFluxidiYellow.withOpacity(0.45),
                              ),
                            ),
                            child: Text(
                              _t(
                                nl: 'Vast tarief per rit volgens bedrijfsregels',
                                en: 'Fixed fare per ride by company rules',
                                fr: "Tarif fixe par trajet selon les regles de l'entreprise",
                                es: 'Tarifa fija por trayecto según reglas de la empresa',
                              ),
                              style: TextStyle(
                                color: kFluxidiYellow.withOpacity(0.98),
                                fontSize: 11.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                  if (showInvoiceSection)
                    _section(
                      title: _t(
                        nl: 'Zakelijk / Factuur',
                        en: 'Business / Invoice',
                        fr: 'Professionnel / Facture',
                        es: 'Empresa / Factura',
                      ),
                      children: [
                        _kv(
                          _t(
                            nl: 'Zakelijke klant',
                            en: 'Business customer',
                            fr: 'Client professionnel',
                            es: 'Cliente empresa',
                          ),
                          business
                              ? _t(nl: 'Ja', en: 'Yes', fr: 'Oui', es: 'Si')
                              : _t(nl: 'Nee', en: 'No', fr: 'Non', es: 'No'),
                        ),
                        _kv(
                          _t(
                            nl: 'Bedrijfsnaam',
                            en: 'Company name',
                            fr: "Nom de l'entreprise",
                            es: 'Empresa',
                          ),
                          v.companyName,
                          stacked: true,
                        ),
                        _kv(
                          _t(
                            nl: 'BTW-nummer',
                            en: 'VAT number',
                            fr: 'Numero de TVA',
                            es: 'NIF/IVA',
                          ),
                          v.vatNumber,
                          stacked: true,
                        ),
                        _kv(
                          _t(
                            nl: 'Factuur e-mail',
                            en: 'Invoice email',
                            fr: 'E-mail facture',
                            es: 'Email de factura',
                          ),
                          invoiceEmail,
                          stacked: true,
                          emptyText: _notFilled(),
                        ),
                        _kv(
                          _t(
                            nl: 'Factuuradres',
                            en: 'Invoice address',
                            fr: 'Adresse de facturation',
                            es: 'Dirección de factura',
                          ),
                          invoiceAddress,
                          stacked: true,
                          emptyText: _notFilled(),
                        ),
                        const SizedBox(height: 8),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _openReceiptAction(
                                context,
                                _ReceiptQuickAction.viewPdf,
                              ),
                              icon: const Icon(Icons.visibility_outlined),
                              label: Text(
                                _t(
                                  nl: 'Bekijk PDF',
                                  en: 'View PDF',
                                  fr: 'Voir PDF',
                                  es: 'Ver PDF',
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _openReceiptAction(
                                context,
                                _ReceiptQuickAction.sharePdf,
                              ),
                              icon: const Icon(Icons.download_outlined),
                              label: Text(
                                _t(
                                  nl: 'Deel PDF',
                                  en: 'Share PDF',
                                  fr: 'Partager PDF',
                                  es: 'Compartir PDF',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
