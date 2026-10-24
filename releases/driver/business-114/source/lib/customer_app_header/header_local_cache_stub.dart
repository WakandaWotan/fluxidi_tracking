import 'package:flutter/painting.dart';

ImageProvider headerImageProvider(String url) => NetworkImage(url);
Future<Map<String, dynamic>?> readHeaderPresentation(String scope) async =>
    null;
Future<void> saveHeaderPresentation(
  String scope,
  Map<String, dynamic> value,
) async {}
