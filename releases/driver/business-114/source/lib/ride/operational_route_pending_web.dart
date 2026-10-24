import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class OperationalPendingStore {
  String _key(String key) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key))
      throw StateError('Invalid pending key');
    return 'fluxidi_operational_route_$key';
  }

  Future<Map<String, dynamic>?> read(String key) async {
    final raw = html.window.localStorage[_key(key)];
    if (raw != null && utf8.encode(raw).length > 65536)
      throw StateError('Pending intent too large');
    return raw == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> write(String key, Map<String, dynamic> value) async {
    final target = _key(key), data = jsonEncode(value);
    if (data.length > 16384) throw StateError('Pending intent too large');
    var count = 0, bytes = 0;
    for (final name in html.window.localStorage.keys) {
      if (!name.startsWith('fluxidi_operational_route_') || name == target)
        continue;
      count++;
      bytes += utf8.encode(html.window.localStorage[name] ?? '').length;
      if (count >= 64 || bytes > 2 * 1024 * 1024)
        throw StateError('Pending journal full');
    }
    if (bytes + utf8.encode(data).length > 2 * 1024 * 1024)
      throw StateError('Pending journal full');
    html.window.localStorage[target] = data;
  }

  Future<void> clear(String key) async {
    html.window.localStorage.remove(_key(key));
  }
}
