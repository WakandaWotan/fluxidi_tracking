// RELEASE-P0-MOLLIE-STREET-CHECKOUT-RETURN-1
//
// Waiting dialog for a street-ride Mollie hosted checkout. Owns:
//   * bounded /pay/status polling (injected via [pollOnce]);
//   * immediate poll on first frame and on app resume;
//   * optional "I have paid" refresh;
//   * terminal success/failure UI without requiring close/reopen.
//
// Server truth comes only from [pollOnce] — deep links and local notifiers
// may *trigger* a poll, but never mark the ride paid by themselves.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/payment/mollie_street_checkout.dart';
import 'package:fluxidi_tracking/payment/payment_qr_panel.dart';
import 'package:fluxidi_tracking/payment_return.dart';

/// Copy for the generic Mollie hosted-checkout QR panel (not Bancontact-only).
class MollieStreetCheckoutCopy {
  const MollieStreetCheckoutCopy({
    required this.title,
    required this.instruction,
    required this.waitingText,
    required this.succeededText,
    required this.failedText,
    required this.cancelledText,
    required this.expiredText,
    required this.iHavePaidLabel,
    required this.closeLabel,
  });

  final String title;
  final String instruction;
  final String waitingText;
  final String succeededText;
  final String failedText;
  final String cancelledText;
  final String expiredText;
  final String iHavePaidLabel;
  final String closeLabel;
}

/// Content of the street "Online betalen" waiting dialog.
class MollieStreetCheckoutDialogContent extends StatefulWidget {
  const MollieStreetCheckoutDialogContent({
    super.key,
    required this.language,
    required this.qrSrc,
    required this.checkoutUrl,
    required this.amountText,
    required this.paymentBookingId,
    required this.textMutedColor,
    required this.copy,
    required this.pollOnce,
    this.pendingPaymentListenable,
    this.maxAttempts = 60,
    this.interval = const Duration(seconds: 5),
  });

  final AppLanguage language;
  final String qrSrc;
  final String? checkoutUrl;
  final String amountText;
  final String paymentBookingId;
  final Color textMutedColor;
  final MollieStreetCheckoutCopy copy;
  final Future<MollieStreetCheckoutPollOutcome> Function() pollOnce;

  /// Optional app-level pending-payment notifier. When the matching payment
  /// id is marked checking (e.g. deep link / coordinator resume), this dialog
  /// immediately re-polls server truth.
  final ValueNotifier<FluxidiPendingPayment?>? pendingPaymentListenable;

  final int maxAttempts;
  final Duration interval;

  @override
  State<MollieStreetCheckoutDialogContent> createState() =>
      MollieStreetCheckoutDialogContentState();
}

@visibleForTesting
class MollieStreetCheckoutDialogContentState
    extends State<MollieStreetCheckoutDialogContent>
    with WidgetsBindingObserver {
  int _attempts = 0;
  bool _polling = false;
  bool _stopped = false;
  bool _pollQueued = false;
  MollieStreetCheckoutPollOutcome? _terminal;
  Timer? _intervalTimer;
  Timer? _terminalPaintTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.pendingPaymentListenable?.addListener(_onPendingPaymentChanged);
    if (widget.paymentBookingId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_runPoll(source: 'DIALOG_OPEN'));
      });
    }
  }

  @override
  void dispose() {
    _stopped = true;
    _intervalTimer?.cancel();
    _terminalPaintTimer?.cancel();
    widget.pendingPaymentListenable?.removeListener(_onPendingPaymentChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_terminal != null) return;
    unawaited(_runPoll(source: 'LIFECYCLE_RESUME'));
  }

  void _onPendingPaymentChanged() {
    if (_terminal != null || _stopped) return;
    final pending = widget.pendingPaymentListenable?.value;
    if (pending == null) return;
    if (pending.paymentBookingId != widget.paymentBookingId) return;
    // Deep link / coordinator only triggers a server poll — never marks paid.
    unawaited(_runPoll(source: 'PENDING_NOTIFIER'));
  }

  /// Manual refresh ("Ik heb betaald").
  Future<void> refreshNow() => _runPoll(source: 'USER_REFRESH');

  Future<void> _runPoll({required String source}) async {
    if (!mounted || _stopped || _terminal != null) return;
    if (_polling) {
      _pollQueued = true;
      return;
    }
    _polling = true;
    _pollQueued = false;
    if (mounted) setState(() {});
    MollieStreetCheckoutPollOutcome outcome;
    try {
      outcome = await widget.pollOnce();
    } catch (_) {
      outcome = MollieStreetCheckoutPollOutcome.error;
    }
    if (!mounted || _stopped) return;
    _polling = false;
    _attempts++;

    if (molliePollOutcomeIsTerminal(outcome)) {
      _intervalTimer?.cancel();
      setState(() => _terminal = outcome);
      // Brief success/failure paint, then pop so the receipt can refresh.
      _terminalPaintTimer?.cancel();
      _terminalPaintTimer = Timer(const Duration(milliseconds: 450), () {
        if (!mounted || _stopped) return;
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop(outcome);
        }
      });
      return;
    }

    if (mounted) setState(() {});

    if (_pollQueued) {
      unawaited(_runPoll(source: 'QUEUED'));
      return;
    }

    if (_attempts >= widget.maxAttempts) {
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop(MollieStreetCheckoutPollOutcome.pending);
      }
      return;
    }

    // Continue bounded background polling while the dialog stays open.
    _intervalTimer?.cancel();
    _intervalTimer = Timer(widget.interval, () {
      if (!mounted || _stopped || _terminal != null) return;
      unawaited(_runPoll(source: 'INTERVAL'));
    });
  }

  String _statusText() {
    switch (_terminal) {
      case MollieStreetCheckoutPollOutcome.paid:
        return widget.copy.succeededText;
      case MollieStreetCheckoutPollOutcome.failed:
        return widget.copy.failedText;
      case MollieStreetCheckoutPollOutcome.cancelled:
        return widget.copy.cancelledText;
      case MollieStreetCheckoutPollOutcome.expired:
        return widget.copy.expiredText;
      case MollieStreetCheckoutPollOutcome.pending:
      case MollieStreetCheckoutPollOutcome.error:
      case null:
        return widget.copy.waitingText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPaid = _terminal == MollieStreetCheckoutPollOutcome.paid;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaymentQrPanel(
          language: widget.language,
          qrSrc: widget.qrSrc,
          checkoutUrl: widget.checkoutUrl,
          title: widget.copy.title,
          subtitle: widget.copy.instruction,
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            widget.amountText,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        if (widget.paymentBookingId.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_polling && _terminal == null) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
              ],
              if (isPaid)
                const Icon(Icons.check_circle, color: Color(0xFF15803D), size: 18),
              if (isPaid) const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _statusText(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: isPaid
                        ? const Color(0xFF15803D)
                        : widget.textMutedColor,
                    fontStyle: isPaid ? FontStyle.normal : FontStyle.italic,
                    fontWeight: isPaid ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          if (_terminal == null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _polling ? null : () => unawaited(refreshNow()),
              child: Text(widget.copy.iHavePaidLabel),
            ),
          ],
        ],
      ],
    );
  }
}
