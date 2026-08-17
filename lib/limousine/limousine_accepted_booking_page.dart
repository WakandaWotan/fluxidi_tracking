import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../customer_theme_palette.dart';
import '../customer_theme_store.dart';
import 'limousine_accepted_booking.dart';
import 'limousine_accepted_booking_api.dart';
import 'limousine_accepted_booking_labels.dart';
import 'limousine_customer_entry.dart';
import 'limousine_customer_quote_api.dart';
import 'limousine_customer_quote_labels.dart';
import 'limousine_offers.dart';
import 'limousine_quote_inbox.dart';
import 'limousine_quote_inbox_labels.dart';

class LimousineAcceptedBookingPage extends StatefulWidget {
  const LimousineAcceptedBookingPage({
    super.key,
    required this.controller,
    this.entryEnabled,
    this.onBackToQuote,
    this.onBackToProfile,
  });

  final LimousineAcceptedBookingController controller;
  final bool? entryEnabled;
  final VoidCallback? onBackToQuote;
  final VoidCallback? onBackToProfile;

  @override
  State<LimousineAcceptedBookingPage> createState() =>
      _LimousineAcceptedBookingPageState();
}

class _LimousineAcceptedBookingPageState
    extends State<LimousineAcceptedBookingPage> {
  bool get _entryEnabled =>
      widget.entryEnabled ?? LimousineCustomerEntryContract.isVisible;

  AppLanguage get _lang => appLanguageNotifier.value;

  String _t(LocalizedText text) => text.of(_lang);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteForCustomerTheme(customerThemeNotifier.value);
    final controller = widget.controller;
    return Scaffold(
      key: kLimousineAcceptedBookingPageKey,
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        title: Text(_t(kLimousineAcceptedBookingTitle)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (!_entryEnabled)
              Text(
                _t(
                  kLimousineAcceptedBookingErrors[LimousineAcceptedBookingError
                      .gateOff]!,
                ),
              )
            else if (controller.phase == LimousineAcceptedBookingPhase.success)
              _success(controller, palette)
            else ...[
              _review(controller.reviewFor(_lang), palette),
              if (controller.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _t(
                      kLimousineAcceptedBookingErrors[controller.error] ??
                          kLimousineAcceptedBookingRetryable,
                    ),
                  ),
                ),
              if (controller.phase == LimousineAcceptedBookingPhase.submitting)
                Padding(
                  key: kLimousineAcceptedBookingCreatingKey,
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_t(kLimousineAcceptedBookingCreating)),
                ),
              if (controller.phase !=
                  LimousineAcceptedBookingPhase.success) ...[
                CheckboxListTile(
                  key: kLimousineAcceptedBookingConfirmKey,
                  value: controller.confirmationAcknowledged,
                  onChanged: controller.submitting
                      ? null
                      : (value) => controller.setConfirmationAcknowledged(
                          value == true,
                        ),
                  title: Text(_t(kLimousineAcceptedBookingConfirm)),
                ),
                FilledButton(
                  key: kLimousineAcceptedBookingSubmitKey,
                  onPressed:
                      controller.submitting ||
                          !controller.confirmationAcknowledged
                      ? null
                      : () => controller.confirmBooking(),
                  child: Text(_t(kLimousineAcceptedBookingSubmit)),
                ),
              ],
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: kLimousineAcceptedBookingBackToQuoteKey,
                onPressed:
                    widget.onBackToQuote ??
                    () => Navigator.of(context).maybePop(),
                child: Text(_t(kLimousineAcceptedBookingBackToQuote)),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: kLimousineAcceptedBookingBackToProfileKey,
                onPressed:
                    widget.onBackToProfile ??
                    () => Navigator.of(context).maybePop(),
                child: Text(_t(kLimousineAcceptedBookingBackToProfile)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _review(
    LimousineAcceptedBookingReview review,
    CustomerThemePalette palette,
  ) {
    Widget row(LocalizedText label, String value) {
      if (value.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(_t(label))),
            Expanded(child: Text(value, textAlign: TextAlign.end)),
          ],
        ),
      );
    }

    String localizedMap(Map<String, String> value) =>
        localizedLimousineText(value, languageCode: _lang.name);

    return Card(
      key: kLimousineAcceptedBookingReviewKey,
      color: palette.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(kLimousineAcceptedBookingProvider, review.providerName),
            row(kLimousineAcceptedBookingOffer, review.offerTitle),
            if (review.serviceClassLabel.isNotEmpty)
              row(kLimousineAcceptedBookingClass, review.serviceClassLabel),
            if (review.vehicleSupplied)
              row(kLimousineAcceptedBookingVehicle, review.offerTitle),
            if (review.journeyType.isNotEmpty)
              Text(limousineJourneyTypeLabel(review.journeyType, _lang)),
            row(kLimousineCustomerFrom, review.from),
            row(kLimousineCustomerTo, review.to),
            if (review.stops.isNotEmpty)
              Text(
                '${_t(kLimousineCustomerStops)}: ${review.stops.join(', ')}',
              ),
            if (review.scheduledPickupIso.isNotEmpty)
              Text(review.scheduledPickupIso),
            if (review.roundtrip && review.returnPickupIso.isNotEmpty)
              Text(review.returnPickupIso),
            if (review.pax != null)
              Text('${_t(kLimousineCustomerPax)}: ${review.pax}'),
            if (review.bags != null)
              Text('${_t(kLimousineCustomerBags)}: ${review.bags}'),
            if (review.includedServices.isNotEmpty)
              Text(_t(kLimousineCustomerIncludedServices)),
            if (review.acceptedExtras.isNotEmpty)
              Text(_t(kLimousineCustomerPaidExtras)),
            if (localizedMap(review.mobilisationDisclosure).isNotEmpty)
              row(
                kLimousineCustomerMobilisation,
                localizedMap(review.mobilisationDisclosure),
              ),
            const SizedBox(height: 8),
            Text(
              formatLimousineMoney(review.totalInclVatCents, review.currency),
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (review.vatTreatment.isNotEmpty)
              Text('${_t(kLimousineCustomerVat)}: ${review.vatTreatment}'),
            Text(
              '${kLimousineQuoteTermsRevision.of(_lang)}: ${review.termsRevision}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _success(
    LimousineAcceptedBookingController controller,
    CustomerThemePalette palette,
  ) {
    final reference =
        controller.result?.publicReference ??
        controller.result?.bookingId ??
        '';
    return Card(
      key: kLimousineAcceptedBookingSuccessKey,
      color: palette.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(kLimousineAcceptedBookingSuccess),
              style: TextStyle(
                color: palette.success,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text('${_t(kLimousineAcceptedBookingReference)}: $reference'),
          ],
        ),
      ),
    );
  }
}

void openLimousineAcceptedBookingReview(
  BuildContext context, {
  required LimousineCustomerQuoteController quoteController,
  LimousineAcceptedBookingGateway? gateway,
  bool? entryEnabled,
}) {
  final handoff = quoteController.handoff;
  if (handoff == null) return;
  final enabled = entryEnabled ?? LimousineCustomerEntryContract.isVisible;
  final bookingController = LimousineAcceptedBookingController(
    handoff: handoff,
    draft: quoteController.draft,
    request: quoteController.request,
    offer: quoteController.selectedOffer,
    providerName: quoteController.selectedProvider?.provider.companyName ?? '',
    entryEnabled: enabled,
    quoteController: quoteController,
    gateway: gateway ?? HttpLimousineAcceptedBookingGateway(),
  );
  Navigator.of(context)
      .push(
        MaterialPageRoute<void>(
          builder: (_) => LimousineAcceptedBookingPage(
            controller: bookingController,
            entryEnabled: enabled,
          ),
        ),
      )
      .whenComplete(bookingController.dispose);
}
