// COMPANY-CUSTOMER-OPS-P0 — local browser adapter of the company dashboard.
//
// The browser path is not the product definition of the full Windows app.
// Full app-shell: scripts/start_local_customer_ops_windows.ps1 (main.dart).
//
// flutter run -d chrome --target=lib/company/company_customer_ops_local_demo.dart
//   --web-hostname 127.0.0.1 --web-port 8099
//   --dart-define=BOOKING_BASE_URL=http://127.0.0.1:8788

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/company/company_booking_detail_page.dart';
import 'package:fluxidi_tracking/company/company_dashboard_page.dart';
import 'package:fluxidi_tracking/company/company_ops_identity.dart';
import 'package:fluxidi_tracking/company/company_ops_theme_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Flutter web uses CanvasKit. Real Chrome paints glyphs correctly; some
  // automation screenshot hosts sample the glyph atlas and look unreadable.
  SemanticsBinding.instance.ensureSemantics();
  appLanguageNotifier.value = AppLanguage.nl;
  registerCompanyOpsThemeRemoteSync();
  await loadBusinessThemePreference();
  runApp(const CompanyCustomerOpsLocalDemoApp());
}

class CompanyCustomerOpsLocalDemoApp extends StatelessWidget {
  const CompanyCustomerOpsLocalDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: true,
      title: 'Bedrijfsdashboard lokaal',
      onGenerateRoute: (settings) {
        final bookingFromQuery =
            Uri.base.queryParameters['booking']?.trim() ?? '';
        if (bookingFromQuery.isNotEmpty) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => CompanyBookingDetailPage(
              bookingId: bookingFromQuery,
              language: AppLanguage.nl,
            ),
          );
        }
        final name = settings.name ?? '/';
        if (name.startsWith('/bookings/')) {
          final bookingId = Uri.decodeComponent(
            name.substring('/bookings/'.length),
          );
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => CompanyBookingDetailPage(
              bookingId: bookingId,
              language: AppLanguage.nl,
            ),
          );
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const CompanyDashboardPage(
            language: AppLanguage.nl,
          ),
        );
      },
    );
  }
}

Future<void> activateCompanyOpsLocalSession(
  CompanyOpsLocalSession session,
) async {
  beginCompanyOpsContextClear();
  companyOpsLocalSessionNotifier.value = session;
  bindBusinessThemeCompanyScope(session.companyId);
}
