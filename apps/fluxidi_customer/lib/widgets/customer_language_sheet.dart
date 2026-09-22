import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';

import '../app/customer_labels.dart';
import '../app/customer_theme.dart';
import '../bridge/customer_language.dart';

/// Language picker over the existing app languages.
Future<void> showCustomerLanguageSheet(BuildContext context) async {
  final palette = activeCustomerPalette();
  final current = appConfig.currentLanguage;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  CustomerText.language.current,
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                ),
              ),
            ),
            for (final language in kCustomerLanguages)
              ListTile(
                key: Key('customer_language_${language.name}'),
                title: Text(
                  kCustomerLanguageLabels[language] ?? language.name,
                  style: TextStyle(color: palette.textPrimary),
                ),
                trailing: language == current
                    ? Icon(Icons.check, color: palette.gold)
                    : null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(saveCustomerLanguagePreference(language));
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
