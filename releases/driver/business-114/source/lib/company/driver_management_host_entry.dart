import 'dart:convert';

// Fixed build configuration, never a URL supplied by a driver/browser payload.
const driverManagementHostOrigin = String.fromEnvironment(
  'DRIVER_MANAGEMENT_HOST_ORIGIN',
  defaultValue: 'https://fluxidi-booking-api.fluxidi.workers.dev',
);

class DriverManagementHostEntry {
  DriverManagementHostEntry(String configuredOrigin)
    : origin = _origin(configuredOrigin);

  final Uri origin;

  static Uri _origin(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw StateError('driver_management_https_host_required');
    }
    return uri.replace(path: '');
  }

  Future<Uri> open({
    required String companyId,
    required String role,
    required DateTime? expiresAt,
    required Map<String, String> ownerHeaders,
    required bool synthetic,
    required Future<({int status, String body})> Function(
      Uri uri, Map<String, String> headers,
    ) post,
    required Future<bool> Function() sessionUnchanged,
    DateTime? now,
  }) async {
    final authorization = ownerHeaders['Authorization'] ?? '';
    if (companyId.trim().isEmpty || role != 'companyAdmin' || synthetic ||
        !authorization.startsWith('Bearer ') || authorization.length <= 7 ||
        (expiresAt != null && !expiresAt.isAfter(now ?? DateTime.now().toUtc()))) {
      throw StateError('driver_management_company_session_required');
    }
    // No company ID or client role is sent as authority. The host resolves both
    // from the existing server-validated company session.
    final response = await post(origin.resolve('/driver-management/host-session'), {
      'Authorization': authorization,
      'Content-Type': 'application/json',
      'x-driver-management': '1',
    });
    if (response.status != 200) {
      throw StateError('driver_management_session_denied');
    }
    final body = jsonDecode(response.body);
    final location = body is Map ? Uri.tryParse('${body['location'] ?? ''}') : null;
    if (location == null || location.origin != origin.origin ||
        location.path != '/driver-management/handoff' || location.hasQuery ||
        location.userInfo.isNotEmpty ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(location.fragment)) {
      throw StateError('driver_management_handoff_denied');
    }
    if (!await sessionUnchanged()) {
      throw StateError('driver_management_session_changed');
    }
    return location;
  }
}
