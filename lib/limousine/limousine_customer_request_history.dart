// Persistent customer limousine quote-request history.
// Reuses flutter_secure_storage like the accepted-booking vault.
// Never writes limqs1 to SharedPreferences. Never logs vault contents.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app_strings.dart';
import 'limousine_customer_quote.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_quote_presentation.dart';

const int kLimousineCustomerRequestHistorySchemaVersion = 1;

const String kLimousineCustomerRequestHistoryStorageKey =
    'limousine_customer_quote_requests_v1';

const Key kLimousineCustomerRequestsSectionKey = ValueKey<String>(
  'limousine_customer_requests_section',
);
const Key kLimousineCustomerRequestsListKey = ValueKey<String>(
  'limousine_customer_requests_list',
);
const Key kLimousineCustomerRequestDetailKey = ValueKey<String>(
  'limousine_customer_request_detail',
);

class LimousineCustomerRequestHistoryException implements Exception {
  const LimousineCustomerRequestHistoryException();
}

class LimousineCustomerRequestRecord {
  const LimousineCustomerRequestRecord({
    required this.quoteRequestId,
    required this.statusRef,
    required this.state,
    this.companyName = '',
    this.vehicleDisplayName = '',
    this.offerDisplayName = '',
    this.from = '',
    this.to = '',
    this.scheduledPickupIso = '',
    this.publicPartnerId = '',
    this.request,
    this.updatedAt = '',
  });

  final String quoteRequestId;
  final String statusRef;
  final String state;
  final String companyName;
  final String vehicleDisplayName;
  final String offerDisplayName;
  final String from;
  final String to;
  final String scheduledPickupIso;
  final String publicPartnerId;
  final LimousineQuoteRequest? request;
  final String updatedAt;

  LimousineCustomerRequestRecord copyWith({
    String? state,
    String? companyName,
    String? vehicleDisplayName,
    String? offerDisplayName,
    String? from,
    String? to,
    String? scheduledPickupIso,
    String? publicPartnerId,
    LimousineQuoteRequest? request,
    String? updatedAt,
  }) {
    return LimousineCustomerRequestRecord(
      quoteRequestId: quoteRequestId,
      statusRef: statusRef,
      state: state ?? this.state,
      companyName: companyName ?? this.companyName,
      vehicleDisplayName: vehicleDisplayName ?? this.vehicleDisplayName,
      offerDisplayName: offerDisplayName ?? this.offerDisplayName,
      from: from ?? this.from,
      to: to ?? this.to,
      scheduledPickupIso: scheduledPickupIso ?? this.scheduledPickupIso,
      publicPartnerId: publicPartnerId ?? this.publicPartnerId,
      request: request ?? this.request,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schema_version': kLimousineCustomerRequestHistorySchemaVersion,
      'quote_request_id': quoteRequestId,
      'status_ref': statusRef,
      'state': state,
      'company_name': companyName,
      'vehicle_display_name': vehicleDisplayName,
      'offer_display_name': offerDisplayName,
      'from': from,
      'to': to,
      'scheduled_pickup_iso': scheduledPickupIso,
      'public_partner_id': publicPartnerId,
      'updated_at': updatedAt,
      if (request != null) 'request': _requestSnapshot(request!),
    };
  }

  factory LimousineCustomerRequestRecord.fromJson(Object? raw) {
    final map = raw is Map
        ? raw.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    LimousineQuoteRequest? request;
    final nested = map['request'];
    if (nested is Map) {
      try {
        request = LimousineQuoteRequest.fromJson(nested);
      } on FormatException {
        request = null;
      }
    }
    return LimousineCustomerRequestRecord(
      quoteRequestId: (map['quote_request_id'] ?? '').toString().trim(),
      statusRef: (map['status_ref'] ?? '').toString().trim(),
      state: LimousineQuoteStateId.normalize(
        (map['state'] ?? request?.state ?? '').toString(),
      ),
      companyName: (map['company_name'] ?? '').toString().trim(),
      vehicleDisplayName: (map['vehicle_display_name'] ?? '').toString().trim(),
      offerDisplayName: (map['offer_display_name'] ?? '').toString().trim(),
      from: (map['from'] ?? '').toString().trim(),
      to: (map['to'] ?? '').toString().trim(),
      scheduledPickupIso: (map['scheduled_pickup_iso'] ?? '').toString().trim(),
      publicPartnerId:
          (map['public_partner_id'] ??
                  map['publicPartnerId'] ??
                  request?.publicPartnerId ??
                  '')
              .toString()
              .trim(),
      request: request,
      updatedAt: (map['updated_at'] ?? '').toString().trim(),
    );
  }
}

Map<String, dynamic> _requestSnapshot(LimousineQuoteRequest request) {
  return <String, dynamic>{
    'quote_request_id': request.quoteRequestId,
    'state': request.state,
    'revision': request.revision,
    'offer_id': request.offerId,
    'service_class_id': request.serviceClassId,
    'vehicle_id': request.vehicleId,
    'journey_type': request.journeyType,
    'scheduled_pickup_iso': request.scheduledPickupIso,
    'pax': request.pax,
    'bags': request.bags,
    'created_at': request.createdAt,
    'updated_at': request.updatedAt,
    if (request.quote != null)
      'quote': <String, dynamic>{
        'total_incl_vat_cents': request.quote!.totalInclVatCents,
        'currency': request.quote!.currency,
        'vat_treatment': request.quote!.vatTreatment,
        'expires_at': request.quote!.expiresAt,
        'terms_revision': request.quote!.termsRevision,
        'public_text': request.quote!.publicText,
        'included_services': request.quote!.includedServices,
        'mobilisation_disclosure': request.quote!.mobilisationDisclosure,
        'terms': request.quote!.terms,
      },
    if (request.fulfilment != null)
      'fulfilment': <String, dynamic>{
        'from': request.fulfilment!.from,
        'to': request.fulfilment!.to,
        'stops': request.fulfilment!.stops,
        'customer_note': request.fulfilment!.customerNote,
      },
    'vehicle_snapshot': request.vehicleSnapshot,
    'pricing_snapshot': request.pricingSnapshot,
    'quotation_available': request.quotationAvailable,
    if (request.quotationRevision != null)
      'quotation_revision': request.quotationRevision,
    if (request.locale.isNotEmpty) 'locale': request.locale,
    'company_viewed': request.companyViewed,
    if (request.companyViewedAt.isNotEmpty)
      'company_viewed_at': request.companyViewedAt,
    if (request.quotationSentAt.isNotEmpty)
      'quotation_sent_at': request.quotationSentAt,
    if (request.quotationExpiresAt.isNotEmpty)
      'quotation_expires_at': request.quotationExpiresAt,
    if (request.quotationTotalInclVatCents != null)
      'quotation_total_incl_vat_cents': request.quotationTotalInclVatCents,
    if (request.quotationCurrency.isNotEmpty)
      'quotation_currency': request.quotationCurrency,
    if (request.acceptedAt.isNotEmpty) 'accepted_at': request.acceptedAt,
    if (request.publicPartnerId.isNotEmpty)
      'public_partner_id': request.publicPartnerId,
  };
}

abstract class LimousineCustomerRequestHistoryVault {
  Future<void> write(String value);
  Future<String?> read();
  Future<void> delete();
}

class FlutterSecureLimousineCustomerRequestHistoryVault
    implements LimousineCustomerRequestHistoryVault {
  FlutterSecureLimousineCustomerRequestHistoryVault({
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String value) async {
    try {
      await _storage.write(
        key: kLimousineCustomerRequestHistoryStorageKey,
        value: value,
      );
    } catch (_) {
      throw const LimousineCustomerRequestHistoryException();
    }
  }

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(
        key: kLimousineCustomerRequestHistoryStorageKey,
      );
    } catch (_) {
      throw const LimousineCustomerRequestHistoryException();
    }
  }

  @override
  Future<void> delete() async {
    try {
      await _storage.delete(key: kLimousineCustomerRequestHistoryStorageKey);
    } catch (_) {
      throw const LimousineCustomerRequestHistoryException();
    }
  }
}

class MemoryLimousineCustomerRequestHistoryVault
    implements LimousineCustomerRequestHistoryVault {
  MemoryLimousineCustomerRequestHistoryVault();

  String? value;

  @override
  Future<void> write(String next) async {
    value = next;
  }

  @override
  Future<String?> read() async => value;

  @override
  Future<void> delete() async {
    value = null;
  }
}

class LimousineCustomerRequestHistoryRepository {
  LimousineCustomerRequestHistoryRepository({
    LimousineCustomerRequestHistoryVault? vault,
  }) : _vault = vault ?? FlutterSecureLimousineCustomerRequestHistoryVault();

  final LimousineCustomerRequestHistoryVault _vault;

  Future<List<LimousineCustomerRequestRecord>> list({
    String customerId = '',
  }) async {
    final items = await _readAll();
    final scope = customerId.trim();
    if (scope.isEmpty) return items;
    return items
        .where((item) => item.quoteRequestId.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> upsert(LimousineCustomerRequestRecord record) async {
    if (record.quoteRequestId.trim().isEmpty) return;
    if (!looksLikeLimousineStatusRef(record.statusRef)) return;
    final items = await _readAll();
    final next = <LimousineCustomerRequestRecord>[];
    var replaced = false;
    for (final item in items) {
      if (item.quoteRequestId == record.quoteRequestId) {
        next.add(record);
        replaced = true;
      } else {
        next.add(item);
      }
    }
    if (!replaced) next.insert(0, record);
    await _writeAll(next);
  }

  Future<void> updateFromPoll(LimousineQuoteRequest request) async {
    final items = await _readAll();
    final next = <LimousineCustomerRequestRecord>[];
    for (final item in items) {
      if (item.quoteRequestId == request.quoteRequestId) {
        next.add(
          item.copyWith(
            state: request.state,
            from: request.fulfilment?.from ?? item.from,
            to: request.fulfilment?.to ?? item.to,
            scheduledPickupIso: request.scheduledPickupIso.isNotEmpty
                ? request.scheduledPickupIso
                : item.scheduledPickupIso,
            vehicleDisplayName:
                limousineQuoteVehicleDisplay(request, AppLanguage.nl).isNotEmpty
                ? limousineQuoteVehicleDisplay(request, AppLanguage.nl)
                : item.vehicleDisplayName,
            request: request,
            updatedAt: request.updatedAt,
          ),
        );
      } else {
        next.add(item);
      }
    }
    await _writeAll(next);
  }

  Future<void> clearAll() async {
    await _vault.delete();
  }

  Future<List<LimousineCustomerRequestRecord>> _readAll() async {
    try {
      final raw = await _vault.read();
      if (raw == null || raw.trim().isEmpty) {
        return <LimousineCustomerRequestRecord>[];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <LimousineCustomerRequestRecord>[];
      final items = decoded['items'];
      if (items is! List) return const <LimousineCustomerRequestRecord>[];
      final out = <LimousineCustomerRequestRecord>[];
      for (final item in items) {
        final record = LimousineCustomerRequestRecord.fromJson(item);
        if (record.quoteRequestId.isEmpty) continue;
        out.add(record);
      }
      return out;
    } on LimousineCustomerRequestHistoryException {
      return const <LimousineCustomerRequestRecord>[];
    } catch (_) {
      return const <LimousineCustomerRequestRecord>[];
    }
  }

  Future<void> _writeAll(List<LimousineCustomerRequestRecord> items) async {
    await _vault.write(
      jsonEncode(<String, dynamic>{
        'schema_version': kLimousineCustomerRequestHistorySchemaVersion,
        'items': items.map((item) => item.toJson()).toList(growable: false),
      }),
    );
  }
}
