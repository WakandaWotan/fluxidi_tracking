import 'dart:async';

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_strings.dart';
import '../customer_theme_palette.dart';
import '../customer_theme_store.dart';
import '../payment/booking_billing_identity_form.dart';
import '../payment/booking_payment_method_tile.dart';
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

  /// Owned here, like every other booking surface owns its billing fields, so
  /// nothing the customer types outlives this page.
  final BookingBillingIdentityControllers _billing =
      BookingBillingIdentityControllers();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    if (_entryEnabled && widget.controller.paymentCapability == null) {
      unawaited(widget.controller.loadPaymentCapability());
    }
  }

  /// Same four-language resolution the other booking surfaces use, so the
  /// shared payment copy reads identically here.
  String _payText({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) {
    switch (_lang) {
      case AppLanguage.nl:
        return nl;
      case AppLanguage.en:
        return en;
      case AppLanguage.fr:
        return fr;
      case AppLanguage.es:
        return es;
      case AppLanguage.de:
        return en;
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _billing.dispose();
    super.dispose();
  }

  void _syncBillingIdentity() {
    widget.controller.updateBillingIdentity(_billing.identity);
  }

  void _onBillingEnabledChanged(bool enabled) {
    widget.controller.setBillingEnabled(enabled);
    _syncBillingIdentity();
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
              _paymentSection(controller, palette),
              _billingSection(controller, palette),
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
                  onPressed: controller.canConfirmBooking
                      ? () => controller.confirmBooking()
                      : null,
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

  /// The payment picker, driven entirely by the partner capability the server
  /// published for this accepted quote.
  Widget _paymentSection(
    LimousineAcceptedBookingController controller,
    CustomerThemePalette palette,
  ) {
    final options = controller.paymentOptionsFor(_lang.name);
    final visible = controller.visiblePaymentMethodIds;
    return Card(
      key: kLimousineAcceptedBookingPaymentSectionKey,
      color: palette.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(kLimousineAcceptedBookingPaymentTitle),
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _t(kLimousineAcceptedBookingPaymentSubtitle),
              style: TextStyle(color: palette.textMuted, fontSize: 12.4),
            ),
            const SizedBox(height: 10),
            if (controller.loadingPaymentCapability)
              Row(
                key: kLimousineAcceptedBookingPaymentLoadingKey,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.gold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _t(kLimousineAcceptedBookingPaymentLoading),
                      style: TextStyle(color: palette.textMuted),
                    ),
                  ),
                ],
              )
            else if (options == null || visible.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: kLimousineAcceptedBookingPaymentRetryKey,
                  onPressed: () => controller.loadPaymentCapability(),
                  child: Text(_t(kLimousineAcceptedBookingPaymentRetry)),
                ),
              )
            else ...[
              if (options.onlinePaymentsBlockedMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    options.onlinePaymentsBlockedMessage!,
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                ),
              for (final methodId in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: BookingPaymentMethodTile(
                    key: limousineAcceptedBookingPaymentMethodKey(methodId),
                    methodId: methodId,
                    label: paymentMethodDisplayLabel(methodId, _payText),
                    description: paymentMethodShortDescription(
                      methodId,
                      _payText,
                      qrPaymentConfigured: options.qrPaymentConfigured,
                    ),
                    selected: controller.selectedPaymentMethodId == methodId,
                    displayOnly: options.isDisplayOnly(methodId),
                    style: BookingPaymentTileStyle(
                      animationDuration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      selectedBackground: palette.surfaceAlt,
                      unselectedBackground: palette.surface,
                      selectedBorderColor: palette.gold,
                      unselectedBorderColor: palette.border,
                      accentColor: palette.gold,
                      labelColor: palette.textPrimary,
                      mutedColor: palette.textMuted,
                      descriptionColor: palette.textMuted,
                      unselectedLogoColor: palette.textMuted,
                    ),
                    onSelect: controller.submitting
                        ? null
                        : () => controller.selectPaymentMethod(methodId),
                    onDisplayOnlyTap: controller.submitting
                        ? null
                        : () => _showPaymentNotice(
                            displayOnlyPaymentMethodMessage(
                              methodId,
                              _payText,
                              languageCode: _lang.name,
                            ),
                            palette,
                          ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Buyer billing identity for a company invoice. Private is the default
  /// and sends nothing; turning the toggle on never changes the accepted
  /// quote amount.
  Widget _billingSection(
    LimousineAcceptedBookingController controller,
    CustomerThemePalette palette,
  ) {
    final missing = controller.missingBillingIdentityField;
    final warning = missing == null
        ? null
        : bookingBillingIdentityMissingFieldMessage(missing, _payText);
    final interactive = !controller.submitting && !controller.succeeded;
    return Card(
      key: kLimousineAcceptedBookingBillingSectionKey,
      color: palette.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(kLimousineAcceptedBookingBillingTitle),
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _t(kLimousineAcceptedBookingBillingSubtitle),
              style: TextStyle(color: palette.textMuted, fontSize: 12.4),
            ),
            const SizedBox(height: 4),
            Text(
              _t(kLimousineAcceptedBookingBillingPriceUnchanged),
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 6),
            BookingBillingIdentityForm(
              enabled: controller.billingEnabled,
              controllers: _billing,
              t: _payText,
              onEnabledChanged: interactive ? _onBillingEnabledChanged : null,
              onChanged: interactive ? _syncBillingIdentity : null,
              warning: warning,
              style: BookingBillingFormStyle(
                accentColor: palette.gold,
                labelColor: palette.textPrimary,
                mutedColor: palette.textMuted,
                fieldBackground: palette.surfaceAlt,
                fieldBorderColor: palette.border,
                warningColor: palette.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentNotice(String message, CustomerThemePalette palette) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: palette.surfaceAlt,
        content: Text(message, style: TextStyle(color: palette.textPrimary)),
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
            if (controller.checkoutStartFailed)
              Padding(
                key: kLimousineAcceptedBookingCheckoutUnavailableKey,
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _t(kLimousineAcceptedBookingCheckoutUnavailable),
                  style: TextStyle(color: palette.textMuted),
                ),
              ),
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
  LimousineAcceptedPaymentCapabilityLoader? paymentCapabilityLoader,
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
    reviewSnapshot: quoteController.secureResumeReview,
    gateway: gateway ?? HttpLimousineAcceptedBookingGateway(),
    initialPaymentCapability: quoteController.acceptedPaymentCapability,
    // Always re-readable: the partner's capability comes from the accepted
    // quote's own status read, never from the company profile on this device.
    paymentCapabilityLoader:
        paymentCapabilityLoader ??
        () => readLimousinePartnerPaymentCapability(
          statusRef: quoteController.statusRef ?? '',
        ),
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
