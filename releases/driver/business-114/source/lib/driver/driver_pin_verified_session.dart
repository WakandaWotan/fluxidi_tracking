import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../app_config.dart';
import '../driver_session_store.dart';

/// A server-issued driver bearer, never a QR/challenge or locally minted token.
/// PIN unlock only releases it; the server must accept it on every sign-in.
class DriverPinServerSession {
  DriverPinServerSession._(this.session);
  final ActiveDriverSession session;

  factory DriverPinServerSession.fromVerifiedSession(
    ActiveDriverSession source,
  ) {
    final expiry = DateTime.tryParse(source.driverSessionExpiresAtUtc ?? '');
    if (!source.isStandaloneLoginSession ||
        source.isOperatorMintedSession ||
        (source.tenantId ?? '').isEmpty ||
        (source.companyId ?? '').isEmpty ||
        (source.companyCode ?? '').isEmpty ||
        source.driverId.isEmpty ||
        (source.driverSessionToken ?? '').isEmpty ||
        expiry == null ||
        !expiry.isAfter(DateTime.now())) {
      throw StateError('pin_server_session_invalid');
    }
    // The pairing employee number may be the temporary challenge fallback.
    // It is never copied into the encrypted PIN credential.
    return DriverPinServerSession._(
      ActiveDriverSession(
        driverId: source.driverId,
        employeeNumber: source.driverId,
        fullName: source.fullName,
        phone: '',
        loggedInAt: source.loggedInAt,
        updatedAt: source.updatedAt,
        tenantId: source.tenantId,
        companyId: source.companyId,
        companyCode: source.companyCode,
        assignedVehicleId: source.assignedVehicleId,
        driverPhotoUrl: source.driverPhotoUrl,
        companyLogoUrl: source.companyLogoUrl,
        vehiclePhotoUrl: source.vehiclePhotoUrl,
        driverSessionToken: source.driverSessionToken,
        driverSessionExpiresAtUtc: expiry.toUtc().toIso8601String(),
        linkMethod: 'driver_pairing_code',
      ),
    );
  }

  // Only the encrypted PIN store serializes this credential with its bearer.
  Map<String, dynamic> toJson() => session.toJson(includeToken: true);

  factory DriverPinServerSession.fromJson(Map<String, dynamic> json) =>
      DriverPinServerSession.fromVerifiedSession(
        ActiveDriverSession.fromJson(json),
      );

  /// No driver_id query: the endpoint must derive the actor from the bearer.
  /// A company-admin bearer cannot select a driver through this request.
  Future<ActiveDriverSession> verify() async {
    DriverPinServerSession.fromVerifiedSession(session); // expiry before I/O
    final response = await http
        .get(
          Uri.parse('${appConfig.bookingBaseUrl}/public/driver/status'),
          headers: {
            'Authorization': 'Bearer ${session.driverSessionToken}',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 12));
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200 ||
        data is! Map ||
        data['ok'] != true ||
        data['tenant_id'] != session.tenantId ||
        data['company_id'] != session.companyId ||
        data['driver_id'] != session.driverId ||
        data['driver'] is! Map ||
        data['driver']['driver_id'] != session.driverId ||
        data['driver']['is_active'] != true ||
        (data['driver']['assigned_vehicle_id'] ?? '') !=
            (session.assignedVehicleId ?? '')) {
      throw StateError('pin_server_session_rejected');
    }
    DriverPinServerSession.fromVerifiedSession(session); // expiry during I/O
    return ActiveDriverSession(
      driverId: session.driverId,
      employeeNumber: session.driverId,
      fullName: session.fullName,
      phone: '',
      loggedInAt: session.loggedInAt,
      updatedAt: session.updatedAt,
      tenantId: session.tenantId,
      companyId: session.companyId,
      companyCode: session.companyCode,
      // A reassignment requires a newly issued credential, not a local change
      // to the vehicle identity of an existing server bearer.
      assignedVehicleId: session.assignedVehicleId,
      driverPhotoUrl: session.driverPhotoUrl,
      companyLogoUrl: session.companyLogoUrl,
      vehiclePhotoUrl: session.vehiclePhotoUrl,
      driverSessionToken: session.driverSessionToken,
      driverSessionExpiresAtUtc: session.driverSessionExpiresAtUtc,
      linkMethod: 'driver_pairing_code',
    );
  }
}

/// Process-memory-only handoff from a just verified QR/code response.
/// The five-minute window cannot be restored after app restart.
class FreshDriverPinSetup {
  FreshDriverPinSetup(ActiveDriverSession session)
    : credential = DriverPinServerSession.fromVerifiedSession(session);
  @visibleForTesting
  FreshDriverPinSetup.withAge(ActiveDriverSession session, this._testAge)
    : credential = DriverPinServerSession.fromVerifiedSession(session);
  final DriverPinServerSession credential;
  final Stopwatch _age = Stopwatch()..start();
  Duration Function()? _testAge;
  bool matches(ActiveDriverSession current) =>
      (_testAge?.call() ?? _age.elapsed) < const Duration(minutes: 5) &&
      current.isStandaloneLoginSession &&
      current.driverId == credential.session.driverId &&
      current.tenantId == credential.session.tenantId &&
      current.companyId == credential.session.companyId &&
      current.companyCode == credential.session.companyCode &&
      current.driverSessionToken == credential.session.driverSessionToken &&
      DateTime.tryParse(
            current.driverSessionExpiresAtUtc ?? '',
          )?.isAfter(DateTime.now()) ==
          true;
}
