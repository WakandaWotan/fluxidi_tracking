import 'package:http/http.dart' as http;

enum DriverSessionProbeResult { valid, invalid, unavailable }

/// Checks the server-issued bearer on an existing, read-only driver route.
/// A transport/5xx failure is not evidence that the session was revoked.
class DriverSessionProbe {
  const DriverSessionProbe();

  Future<DriverSessionProbeResult> check({
    required String bookingBaseUrl,
    required String token,
    http.Client? client,
  }) async {
    if (token.trim().isEmpty) return DriverSessionProbeResult.invalid;
    final transport = client ?? http.Client();
    try {
      final response = await transport
          .get(
            Uri.parse('$bookingBaseUrl/driver/bookings?limit=1'),
            headers: <String, String>{
              'Accept': 'application/json',
              'Authorization': 'Bearer ${token.trim()}',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) return DriverSessionProbeResult.valid;
      if (response.statusCode == 401 || response.statusCode == 403) {
        return DriverSessionProbeResult.invalid;
      }
      return DriverSessionProbeResult.unavailable;
    } catch (_) {
      return DriverSessionProbeResult.unavailable;
    } finally {
      if (client == null) transport.close();
    }
  }
}
