import 'package:http/http.dart' as http;

// All default Dart HTTP clients in the application zone share this boundary.
// Own Booking/Navigation/Tracking endpoints remain unchanged. This does not
// claim to control old installed apps, native SDK traffic or backend traffic.
class FluxidiProviderHttpClient extends http.BaseClient {
  FluxidiProviderHttpClient(this._inner);
  final http.Client _inner;
  static bool blockedHost(String host) {
    final h = host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    return h == 'mapbox.com' || h.endsWith('.mapbox.com') ||
      h == 'mapbox.cn' || h.endsWith('.mapbox.cn');
  }
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (blockedHost(request.url.host)) {
      // Never expose credentials or the original token-bearing URL.
      throw http.ClientException('External Mapbox requests are disabled');
    }
    return _inner.send(request);
  }
  @override
  void close() => _inner.close();
}
