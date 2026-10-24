/// Preferences only. Backend authorization and capabilities control activation.
class CompanyOperatingPolicy {
  const CompanyOperatingPolicy({
    this.deviceBinding = 'existing',
    this.availabilitySource = 'existing',
    this.scheduledDispatch = 'existing',
    this.immediateDispatch = 'existing',
    this.offerResponseSeconds,
    this.unansweredOffer,
    this.primaryVehicleId,
    this.primaryReviewAboveCents,
  });
  final String deviceBinding,
      availabilitySource,
      scheduledDispatch,
      immediateDispatch;
  final int? offerResponseSeconds;
  final String? unansweredOffer;
  final String? primaryVehicleId;
  final int? primaryReviewAboveCents;

  factory CompanyOperatingPolicy.fromJson(Map<String, dynamic> json) {
    final policy = CompanyOperatingPolicy(
      deviceBinding: json['device_binding'] as String? ?? 'existing',
      availabilitySource: json['availability_source'] as String? ?? 'existing',
      scheduledDispatch: json['scheduled_dispatch'] as String? ?? 'existing',
      immediateDispatch: json['immediate_dispatch'] as String? ?? 'existing',
      offerResponseSeconds: json['offer_response_seconds'] as int?,
      unansweredOffer: json['unanswered_offer'] as String?,
      primaryVehicleId: json['primary_vehicle_id'] as String?,
      primaryReviewAboveCents: json['primary_review_above_cents'] as int?,
    );
    if (json['version'] != 1 || policy.validationError != null)
      throw const FormatException('operating_policy_invalid');
    return policy;
  }
  String? get validationError {
    if (!['existing', 'vehicle'].contains(deviceBinding) ||
        !['existing', 'manual_duty'].contains(availabilitySource) ||
        !['existing', 'manager_first'].contains(scheduledDispatch) ||
        ![
          'existing',
          'manager_first',
          'driver_offer',
          'primary_vehicle_first',
          'manager_above_threshold',
        ].contains(immediateDispatch) ||
        unansweredOffer != null &&
            !['central', 'next_vehicle'].contains(unansweredOffer) ||
        offerResponseSeconds != null && offerResponseSeconds! <= 0)
      return 'operating_policy_invalid';
    if (primaryReviewAboveCents != null && primaryReviewAboveCents! < 0 ||
        primaryVehicleId != null &&
            !RegExp(r'^[a-zA-Z0-9_.-]{1,96}$').hasMatch(primaryVehicleId!))
      return 'operating_policy_invalid';
    if (['driver_offer', 'primary_vehicle_first', 'manager_above_threshold'].contains(immediateDispatch) &&
        (offerResponseSeconds == null || unansweredOffer == null))
      return 'offer_policy_incomplete';
    if (immediateDispatch == 'primary_vehicle_first' &&
        (primaryVehicleId == null || primaryReviewAboveCents == null))
      return 'primary_offer_policy_incomplete';
    if (immediateDispatch == 'manager_above_threshold' && primaryReviewAboveCents == null) return 'manager_review_policy_incomplete';
    return null;
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'device_binding': deviceBinding,
    'availability_source': availabilitySource,
    'scheduled_dispatch': scheduledDispatch,
    'immediate_dispatch': immediateDispatch,
    'offer_response_seconds': offerResponseSeconds,
    'unanswered_offer': unansweredOffer,
    if (primaryVehicleId != null) 'primary_vehicle_id': primaryVehicleId,
    if (primaryReviewAboveCents != null)
      'primary_review_above_cents': primaryReviewAboveCents,
  };
  CompanyOperatingPolicy copyWith({
    String? deviceBinding,
    String? availabilitySource,
    String? scheduledDispatch,
    String? immediateDispatch,
    int? offerResponseSeconds,
    String? unansweredOffer,
    String? primaryVehicleId,
    int? primaryReviewAboveCents,
    bool clearOfferResponseSeconds = false,
  }) => CompanyOperatingPolicy(
    deviceBinding: deviceBinding ?? this.deviceBinding,
    availabilitySource: availabilitySource ?? this.availabilitySource,
    scheduledDispatch: scheduledDispatch ?? this.scheduledDispatch,
    immediateDispatch: immediateDispatch ?? this.immediateDispatch,
    offerResponseSeconds: clearOfferResponseSeconds
        ? null
        : offerResponseSeconds ?? this.offerResponseSeconds,
    unansweredOffer: unansweredOffer ?? this.unansweredOffer,
    primaryVehicleId: primaryVehicleId ?? this.primaryVehicleId,
    primaryReviewAboveCents:
        primaryReviewAboveCents ?? this.primaryReviewAboveCents,
  );
}
