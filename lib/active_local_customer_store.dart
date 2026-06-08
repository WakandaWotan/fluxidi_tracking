import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class ActiveLocalCustomerStore {
  ActiveLocalCustomerStore._();

  static final ActiveLocalCustomerStore instance = ActiveLocalCustomerStore._();

  static const String _stateDirName = 'customer_state';
  static const String _fileName = 'active_local_customer_id_v1.json';

  String? _cache;

  String generateCustomerId() {
    final random = math.Random.secure();
    final partA = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final partB = random.nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
    return 'cust_${partA}_$partB';
  }

  String _maskCustomerId(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= 4) return trimmed.isEmpty ? '-' : '...$trimmed';
    return '${trimmed.substring(0, 2)}...${trimmed.substring(trimmed.length - 2)}';
  }

  Future<File> _file() async {
    final base = await getApplicationDocumentsDirectory();
    final root = Directory(
      '${base.path}${Platform.pathSeparator}$_stateDirName',
    );
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return File('${root.path}${Platform.pathSeparator}$_fileName');
  }

  void invalidateCache() {
    _cache = null;
  }

  Future<String> getActiveCustomerId() async {
    final cached = (_cache ?? '').trim();
    if (cached.isNotEmpty) return cached;
    try {
      final file = await _file();
      if (!await file.exists()) return '';
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return '';
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return '';
      final id = (decoded['customerId'] ?? decoded['customer_id'] ?? '')
          .toString()
          .trim();
      _cache = id;
      return id;
    } catch (_) {
      return '';
    }
  }

  Future<void> setActiveCustomerId(String customerId) async {
    final normalized = customerId.trim();
    if (normalized.isEmpty) return;
    final file = await _file();
    await file.writeAsString(
      jsonEncode(<String, dynamic>{
        'customerId': normalized,
        'customer_id': normalized,
        'updatedAt': DateTime.now().toIso8601String(),
      }),
      flush: true,
    );
    _cache = normalized;
    debugPrint(
      '[ACTIVE_LOCAL_CUSTOMER][SET] id=${_maskCustomerId(normalized)}',
    );
  }

  Future<String> createNewLocalCustomerId() async {
    final id = generateCustomerId();
    await setActiveCustomerId(id);
    debugPrint('[ACTIVE_LOCAL_CUSTOMER][CREATE] id=${_maskCustomerId(id)}');
    return id;
  }

  Future<void> clearActiveCustomerId() async {
    _cache = null;
    try {
      final file = await _file();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
