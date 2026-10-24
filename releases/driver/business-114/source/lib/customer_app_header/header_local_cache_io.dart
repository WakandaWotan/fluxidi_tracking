import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

Future<File> _file(String key) async {
  final root = await getApplicationCacheDirectory();
  final dir = Directory('${root.path}/company_header_v1');
  await dir.create(recursive: true);
  return File('${dir.path}/${sha256.convert(utf8.encode(key))}');
}

Future<Map<String, dynamic>?> readHeaderPresentation(String scope) async {
  try {
    final file = await _file('presentation:$scope');
    if (!await file.exists() || await file.length() > 65536) return null;
    return Map<String, dynamic>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
  } catch (_) {
    return null;
  }
}

Future<void> saveHeaderPresentation(
  String scope,
  Map<String, dynamic> value,
) async {
  try {
    final file = await _file('presentation:$scope');
    await file.writeAsString(jsonEncode(value), flush: true);
  } catch (_) {
    /* Presentation cache never blocks login or navigation. */
  }
}

ImageProvider headerImageProvider(String url) => _HeaderImage(url);

class _HeaderImage extends ImageProvider<_HeaderImage> {
  const _HeaderImage(this.url);
  final String url;
  static final Map<String, Future<Uint8List>> _pending = {};
  @override
  Future<_HeaderImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    _HeaderImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _decode(decode), scale: 1);

  Future<ui.Codec> _decode(ImageDecoderCallback decode) async {
    final bytes = await (_pending[url] ??= _bytes().whenComplete(() {
      _pending.remove(url);
    }));
    try {
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      try {
        await (await _file('image:$url')).delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<Uint8List> _bytes() async {
    File? file;
    try {
      file = await _file('image:$url');
      if (await file.exists() && await file.length() <= 4 * 1024 * 1024) {
        return await file.readAsBytes();
      }
    } catch (_) {}
    final uri = Uri.parse(url);
    if (uri.scheme != 'https') throw StateError('Invalid public header URL');
    final client = http.Client();
    try {
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200 ||
          response.bodyBytes.isEmpty ||
          response.bodyBytes.length > 4 * 1024 * 1024) {
        throw StateError('Header image unavailable');
      }
      try {
        if (file != null) {
          await file.writeAsBytes(response.bodyBytes, flush: true);
          // Bound disk growth when companies publish replacement media.
          final files = await file.parent
              .list()
              .where((entry) => entry is File)
              .cast<File>()
              .toList();
          if (files.length > 64) {
            final dated = await Future.wait(
              files.map((f) async => (f, await f.lastModified())),
            );
            dated.sort((a, b) => a.$2.compareTo(b.$2));
            for (final entry in dated.take(dated.length - 64)) {
              await entry.$1.delete();
            }
          }
        }
      } catch (_) {}
      return response.bodyBytes;
    } finally {
      client.close();
    }
  }

  @override
  bool operator ==(Object other) => other is _HeaderImage && other.url == url;
  @override
  int get hashCode => url.hashCode;
}
