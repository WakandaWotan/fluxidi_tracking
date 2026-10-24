import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readCompanyCustomerImportPath(String? path) async {
  final filePath = (path ?? '').trim();
  if (filePath.isEmpty) return null;
  final file = File(filePath);
  if (!await file.exists()) return null;
  final bytes = await file.readAsBytes();
  return bytes.isEmpty ? null : bytes;
}
