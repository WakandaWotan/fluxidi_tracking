import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_ops_api.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';
import 'package:fluxidi_tracking/company/company_ops_identity.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

import 'company_public_booking_link.dart';
import 'company_public_booking_link_view.dart';
import 'active_company_booking_link_view.dart';

const Key kCompanyBookingLinkPageKey = Key('company_booking_link_page');
const Key kCompanyBookingLinkUrlKey = Key('company_booking_link_url');

class CompanyBookingLinkPage extends StatefulWidget {
  const CompanyBookingLinkPage({
    super.key,
    this.language,
    this.profileLoader,
    this.contextLoader,
    this.companyId,
  });

  final AppLanguage? language;
  final Future<Map<String, dynamic>> Function()? profileLoader;
  final CompanyBookingContextLoader? contextLoader;
  final String? companyId;

  @override
  State<CompanyBookingLinkPage> createState() => _CompanyBookingLinkPageState();
}

class _CompanyBookingLinkPageState extends State<CompanyBookingLinkPage> {
  late final String _companyId;
  late final String _sessionToken;

  @override
  void initState() {
    super.initState();
    final session = resolveCompanyOpsLocalSession();
    _companyId = widget.companyId ?? session.companyId;
    _sessionToken = session.sessionToken;
  }

  bool _scopeIsCurrent() {
    if (widget.companyId != null) return widget.companyId == _companyId;
    final session = resolveCompanyOpsLocalSession();
    return session.companyId == _companyId &&
        session.sessionToken == _sessionToken;
  }

  @override
  Widget build(BuildContext context) => CompanyOpsThemedSurface(
    child: Scaffold(
      key: kCompanyBookingLinkPageKey,
      appBar: AppBar(
        title: Text(switch (widget.language ?? AppLanguage.nl) {
          AppLanguage.nl => 'Deel boekingslink',
          AppLanguage.en => 'Share booking link',
          AppLanguage.fr => 'Partager le lien de réservation',
          AppLanguage.es => 'Compartir enlace de reserva',
          AppLanguage.de => 'Buchungslink teilen',
        }),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.profileLoader == null &&
              widget.contextLoader == null &&
              widget.companyId == null &&
              _sessionToken.isEmpty &&
              activeDriverSessionNotifier.value != null)
            ActiveCompanyBookingLinkView(
              language: widget.language ?? AppLanguage.nl,
            )
          else
            ListenableBuilder(
              listenable: Listenable.merge([
                activeCompanySessionNotifier,
                companyOpsLocalSessionNotifier,
              ]),
              builder: (context, _) => CompanyPublicBookingLinkView(
                language: widget.language ?? AppLanguage.nl,
                urlKey: kCompanyBookingLinkUrlKey,
                scopeIsCurrent: _scopeIsCurrent,
                loader: () => resolveCompanyPublicBookingLink(
                  expectedCompanyId: _companyId,
                  profileLoader:
                      widget.profileLoader ?? fetchCompanyOpsBusinessProfile,
                  contextLoader:
                      widget.contextLoader ?? fetchCompanyBookingContext,
                  scopeIsCurrent: _scopeIsCurrent,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
