/// Company-scoped Chiron connection settings (non-secret metadata only).
/// Credentials are stored server-side in a later phase — never in Flutter.
class ChironConnectionEnvironment {
  ChironConnectionEnvironment._();

  static const String test = 'test';
  static const String production = 'production';

  static const Set<String> all = {test, production};
}

class ChironCredentialAuthScheme {
  ChironCredentialAuthScheme._();

  static const String authSchemeApiToken = 'api_token';
}

class ChironConnectionStatus {
  ChironConnectionStatus._();

  static const String notConfigured = 'not_configured';
  static const String testPending = 'test_pending';
  static const String testPassed = 'test_passed';
  static const String testFailed = 'test_failed';
}

/// Server-side `last_connection_status` values (Phase 1 config status API).
class ChironBackendLastConnectionStatus {
  ChironBackendLastConnectionStatus._();

  static const String neverTested = 'never_tested';
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

  /// Maps server `last_connection_status` to local [ChironConnectionStatus].
  static String mapBackendLastConnectionStatus(String raw) {
    final token = raw.trim().toLowerCase();
    switch (token) {
      case ChironConnectionStatus.testPassed:
      case ChironConnectionStatus.testFailed:
      case ChironConnectionStatus.testPending:
        return token;
      case ChironBackendLastConnectionStatus.neverTested:
        return ChironConnectionStatus.notConfigured;
      default:
        return ChironConnectionStatus.notConfigured;
    }
  }

  static bool canEnableProductionFromBackend({
    required bool enabled,
    required String lastConnectionStatus,
  }) {
    return enabled &&
        lastConnectionStatus.trim().toLowerCase() ==
            ChironConnectionStatus.testPassed;
  }
}
