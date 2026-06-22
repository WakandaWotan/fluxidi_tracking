import 'package:flutter/material.dart';

/// Builds the company chauffeur management screen.
///
/// The implementation lives in [main.dart] parts today. [main.dart] registers
/// the builder at startup so other features (e.g. Chiron readiness) can open
/// chauffeurbeheer without importing [main.dart].
typedef CompanyDriverManagementPageBuilder = Widget Function();

CompanyDriverManagementPageBuilder? _companyDriverManagementPageBuilder;

/// Called once from [main.dart] during app startup.
void registerCompanyDriverManagementPageBuilder(
  CompanyDriverManagementPageBuilder builder,
) {
  _companyDriverManagementPageBuilder = builder;
}

/// Returns the registered chauffeur management page.
Widget companyDriverManagementPage() {
  final builder = _companyDriverManagementPageBuilder;
  if (builder == null) {
    assert(() {
      debugPrint(
        '[COMPANY_DRIVER_MANAGEMENT] builder not registered; '
        'call registerCompanyDriverManagementPageBuilder from main.dart',
      );
      return true;
    }());
    return const SizedBox.shrink();
  }
  return builder();
}
