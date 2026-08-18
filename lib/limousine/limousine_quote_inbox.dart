// LIMOUSINE-MARKETPLACE-P2D1 — company quote-inbox models, filters, money,
// action policy and revision-safe merge. Mirrors the Worker contracts in
// limousine_manual_quote.mjs / limousine_quote_inbox.mjs. The server remains
// authoritative for state, revision, price, terms and transition validity.

import 'package:flutter/foundation.dart';

import 'limousine_offers.dart';

const Key kLimousineQuoteInboxEntryKey = ValueKey<String>(
  'limousine_quote_inbox_entry',
);
const Key kLimousineQuoteInboxPageKey = ValueKey<String>(
  'limousine_quote_inbox_page',
);
const Key kLimousineQuoteInboxLoadingKey = ValueKey<String>(
  'limousine_quote_inbox_loading',
);
const Key kLimousineQuoteInboxEmptyKey = ValueKey<String>(
  'limousine_quote_inbox_empty',
);
const Key kLimousineQuoteInboxListKey = ValueKey<String>(
  'limousine_quote_inbox_list',
);
const Key kLimousineQuoteInboxRetryKey = ValueKey<String>(
  'limousine_quote_inbox_retry',
);
const Key kLimousineQuoteInboxFilterBarKey = ValueKey<String>(
  'limousine_quote_inbox_filters',
);
const Key kLimousineQuoteInboxPhoneLayoutKey = ValueKey<String>(
  'limousine_quote_inbox_phone',
);
const Key kLimousineQuoteInboxTabletLayoutKey = ValueKey<String>(
  'limousine_quote_inbox_tablet',
);
const Key kLimousineQuoteDetailPageKey = ValueKey<String>(
  'limousine_quote_detail_page',
);
const Key kLimousineQuoteMarkViewedKey = ValueKey<String>(
  'limousine_quote_mark_viewed',
);
const Key kLimousineQuoteSubmitKey = ValueKey<String>('limousine_quote_submit');
const Key kLimousineQuoteDeclineKey = ValueKey<String>(
  'limousine_quote_decline',
);
const Key kLimousineQuoteReadOnlyBannerKey = ValueKey<String>(
  'limousine_quote_readonly_banner',
);
const Key kLimousineQuoteEditorPageKey = ValueKey<String>(
  'limousine_quote_editor_page',
);
const Key kLimousineQuoteDeclineDialogKey = ValueKey<String>(
  'limousine_quote_decline_dialog',
);
const Key kLimousineQuoteInboxHeroKey = ValueKey<String>(
  'limousine_quote_inbox_hero',
);
const Key kLimousineQuoteInboxKpiRowKey = ValueKey<String>(
  'limousine_quote_inbox_kpis',
);
const Key kLimousineQuoteInboxSearchKey = ValueKey<String>(
  'limousine_quote_inbox_search',
);
const Key kLimousineQuoteInboxGateOffKey = ValueKey<String>(
  'limousine_quote_inbox_gate_off',
);
const Key kLimousineQuoteInboxErrorKey = ValueKey<String>(
  'limousine_quote_inbox_error',
);
const Key kLimousineQuoteInboxRefreshKey = ValueKey<String>(
  'limousine_quote_inbox_refresh',
);
const Key kLimousineQuoteInboxTestBadgeKey = ValueKey<String>(
  'limousine_quote_inbox_test_badge',
);
const Key kLimousineQuoteInboxTileVisualKey = ValueKey<String>(
  'limousine_quote_inbox_tile_visual',
);
const Key kLimousineQuoteInboxTileBadgeKey = ValueKey<String>(
  'limousine_quote_inbox_tile_badge',
);

Key limousineQuoteInboxKpiKey(String code) =>
    ValueKey<String>('limousine_quote_inbox_kpi_$code');

Key limousineQuoteInboxActionKey(String quoteRequestId, String action) =>
    ValueKey<String>('limousine_inbox_action_${quoteRequestId}_$action');

abstract final class LimousineQuoteStateId {
  static const String requested = 'requested';
  static const String viewedByCompany = 'viewed_by_company';
  static const String quoted = 'quoted';
  static const String customerAcceptanceRequired =
      'customer_acceptance_required';
  static const String accepted = 'accepted';
  static const String bookingCreated = 'booking_created';
  static const String declined = 'declined';
  static const String expired = 'expired';
  static const String withdrawn = 'withdrawn';
  static const String superseded = 'superseded';
  static const String cancelled = 'cancelled';

  static const Set<String> known = <String>{
    requested,
    viewedByCompany,
    quoted,
    customerAcceptanceRequired,
    accepted,
    bookingCreated,
    declined,
    expired,
    withdrawn,
    superseded,
    cancelled,
  };

  static const Set<String> terminal = <String>{
    bookingCreated,
    declined,
    expired,
    withdrawn,
    superseded,
    cancelled,
  };

  static const Set<String> closedGroup = <String>{
    declined,
    expired,
    withdrawn,
    superseded,
    cancelled,
  };

  static const Set<String> waitingForCustomer = <String>{
    quoted,
    customerAcceptanceRequired,
  };

  static bool isKnown(String state) => known.contains(normalize(state));

  static bool isTerminal(String state) => terminal.contains(normalize(state));

  static String normalize(String? raw) =>
      (raw ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
}

enum LimousineQuoteInboxFilter {
  all,
  requested,
  viewed,
  waitingForCustomer,
  accepted,
  completed,
  closed,
}

extension LimousineQuoteInboxFilterX on LimousineQuoteInboxFilter {
  /// Server `state` query accepts one stored value. Multi-state visual groups
  /// return null so the client filters the unfiltered page.
  String? get serverState {
    switch (this) {
      case LimousineQuoteInboxFilter.all:
        return null;
      case LimousineQuoteInboxFilter.requested:
        return LimousineQuoteStateId.requested;
      case LimousineQuoteInboxFilter.viewed:
        return LimousineQuoteStateId.viewedByCompany;
      case LimousineQuoteInboxFilter.waitingForCustomer:
        return null;
      case LimousineQuoteInboxFilter.accepted:
        return LimousineQuoteStateId.accepted;
      case LimousineQuoteInboxFilter.completed:
        return LimousineQuoteStateId.bookingCreated;
      case LimousineQuoteInboxFilter.closed:
        return null;
    }
  }

  Set<String> get acceptedStates {
    switch (this) {
      case LimousineQuoteInboxFilter.all:
        return LimousineQuoteStateId.known;
      case LimousineQuoteInboxFilter.requested:
        return const <String>{LimousineQuoteStateId.requested};
      case LimousineQuoteInboxFilter.viewed:
        return const <String>{LimousineQuoteStateId.viewedByCompany};
      case LimousineQuoteInboxFilter.waitingForCustomer:
        return LimousineQuoteStateId.waitingForCustomer;
      case LimousineQuoteInboxFilter.accepted:
        return const <String>{LimousineQuoteStateId.accepted};
      case LimousineQuoteInboxFilter.completed:
        return const <String>{LimousineQuoteStateId.bookingCreated};
      case LimousineQuoteInboxFilter.closed:
        return LimousineQuoteStateId.closedGroup;
    }
  }

  bool accepts(String state) {
    if (this == LimousineQuoteInboxFilter.all) return true;
    return acceptedStates.contains(LimousineQuoteStateId.normalize(state));
  }
}

const int kLimousineQuoteInboxPageDefault = 20;
const int kLimousineQuoteInboxPageMax = 25;

const List<String> kLimousineRequiredTermsKeys = <String>[
  'cancellation_deadline_hours',
  'cancellation_penalty_percent',
  'waiting_time_included_minutes',
  'waiting_time_overage_cents_per_minute',
  'no_show_penalty_percent',
  'overtime_cents_per_hour',
];

const Set<String> kLimousineKnownQuotePayloadKeys = <String>{
  'total_incl_vat_cents',
  'currency',
  'vat_treatment',
  'vat_rate',
  'vat_rate_source',
  'public_text',
  'expires_at',
  'included_services',
  'paid_extras',
  'separately_priced_extras',
  'mobilisation_disclosure',
  'terms',
  'terms_revision',
};

const Set<String> kLimousineKnownTermsKeys = <String>{
  'terms_revision',
  'cancellation_deadline_hours',
  'cancellation_penalty_percent',
  'waiting_time_included_minutes',
  'waiting_time_overage_cents_per_minute',
  'no_show_penalty_percent',
  'overtime_cents_per_hour',
  'included_services',
  'paid_extras',
  'mobilisation_disclosure',
  'customer_obligations',
  'important_information',
};

const List<String> kLimousineQuoteForbiddenDisplayKeys = <String>[
  'authorization',
  'headers',
  'cookie',
  'card',
  'cvc',
  'pan',
  'api_key',
  'secret',
  'token',
  'acceptance_reference',
  'status_ref',
  'status_access',
  'customer_fingerprint',
  'email',
  'phone',
  'customer_name',
  'customer_reference',
  'operating_base_address',
  'internal_cost',
  'margin',
  'provider_payload',
  'audit',
  'itinerary_fingerprint',
];

const String kLimousineDeclineReasonCompanyDeclined = 'company_declined';

bool limousineQuoteInboxEntryVisible({required bool? entitled}) =>
    entitled == true;

bool limousineQuoteInboxIsTablet(double shortestSide) => shortestSide >= 600;

int? limousineMajorUnitsToCents(String raw) {
  final text = raw.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (text.isEmpty) return null;
  final negative = text.startsWith('-');
  final body = negative ? text.substring(1) : text;
  if (body.isEmpty || body == '.') return null;
  final parts = body.split('.');
  if (parts.length > 2) return null;
  final wholeText = parts[0].isEmpty ? '0' : parts[0];
  if (!RegExp(r'^\d+$').hasMatch(wholeText)) return null;
  final whole = int.parse(wholeText);
  var fraction = 0;
  if (parts.length == 2) {
    final fracText = parts[1];
    if (fracText.isEmpty) {
      fraction = 0;
    } else if (fracText.length == 1) {
      if (!RegExp(r'^\d$').hasMatch(fracText)) return null;
      fraction = int.parse(fracText) * 10;
    } else if (fracText.length == 2) {
      if (!RegExp(r'^\d{2}$').hasMatch(fracText)) return null;
      fraction = int.parse(fracText);
    } else {
      return null;
    }
  }
  final cents = whole * 100 + fraction;
  return negative ? -cents : cents;
}

String limousineCentsToMajorUnits(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final frac = (abs % 100).toString().padLeft(2, '0');
  return '$sign$whole.$frac';
}

String formatLimousineMoney(int cents, String currency) {
  final iso = limousineCurrencyOf(currency);
  final code = iso.isEmpty ? currency.trim().toUpperCase() : iso;
  return '$code ${limousineCentsToMajorUnits(cents)}';
}

Map<String, dynamic> _asMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

String _text(Object? raw, {int max = 240}) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty) return '';
  return value.length <= max ? value : value.substring(0, max);
}

int? _intOf(Object? raw) => limousineCentsOf(raw);

List<String> _stringList(Object? raw, {int max = 64}) {
  if (raw is! List) return const <String>[];
  final out = <String>[];
  for (final item in raw.take(20)) {
    final text = _text(item, max: max);
    if (text.isNotEmpty) out.add(text);
  }
  return out;
}

Map<String, String> _localized(Object? raw, {int max = 1200}) {
  final src = _asMap(raw);
  final out = <String, String>{};
  for (final lang in const <String>['nl', 'en', 'fr', 'es']) {
    final text = _text(src[lang], max: max);
    if (text.isNotEmpty) out[lang] = text;
  }
  return out;
}

String localizedLimousineText(
  Map<String, String> values, {
  required String languageCode,
}) {
  final code = languageCode.trim().toLowerCase();
  final direct = values[code];
  if (direct != null && direct.trim().isNotEmpty) return direct.trim();
  for (final lang in const <String>['nl', 'en', 'fr', 'es']) {
    final text = values[lang];
    if (text != null && text.trim().isNotEmpty) return text.trim();
  }
  return '';
}

bool limousineQuoteProjectionLeaksForbidden(Object? raw) {
  if (raw is! Map) return false;
  return _containsForbiddenKey(raw);
}

bool _containsForbiddenKey(Object? raw) {
  if (raw is Map) {
    for (final entry in raw.entries) {
      final key = entry.key.toString().trim().toLowerCase();
      if (kLimousineQuoteForbiddenDisplayKeys.contains(key)) return true;
      if (_containsForbiddenKey(entry.value)) return true;
    }
  } else if (raw is List) {
    for (final item in raw) {
      if (_containsForbiddenKey(item)) return true;
    }
  }
  return false;
}

Map<String, dynamic> stripLimousineQuoteForbidden(Map<String, dynamic> raw) {
  final out = <String, dynamic>{};
  raw.forEach((key, value) {
    final token = key.trim().toLowerCase();
    if (kLimousineQuoteForbiddenDisplayKeys.contains(token)) return;
    if (value is Map) {
      out[key] = stripLimousineQuoteForbidden(_asMap(value));
    } else if (value is List) {
      out[key] = value
          .map(
            (item) =>
                item is Map ? stripLimousineQuoteForbidden(_asMap(item)) : item,
          )
          .toList();
    } else {
      out[key] = value;
    }
  });
  return out;
}

class LimousineQuoteInboxMeta {
  const LimousineQuoteInboxMeta({
    this.activitySeq,
    this.transitionsBlocked = false,
  });

  final int? activitySeq;
  final bool transitionsBlocked;

  factory LimousineQuoteInboxMeta.fromJson(Object? raw) {
    final map = _asMap(raw);
    return LimousineQuoteInboxMeta(
      activitySeq: _intOf(map['activity_seq'] ?? map['activitySeq']),
      transitionsBlocked:
          map['transitions_blocked'] == true ||
          map['transitionsBlocked'] == true,
    );
  }
}

class LimousineQuoteFulfilment {
  const LimousineQuoteFulfilment({
    this.from = '',
    this.to = '',
    this.stops = const <String>[],
    this.returnPickupIso = '',
    this.requestedDurationMinutes,
    this.customerNote = '',
    this.locale = '',
  });

  final String from;
  final String to;
  final List<String> stops;
  final String returnPickupIso;
  final int? requestedDurationMinutes;
  final String customerNote;
  final String locale;

  bool get hasJourney => from.isNotEmpty || to.isNotEmpty || stops.isNotEmpty;

  factory LimousineQuoteFulfilment.fromJson(Object? raw) {
    final map = _asMap(raw);
    final stopsRaw = map['stops'];
    final stops = <String>[];
    if (stopsRaw is List) {
      for (final item in stopsRaw.take(8)) {
        final text = _text(item, max: 240);
        if (text.isNotEmpty) stops.add(text);
      }
    }
    return LimousineQuoteFulfilment(
      from: _text(map['from'], max: 240),
      to: _text(map['to'], max: 240),
      stops: stops,
      returnPickupIso: _text(
        map['return_pickup_iso'] ?? map['returnPickupIso'],
        max: 40,
      ),
      requestedDurationMinutes: _intOf(
        map['requested_duration_minutes'] ?? map['requestedDurationMinutes'],
      ),
      customerNote: _text(
        map['customer_note'] ?? map['customerNote'],
        max: 500,
      ),
      locale: _text(map['locale'], max: 8),
    );
  }
}

class LimousineQuotedPrice {
  const LimousineQuotedPrice({
    required this.totalInclVatCents,
    required this.currency,
    this.vatTreatment = '',
    this.vatRate,
    this.publicText = const <String, String>{},
    this.includedServices = const <Map<String, dynamic>>[],
    this.separatelyPricedExtras = const <Map<String, dynamic>>[],
    this.mobilisationDisclosure = const <String, String>{},
    this.termsRevision,
    this.expiresAt = '',
    this.quotedAt = '',
    this.terms,
  });

  final int totalInclVatCents;
  final String currency;
  final String vatTreatment;
  final num? vatRate;
  final Map<String, String> publicText;
  final List<Map<String, dynamic>> includedServices;
  final List<Map<String, dynamic>> separatelyPricedExtras;
  final Map<String, String> mobilisationDisclosure;
  final int? termsRevision;
  final String expiresAt;
  final String quotedAt;
  final Map<String, dynamic>? terms;

  factory LimousineQuotedPrice.fromJson(Object? raw) {
    final map = _asMap(raw);
    if (map.isEmpty) {
      throw const FormatException('missing_quote');
    }
    final cents = _intOf(
      map['total_incl_vat_cents'] ?? map['totalInclVatCents'],
    );
    final currency = limousineCurrencyOf(map['currency']);
    if (cents == null || currency.isEmpty) {
      throw const FormatException('invalid_quote');
    }
    final extras =
        map['separately_priced_extras'] ??
        map['separatelyPricedExtras'] ??
        map['paid_extras'];
    final services = map['included_services'] ?? map['includedServices'];
    final termsRaw = map['terms'];
    return LimousineQuotedPrice(
      totalInclVatCents: cents,
      currency: currency,
      vatTreatment: _text(map['vat_treatment'] ?? map['vatTreatment'], max: 16),
      vatRate: map['vat_rate'] is num
          ? map['vat_rate'] as num
          : num.tryParse('${map['vat_rate'] ?? map['vatRate'] ?? ''}'),
      publicText: _localized(map['public_text'] ?? map['publicText']),
      includedServices: _objectList(services),
      separatelyPricedExtras: _objectList(extras),
      mobilisationDisclosure: _localized(
        map['mobilisation_disclosure'] ?? map['mobilisationDisclosure'],
        max: 240,
      ),
      termsRevision: _intOf(map['terms_revision'] ?? map['termsRevision']),
      expiresAt: _text(map['expires_at'] ?? map['expiresAt'], max: 40),
      quotedAt: _text(map['quoted_at'] ?? map['quotedAt'], max: 40),
      terms: termsRaw is Map
          ? stripLimousineQuoteForbidden(_asMap(termsRaw))
          : null,
    );
  }
}

List<Map<String, dynamic>> _objectList(Object? raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  final out = <Map<String, dynamic>>[];
  for (final item in raw.take(20)) {
    if (item is Map) out.add(stripLimousineQuoteForbidden(_asMap(item)));
  }
  return out;
}

class LimousineQuoteDecline {
  const LimousineQuoteDecline({
    this.reasonCode = '',
    this.publicText = const <String, String>{},
  });

  final String reasonCode;
  final Map<String, String> publicText;

  factory LimousineQuoteDecline.fromJson(Object? raw) {
    final map = _asMap(raw);
    return LimousineQuoteDecline(
      reasonCode: _text(map['reason_code'] ?? map['reasonCode'], max: 64),
      publicText: _localized(map['public_text'] ?? map['publicText'], max: 600),
    );
  }
}

class LimousineQuoteRequest {
  const LimousineQuoteRequest({
    required this.quoteRequestId,
    required this.state,
    required this.revision,
    this.offerId = '',
    this.serviceClassId = '',
    this.vehicleId = '',
    this.journeyType = '',
    this.scheduledPickupIso = '',
    this.roundtrip = false,
    this.pax,
    this.bags,
    this.selectedExtraIds = const <String>[],
    this.quote,
    this.decline,
    this.bookingReference = '',
    this.createdAt = '',
    this.updatedAt = '',
    this.fulfilment,
    this.inbox = const LimousineQuoteInboxMeta(),
    this.acceptanceAllowed,
    this.acceptanceBlockedReason = '',
    this.missingTerms = const <String>[],
  });

  final String quoteRequestId;
  final String state;
  final int revision;
  final String offerId;
  final String serviceClassId;
  final String vehicleId;
  final String journeyType;
  final String scheduledPickupIso;
  final bool roundtrip;
  final int? pax;
  final int? bags;
  final List<String> selectedExtraIds;
  final LimousineQuotedPrice? quote;
  final LimousineQuoteDecline? decline;
  final String bookingReference;
  final String createdAt;
  final String updatedAt;
  final LimousineQuoteFulfilment? fulfilment;
  final LimousineQuoteInboxMeta inbox;
  final bool? acceptanceAllowed;
  final String acceptanceBlockedReason;
  final List<String> missingTerms;

  bool get isUnread =>
      LimousineQuoteStateId.normalize(state) == LimousineQuoteStateId.requested;

  bool get isUnknownState => !LimousineQuoteStateId.isKnown(state);

  bool get transitionsBlocked => inbox.transitionsBlocked;

  factory LimousineQuoteRequest.fromJson(Object? raw) {
    final map = stripLimousineQuoteForbidden(_asMap(raw));
    final id = _text(
      map['quote_request_id'] ?? map['quoteRequestId'],
      max: 120,
    );
    if (id.isEmpty) {
      throw const FormatException('missing_quote_request_id');
    }
    final extras = map['selected_extra_ids'] ?? map['selectedExtraIds'];
    final extraIds = <String>[];
    if (extras is List) {
      for (final item in extras) {
        final text = _text(item, max: 64);
        if (text.isNotEmpty) extraIds.add(text);
      }
    }
    LimousineQuotedPrice? quote;
    if (map['quote'] is Map) {
      try {
        quote = LimousineQuotedPrice.fromJson(map['quote']);
      } on FormatException {
        quote = null;
      }
    }
    return LimousineQuoteRequest(
      quoteRequestId: id,
      state: LimousineQuoteStateId.normalize(_text(map['state'], max: 40)),
      revision: _intOf(map['revision']) ?? 0,
      offerId: _text(map['offer_id'] ?? map['offerId'], max: 64),
      serviceClassId: _text(
        map['service_class_id'] ?? map['serviceClassId'],
        max: 64,
      ),
      vehicleId: _text(map['vehicle_id'] ?? map['vehicleId'], max: 96),
      journeyType: _text(map['journey_type'] ?? map['journeyType'], max: 32),
      scheduledPickupIso: _text(
        map['scheduled_pickup_iso'] ?? map['scheduledPickupIso'],
        max: 40,
      ),
      roundtrip: map['roundtrip'] == true,
      pax: _intOf(map['pax']),
      bags: _intOf(map['bags']),
      selectedExtraIds: extraIds,
      quote: quote,
      decline: map['decline'] is Map
          ? LimousineQuoteDecline.fromJson(map['decline'])
          : null,
      bookingReference: _text(
        map['booking_reference'] ?? map['bookingReference'],
        max: 64,
      ),
      createdAt: _text(map['created_at'] ?? map['createdAt'], max: 40),
      updatedAt: _text(map['updated_at'] ?? map['updatedAt'], max: 40),
      fulfilment: map['fulfilment'] is Map
          ? LimousineQuoteFulfilment.fromJson(map['fulfilment'])
          : null,
      inbox: LimousineQuoteInboxMeta.fromJson(map['inbox']),
      acceptanceAllowed: map.containsKey('acceptance_allowed')
          ? map['acceptance_allowed'] == true
          : (map.containsKey('acceptanceAllowed')
                ? map['acceptanceAllowed'] == true
                : null),
      acceptanceBlockedReason: _text(
        map['acceptance_blocked_reason'] ?? map['acceptanceBlockedReason'],
        max: 64,
      ),
      missingTerms: _stringList(
        map['missing_terms'] ?? map['missingTerms'],
        max: 64,
      ),
    );
  }

  LimousineQuoteRequest mergeAuthoritative(LimousineQuoteRequest incoming) {
    return LimousineQuoteRequest(
      quoteRequestId: incoming.quoteRequestId,
      state: incoming.state,
      revision: incoming.revision,
      offerId: incoming.offerId.isNotEmpty ? incoming.offerId : offerId,
      serviceClassId: incoming.serviceClassId.isNotEmpty
          ? incoming.serviceClassId
          : serviceClassId,
      vehicleId: incoming.vehicleId.isNotEmpty ? incoming.vehicleId : vehicleId,
      journeyType: incoming.journeyType.isNotEmpty
          ? incoming.journeyType
          : journeyType,
      scheduledPickupIso: incoming.scheduledPickupIso.isNotEmpty
          ? incoming.scheduledPickupIso
          : scheduledPickupIso,
      roundtrip: incoming.roundtrip,
      pax: incoming.pax ?? pax,
      bags: incoming.bags ?? bags,
      selectedExtraIds: incoming.selectedExtraIds.isNotEmpty
          ? incoming.selectedExtraIds
          : selectedExtraIds,
      quote: incoming.quote ?? quote,
      decline: incoming.decline ?? decline,
      bookingReference: incoming.bookingReference.isNotEmpty
          ? incoming.bookingReference
          : bookingReference,
      createdAt: incoming.createdAt.isNotEmpty ? incoming.createdAt : createdAt,
      updatedAt: incoming.updatedAt.isNotEmpty ? incoming.updatedAt : updatedAt,
      fulfilment: incoming.fulfilment ?? fulfilment,
      inbox:
          incoming.inbox.activitySeq != null ||
              incoming.inbox.transitionsBlocked
          ? incoming.inbox
          : inbox,
      acceptanceAllowed: incoming.acceptanceAllowed ?? acceptanceAllowed,
      acceptanceBlockedReason: incoming.acceptanceBlockedReason,
      missingTerms: incoming.missingTerms,
    );
  }
}

class LimousineQuoteInboxPageData {
  const LimousineQuoteInboxPageData({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<LimousineQuoteRequest> items;
  final String? nextCursor;
  final bool hasMore;

  factory LimousineQuoteInboxPageData.fromJson(Object? raw) {
    final map = stripLimousineQuoteForbidden(_asMap(raw));
    final itemsRaw = map['items'];
    final items = <LimousineQuoteRequest>[];
    if (itemsRaw is List) {
      for (final item in itemsRaw) {
        if (item is! Map) continue;
        try {
          items.add(LimousineQuoteRequest.fromJson(item));
        } on FormatException {
          continue;
        }
      }
    }
    final cursor = _text(map['next_cursor'] ?? map['nextCursor'], max: 400);
    return LimousineQuoteInboxPageData(
      items: items,
      nextCursor: cursor.isEmpty ? null : cursor,
      hasMore: map['has_more'] == true || map['hasMore'] == true,
    );
  }
}

/// Opaque cursor is forwarded as-is. Never decode or invent one.
String? opaqueLimousineInboxCursor(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty || text.length > 400) return null;
  return text;
}

List<LimousineQuoteRequest> mergeLimousineInboxPages({
  required List<LimousineQuoteRequest> existing,
  required List<LimousineQuoteRequest> incoming,
}) {
  final latest = <String, LimousineQuoteRequest>{};
  for (final item in existing) {
    latest[item.quoteRequestId] = item;
  }
  for (final item in incoming) {
    final prev = latest[item.quoteRequestId];
    if (prev == null || item.revision >= prev.revision) {
      latest[item.quoteRequestId] = item;
    }
  }
  final out = <LimousineQuoteRequest>[];
  final seen = <String>{};
  for (final item in existing) {
    final next = latest[item.quoteRequestId];
    if (next != null && seen.add(next.quoteRequestId)) {
      out.add(next);
    }
  }
  for (final item in incoming) {
    if (seen.add(item.quoteRequestId)) {
      out.add(latest[item.quoteRequestId]!);
    }
  }
  return out;
}

class LimousineQuoteActions {
  const LimousineQuoteActions({
    required this.canMarkViewed,
    required this.canQuote,
    required this.canDecline,
    required this.readOnly,
  });

  final bool canMarkViewed;
  final bool canQuote;
  final bool canDecline;
  final bool readOnly;

  bool get hasCommercial => canQuote || canDecline;
}

LimousineQuoteActions limousineQuoteActionsFor(
  LimousineQuoteRequest record, {
  bool gateOff = false,
}) {
  final state = LimousineQuoteStateId.normalize(record.state);
  final unknown = !LimousineQuoteStateId.isKnown(state);
  final terminal = LimousineQuoteStateId.isTerminal(state);
  final accepted =
      state == LimousineQuoteStateId.accepted ||
      state == LimousineQuoteStateId.bookingCreated;
  final blocked = record.transitionsBlocked || gateOff || unknown;
  final revisionPresent =
      record.revision >= 0 && record.quoteRequestId.isNotEmpty;
  final readOnly =
      blocked || terminal || accepted || !revisionPresent || unknown;
  final canViewed =
      !gateOff &&
      !unknown &&
      revisionPresent &&
      state == LimousineQuoteStateId.requested;
  final canQuote =
      !readOnly &&
      (state == LimousineQuoteStateId.requested ||
          state == LimousineQuoteStateId.viewedByCompany);
  final canDecline =
      !readOnly &&
      (state == LimousineQuoteStateId.requested ||
          state == LimousineQuoteStateId.viewedByCompany ||
          state == LimousineQuoteStateId.quoted ||
          state == LimousineQuoteStateId.customerAcceptanceRequired);
  return LimousineQuoteActions(
    canMarkViewed: canViewed,
    canQuote: canQuote,
    canDecline: canDecline,
    readOnly: readOnly || (!canViewed && !canQuote && !canDecline),
  );
}

class LimousineCompanyQuoteDraft {
  const LimousineCompanyQuoteDraft({
    this.totalInclVatCents,
    this.currency = '',
    this.vatTreatment = '',
    this.vatRate,
    this.expiresAt = '',
    this.termsRevision,
    this.cancellationDeadlineHours,
    this.cancellationPenaltyPercent,
    this.waitingTimeIncludedMinutes,
    this.waitingTimeOverageCentsPerMinute,
    this.noShowPenaltyPercent,
    this.overtimeCentsPerHour,
    this.publicText = const <String, String>{},
    this.includedServices = const <Map<String, dynamic>>[],
    this.paidExtras = const <Map<String, dynamic>>[],
    this.mobilisationDisclosure = const <String, String>{},
    this.customerObligations = const <String, String>{},
    this.importantInformation = const <String, String>{},
    this.unknownCriticalKeys = const <String>[],
  });

  final int? totalInclVatCents;
  final String currency;
  final String vatTreatment;
  final num? vatRate;
  final String expiresAt;
  final int? termsRevision;
  final int? cancellationDeadlineHours;
  final int? cancellationPenaltyPercent;
  final int? waitingTimeIncludedMinutes;
  final int? waitingTimeOverageCentsPerMinute;
  final int? noShowPenaltyPercent;
  final int? overtimeCentsPerHour;
  final Map<String, String> publicText;
  final List<Map<String, dynamic>> includedServices;
  final List<Map<String, dynamic>> paidExtras;
  final Map<String, String> mobilisationDisclosure;
  final Map<String, String> customerObligations;
  final Map<String, String> importantInformation;
  final List<String> unknownCriticalKeys;

  Map<String, dynamic> toWorkerQuote() {
    return <String, dynamic>{
      'total_incl_vat_cents': totalInclVatCents,
      'currency': limousineCurrencyOf(currency),
      'vat_treatment': vatTreatment.trim(),
      if (vatRate != null) 'vat_rate': vatRate,
      if (expiresAt.trim().isNotEmpty) 'expires_at': expiresAt.trim(),
      if (publicText.isNotEmpty) 'public_text': publicText,
      'terms': <String, dynamic>{
        'terms_revision': termsRevision,
        'cancellation_deadline_hours': cancellationDeadlineHours,
        'cancellation_penalty_percent': cancellationPenaltyPercent,
        'waiting_time_included_minutes': waitingTimeIncludedMinutes,
        'waiting_time_overage_cents_per_minute':
            waitingTimeOverageCentsPerMinute,
        'no_show_penalty_percent': noShowPenaltyPercent,
        'overtime_cents_per_hour': overtimeCentsPerHour,
        if (includedServices.isNotEmpty) 'included_services': includedServices,
        if (paidExtras.isNotEmpty) 'paid_extras': paidExtras,
        if (mobilisationDisclosure.isNotEmpty)
          'mobilisation_disclosure': mobilisationDisclosure,
        if (customerObligations.isNotEmpty)
          'customer_obligations': customerObligations,
        if (importantInformation.isNotEmpty)
          'important_information': importantInformation,
      },
    };
  }
}

class LimousineQuoteDraftValidation {
  const LimousineQuoteDraftValidation({
    required this.ok,
    this.missing = const <String>[],
    this.unknownCritical = const <String>[],
  });

  final bool ok;
  final List<String> missing;
  final List<String> unknownCritical;
}

LimousineQuoteDraftValidation validateLimousineCompanyQuoteDraft(
  LimousineCompanyQuoteDraft draft,
) {
  final missing = <String>[];
  if (draft.totalInclVatCents == null || draft.totalInclVatCents! <= 0) {
    missing.add('total_incl_vat_cents');
  }
  if (limousineCurrencyOf(draft.currency).isEmpty) {
    missing.add('currency');
  }
  if (draft.vatTreatment.trim().isEmpty) {
    missing.add('vat_treatment');
  }
  if (draft.expiresAt.trim().isEmpty ||
      DateTime.tryParse(draft.expiresAt.trim()) == null) {
    missing.add('expires_at');
  }
  if (draft.termsRevision == null || draft.termsRevision! <= 0) {
    missing.add('terms_revision');
  }
  void requireTerm(String key, int? value) {
    if (value == null || value < 0) missing.add(key);
  }

  requireTerm('cancellation_deadline_hours', draft.cancellationDeadlineHours);
  requireTerm('cancellation_penalty_percent', draft.cancellationPenaltyPercent);
  requireTerm(
    'waiting_time_included_minutes',
    draft.waitingTimeIncludedMinutes,
  );
  requireTerm(
    'waiting_time_overage_cents_per_minute',
    draft.waitingTimeOverageCentsPerMinute,
  );
  requireTerm('no_show_penalty_percent', draft.noShowPenaltyPercent);
  requireTerm('overtime_cents_per_hour', draft.overtimeCentsPerHour);
  final unknown = List<String>.from(draft.unknownCriticalKeys);
  return LimousineQuoteDraftValidation(
    ok: missing.isEmpty && unknown.isEmpty,
    missing: missing,
    unknownCritical: unknown,
  );
}

LimousineQuoteDraftValidation validateLimousineCompanyQuotePayload(
  Map<String, dynamic> raw,
) {
  final unknown = <String>[];
  raw.forEach((key, _) {
    if (!kLimousineKnownQuotePayloadKeys.contains(key)) {
      unknown.add(key);
    }
  });
  final terms = _asMap(raw['terms']);
  terms.forEach((key, _) {
    if (!kLimousineKnownTermsKeys.contains(key)) {
      unknown.add('terms.$key');
    }
  });
  final draft = LimousineCompanyQuoteDraft(
    totalInclVatCents: _intOf(raw['total_incl_vat_cents']),
    currency: _text(raw['currency'], max: 3),
    vatTreatment: _text(raw['vat_treatment'], max: 16),
    vatRate: raw['vat_rate'] is num ? raw['vat_rate'] as num : null,
    expiresAt: _text(raw['expires_at'], max: 40),
    termsRevision: _intOf(terms['terms_revision'] ?? raw['terms_revision']),
    cancellationDeadlineHours: _intOf(terms['cancellation_deadline_hours']),
    cancellationPenaltyPercent: _intOf(terms['cancellation_penalty_percent']),
    waitingTimeIncludedMinutes: _intOf(terms['waiting_time_included_minutes']),
    waitingTimeOverageCentsPerMinute: _intOf(
      terms['waiting_time_overage_cents_per_minute'],
    ),
    noShowPenaltyPercent: _intOf(terms['no_show_penalty_percent']),
    overtimeCentsPerHour: _intOf(terms['overtime_cents_per_hour']),
    unknownCriticalKeys: unknown,
  );
  return validateLimousineCompanyQuoteDraft(draft);
}

class LimousineDeclineDraft {
  const LimousineDeclineDraft({
    this.reasonCode = kLimousineDeclineReasonCompanyDeclined,
    this.publicText = const <String, String>{},
  });

  final String reasonCode;
  final Map<String, String> publicText;

  Map<String, dynamic> toWorkerBody() {
    final reason = _text(reasonCode, max: 64);
    return <String, dynamic>{
      'reason_code': reason.isEmpty
          ? kLimousineDeclineReasonCompanyDeclined
          : reason,
      if (publicText.isNotEmpty) 'public_text': publicText,
    };
  }
}

enum LimousineQuoteInboxErrorKind {
  session,
  gateOff,
  notFound,
  staleRevision,
  network,
  invalid,
  unknown,
}

class LimousineQuoteInboxException implements Exception {
  const LimousineQuoteInboxException({
    required this.kind,
    this.code = '',
    this.statusCode,
    this.currentRevision,
    this.missing = const <String>[],
  });

  final LimousineQuoteInboxErrorKind kind;
  final String code;
  final int? statusCode;
  final int? currentRevision;
  final List<String> missing;

  @override
  String toString() =>
      'LimousineQuoteInboxException(${kind.name}, code=$code, status=$statusCode)';
}

class LimousineQuoteRespondResult {
  const LimousineQuoteRespondResult({
    required this.record,
    this.stale = false,
    this.currentRevision,
  });

  final LimousineQuoteRequest? record;
  final bool stale;
  final int? currentRevision;
}
