// NAV-DIRECTIONS-FAILURE-SECURITY-AND-RECOVERY-1
//
// One authoritative, dependency-light place that turns a caught route/geocode
// exception into (a) a coarse PII-free classification, (b) a redacted
// diagnostic string safe for logs, and (c) concise localized driver copy.
//
// It NEVER exposes or retains: access tokens, full request URIs, exact
// coordinates, addresses, raw response bodies, or trip/customer identifiers.
// The raw exception object is inspected transiently and only its *type* +
// redacted class/message shape are used — the caught object is never stored,
// logged verbatim, or shown to the driver.

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../app_strings.dart';
import 'driver_navigation_formatters.dart';

/// Coarse route-failure classes. Deliberately small and PII-free.
enum NavRouteErrorKind {
  dnsFailure,
  offline,
  timeout,
  connectionReset,
  http401or403,
  http429,
  server5xx,
  invalidResponse,
  unknown,
}

/// Short stable code for bounded diagnostics/logs (never user-facing raw text).
String navRouteErrorCode(NavRouteErrorKind kind) {
  switch (kind) {
    case NavRouteErrorKind.dnsFailure:
      return 'dns_failure';
    case NavRouteErrorKind.offline:
      return 'offline';
    case NavRouteErrorKind.timeout:
      return 'timeout';
    case NavRouteErrorKind.connectionReset:
      return 'connection_reset';
    case NavRouteErrorKind.http401or403:
      return 'http_401_or_403';
    case NavRouteErrorKind.http429:
      return 'http_429';
    case NavRouteErrorKind.server5xx:
      return 'server_5xx';
    case NavRouteErrorKind.invalidResponse:
      return 'invalid_response';
    case NavRouteErrorKind.unknown:
      return 'unknown';
  }
}

/// Classifies an HTTP status code into a route-error class, or null when the
/// status is not itself an error (2xx).
NavRouteErrorKind? classifyNavRouteHttpStatus(int statusCode) {
  if (statusCode >= 200 && statusCode < 300) return null;
  if (statusCode == 401 || statusCode == 403) {
    return NavRouteErrorKind.http401or403;
  }
  if (statusCode == 429) return NavRouteErrorKind.http429;
  if (statusCode >= 500 && statusCode < 600) return NavRouteErrorKind.server5xx;
  return NavRouteErrorKind.invalidResponse;
}

/// Classifies an arbitrary caught error/exception WITHOUT retaining it.
///
/// The message is only pattern-matched for well-known transient signatures
/// (host lookup, connection reset, network unreachable). It is never returned
/// or stored.
NavRouteErrorKind classifyNavRouteError(Object? error) {
  if (error is NavRouteHttpStatusException) {
    return classifyNavRouteHttpStatus(error.statusCode) ??
        NavRouteErrorKind.invalidResponse;
  }
  if (error is TimeoutException) return NavRouteErrorKind.timeout;
  if (error is FormatException) return NavRouteErrorKind.invalidResponse;

  if (error is SocketException) {
    return _classifySocketMessage(error.osError?.message, error.message);
  }
  if (error is http.ClientException) {
    // package:http wraps io SocketExceptions; the message carries the cause but
    // may also carry a uri= suffix — we only read it to pattern-match, never
    // surface it.
    return _classifyClientExceptionMessage(error.message);
  }
  if (error is HttpException) return NavRouteErrorKind.invalidResponse;

  // Fall back to a bounded string sniff for platform errors that are not typed
  // (e.g. dart:io errors surfaced as generic objects on some platforms).
  final lower = error?.toString().toLowerCase() ?? '';
  final sniffed = _sniffMessage(lower);
  return sniffed ?? NavRouteErrorKind.unknown;
}

NavRouteErrorKind _classifyClientExceptionMessage(String message) {
  final lower = message.toLowerCase();
  return _sniffMessage(lower) ?? NavRouteErrorKind.unknown;
}

NavRouteErrorKind _classifySocketMessage(String? osMessage, String? message) {
  final lower = '${osMessage ?? ''} ${message ?? ''}'.toLowerCase();
  return _sniffMessage(lower) ?? NavRouteErrorKind.offline;
}

NavRouteErrorKind? _sniffMessage(String lower) {
  if (lower.contains('failed host lookup') ||
      lower.contains('no address associated with hostname') ||
      lower.contains('nodename nor servname') ||
      lower.contains('errno = 7') ||
      lower.contains('name or service not known')) {
    return NavRouteErrorKind.dnsFailure;
  }
  if (lower.contains('connection reset') ||
      lower.contains('connection closed') ||
      lower.contains('broken pipe') ||
      lower.contains('connection terminated')) {
    return NavRouteErrorKind.connectionReset;
  }
  if (lower.contains('network is unreachable') ||
      lower.contains('no route to host') ||
      lower.contains('network is down') ||
      lower.contains('socketexception') ||
      lower.contains('connection refused') ||
      lower.contains('connection timed out')) {
    return NavRouteErrorKind.offline;
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return NavRouteErrorKind.timeout;
  }
  return null;
}

/// Non-2xx HTTP status raised by the route/geocode fetch layer. Carries only
/// the numeric status (no body, no URI).
class NavRouteHttpStatusException implements Exception {
  const NavRouteHttpStatusException(this.statusCode);
  final int statusCode;
  @override
  String toString() => 'NavRouteHttpStatusException($statusCode)';
}

final RegExp _tokenParamRe = RegExp(r'access_token=[^&\s"\)]+', caseSensitive: false);
final RegExp _pkTokenRe = RegExp(r'\b(?:pk|sk|tk)\.[A-Za-z0-9._\-]+');
final RegExp _mapboxUriRe = RegExp(
  r'https?://[^\s"\)]*mapbox[^\s"\)]*',
  caseSensitive: false,
);
final RegExp _genericUriRe = RegExp(r'https?://[^\s"\)]+', caseSensitive: false);
final RegExp _mapboxHostRe = RegExp(
  r"[a-z0-9.-]*mapbox\.com",
  caseSensitive: false,
);
final RegExp _coordPairRe = RegExp(
  r'-?\d{1,3}\.\d{3,},-?\d{1,3}\.\d{3,}',
);
final RegExp _uriEqSuffixRe = RegExp(r',?\s*uri=\S+', caseSensitive: false);

/// Redacts any token, mapbox URI, generic URL, `uri=` suffix, and decimal
/// coordinate pair from a diagnostic string so it is safe to log. Never used to
/// build user-facing copy (that comes from [navRouteErrorMessage]).
String redactNavRouteDiagnostic(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  var out = raw;
  out = out.replaceAll(_uriEqSuffixRe, ' uri=[redacted]');
  out = out.replaceAll(_tokenParamRe, 'access_token=[redacted]');
  out = out.replaceAll(_mapboxUriRe, '[redacted-url]');
  out = out.replaceAll(_genericUriRe, '[redacted-url]');
  out = out.replaceAll(_mapboxHostRe, '[redacted-host]');
  out = out.replaceAll(_pkTokenRe, '[redacted-token]');
  out = out.replaceAll(_coordPairRe, '[redacted-coords]');
  return out.trim();
}

/// Localized, concise driver copy for a route failure. Title only — never a
/// stack trace, class name, URL, token or coordinate.
class NavRouteErrorCopy {
  const NavRouteErrorCopy({
    required this.message,
    required this.retryLabel,
    required this.dismissLabel,
  });
  final String message;
  final String retryLabel;
  final String dismissLabel;
}

/// Builds localized copy for a route-error class using the app's translate
/// callback (same locale source as the navigation UI).
NavRouteErrorCopy navRouteErrorMessage(
  NavRouteErrorKind kind, {
  required DriverNavTranslate tr,
}) {
  final retryLabel = tr(
    nl: 'Opnieuw proberen',
    en: 'Retry',
    fr: 'Réessayer',
    es: 'Reintentar',
  );
  final dismissLabel = tr(
    nl: 'Sluiten',
    en: 'Close',
    fr: 'Fermer',
    es: 'Cerrar',
  );
  final String message;
  switch (kind) {
    case NavRouteErrorKind.dnsFailure:
    case NavRouteErrorKind.offline:
    case NavRouteErrorKind.connectionReset:
      message = tr(
        nl: 'Route kon niet worden geladen. Controleer je internetverbinding.',
        en: 'Could not load the route. Check your internet connection.',
        fr: 'Itinéraire indisponible. Vérifiez votre connexion Internet.',
        es: 'No se pudo cargar la ruta. Revisa tu conexión a Internet.',
      );
      break;
    case NavRouteErrorKind.timeout:
      message = tr(
        nl: 'Route laden duurde te lang. Controleer je verbinding en probeer opnieuw.',
        en: 'Loading the route timed out. Check your connection and try again.',
        fr: 'Le chargement de l’itinéraire a expiré. Vérifiez votre connexion.',
        es: 'La carga de la ruta expiró. Revisa tu conexión e inténtalo de nuevo.',
      );
      break;
    case NavRouteErrorKind.http401or403:
    case NavRouteErrorKind.http429:
    case NavRouteErrorKind.server5xx:
    case NavRouteErrorKind.invalidResponse:
    case NavRouteErrorKind.unknown:
      message = tr(
        nl: 'Route kon niet worden geladen. Probeer het zo opnieuw.',
        en: 'Could not load the route. Please try again shortly.',
        fr: 'Itinéraire indisponible. Réessayez dans un instant.',
        es: 'No se pudo cargar la ruta. Inténtalo de nuevo en breve.',
      );
      break;
  }
  return NavRouteErrorCopy(
    message: message,
    retryLabel: retryLabel,
    dismissLabel: dismissLabel,
  );
}

/// Whether a route-error class is a transient connectivity failure that should
/// be retried automatically under the bounded policy.
bool navRouteErrorIsRetryable(NavRouteErrorKind kind) {
  switch (kind) {
    case NavRouteErrorKind.dnsFailure:
    case NavRouteErrorKind.offline:
    case NavRouteErrorKind.timeout:
    case NavRouteErrorKind.connectionReset:
    case NavRouteErrorKind.http429:
    case NavRouteErrorKind.server5xx:
      return true;
    case NavRouteErrorKind.http401or403:
    case NavRouteErrorKind.invalidResponse:
    case NavRouteErrorKind.unknown:
      return false;
  }
}

/// Bounded backoff for automatic route retries: 2s, 4s, 8s, 16s, capped at 30s;
/// never a per-tick storm. Attempts beyond [maxAutoRouteRetryAttempts] should
/// stop auto-retrying (manual Retry still allowed).
const int maxAutoRouteRetryAttempts = 4;

Duration navRouteRetryBackoff(int attempt) {
  final safe = attempt < 0 ? 0 : (attempt > 10 ? 10 : attempt);
  final seconds = 2 * (1 << safe);
  const maxSeconds = 30;
  return Duration(seconds: seconds > maxSeconds ? maxSeconds : seconds);
}

/// Maps the active application language to the Mapbox Directions `language`
/// parameter. Single source of truth so the request locale always matches the
/// navigation UI locale. `pt` is intentionally absent — it is not a product
/// [AppLanguage]; add a case here if/when the enum gains it.
String mapboxDirectionsLanguageCode(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.fr:
      return 'fr';
    case AppLanguage.es:
      return 'es';
    case AppLanguage.en:
      return 'en';
    case AppLanguage.nl:
      return 'nl';
  }
}
