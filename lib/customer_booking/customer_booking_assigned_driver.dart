import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_keys.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_labels.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';

const Key kCustomerBookingAssignedDriverKey = Key(
  'customer_booking_assigned_driver',
);
const Key kCustomerBookingAssignedDriverPendingKey = Key(
  'customer_booking_assigned_driver_pending',
);
const Key kCustomerBookingAssignedDriverReviewsKey = Key(
  'customer_booking_assigned_driver_reviews',
);

class CustomerBookingAssignedDriver {
  const CustomerBookingAssignedDriver({
    this.driverId = '',
    this.firstName = '',
    this.photoUrl = '',
    this.ratingAverage,
    this.ratingCount = 0,
    this.reviewsUrl = '',
    this.assigned = false,
  });

  final String driverId;
  final String firstName;
  final String photoUrl;
  final double? ratingAverage;
  final int ratingCount;
  final String reviewsUrl;
  final bool assigned;
}

CustomerBookingAssignedDriver customerBookingAssignedDriverFromMaps({
  Map<String, dynamic>? booking,
  Map<String, dynamic>? driver,
}) {
  final root = booking ?? const <String, dynamic>{};
  final nested = root['assigned_driver'] is Map
      ? Map<String, dynamic>.from(root['assigned_driver'] as Map)
      : root['assignedDriver'] is Map
      ? Map<String, dynamic>.from(root['assignedDriver'] as Map)
      : driver;
  final id = (root['assigned_driver_id'] ??
          root['assignedDriverId'] ??
          (nested == null ? '' : companyAgendaDriverId(nested)))
      .toString()
      .trim();
  if (id.isEmpty && (nested == null || companyAgendaDriverId(nested).isEmpty)) {
    return const CustomerBookingAssignedDriver();
  }
  final record = nested ?? <String, dynamic>{'driver_id': id};
  final rating = _personalRating(record);
  return CustomerBookingAssignedDriver(
    driverId: id.isEmpty ? companyAgendaDriverId(record) : id,
    firstName: companyAgendaDriverFirstName(record),
    photoUrl: companyAgendaResolvedPhotoUrl(
      (record['public_photo_url'] ??
              record['publicPhotoUrl'] ??
              record['driver_photo_url'] ??
              record['driverPhotoUrl'] ??
              record['photo_url'] ??
              record['portrait_url'] ??
              '')
          .toString(),
    ),
    ratingAverage: rating.average,
    ratingCount: rating.count,
    reviewsUrl: (record['reviews_url'] ?? record['reviewsUrl'] ?? '')
        .toString()
        .trim(),
    assigned: true,
  );
}

CustomerBookingAssignedDriver customerBookingProposedDriverFromRecord(
  Map<String, dynamic>? driver,
) {
  if (driver == null) return const CustomerBookingAssignedDriver();
  final parsed = customerBookingAssignedDriverFromMaps(driver: driver);
  if (parsed.driverId.isEmpty && parsed.firstName.isEmpty) {
    return const CustomerBookingAssignedDriver();
  }
  return CustomerBookingAssignedDriver(
    driverId: parsed.driverId,
    firstName: parsed.firstName,
    photoUrl: parsed.photoUrl,
    ratingAverage: parsed.ratingAverage,
    ratingCount: parsed.ratingCount,
    assigned: false,
  );
}

({double? average, int count}) _personalRating(Map<String, dynamic> raw) {
  // Company aggregates stay on the company. Only personal driver fields.
  final avgRaw = raw['driver_rating_avg'] ??
      raw['driverRatingAvg'] ??
      raw['rating_avg'] ??
      raw['ratingAvg'];
  final countRaw = raw['driver_rating_count'] ??
      raw['driverRatingCount'] ??
      raw['rating_count'] ??
      raw['ratingCount'];
  final avg = avgRaw is num ? avgRaw.toDouble() : double.tryParse('$avgRaw');
  final count = countRaw is num
      ? countRaw.round()
      : int.tryParse('$countRaw') ?? 0;
  if (avg == null || avg <= 0 || count <= 0) {
    return (average: null, count: 0);
  }
  return (average: avg, count: count);
}

class CustomerBookingProposedDriverLine extends StatelessWidget {
  const CustomerBookingProposedDriverLine({
    super.key,
    required this.driver,
    required this.language,
    required this.titleColor,
    required this.mutedColor,
    required this.surfaceAlt,
  });

  final CustomerBookingAssignedDriver driver;
  final AppLanguage language;
  final Color titleColor;
  final Color mutedColor;
  final Color surfaceAlt;

  @override
  Widget build(BuildContext context) {
    if (driver.driverId.isEmpty && driver.firstName.isEmpty) {
      return Text(
        kCustomerBookingDriverPending.of(language),
        key: kCustomerBookingProposedDriverKey,
        style: TextStyle(color: mutedColor, fontSize: 12, fontWeight: FontWeight.w600),
      );
    }
    final name = driver.firstName.isEmpty
        ? kCustomerBookingDriverFallback.of(language)
        : driver.firstName;
    final score = driver.ratingAverage == null
        ? kCustomerBookingDriverProposed.of(language)
        : '${driver.ratingAverage!.toStringAsFixed(1)} · ${driver.ratingCount}';
    final photo = driver.photoUrl.trim();
    return Row(
      key: kCustomerBookingProposedDriverKey,
      children: [
        if (photo.isNotEmpty)
          ClipOval(
            child: Image.network(
              photo,
              width: 28,
              height: 28,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _dot(),
            ),
          )
        else
          _dot(),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$name · $score',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: titleColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _dot() {
    return CircleAvatar(
      radius: 14,
      backgroundColor: surfaceAlt,
      child: Icon(Icons.person_outline, size: 16, color: titleColor),
    );
  }
}

class CustomerBookingAssignedDriverCard extends StatelessWidget {
  const CustomerBookingAssignedDriverCard({
    super.key,
    required this.driver,
    required this.language,
    required this.palette,
    this.wide = false,
    this.onOpenReviews,
  });

  final CustomerBookingAssignedDriver driver;
  final AppLanguage language;
  final CustomerThemePalette palette;
  final bool wide;
  final VoidCallback? onOpenReviews;

  @override
  Widget build(BuildContext context) {
    if (!driver.assigned) {
      return Text(
        kCustomerBookingDriverPending.of(language),
        key: kCustomerBookingAssignedDriverPendingKey,
        style: TextStyle(
          color: palette.textMuted,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    final name = driver.firstName.isEmpty
        ? kCustomerBookingDriverFallback.of(language)
        : driver.firstName;
    final score = driver.ratingAverage == null
        ? kCustomerBookingDriverNoReviews.of(language)
        : '${driver.ratingAverage!.toStringAsFixed(1)} · ${driver.ratingCount}';
    final photo = driver.photoUrl.trim();
    return Material(
      key: kCustomerBookingAssignedDriverKey,
      color: palette.surface,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: wide
            ? Row(
                children: [
                  _avatar(photo),
                  const SizedBox(width: 10),
                  Expanded(child: _copy(name, score)),
                ],
              )
            : Row(
                children: [
                  _avatar(photo),
                  const SizedBox(width: 10),
                  Expanded(child: _copy(name, score)),
                ],
              ),
      ),
    );
  }

  Widget _avatar(String photo) {
    if (photo.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          photo,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackIcon(),
        ),
      );
    }
    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    return CircleAvatar(
      radius: 20,
      backgroundColor: palette.surfaceAlt,
      child: Icon(Icons.person_outline, color: palette.textPrimary),
    );
  }

  Widget _copy(String name, String score) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          score,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: palette.textMuted, fontWeight: FontWeight.w600),
        ),
        if (driver.reviewsUrl.isNotEmpty || onOpenReviews != null)
          TextButton(
            key: kCustomerBookingAssignedDriverReviewsKey,
            onPressed: onOpenReviews,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(kCustomerBookingDriverReviews.of(language)),
          ),
      ],
    );
  }
}
