import 'business_theme_company_scope_stub.dart'
    if (dart.library.io) 'business_theme_company_scope_io.dart' as impl;

/// Company id from the existing [activeCompanySessionNotifier], when present.
String? readActiveCompanySessionId() => impl.readActiveCompanySessionId();

/// Listens to company-session changes so scoped themes stay isolated.
void listenToActiveCompanySession(void Function() listener) {
  impl.listenToActiveCompanySession(listener);
}
