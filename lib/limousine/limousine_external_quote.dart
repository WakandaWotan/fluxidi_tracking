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
const Key kLimousineExternalPaxKey = ValueKey<String>('limousine_external_pax');
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
const Key kLimousineExternalPreviewKey = ValueKey<String>(
  'limousine_external_preview',
);
const Key kLimousineExternalPreviewSendKey = ValueKey<String>(
  'limousine_external_preview_send',
);
const Key kLimousineExternalPreviewEditKey = ValueKey<String>(
  'limousine_external_preview_edit',
);
const Key kLimousineExternalPreviewDiscardKey = ValueKey<String>(
  'limousine_external_preview_discard',
);
const Key kLimousineExternalOriginBadgeKey = ValueKey<String>(
  'limousine_external_origin_badge',
);
const Key kLimousineExternalReturnWhenKey = ValueKey<String>(
  'limousine_external_return_when',
);
const Key kLimousineExternalExtrasKey = ValueKey<String>(
  'limousine_external_extras',
);
const Key kLimousineExternalPreviewMoneyKey = ValueKey<String>(
  'limousine_external_preview_money',
);
const Key kLimousineExternalPreviewVatKey = ValueKey<String>(
  'limousine_external_preview_vat',
);
const Key kLimousineExternalPreviewTotalKey = ValueKey<String>(
  'limousine_external_preview_total',
);

const int kLimousineOwnCustomerPaxMin = 1;
const int kLimousineOwnCustomerPaxMax = 16;
const int kLimousineOwnCustomerBagsMin = 0;
const int kLimousineOwnCustomerBagsMax = 99;

bool looksLikeOwnCustomerMail(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return false;
  final at = text.indexOf('@');
  if (at <= 0 || at != text.lastIndexOf('@')) return false;
  final host = text.substring(at + 1);
  return host.contains('.') && !text.contains(' ');
}

bool looksLikeOwnCustomerMobile(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length >= 8 && digits.length <= 15;
}

bool limousineOwnCustomerPaxOk(int? pax) {
  return pax != null &&
      pax >= kLimousineOwnCustomerPaxMin &&
      pax <= kLimousineOwnCustomerPaxMax;
}

bool limousineOwnCustomerBagsOk(int? bags) {
  return bags != null &&
      bags >= kLimousineOwnCustomerBagsMin &&
      bags <= kLimousineOwnCustomerBagsMax;
}

class LimousineOwnCustomerFormIssue {
  const LimousineOwnCustomerFormIssue({required this.ok, this.code = ''});

  final bool ok;
  final String code;
}

LimousineOwnCustomerFormIssue validateOwnCustomerContactForm({
  required String name,
  required String email,
  required String mobile,
}) {
  if (name.trim().isEmpty) {
    return const LimousineOwnCustomerFormIssue(ok: false, code: 'name');
  }
  final mail = email.trim();
  final phone = mobile.trim();
  if (mail.isEmpty && phone.isEmpty) {
    return const LimousineOwnCustomerFormIssue(ok: false, code: 'contact');
  }
  if (mail.isNotEmpty && !looksLikeOwnCustomerMail(mail)) {
    return const LimousineOwnCustomerFormIssue(ok: false, code: 'mail');
  }
  if (phone.isNotEmpty && !looksLikeOwnCustomerMobile(phone)) {
    return const LimousineOwnCustomerFormIssue(ok: false, code: 'mobile');
  }
  return const LimousineOwnCustomerFormIssue(ok: true);
}

LimousineOwnCustomerFormIssue validateOwnCustomerJourneyForm({
  required String from,
  required String to,
  required String offerId,
  required String vehicleId,
  required int? pax,
  required int? bags,
  required bool roundtrip,
  String returnPickupIso = '',
}) {
  if (from.trim().isEmpty) {
    return const LimousineOwnCustomerFormIssue(ok: false, code: 'from');
  }
  if (to.trim().isEmpty) {
    return const LimousineOwnCustomerFormIssue(ok: false, code: 'to');
  }
  if (offerId.trim().isEmpty) {
    return const LimousineOwnCustomerFormIssue(ok: false, code: 'offer');
  }
  if (vehicleId.trim().isEmpty) {
    return const LimousineOwnCustomerFormIssue(ok: false, code: 'vehicle');
  }
  if (!limousineOwnCustomerPaxOk(pax)) {
    return const LimousineOwnCustomerFormIssue(ok: false, code: 'pax');
  }
  if (!limousineOwnCustomerBagsOk(bags)) {
    return const LimousineOwnCustomerFormIssue(ok: false, code: 'bags');
  }
  if (roundtrip && returnPickupIso.trim().isEmpty) {
    return const LimousineOwnCustomerFormIssue(ok: false, code: 'return');
  }
  return const LimousineOwnCustomerFormIssue(ok: true);
}

String ownCustomerVatPercentLabel(num rate) {
  final pct = rate <= 1 ? rate * 100 : rate;
  if (pct == pct.roundToDouble()) return '${pct.toStringAsFixed(0)}%';
  return '$pct%';
}

class LimousineOwnCustomerPreviewMoney {
  const LimousineOwnCustomerPreviewMoney({
    required this.enteredCents,
    required this.netCents,
    required this.vatCents,
    required this.grossCents,
    required this.vatRate,
    required this.vatTreatment,
  });

  final int enteredCents;
  final int netCents;
  final int vatCents;
  final int grossCents;
  final num vatRate;
  final String vatTreatment;
}

/// Display-only preview. The Worker freezes the canonical split on send.
LimousineOwnCustomerPreviewMoney previewOwnCustomerQuoteMoney({
  required int enteredCents,
  required String vatTreatment,
  required num vatRate,
}) {
  final rate = vatRate <= 1 ? vatRate : vatRate / 100;
  final treatment = vatTreatment.trim().toLowerCase();
  if (treatment == 'none' || rate <= 0) {
    return LimousineOwnCustomerPreviewMoney(
      enteredCents: enteredCents,
      netCents: enteredCents,
      vatCents: 0,
      grossCents: enteredCents,
      vatRate: 0,
      vatTreatment: treatment.isEmpty ? 'none' : treatment,
    );
  }
  if (treatment == 'incl') {
    final net = (enteredCents / (1 + rate)).round();
    final vat = enteredCents - net;
    return LimousineOwnCustomerPreviewMoney(
      enteredCents: enteredCents,
      netCents: net,
      vatCents: vat,
      grossCents: enteredCents,
      vatRate: rate,
      vatTreatment: treatment,
    );
  }
  final vat = ((enteredCents / 100.0) * rate * 100).round();
  return LimousineOwnCustomerPreviewMoney(
    enteredCents: enteredCents,
    netCents: enteredCents,
    vatCents: vat,
    grossCents: enteredCents + vat,
    vatRate: rate,
    vatTreatment: 'excl',
  );
}

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

  bool get hasContact =>
      displayName.isNotEmpty || mail.isNotEmpty || mobile.isNotEmpty;

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
      companyLabel: _text(map['company_label'] ?? map['company_name'], 80),
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
    this.serviceClassId = '',
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
  final String serviceClassId;
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
      if (serviceClassId.trim().isNotEmpty)
        'service_class_id': serviceClassId.trim(),
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
