import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:fluxidi_tracking/customer_session_store.dart';

import 'customer_booking_presence.dart';
import 'customer_device_unlock.dart';
import 'customer_secure_session_vault.dart';
import 'customer_session_surface.dart';

/// In-memory lock view for the customer shell.
enum CustomerSessionLockPhase { unlocked, locked }

/// Optional device unlock around the existing customer session.
///
/// Secrets live in [CustomerSecureSessionVault]. A successful fingerprint,
/// face or device-PIN dialog only hydrates an already-valid session. An expired
/// or revoked server session is deleted, never renewed.
class CustomerSessionLock extends ChangeNotifier {
  CustomerSessionLock({
    required CustomerSecureSessionVault vault,
    required CustomerDeviceUnlock unlock,
    required CustomerSessionSurface surface,
    CustomerBookingPresence? bookingPresence,
  }) : _vault = vault,
       _unlock = unlock,
       _surface = surface,
       _booking = bookingPresence ?? CustomerBookingPresence.instance;

  static CustomerSessionLock? _instance;

  static CustomerSessionLock get instance {
    return _instance ??= CustomerSessionLock(
      vault: PlatformCustomerSecureSessionVault(),
      unlock: LocalAuthCustomerDeviceUnlock(),
      surface: StoreCustomerSessionSurface(),
    );
  }

  @visibleForTesting
  static void debugOverride(CustomerSessionLock? lock) {
    _instance = lock;
  }

  final CustomerSecureSessionVault _vault;
  final CustomerDeviceUnlock _unlock;
  final CustomerSessionSurface _surface;
  final CustomerBookingPresence _booking;

  CustomerSessionLockPhase _phase = CustomerSessionLockPhase.unlocked;
  bool _enabled = false;
  bool _attached = false;
  bool _suppressVaultClear = false;
  bool _pendingLock = false;
  bool _paymentReturnActive = false;
  bool _navigationBusy = false;

  CustomerSessionLockPhase get phase => _phase;

  bool get isLocked => _phase == CustomerSessionLockPhase.locked;

  bool get isEnabled => _enabled;

  bool get hasPendingLock => _pendingLock;

  bool get paymentReturnActive => _paymentReturnActive;

  set paymentReturnActive(bool value) {
    if (_paymentReturnActive == value) return;
    _paymentReturnActive = value;
    if (!value) {
      unawaited(applyPendingLockIfSafe());
    }
  }

  bool get navigationBusy => _navigationBusy;

  set navigationBusy(bool value) {
    if (_navigationBusy == value) return;
    _navigationBusy = value;
    if (!value) {
      unawaited(applyPendingLockIfSafe());
    }
  }

  bool get shouldDeferLock =>
      _booking.isActive || _paymentReturnActive || _navigationBusy;

  Future<bool> canProtectDevice() => _unlock.canProtect();

  Future<void> attach() async {
    if (_attached) return;
    _attached = true;
    _booking.addIdleListener(_onBookingBecameIdle);
    CustomerSessionStore.instance.addClearedListener(_onStoreCleared);
    await restoreAtLaunch();
  }

  void detach() {
    if (!_attached) return;
    CustomerSessionStore.instance.removeClearedListener(_onStoreCleared);
    _booking.removeIdleListener(_onBookingBecameIdle);
    _attached = false;
  }

  void _onBookingBecameIdle() {
    unawaited(applyPendingLockIfSafe());
  }

  void _onStoreCleared() {
    if (_suppressVaultClear) return;
    unawaited(() async {
      await _discardSessionSecrets();
      _pendingLock = false;
      if (_phase != CustomerSessionLockPhase.unlocked) {
        _phase = CustomerSessionLockPhase.unlocked;
        notifyListeners();
      }
    }());
  }

  void markLockPending() {
    if (_enabled) {
      _pendingLock = true;
    }
  }

  Future<void> restoreAtLaunch() async {
    _enabled = await _vault.readUnlockEnabled();
    await _migratePlaintextIfNeeded();
    final stored = await _readStoredSession();
    if (stored == null) {
      _pendingLock = false;
      _phase = CustomerSessionLockPhase.unlocked;
      debugPrint(
        '[CUSTOMER_LOCK] launch open reason=no_session enabled=$_enabled',
      );
      notifyListeners();
      return;
    }
    if (!_surface.isValid(stored)) {
      await _discardSessionSecrets();
      _pendingLock = false;
      _phase = CustomerSessionLockPhase.unlocked;
      debugPrint(
        '[CUSTOMER_LOCK] launch open reason=invalid enabled=$_enabled',
      );
      notifyListeners();
      return;
    }
    await _surface.deletePlaintextFile();
    if (_enabled) {
      await _forgetProcessSession();
      _pendingLock = false;
      _phase = CustomerSessionLockPhase.locked;
      debugPrint('[CUSTOMER_LOCK] launch locked');
      notifyListeners();
      return;
    }
    _surface.remember(stored);
    _pendingLock = false;
    _phase = CustomerSessionLockPhase.unlocked;
    debugPrint('[CUSTOMER_LOCK] launch open enabled=false');
    notifyListeners();
  }

  Future<bool> persistCurrentSession() async {
    final session = _surface.peek() ?? await _surface.loadFromFile();
    if (session == null || !_surface.isValid(session)) {
      await _surface.deletePlaintextFile();
      return false;
    }
    final wrote = await _vault.writeSessionJson(jsonEncode(session.toJson()));
    if (!wrote) {
      debugPrint('[CUSTOMER_LOCK] session vault write failed');
      return false;
    }
    await _forgetProcessSession();
    await _surface.deletePlaintextFile();
    _surface.remember(session);
    return true;
  }

  Future<CustomerUnlockResult> enableAfterAuthentication({
    required String reason,
  }) async {
    if (!await _unlock.canProtect()) return CustomerUnlockResult.unavailable;
    final result = await _unlock.authenticate(reason: reason);
    if (result != CustomerUnlockResult.success) return result;
    if (!await persistCurrentSession()) return CustomerUnlockResult.failed;
    if (!await _vault.writeUnlockEnabled(true)) {
      debugPrint('[CUSTOMER_LOCK] unlock flag write failed');
      return CustomerUnlockResult.failed;
    }
    _enabled = true;
    _phase = CustomerSessionLockPhase.unlocked;
    notifyListeners();
    return result;
  }

  Future<CustomerUnlockResult> disableAfterAuthentication({
    required String reason,
  }) async {
    if (!await _unlock.canProtect()) return CustomerUnlockResult.unavailable;
    final result = await _unlock.authenticate(reason: reason);
    if (result != CustomerUnlockResult.success) return result;
    if (!await _vault.writeUnlockEnabled(false)) {
      debugPrint('[CUSTOMER_LOCK] unlock flag clear failed');
      return CustomerUnlockResult.failed;
    }
    _enabled = false;
    _pendingLock = false;
    _phase = CustomerSessionLockPhase.unlocked;
    notifyListeners();
    return result;
  }

  /// Locks the process copy of the session. Vault contents stay as they are.
  ///
  /// Does not pop routes. A deferred request is kept until [applyPendingLockIfSafe].
  Future<bool> lockIfNeeded() async {
    if (!_enabled) return false;
    if (shouldDeferLock) {
      _pendingLock = true;
      return false;
    }
    final stored = await _readStoredSession();
    if (stored == null || !_surface.isValid(stored)) {
      await _discardSessionSecrets();
      _pendingLock = false;
      return false;
    }
    await _forgetProcessSession();
    await _surface.deletePlaintextFile();
    _pendingLock = false;
    if (_phase != CustomerSessionLockPhase.locked) {
      _phase = CustomerSessionLockPhase.locked;
      notifyListeners();
    }
    return true;
  }

  /// Applies a lock that was deferred during a booking, payment return or
  /// pushed page, as soon as those conditions have cleared.
  Future<bool> applyPendingLockIfSafe() async {
    if (!_pendingLock || !_enabled) return false;
    if (shouldDeferLock) return false;
    return lockIfNeeded();
  }

  Future<CustomerUnlockResult> unlock({required String reason}) async {
    if (!_enabled) {
      await restoreAtLaunch();
      return CustomerUnlockResult.success;
    }
    final result = await _unlock.authenticate(reason: reason);
    if (result != CustomerUnlockResult.success) return result;
    final stored = await _readStoredSession();
    if (stored == null || !_surface.isValid(stored)) {
      await _discardSessionSecrets();
      _pendingLock = false;
      _phase = CustomerSessionLockPhase.unlocked;
      notifyListeners();
      return CustomerUnlockResult.success;
    }
    await _surface.deletePlaintextFile();
    _surface.remember(stored);
    _pendingLock = false;
    _phase = CustomerSessionLockPhase.unlocked;
    notifyListeners();
    return CustomerUnlockResult.success;
  }

  Future<void> signOut() async {
    await _discardSessionSecrets();
    _pendingLock = false;
    _phase = CustomerSessionLockPhase.unlocked;
    notifyListeners();
  }

  Future<CustomerSession?> _readStoredSession() async {
    final raw = await _vault.readSessionJson();
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return CustomerSession.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> _migratePlaintextIfNeeded() async {
    final existing = await _vault.readSessionJson();
    if (existing != null && existing.trim().isNotEmpty) {
      await _surface.deletePlaintextFile();
      return;
    }
    final fileSession = await _surface.loadFromFile();
    if (fileSession == null) {
      await _surface.deletePlaintextFile();
      return;
    }
    if (!_surface.isValid(fileSession)) {
      await _surface.deletePlaintextFile();
      return;
    }
    final wrote = await _vault.writeSessionJson(
      jsonEncode(fileSession.toJson()),
    );
    if (!wrote) {
      debugPrint('[CUSTOMER_LOCK] migrate vault write failed');
      _surface.remember(fileSession);
      return;
    }
    await _forgetProcessSession();
    await _surface.deletePlaintextFile();
    if (!_enabled) {
      _surface.remember(fileSession);
    }
  }

  Future<void> _discardSessionSecrets() async {
    await _vault.deleteSession();
    await _forgetProcessSession();
    await _surface.deletePlaintextFile();
  }

  Future<void> _forgetProcessSession() async {
    _suppressVaultClear = true;
    try {
      await _surface.forgetMemoryAndFile();
    } finally {
      _suppressVaultClear = false;
    }
  }
}
