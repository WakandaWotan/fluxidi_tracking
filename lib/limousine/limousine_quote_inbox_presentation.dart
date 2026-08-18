// LIMOUSINE-MARKETPLACE-P2D4C1B — inbox presentation helpers.
// Counts, search and card actions stay derived from loaded DTOs. No second
// quote engine and no client price authority.

import '../app_config.dart';
import '../app_strings.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_quote_inbox_labels.dart';

enum LimousineQuoteInboxKpiCode { neu, toAnswer, waitingCustomer, accepted }

enum LimousineQuoteInboxCardAction {
  view,
  createQuote,
  editQuote,
  viewQuote,
  openAcceptedHandoff,
  viewBooking,
  close,
}

class LimousineQuoteInboxKpis {
  const LimousineQuoteInboxKpis({
    required this.neu,
    required this.toAnswer,
    required this.waitingCustomer,
    required this.accepted,
  });

  final int neu;
  final int toAnswer;
  final int waitingCustomer;
  final int accepted;

  int of(LimousineQuoteInboxKpiCode code) {
    switch (code) {
      case LimousineQuoteInboxKpiCode.neu:
        return neu;
      case LimousineQuoteInboxKpiCode.toAnswer:
        return toAnswer;
      case LimousineQuoteInboxKpiCode.waitingCustomer:
        return waitingCustomer;
      case LimousineQuoteInboxKpiCode.accepted:
        return accepted;
    }
  }
}

const List<LimousineQuoteInboxFilter> kLimousineQuoteInboxPrimaryFilters =
    <LimousineQuoteInboxFilter>[
      LimousineQuoteInboxFilter.all,
      LimousineQuoteInboxFilter.requested,
      LimousineQuoteInboxFilter.viewed,
      LimousineQuoteInboxFilter.waitingForCustomer,
      LimousineQuoteInboxFilter.accepted,
    ];

const List<LimousineQuoteInboxFilter> kLimousineQuoteInboxOverflowFilters =
    <LimousineQuoteInboxFilter>[
      LimousineQuoteInboxFilter.completed,
      LimousineQuoteInboxFilter.closed,
    ];

LimousineQuoteInboxKpis limousineQuoteInboxKpis(
  Iterable<LimousineQuoteRequest> records,
) {
  var neu = 0;
  var toAnswer = 0;
  var waitingCustomer = 0;
  var accepted = 0;
  for (final record in records) {
    final state = LimousineQuoteStateId.normalize(record.state);
    if (state == LimousineQuoteStateId.requested) {
      neu += 1;
      toAnswer += 1;
    } else if (state == LimousineQuoteStateId.viewedByCompany) {
      toAnswer += 1;
    } else if (LimousineQuoteStateId.waitingForCustomer.contains(state)) {
      waitingCustomer += 1;
    } else if (state == LimousineQuoteStateId.accepted) {
      accepted += 1;
    }
  }
  return LimousineQuoteInboxKpis(
    neu: neu,
    toAnswer: toAnswer,
    waitingCustomer: waitingCustomer,
    accepted: accepted,
  );
}

int? limousineQuoteInboxUnreadBadge(Iterable<LimousineQuoteRequest> records) {
  final count = records.where((record) => record.isUnread).length;
  return count > 0 ? count : null;
}

bool limousineQuoteInboxMatchesQuery(
  LimousineQuoteRequest record,
  String rawQuery, {
  AppLanguage language = AppLanguage.nl,
}) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return true;
  final fulfilment = record.fulfilment;
  final haystack = <String>[
    record.quoteRequestId,
    record.offerId,
    record.serviceClassId,
    record.vehicleId,
    record.bookingReference,
    record.journeyType,
    kLimousineJourneyTypeLabels[record.journeyType]?.of(language) ?? '',
    limousineServiceClassLabel(record.serviceClassId, language),
    fulfilment?.from ?? '',
    fulfilment?.to ?? '',
    ...?fulfilment?.stops,
    fulfilment?.customerNote ?? '',
  ];
  return haystack.any((value) => value.toLowerCase().contains(query));
}

List<LimousineQuoteRequest> limousineQuoteInboxSearch(
  Iterable<LimousineQuoteRequest> records,
  String query, {
  AppLanguage language = AppLanguage.nl,
}) {
  return records
      .where(
        (record) =>
            limousineQuoteInboxMatchesQuery(record, query, language: language),
      )
      .toList(growable: false);
}

List<LimousineQuoteInboxCardAction> limousineQuoteInboxCardActions(
  LimousineQuoteRequest record, {
  bool gateOff = false,
}) {
  final state = LimousineQuoteStateId.normalize(record.state);
  final actions = limousineQuoteActionsFor(record, gateOff: gateOff);
  final out = <LimousineQuoteInboxCardAction>[];
  if (actions.canQuote && record.quote == null) {
    out.add(LimousineQuoteInboxCardAction.createQuote);
  }
  if (actions.canQuote && record.quote != null) {
    out.add(LimousineQuoteInboxCardAction.editQuote);
  }
  if (record.quote != null &&
      LimousineQuoteStateId.waitingForCustomer.contains(state)) {
    out.add(LimousineQuoteInboxCardAction.viewQuote);
  }
  if (state == LimousineQuoteStateId.accepted) {
    out.add(LimousineQuoteInboxCardAction.openAcceptedHandoff);
  }
  if (state == LimousineQuoteStateId.bookingCreated) {
    out.add(LimousineQuoteInboxCardAction.viewBooking);
  }
  out.add(LimousineQuoteInboxCardAction.view);
  if (actions.canDecline && !actions.canQuote) {
    out.add(LimousineQuoteInboxCardAction.close);
  }
  return out;
}

String limousineQuoteInboxStatusLabel(
  LimousineQuoteRequest record,
  AppLanguage language,
) {
  if (record.isUnknownState) {
    return kLimousineQuoteUnknownState.of(language);
  }
  final state = LimousineQuoteStateId.normalize(record.state);
  final mapped = kLimousineQuoteInboxStatusLabels[state];
  if (mapped != null) return mapped.of(language);
  return limousineQuoteStateLabel(state, language);
}

String limousineQuoteInboxCardTitle(
  LimousineQuoteRequest record,
  AppLanguage language,
) {
  final journey = kLimousineJourneyTypeLabels[record.journeyType]?.of(language);
  final destination = record.fulfilment?.to.trim() ?? '';
  if (journey != null && journey.isNotEmpty && destination.isNotEmpty) {
    return '$journey · $destination';
  }
  if (journey != null && journey.isNotEmpty) return journey;
  if (destination.isNotEmpty) return destination;
  final origin = record.fulfilment?.from.trim() ?? '';
  if (origin.isNotEmpty) return origin;
  return kLimousineQuoteInboxRequestFallback.of(language);
}

String limousineQuoteInboxRouteSummary(LimousineQuoteRequest record) {
  final fulfilment = record.fulfilment;
  if (fulfilment == null || !fulfilment.hasJourney) return '';
  final parts = <String>[
    if (fulfilment.from.isNotEmpty) fulfilment.from,
    if (fulfilment.to.isNotEmpty) fulfilment.to,
  ];
  return parts.join(' · ');
}

String limousineQuoteInboxPublicReference(LimousineQuoteRequest record) {
  return record.quoteRequestId;
}

String? limousineQuoteInboxAuthoritativeAmount(
  LimousineQuoteRequest record,
  AppLanguage language,
) {
  final quote = record.quote;
  if (quote == null) return null;
  final money = formatLimousineMoney(quote.totalInclVatCents, quote.currency);
  final state = LimousineQuoteStateId.normalize(record.state);
  final suffix =
      state == LimousineQuoteStateId.accepted ||
          state == LimousineQuoteStateId.bookingCreated
      ? kLimousineQuoteInboxAmountAccepted.of(language)
      : kLimousineQuoteInboxAmountOffered.of(language);
  return '$money $suffix';
}

double limousineQuoteInboxContentWidth(double viewportWidth) {
  if (viewportWidth >= 700) {
    return viewportWidth < 1080 ? viewportWidth : 1080;
  }
  return viewportWidth;
}

bool limousineQuoteInboxLooksRawBackend(String text) {
  final lower = text.toLowerCase();
  return lower.contains('exception') ||
      lower.contains('404') ||
      lower.contains('not_found') ||
      LimousineQuoteStateId.known.any((state) => text == state);
}

LocalizedText limousineQuoteInboxActionLabel(
  LimousineQuoteInboxCardAction action,
) {
  switch (action) {
    case LimousineQuoteInboxCardAction.view:
      return kLimousineQuoteInboxView;
    case LimousineQuoteInboxCardAction.createQuote:
      return kLimousineQuoteInboxCreateQuote;
    case LimousineQuoteInboxCardAction.editQuote:
      return kLimousineQuoteInboxEditQuote;
    case LimousineQuoteInboxCardAction.viewQuote:
      return kLimousineQuoteInboxViewQuote;
    case LimousineQuoteInboxCardAction.openAcceptedHandoff:
      return kLimousineQuoteInboxOpenHandoff;
    case LimousineQuoteInboxCardAction.viewBooking:
      return kLimousineQuoteInboxViewBooking;
    case LimousineQuoteInboxCardAction.close:
      return kLimousineQuoteInboxClose;
  }
}

LocalizedText limousineQuoteInboxKpiLabel(LimousineQuoteInboxKpiCode code) {
  switch (code) {
    case LimousineQuoteInboxKpiCode.neu:
      return kLimousineQuoteInboxKpiNew;
    case LimousineQuoteInboxKpiCode.toAnswer:
      return kLimousineQuoteInboxKpiToAnswer;
    case LimousineQuoteInboxKpiCode.waitingCustomer:
      return kLimousineQuoteInboxKpiWaiting;
    case LimousineQuoteInboxKpiCode.accepted:
      return kLimousineQuoteInboxKpiAccepted;
  }
}

LocalizedText limousineQuoteInboxKpiHint(LimousineQuoteInboxKpiCode code) {
  switch (code) {
    case LimousineQuoteInboxKpiCode.neu:
      return kLimousineQuoteInboxKpiNewHint;
    case LimousineQuoteInboxKpiCode.toAnswer:
      return kLimousineQuoteInboxKpiToAnswerHint;
    case LimousineQuoteInboxKpiCode.waitingCustomer:
      return kLimousineQuoteInboxKpiWaitingHint;
    case LimousineQuoteInboxKpiCode.accepted:
      return kLimousineQuoteInboxKpiAcceptedHint;
  }
}

bool limousineQuoteInboxUsesPaletteTokens(String source) {
  return source.contains('paletteForBusinessTheme') &&
      source.contains('BusinessThemePalette') &&
      !source.contains('Color(0xFFC49A45)') &&
      !source.contains('Color(0xFFD4AF37)');
}
