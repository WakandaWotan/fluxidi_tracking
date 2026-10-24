import 'dart:io';

import 'package:fluxidi_tracking/customer_session_store.dart';
import 'package:fluxidi_tracking/fluxidi_runtime_env.dart';
import 'package:path_provider/path_provider.dart';

/// Same on-disk name the golden [CustomerSessionStore] uses.
const String kCustomerSessionPlaintextFileName =
    'global_customer_session_v1.json';
const String kCustomerSessionPlaintextDirName = 'customer_state';

/// The in-process customer session, isolated so tests need no disk.
abstract class CustomerSessionSurface {
  CustomerSession? peek();

  void remember(CustomerSession session);

  Future<CustomerSession?> loadFromFile();

  Future<void> forgetMemoryAndFile();

  /// True when the leftover plaintext JSON file still exists.
  Future<bool> plaintextFileExists();

  /// Deletes only the leftover JSON file. Process memory stays as it is.
  Future<void> deletePlaintextFile();

  bool isValid(CustomerSession session);
}

/// Production surface: the existing [CustomerSessionStore].
class StoreCustomerSessionSurface implements CustomerSessionSurface {
  @override
  CustomerSession? peek() => CustomerSessionStore.instance.peekCachedSession();

  @override
  void remember(CustomerSession session) {
    CustomerSessionStore.instance.rememberSession(session);
  }

  @override
  Future<CustomerSession?> loadFromFile() {
    return CustomerSessionStore.instance.load();
  }

  @override
  Future<void> forgetMemoryAndFile() {
    return CustomerSessionStore.instance.clear();
  }

  @override
  Future<bool> plaintextFileExists() async {
    try {
      return await (await _plaintextFile()).exists();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> deletePlaintextFile() async {
    try {
      final file = await _plaintextFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  @override
  bool isValid(CustomerSession session) {
    return CustomerSessionStore.instance.isValid(session);
  }

  Future<File> _plaintextFile() async {
    final base = await getApplicationDocumentsDirectory();
    final root = Directory(
      '${base.path}${Platform.pathSeparator}${fluxidiRuntimeStateDirName(kCustomerSessionPlaintextDirName)}',
    );
    return File(
      '${root.path}${Platform.pathSeparator}$kCustomerSessionPlaintextFileName',
    );
  }
}

/// In-memory surface for tests.
class MemoryCustomerSessionSurface implements CustomerSessionSurface {
  CustomerSession? session;
  CustomerSession? fileSession;

  @override
  CustomerSession? peek() => session;

  @override
  void remember(CustomerSession session) {
    this.session = session;
  }

  @override
  Future<CustomerSession?> loadFromFile() async => fileSession;

  @override
  Future<void> forgetMemoryAndFile() async {
    session = null;
    fileSession = null;
  }

  @override
  Future<bool> plaintextFileExists() async => fileSession != null;

  @override
  Future<void> deletePlaintextFile() async {
    fileSession = null;
  }

  @override
  bool isValid(CustomerSession session) {
    if (session.customerSessionToken.trim().isEmpty) return false;
    if (session.customerId.trim().isEmpty) return false;
    final expiresAt = DateTime.tryParse(session.expiresAt.trim());
    if (expiresAt == null) return false;
    return DateTime.now().toUtc().isBefore(expiresAt.toUtc());
  }
}
