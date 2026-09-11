// COMPANY-CUSTOMER-OPS-P0 — local browser demo of the company dashboard.
//
// flutter run -d chrome --target=lib/company/company_customer_ops_local_demo.dart
//   --web-hostname 127.0.0.1 --web-port 8099
//   --dart-define=BOOKING_BASE_URL=http://127.0.0.1:8788

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_dashboard_page.dart';
import 'package:fluxidi_tracking/company/company_local_bookings_page.dart';
import 'package:fluxidi_tracking/company/company_ops_identity.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  appLanguageNotifier.value = AppLanguage.nl;
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
            builder: (_) => CompanyLocalBookingDetailPage(
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
            builder: (_) => CompanyLocalBookingDetailPage(
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
  applyCompanyOpsHuisstijl(session.companyId);
}
