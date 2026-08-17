import 'package:fluxidi_tracking/app_config.dart';

import 'ratehawk_hotelpage.dart';
import 'ratehawk_search.dart';

const String kRatehawkPrebookRefPrefix = 'rhp1';
const String kRatehawkAcceptedRefPrefix = 'rha1';

enum RatehawkPrebookLifecycleState {
  idle,
  checking,
  readyUnchanged,
  readyChanged,
  blocked,
  retryable,
  accepted,
}

class RatehawkPrebookChange {
  const RatehawkPrebookChange({
    required this.code,
    this.label,
    this.before,
    this.after,
  });

  final String code;
  final String? label;
  final String? before;
  final String? after;
}

class RatehawkPrebookDisputeSnapshot {
  const RatehawkPrebookDisputeSnapshot({
    this.ok = false,
    this.hid,
    this.roomName,
    this.mealPlan,
    this.customerTotalLabel,
    this.currency,
    this.locale,
    this.termsRevision,
    this.acceptedAt,
    this.changeCodes = const <String>[],
    this.omitted = const <String>[],
  });

  final bool ok;
  final int? hid;
  final String? roomName;
  final String? mealPlan;
  final String? customerTotalLabel;
  final String? currency;
  final String? locale;
  final String? termsRevision;
  final DateTime? acceptedAt;
  final List<String> changeCodes;
  final List<String> omitted;
}

class RatehawkPrebookResponse {
  const RatehawkPrebookResponse({
    this.ok = false,
    this.invoked = false,
    this.reason,
    this.retryable = false,
    this.progressBlocked = true,
    this.acceptanceAllowed = false,
    this.accepted = false,
    this.changed = false,
    this.changes = const <RatehawkPrebookChange>[],
    this.currentTerms,
    this.prebookRef,
    this.acceptedRef,
    this.termsRevision,
    this.disputeSnapshot,
    this.existingActions = const <String>[],
    this.stay22FallbackRetained = true,
    this.mobilityIndependent = true,
    this.malformed = false,
    this.timedOut = false,
  });

  final bool ok;
  final bool invoked;
  final String? reason;
  final bool retryable;
  final bool progressBlocked;
  final bool acceptanceAllowed;
  final bool accepted;
  final bool changed;
  final List<RatehawkPrebookChange> changes;
  final RatehawkHotelpageOffer? currentTerms;
  final String? prebookRef;
  final String? acceptedRef;
  final String? termsRevision;
  final RatehawkPrebookDisputeSnapshot? disputeSnapshot;
  final List<String> existingActions;
  final bool stay22FallbackRetained;
  final bool mobilityIndependent;
  final bool malformed;
  final bool timedOut;
}

abstract class RatehawkPrebookClient {
  Future<RatehawkPrebookResponse> check({
    required String offerRef,
    required String locale,
  });

  Future<RatehawkPrebookResponse> accept({
    required String prebookRef,
    required String locale,
    String? termsRevision,
  });
}

class BookingRatehawkPrebookClient implements RatehawkPrebookClient {
  const BookingRatehawkPrebookClient();

  @override
  Future<RatehawkPrebookResponse> check({
    required String offerRef,
    required String locale,
  }) async {
    try {
      final payload = await fetchPublicRatehawkPrebook(
        offerRef: offerRef,
        locale: locale,
      );
      if (payload == null) {
        return const RatehawkPrebookResponse(
          timedOut: true,
          retryable: true,
          reason: 'backend_unavailable',
        );
      }
      return parseRatehawkPrebookPayload(payload);
    } catch (_) {
      return const RatehawkPrebookResponse(
        malformed: true,
        retryable: true,
        reason: 'backend_error',
      );
    }
  }

  @override
  Future<RatehawkPrebookResponse> accept({
    required String prebookRef,
    required String locale,
    String? termsRevision,
  }) async {
    try {
      final payload = await fetchPublicRatehawkPrebookAccept(
        prebookRef: prebookRef,
        locale: locale,
        termsRevision: termsRevision,
      );
      if (payload == null) {
        return const RatehawkPrebookResponse(
          timedOut: true,
          retryable: true,
          reason: 'backend_unavailable',
        );
      }
      return parseRatehawkPrebookPayload(payload);
    } catch (_) {
      return const RatehawkPrebookResponse(
        malformed: true,
        retryable: true,
        reason: 'backend_error',
      );
    }
  }
}

class RecordingRatehawkPrebookClient implements RatehawkPrebookClient {
  RecordingRatehawkPrebookClient({this.checkResponse, this.acceptResponse});

  RatehawkPrebookResponse? checkResponse;
  RatehawkPrebookResponse? acceptResponse;
  final List<Map<String, String>> checkCalls = <Map<String, String>>[];
  final List<Map<String, String>> acceptCalls = <Map<String, String>>[];

  @override
  Future<RatehawkPrebookResponse> check({
    required String offerRef,
    required String locale,
  }) async {
    checkCalls.add(<String, String>{'offer_ref': offerRef, 'locale': locale});
    return checkResponse ??
        const RatehawkPrebookResponse(
          retryable: true,
          reason: 'ratehawk_prebook_disabled',
        );
  }

  @override
  Future<RatehawkPrebookResponse> accept({
    required String prebookRef,
    required String locale,
    String? termsRevision,
  }) async {
    acceptCalls.add(<String, String>{
      'prebook_ref': prebookRef,
      'locale': locale,
      'terms_revision': termsRevision ?? '',
    });
    return acceptResponse ??
        const RatehawkPrebookResponse(
          retryable: true,
          reason: 'ratehawk_prebook_disabled',
        );
  }
}

class RatehawkPrebookController {
  RatehawkPrebookController({
    RatehawkPrebookClient? client,
    this.reduceMotion = false,
  }) : client = client ?? const BookingRatehawkPrebookClient();

  final RatehawkPrebookClient client;
  final bool reduceMotion;

  RatehawkPrebookLifecycleState state = RatehawkPrebookLifecycleState.idle;
  RatehawkPrebookResponse? response;
  String? reason;
  int requestCount = 0;
  int _generation = 0;
  final List<void Function()> _listeners = <void Function()>[];

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);
  void dispose() => _listeners.clear();

  void _notify() {
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
  }

  void cancel() {
    _generation += 1;
    if (state == RatehawkPrebookLifecycleState.checking) {
      state = RatehawkPrebookLifecycleState.idle;
      reason = 'cancelled';
      _notify();
    }
  }

  Future<void> check({required String offerRef, required String locale}) async {
    if (!isRatehawkOfferRef(offerRef)) {
      state = RatehawkPrebookLifecycleState.blocked;
      reason = 'offer_ref_invalid';
      response = null;
      _notify();
      return;
    }
    final generation = ++_generation;
    requestCount += 1;
    state = RatehawkPrebookLifecycleState.checking;
    reason = null;
    _notify();
    final next = await client.check(offerRef: offerRef, locale: locale);
    if (generation != _generation) return;
    _apply(next);
  }

  Future<void> accept({required String locale}) async {
    final current = response;
    final prebookRef = current?.prebookRef;
    if (current == null ||
        current.acceptanceAllowed != true ||
        !isRatehawkPrebookRef(prebookRef)) {
      state = RatehawkPrebookLifecycleState.blocked;
      reason = 'prebook_ref_invalid';
      _notify();
      return;
    }
    final generation = ++_generation;
    requestCount += 1;
    state = RatehawkPrebookLifecycleState.checking;
    reason = null;
    _notify();
    final next = await client.accept(
      prebookRef: prebookRef!,
      locale: locale,
      termsRevision: current.termsRevision,
    );
    if (generation != _generation) return;
    _apply(next);
  }

  void _apply(RatehawkPrebookResponse next) {
    response = next;
    reason = next.reason;
    if (next.timedOut || next.malformed || next.retryable) {
      state = RatehawkPrebookLifecycleState.retryable;
      _notify();
      return;
    }
    if (next.accepted == true && isRatehawkAcceptedRef(next.acceptedRef)) {
      state = RatehawkPrebookLifecycleState.accepted;
      _notify();
      return;
    }
    if (next.progressBlocked == true || next.acceptanceAllowed != true) {
      state = RatehawkPrebookLifecycleState.blocked;
      _notify();
      return;
    }
    state = next.changed
        ? RatehawkPrebookLifecycleState.readyChanged
        : RatehawkPrebookLifecycleState.readyUnchanged;
    _notify();
  }
}

bool isRatehawkPrebookRef(String? raw) {
  final token = (raw ?? '').trim();
  return token.startsWith('$kRatehawkPrebookRefPrefix.') &&
      token.split('.').length >= 3;
}

bool isRatehawkAcceptedRef(String? raw) {
  final token = (raw ?? '').trim();
  return token.startsWith('$kRatehawkAcceptedRefPrefix.') &&
      token.split('.').length >= 3;
}

RatehawkPrebookResponse parseRatehawkPrebookPayload(
  Map<String, dynamic> payload,
) {
  if (ratehawkPayloadContainsForbiddenClientFields(payload)) {
    return const RatehawkPrebookResponse(
      malformed: true,
      reason: 'forbidden_provider_fields',
    );
  }
  final reason = payload['reason']?.toString();
  final retryable = payload['retryable'] == true;
  final accepted = payload['accepted'] == true;
  final progressBlocked = payload['progress_blocked'] == true;
  final acceptanceAllowed = payload['acceptance_allowed'] == true;
  final changed = payload['changed'] == true;
  RatehawkHotelpageOffer? currentTerms;
  final rawTerms = payload['current_terms'];
  if (rawTerms is Map) {
    currentTerms = parseRatehawkHotelpageOffer(
      Map<String, dynamic>.from(rawTerms),
    );
  }
  return RatehawkPrebookResponse(
    ok: payload['ok'] == true,
    invoked: payload['invoked'] == true,
    reason: reason,
    retryable: retryable,
    progressBlocked: progressBlocked,
    acceptanceAllowed: acceptanceAllowed,
    accepted: accepted,
    changed: changed,
    changes: _changes(payload['changes']),
    currentTerms: currentTerms,
    prebookRef: _ref(payload['prebook_ref'], isRatehawkPrebookRef),
    acceptedRef: _ref(payload['accepted_ref'], isRatehawkAcceptedRef),
    termsRevision: _text(payload['terms_revision']),
    disputeSnapshot: _dispute(payload['dispute_snapshot']),
    existingActions: _stringList(payload['existing_actions']),
    stay22FallbackRetained: payload['stay22_fallback_retained'] != false,
    mobilityIndependent: payload['mobility_independent_of_ratehawk'] != false,
  );
}

List<RatehawkPrebookChange> _changes(dynamic raw) {
  if (raw is! List) return const <RatehawkPrebookChange>[];
  final out = <RatehawkPrebookChange>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final code = item['code']?.toString().trim() ?? '';
    if (code.isEmpty) continue;
    out.add(
      RatehawkPrebookChange(
        code: code,
        label: _text(item['label']),
        before: _display(item['before']),
        after: _display(item['after']),
      ),
    );
  }
  return out;
}

RatehawkPrebookDisputeSnapshot? _dispute(dynamic raw) {
  if (raw is! Map) return null;
  final json = Map<String, dynamic>.from(raw);
  if (ratehawkPayloadContainsForbiddenClientFields(json)) return null;
  final total = json['customer_total'];
  return RatehawkPrebookDisputeSnapshot(
    ok: json['ok'] == true,
    hid: int.tryParse('${json['hid'] ?? ''}'),
    roomName: _text(json['room_name']),
    mealPlan: _text(json['meal_plan']),
    customerTotalLabel: total is Map
        ? _text(total['label'])
        : _text(json['customer_total']),
    currency: total is Map ? _text(total['currency']) : _text(json['currency']),
    locale: _text(json['locale']),
    termsRevision: _text(json['terms_revision']),
    acceptedAt: _date(json['accepted_at']),
    changeCodes: _stringList(
      json['prebook_changes'] is List
          ? (json['prebook_changes'] as List)
                .whereType<Map>()
                .map((row) => row['code'])
                .toList()
          : json['change_codes'],
    ),
    omitted: _stringList(json['omitted']),
  );
}

String? _ref(dynamic raw, bool Function(String?) ok) {
  final value = _text(raw);
  return ok(value) ? value : null;
}

String? _text(dynamic raw) {
  if (raw == null) return null;
  final text = raw.toString().trim();
  return text.isEmpty ? null : text;
}

String? _display(dynamic raw) {
  if (raw == null) return null;
  if (raw is String || raw is num || raw is bool) return raw.toString();
  return raw.toString();
}

DateTime? _date(dynamic raw) {
  if (raw is num && raw.isFinite) {
    return DateTime.fromMillisecondsSinceEpoch(raw.round());
  }
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const <String>[];
  return raw
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String ratehawkPrebookCheckLabel(String languageCode) {
  return ratehawkSearchLabel(
    languageCode,
    nl: 'Prijs en voorwaarden controleren',
    en: 'Check price and conditions',
    fr: 'Vérifier le prix et les conditions',
    es: 'Comprobar precio y condiciones',
  );
}

String ratehawkPrebookConfirmLabel(String languageCode) {
  return ratehawkSearchLabel(
    languageCode,
    nl: 'Voorwaarden bevestigen',
    en: 'Confirm these terms',
    fr: 'Confirmer ces conditions',
    es: 'Confirmar estas condiciones',
  );
}

String ratehawkPrebookAcceptChangesLabel(String languageCode) {
  return ratehawkSearchLabel(
    languageCode,
    nl: 'Gewijzigde voorwaarden accepteren',
    en: 'Accept changed terms',
    fr: 'Accepter les conditions modifiées',
    es: 'Aceptar las condiciones modificadas',
  );
}

String ratehawkPrebookRefreshLabel(String languageCode) {
  return ratehawkSearchLabel(
    languageCode,
    nl: 'Beschikbaarheid vernieuwen',
    en: 'Refresh availability',
    fr: 'Actualiser la disponibilité',
    es: 'Actualizar disponibilidad',
  );
}

String ratehawkPrebookOtherRoomsLabel(String languageCode) {
  return ratehawkSearchLabel(
    languageCode,
    nl: 'Andere kamers',
    en: 'Other rooms',
    fr: 'Autres chambres',
    es: 'Otras habitaciones',
  );
}

String ratehawkPrebookCancelLabel(String languageCode) {
  return ratehawkSearchLabel(
    languageCode,
    nl: 'Annuleren',
    en: 'Cancel',
    fr: 'Annuler',
    es: 'Cancelar',
  );
}

String ratehawkPrebookAcceptedLabel(String languageCode) {
  return ratehawkSearchLabel(
    languageCode,
    nl: 'Voorwaarden geaccepteerd. Boeken volgt in een latere stap.',
    en: 'Terms accepted. Booking follows in a later step.',
    fr: 'Conditions acceptées. La réservation suivra plus tard.',
    es: 'Condiciones aceptadas. La reserva sigue en un paso posterior.',
  );
}

String ratehawkPrebookBlockedLabel(String languageCode) {
  return ratehawkSearchLabel(
    languageCode,
    nl: 'Deze aanbieding is niet meer boekbaar.',
    en: 'This offer is no longer bookable.',
    fr: 'Cette offre n’est plus réservable.',
    es: 'Esta oferta ya no se puede reservar.',
  );
}

String ratehawkPrebookStateLabel(
  RatehawkPrebookLifecycleState state,
  String languageCode,
) {
  switch (state) {
    case RatehawkPrebookLifecycleState.idle:
      return ratehawkPrebookCheckLabel(languageCode);
    case RatehawkPrebookLifecycleState.checking:
      return ratehawkSearchLabel(
        languageCode,
        nl: 'Prijs en voorwaarden controleren',
        en: 'Checking price and conditions',
        fr: 'Vérification du prix et des conditions',
        es: 'Comprobando precio y condiciones',
      );
    case RatehawkPrebookLifecycleState.readyUnchanged:
      return ratehawkSearchLabel(
        languageCode,
        nl: 'Huidige voorwaarden ongewijzigd',
        en: 'Current terms unchanged',
        fr: 'Conditions actuelles inchangées',
        es: 'Condiciones actuales sin cambios',
      );
    case RatehawkPrebookLifecycleState.readyChanged:
      return ratehawkSearchLabel(
        languageCode,
        nl: 'Gewijzigde voorwaarden — nieuwe bevestiging vereist',
        en: 'Changed terms — renewed confirmation required',
        fr: 'Conditions modifiées — nouvelle confirmation requise',
        es: 'Condiciones modificadas — se requiere nueva confirmación',
      );
    case RatehawkPrebookLifecycleState.blocked:
      return ratehawkPrebookBlockedLabel(languageCode);
    case RatehawkPrebookLifecycleState.retryable:
      return ratehawkRetryLabel(languageCode);
    case RatehawkPrebookLifecycleState.accepted:
      return ratehawkPrebookAcceptedLabel(languageCode);
  }
}
