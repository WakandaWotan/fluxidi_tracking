import 'package:http/http.dart' as http;

// Public GETs only: reuse connections and coalesce concurrent identical reads.
// Live availability is never cached after completion.
final _client = http.Client();
final Map<String, Future<http.Response>> _pending = {};
final Map<String, (DateTime, http.Response)> _profiles = {};

Future<http.Response> publicCompanyGet(
  Uri uri, {
  Map<String, String>? headers,
}) {
  final key = uri.toString();
  final profile = uri.path == '/partners/profile';
  final cached = _profiles[key];
  if (profile &&
      cached != null &&
      DateTime.now().difference(cached.$1) < const Duration(seconds: 30)) {
    return Future.value(cached.$2);
  }
  final pending = _pending[key];
  if (pending != null) return pending;
  final future = _client
      .get(uri, headers: headers)
      .timeout(const Duration(seconds: 12))
      .then((response) {
        if (profile && response.statusCode == 200) {
          if (_profiles.length >= 16) _profiles.remove(_profiles.keys.first);
          _profiles[key] = (DateTime.now(), response);
        }
        return response;
      });
  _pending[key] = future;
  return future.whenComplete(() {
    if (identical(_pending[key], future)) _pending.remove(key);
  });
}
