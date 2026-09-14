import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_config.dart';

class CompanyAgendaDriverLook {
  const CompanyAgendaDriverLook({
    required this.driverId,
    required this.displayName,
    required this.color,
    this.photoUrl = '',
    this.availabilityStatus = '',
  });

  final String driverId;
  final String displayName;
  final Color color;
  final String photoUrl;
  final String availabilityStatus;

  String get initials => companyAgendaInitials(displayName);

  bool get isOnlineNow {
    final status = availabilityStatus.trim().toLowerCase();
    return status == 'available' || status == 'online' || status == 'busy';
  }
}

String companyAgendaInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final text = parts.first;
    return text.substring(0, text.length >= 2 ? 2 : 1).toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

Color companyAgendaFallbackColor(String seed) {
  final text = seed.trim();
  var hash = 0;
  for (var i = 0; i < text.length; i += 1) {
    hash = 0x1fffffff & (hash * 31 + text.codeUnitAt(i));
  }
  final hue = (hash % 360).toDouble();
  return HSVColor.fromAHSV(1, hue, 0.42, 0.62).toColor();
}

Color companyAgendaColorFromHex(String raw, {required String fallbackSeed}) {
  var hex = raw.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 3) {
    hex = hex.split('').map((ch) => '$ch$ch').join();
  }
  if (hex.length == 6 || hex.length == 8) {
    final value = int.tryParse(hex, radix: 16);
    if (value != null) {
      return Color(hex.length == 6 ? 0xFF000000 | value : value);
    }
  }
  return companyAgendaFallbackColor(fallbackSeed);
}

String companyAgendaDriverId(Map<String, dynamic> raw) {
  return (raw['driver_id'] ?? raw['driverId'] ?? '').toString().trim();
}

String companyAgendaDriverName(Map<String, dynamic> raw) {
  final name = (raw['display_name'] ?? raw['displayName'] ?? raw['name'] ?? '')
      .toString()
      .trim();
  return name.isEmpty ? companyAgendaDriverId(raw) : name;
}

CompanyAgendaDriverLook companyAgendaDriverLook(
  Map<String, dynamic> raw, {
  String fallbackId = '',
}) {
  final id = companyAgendaDriverId(raw).isEmpty
      ? fallbackId
      : companyAgendaDriverId(raw);
  return CompanyAgendaDriverLook(
    driverId: id,
    displayName: companyAgendaDriverName(raw).isEmpty
        ? id
        : companyAgendaDriverName(raw),
    color: companyAgendaColorFromHex(
      (raw['agenda_color'] ?? raw['agendaColor'] ?? '').toString(),
      fallbackSeed: id,
    ),
    photoUrl: companyAgendaResolvedPhotoUrl(
      (raw['driver_photo_url'] ?? raw['driverPhotoUrl'] ?? raw['photo_url'] ?? '')
          .toString(),
    ),
    availabilityStatus:
        (raw['availability_status'] ?? raw['availabilityStatus'] ?? '')
            .toString(),
  );
}

CompanyAgendaDriverLook companyAgendaLookForDriver({
  required String driverId,
  required List<Map<String, dynamic>> drivers,
}) {
  final id = driverId.trim();
  for (final driver in drivers) {
    if (companyAgendaDriverId(driver) == id) {
      return companyAgendaDriverLook(driver, fallbackId: id);
    }
  }
  return CompanyAgendaDriverLook(
    driverId: id,
    displayName: id,
    color: companyAgendaFallbackColor(id),
  );
}

String companyAgendaVehiclePlate(Map<String, dynamic> raw) {
  return (raw['license_plate'] ?? raw['licensePlate'] ?? '').toString().trim();
}

String companyAgendaVehicleName(Map<String, dynamic> raw) {
  return (raw['vehicle_name'] ??
          raw['vehicleName'] ??
          raw['brand_model'] ??
          raw['brandModel'] ??
          raw['label'] ??
          '')
      .toString()
      .trim();
}

String companyAgendaVehicleLabel(Map<String, dynamic> raw) {
  final plate = companyAgendaVehiclePlate(raw);
  final name = companyAgendaVehicleName(raw);
  final id = companyAgendaVehicleId(raw);
  if (name.isNotEmpty && plate.isNotEmpty) return '$name · $plate';
  if (name.isNotEmpty) return name;
  if (plate.isNotEmpty) return plate;
  return id;
}

int companyAgendaVehicleCapacity(Map<String, dynamic> raw) {
  final value = raw['passenger_capacity'] ?? raw['passengerCapacity'] ?? raw['seats'];
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String companyAgendaResolvedPhotoUrl(String raw) {
  final url = raw.trim();
  if (url.isEmpty) return '';
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  if (url.startsWith('/')) return '$kBookingBaseUrl$url';
  return url;
}

String companyAgendaVehicleId(Map<String, dynamic> raw) {
  return (raw['vehicle_id'] ?? raw['vehicleId'] ?? '').toString().trim();
}

bool companyAgendaFlagIsActive(Object? raw) {
  if (raw == false || raw == 0) return false;
  final text = raw?.toString().trim().toLowerCase() ?? '';
  return text != 'false' && text != '0' && text != 'inactive';
}

bool companyAgendaDriverIsActive(Map<String, dynamic> raw) {
  if (raw.containsKey('is_active') ||
      raw.containsKey('isActive') ||
      raw.containsKey('active')) {
    return companyAgendaFlagIsActive(
      raw['is_active'] ?? raw['isActive'] ?? raw['active'],
    );
  }
  return true;
}

bool companyAgendaVehicleIsActive(Map<String, dynamic> raw) {
  if (raw.containsKey('is_active') ||
      raw.containsKey('isActive') ||
      raw.containsKey('active')) {
    return companyAgendaFlagIsActive(
      raw['is_active'] ?? raw['isActive'] ?? raw['active'],
    );
  }
  return true;
}

bool companyAgendaVehicleFitsPassengers(
  Map<String, dynamic> raw,
  int passengers,
) {
  final capacity = companyAgendaVehicleCapacity(raw);
  if (capacity <= 0 || passengers <= 0) return true;
  return capacity >= passengers;
}

bool companyAgendaDriverIsSuitable(Map<String, dynamic> raw) {
  return companyAgendaDriverId(raw).isNotEmpty &&
      companyAgendaDriverIsActive(raw);
}

bool companyAgendaVehicleIsSuitable(
  Map<String, dynamic> raw, {
  required int passengers,
}) {
  return companyAgendaVehicleId(raw).isNotEmpty &&
      companyAgendaVehicleIsActive(raw) &&
      companyAgendaVehicleFitsPassengers(raw, passengers);
}

String companyAgendaResolvedDriverLabel(
  String raw,
  List<Map<String, dynamic>> drivers,
) {
  final text = raw.trim();
  if (text.isEmpty || text == '—') return text.isEmpty ? '—' : text;
  for (final driver in drivers) {
    if (companyAgendaDriverId(driver) == text) {
      return companyAgendaDriverName(driver);
    }
  }
  return text;
}

String companyAgendaResolvedVehicleLabel(
  String raw,
  List<Map<String, dynamic>> vehicles,
) {
  final text = raw.trim();
  if (text.isEmpty || text == '—') return text.isEmpty ? '—' : text;
  for (final vehicle in vehicles) {
    if (companyAgendaVehicleId(vehicle) == text) {
      return companyAgendaVehicleLabel(vehicle);
    }
  }
  return text;
}
