// P3P — company-side external customer quotation models.
// Contact PII stays off the public quote projection and off quote hashes.

import 'package:flutter/foundation.dart';

import 'limousine_quote_inbox.dart';

const String kLimousineExternalOriginChannel = 'company_external';

const Key kLimousineExternalQuoteCreateActionKey = ValueKey<String>(
  'limousine_external_quote_create',
);
const Key kLimousineExternalQuotePageKey = ValueKey<String>(
  'limousine_external_quote_page',
);
const Key kLimousineExternalContactNameKey = ValueKey<String>(
  'limousine_external_contact_name',
);
const Key kLimousineExternalContactEmailKey = ValueKey<String>(
  'limousine_external_contact_email',
);
const Key kLimousineExternalContactMobileKey = ValueKey<String>(
  'limousine_external_contact_mobile',
);
const Key kLimousineExternalContactLocaleKey = ValueKey<String>(
  'limousine_external_contact_locale',
);
const Key kLimousineExternalContactCompanyKey = ValueKey<String>(
  'limousine_external_contact_company',
);
const Key kLimousineExternalPickupKey = ValueKey<String>(
  'limousine_external_pickup',
);
const Key kLimousineExternalDestinationKey = ValueKey<String>(
  'limousine_external_destination',
);
const Key kLimousineExternalStopsKey = ValueKey<String>(
  'limousine_external_stops',
);
const Key kLimousineExternalWhenKey = ValueKey<String>(
  'limousine_external_when',
);
const Key kLimousineExternalReturnKey = ValueKey<String>(
  'limousine_external_return',
);
const Key kLimousineExternalPaxKey = ValueKey<String>(
  'limousine_external_pax',
);
const Key kLimousineExternalBagsKey = ValueKey<String>(
  'limousine_external_bags',
);
const Key kLimousineExternalOccasionKey = ValueKey<String>(
  'limousine_external_occasion',
);
const Key kLimousineExternalVehicleKey = ValueKey<String>(
  'limousine_external_vehicle',
);
const Key kLimousineExternalOfferKey = ValueKey<String>(
  'limousine_external_offer',
);
const Key kLimousineExternalCopyLinkKey = ValueKey<String>(
  'limousine_external_copy_link',
);
const Key kLimousineExternalShareLinkKey = ValueKey<String>(
  'limousine_external_share_link',
);
const Key kLimousineExternalTimelineKey = ValueKey<String>(
  'limousine_external_timeline',
);
const Key kLimousineExternalContactSummaryKey = ValueKey<String>(
  'limousine_external_contact_summary',
);
const Key kLimousineExternalSubmitKey = ValueKey<String>(
  'limousine_external_submit',
);

class LimousineExternalContactSummary {
  const LimousineExternalContactSummary({
    this.displayName = '',
    this.mail = '',
    this.mobile = '',
    this.locale = 'nl',
    this.companyLabel = '',
  });

  final String displayName;
  final String mail;
  final String mobile;
  final String locale;
  final String companyLabel;

  bool get hasContact => displayName.isNotEmpty || mail.isNotEmpty || mobile.isNotEmpty;

  Map<String, dynamic> toWorkerContact() {
    return <String, dynamic>{
      'name': displayName.trim(),
      if (mail.trim().isNotEmpty) 'email': mail.trim(),
      if (mobile.trim().isNotEmpty) 'phone': mobile.trim(),
      'locale': normalizeLimousineQuoteLocale(locale),
      if (companyLabel.trim().isNotEmpty) 'company_name': companyLabel.trim(),
    };
  }

  factory LimousineExternalContactSummary.fromJson(Object? raw) {
    if (raw is! Map) return const LimousineExternalContactSummary();
    final map = Map<String, dynamic>.from(raw);
    return LimousineExternalContactSummary(
      displayName: _text(
        map['display_name'] ?? map['name'] ?? map['customer_name'],
        80,
      ),
      mail: _text(map['mail'] ?? map['email'], 160),
      mobile: _text(map['mobile'] ?? map['phone'], 32),
      locale: normalizeLimousineQuoteLocale('${map['locale'] ?? 'nl'}'),
      companyLabel: _text(
        map['company_label'] ?? map['company_name'],
        80,
      ),
    );
  }
}

class LimousineExternalQuoteCreateResult {
  const LimousineExternalQuoteCreateResult({
    required this.record,
    this.invitationUrl = '',
    this.contact = const LimousineExternalContactSummary(),
    this.idempotent = false,
  });

  final LimousineQuoteRequest record;
  final String invitationUrl;
  final LimousineExternalContactSummary contact;
  final bool idempotent;
}

class LimousineExternalInvitationResult {
  const LimousineExternalInvitationResult({
    required this.record,
    this.invitationUrl = '',
  });

  final LimousineQuoteRequest record;
  final String invitationUrl;
}

class LimousineExternalJourneyDraft {
  const LimousineExternalJourneyDraft({
    this.offerId = '',
    this.vehicleId = '',
    this.journeyType = 'point_to_point',
    this.from = '',
    this.to = '',
    this.stops = const <String>[],
    this.scheduledPickupIso = '',
    this.roundtrip = false,
    this.returnPickupIso = '',
    this.pax,
    this.bags,
    this.occasion = '',
    this.selectedExtraIds = const <String>[],
    this.locale = 'nl',
  });

  final String offerId;
  final String vehicleId;
  final String journeyType;
  final String from;
  final String to;
  final List<String> stops;
  final String scheduledPickupIso;
  final bool roundtrip;
  final String returnPickupIso;
  final int? pax;
  final int? bags;
  final String occasion;
  final List<String> selectedExtraIds;
  final String locale;

  Map<String, dynamic> toWorkerRequest() {
    return <String, dynamic>{
      'offer_id': offerId.trim(),
      if (vehicleId.trim().isNotEmpty) 'vehicle_id': vehicleId.trim(),
      'journey_type': journeyType.trim(),
      'from': from.trim(),
      'to': to.trim(),
      if (stops.isNotEmpty)
        'stops': stops
            .map((stop) => stop.trim())
            .where((stop) => stop.isNotEmpty)
            .take(8)
            .toList(growable: false),
      'scheduled_pickup_iso': scheduledPickupIso.trim(),
      if (roundtrip) 'roundtrip': true,
      if (roundtrip && returnPickupIso.trim().isNotEmpty)
        'return_pickup_iso': returnPickupIso.trim(),
      if (pax != null) 'pax': pax,
      if (bags != null) 'bags': bags,
      if (occasion.trim().isNotEmpty) 'occasion': occasion.trim(),
      if (selectedExtraIds.isNotEmpty) 'selected_extra_ids': selectedExtraIds,
      'locale': normalizeLimousineQuoteLocale(locale),
    };
  }
}

bool limousineQuoteIsExternal(LimousineQuoteRequest record) {
  return record.originChannel == kLimousineExternalOriginChannel ||
      record.externalDelivery.isExternal;
}

String _text(Object? raw, int max) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty) return '';
  return value.length <= max ? value : value.substring(0, max);
}

