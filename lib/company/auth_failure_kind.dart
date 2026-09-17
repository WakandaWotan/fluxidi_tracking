/// Maps remote auth failures to a stable UI code.
///
/// Distinguishes network, missing local route, wrong environment, and a
/// genuinely expired or incorrect verification code. Never carries tokens.
enum AuthFailureKind {
  networkError,
  localWorkerUnreachable,
  routeMissing,
  wrongEnvironment,
  companyNotFound,
  invalidCompanyCode,
  invalidPairingCode,
  verificationFailed,
  smsNotConfigured,
  localSmsUnavailable,
  unsupportedPhoneRegion,
  rateLimited,
  invalidPhone,
  emailNotLinked,
  generic,
}

String authFailureCode(AuthFailureKind kind) {
  switch (kind) {
    case AuthFailureKind.networkError:
      return 'network_error';
    case AuthFailureKind.localWorkerUnreachable:
      return 'local_worker_unreachable';
    case AuthFailureKind.routeMissing:
      return 'route_missing';
    case AuthFailureKind.wrongEnvironment:
      return 'wrong_environment';
    case AuthFailureKind.companyNotFound:
      return 'company_not_found';
    case AuthFailureKind.invalidCompanyCode:
      return 'invalid_company_code';
    case AuthFailureKind.invalidPairingCode:
      return 'invalid_pairing_code';
    case AuthFailureKind.verificationFailed:
      return 'verification_failed';
    case AuthFailureKind.smsNotConfigured:
      return 'sms_not_configured';
    case AuthFailureKind.localSmsUnavailable:
      return 'local_sms_unavailable';
    case AuthFailureKind.unsupportedPhoneRegion:
      return 'unsupported_phone_region';
    case AuthFailureKind.rateLimited:
      return 'rate_limited';
    case AuthFailureKind.invalidPhone:
      return 'invalid_phone';
    case AuthFailureKind.emailNotLinked:
      return 'email_not_linked';
    case AuthFailureKind.generic:
      return 'generic';
  }
}

AuthFailureKind classifyRemoteAuthFailure({
  int? statusCode,
  String error = '',
  bool networkException = false,
  bool loopbackHost = false,
  bool companyResolvable = false,
  bool customerAuth = false,
}) {
  if (networkException) {
    return loopbackHost
        ? AuthFailureKind.localWorkerUnreachable
        : AuthFailureKind.networkError;
  }
  final err = error.trim().toLowerCase();
  if (err == 'invalid_company_code') return AuthFailureKind.invalidCompanyCode;
  if (err == 'invalid_pairing_code' || err == 'invalid_body') {
    return AuthFailureKind.invalidPairingCode;
  }
  if (err == 'unsupported_phone_region') {
    return AuthFailureKind.unsupportedPhoneRegion;
  }
  if (err == 'rate_limited') return AuthFailureKind.rateLimited;
  if (err == 'invalid_phone') return AuthFailureKind.invalidPhone;
  if (err == 'email_not_linked') return AuthFailureKind.emailNotLinked;
  if (err == 'sms_not_configured' || err == 'sms_send_failed') {
    return loopbackHost
        ? AuthFailureKind.localSmsUnavailable
        : AuthFailureKind.smsNotConfigured;
  }
  if (err == 'company_not_found' || statusCode == 404) {
    if (loopbackHost) return AuthFailureKind.wrongEnvironment;
    return statusCode == 404 && err.isEmpty
        ? AuthFailureKind.routeMissing
        : AuthFailureKind.companyNotFound;
  }
  // Customer phone/email OTP: a 403 or generic verify/persist miss is a
  // wrong or already-used code, not "this number does not belong here".
  if (customerAuth &&
      (err == 'verification_failed' ||
          err == 'customer_phone_auth_verify_failed' ||
          err == 'customer_email_auth_verify_failed' ||
          err == 'session_missing' ||
          statusCode == 403)) {
    return AuthFailureKind.verificationFailed;
  }
  if (loopbackHost &&
      !companyResolvable &&
      !customerAuth &&
      (err == 'verification_failed' || err.isEmpty || statusCode == 403)) {
    return AuthFailureKind.wrongEnvironment;
  }
  if (err == 'verification_failed' || statusCode == 403) {
    return AuthFailureKind.verificationFailed;
  }
  if (err.isEmpty) return AuthFailureKind.generic;
  if (err == 'wrong_environment') return AuthFailureKind.wrongEnvironment;
  if (err == 'network_error') return AuthFailureKind.networkError;
  if (err == 'local_worker_unreachable') {
    return AuthFailureKind.localWorkerUnreachable;
  }
  if (err == 'route_missing') return AuthFailureKind.routeMissing;
  return AuthFailureKind.generic;
}

AuthFailureKind classifyThrownAuthFailure(
  Object error, {
  required bool loopbackHost,
  bool customerAuth = false,
}) {
  final text = error.toString().toLowerCase();
  final network =
      text.contains('socket') ||
      text.contains('timeout') ||
      text.contains('failed host lookup') ||
      text.contains('connection refused') ||
      text.contains('connection errored') ||
      text.contains('xmlhttprequest') ||
      text.contains('geweigerd') ||
      text.contains('errno = 1225') ||
      text.contains('errno=1225');
  String code = '';
  for (final candidate in <String>[
    'sms_not_configured',
    'sms_send_failed',
    'unsupported_phone_region',
    'rate_limited',
    'invalid_phone',
    'email_not_linked',
    'company_not_found',
    'customer_phone_auth_verify_failed',
    'customer_email_auth_verify_failed',
    'session_missing',
    'verification_failed',
    'invalid_company_code',
    'invalid_pairing_code',
  ]) {
    if (text.contains(candidate)) {
      code = candidate;
      break;
    }
  }
  return classifyRemoteAuthFailure(
    error: code,
    networkException: network,
    loopbackHost: loopbackHost,
    customerAuth: customerAuth,
  );
}

String describePublicAuthHost(String rawUrl) {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null || !uri.hasScheme) return 'unset';
  final port = uri.hasPort
      ? uri.port
      : (uri.scheme == 'https' ? 443 : 80);
  return '${uri.scheme}://${uri.host}:$port';
}
