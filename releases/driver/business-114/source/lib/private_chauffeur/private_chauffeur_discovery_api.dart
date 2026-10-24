// GET /partners/nearby for Privéchauffeur.
//
// The worker currently maps only service=limousine. Any other service value,
// including private_chauffeur, becomes "no filter" and an unscoped call is
// rejected. This client therefore:
// - refuses an unscoped search instead of listing every taxi company;
// - sends service=private_chauffeur so a future worker filter can take over;
// - drops every partner that does not explicitly offer the service.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../limousine/limousine_customer_discovery.dart';
import '../limousine/limousine_service_capability.dart';
import 'private_chauffeur_capability.dart';
import 'private_chauffeur_discovery.dart';

const String kPrivateChauffeurNearbyPath = '/partners/nearby';
const String kPrivateChauffeurProfilePath = '/partners/profile';

abstract class PrivateChauffeurDiscoveryGateway {
  Future<PrivateChauffeurDiscoveryPageData> search(
    LimousineDiscoveryQuery query,
  );

  Future<Map<String, dynamic>?> loadPublicProfile(String publicPartnerId);
}

class MemoryPrivateChauffeurDiscoveryGateway
    implements PrivateChauffeurDiscoveryGateway {
  MemoryPrivateChauffeurDiscoveryGateway({
    this.searchHandler,
    this.profileHandler,
  });

  Future<PrivateChauffeurDiscoveryPageData> Function(
    LimousineDiscoveryQuery query,
  )?
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
  Future<PrivateChauffeurDiscoveryPageData> search(
    LimousineDiscoveryQuery query,
  ) async {
    searchCalls += 1;
    lastQuery = query;
    requestedPaths.add(kPrivateChauffeurNearbyPath);
    final handler = searchHandler;
    if (handler != null) return handler(query);
    return const PrivateChauffeurDiscoveryPageData();
  }

  @override
  Future<Map<String, dynamic>?> loadPublicProfile(
    String publicPartnerId,
  ) async {
    profileCalls += 1;
    requestedPaths.add(kPrivateChauffeurProfilePath);
    final handler = profileHandler;
    if (handler != null) return handler(publicPartnerId);
    return null;
  }
}

class HttpPrivateChauffeurDiscoveryGateway
    implements PrivateChauffeurDiscoveryGateway {
  HttpPrivateChauffeurDiscoveryGateway({
    http.Client? client,
    String? bookingBaseUrl,
  }) : _client = client,
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
  Future<PrivateChauffeurDiscoveryPageData> search(
    LimousineDiscoveryQuery query,
  ) async {
    if (query.isUnscoped) {
      return const PrivateChauffeurDiscoveryPageData(needPlace: true);
    }
    final parameters = <String, String>{
      'service': kPrivateChauffeurServiceCode,
    };
    final postcode = (query.postcode ?? '').trim();
    if (postcode.isNotEmpty) {
      parameters['postcode'] = postcode;
    } else if (query.lat != null && query.lng != null) {
      parameters['lat'] = query.lat!.toStringAsFixed(6);
      parameters['lng'] = query.lng!.toStringAsFixed(6);
    }
    final uri = Uri.parse(
      '$_base$kPrivateChauffeurNearbyPath',
    ).replace(queryParameters: parameters);
    try {
      final res = await _get(uri);
      final body = _decode(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return const PrivateChauffeurDiscoveryPageData(networkError: true);
      }
      final raw = body['partners'];
      final cards = raw is List
          ? privateChauffeurCardsFromNearbyPartners(raw)
          : const <LimousineDiscoveryCard>[];
      return PrivateChauffeurDiscoveryPageData(cards: cards);
    } catch (_) {
      return const PrivateChauffeurDiscoveryPageData(networkError: true);
    }
  }

  @override
  Future<Map<String, dynamic>?> loadPublicProfile(
    String publicPartnerId,
  ) async {
    final id = publicPartnerId.trim();
    if (id.isEmpty) return null;
    final uri = Uri.parse(
      '$_base$kPrivateChauffeurProfilePath',
    ).replace(queryParameters: <String, String>{'partner_id': id});
    try {
      final res = await _get(uri);
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final body = _decode(res);
      final raw = body['profile'] is Map ? body['profile'] : body;
      if (raw is! Map) return null;
      final profile = asStringKeyedMap(raw);
      if (!privateChauffeurPartnerIsListable(profile)) return null;
      return profile;
    } catch (_) {
      return null;
    }
  }
}

enum PrivateChauffeurDiscoveryPhase {
  idle,
  loading,
  ready,
  empty,
  needPlace,
  network,
}

class PrivateChauffeurDiscoveryController extends ChangeNotifier {
  PrivateChauffeurDiscoveryController({
    required PrivateChauffeurDiscoveryGateway gateway,
  }) : _gateway = gateway;

  final PrivateChauffeurDiscoveryGateway _gateway;

  PrivateChauffeurDiscoveryPhase phase = PrivateChauffeurDiscoveryPhase.idle;
  List<LimousineDiscoveryCard> cards = const <LimousineDiscoveryCard>[];
  String unavailablePartnerId = '';
  bool openingProfile = false;

  bool get isSearching => phase == PrivateChauffeurDiscoveryPhase.loading;

  MemoryPrivateChauffeurDiscoveryGateway? get memoryGateway {
    final gateway = _gateway;
    return gateway is MemoryPrivateChauffeurDiscoveryGateway ? gateway : null;
  }

  Future<void> search(LimousineDiscoveryQuery? query) async {
    if (isSearching || openingProfile) return;
    final resolved = query ?? const LimousineDiscoveryQuery();
    if (resolved.isUnscoped) {
      phase = PrivateChauffeurDiscoveryPhase.needPlace;
      cards = const <LimousineDiscoveryCard>[];
      unavailablePartnerId = '';
      notifyListeners();
      return;
    }
    phase = PrivateChauffeurDiscoveryPhase.loading;
    unavailablePartnerId = '';
    notifyListeners();
    try {
      final result = await _gateway
          .search(resolved)
          .timeout(const Duration(seconds: 12));
      if (result.needPlace) {
        phase = PrivateChauffeurDiscoveryPhase.needPlace;
        cards = const <LimousineDiscoveryCard>[];
      } else if (result.networkError) {
        phase = PrivateChauffeurDiscoveryPhase.network;
        cards = const <LimousineDiscoveryCard>[];
      } else if (result.cards.isEmpty) {
        phase = PrivateChauffeurDiscoveryPhase.empty;
        cards = const <LimousineDiscoveryCard>[];
      } else {
        phase = PrivateChauffeurDiscoveryPhase.ready;
        cards = List<LimousineDiscoveryCard>.from(result.cards);
      }
    } on TimeoutException {
      phase = PrivateChauffeurDiscoveryPhase.network;
      cards = const <LimousineDiscoveryCard>[];
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>?> confirmProfile(
    LimousineDiscoveryCard card,
  ) async {
    if (openingProfile || isSearching) return null;
    openingProfile = true;
    unavailablePartnerId = '';
    notifyListeners();
    try {
      final profile = await _gateway
          .loadPublicProfile(card.publicPartnerId)
          .timeout(const Duration(seconds: 12));
      final map = profile == null ? null : asStringKeyedMap(profile);
      if (map == null || !privateChauffeurPartnerIsListable(map)) {
        unavailablePartnerId = card.publicPartnerId;
        return null;
      }
      return map;
    } on TimeoutException {
      unavailablePartnerId = card.publicPartnerId;
      return null;
    } finally {
      openingProfile = false;
      notifyListeners();
    }
  }
}
