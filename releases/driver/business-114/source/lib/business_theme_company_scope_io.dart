import 'company_session_store.dart';

String? readActiveCompanySessionId() {
  final id = (activeCompanySessionNotifier.value?.companyId ?? '').trim();
  return id.isEmpty ? null : id;
}

void listenToActiveCompanySession(void Function() listener) {
  activeCompanySessionNotifier.addListener(listener);
}
