import 'package:flutter/material.dart';

import '../app/customer_app_config.dart';
import '../app/customer_labels.dart';
import '../app/customer_theme.dart';

/// Neutral screen opened when the app is reached through its own
/// payment-return link.
///
/// It states nothing about a payment. Link query parameters are never read or
/// shown: a return link is a navigation trigger, not a result. Once payments
/// are wired up, status must come from an authenticated server read.
class CustomerPaymentReturnScreen extends StatelessWidget {
  const CustomerPaymentReturnScreen({
    super.key,
    this.config = kCustomerAppConfig,
    this.onClose,
  });

  final CustomerAppConfig config;

  /// Closes this screen. Falls back to popping when no callback is given.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return CustomerLanguageBuilder(
      builder: (context, language) {
        final theme = Theme.of(context);
        final palette = activeCustomerPalette();
        return Scaffold(
          backgroundColor: palette.background,
          appBar: AppBar(
            title: Text(CustomerText.paymentReturnTitle.of(language)),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.open_in_new_outlined,
                        size: 40,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        CustomerText.paymentReturnHeadline.of(language),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        CustomerText.paymentReturnBody.of(language),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: palette.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              CustomerText.paymentReturnWhyTitle.of(language),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              CustomerText.paymentReturnWhyBody.of(language),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(
                          key: const Key('payment_return_close'),
                          onPressed: onClose ??
                              () => Navigator.of(context).maybePop(),
                          child: Text(
                            CustomerText.paymentReturnClose.of(language),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
