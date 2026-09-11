// COMPANY-CUSTOMER-OPS-P0 — local browser demo of Klantenbeheer.
//
// flutter run -d chrome --target=lib/company/company_customer_ops_local_demo.dart
//   --web-hostname 127.0.0.1 --web-port 8099
//   --dart-define=BOOKING_BASE_URL=http://127.0.0.1:8788
//   --dart-define=COMPANY_SESSION_TOKEN=cst_local_demo_synthetic
//   --dart-define=FLUXIDI_DEV_COMPANY_ID=demo_company_p0

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_customer_import_models.dart';
import 'package:fluxidi_tracking/company/company_customers_page.dart';
import 'package:fluxidi_tracking/company/company_customers_repository_factory_web.dart';
import 'package:fluxidi_tracking/company/company_local_bookings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  appLanguageNotifier.value = AppLanguage.nl;
  final sample = await _loadSyntheticCustomersFile();
  runApp(CompanyCustomerOpsLocalDemoApp(sampleFile: sample));
}

Future<CompanyCustomerImportPickedFile> _loadSyntheticCustomersFile() async {
  final res = await http.get(
    Uri.parse('$kCompanyCustomerOpsLocalDemoBaseUrl/local/contacts_demo.csv'),
  );
  if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
    throw StateError('synthetic customer file missing');
  }
  return CompanyCustomerImportPickedFile(
    name: 'contacts_demo.csv',
    bytes: res.bodyBytes,
  );
}

class CompanyCustomerOpsLocalDemoApp extends StatelessWidget {
  const CompanyCustomerOpsLocalDemoApp({super.key, required this.sampleFile});

  final CompanyCustomerImportPickedFile sampleFile;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: true,
      title: 'Klantenbeheer lokaal',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1C2430)),
        useMaterial3: true,
      ),
      onGenerateRoute: (settings) {
        final bookingFromQuery = Uri.base.queryParameters['booking']?.trim() ?? '';
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
        if (name == '/bookings') {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const CompanyLocalBookingsPage(
              language: AppLanguage.nl,
            ),
          );
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => CompanyCustomerOpsLocalDemoShell(
            sampleFile: sampleFile,
          ),
        );
      },
    );
  }
}

class CompanyCustomerOpsLocalDemoShell extends StatefulWidget {
  const CompanyCustomerOpsLocalDemoShell({super.key, required this.sampleFile});

  final CompanyCustomerImportPickedFile sampleFile;

  @override
  State<CompanyCustomerOpsLocalDemoShell> createState() =>
      _CompanyCustomerOpsLocalDemoShellState();
}

class _CompanyCustomerOpsLocalDemoShellState
    extends State<CompanyCustomerOpsLocalDemoShell> {
  int _index = Uri.base.queryParameters['tab'] == 'bookings' ? 1 : 0;
  int _bookingsGen = 0;

  void _openBooking(String bookingId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CompanyLocalBookingDetailPage(
          bookingId: bookingId,
          language: AppLanguage.nl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          CompanyCustomersPage(
            language: AppLanguage.nl,
            issuerName: 'Fluxidi Demo Cars',
            repository: createCompanyCustomersRepository(),
            sessionStore: createCompanyCustomerImportSessionStore(),
            initialImportFile: widget.sampleFile,
            importPicker: () async => widget.sampleFile,
            onOpenBooking: _openBooking,
          ),
          CompanyLocalBookingsPage(
            key: ValueKey<int>(_bookingsGen),
            language: AppLanguage.nl,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        key: kCompanyLocalBookingsNavKey,
        selectedIndex: _index,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            label: 'Klanten',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            label: 'Boekingen',
          ),
        ],
        onDestinationSelected: (index) {
          setState(() {
            _index = index;
            if (index == 1) _bookingsGen += 1;
          });
        },
      ),
    );
  }
}
