// LIMOUSINE-MARKETPLACE-P2D2 — customer quote HTTP client and controller.
// Never logs limqs1, limacc1, fingerprints, Authorization or raw bodies.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../customer_session_store.dart';
import 'limousine_accepted_booking.dart';
import 'limousine_accepted_booking_resume.dart';
import 'limousine_accepted_booking_vault.dart';
import 'limousine_customer_quote.dart';
import 'limousine_quote_inbox.dart';

typedef LimousineCustomerAuthHeaders = Future<Map<String, String>> Function();

Future<String?> _defaultLimousineResumeCustomerId() async {
  try {
    final session = await CustomerSessionStore.instance.loadValidSession();
    final customerId = (session?.customerId ?? '').trim();
    return customerId.isEmpty ? null : customerId;
  } catch (_) {
    return null;
  }
}

abstract class LimousineCustomerQuoteGateway {
  Future<List<LimousineDiscoveredProvider>> discoverNearby({
    String? postcode,
    double? lat,
    double? lng,
    int radiusKm = 20,
  });

  Future<LimousineProviderDetail> loadProvider(String partnerId);

  Future<LimousineQuoteCreateResult> createRequest(
    LimousineQuoteCreateDraft draft,
  );

  Future<LimousineQuoteRequest> pollStatus(String statusRef);

  Future<LimousineQuoteAcceptResult> accept({
    required String quoteRequestId,
    required int expectedRevision,
    required int termsRevision,
  });
}

class LimousineCustomerQuoteException implements Exception {
  const LimousineCustomerQuoteException({
    required this.code,
    this.statusCode = 0,
    this.stale = false,
    this.rateLimited = false,
    this.unavailable = false,
    this.retryAfter,
  });

  final String code;
  final int statusCode;
  final bool stale;
  final bool rateLimited;
  final bool unavailable;
  final Duration? retryAfter;
}

Future<Map<String, String>> defaultLimousineCustomerAuthHeaders() async {
  final headers = <String, String>{
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
  try {
    final session = await CustomerSessionStore.instance.loadValidSession();
    final token = (session?.customerSessionToken ?? '').trim();
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
  } catch (_) {}
  return headers;
}

class HttpLimousineCustomerQuoteGateway
    implements LimousineCustomerQuoteGateway {
  HttpLimousineCustomerQuoteGateway({
    http.Client? client,
    LimousineCustomerAuthHeaders? authHeaders,
    String? bookingBaseUrl,
  }) : _client = client,
       _authHeaders = authHeaders ?? defaultLimousineCustomerAuthHeaders,
       _bookingBaseUrl = bookingBaseUrl;

  final http.Client? _client;
  final LimousineCustomerAuthHeaders _authHeaders;
  final String? _bookingBaseUrl;

  String get _base => (_bookingBaseUrl ?? appConfig.bookingBaseUrl).trim();

  Future<http.Response> _get(Uri uri, Map<String, String> headers) {
    final client = _client;
    if (client != null) {
      return client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));
    }
    return http.get(uri, headers: headers).timeout(const Duration(seconds: 12));
  }

  Future<http.Response> _post(
    Uri uri,
    Map<String, String> headers,
    String body,
  ) {
    final client = _client;
    if (client != null) {
      return client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 15));
    }
    return http
        .post(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 15));
  }

  Map<String, dynamic> _decode(http.Response res) {
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return const <String, dynamic>{};
  }

  Never _throwFailed(int status, Map<String, dynamic> map) {
    final error = (map['error'] ?? '').toString();
    final retryRaw = map['retry_after'] ?? map['retryAfter'];
    final retrySeconds = retryRaw is num
        ? retryRaw.toInt()
        : int.tryParse('$retryRaw');
    throw LimousineCustomerQuoteException(
      code: error.isEmpty ? 'unavailable' : error,
      statusCode: status,
      stale: error == 'stale_revision' || status == 409,
      rateLimited: error == 'rate_limited' || status == 429,
      unavailable: status == 404 || error == 'invalid_status_ref',
      retryAfter: retrySeconds != null && retrySeconds > 0
          ? Duration(seconds: retrySeconds)
          : null,
    );
  }

  @override
  Future<List<LimousineDiscoveredProvider>> discoverNearby({
    String? postcode,
    double? lat,
    double? lng,
    int radiusKm = 20,
  }) async {
    final query = <String, String>{'service': 'limousine'};
    final code = (postcode ?? '').trim();
    if (code.isNotEmpty) {
      query['postcode'] = code;
    } else if (lat != null && lng != null) {
      query['lat'] = lat.toStringAsFixed(6);
      query['lng'] = lng.toStringAsFixed(6);
      query['radius_km'] = '$radiusKm';
    } else {
      return const <LimousineDiscoveredProvider>[];
    }
    final uri = Uri.parse(
      '$_base/partners/nearby',
    ).replace(queryParameters: query);
    try {
      final res = await _get(uri, const <String, String>{
        'Accept': 'application/json',
      });
      final map = _decode(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _throwFailed(res.statusCode, map);
      }
      final raw = map['partners'];
      final out = <LimousineDiscoveredProvider>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final provider = LimousineDiscoveredProvider.fromJson(item);
          if (provider.limousineAvailable && provider.partnerId.isNotEmpty) {
            out.add(provider);
          }
        }
      }
      return out;
    } on LimousineCustomerQuoteException {
      rethrow;
    } catch (_) {
      throw const LimousineCustomerQuoteException(code: 'network');
    }
  }

  @override
  Future<LimousineProviderDetail> loadProvider(String partnerId) async {
    final id = partnerId.trim();
    if (id.isEmpty) {
      throw const LimousineCustomerQuoteException(code: 'unknown_partner');
    }
    final uri = Uri.parse(
      '$_base/partners/profile',
    ).replace(queryParameters: <String, String>{'partner_id': id});
    try {
      final res = await _get(uri, const <String, String>{
        'Accept': 'application/json',
      });
      final map = _decode(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _throwFailed(res.statusCode, map);
      }
      final profile = map['profile'] is Map
          ? Map<String, dynamic>.from(map['profile'] as Map)
          : map;
      final provider = LimousineDiscoveredProvider.fromJson(<String, dynamic>{
        ...profile,
        'partner_id': profile['partner_id'] ?? id,
        'limousine_available':
            profile['limousine_available'] == true ||
            profile['limousine_service_enabled'] == true ||
            (profile['limousine_projection'] is Map &&
                (profile['limousine_projection']
                        as Map)['limousine_available'] ==
                    true),
      });
      final offersRaw =
          profile['limousine_offers'] ?? profile['limousineOffers'];
      final offers = <LimousinePublishedOffer>[];
      if (offersRaw is List) {
        for (final item in offersRaw) {
          if (item is! Map) continue;
          final offer = LimousinePublishedOffer.fromJson(item);
          if (offer.offerId.isNotEmpty) offers.add(offer);
        }
      }
      return LimousineProviderDetail(
        provider: provider,
        offers: sortLimousineOffersVehicleFirst(offers),
      );
    } on LimousineCustomerQuoteException {
      rethrow;
    } catch (_) {
      throw const LimousineCustomerQuoteException(code: 'network');
    }
  }

  @override
  Future<LimousineQuoteCreateResult> createRequest(
    LimousineQuoteCreateDraft draft,
  ) async {
    final body = limousineCustomerCreateBody(draft);
    if (!limousineCustomerCreateBodyIsBounded(body)) {
      throw const LimousineCustomerQuoteException(code: 'invalid_request');
    }
    final uri = Uri.parse('$_base/limousine/quote-requests');
    try {
      final headers = await _authHeaders();
      final res = await _post(uri, headers, jsonEncode(body));
      final map = _decode(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _throwFailed(res.statusCode, map);
      }
      final request = LimousineQuoteRequest.fromJson(map['quote_request']);
      return LimousineQuoteCreateResult(
        request: request,
        statusRef: (map['status_ref'] ?? map['statusRef'] ?? '').toString(),
        statusExpiresAt:
            (map['status_expires_at'] ?? map['statusExpiresAt'] ?? '')
                .toString(),
        idempotent: map['idempotent'] == true,
      );
    } on LimousineCustomerQuoteException {
      rethrow;
    } catch (_) {
      throw const LimousineCustomerQuoteException(code: 'network');
    }
  }

  @override
  Future<LimousineQuoteRequest> pollStatus(String statusRef) async {
    if (!looksLikeLimousineStatusRef(statusRef)) {
      throw const LimousineCustomerQuoteException(
        code: 'unavailable',
        unavailable: true,
        statusCode: 404,
      );
    }
    final uri = Uri.parse('$_base/limousine/quote-requests/status');
    try {
      final headers = await _authHeaders();
      final res = await _post(
        uri,
        headers,
        jsonEncode(<String, dynamic>{'status_ref': statusRef}),
      );
      final map = _decode(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _throwFailed(res.statusCode, map);
      }
      return LimousineQuoteRequest.fromJson(map['quote_request']);
    } on LimousineCustomerQuoteException {
      rethrow;
    } catch (_) {
      throw const LimousineCustomerQuoteException(code: 'network');
    }
  }

  @override
  Future<LimousineQuoteAcceptResult> accept({
    required String quoteRequestId,
    required int expectedRevision,
    required int termsRevision,
  }) async {
    final uri = Uri.parse('$_base/limousine/quote-requests/accept');
    try {
      final headers = await _authHeaders();
      final res = await _post(
        uri,
        headers,
        jsonEncode(
          limousineCustomerAcceptBody(
            quoteRequestId: quoteRequestId,
            expectedRevision: expectedRevision,
            termsRevision: termsRevision,
          ),
        ),
      );
      final map = _decode(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _throwFailed(res.statusCode, map);
      }
      return LimousineQuoteAcceptResult(
        request: LimousineQuoteRequest.fromJson(map['quote_request']),
        acceptanceReference: (map['acceptance_reference'] ?? '').toString(),
        expiresAt: (map['expires_at'] ?? '').toString(),
      );
    } on LimousineCustomerQuoteException {
      rethrow;
    } catch (_) {
      throw const LimousineCustomerQuoteException(code: 'network');
    }
  }
}

typedef LimousineAcceptedResumeCustomerIdLoader = Future<String?> Function();

class LimousineCustomerQuoteController extends ChangeNotifier {
  LimousineCustomerQuoteController({
    required LimousineCustomerQuoteGateway gateway,
    LimousineStatusReferenceStore? statusStore,
    LimousineAcceptedBookingResumeRepository? resumeRepository,
    LimousineAcceptedResumeCustomerIdLoader? customerIdLoader,
    String accountScope = 'customer',
    DateTime Function()? clock,
  }) : _gateway = gateway,
       _statusStore = statusStore ?? LimousineInMemoryStatusReferenceStore(),
       _resumeRepository = resumeRepository,
       _customerIdLoader =
           customerIdLoader ?? _defaultLimousineResumeCustomerId,
       _accountScope = accountScope,
       _clock = clock ?? DateTime.now {
    CustomerSessionStore.instance.addClearedListener(_onSessionCleared);
  }

  final LimousineCustomerQuoteGateway _gateway;
  final LimousineStatusReferenceStore _statusStore;
  final LimousineAcceptedBookingResumeRepository? _resumeRepository;
  final LimousineAcceptedResumeCustomerIdLoader _customerIdLoader;
  final String _accountScope;
  final DateTime Function() _clock;

  LimousineCustomerQuoteStep step = LimousineCustomerQuoteStep.journey;
  LimousineCustomerQuotePhase phase = LimousineCustomerQuotePhase.draft;
  LimousineQuoteCreateDraft draft = const LimousineQuoteCreateDraft();
  List<LimousineDiscoveredProvider> providers = const [];
  LimousineProviderDetail? selectedProvider;
  LimousinePublishedOffer? selectedOffer;
  LimousineQuoteRequest? request;
  LimousineAcceptedQuoteHandoff? handoff;
  LimousineAcceptedBookingReview? secureResumeReview;
  bool restoredFromSecureResume = false;
  List<LimousineCustomerDraftError> draftErrors = const [];
  String safeError = '';
  bool quoteUpdated = false;
  bool termsAcknowledged = false;
  bool discovering = false;
  bool loadingProvider = false;
  bool providerOfferLocked = false;
  int lastDiscoveryCount = 0;
  String lastDiscoveryService = '';

  String? _statusRef;
  String? _acceptanceRef;
  int _createGeneration = 0;
  int _statusGeneration = 0;
  int _acceptGeneration = 0;
  DateTime? _lastManualRefreshAt;
  DateTime? _retryAfterUntil;
  Timer? _pollTimer;
  bool _pollingEnabled = false;
  final List<DateTime> _statusAttempts = <DateTime>[];
  final List<String> _logSink = <String>[];

  String? get statusRefForTests => _statusRef;
  String? get acceptanceRefForTests => _acceptanceRef;
  List<String> get logSinkForTests => List<String>.unmodifiable(_logSink);
  LimousineStatusReferenceStore get statusStore => _statusStore;
  bool get submitting => phase == LimousineCustomerQuotePhase.submitting;
  bool get accepting => phase == LimousineCustomerQuotePhase.accepting;
  bool get persistStatusAcrossRestarts => _statusStore.persistsAcrossRestarts;

  void _safeLog(String message) {
    if (limousineTextLooksLikeSecret(message)) return;
    _logSink.add(message);
  }

  @visibleForTesting
  void handleSessionClearedForTests() => _onSessionCleared();

  void _onSessionCleared() {
    unawaited(_statusStore.clearAll());
    _forgetAcceptedHandoff();
    notifyListeners();
  }

  void _forgetAcceptedHandoff() {
    _acceptanceRef = null;
    handoff = null;
    secureResumeReview = null;
    restoredFromSecureResume = false;
    unawaited(_resumeRepository?.discard());
  }

  void clearAcceptedHandoff() {
    _forgetAcceptedHandoff();
    notifyListeners();
  }

  void applySecureResumeEnvelope(
    LimousineAcceptedBookingResumeEnvelope envelope,
  ) {
    handoff = envelope.handoff;
    draft = envelope.draft;
    secureResumeReview = envelope.review;
    restoredFromSecureResume = true;
    _acceptanceRef = envelope.handoff.acceptanceReference;
    step = LimousineCustomerQuoteStep.acceptOffer;
    notifyListeners();
  }

  Future<LimousineAcceptedBookingResumeEnvelope?> restoreAcceptedResume({
    required LimousineAcceptedBookingResumeScope scope,
  }) async {
    final repo = _resumeRepository;
    if (repo == null) return null;
    final envelope = await repo.restore(scope: scope);
    if (envelope == null) {
      if (restoredFromSecureResume) {
        _acceptanceRef = null;
        handoff = null;
        secureResumeReview = null;
        restoredFromSecureResume = false;
        notifyListeners();
      }
      return null;
    }
    applySecureResumeEnvelope(envelope);
    return envelope;
  }

  Future<LimousineAcceptedBookingResumeEnvelope?> detectSecureResume() async {
    if (_resumeRepository == null) return null;
    final customerId = ((await _customerIdLoader()) ?? '').trim();
    if (customerId.isEmpty) return null;
    return restoreAcceptedResume(
      scope: LimousineAcceptedBookingResumeScope(customerId: customerId),
    );
  }

  Future<void> discardSecureResume() async {
    _forgetAcceptedHandoff();
    notifyListeners();
  }

  @override
  void dispose() {
    stopPolling();
    CustomerSessionStore.instance.removeClearedListener(_onSessionCleared);
    super.dispose();
  }

  void updateDraft(LimousineQuoteCreateDraft next) {
    draft = next;
    draftErrors = const [];
    notifyListeners();
  }

  void goTo(LimousineCustomerQuoteStep next) {
    step = next;
    notifyListeners();
  }

  bool validateCurrentDraft() {
    draftErrors = validateLimousineCustomerDraft(draft, offer: selectedOffer);
    notifyListeners();
    return draftErrors.isEmpty;
  }

  Future<void> discover({String? postcode, double? lat, double? lng}) async {
    discovering = true;
    lastDiscoveryService = 'limousine';
    safeError = '';
    notifyListeners();
    try {
      final found = await _gateway.discoverNearby(
        postcode: postcode,
        lat: lat,
        lng: lng,
      );
      providers = filterWorkerEligibleLimousineProviders(found);
      lastDiscoveryCount = providers.length;
    } on LimousineCustomerQuoteException {
      providers = const [];
      lastDiscoveryCount = 0;
      safeError = 'network';
    } finally {
      discovering = false;
      notifyListeners();
    }
  }

  void applyShowroomSelection({
    required String publicPartnerId,
    required LimousinePublishedOffer offer,
    String companyName = '',
  }) {
    final partnerId = publicPartnerId.trim();
    if (partnerId.isEmpty || offer.offerId.trim().isEmpty) return;
    selectedProvider = LimousineProviderDetail(
      provider: LimousineDiscoveredProvider(
        partnerId: partnerId,
        companyName: companyName.trim(),
        limousineAvailable: true,
      ),
      offers: <LimousinePublishedOffer>[offer],
    );
    selectedOffer = offer;
    providerOfferLocked = true;
    draft = draft.copyWith(publicPartnerId: partnerId, offerId: offer.offerId);
    notifyListeners();
  }

  Future<void> selectProvider(LimousineDiscoveredProvider provider) async {
    if (providerOfferLocked) return;
    loadingProvider = true;
    notifyListeners();
    try {
      final detail = await _gateway.loadProvider(provider.partnerId);
      selectedProvider = detail;
      final ranked = sortLimousineOffersVehicleFirst(detail.offers);
      selectedOffer = ranked.isEmpty ? null : ranked.first;
      draft = draft.copyWith(
        publicPartnerId: detail.provider.partnerId,
        offerId: selectedOffer?.offerId ?? '',
      );
    } on LimousineCustomerQuoteException {
      safeError = 'network';
    } finally {
      loadingProvider = false;
      notifyListeners();
    }
  }

  void selectOffer(LimousinePublishedOffer offer) {
    if (providerOfferLocked) return;
    selectedOffer = offer;
    draft = draft.copyWith(offerId: offer.offerId);
    notifyListeners();
  }

  Future<bool> submitRequest() async {
    if (submitting) return false;
    if (!validateCurrentDraft()) return false;
    final body = limousineCustomerCreateBody(draft);
    if (!limousineCustomerCreateBodyIsBounded(body)) return false;
    phase = LimousineCustomerQuotePhase.submitting;
    notifyListeners();
    final generation = ++_createGeneration;
    try {
      final result = await _gateway.createRequest(draft);
      if (generation != _createGeneration) return false;
      request = result.request;
      quoteUpdated = false;
      termsAcknowledged = false;
      if (looksLikeLimousineStatusRef(result.statusRef)) {
        _statusRef = result.statusRef;
        await _statusStore.retain(
          accountScope: _accountScope,
          requestKey: result.request.quoteRequestId,
          statusRef: result.statusRef,
        );
      }
      phase = LimousineCustomerQuotePhase.live;
      step = LimousineQuoteStateId.waitingForCustomer.contains(request!.state)
          ? LimousineCustomerQuoteStep.reviewQuote
          : LimousineCustomerQuoteStep.waitingCompany;
      if (limousineCustomerShouldPoll(request!.state)) {
        startPolling();
      }
      _safeLog('quote_request_created');
      notifyListeners();
      return true;
    } on LimousineCustomerQuoteException catch (error) {
      if (generation != _createGeneration) return false;
      phase = LimousineCustomerQuotePhase.draft;
      safeError = error.unavailable ? 'unavailable' : 'network';
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshStatus({bool manual = false}) async {
    final ref = _statusRef;
    if (!looksLikeLimousineStatusRef(ref)) {
      if (request != null) {
        phase = LimousineCustomerQuotePhase.unavailable;
        notifyListeners();
      }
      return;
    }
    if (manual) {
      final last = _lastManualRefreshAt;
      if (last != null &&
          _clock().difference(last) < kLimousineStatusManualDebounce) {
        return;
      }
      _lastManualRefreshAt = _clock();
    }
    final retryUntil = _retryAfterUntil;
    if (retryUntil != null && _clock().isBefore(retryUntil)) {
      return;
    }
    if (!_canAttemptStatusNow()) return;
    final generation = ++_statusGeneration;
    final previousRevision = request?.revision ?? 0;
    try {
      final next = await _gateway.pollStatus(ref!);
      if (generation != _statusGeneration) return;
      if (request != null && next.revision < request!.revision) return;
      if (request != null &&
          next.revision > previousRevision &&
          previousRevision > 0) {
        quoteUpdated = true;
        termsAcknowledged = false;
        _forgetAcceptedHandoff();
      }
      request = request == null ? next : request!.mergeAuthoritative(next);
      if (LimousineQuoteStateId.isTerminal(request!.state) ||
          request!.isUnknownState) {
        stopPolling();
      }
      if (LimousineQuoteStateId.waitingForCustomer.contains(request!.state)) {
        step = LimousineCustomerQuoteStep.reviewQuote;
      }
      notifyListeners();
    } on LimousineCustomerQuoteException catch (error) {
      if (generation != _statusGeneration) return;
      if (error.rateLimited) {
        if (error.retryAfter != null) {
          _retryAfterUntil = _clock().add(error.retryAfter!);
        }
        _safeLog('status_rate_limited');
        return;
      }
      if (error.unavailable) {
        phase = LimousineCustomerQuotePhase.unavailable;
        stopPolling();
        notifyListeners();
      }
    }
  }

  bool _canAttemptStatusNow() {
    final now = _clock();
    _statusAttempts.removeWhere(
      (stamp) => now.difference(stamp) > kLimousineStatusRateWindow,
    );
    if (_statusAttempts.length >= kLimousineStatusRateMax) return false;
    _statusAttempts.add(now);
    return true;
  }

  void startPolling() {
    _pollingEnabled = true;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(kLimousineStatusAutoPollInterval, (_) {
      if (!_pollingEnabled) return;
      final state = request?.state ?? '';
      if (!limousineCustomerShouldPoll(state)) {
        stopPolling();
        return;
      }
      unawaited(refreshStatus());
    });
  }

  void pausePolling() {
    _pollingEnabled = false;
  }

  void resumePolling() {
    if (request == null) return;
    if (!limousineCustomerShouldPoll(request!.state)) return;
    _pollingEnabled = true;
  }

  void stopPolling() {
    _pollingEnabled = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void setTermsAcknowledged(bool value) {
    termsAcknowledged = value;
    notifyListeners();
  }

  Future<bool> acceptCurrentQuote() async {
    final live = request;
    if (live == null || accepting) return false;
    if (!termsAcknowledged) return false;
    if (!limousineCustomerCanAccept(live, now: _clock().toUtc())) return false;
    phase = LimousineCustomerQuotePhase.accepting;
    notifyListeners();
    final generation = ++_acceptGeneration;
    try {
      final result = await _gateway.accept(
        quoteRequestId: live.quoteRequestId,
        expectedRevision: live.revision,
        termsRevision: live.quote?.termsRevision ?? 0,
      );
      if (generation != _acceptGeneration) return false;
      request = result.request;
      if (looksLikeLimousineAcceptanceRef(result.acceptanceReference)) {
        _acceptanceRef = result.acceptanceReference;
        handoff = LimousineAcceptedQuoteHandoff(
          acceptanceReference: result.acceptanceReference,
          quoteRequestId: result.request.quoteRequestId,
          quoteRevision: result.request.revision,
          termsRevision: result.request.quote?.termsRevision ?? 0,
          totalInclVatCents: result.request.quote?.totalInclVatCents ?? 0,
          currency: result.request.quote?.currency ?? '',
          offerId: result.request.offerId,
          publicPartnerId: draft.publicPartnerId,
          from: draft.from,
          to: draft.to,
          scheduledPickupIso: result.request.scheduledPickupIso,
        );
        restoredFromSecureResume = false;
        secureResumeReview = buildLimousineAcceptedBookingReview(
          handoff: handoff!,
          draft: draft,
          request: result.request,
          offer: selectedOffer,
          providerName: selectedProvider?.provider.companyName ?? '',
        );
        await _persistAcceptedResume(result);
      }
      phase = LimousineCustomerQuotePhase.live;
      step = LimousineCustomerQuoteStep.acceptOffer;
      stopPolling();
      _safeLog('quote_accepted');
      notifyListeners();
      return true;
    } on LimousineCustomerQuoteException catch (error) {
      if (generation != _acceptGeneration) return false;
      _forgetAcceptedHandoff();
      phase = LimousineCustomerQuotePhase.live;
      if (error.stale) {
        quoteUpdated = true;
        termsAcknowledged = false;
        await refreshStatus(manual: true);
      } else if (error.unavailable) {
        phase = LimousineCustomerQuotePhase.unavailable;
      } else {
        safeError = 'network';
      }
      notifyListeners();
      return false;
    }
  }

  Future<void> _persistAcceptedResume(LimousineQuoteAcceptResult result) async {
    final repo = _resumeRepository;
    final live = handoff;
    final snapshot = secureResumeReview;
    if (repo == null || live == null || snapshot == null) return;
    final expiresAt = DateTime.tryParse(result.expiresAt.trim());
    if (expiresAt == null) return;
    final customerId = ((await _customerIdLoader()) ?? '').trim();
    if (customerId.isEmpty) return;
    await repo.persistAccepted(
      handoff: live,
      draft: draft,
      review: snapshot,
      customerId: customerId,
      expiresAt: expiresAt.toUtc(),
      providerName: selectedProvider?.provider.companyName ?? '',
    );
  }
}
