import 'package:flutter/material.dart';

import '../app/customer_app_config.dart';

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
  });

  final CustomerAppConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Terug in de app')),
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
                    'Je bent terug in de app',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Deze app heeft een terugkeerlink ontvangen op het eigen '
                    'developmentscheme. Er is in deze fase geen betaling, '
                    'boeking of status aan verbonden.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: config.brand.textSoft,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: config.brand.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Waarom hier geen status staat',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Een terugkeerlink is geen betaalbewijs. Een '
                          'betaalstatus mag later alleen van de server komen, '
                          'nooit uit de link zelf.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: config.brand.textSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Naar het startscherm'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
