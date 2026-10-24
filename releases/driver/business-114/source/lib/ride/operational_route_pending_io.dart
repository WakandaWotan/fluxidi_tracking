import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class OperationalPendingStore {
  static Future<void> _writes = Future.value();
  OperationalPendingStore({this.directory});
  final Directory? directory;
  Future<File> _file(String key) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key))
      throw StateError('Invalid pending key');
    final base = directory ?? await getApplicationSupportDirectory();
    final folder = Directory('${base.path}/operational-route-pending');
    await folder.create(recursive: true);
    return File('${folder.path}/$key.json');
  }

  Future<Map<String, dynamic>?> read(String key) async {
    final file = await _file(key);
    // A crash after durable intent write but before rename keeps the exact body.
    final next = File('${file.path}.next');
    final source = await next.exists() ? next : file;
    if (!await source.exists()) return null;
    if (await source.length() > 65536)
      throw StateError('Pending intent too large');
    return Map<String, dynamic>.from(
      jsonDecode(await source.readAsString()) as Map,
    );
  }

  Future<void> write(String key, Map<String, dynamic> value) {
    final operation = _writes.then((_) => _write(key, value));
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _write(String key, Map<String, dynamic> value) async {
    final data = jsonEncode(value);
    if (data.length > 16384) throw StateError('Pending intent too large');
    final file = await _file(key),
        next = File('${(await _file(key)).path}.next');
    // Uncertain intentions never expire silently. Bound the unresolved journal
    // and refuse a new transport until existing intentions are reconciled.
    final keys = <String>{};
    var bytes = 0;
    await for (final entry in file.parent.list(followLinks: false)) {
      if (entry is! File) throw StateError('Invalid pending journal');
      final name = entry.uri.pathSegments.last;
      if (!RegExp(r'^[a-f0-9]{64}\.json(?:\.next)?$').hasMatch(name))
        throw StateError('Invalid pending journal');
      if (name.startsWith(key)) continue;
      keys.add(name.substring(0, 64));
      bytes += await entry.length();
      if (keys.length >= 64 || bytes > 2 * 1024 * 1024)
        throw StateError('Pending journal full');
    }
    if (bytes + utf8.encode(data).length > 2 * 1024 * 1024)
      throw StateError('Pending journal full');
    await next.writeAsString(data, flush: true);
    await next.rename(file.path);
  }

  Future<void> clear(String key) async {
    final file = await _file(key),
        next = File('${(await _file(key)).path}.next');
    if (await next.exists()) await next.delete();
    if (await file.exists()) await file.delete();
  }
}
