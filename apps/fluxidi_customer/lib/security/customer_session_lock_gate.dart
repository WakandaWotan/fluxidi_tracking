import 'dart:async';

import 'package:flutter/material.dart';

import '../app/customer_labels.dart';
import '../app/customer_theme.dart';
import 'customer_device_unlock.dart';
import 'customer_session_lock.dart';

/// Cover shown while the customer session is locked.
///
/// The OS dialog does the actual recognition. This page only retries or
/// explains cancel / failure. It never invents a Fluxidi PIN field.
class CustomerSessionLockGate extends StatefulWidget {
  const CustomerSessionLockGate({
    super.key,
    required this.lock,
    this.autoPrompt = true,
  });

  final CustomerSessionLock lock;
  final bool autoPrompt;

  @override
  State<CustomerSessionLockGate> createState() => _CustomerSessionLockGateState();
}

class _CustomerSessionLockGateState extends State<CustomerSessionLockGate> {
  bool _busy = false;
  CustomerUnlockResult? _last;

  @override
  void initState() {
    super.initState();
    if (widget.autoPrompt) {
      unawaited(_prompt());
    }
  }

  Future<void> _prompt() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _last = null;
    });
    final result = await widget.lock.unlock(
      reason: CustomerText.unlockReasonOpen.current,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _last = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = activeCustomerPalette();
    final theme = Theme.of(context);
    final message = switch (_last) {
      CustomerUnlockResult.canceled => CustomerText.unlockCanceled.current,
      CustomerUnlockResult.failed => CustomerText.unlockFailed.current,
      CustomerUnlockResult.unavailable => CustomerText.unlockUnavailable.current,
      _ => CustomerText.unlockGateBody.current,
    };

    return Material(
      color: palette.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            children: <Widget>[
              const Spacer(),
              Icon(Icons.lock_outline, size: 48, color: palette.gold),
              const SizedBox(height: 20),
              Text(
                CustomerText.unlockGateTitle.current,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.textMuted,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('customer_unlock_retry'),
                  onPressed: _busy ? null : () => unawaited(_prompt()),
                  child: Text(CustomerText.unlockRetry.current),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
