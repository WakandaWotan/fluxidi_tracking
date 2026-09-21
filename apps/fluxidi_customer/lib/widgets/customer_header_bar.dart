import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';

import '../app/customer_app_config.dart';
import '../app/customer_theme.dart';
import '../bridge/customer_flows.dart';
import '../bridge/customer_language.dart';
import 'customer_language_sheet.dart';

/// Top of the customer screens: the real Fluxidi logo, the language choice and
/// the palette button that opens the full existing theme picker.
class CustomerHeaderBar extends StatelessWidget {
  const CustomerHeaderBar({
    super.key,
    this.config = kCustomerAppConfig,
    this.showEnvironmentLabel = true,
  });

  final CustomerAppConfig config;
  final bool showEnvironmentLabel;

  @override
  Widget build(BuildContext context) {
    final palette = activeCustomerPalette();
    final language = appConfig.currentLanguage;
    return Row(
      children: <Widget>[
        // Two logo files exist; the gold one is the readable version on a dark
        // palette, the dark one on a light palette.
        Image.asset(
          palette.isDark
              ? 'assets/fluxidi/fluxidi_logo_horizontal_gold.png'
              : 'assets/fluxidi/fluxidi_logo_horizontal_dark.png',
          height: 30,
          fit: BoxFit.contain,
        ),
        if (showEnvironmentLabel) ...<Widget>[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: palette.gold.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: palette.gold.withValues(alpha: 0.5)),
            ),
            child: Text(
              config.environmentLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: palette.gold,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
        const Spacer(),
        TextButton(
          key: const Key('customer_header_language'),
          onPressed: () => unawaited(showCustomerLanguageSheet(context)),
          child: Text(
            kCustomerLanguageShortLabels[language] ?? language.name.toUpperCase(),
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          key: const Key('customer_header_palette'),
          tooltip: 'Thema',
          icon: Icon(Icons.palette_outlined, color: palette.textPrimary),
          onPressed: () => unawaited(openThemePicker(context)),
        ),
      ],
    );
  }
}
