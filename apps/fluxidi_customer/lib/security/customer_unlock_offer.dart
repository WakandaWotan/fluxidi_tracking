import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';

import '../app/customer_labels.dart';
import 'customer_session_lock.dart';

/// Offers device unlock once, after a successful sign-in.
Future<void> offerCustomerDeviceUnlockAfterSignIn(
  BuildContext context, {
  CustomerSessionLock? lock,
}) async {
  final coordinator = lock ?? CustomerSessionLock.instance;
  if (coordinator.isEnabled) return;
  if (!await coordinator.canProtectDevice()) return;
  if (!context.mounted) return;

  final language = currentCustomerLanguage();
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        key: const Key('customer_unlock_offer_dialog'),
        title: Text(CustomerText.unlockOfferTitle.of(language)),
        content: Text(CustomerText.unlockOfferBody.of(language)),
        actions: <Widget>[
          TextButton(
            key: const Key('customer_unlock_offer_later'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(CustomerText.unlockOfferLater.of(language)),
          ),
          FilledButton(
            key: const Key('customer_unlock_offer_enable'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(CustomerText.unlockOfferEnable.of(language)),
          ),
        ],
      );
    },
  );
  if (accepted != true || !context.mounted) return;
  await coordinator.enableAfterAuthentication(
    reason: CustomerText.unlockReasonEnable.of(language),
  );
}

AppLanguage currentCustomerLanguage() {
  return appLanguageNotifier.value;
}
