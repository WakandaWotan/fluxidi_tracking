import 'package:flutter/material.dart';

import '../app_strings.dart';
import '../customer_theme_palette.dart';
import '../customer_theme_store.dart';
import '../limousine/limousine_p2d4c1a_ux.dart';
import 'private_chauffeur_capability.dart';
import 'private_chauffeur_labels.dart';

const Key kPrivateChauffeurSelectionPageKey = ValueKey<String>(
  'private_chauffeur_selection_page',
);
const Key kPrivateChauffeurSelectedCompanyKey = ValueKey<String>(
  'private_chauffeur_selected_company',
);
const Key kPrivateChauffeurSelectedServiceKey = ValueKey<String>(
  'private_chauffeur_selected_service',
);
const Key kPrivateChauffeurSelectedPartnerKey = ValueKey<String>(
  'private_chauffeur_selected_partner',
);

class PrivateChauffeurSelection {
  const PrivateChauffeurSelection({
    required this.publicPartnerId,
    required this.companyName,
    required this.serviceCode,
  });

  final String publicPartnerId;
  final String companyName;

  /// Always [kPrivateChauffeurServiceCode] for this flow.
  final String serviceCode;
}

/// Holds the chosen company and service. Does not quote or book.
class PrivateChauffeurSelectionPage extends StatelessWidget {
  const PrivateChauffeurSelectionPage({super.key, required this.selection});

  final PrivateChauffeurSelection selection;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, language, _) {
        return ValueListenableBuilder<CustomerThemeVariant>(
          valueListenable: customerThemeNotifier,
          builder: (context, variant, _) {
            final palette = paletteForCustomerTheme(variant);
            final tokens = LimousineUxTokens.fromCustomer(palette);
            assert(selection.serviceCode == kPrivateChauffeurServiceCode);
            return Scaffold(
              key: kPrivateChauffeurSelectionPageKey,
              backgroundColor: tokens.background,
              appBar: AppBar(
                backgroundColor: tokens.background,
                foregroundColor: tokens.onSurface,
                title: Text(kPrivateChauffeurTitle.of(language)),
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  Text(
                    selection.companyName,
                    key: kPrivateChauffeurSelectedCompanyKey,
                    style: TextStyle(
                      color: tokens.onSurface,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${kPrivateChauffeurServiceLine.of(language)}: ${kPrivateChauffeurTitle.of(language)}',
                    key: kPrivateChauffeurSelectedServiceKey,
                    style: TextStyle(color: tokens.onSurface, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selection.publicPartnerId,
                    key: kPrivateChauffeurSelectedPartnerKey,
                    style: TextStyle(color: tokens.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    kPrivateChauffeurSelectionIntro.of(language),
                    style: TextStyle(
                      color: tokens.onSurface,
                      height: 1.4,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    kPrivateChauffeurSelectionHold.of(language),
                    style: TextStyle(
                      color: tokens.muted,
                      height: 1.45,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
