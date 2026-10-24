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
import 'limousine_quote_presentation.dart';
import 'limousine_quotation_pdf_action.dart';
import 'limousine_wizard_vehicle.dart';

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
    this.onReturnToCustomerStart,
  });

  final LimousineCustomerQuoteController controller;
  final AppLanguage language;
  final CustomerThemePalette palette;
  final VoidCallback? onOpenBookingReview;
  final VoidCallback? onReturnToCustomerStart;

  String _t(LocalizedText text) => text.of(language);

  @override
  Widget build(BuildContext context) {
    final request = controller.request;
    if (request == null) {
      return LimousineCustomerUnavailableBanner(language: language);
    }
    final quote = request.quote;
    final companyName =
        (controller.providerDisplayName.isNotEmpty
                ? controller.providerDisplayName
                : controller.selectedProvider?.provider.companyName ?? '')
            .trim();
    final vehicleName = (controller.lockedVehicle?.name ?? '').trim().isNotEmpty
        ? controller.lockedVehicle!.name.trim()
        : limousineQuoteVehicleDisplay(request, language);
    final refreshFailed = controller.statusRefreshFailed;
    final content = Column(
      key: kLimousineCustomerStatusPageKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (refreshFailed)
          Card(
            key: kLimousineCustomerStatusRefreshFailedKey,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_t(kLimousineCustomerStatusRefreshFailed)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => controller.refreshStatus(manual: true),
                    child: Text(_t(kLimousineCustomerRefresh)),
                  ),
                ],
              ),
            ),
          )
        else
          Chip(
            label: Text(
              limousineCustomerStateLabel(
                request.state,
                language,
                companyName: companyName,
                request: request,
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (!refreshFailed &&
            LimousineQuoteStateId.normalize(
                  limousineCustomerLifecycleState(
                    request.state,
                    request: request,
                  ),
                ) ==
                LimousineQuoteStateId.requested)
          Padding(
            key: kLimousineQuoteSubmitConfirmationKey,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  limousineCustomerRequestReceivedLabel(
                    language,
                    companyName: companyName,
                  ),
                ),
                if (request.quoteRequestId.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${_t(kLimousineQuoteSubmittedReference)}: ${request.quoteRequestId}',
                    key: kLimousineQuoteSubmitReferenceKey,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
                if (vehicleName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      vehicleName,
                      key: kLimousineReviewLockedVehicleKey,
                    ),
                  ),
                const SizedBox(height: 8),
                Text(_t(kLimousineCustomerWaitingCopy)),
                const SizedBox(height: 12),
                FilledButton(
                  key: kLimousineQuoteSubmittedHomeKey,
                  onPressed: () {
                    controller.resetAfterConfirmedSubmit();
                    onReturnToCustomerStart?.call();
                  },
                  child: Text(_t(kLimousineQuoteSubmittedHome)),
                ),
              ],
            ),
          ),
        if (!refreshFailed &&
            limousineCustomerLifecycleState(request.state, request: request) ==
                LimousineQuoteStateId.viewedByCompany)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_t(kLimousineCustomerCompanyViewedCopy)),
                if (request.companyViewedAt.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      formatLimousineUserDate(
                        request.companyViewedAt,
                        language,
                      ),
                      key: kLimousineCustomerViewedAtKey,
                    ),
                  ),
              ],
            ),
          ),
        if (request.bookingReference.isNotEmpty) Text(request.bookingReference),
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
        const SizedBox(height: 8),
        Text(
          _t(kLimousineCustomerYourRequest),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        if ((request.fulfilment?.from ?? '').isNotEmpty ||
            (request.fulfilment?.to ?? '').isNotEmpty)
          Text(
            [
              request.fulfilment?.from ?? '',
              request.fulfilment?.to ?? '',
            ].where((part) => part.trim().isNotEmpty).join(' → '),
          ),
        if (request.scheduledPickupIso.isNotEmpty)
          Text(
            limousineQuoteDisplayOrEmpty(request.scheduledPickupIso, language),
          ),
        if (request.pax != null)
          Text('${_t(kLimousineCustomerPax)}: ${request.pax}'),
        if (vehicleName.isNotEmpty) Text(vehicleName),
        if (quote != null) ...[
          const SizedBox(height: 16),
          Text(
            limousineCustomerQuoteFromCompanyLabel(
              language,
              companyName: companyName,
            ),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 6),
          ...() {
            final money = limousineCanonicalMoneyFromRequest(request);
            final gross = money?.grossCents ?? quote.totalInclVatCents;
            final lines = money == null
                ? const <LimousineQuoteMoneyLine>[]
                : limousineQuoteMoneyLines(money: money, language: language);
            final vatLabel = limousineVatRatePercentLabel(
              money?.vatRate ?? quote.vatRate,
              language,
              inclusive:
                  (money?.vatTreatment ?? quote.vatTreatment)
                      .trim()
                      .toLowerCase() ==
                  kLimousineQuoteVatIncl,
            );
            return <Widget>[
              for (final line in lines)
                Text(
                  '${line.label}: ${formatLimousineEuroAmount(line.cents)}',
                  key: line.emphasize
                      ? kLimousineCustomerQuoteTotalKey
                      : line.label == vatLabel
                      ? kLimousineCustomerQuoteVatKey
                      : line.label == kLimousineQuoteNetAmount.of(language)
                      ? kLimousineCustomerQuoteNetKey
                      : null,
                  style: line.emphasize
                      ? TextStyle(
                          color: palette.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        )
                      : null,
                ),
              if (lines.isEmpty)
                Text(
                  formatLimousineEuroAmount(gross),
                  key: kLimousineCustomerQuoteTotalKey,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ];
          }(),
          if ((request.quotationCurrency.isNotEmpty
                  ? request.quotationCurrency
                  : quote.currency)
              .isNotEmpty)
            Text(
              request.quotationCurrency.isNotEmpty
                  ? request.quotationCurrency
                  : quote.currency,
            ),
          if (limousineVatTreatmentLabel(
            request.quotationVatTreatment.isNotEmpty
                ? request.quotationVatTreatment
                : quote.vatTreatment,
            language,
          ).isNotEmpty)
            Text(
              limousineVatTreatmentLabel(
                request.quotationVatTreatment.isNotEmpty
                    ? request.quotationVatTreatment
                    : quote.vatTreatment,
                language,
              ),
            ),
          if ((request.quotationSentAt.isNotEmpty
                  ? request.quotationSentAt
                  : quote.quotedAt)
              .isNotEmpty)
            Text(
              '${_t(kLimousineCustomerQuoteSentAt)}: ${formatLimousineUserDate(request.quotationSentAt.isNotEmpty ? request.quotationSentAt : quote.quotedAt, language)}',
              key: kLimousineCustomerQuoteSentAtKey,
            ),
          if ((request.quotationExpiresAt.isNotEmpty
                  ? request.quotationExpiresAt
                  : quote.expiresAt)
              .isNotEmpty)
            Text(
              '${_t(kLimousineCustomerQuoteValidUntil)}: ${formatLimousineUserDate(request.quotationExpiresAt.isNotEmpty ? request.quotationExpiresAt : quote.expiresAt, language)}',
              key: kLimousineCustomerQuoteExpiresAtKey,
            ),
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
        if (request.hasQuotationPdf) ...[
          const SizedBox(height: 12),
          LimousineQuotationPdfAction(
            buttonKey: kLimousineCustomerViewQuotationKey,
            label: _t(kLimousineQuoteViewQuotation),
            previewTitle: _t(kLimousineQuoteViewQuotationPreviewTitle),
            errorLabel: _t(kLimousineQuoteViewQuotationError),
            loadBytes: controller.loadQuotationPdf,
          ),
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
    return Theme(
      data: themeForCustomerPalette(Theme.of(context), palette),
      child: DefaultTextStyle(
        style: TextStyle(color: palette.textPrimary, height: 1.35),
        child: content,
      ),
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

    String includedLabels(Object? raw) {
      if (raw is! List) return '';
      final labels = <String>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final label = item['label'] ?? item['name'];
        final text = label is Map
            ? localized(label)
            : (label ?? '').toString().trim();
        if (text.isNotEmpty) labels.add(text);
      }
      return labels.join(', ');
    }

    final cancelHours = terms['cancellation_deadline_hours'];
    final cancelPct = terms['cancellation_penalty_percent'];
    final waitMin = terms['waiting_time_included_minutes'];
    final waitOver = terms['waiting_time_overage_cents_per_minute'];
    final noShow = terms['no_show_penalty_percent'];
    final overtime = terms['overtime_cents_per_hour'];
    final included = includedLabels(
      quote?.includedServices.isNotEmpty == true
          ? quote!.includedServices
          : terms['included_services'],
    );
    final extras = includedLabels(
      quote?.separatelyPricedExtras.isNotEmpty == true
          ? quote!.separatelyPricedExtras
          : terms['paid_extras'],
    );
    final mobilisation = localized(
      quote?.mobilisationDisclosure.isNotEmpty == true
          ? quote!.mobilisationDisclosure
          : terms['mobilisation_disclosure'],
    );
    final obligations = localized(terms['customer_obligations']);
    final important = localized(terms['important_information']);
    final rows = <Widget>[
      if (cancelHours is num && cancelHours > 0)
        row(kLimousineQuoteCancelDeadline.of(language), cancelHours),
      if (cancelPct is num && cancelPct > 0)
        row(kLimousineQuoteCancelPenalty.of(language), cancelPct),
      if (waitMin is num && waitMin > 0)
        row(kLimousineQuoteWaitingIncluded.of(language), waitMin),
      if (waitOver is num && waitOver > 0)
        row(
          kLimousineQuoteWaitingOverage.of(language),
          formatLimousineEuroAmount(waitOver.toInt()),
        ),
      if (noShow is num && noShow > 0)
        row(kLimousineQuoteNoShow.of(language), noShow),
      if (overtime is num && overtime > 0)
        row(
          kLimousineQuoteOvertime.of(language),
          formatLimousineEuroAmount(overtime.toInt()),
        ),
      if (included.isNotEmpty)
        row(kLimousineCustomerIncludedServices.of(language), included),
      if (extras.isNotEmpty)
        row(kLimousineCustomerPaidExtras.of(language), extras),
      if (mobilisation.isNotEmpty)
        row(kLimousineCustomerMobilisation.of(language), mobilisation),
      if (obligations.isNotEmpty)
        row(kLimousineCustomerObligations.of(language), obligations),
      if (important.isNotEmpty)
        row(kLimousineCustomerImportant.of(language), important),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: kLimousineCustomerTermsCardKey,
      color: scheme.surface,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: scheme.onSurface, height: 1.35),
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
              ...rows,
            ],
          ),
        ),
      ),
    );
  }
}
