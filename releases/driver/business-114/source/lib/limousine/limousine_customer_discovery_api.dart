// LIMOUSINE-MARKETPLACE-P2D4C1F — discovery search over GET /partners/nearby.
// Preserves server order. Never calls /book or quote-create.
// Unscoped search is the default recommended listing; region/GPS refine it.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import 'limousine_customer_discovery.dart';
import 'limousine_pricing_local_store.dart';
import 'limousine_pricing_overlay.dart';
import 'limousine_public_showroom.dart';
import 'limousine_service_capability.dart';
import 'limousine_vehicle_public_copy.dart';

abstract class LimousineDiscoveryGateway {
  Future<LimousineDiscoveryPageData> search(LimousineDiscoveryQuery query);

  Future<Map<String, dynamic>?> loadPublicProfile(String publicPartnerId);
}

class MemoryLimousineDiscoveryGateway implements LimousineDiscoveryGateway {
  MemoryLimousineDiscoveryGateway({this.searchHandler, this.profileHandler});

  Future<LimousineDiscoveryPageData> Function(LimousineDiscoveryQuery query)?
  searchHandler;
  Future<Map<String, dynamic>?> Function(String publicPartnerId)?
  profileHandler;

  int searchCalls = 0;
  int profileCalls = 0;
  int bookCalls = 0;
  int createQuoteCalls = 0;
  LimousineDiscoveryQuery? lastQuery;
  final List<String> requestedPaths = <String>[];

  @override
  Future<LimousineDiscoveryPageData> search(
    LimousineDiscoveryQuery query,
  ) async {
    searchCalls += 1;
    lastQuery = query;
    requestedPaths.add(kLimousineDiscoveryNearbyPath);
    final handler = searchHandler;
    if (handler != null) return handler(query);
    return const LimousineDiscoveryPageData();
  }

  @override
  Future<Map<String, dynamic>?> loadPublicProfile(
    String publicPartnerId,
  ) async {
    profileCalls += 1;
    requestedPaths.add(kLimousineDiscoveryProfilePath);
    final handler = profileHandler;
    if (handler != null) return handler(publicPartnerId);
    return null;
  }
}

class HttpLimousineDiscoveryGateway implements LimousineDiscoveryGateway {
  HttpLimousineDiscoveryGateway({http.Client? client, String? bookingBaseUrl})
    : _client = client,
      _bookingBaseUrl = bookingBaseUrl;

  final http.Client? _client;
  final String? _bookingBaseUrl;

  String get _base => (_bookingBaseUrl ?? appConfig.bookingBaseUrl).trim();

  Future<http.Response> _get(Uri uri) {
    final client = _client;
    final headers = const <String, String>{'Accept': 'application/json'};
    if (client != null) {
      return client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));
    }
    return http.get(uri, headers: headers).timeout(const Duration(seconds: 12));
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

  @override
  Future<LimousineDiscoveryPageData> search(
    LimousineDiscoveryQuery query,
  ) async {
    final parameters = <String, String>{'service': 'limousine'};
    final postcode = (query.postcode ?? '').trim();
    if (postcode.isNotEmpty) {
      parameters['postcode'] = postcode;
    } else if (query.lat != null && query.lng != null) {
      parameters['lat'] = query.lat!.toStringAsFixed(6);
      parameters['lng'] = query.lng!.toStringAsFixed(6);
    }
    final uri = Uri.parse(
      '$_base$kLimousineDiscoveryNearbyPath',
    ).replace(queryParameters: parameters);
    try {
      final res = await _get(uri);
      final body = _decode(res);
      if (limousineDiscoveryResponseIsGatesOff(res.statusCode, body)) {
        return const LimousineDiscoveryPageData(gatesOff: true);
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return const LimousineDiscoveryPageData(networkError: true);
      }
      final raw = body['partners'];
      final cards = raw is List
          ? limousineDiscoveryCardsFromNearbyPartners(raw)
          : const <LimousineDiscoveryCard>[];
      return LimousineDiscoveryPageData(
        cards: cards,
        listingMode: (body['limousine_listing_mode'] ?? '').toString(),
      );
    } catch (_) {
      return const LimousineDiscoveryPageData(networkError: true);
    }
  }

  @override
  Future<Map<String, dynamic>?> loadPublicProfile(
    String publicPartnerId,
  ) async {
    final id = publicPartnerId.trim();
    if (id.isEmpty) return null;
    final uri = Uri.parse(
      '$_base$kLimousineDiscoveryProfilePath',
    ).replace(queryParameters: <String, String>{'partner_id': id});
    try {
      final res = await _get(uri);
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final body = _decode(res);
      if (body['profile'] is Map) {
        return Map<String, dynamic>.from(body['profile'] as Map);
      }
      return body;
    } catch (_) {
      return null;
    }
  }
}

enum LimousineDiscoveryPhase {
  idle,
  loading,
  ready,
  empty,
  gatesOff,
  needPlace,
  network,
}

class LimousineDiscoveryController extends ChangeNotifier {
  LimousineDiscoveryController({required LimousineDiscoveryGateway gateway})
    : _gateway = gateway;

  final LimousineDiscoveryGateway _gateway;

  LimousineDiscoveryPhase phase = LimousineDiscoveryPhase.idle;
  List<LimousineDiscoveryCard> cards = const <LimousineDiscoveryCard>[];
  String profileUnavailablePartnerId = '';
  bool openingProfile = false;
  int suppressedSearchTaps = 0;
  int searchStarts = 0;
  LimousineDiscoveryQuery? lastQuery;
  String listingMode = '';

  bool get showsTestEnvironment =>
      listingMode.trim().toLowerCase() == 'test_preview' ||
      cards.any((card) => card.testPreview);

  bool get isSearching => phase == LimousineDiscoveryPhase.loading;

  MemoryLimousineDiscoveryGateway? get _memoryGateway {
    final gateway = _gateway;
    return gateway is MemoryLimousineDiscoveryGateway ? gateway : null;
  }

  bool get calledBook => (_memoryGateway?.bookCalls ?? 0) > 0;

  bool get createdQuote => (_memoryGateway?.createQuoteCalls ?? 0) > 0;

  List<String> get requestedPaths =>
      List<String>.from(_memoryGateway?.requestedPaths ?? const <String>[]);

  Future<void> search(LimousineDiscoveryQuery? query) async {
    if (isSearching || openingProfile) {
      suppressedSearchTaps += 1;
      return;
    }
    final resolved = query ?? const LimousineDiscoveryQuery();
    searchStarts += 1;
    lastQuery = resolved;
    listingMode = '';
    phase = LimousineDiscoveryPhase.loading;
    profileUnavailablePartnerId = '';
    notifyListeners();
    try {
      final result = await _gateway
          .search(resolved)
          .timeout(const Duration(seconds: 12));
      listingMode = result.listingMode;
      if (result.networkError) {
        phase = LimousineDiscoveryPhase.network;
      } else if (result.gatesOff) {
        phase = LimousineDiscoveryPhase.gatesOff;
        cards = const <LimousineDiscoveryCard>[];
      } else if (result.cards.isEmpty) {
        phase = LimousineDiscoveryPhase.empty;
        cards = const <LimousineDiscoveryCard>[];
      } else {
        phase = LimousineDiscoveryPhase.ready;
        cards = resolved.isUnscoped
            ? result.cards
                  .map((card) => card.copyWith(clearDistance: true))
                  .toList(growable: false)
            : List<LimousineDiscoveryCard>.from(result.cards);
      }
    } on TimeoutException {
      phase = LimousineDiscoveryPhase.network;
      cards = const <LimousineDiscoveryCard>[];
    }
    notifyListeners();
  }

  Future<void> searchAnotherRegion() {
    return search(const LimousineDiscoveryQuery());
  }

  Future<Map<String, dynamic>?> openConfirmedPublicProfile(
    LimousineDiscoveryCard card,
  ) async {
    if (openingProfile || isSearching) {
      suppressedSearchTaps += 1;
      return null;
    }
    openingProfile = true;
    profileUnavailablePartnerId = '';
    notifyListeners();
    try {
      final profile = await _gateway
          .loadPublicProfile(card.publicPartnerId)
          .timeout(const Duration(seconds: 12));
      final map = profile == null ? null : asStringKeyedMap(profile);
      if (map == null || !limousinePublicProfileMarksAvailable(map)) {
        profileUnavailablePartnerId = card.publicPartnerId;
        return null;
      }
      await limousinePricingLocalStore.warm();
      final hydrated = limousineHydratePublishedPartnerOverlay(map);
      return limousineAttachPublishedVehiclePublicCopy(
        hydrated,
        limousinePricingLocalStore.publishedCopyForProfile(hydrated),
      );
    } on TimeoutException {
      profileUnavailablePartnerId = card.publicPartnerId;
      return null;
    } finally {
      openingProfile = false;
      notifyListeners();
    }
  }
}
