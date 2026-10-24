import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../app_config.dart';
import '../customer_session_store.dart';
import 'affiliate_models.dart';

enum AffiliateFailure {
  signInRequired,
  unavailable,
  sessionChanged,
  termsChanged,
  identifiersInvalid,
}

class AffiliateException implements Exception {
  const AffiliateException(this.failure);
  final AffiliateFailure failure;
}

/// A private in-memory request owner. Never logged, serialized or put in URLs.
class AffiliateOwner {
  const AffiliateOwner(this.session, this.revision);
  final CustomerSession session;
  final int revision;
}

class OwnedAffiliateOverview {
  const OwnedAffiliateOverview(this.owner, this.data);
  final AffiliateOwner owner;
  final AffiliateOverview data;
}

class AffiliateRepository {
  AffiliateRepository({
    http.Client? transport,
    String? baseUrl,
    Future<CustomerSession?> Function()? loadSession,
    CustomerSession? Function()? currentSession,
    ValueListenable<int>? revision,
  }) : _http = transport ?? http.Client(),
       _ownsHttp = transport == null,
       _base = baseUrl ?? kBookingBaseUrl,
       _load = loadSession ?? CustomerSessionStore.instance.loadValidSession,
       _current =
           currentSession ?? CustomerSessionStore.instance.peekCachedSession,
       revision = revision ?? CustomerSessionStore.sessionRevision;
  final http.Client _http;
  final bool _ownsHttp;
  final String _base;
  final Future<CustomerSession?> Function() _load;
  final CustomerSession? Function() _current;
  final ValueListenable<int> revision;
  bool _disposed = false;

  bool owns(AffiliateOwner owner) {
    final current = _current(),
        expiry = DateTime.tryParse(owner.session.expiresAt);
    return !_disposed &&
        owner.revision == revision.value &&
        current != null &&
        current.customerId == owner.session.customerId &&
        current.customerSessionToken == owner.session.customerSessionToken &&
        expiry != null &&
        DateTime.now().toUtc().isBefore(expiry.toUtc());
  }

  Future<AffiliateOwner> _owner({AffiliateOwner? expected}) async {
    final before = revision.value;
    final cached = _current();
    final session = await _load();
    if (_disposed || (cached != null && before != revision.value)) {
      throw const AffiliateException(AffiliateFailure.sessionChanged);
    }
    if (session == null)
      throw const AffiliateException(AffiliateFailure.signInRequired);
    final owner = AffiliateOwner(session, revision.value);
    if (!owns(owner) ||
        (expected != null &&
            (!owns(expected) || expected.revision != owner.revision))) {
      throw const AffiliateException(AffiliateFailure.sessionChanged);
    }
    return expected ?? owner;
  }

  Uri _uri(String path, Map<String, String>? query) {
    final origin = Uri.parse(_base);
    if (origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment)
      throw const FormatException('Invalid origin');
    return origin.replace(
      path: '${origin.path.replaceFirst(RegExp(r'/$'), '')}$path',
      queryParameters: query,
    );
  }

  Future<Map<String, dynamic>> _request(
    AffiliateOwner owner,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (!owns(owner))
      throw const AffiliateException(AffiliateFailure.sessionChanged);
    try {
      final headers = {
        'Authorization': 'Bearer ${owner.session.customerSessionToken}',
        'Accept': 'application/json',
        'Cache-Control': 'no-store',
        if (body != null) 'Content-Type': 'application/json',
      };
      final response =
          await (body == null
                  ? _http.get(_uri(path, query), headers: headers)
                  : _http.post(
                      _uri(path, query),
                      headers: headers,
                      body: jsonEncode(body),
                    ))
              .timeout(const Duration(seconds: 12));
      if (!owns(owner))
        throw const AffiliateException(AffiliateFailure.sessionChanged);
      // Never clear a newer login (or mutate any session) on a late HTTP failure.
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const AffiliateException(AffiliateFailure.signInRequired);
      }
      if (response.statusCode == 400 || response.statusCode == 409) {
        if (response.statusCode == 400 &&
            const [
              '/affiliate/application',
              '/affiliate/application/identifiers',
            ].contains(path) &&
            response.bodyBytes.length <= 256 * 1024) {
          String? identifierError;
          try {
            final error = jsonDecode(utf8.decode(response.bodyBytes));
            if (error is Map && error['error'] is String)
              identifierError = error['error'] as String;
          } catch (_) {}
          if (const [
            'affiliate_application_identifier_invalid',
            'affiliate_business_identifiers_only',
          ].contains(identifierError)) {
            throw const AffiliateException(AffiliateFailure.identifiersInvalid);
          }
        }
        throw const AffiliateException(AffiliateFailure.termsChanged);
      }
      final cache = response.headers['cache-control']?.toLowerCase() ?? '';
      if (response.statusCode != 200 ||
          response.bodyBytes.length > 256 * 1024 ||
          !cache.contains('private') ||
          !cache.contains('no-store')) {
        throw const AffiliateException(AffiliateFailure.unavailable);
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
        throw const AffiliateException(AffiliateFailure.unavailable);
      }
      return decoded;
    } on AffiliateException {
      rethrow;
    } catch (_) {
      throw AffiliateException(
        owns(owner)
            ? AffiliateFailure.unavailable
            : AffiliateFailure.sessionChanged,
      );
    }
  }

  Future<OwnedAffiliateOverview> loadOverview() async {
    final owner = await _owner();
    final json = await _request(owner, '/affiliate/me');
    try {
      return OwnedAffiliateOverview(
        owner,
        AffiliateOverview.parse(json, owner.session.customerId),
      );
    } catch (_) {
      throw const AffiliateException(AffiliateFailure.unavailable);
    }
  }

  Future<OwnedAffiliateOverview> apply(
    OwnedAffiliateOverview overview, {
    required String displayName,
    required bool accepted,
    String applicantType = 'person',
    String legalName = '',
    String address = '',
    String country = '',
    String companyRegistrationNumber = '',
    String vatNumber = '',
  }) async {
    if (!overview.data.mayApply ||
        overview.data.status != 'not_enrolled' ||
        !accepted ||
        displayName.trim().isEmpty ||
        !const ['person', 'business'].contains(applicantType)) {
      throw const AffiliateException(AffiliateFailure.termsChanged);
    }
    _validateIdentifiers(companyRegistrationNumber, vatNumber);
    if (applicantType != 'business' &&
        (companyRegistrationNumber.isNotEmpty || vatNumber.isNotEmpty)) {
      throw const AffiliateException(AffiliateFailure.identifiersInvalid);
    }
    final owner = await _owner(expected: overview.owner);
    final json = await _request(
      owner,
      '/affiliate/application',
      body: {
        'display_name': displayName.trim(),
        'applicant_type': applicantType,
        if (legalName.trim().isNotEmpty) 'legal_name': legalName.trim(),
        if (address.trim().isNotEmpty) 'address': address.trim(),
        if (country.trim().isNotEmpty) 'country': country.trim().toUpperCase(),
        if (applicantType == 'business' && companyRegistrationNumber.isNotEmpty)
          'company_registration_number': companyRegistrationNumber,
        if (applicantType == 'business' && vatNumber.isNotEmpty)
          'vat_number': vatNumber,
        'terms_version': overview.data.termsVersion,
        'accepted': true,
      },
    );
    try {
      return OwnedAffiliateOverview(
        owner,
        AffiliateOverview.parse(json, owner.session.customerId),
      );
    } catch (_) {
      throw const AffiliateException(AffiliateFailure.unavailable);
    }
  }

  void _validateIdentifiers(String registration, String vat) {
    try {
      affiliateIdentifier(registration);
      affiliateIdentifier(vat);
    } on FormatException {
      throw const AffiliateException(AffiliateFailure.identifiersInvalid);
    }
  }

  Future<OwnedAffiliateOverview> updateApplicationIdentifiers(
    OwnedAffiliateOverview overview, {
    required String companyRegistrationNumber,
    required String vatNumber,
  }) async {
    if (overview.data.status != 'pending' ||
        overview.data.profile?.applicantType != 'business') {
      throw const AffiliateException(AffiliateFailure.termsChanged);
    }
    _validateIdentifiers(companyRegistrationNumber, vatNumber);
    final owner = await _owner(expected: overview.owner);
    final json = await _request(
      owner,
      '/affiliate/application/identifiers',
      body: {
        'expected_revision': overview.data.revision,
        'company_registration_number': companyRegistrationNumber,
        'vat_number': vatNumber,
      },
    );
    try {
      return OwnedAffiliateOverview(
        owner,
        AffiliateOverview.parse(json, owner.session.customerId),
      );
    } catch (_) {
      throw const AffiliateException(AffiliateFailure.unavailable);
    }
  }

  Future<AffiliatePayoutPage> loadPayouts(
    AffiliateOwner expected, {
    String? cursor,
  }) async {
    final owner = await _owner(expected: expected);
    final json = await _request(
      owner,
      '/affiliate/payouts',
      query: {'limit': '20', if (cursor != null) 'cursor': cursor},
    );
    try {
      return AffiliatePayoutPage.parse(json);
    } catch (_) {
      throw const AffiliateException(AffiliateFailure.unavailable);
    }
  }

  void dispose() {
    _disposed = true;
    if (_ownsHttp) _http.close();
  }

  Future<AffiliateEntryPage> loadEntries(
    AffiliateOwner expected, {
    String? cursor,
  }) async {
    final owner = await _owner(expected: expected);
    final json = await _request(
      owner,
      '/affiliate/entries',
      query: {'limit': '20', 'cursor': cursor ?? '0'},
    );
    try {
      return AffiliateEntryPage.parse(json);
    } catch (_) {
      throw const AffiliateException(AffiliateFailure.unavailable);
    }
  }

  Future<Map<String, dynamic>> administrativeRequest(
    OwnedAffiliateOverview overview,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    const getPaths = {
      'applications',
      'overview',
      'receipts/review',
      'batches',
      'audit',
      'registrations',
    };
    const postPaths = {
      'applications/review',
      'bank-accounts/verify',
      'owners/review',
      'receipts/basis',
      'receipts/retry',
      'receipts/recover',
      'batches',
      'batches/export',
      'batches/reconcile',
      'batches/cancel',
      'registrations/complete',
    };
    if (!overview.data.canAdminister ||
        !(body == null ? getPaths : postPaths).contains(path)) {
      throw const AffiliateException(AffiliateFailure.signInRequired);
    }
    final owner = await _owner(expected: overview.owner);
    // The server rechecks the genuine personal CEO capability on every call,
    // including inside the durable transaction. No local role grants access.
    return _request(owner, '/affiliate/admin/$path', body: body, query: query);
  }

  Future<OwnedAffiliateOverview> saveBank(
    OwnedAffiliateOverview overview, {
    required String iban,
    required String holder,
  }) async {
    final normalizedIban = iban.replaceAll(RegExp(r'\s'), '').toUpperCase();
    if (overview.data.status == 'not_enrolled' ||
        !RegExp(
          r'^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$',
        ).hasMatch(normalizedIban) ||
        holder.trim().isEmpty) {
      throw const AffiliateException(AffiliateFailure.termsChanged);
    }
    final owner = await _owner(expected: overview.owner);
    final json = await _request(
      owner,
      '/affiliate/bank-account',
      body: {
        'iban': normalizedIban,
        'account_holder': holder.trim(),
        'expected_revision': overview.data.revision,
      },
    );
    if (json['bank_verified'] != false ||
        json['revision'] != overview.data.revision + 1 ||
        json['bank_revision'] != overview.data.bankRevision + 1) {
      throw const AffiliateException(AffiliateFailure.unavailable);
    }
    try {
      return OwnedAffiliateOverview(
        owner,
        AffiliateOverview.parse(json, owner.session.customerId),
      );
    } catch (_) {
      throw const AffiliateException(AffiliateFailure.unavailable);
    }
  }

  Future<AffiliateReferralPage> loadReferrals(
    AffiliateOwner expected, {
    String? cursor,
  }) async {
    final owner = await _owner(expected: expected);
    final json = await _request(
      owner,
      '/affiliate/referrals',
      query: {'limit': '20', if (cursor != null) 'cursor': cursor},
    );
    try {
      return AffiliateReferralPage.parse(json);
    } catch (_) {
      throw const AffiliateException(AffiliateFailure.unavailable);
    }
  }
}
