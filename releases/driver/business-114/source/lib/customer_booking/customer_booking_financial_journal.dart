import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

typedef FinancialJournalRead = Future<String?> Function(String key);
typedef FinancialJournalWrite = Future<void> Function(String key, String value);

/// Private, encrypted acceptance checkpoint. No token or provider key is stored.
/// The same customer/contact, company and backend target must reopen it.
class CustomerFinancialAcceptanceJournal {
  CustomerFinancialAcceptanceJournal({FinancialJournalRead? read,
    FinancialJournalWrite? write}) :
    _read = read ?? ((key) => const FlutterSecureStorage().read(key: key)),
    _write = write ?? ((key, value) => const FlutterSecureStorage().write(key: key, value: value));
  final FinancialJournalRead _read;
  final FinancialJournalWrite _write;
  String key({required String backend, required String tenant,
    required String company, required String owner}) => 'financial_acceptance_v1_' +
      sha256.convert(utf8.encode(jsonEncode([backend, tenant, company, owner]))).toString();
  Future<Map<String, dynamic>?> load(String key) async {
    final raw = await _read(key);
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }
  Future<void> save(String key, Map<String, dynamic> record) =>
      _write(key, jsonEncode(record));
  Future<void> complete(String key) => save(key, {'status': 'completed'});
}
