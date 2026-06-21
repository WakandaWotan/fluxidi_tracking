/// Company-scoped Chiron connection settings (non-secret metadata only).
/// Credentials are stored server-side in a later phase — never in Flutter.
class ChironConnectionEnvironment {
  ChironConnectionEnvironment._();

  static const String test = 'test';
  static const String production = 'production';
}

class ChironConnectionStatus {
  ChironConnectionStatus._();

  static const String notConfigured = 'not_configured';
  static const String testPending = 'test_pending';
  static const String testPassed = 'test_passed';
  static const String testFailed = 'test_failed';
}

class ChironRegionScope {
  ChironRegionScope._();

  static const String flanders = 'flanders';
}

class ChironCompanyConnectionDefaults {
  ChironCompanyConnectionDefaults._();

  static const bool chironEnabled = false;
  static const String chironEnvironment = ChironConnectionEnvironment.test;
  static const String chironConnectionStatus =
      ChironConnectionStatus.notConfigured;
  static const String chironRegionScope = '';
  static const String chironLastTestedAt = '';
  static const bool chironProductionEnabled = false;

  static bool canEnableProduction({
    required bool chironEnabled,
    required String connectionStatus,
  }) {
    return chironEnabled &&
        connectionStatus == ChironConnectionStatus.testPassed;
  }
}
