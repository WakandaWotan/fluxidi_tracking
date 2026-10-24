import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_deactivation.dart';
import 'package:fluxidi_tracking/limousine/limousine_dimensions.dart';
import 'package:fluxidi_tracking/limousine/limousine_marketplace_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_price_snapshot.dart';
import 'package:fluxidi_tracking/limousine/limousine_pricing_separation.dart';
import 'package:fluxidi_tracking/limousine/limousine_state_composition.dart';

Map<String, dynamic> _publiclyAvailableCompany({
  String subscriptionStatus = 'active',
  Map<String, dynamic> features = const {'limousine': true},
  List<String> services = const ['limousine'],
  bool profileEnabled = true,
  bool bookable = true,
  List<Map<String, dynamic>>? vehicles,
  Map<String, dynamic>? extra,
}) {
  return <String, dynamic>{
    'company_name': 'Coachline',
    'is_active': true,
    'availability_status': 'active',
    'bookable': bookable,
    'profile_enabled': profileEnabled,
    'published_at': '2026-08-17T10:00:00Z',
    'subscription_status': subscriptionStatus,
    'features': features,
    'services': services,
    'vehicles':
        vehicles ??
        const [
          <String, dynamic>{
            'name': 'Fleet One',
            'category': 'limousine',
            'is_active': true,
          },
        ],
    'limousine_available': true,
    'limousine_offers': const [
      <String, dynamic>{
        'offer_id': 'off_quote',
        'enabled': true,
        'published': true,
        'price_presentation': 'quote_required',
      },
    ],
    ...?extra,
  };
}

void main() {
  group('typed dimensions stay separate', () {
    test('service category normalizes taxi and limousine only', () {
      expect(normalizeServiceCategory('taxi'), LimousineServiceCategory.taxi);
      expect(
        normalizeServiceCategory('taxi_vvb'),
        LimousineServiceCategory.taxi,
      );
      expect(
        normalizeServiceCategory('limousine'),
        LimousineServiceCategory.limousine,
      );
      expect(normalizeServiceCategory('airport'), isNull);
      expect(normalizeServiceCategory('premium'), isNull);
    });

    test('journey type is independent from service category', () {
      expect(
        normalizeJourneyType('airport_transfer'),
        LimousineJourneyType.airportTransfer,
      );
      expect(
        normalizeJourneyType('hourly'),
        LimousineJourneyType.hourlyPackage,
      );
      expect(
        normalizeJourneyType('hotel_bnb_pickup'),
        LimousineJourneyType.hotelTransfer,
      );
      // limousine + airport transfer is a valid combination, not exclusive.
      expect(normalizeServiceCategory('limousine'), isNotNull);
      expect(normalizeJourneyType('airport_transfer'), isNotNull);
    });

    test('vehicle/service class is never inferred from brand or marketing', () {
      expect(serviceClassFromBrandOrName('Mercedes S-Class').isValid, isFalse);
      expect(serviceClassFromBrandOrName('Executive Premium').isValid, isFalse);
      expect(isForbiddenClassInferenceToken('mercedes'), isTrue);
      expect(isForbiddenClassInferenceToken('executive'), isTrue);
      expect(isForbiddenClassInferenceToken('premium'), isTrue);
      // Authoritative configured id is accepted as a class ref.
      final configured = LimousineServiceClassRef.fromAuthoritativeId(
        'executive_sedan',
      );
      expect(configured.isValid, isTrue);
      expect(configured.id, 'executive_sedan');
    });
  });

  group('pricing separation contract', () {
    test('resolution order: fixed > hourly > distance/time > manual', () {
      expect(
        resolveLimousinePricingMode(
          const LimousinePricingInputs(
            hasMatchingLimousineFixedFare: true,
            hasConfiguredHourlyOrPackagePrice: true,
            hasLimousineDistanceTimeProfile: true,
            manualQuoteAllowed: true,
          ),
        ).mode,
        LimousinePricingMode.fixedRouteOrAirportFare,
      );
      expect(
        resolveLimousinePricingMode(
          const LimousinePricingInputs(
            hasConfiguredHourlyOrPackagePrice: true,
            hasLimousineDistanceTimeProfile: true,
          ),
        ).mode,
        LimousinePricingMode.hourlyOrPackage,
      );
      expect(
        resolveLimousinePricingMode(
          const LimousinePricingInputs(hasLimousineDistanceTimeProfile: true),
        ).mode,
        LimousinePricingMode.limousineDistanceTime,
      );
      expect(
        resolveLimousinePricingMode(
          const LimousinePricingInputs(manualQuoteAllowed: true),
        ).mode,
        LimousinePricingMode.manualQuote,
      );
    });

    test('missing limousine pricing never falls back to taxi pricing', () {
      final resolution = resolveLimousinePricingMode(
        const LimousinePricingInputs(),
      );
      expect(resolution.mode, LimousinePricingMode.unavailable);
      expect(resolution.failedClosed, isTrue);
      expect(resolution.hasResolvedPrice, isFalse);
      expect(
        limousinePricingForbidsTaxiFallback(LimousineServiceCategory.limousine),
        isTrue,
      );
    });

    test('missing price resolves to manual quote or unavailable', () {
      expect(
        resolveLimousinePricingMode(
          const LimousinePricingInputs(manualQuoteAllowed: true),
        ).requiresManualQuote,
        isTrue,
      );
      expect(
        resolveLimousinePricingMode(
          const LimousinePricingInputs(),
        ).isUnavailable,
        isTrue,
      );
    });

    test('stale or contradictory pricing fails closed', () {
      expect(
        resolveLimousinePricingMode(
          const LimousinePricingInputs(
            hasMatchingLimousineFixedFare: true,
            pricingIsStale: true,
          ),
        ).mode,
        LimousinePricingMode.unavailable,
      );
      expect(
        resolveLimousinePricingMode(
          const LimousinePricingInputs(
            hasLimousineDistanceTimeProfile: true,
            pricingIsContradictory: true,
          ),
        ).failedClosed,
        isTrue,
      );
    });

    test('taxi and limousine fixed fares remain distinct', () {
      expect(
        fixedFareRuleAppliesToRequest(
          ruleCategory: LimousineServiceCategory.taxi,
          requestCategory: LimousineServiceCategory.limousine,
        ),
        isFalse,
      );
      expect(
        fixedFareRuleAppliesToRequest(
          ruleCategory: LimousineServiceCategory.limousine,
          requestCategory: LimousineServiceCategory.limousine,
        ),
        isTrue,
      );
      expect(
        fixedFaresAreDistinctByCategory(
          a: LimousineServiceCategory.taxi,
          b: LimousineServiceCategory.limousine,
        ),
        isTrue,
      );
    });

    test('street-meter finalization is forbidden for scheduled limousine', () {
      expect(
        isStreetMeterFinalizationForbidden(
          category: LimousineServiceCategory.limousine,
          isScheduled: true,
        ),
        isTrue,
      );
      expect(
        canFinalizeWithStreetMeter(
          category: LimousineServiceCategory.limousine,
          isScheduled: true,
        ),
        isFalse,
      );
      // Taxi street ride meter finalization stays allowed (unchanged behaviour).
      expect(
        canFinalizeWithStreetMeter(
          category: LimousineServiceCategory.taxi,
          isScheduled: false,
        ),
        isTrue,
      );
    });
  });

  group('accepted-price snapshot contract', () {
    test(
      'resolved fixed fare snapshot is complete and maps to booking fields',
      () {
        final snapshot = LimousineAcceptedPriceSnapshot(
          companyId: 'cmp_x',
          serviceCategory: LimousineServiceCategory.limousine,
          journeyType: LimousineJourneyType.airportTransfer,
          serviceClass: LimousineServiceClassRef.fromAuthoritativeId(
            'executive',
          ),
          pricingMode: LimousinePricingMode.fixedRouteOrAirportFare,
          matchedPricingRuleRef: 'rule_123',
          pricingSourceRevision: 7,
          totalInclVat: 189.0,
          currency: 'EUR',
          vatTreatment: 'incl',
          acceptedAtIso: '2026-08-17T10:05:00Z',
        );
        expect(snapshot.isComplete, isTrue);
        final json = snapshot.toBookingSnapshotJson();
        expect(json['service_category'], 'limousine');
        expect(json['journey_type'], 'airportTransfer');
        expect(json['service_class'], 'executive');
        expect(json['pricing_mode'], 'fixedRouteOrAirportFare');
        expect(json['fixed_fare_rule_id'], 'rule_123');
        expect(json['source_revision'], 7);
        expect(json['price_incl_vat'], 189.0);
        expect(json['currency'], 'EUR');
      },
    );

    test(
      'manual quote / unavailable cannot be snapshotted as resolved price',
      () {
        final manual = LimousineAcceptedPriceSnapshot(
          companyId: 'cmp_x',
          serviceCategory: LimousineServiceCategory.limousine,
          journeyType: LimousineJourneyType.pointToPoint,
          serviceClass: LimousineServiceClassRef.fromAuthoritativeId('sedan'),
          pricingMode: LimousinePricingMode.manualQuote,
          totalInclVat: 0,
          currency: 'EUR',
          acceptedAtIso: '',
        );
        expect(manual.isComplete, isFalse);
        expect(manual.missingRequiredFields(), contains('pricingMode'));
        expect(manual.missingRequiredFields(), contains('totalInclVat'));
      },
    );

    test('fixed fare snapshot requires a matched rule reference', () {
      final noRule = LimousineAcceptedPriceSnapshot(
        companyId: 'cmp_x',
        serviceCategory: LimousineServiceCategory.limousine,
        journeyType: LimousineJourneyType.airportTransfer,
        serviceClass: LimousineServiceClassRef.fromAuthoritativeId('executive'),
        pricingMode: LimousinePricingMode.fixedRouteOrAirportFare,
        totalInclVat: 100,
        currency: 'EUR',
        acceptedAtIso: '2026-08-17T10:05:00Z',
      );
      expect(noRule.missingRequiredFields(), contains('matchedPricingRuleRef'));
    });
  });

  group('first-class capability / state composition', () {
    test('valid capability composition is publicly available', () {
      final composition = composeLimousinePublicAvailability(
        _publiclyAvailableCompany(),
      );
      expect(
        composition.state,
        LimousinePublicAvailabilityState.publiclyAvailable,
      );
      expect(composition.isPubliclyAvailable, isTrue);
      expect(
        isPubliclyEligibleLimousineProvider(_publiclyAvailableCompany()),
        isTrue,
      );
    });

    test('missing subscription/entitlement fails closed', () {
      // No explicit entitlement flag, default policy requires it.
      final noEntitlement = composeLimousinePublicAvailability(
        _publiclyAvailableCompany(features: const <String, dynamic>{}),
      );
      expect(
        noEntitlement.state,
        LimousinePublicAvailabilityState.unavailableUnderSubscription,
      );

      // A suspended/expired subscription never permits, even with an
      // entitlement flag: it is a subscription-level block, not an account one.
      final suspendedSub = composeLimousinePublicAvailability(
        _publiclyAvailableCompany(subscriptionStatus: 'suspended'),
      );
      expect(
        suspendedSub.state,
        LimousinePublicAvailabilityState.unavailableUnderSubscription,
      );

      final cancelled = composeLimousinePublicAvailability(
        _publiclyAvailableCompany(subscriptionStatus: 'cancelled'),
      );
      expect(
        cancelled.state,
        LimousinePublicAvailabilityState.unavailableUnderSubscription,
      );
    });

    test('entitled but company-disabled fails closed', () {
      final disabled = composeLimousinePublicAvailability(
        _publiclyAvailableCompany(services: const ['taxi_vvb']),
      );
      expect(
        disabled.state,
        LimousinePublicAvailabilityState.entitledButDisabledByCompany,
      );
      expect(
        isPubliclyEligibleLimousineProvider(
          _publiclyAvailableCompany(services: const ['taxi_vvb']),
        ),
        isFalse,
      );
    });

    test('enabled but unpublished public profile fails closed', () {
      final unpublished = _publiclyAvailableCompany(profileEnabled: false);
      unpublished['published_at'] = '';
      final composition = composeLimousinePublicAvailability(unpublished);
      expect(
        composition.state,
        LimousinePublicAvailabilityState.enabledButProfileNotPublished,
      );
    });

    test('no eligible active limousine vehicle/service fails closed', () {
      final composition = composeLimousinePublicAvailability(
        _publiclyAvailableCompany(vehicles: const []),
      );
      expect(
        composition.state,
        LimousinePublicAvailabilityState.publishedButTemporarilyUnavailable,
      );
    });

    test('published but bookings not accepted stays visible', () {
      final composition = composeLimousinePublicAvailability(
        _publiclyAvailableCompany(bookable: false),
      );
      expect(
        composition.state,
        LimousinePublicAvailabilityState.publiclyAvailable,
      );
      expect(
        limousineAvailabilityStateLabelFor(composition.state, AppLanguage.nl),
        'Gepubliceerd en zichtbaar',
      );
    });

    test('suspended/deleted/tombstoned company fails closed', () {
      for (final extra in const [
        {'suspended': true},
        {'deleted': true},
        {'tombstoned': true},
        {'status': 'suspended'},
      ]) {
        final composition = composeLimousinePublicAvailability(
          _publiclyAvailableCompany(extra: extra),
        );
        expect(
          composition.state,
          LimousinePublicAvailabilityState.suspendedOrBlocked,
          reason: extra.toString(),
        );
      }
    });

    test('taxi-only company is not a limousine provider', () {
      final taxiOnly = _publiclyAvailableCompany(
        services: const ['taxi_vvb'],
        vehicles: const [
          <String, dynamic>{
            'name': 'Taxi 1',
            'category': 'Comfort',
            'is_active': true,
          },
        ],
      );
      expect(isPubliclyEligibleLimousineProvider(taxiOnly), isFalse);
    });

    test('airport-transfer capability alone does not imply limousine', () {
      final airportOnly = _publiclyAvailableCompany(
        services: const ['airport_transfer'],
        extra: const {
          'airport_service_enabled': true,
          'capabilities': <String, dynamic>{'airport': true},
        },
      );
      final composition = composeLimousinePublicAvailability(airportOnly);
      expect(
        composition.state,
        LimousinePublicAvailabilityState.entitledButDisabledByCompany,
      );
      expect(isPubliclyEligibleLimousineProvider(airportOnly), isFalse);
    });

    test(
      'entitlement policy stays compatible with either commercial decision',
      () {
        final company = _publiclyAvailableCompany(
          features: const <String, dynamic>{},
        );
        // Included-in-plan policy makes a permitting subscription entitle it.
        final included = composeLimousinePublicAvailability(
          company,
          policy: LimousineEntitlementPolicy.includedInPlan,
        );
        expect(
          included.state,
          LimousinePublicAvailabilityState.publiclyAvailable,
        );
        // Even under included-in-plan, an explicit false flag fails closed.
        final explicitFalse = composeLimousinePublicAvailability(
          _publiclyAvailableCompany(features: const {'limousine': false}),
          policy: LimousineEntitlementPolicy.includedInPlan,
        );
        expect(
          explicitFalse.state,
          LimousinePublicAvailabilityState.unavailableUnderSubscription,
        );
      },
    );

    test('subscription state normalization matches worker statuses', () {
      expect(
        normalizeSubscriptionState('active'),
        LimousineSubscriptionState.active,
      );
      expect(
        normalizeSubscriptionState('valid'),
        LimousineSubscriptionState.active,
      );
      expect(
        normalizeSubscriptionState('trialing'),
        LimousineSubscriptionState.trial,
      );
      expect(
        normalizeSubscriptionState('grace_period'),
        LimousineSubscriptionState.grace,
      );
      expect(
        normalizeSubscriptionState('past_due'),
        LimousineSubscriptionState.grace,
      );
      expect(
        normalizeSubscriptionState('cancelled'),
        LimousineSubscriptionState.cancelled,
      );
      expect(
        normalizeSubscriptionState('suspended'),
        LimousineSubscriptionState.expired,
      );
      expect(
        subscriptionStatePermitsLimousine(LimousineSubscriptionState.grace),
        isTrue,
      );
      expect(
        subscriptionStatePermitsLimousine(LimousineSubscriptionState.cancelled),
        isFalse,
      );
    });
  });

  group('deactivation semantics', () {
    test(
      'deactivation stops new discovery/bookings, preserves everything else',
      () {
        const d = kLimousineDeactivationDecision;
        expect(d.stopNewMarketplaceVisibility, isTrue);
        expect(d.stopNewBookings, isTrue);
        expect(d.preserveExistingBookings, isTrue);
        expect(d.preserveBookingCompletionFlow, isTrue);
        expect(d.preservePayments, isTrue);
        expect(d.preserveInvoices, isTrue);
        expect(d.preserveAudit, isTrue);
        expect(d.preserveHistory, isTrue);
        expect(d.preserveLimousineConfigForReactivation, isTrue);
        expect(d.preservePricingSnapshots, isTrue);
        expect(d.disablesUnrelatedTaxiOrAirport, isFalse);
        expect(d.erasesHistoricalPricingSnapshots, isFalse);
      },
    );

    test('older state never overwrites a newer disable/suspension', () {
      final stale = resolveLimousineAvailabilityTransition(
        currentCommand: LimousineAvailabilityCommand.suspend,
        currentRevision: 10,
        incomingCommand: LimousineAvailabilityCommand.enable,
        incomingRevision: 9,
      );
      expect(stale.applied, isFalse);
      expect(stale.effectiveCommand, LimousineAvailabilityCommand.suspend);
      expect(stale.ignoredReason, 'stale_revision');

      final replay = resolveLimousineAvailabilityTransition(
        currentCommand: LimousineAvailabilityCommand.disable,
        currentRevision: 10,
        incomingCommand: LimousineAvailabilityCommand.enable,
        incomingRevision: 10,
      );
      expect(replay.applied, isFalse);
      expect(replay.ignoredReason, 'idempotent_replay');
    });

    test('a newer valid reactivation restores availability', () {
      final reactivate = resolveLimousineAvailabilityTransition(
        currentCommand: LimousineAvailabilityCommand.suspend,
        currentRevision: 10,
        incomingCommand: LimousineAvailabilityCommand.enable,
        incomingRevision: 11,
      );
      expect(reactivate.applied, isTrue);
      expect(reactivate.effectiveCommand, LimousineAvailabilityCommand.enable);
      expect(reactivate.effectiveRevision, 11);
    });
  });

  group('localization for the six availability states', () {
    test('all six states have NL/EN/FR/ES labels', () {
      for (final state in LimousinePublicAvailabilityState.values) {
        final label = kLimousineAvailabilityStateLabels[state];
        expect(label, isNotNull, reason: state.name);
        for (final lang in const [
          AppLanguage.nl,
          AppLanguage.en,
          AppLanguage.fr,
          AppLanguage.es,
        ]) {
          expect(
            label!.of(lang).trim(),
            isNotEmpty,
            reason: '${state.name}/$lang',
          );
        }
      }
      expect(
        limousineAvailabilityStateLabelFor(
          LimousinePublicAvailabilityState.publiclyAvailable,
          AppLanguage.fr,
        ),
        'Publié et visible',
      );
    });
  });
}
