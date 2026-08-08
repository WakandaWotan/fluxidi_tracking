// RELEASE-P0-MOLLIE-STREET-CHECKOUT-CONVERGE-1
//
// Waiting dialog for a street-ride Mollie hosted checkout. Owns:
//   * bounded /pay/status polling (injected via [pollOnce]);
//   * immediate poll on first frame and on app resume;
//   * "I have paid" refresh with visible feedback (never silent);
//   * accepting a same-id verified paid/confirmed notifier event;
//   * terminal success/failure UI without requiring close/reopen.
//
// Deep-link status hints never mark paid. Notifier paid/confirmed is trusted
// only when PaymentReturnCoordinator already reconciled via authenticated
// `/pay/status` for the same payment shadow id.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/payment/mollie_street_checkout.dart';
import 'package:fluxidi_tracking/payment/mollie_street_status_auth.dart';
import 'package:fluxidi_tracking/payment/payment_qr_panel.dart';
import 'package:fluxidi_tracking/payment_return.dart';

/// Copy for the generic Mollie hosted-checkout QR panel (not Bancontact-only).
class MollieStreetCheckoutCopy {
  const MollieStreetCheckoutCopy({
    required this.title,
    required this.instruction,
    required this.waitingText,
    required this.processingText,
    required this.succeededText,
    required this.failedText,
    required this.cancelledText,
    required this.expiredText,
    required this.iHavePaidLabel,
    required this.closeLabel,
    required this.statusAuthErrorText,
    required this.statusNotFoundErrorText,
    required this.statusServerErrorText,
    required this.statusGenericErrorText,
    this.cancelOnlinePaymentLabel = 'Cancel online payment',
    this.cancelOnlinePaymentHint =
        'Stops this online attempt at the provider before another payment method can be chosen.',
    this.cancelOnlinePaymentBusyText = 'Canceling online payment…',
    this.cancelOnlinePaymentFailedText =
        'Could not confirm cancellation. Online payment is still open.',
  });

  final String title;
  final String instruction;
  final String waitingText;
  final String processingText;
  final String succeededText;
  final String failedText;
  final String cancelledText;
  final String expiredText;
  final String iHavePaidLabel;
  final String closeLabel;
  final String statusAuthErrorText;
  final String statusNotFoundErrorText;
  final String statusServerErrorText;
  final String statusGenericErrorText;

  /// STREET-ONLINE-PAYMENT-CONVERGENCE-P0: first-class cancel inside dialog.
  final String cancelOnlinePaymentLabel;
  final String cancelOnlinePaymentHint;
  final String cancelOnlinePaymentBusyText;
  final String cancelOnlinePaymentFailedText;
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
    this.canonicalBookingId,
    this.onCancelOnlinePayment,
    this.onAuthoritativeRefresh,
    this.maxAttempts = 60,
    this.interval = const Duration(seconds: 5),
  });

  final AppLanguage language;
  final String qrSrc;
  final String? checkoutUrl;
  final String amountText;
  final String paymentBookingId;
  final String? canonicalBookingId;
  final Color textMutedColor;
  final MollieStreetCheckoutCopy copy;
  final Future<MollieStreetCheckoutPollResult> Function() pollOnce;

  /// Optional app-level pending-payment notifier. Matching payment id with
  /// verified paid/confirmed transitions the modal immediately; other
  /// matching updates only trigger a server poll.
  final ValueNotifier<FluxidiPendingPayment?>? pendingPaymentListenable;

  /// STREET-ONLINE-PAYMENT-CONVERGENCE-P0: authoritative cancel via
  /// `/mollie-checkout-recovery` action=cancel. Must not be a local dismiss.
  final Future<MollieStreetCheckoutPollOutcome> Function()? onCancelOnlinePayment;

  /// One-shot authoritative refresh (recovery action=refresh) on dialog open
  /// and app resume. Provider truth may converge without waiting for poll.
  final Future<MollieStreetCheckoutPollOutcome?> Function()? onAuthoritativeRefresh;

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
  int _pollGeneration = 0;
  bool _polling = false;
  bool _stopped = false;
  bool _pollQueued = false;
  bool _userRefreshPendingFeedback = false;
  bool _cancelBusy = false;
  bool _authoritativeRefreshInFlight = false;
  MollieStreetCheckoutPollOutcome? _terminal;
  String? _feedbackText;
  Timer? _intervalTimer;
  Timer? _terminalPaintTimer;

  @visibleForTesting
  bool get isPolling => _polling;

  @visibleForTesting
  bool get isCancelBusy => _cancelBusy;

  @visibleForTesting
  MollieStreetCheckoutPollOutcome? get terminalOutcome => _terminal;

  @visibleForTesting
  String? get feedbackText => _feedbackText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.pendingPaymentListenable?.addListener(_onPendingPaymentChanged);
    if (widget.paymentBookingId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_runAuthoritativeRefreshThenPoll(source: 'DIALOG_OPEN'));
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
    unawaited(_runAuthoritativeRefreshThenPoll(source: 'LIFECYCLE_RESUME'));
  }

  Future<void> _runAuthoritativeRefreshThenPoll({required String source}) async {
    if (!mounted || _stopped || _terminal != null) return;
    if (_authoritativeRefreshInFlight) {
      unawaited(_runPoll(source: source));
      return;
    }
    final refresh = widget.onAuthoritativeRefresh;
    if (refresh == null) {
      unawaited(_runPoll(source: source));
      return;
    }
    _authoritativeRefreshInFlight = true;
    try {
      final outcome = await refresh();
      if (!mounted || _stopped) return;
      if (outcome != null && molliePollOutcomeIsTerminal(outcome)) {
        _intervalTimer?.cancel();
        setState(() {
          _terminal = outcome;
          _feedbackText = null;
        });
        _scheduleTerminalPop(outcome);
        return;
      }
    } catch (_) {
      // Fall through to bounded /pay/status poll.
    } finally {
      _authoritativeRefreshInFlight = false;
    }
    if (!mounted || _stopped || _terminal != null) return;
    unawaited(_runPoll(source: source));
  }

  /// Explicit provider-side cancel (not local dismiss).
  Future<void> cancelOnlinePaymentNow() async {
    if (!mounted || _stopped || _cancelBusy) return;
    if (_terminal != null && molliePollOutcomeIsTerminal(_terminal!)) return;
    final cancel = widget.onCancelOnlinePayment;
    if (cancel == null) return;
    setState(() {
      _cancelBusy = true;
      _feedbackText = widget.copy.cancelOnlinePaymentBusyText;
    });
    try {
      final outcome = await cancel();
      if (!mounted || _stopped) return;
      if (outcome == MollieStreetCheckoutPollOutcome.paid ||
          molliePollOutcomeIsTerminal(outcome)) {
        _intervalTimer?.cancel();
        setState(() {
          _terminal = outcome;
          _feedbackText = null;
          _cancelBusy = false;
        });
        _scheduleTerminalPop(outcome);
        return;
      }
      setState(() {
        _cancelBusy = false;
        _feedbackText = widget.copy.cancelOnlinePaymentFailedText;
      });
    } catch (_) {
      if (!mounted || _stopped) return;
      setState(() {
        _cancelBusy = false;
        _feedbackText = widget.copy.cancelOnlinePaymentFailedText;
      });
    }
  }

  void _onPendingPaymentChanged() {
    if (_terminal != null || _stopped) return;
    final pending = widget.pendingPaymentListenable?.value;
    if (pending == null) return;
    if (!mollieStreetPaymentIdsMatch(
      pending.paymentBookingId,
      widget.paymentBookingId,
    )) {
      return;
    }
    // Same payment shadow: accept verified paid/confirmed from coordinator.
    if (pending.status == FluxidiPaymentStatus.paid ||
        pending.status == FluxidiPaymentStatus.confirmed) {
      _acceptVerifiedPaid(source: 'PENDING_NOTIFIER');
      return;
    }
    // Deep link / checking only triggers a server poll — never marks paid.
    unawaited(_runPoll(source: 'PENDING_NOTIFIER'));
  }

  /// Manual refresh ("Ik heb betaald") — always shows visible feedback.
  Future<void> refreshNow() =>
      _runPoll(source: 'USER_REFRESH', userInitiated: true);

  void _acceptVerifiedPaid({required String source}) {
    if (_terminal == MollieStreetCheckoutPollOutcome.paid) return;
    _intervalTimer?.cancel();
    _pollQueued = false;
    _polling = false;
    _feedbackText = null;
    if (!mounted || _stopped) return;
    setState(() => _terminal = MollieStreetCheckoutPollOutcome.paid);
    debugPrint(
      '[MOLLIE_STREET_CHECKOUT][NOTIFIER_PAID] source=$source '
      'pay=${mollieStreetIdHash(widget.paymentBookingId)} '
      'booking=${mollieStreetIdHash(widget.canonicalBookingId)}',
    );
    _scheduleTerminalPop(MollieStreetCheckoutPollOutcome.paid);
  }

  void _scheduleTerminalPop(MollieStreetCheckoutPollOutcome outcome) {
    _terminalPaintTimer?.cancel();
    _terminalPaintTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || _stopped) return;
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop(outcome);
      }
    });
  }

  String _feedbackForError(MollieStreetCheckoutPollResult result) {
    final code = (result.sanitizedErrorCode ?? '').toLowerCase();
    if (code == 'unauthorized' || code == 'forbidden') {
      return widget.copy.statusAuthErrorText;
    }
    if (code == 'not_found' || code == 'booking_not_found') {
      return widget.copy.statusNotFoundErrorText;
    }
    if (code == 'server_error' || result.httpCode >= 500) {
      return widget.copy.statusServerErrorText;
    }
    return widget.copy.statusGenericErrorText;
  }

  Future<void> _runPoll({
    required String source,
    bool userInitiated = false,
  }) async {
    if (!mounted || _stopped) return;
    if (_terminal == MollieStreetCheckoutPollOutcome.paid) return;
    if (_terminal != null && molliePollOutcomeIsTerminal(_terminal!)) return;

    if (_polling) {
      _pollQueued = true;
      if (userInitiated) _userRefreshPendingFeedback = true;
      return;
    }

    final myGen = ++_pollGeneration;
    _polling = true;
    _pollQueued = false;
    if (userInitiated) {
      _userRefreshPendingFeedback = true;
      _feedbackText = null;
    }
    if (mounted) setState(() {});

    MollieStreetCheckoutPollResult result;
    try {
      result = await widget.pollOnce();
    } catch (_) {
      result = MollieStreetCheckoutPollResult.error;
    }

    if (!mounted || _stopped) return;

    // Latest-wins: discard stale non-paid results when a newer poll started.
    final isStale = myGen != _pollGeneration;
    if (isStale &&
        result.outcome != MollieStreetCheckoutPollOutcome.paid &&
        !_userRefreshPendingFeedback) {
      _polling = false;
      if (_pollQueued) {
        unawaited(_runPoll(source: 'QUEUED'));
      }
      return;
    }

    // Paid always wins — even from a slightly older in-flight response.
    if (_terminal == MollieStreetCheckoutPollOutcome.paid) {
      _polling = false;
      return;
    }

    _polling = false;
    _attempts++;

    final outcome = result.outcome;
    final showUserFeedback =
        userInitiated || _userRefreshPendingFeedback;

    if (molliePollOutcomeIsTerminal(outcome)) {
      _intervalTimer?.cancel();
      _userRefreshPendingFeedback = false;
      _feedbackText = null;
      setState(() => _terminal = outcome);
      _scheduleTerminalPop(outcome);
      return;
    }

    if (showUserFeedback) {
      _userRefreshPendingFeedback = false;
      if (outcome == MollieStreetCheckoutPollOutcome.pending) {
        _feedbackText = widget.copy.processingText;
      } else if (outcome == MollieStreetCheckoutPollOutcome.error) {
        _feedbackText = _feedbackForError(result);
      }
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

    _intervalTimer?.cancel();
    _intervalTimer = Timer(widget.interval, () {
      if (!mounted || _stopped || _terminal != null) return;
      unawaited(_runPoll(source: 'INTERVAL'));
    });
  }

  String _statusText() {
    if (_terminal == null &&
        _feedbackText != null &&
        _feedbackText!.trim().isNotEmpty) {
      return _feedbackText!;
    }
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
    final hasFeedback =
        _feedbackText != null && _feedbackText!.trim().isNotEmpty;
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
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF15803D),
                  size: 18,
                ),
              if (isPaid) const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _statusText(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: isPaid
                        ? const Color(0xFF15803D)
                        : hasFeedback
                        ? const Color(0xFFB45309)
                        : widget.textMutedColor,
                    fontStyle: isPaid || hasFeedback
                        ? FontStyle.normal
                        : FontStyle.italic,
                    fontWeight: isPaid || hasFeedback
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          if (_terminal == null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: (_polling || _cancelBusy)
                  ? null
                  : () => unawaited(refreshNow()),
              child: Text(widget.copy.iHavePaidLabel),
            ),
            if (widget.onCancelOnlinePayment != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.copy.cancelOnlinePaymentHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: widget.textMutedColor,
                ),
              ),
              const SizedBox(height: 6),
              OutlinedButton(
                onPressed: (_polling || _cancelBusy)
                    ? null
                    : () => unawaited(cancelOnlinePaymentNow()),
                child: Text(widget.copy.cancelOnlinePaymentLabel),
              ),
            ],
          ],
        ],
      ],
    );
  }
}
