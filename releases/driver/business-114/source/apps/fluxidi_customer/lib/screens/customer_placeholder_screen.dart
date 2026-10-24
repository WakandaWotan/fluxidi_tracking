import 'package:flutter/material.dart';

import '../app/customer_app_config.dart';

/// Temporary screen for a customer feature that is not wired up yet.
///
/// Shows no rides, no prices, no account state and offers no payment action.
class CustomerPlaceholderScreen extends StatelessWidget {
  const CustomerPlaceholderScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.pending,
    this.config = kCustomerAppConfig,
  });

  final String title;
  final IconData icon;

  /// What this screen will offer once it is connected.
  final List<String> pending;

  final CustomerAppConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(icon, size: 40, color: theme.colorScheme.primary),
                  const SizedBox(height: 14),
                  Text(
                    'Nog niet aangesloten',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Dit onderdeel wordt in een volgende fase aangesloten op '
                    'de bestaande Fluxidi-diensten. Er worden hier bewust geen '
                    'ritten, prijzen of klantgegevens getoond.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: config.brand.textSoft,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Wat hier later komt',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final item in pending)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(top: 6, right: 8),
                            child: Icon(
                              Icons.circle,
                              size: 6,
                              color: config.brand.textSoft,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              item,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: config.brand.textSoft,
                              ),
                            ),
                          ),
                        ],
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
