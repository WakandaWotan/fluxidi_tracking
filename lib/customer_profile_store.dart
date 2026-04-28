import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CustomerProfile {
  const CustomerProfile({
    required this.customerId,
    required this.name,
    required this.phone,
    required this.email,
    required this.companyName,
    required this.vatNumber,
    required this.createdAt,
    required this.updatedAt,
  });

  final String customerId;
  final String name;
  final String phone;
  final String email;
  final String companyName;
  final String vatNumber;
  final String createdAt;
  final String updatedAt;

  bool get hasContactDetails =>
      name.trim().isNotEmpty ||
      phone.trim().isNotEmpty ||
      email.trim().isNotEmpty;

  factory CustomerProfile.fromJson(Map<String, dynamic> json) {
    String read(String key) => (json[key] ?? '').toString().trim();
    return CustomerProfile(
      customerId: read('customerId'),
      name: read('name'),
      phone: read('phone'),
      email: read('email').toLowerCase(),
      companyName: read('companyName'),
      vatNumber: read('vatNumber'),
      createdAt: read('createdAt'),
      updatedAt: read('updatedAt'),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'customerId': customerId,
      'name': name,
      'phone': phone,
      'email': email,
      'companyName': companyName,
      'vatNumber': vatNumber,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

class CustomerProfileStore {
  CustomerProfileStore._();

  static final CustomerProfileStore instance = CustomerProfileStore._();

  static const String _fileName = 'customer_profile_v1.json';

  CustomerProfile? _cache;

  Future<File> _file() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}customer_state',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  String _generateCustomerId() {
    final random = math.Random.secure();
    final partA = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final partB = random.nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
    return 'cust_${partA}_$partB';
  }

  Future<CustomerProfile?> load() async {
    if (_cache != null) return _cache;
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final profile = CustomerProfile.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (profile.customerId.isEmpty) return null;
      _cache = profile;
      return profile;
    } catch (err) {
      debugPrint('[CUSTOMER_PROFILE][LOAD_ERROR] $err');
      return null;
    }
  }

  Future<CustomerProfile> save({
    required String name,
    required String phone,
    required String email,
    String companyName = '',
    String vatNumber = '',
  }) async {
    final existing = await load();
    final now = DateTime.now().toIso8601String();
    final profile = CustomerProfile(
      customerId: (existing?.customerId.trim().isNotEmpty ?? false)
          ? existing!.customerId
          : _generateCustomerId(),
      name: name.trim(),
      phone: phone.trim(),
      email: email.trim().toLowerCase(),
      companyName: companyName.trim(),
      vatNumber: vatNumber.trim(),
      createdAt: (existing?.createdAt.trim().isNotEmpty ?? false)
          ? existing!.createdAt
          : now,
      updatedAt: now,
    );
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(profile.toJson()));
      _cache = profile;
    } catch (err) {
      debugPrint('[CUSTOMER_PROFILE][SAVE_ERROR] $err');
    }
    return profile;
  }
}
