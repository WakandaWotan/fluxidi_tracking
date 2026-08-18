import 'package:flutter/material.dart';

import '../app_strings.dart';
import '../customer_theme_palette.dart';
import 'limousine_accepted_booking.dart';
import 'limousine_accepted_booking_labels.dart';
import 'limousine_accepted_booking_page.dart';
import 'limousine_accepted_booking_resume_labels.dart';
import 'limousine_customer_quote.dart';
import 'limousine_customer_quote_api.dart';
import 'limousine_customer_quote_labels.dart';
import 'limousine_p2d4c1a_ux.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_quote_inbox_labels.dart';

class LimousineCustomerUnavailableBanner extends StatelessWidget {
  const LimousineCustomerUnavailableBanner({super.key, required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: kLimousineCustomerUnavailableKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(kLimousineGatesOffFriendly.of(language)),
      ),
    );
  }
}

class LimousineCustomerStatusView extends StatelessWidget {
  const LimousineCustomerStatusView({
    super.key,
    required this.controller,
    required this.language,
    required this.palette,
    this.onOpenBookingReview,
  });

  final LimousineCustomerQuoteController controller;
  final AppLanguage language;
  final CustomerThemePalette palette;
  final VoidCallback? onOpenBookingReview;

  String _t(LocalizedText text) => text.of(language);

  @override
  Widget build(BuildContext context) {
    final request = controller.request;
    if (request == null) {
      return LimousineCustomerUnavailableBanner(language: language);
    }
    final quote = request.quote;
    return Column(
      key: kLimousineCustomerStatusPageKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Chip(label: Text(limousineCustomerStateLabel(request.state, language))),
        const SizedBox(height: 8),
        Text(
          '${request.offerId} · ${request.serviceClassId}',
          style: TextStyle(color: palette.textMuted),
        ),
        if (request.scheduledPickupIso.isNotEmpty)
          Text(request.scheduledPickupIso),
        if (request.bookingReference.isNotEmpty) Text(request.bookingReference),
        if (LimousineQuoteStateId.normalize(request.state) ==
                LimousineQuoteStateId.requested ||
            LimousineQuoteStateId.normalize(request.state) ==
                LimousineQuoteStateId.viewedByCompany)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_t(kLimousineCustomerWaitingCopy)),
          ),
        if (controller.quoteUpdated)
          Padding(
            key: kLimousineCustomerQuoteUpdatedKey,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _t(kLimousineCustomerQuoteUpdated),
              style: TextStyle(
                color: palette.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (quote != null) ...[
          const SizedBox(height: 12),
          Text(
            formatLimousineMoney(quote.totalInclVatCents, quote.currency),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text('${_t(kLimousineCustomerVat)}: ${quote.vatTreatment}'),
          if (quote.expiresAt.isNotEmpty)
            Text('${kLimousineQuoteExpires.of(language)}: ${quote.expiresAt}'),
          if (quote.publicText.isNotEmpty)
            Text(
              localizedLimousineText(
                quote.publicText,
                languageCode: language.name,
              ),
            ),
          const SizedBox(height: 12),
          LimousineCustomerTermsCard(request: request, language: language),
        ],
        if (request.decline != null)
          Text(
            localizedLimousineText(
              request.decline!.publicText,
              languageCode: language.name,
            ),
          ),
        if (LimousineQuoteStateId.normalize(request.state) ==
            LimousineQuoteStateId.accepted)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _t(kLimousineCustomerAccepted),
              style: TextStyle(
                color: palette.success,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        const SizedBox(height: 12),
        if (!limousineCustomerCanAccept(request) &&
            LimousineQuoteStateId.waitingForCustomer.contains(request.state))
          Text(_t(kLimousineCustomerCannotAccept)),
        if (limousineCustomerCanAccept(request)) ...[
          CheckboxListTile(
            key: kLimousineCustomerAcceptConfirmKey,
            value: controller.termsAcknowledged,
            onChanged: (value) =>
                controller.setTermsAcknowledged(value == true),
            title: Text(_t(kLimousineCustomerAcceptConfirm)),
          ),
          FilledButton(
            key: kLimousineCustomerAcceptKey,
            onPressed: controller.accepting || !controller.termsAcknowledged
                ? null
                : () => controller.acceptCurrentQuote(),
            child: Text(_t(kLimousineCustomerAcceptAction)),
          ),
        ],
        if (controller.handoff != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton(
              key: controller.restoredFromSecureResume
                  ? kLimousineAcceptedBookingContinueKey
                  : kLimousineAcceptedBookingOpenReviewKey,
              onPressed:
                  onOpenBookingReview ??
                  () => openLimousineAcceptedBookingReview(
                    context,
                    quoteController: controller,
                  ),
              child: Text(
                _t(
                  controller.restoredFromSecureResume
                      ? kLimousineAcceptedBookingContinue
                      : kLimousineAcceptedBookingOpenReview,
                ),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => controller.refreshStatus(manual: true),
            child: Text(_t(kLimousineCustomerRefresh)),
          ),
        ),
      ],
    );
  }
}

class LimousineCustomerTermsCard extends StatelessWidget {
  const LimousineCustomerTermsCard({
    super.key,
    required this.request,
    required this.language,
  });

  final LimousineQuoteRequest request;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final quote = request.quote;
    final terms = quote?.terms ?? const <String, dynamic>{};
    Widget row(String label, Object? value) {
      if (value == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label)),
            Expanded(child: Text('$value', textAlign: TextAlign.end)),
          ],
        ),
      );
    }

    String localized(Object? raw) {
      if (raw is Map) {
        return localizedLimousineText(
          raw.map((key, value) => MapEntry(key.toString(), '$value')),
          languageCode: language.name,
        );
      }
      return '';
    }

    return Card(
      key: kLimousineCustomerTermsCardKey,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kLimousineCustomerTermsTitle.of(language),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            row(
              kLimousineQuoteTermsRevision.of(language),
              quote?.termsRevision ?? terms['terms_revision'],
            ),
            row(
              kLimousineQuoteCancelDeadline.of(language),
              terms['cancellation_deadline_hours'],
            ),
            row(
              kLimousineQuoteCancelPenalty.of(language),
              terms['cancellation_penalty_percent'],
            ),
            row(
              kLimousineQuoteWaitingIncluded.of(language),
              terms['waiting_time_included_minutes'],
            ),
            row(
              kLimousineQuoteWaitingOverage.of(language),
              terms['waiting_time_overage_cents_per_minute'] == null
                  ? null
                  : formatLimousineMoney(
                      (terms['waiting_time_overage_cents_per_minute'] as num)
                          .toInt(),
                      quote?.currency ?? '',
                    ),
            ),
            row(
              kLimousineQuoteNoShow.of(language),
              terms['no_show_penalty_percent'],
            ),
            row(
              kLimousineQuoteOvertime.of(language),
              terms['overtime_cents_per_hour'] == null
                  ? null
                  : formatLimousineMoney(
                      (terms['overtime_cents_per_hour'] as num).toInt(),
                      quote?.currency ?? '',
                    ),
            ),
            if ((terms['included_services'] as List?)?.isNotEmpty == true)
              Text(kLimousineCustomerIncludedServices.of(language)),
            if ((terms['paid_extras'] as List?)?.isNotEmpty == true)
              Text(kLimousineCustomerPaidExtras.of(language)),
            if (localized(terms['mobilisation_disclosure']).isNotEmpty)
              row(
                kLimousineCustomerMobilisation.of(language),
                localized(terms['mobilisation_disclosure']),
              ),
            if (localized(terms['customer_obligations']).isNotEmpty)
              row(
                kLimousineCustomerObligations.of(language),
                localized(terms['customer_obligations']),
              ),
            if (localized(terms['important_information']).isNotEmpty)
              row(
                kLimousineCustomerImportant.of(language),
                localized(terms['important_information']),
              ),
          ],
        ),
      ),
    );
  }
}
