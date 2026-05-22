import 'package:flutter/material.dart';

typedef EventBookCallback = void Function(EventDetailData event);

class EventDetailData {
  const EventDetailData({
    required this.id,
    required this.title,
    required this.category,
    required this.dateTimeLabel,
    required this.locationName,
    required this.city,
    required this.address,
    required this.lat,
    required this.lng,
    required this.distanceOrStatus,
    required this.gradient,
    this.visualAssetPath,
    this.sourceLabel,
    this.marketCode,
    this.countryCode,
    this.categoryKey,
    this.startAtUtc,
    this.endAtUtc,
    this.timeZone,
    this.sourceEventId,
    this.provider,
    this.status,
    this.sourceUrl,
    this.updatedAtUtc,
  });

  final String id;
  final String title;
  final String category;
  final String dateTimeLabel;
  final String locationName;
  final String city;
  final String address;
  final double lat;
  final double lng;
  final String distanceOrStatus;
  final List<Color> gradient;
  final String? visualAssetPath;
  final String? sourceLabel;

  // Future-feed fields (optional for backward compatibility).
  final String? marketCode;
  final String? countryCode;
  final String? categoryKey;
  final DateTime? startAtUtc;
  final DateTime? endAtUtc;
  final String? timeZone;
  final String? sourceEventId;
  final String? provider;
  final String? status;
  final String? sourceUrl;
  final DateTime? updatedAtUtc;

  String get destinationLabel {
    final location = locationName.trim();
    final destination = address.trim();
    if (location.isEmpty) return destination;
    if (destination.isEmpty) return location;
    return '$location, $destination';
  }
}
