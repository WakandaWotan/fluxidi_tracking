// COMPANY-CUSTOMER-OPS-P0 — honest web blocker, never a success stand-in.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_dashboard_tiles.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';

const Key kCompanyDashboardUnavailablePageKey = Key(
  'company_dashboard_unavailable_page',
);
const Key kCompanyDashboardUnavailableBlockerKey = Key(
  'company_dashboard_unavailable_blocker',
);

class CompanyDashboardUnavailablePage extends StatelessWidget {
  const CompanyDashboardUnavailablePage({
    super.key,
    required this.tile,
    this.language,
  });

  final CompanyDashboardTileSpec tile;
  final AppLanguage? language;

  @override
  Widget build(BuildContext context) {
    final lang = language ?? appLanguageNotifier.value;
    final blocker = tile.blocker?.of(lang) ?? '';
    return CompanyOpsThemedSurface(
      child: Scaffold(
        key: kCompanyDashboardUnavailablePageKey,
        appBar: AppBar(title: Text(tile.title.of(lang))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text(
              tile.title.of(lang),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(tile.subtitle.of(lang)),
            const SizedBox(height: 16),
            Text(
              blocker,
              key: kCompanyDashboardUnavailableBlockerKey,
            ),
          ],
        ),
      ),
    );
  }
}
