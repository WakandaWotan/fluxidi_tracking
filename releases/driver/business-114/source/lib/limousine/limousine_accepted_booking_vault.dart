// LIMOUSINE-MARKETPLACE-P2D4A — Keystore/Keychain resume vault.
// Reuses flutter_secure_storage. Fail closed. Never log vault contents.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'limousine_accepted_booking.dart';
import 'limousine_accepted_booking_resume.dart';
import 'limousine_customer_quote.dart';

class LimousineAcceptedBookingVaultException implements Exception {
  const LimousineAcceptedBookingVaultException();
}

abstract class LimousineAcceptedBookingVault {
  Future<void> write(String value);
  Future<String?> read();
  Future<void> delete();
}

class FlutterSecureLimousineAcceptedBookingVault
    implements LimousineAcceptedBookingVault {
  FlutterSecureLimousineAcceptedBookingVault({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String value) async {
    try {
      await _storage.write(
        key: kLimousineAcceptedBookingResumeStorageKey,
        value: value,
      );
    } catch (_) {
      throw const LimousineAcceptedBookingVaultException();
    }
  }

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(
        key: kLimousineAcceptedBookingResumeStorageKey,
      );
    } catch (_) {
      throw const LimousineAcceptedBookingVaultException();
    }
  }

  @override
  Future<void> delete() async {
    try {
      await _storage.delete(key: kLimousineAcceptedBookingResumeStorageKey);
    } catch (_) {
      throw const LimousineAcceptedBookingVaultException();
    }
  }
}

class MemoryLimousineAcceptedBookingVault
    implements LimousineAcceptedBookingVault {
  MemoryLimousineAcceptedBookingVault();

  String? _value;
  bool failReads = false;
  bool failWrites = false;
  bool failDeletes = false;

  @override
  Future<void> write(String value) async {
    if (failWrites) throw const LimousineAcceptedBookingVaultException();
    _value = value;
  }

  @override
  Future<String?> read() async {
    if (failReads) throw const LimousineAcceptedBookingVaultException();
    return _value;
  }

  @override
  Future<void> delete() async {
    if (failDeletes) throw const LimousineAcceptedBookingVaultException();
    _value = null;
  }
}

class LimousineAcceptedBookingResumeRepository {
  LimousineAcceptedBookingResumeRepository({
    LimousineAcceptedBookingVault? vault,
    DateTime Function()? clock,
  }) : _vault = vault ?? FlutterSecureLimousineAcceptedBookingVault(),
       _clock = clock ?? DateTime.now;

  final LimousineAcceptedBookingVault _vault;
  final DateTime Function() _clock;

  int _generation = 0;
  bool _failedClosed = false;
  LimousineAcceptedBookingResumeEnvelope? _cached;

  int get generationForTests => _generation;
  bool get failedClosedForTests => _failedClosed;

  void _bumpGeneration() {
    _generation += 1;
    _cached = null;
  }

  Future<bool> persistAccepted({
    required LimousineAcceptedQuoteHandoff handoff,
    required LimousineQuoteCreateDraft draft,
    required LimousineAcceptedBookingReview review,
    required String customerId,
    required DateTime expiresAt,
    String providerName = '',
  }) async {
    if (_failedClosed) return false;
    final envelope = buildLimousineAcceptedBookingResumeEnvelope(
      handoff: handoff,
      draft: draft,
      review: review,
      customerId: customerId,
      createdAt: _clock().toUtc(),
      expiresAt: expiresAt,
      providerName: providerName,
    );
    if (envelope == null) return false;
    final generation = _generation;
    try {
      await _vault.write(jsonEncode(envelope.toJson()));
      if (generation != _generation) {
        await _safeDelete();
        return false;
      }
      _cached = envelope;
      return true;
    } catch (_) {
      _failedClosed = true;
      _cached = null;
      return false;
    }
  }

  Future<LimousineAcceptedBookingResumeEnvelope?> restore({
    required LimousineAcceptedBookingResumeScope scope,
  }) async {
    if (_failedClosed) return null;
    if (scope.customerId.trim().isEmpty) return null;
    final generation = _generation;
    String? raw;
    try {
      raw = await _vault.read();
    } catch (_) {
      _failedClosed = true;
      _cached = null;
      return null;
    }
    if (generation != _generation) return null;
    if (raw == null || raw.trim().isEmpty) {
      _cached = null;
      return null;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      await _clearInvalid();
      return null;
    }
    final envelope = parseLimousineAcceptedBookingResumeEnvelope(decoded);
    if (envelope == null) {
      await _clearInvalid();
      return null;
    }
    if (envelope.isExpired(_clock())) {
      await _clearInvalid();
      return null;
    }
    if (!envelope.matches(scope)) {
      await _clearInvalid();
      return null;
    }
    if (generation != _generation) return null;
    _cached = envelope;
    return envelope;
  }

  Future<void> discard() async {
    _bumpGeneration();
    await _safeDelete();
  }

  Future<void> _clearInvalid() async {
    _bumpGeneration();
    await _safeDelete();
  }

  Future<void> _safeDelete() async {
    try {
      await _vault.delete();
    } catch (_) {
      _failedClosed = true;
    }
  }
}
