// COMPANY-CUSTOMER-OPS-P0 — existing GET /bookings/:id detail.

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/booking_list_page_repository.dart';
import 'package:fluxidi_tracking/company/company_agenda_http.dart';
import 'package:fluxidi_tracking/company/company_agenda_labels.dart';
import 'package:fluxidi_tracking/company/company_booking_metrics.dart';
import 'package:fluxidi_tracking/company/company_customer_quote_labels.dart';
import 'package:fluxidi_tracking/company/company_driver_agenda_style.dart';
import 'package:fluxidi_tracking/company/company_ops_api.dart';
import 'package:fluxidi_tracking/company/company_form_date_time.dart';
import 'package:fluxidi_tracking/company/company_ops_theme.dart';
import 'package:fluxidi_tracking/company/company_fixed_price_breakdown.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/company/company_roundtrip.dart';
import 'package:fluxidi_tracking/company/company_assignment_choice_field.dart';
import 'package:fluxidi_tracking/company/company_dispatch.dart';
import 'package:fluxidi_tracking/company/company_booking_route_coords.dart';
import 'package:fluxidi_tracking/company/company_crew_combo.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/company/company_plan_ride_form.dart';
import 'package:fluxidi_tracking/company/company_plan_route_map.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';

const Key kCompanyBookingDetailPageKey = Key('company_booking_detail_page');
const Key kCompanyAgendaBackToQuoteHintKey = Key(
  'company_agenda_back_to_quote_hint',
);
const Key kCompanyAgendaAssignButtonKey = Key('company_agenda_assign_button');
const Key kCompanyAgendaUnassignButtonKey = Key(
  'company_agenda_unassign_button',
);
const Key kCompanyAgendaRescheduleButtonKey = Key(
  'company_agenda_reschedule_button',
);
const Key kCompanyAgendaPhoneConfirmKey = Key('company_agenda_phone_confirm');
const Key kCompanyAgendaAssignDriverKey = Key('company_agenda_assign_driver');
const Key kCompanyAgendaAssignedStoredKey = Key(
  'company_agenda_assigned_stored',
);
const Key kCompanyAgendaAssignmentPendingKey = Key(
  'company_agenda_assignment_pending',
);
const Key kCompanyAgendaAssignVehicleKey = Key('company_agenda_assign_vehicle');
const Key kCompanyAgendaAssignChoicesStatusKey = Key(
  'company_agenda_assign_choices_status',
);
const Key kCompanyAgendaOverlapPreviewKey = Key(
  'company_agenda_overlap_preview',
);
const Key kCompanyAgendaCancelButtonKey = Key('company_agenda_cancel_button');
const Key kCompanyBookingDetailPriceBreakdownKey = Key(
  'company_booking_detail_price_breakdown',
);
const Key kCompanyBookingDetailPriceBreakdownMissingKey = Key(
  'company_booking_detail_price_breakdown_missing',
);

enum CompanyBookingOpenedFrom { quote, bookingsList }

class CompanyBookingDetailPage extends StatefulWidget {
  const CompanyBookingDetailPage({
    super.key,
    required this.bookingId,
    this.language,
    this.loader,
    this.driversLoader,
    this.vehiclesLoader,
    this.agendaRepository,
    this.openedFrom = CompanyBookingOpenedFrom.bookingsList,
    this.openedLegId = '',
    this.openedLegType = '',
    this.linkedBookingHint = '',
    this.audience = CompanyPlanAudience.companyOps,
  });

  final String bookingId;
  final AppLanguage? language;
  final Future<Map<String, dynamic>> Function(String bookingId)? loader;
  final Future<List<Map<String, dynamic>>> Function()? driversLoader;
  final Future<List<Map<String, dynamic>>> Function()? vehiclesLoader;
  final CompanyAgendaRepository? agendaRepository;
  final CompanyBookingOpenedFrom openedFrom;
  final String openedLegId;
  final String openedLegType;
  final String linkedBookingHint;
  final CompanyPlanAudience audience;

  @override
  State<CompanyBookingDetailPage> createState() =>
      _CompanyBookingDetailPageState();
}

class _CompanyBookingDetailPageState extends State<CompanyBookingDetailPage> {
  bool _loading = true;
  bool _saving = false;
  bool _fleetLoading = true;
  String? _error;
  String? _assignError;
  String? _overlapPreview;
  String? _fleetError;
  Map<String, dynamic> _row = const <String, dynamic>{};
  List<Map<String, dynamic>> _drivers = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _vehicles = const <Map<String, dynamic>>[];
  String? _driverId;
  String? _vehicleId;

  AppLanguage get _lang => widget.language ?? appLanguageNotifier.value;
  late final CompanyAgendaRepository _agenda =
      widget.agendaRepository ?? CompanyAgendaRepository();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, dynamic> get _record {
    final row = _row;
    if (row['record'] is Map) {
      return Map<String, dynamic>.from(row['record'] as Map);
    }
    return row;
  }

  Map<String, dynamic> get _booking {
    final record = _record;
    if (record['booking'] is Map) {
      return Map<String, dynamic>.from(record['booking'] as Map);
    }
    return const <String, dynamic>{};
  }

  String _text(List<String> keys) {
    for (final key in keys) {
      final value = (_booking[key] ?? _record[key] ?? _row[key])
          ?.toString()
          .trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  bool _flag(List<String> keys) {
    for (final key in keys) {
      final value = _booking[key] ?? _record[key] ?? _row[key];
      if (value == true) return true;
    }
    return false;
  }

  int? get _revision {
    final raw = _text(const ['revision']);
    return int.tryParse(raw);
  }

  int get _passengers {
    return int.tryParse(_text(const ['pax', 'passengers'])) ?? 1;
  }

  int? get _durationMin {
    return resolveCompanyBookingDurationMin(_row);
  }

  CompanyRoundtripChoice get _roundtripChoice {
    return parseCompanyRoundtripChoice(
      _text(const ['roundtrip_dispatch_mode', 'roundtripDispatchMode']),
    );
  }

  bool get _isSplit => _roundtripChoice == CompanyRoundtripChoice.splitNoWait;

  String get _parentBookingId {
    final parent = _text(const ['parent_booking_id', 'parentBookingId']);
    return parent.isEmpty ? widget.bookingId : parent;
  }

  Map<String, dynamic>? get _openedLeg {
    final raw = _record['operational_legs'] ?? _booking['operational_legs'];
    if (raw is! List) return null;
    final wantId = widget.openedLegId.trim().toLowerCase();
    final wantType = widget.openedLegType.trim().toLowerCase();
    Map<String, dynamic>? typed;
    for (final item in raw) {
      if (item is! Map) continue;
      final leg = Map<String, dynamic>.from(item);
      final id = (leg['leg_id'] ?? leg['legId'] ?? '').toString().trim().toLowerCase();
      final type = (leg['leg_type'] ?? leg['legType'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (wantId.isNotEmpty && id == wantId) return leg;
      if (wantType.isNotEmpty && type == wantType) typed = leg;
    }
    return typed;
  }

  String _legOrRecordText(List<String> keys) {
    final leg = _openedLeg;
    if (leg != null) {
      for (final key in keys) {
        final value = leg[key]?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
    }
    return _text(keys);
  }

  bool get _assigned {
    return _storedDriverId.isNotEmpty || _storedVehicleId.isNotEmpty;
  }

  /// The assignment the server actually holds.
  ///
  /// Kept apart from [_driverId] / [_vehicleId], which are only the operator's
  /// current selection. Showing the selection as "Assigned" made a rejected
  /// change look accepted.
  String get _storedDriverId =>
      _legOrRecordText(const ['assigned_driver_id', 'assignedDriverId']);

  String get _storedVehicleId =>
      _legOrRecordText(const ['assigned_vehicle_id', 'assignedVehicleId']);

  /// A different crew is selected than the one on the server.
  bool get _hasPendingAssignmentChange {
    final driver = (_driverId ?? '').trim();
    final vehicle = (_vehicleId ?? '').trim();
    if (driver.isEmpty && vehicle.isEmpty) return false;
    return driver != _storedDriverId || vehicle != _storedVehicleId;
  }

  Future<void> _load() async {
    try {
      final body = await (widget.loader ?? fetchCompanyOpsBookingDetail)(
        widget.bookingId,
      );
      if (!mounted) return;
      setState(() {
        _row = body;
        _loading = false;
        _driverId = _legOrRecordText(const [
          'assigned_driver_id',
          'assignedDriverId',
        ]);
        _vehicleId = _legOrRecordText(const [
          'assigned_vehicle_id',
          'assignedVehicleId',
        ]);
        if (_driverId!.isEmpty) _driverId = null;
        if (_vehicleId!.isEmpty) _vehicleId = null;
      });
      await _loadFleet();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Boeking laden mislukt';
        _loading = false;
      });
    }
  }

  Future<void> _loadFleet() async {
    setState(() {
      _fleetLoading = true;
      _fleetError = null;
    });
    try {
      final results = await Future.wait<List<Map<String, dynamic>>>([
        (widget.driversLoader ?? fetchCompanyOpsDrivers)(),
        (widget.vehiclesLoader ?? fetchCompanyOpsVehicles)(),
      ]);
      if (!mounted) return;
      setState(() {
        _drivers = results[0];
        _vehicles = results[1];
        _fleetLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fleetLoading = false;
        _fleetError = kCompanyAgendaChoicesLoadFailed.of(_lang);
      });
    }
  }

  String _agendaExceptionText(CompanyAgendaException error) {
    return companyAgendaAssignmentExceptionText(error, _lang);
  }

  String get _currentDriverId =>
      _legOrRecordText(const ['assigned_driver_id', 'assignedDriverId']);

  List<Map<String, dynamic>> get _alternativeDrivers {
    return companyDispatchAlternativeDrivers(
      drivers: _drivers,
      currentDriverId: _currentDriverId,
    );
  }

  String? _overlapCheckText(CompanyAgendaOverlapCheck check) {
    if (!check.hasConflict) return null;
    return switch (check.code) {
      'assignment_overlap' => kCompanyAgendaOverlapPreview.of(_lang),
      'assignment_availability_unknown' =>
        kCompanyAgendaAvailabilityUnknown.of(_lang),
      _ => kCompanyAgendaOverlapPreview.of(_lang),
    };
  }

  Future<void> _previewOverlap() async {
    final driverId = (_driverId ?? '').trim();
    final vehicleId = (_vehicleId ?? '').trim();
    final pickup = widget.openedLegType.trim().toLowerCase() == 'return'
        ? _text(const ['return_pickup_iso', 'returnPickupIso'])
        : _text(const ['pickup_iso', 'pickupIso', 'start_at']);
    if ((driverId.isEmpty && vehicleId.isEmpty) || pickup.isEmpty) {
      if (mounted) setState(() => _overlapPreview = null);
      return;
    }
    try {
      final check = await _agenda.checkOverlap(
        driverId: driverId,
        vehicleId: vehicleId,
        pickupIso: pickup,
        durationMin: _durationMin,
        excludeBookingId: widget.bookingId,
      );
      if (!mounted) return;
      setState(() => _overlapPreview = _overlapCheckText(check));
    } on CompanyAgendaException catch (error) {
      if (!mounted) return;
      setState(() => _overlapPreview = _agendaExceptionText(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _overlapPreview = null);
    }
  }

  Future<void> _runMutation(
    Future<void> Function() action,
  ) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _assignError = null;
    });
    try {
      await action();
      final scope = _agenda.scope ?? companyOpsScope();
      bookingListPageRepository.invalidateBookingListsForAffectedCompany(
        tenantId: scope['tenant_id'] ?? '',
        companyId: scope['company_id'] ?? '',
      );
      await _load();
      if (!mounted) return;
      setState(() => _saving = false);
    } on CompanyAgendaException catch (error) {
      // A refusal is definite: the server kept the existing assignment, so
      // only the message changes and the stored crew stays as it was.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _assignError = _agendaExceptionText(error);
      });
    } catch (_) {
      // An uncertain outcome (network, timeout) may or may not have applied.
      // Read the server back rather than leaving a guess on screen.
      if (!mounted) return;
      setState(() => _assignError = kCompanyAgendaSaveFailed.of(_lang));
      try {
        await _load();
      } catch (_) {
        // Keep the refusal message; the next open re-reads anyway.
      }
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  Future<void> _assign() async {
    final driverId = (_driverId ?? '').trim();
    final vehicleId = (_vehicleId ?? '').trim();
    if (driverId.isEmpty && vehicleId.isEmpty) {
      setState(() => _assignError = kCompanyAgendaSaveFailed.of(_lang));
      return;
    }
    await _runMutation(() async {
      await _agenda.assignRide(
        bookingId: widget.bookingId,
        driverId: driverId,
        vehicleId: vehicleId,
        revision: _revision,
        legId: widget.openedLegId,
        legType: widget.openedLegType,
      );
    });
  }

  Future<void> _unassign() async {
    await _runMutation(() async {
      await _agenda.unassignRide(
        bookingId: widget.bookingId,
        revision: _revision,
      );
    });
  }

  Future<void> _reschedule() async {
    final pickupRaw = _text(const ['pickup_iso', 'pickupIso', 'start_at']);
    final current = DateTime.tryParse(pickupRaw)?.toLocal() ?? DateTime.now();
    final picked = await showCompanyDateTimeEditor(
      context: context,
      language: _lang,
      initial: current,
      title: kCompanyAgendaReschedule.of(_lang),
    );
    if (picked == null || !mounted) return;
    await _runMutation(() async {
      await _agenda.rescheduleRide(
        bookingId: widget.bookingId,
        pickupLocal: picked,
        revision: _revision,
        legId: widget.openedLegId,
        legType: widget.openedLegType,
      );
    });
  }

  Future<void> _phoneConfirm() async {
    await _runMutation(() async {
      await _agenda.phoneConfirmRide(bookingId: widget.bookingId);
    });
  }

  Future<void> _cancelRide() async {
    CompanyBookingCancelScope scope = CompanyBookingCancelScope.fullRoundtrip;
    if (_isSplit) {
      final picked = await showDialog<CompanyBookingCancelScope>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(kCompanyAgendaCancelConfirm.of(_lang)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(kCompanyAgendaCancel.of(_lang)),
            ),
            if (widget.openedLegId.trim().isNotEmpty)
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  CompanyBookingCancelScope.singleLeg,
                ),
                child: Text(kCompanyAgendaCancelThisLeg.of(_lang)),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                CompanyBookingCancelScope.fullRoundtrip,
              ),
              child: Text(kCompanyAgendaCancelFullReturn.of(_lang)),
            ),
          ],
        ),
      );
      if (picked == null) return;
      scope = picked;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(kCompanyAgendaCancelConfirm.of(_lang)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(kCompanyAgendaCancel.of(_lang)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(kCompanyAgendaCancelRideAction.of(_lang)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() {
      _saving = true;
      _assignError = null;
    });
    try {
      await cancelCompanyOpsBooking(
        bookingId: widget.bookingId,
        parentBookingId: _parentBookingId,
        legId: widget.openedLegId,
        legType: widget.openedLegType,
        scope: scope,
      );
      final companyScope = _agenda.scope ?? companyOpsScope();
      bookingListPageRepository.invalidateBookingListsForAffectedCompany(
        tenantId: companyScope['tenant_id'] ?? '',
        companyId: companyScope['company_id'] ?? '',
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _assignError = kCompanyAgendaCancelFailed.of(_lang);
      });
    }
  }

  CompanyBookingRouteEndpoints _routeEndpoints({
    CompanyPlanQuoteResult? quote,
    required String from,
    required String to,
  }) {
    return resolveCompanyBookingRouteEndpoints(
      row: _row,
      openedLeg: _openedLeg,
      quote: quote,
      fromText: from,
      toText: to,
    );
  }

  @override
  Widget build(BuildContext context) {
    final quoteId = _text(const ['quote_id', 'quoteId']);
    final customer = _text(const ['customer_name', 'customerName']);
    final from = _text(const ['from', 'pickup']);
    final to = _text(const ['to', 'dropoff']);
    final pickup = _text(const ['pickup_iso', 'pickupIso', 'start_at']);
    final pickupLocal = companyFormDateTimeFromIso(pickup);
    final pax = _text(const ['pax', 'passengers']);
    final amount = resolveCompanyBookingPriceInclVat(_row);
    final currency = resolveCompanyBookingCurrency(_row);
    final durationMin = _durationMin;
    final status = _text(const ['status']);
    final rideOptions = parseCompanyRideOptions(
      _booking['ride_options'] ?? _record['ride_options'] ?? _booking,
    );
    final rideSummary = formatCompanyRideOptionsSummary(
      rideOptions,
      language: _lang,
    );
    final snapshot = companyFixedPriceSnapshotOf(
      Map<String, dynamic>.from(_booking.isEmpty ? _record : _booking),
    ) ??
        companyFixedPriceSnapshotOf(_record);
    final quoteBreakdown = resolveCompanyBookingStoredBreakdown(_row);
    final note = _text(const ['note']);
    final accepted = _flag(const ['assignment_accepted', 'driver_accepted']);
    final phoneAt = _text(const ['phone_confirmed_at', 'phoneConfirmedAt']);
    final phoneBy = _text(const ['phone_confirmed_by', 'phoneConfirmedBy']);
    final distance = parseCompanyBookingMoney(
      _text(const ['distance_km', 'distanceKm']),
    );
    final pricingSource = _text(const ['pricing_source', 'pricingSource']);
    final customerFacing = widget.audience == CompanyPlanAudience.customer;
    final arrival = pickupLocal != null && durationMin != null
        ? pickupLocal.add(Duration(minutes: durationMin))
        : null;
    final quote = CompanyPlanQuoteResult(
      fingerprint: 'detail',
      distanceKm: distance,
      durationMin: durationMin,
      priceInclVat: amount,
      currency: currency,
      pricingSource: pricingSource,
      priceAvailable: amount != null,
    );
    final route = _routeEndpoints(quote: quote, from: from, to: to);
    final mappedQuote = CompanyPlanQuoteResult(
      fingerprint: 'detail',
      distanceKm: distance,
      durationMin: durationMin,
      priceInclVat: amount,
      currency: currency,
      pricingSource: pricingSource,
      priceAvailable: amount != null,
      pickupLat: route.pickup.lat,
      pickupLon: route.pickup.lon,
      dropoffLat: route.dropoff.lat,
      dropoffLon: route.dropoff.lon,
    );
    return CompanyOpsThemedSurface(
      child: Scaffold(
        key: kCompanyBookingDetailPageKey,
        appBar: AppBar(
          title: Text(
            customerFacing
                ? kCompanyAgendaCustomerConfirmTitle.of(_lang)
                : kCompanyCustomerQuoteViewBooking.of(_lang),
          ),
          bottom: widget.openedFrom == CompanyBookingOpenedFrom.quote
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(28),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      kCompanyAgendaBackToQuoteHint.of(_lang),
                      key: kCompanyAgendaBackToQuoteHintKey,
                    ),
                  ),
                )
              : null,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (widget.openedFrom == CompanyBookingOpenedFrom.quote) ...[
                    Text(
                      kCompanyAgendaBackToQuoteHint.of(_lang),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                  ],
                  _DetailCard(
                    title: kCompanyAgendaRouteCard.of(_lang),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (route.canDrawRoute)
                          SizedBox(
                            height: 180,
                            child: CompanyPlanRouteMap(
                              language: _lang,
                              pickup: route.pickup,
                              dropoff: route.dropoff,
                              quote: mappedQuote.hasRoute ? mappedQuote : null,
                              polyline: route.polyline,
                              compactPlaceholder: true,
                              onRetry: () {
                                debugPrint(
                                  'company_booking_route_restore ${route.missingReason}',
                                );
                              },
                            ),
                          )
                        else
                          CompanyPlanRouteMap(
                            language: _lang,
                            pickup: route.pickup,
                            dropoff: route.dropoff,
                            quote: mappedQuote,
                            compactPlaceholder: true,
                            onRetry: () {
                              debugPrint(
                                'company_booking_route_restore ${route.missingReason}',
                              );
                            },
                          ),
                        const SizedBox(height: 8),
                        Text(
                          '$from → $to',
                          key: const Key('company_booking_detail_route'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (pickupLocal != null)
                          Text(formatCompanyFormDateTime(pickupLocal, _lang))
                        else if (pickup.isNotEmpty &&
                            !companyFormLooksLikeIsoTimestamp(pickup))
                          Text(pickup),
                        if (arrival != null)
                          Text(
                            '${kCompanyAgendaEstimatedArrival.of(_lang)}: ${formatCompanyFormTime(arrival)}',
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DetailCard(
                    title: kCompanyAgendaRideFacts.of(_lang),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!customerFacing)
                          Text(
                            customer.isEmpty ? '—' : customer,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        Text(
                          '${kCompanyAgendaPassengers.of(_lang)}: ${pax.isEmpty ? '—' : pax}',
                        ),
                        if (rideOptions.bags > 0)
                          Text(
                            '${companyPlanBagsLabel(_lang)}: ${rideOptions.bags}',
                          ),
                        if (_rideOptionsVehicleLabel(rideOptions).isNotEmpty)
                          Text(_rideOptionsVehicleLabel(rideOptions)),
                        if (_roundtripChoice != CompanyRoundtripChoice.single)
                          Text(
                            companyRoundtripChoiceLabel(_roundtripChoice)
                                .of(_lang),
                          ),
                        if (_roundtripChoice ==
                                CompanyRoundtripChoice.continuousWait &&
                            rideOptions.waitMin > 0)
                          Text(
                            kCompanyAgendaDriverWaitsAbout
                                .of(_lang)
                                .replaceAll('{min}', '${rideOptions.waitMin}'),
                          ),
                        if (rideOptions.airportIata.isNotEmpty)
                          Text(rideOptions.airportIata),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DetailCard(
                    title: kCompanyAgendaPriceCard.of(_lang),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${amount == null ? '—' : formatCompanyBookingMoney(amount, currency)}'
                          '${pricingSource.isEmpty ? '' : ' · ${companyPlanQuotePricingSourceLabel(pricingSource, _lang)}'}',
                          key: const Key('company_booking_detail_amount'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (durationMin != null)
                          Text(
                            formatCompanyBookingDurationMin(durationMin),
                            key: const Key('company_booking_detail_duration'),
                          ),
                        if (distance != null && distance > 0)
                          Text(
                            '${distance.toStringAsFixed(1).replaceAll('.', ',')} km',
                          ),
                        ExpansionTile(
                          key: kCompanyBookingDetailPriceBreakdownKey,
                          tilePadding: EdgeInsets.zero,
                          title: Text(kCompanyAgendaPriceBreakdown.of(_lang)),
                          children: [
                            if (snapshot != null)
                              CompanyFixedPriceBreakdown(
                                language: _lang,
                                snapshot: snapshot,
                              )
                            else if (quoteBreakdown != null)
                              for (final line
                                  in formatCompanyPlanQuoteBreakdownLines(
                                    quoteBreakdown,
                                    language: _lang,
                                    currency: currency,
                                  ))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(line),
                                )
                            else
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  amount == null
                                      ? kCompanyAgendaPriceAmountMissing.of(
                                          _lang,
                                        )
                                      : kCompanyAgendaPriceBreakdownUnavailable
                                          .of(_lang),
                                  key:
                                      kCompanyBookingDetailPriceBreakdownMissingKey,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!customerFacing) ...[
                    const SizedBox(height: 12),
                    _DetailCard(
                      title: kCompanyAgendaAssign.of(_lang),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_assigned)
                            Text(
                              '${kCompanyAgendaAssigned.of(_lang)}: '
                              '${_driverLabel(_storedDriverId)} · '
                              '${_vehicleLabel(_storedVehicleId)}',
                              key: kCompanyAgendaAssignedStoredKey,
                            )
                          else
                            Text(
                              kCompanyCustomerQuoteAssignmentPending.of(_lang),
                            ),
                          // Only a server-accepted change moves the line above.
                          if (_hasPendingAssignmentChange)
                            Text(
                              '${kCompanyAgendaAssignmentPendingChange.of(_lang)}: '
                              '${_driverLabel(_driverId)} · '
                              '${_vehicleLabel(_vehicleId)}',
                              key: kCompanyAgendaAssignmentPendingKey,
                            ),
                          if (_assigned)
                            Text(
                              accepted
                                  ? kCompanyAgendaAccepted.of(_lang)
                                  : kCompanyAgendaNotAccepted.of(_lang),
                            ),
                          if (phoneAt.isNotEmpty)
                            Text(
                              '${kCompanyAgendaPhoneConfirmed.of(_lang)}: ${companyFormLooksLikeIsoTimestamp(phoneAt) && companyFormDateTimeFromIso(phoneAt) != null ? formatCompanyFormDateTime(companyFormDateTimeFromIso(phoneAt)!, _lang) : phoneAt}'
                              '${phoneBy.isEmpty ? '' : ' · $phoneBy'}',
                            ),
                          const SizedBox(height: 8),
                          _assignmentSection(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ExpansionTile(
                      title: Text(kCompanyAgendaTechnicalDetails.of(_lang)),
                      children: [
                        ListTile(title: Text(widget.bookingId)),
                        if (pickup.isNotEmpty) ListTile(title: Text(pickup)),
                        if (quoteId.isNotEmpty) ListTile(title: Text(quoteId)),
                        if (_text(const ['return_pickup_iso']).isNotEmpty)
                          ListTile(
                            title: Text(_text(const ['return_pickup_iso'])),
                          ),
                        if (note.isNotEmpty) ListTile(title: Text(note)),
                        if (status.isNotEmpty) ListTile(title: Text(status)),
                        if (rideSummary.isNotEmpty)
                          ListTile(title: Text(rideSummary)),
                      ],
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _assignmentSection() {
    final choicesEnabled = !_saving && !_fleetLoading && _fleetError == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          kCompanyAgendaAssign.of(_lang),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (_choicesStatusText != null) ...[
          Text(
            _choicesStatusText!,
            key: kCompanyAgendaAssignChoicesStatusKey,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
        ],
        if (_currentDriverId.isNotEmpty) ...[
          Text(
            '${kCompanyAgendaCurrentDriver.of(_lang)}: ${_driverLabel(_currentDriverId)}',
            key: kCompanyAgendaCurrentDriverKey,
          ),
          const SizedBox(height: 8),
        ],
        KeyedSubtree(
          key: kCompanyAgendaAssignDriverKey,
          child: CompanyAssignmentSearchField(
            kind: CompanyAssignmentChoiceKind.driver,
            language: _lang,
            label: kCompanyAgendaAssign.of(_lang),
            selectedId: companyCrewComboId(_driverId ?? '', _vehicleId ?? ''),
            enabled: choicesEnabled,
            choices: companyCrewComboChoices(
              combos: companyPlanCrewCombos(
                drivers: _drivers,
                vehicles: _vehicles,
                type: parseCompanyPlanVehicleType(
                      parseCompanyRideOptions(
                        _booking['ride_options'] ??
                            _record['ride_options'] ??
                            _booking,
                      ).vehicleType,
                    ) ??
                    CompanyPlanVehicleType.sedan,
                passengers: _passengers,
              ),
              language: _lang,
              unassignedLabel: kCompanyAgendaUnassignedLane.of(_lang),
              includePlate: true,
            ),
            onSelected: (id) {
              final parsed = parseCompanyCrewComboId(id);
              setState(() {
                _driverId = parsed.driverId;
                _vehicleId = parsed.vehicleId;
              });
              _previewOverlap();
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          kCompanyAgendaOnlineNowHint.of(_lang),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_overlapPreview != null) ...[
          const SizedBox(height: 8),
          Text(
            _overlapPreview!,
            key: kCompanyAgendaOverlapPreviewKey,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_assignError != null) ...[
          const SizedBox(height: 8),
          Text(
            _assignError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              key: kCompanyAgendaAssignButtonKey,
              onPressed: choicesEnabled ? _assign : null,
              child: Text(kCompanyAgendaAssign.of(_lang)),
            ),
            if (_assigned)
              OutlinedButton(
                key: kCompanyAgendaUnassignButtonKey,
                onPressed: _saving ? null : _unassign,
                child: Text(kCompanyAgendaUnassign.of(_lang)),
              ),
            OutlinedButton(
              key: kCompanyAgendaRescheduleButtonKey,
              onPressed: _saving ? null : _reschedule,
              child: Text(kCompanyAgendaReschedule.of(_lang)),
            ),
            OutlinedButton(
              key: kCompanyAgendaPhoneConfirmKey,
              onPressed: _saving ? null : _phoneConfirm,
              child: Text(kCompanyAgendaMarkPhoneConfirm.of(_lang)),
            ),
            OutlinedButton(
              key: kCompanyAgendaCancelButtonKey,
              onPressed: _saving ? null : _cancelRide,
              child: Text(kCompanyAgendaCancelRideAction.of(_lang)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          kCompanyAgendaPhoneConfirmHint.of(_lang),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  List<String> get _driverIds => [
    for (final driver in _drivers) companyAgendaDriverId(driver),
  ].where((id) => id.isNotEmpty).toList();

  List<String> get _vehicleIds => [
    for (final vehicle in _vehicles) companyAgendaVehicleId(vehicle),
  ].where((id) => id.isNotEmpty).toList();

  bool get _hasRegisteredDrivers => _driverIds.isNotEmpty;

  bool get _hasRegisteredVehicles => _vehicleIds.isNotEmpty;

  bool get _hasSuitableDrivers =>
      _drivers.any(companyAgendaDriverIsSuitable);

  bool get _hasSuitableVehicles => _vehicles.any(
    (vehicle) => companyAgendaVehicleIsSuitable(
      vehicle,
      passengers: _passengers,
    ),
  );

  String? get _choicesStatusText {
    if (_fleetLoading) return kCompanyAgendaChoicesLoading.of(_lang);
    if (_fleetError != null) return _fleetError;
    if (!_hasRegisteredDrivers) {
      return kCompanyAgendaNoRegisteredDrivers.of(_lang);
    }
    if (!_hasSuitableDrivers) {
      return kCompanyAgendaNoSuitableDrivers.of(_lang);
    }
    if (!_hasRegisteredVehicles) {
      return kCompanyAgendaNoRegisteredVehicles.of(_lang);
    }
    if (!_hasSuitableVehicles) {
      return kCompanyAgendaNoSuitableVehicles.of(_lang);
    }
    return null;
  }

  String? _existingValue(String? value, List<String> allowed) {
    final id = (value ?? '').trim();
    if (id.isEmpty || !allowed.contains(id)) return null;
    return id;
  }

  String _driverLabel(String? id) {
    final value = (id ?? '').trim();
    if (value.isEmpty) return '—';
    final name = companyAgendaLookForDriver(
      driverId: value,
      drivers: _drivers,
    ).displayName;
    if (name.isEmpty || companyPlanLooksLikeInternalId(name)) {
      return kCompanyAgendaDriverFallback.of(_lang);
    }
    return name;
  }

  String _vehicleLabel(String? id) {
    final value = (id ?? '').trim();
    if (value.isEmpty) return '—';
    for (final vehicle in _vehicles) {
      if (companyAgendaVehicleId(vehicle) == value) {
        return companyAgendaVehicleLabel(vehicle);
      }
    }
    return value;
  }

  String _vehiclePublicLabel(String? id) {
    final value = (id ?? '').trim();
    if (value.isEmpty) return '—';
    for (final vehicle in _vehicles) {
      if (companyAgendaVehicleId(vehicle) == value) {
        final name = companyAgendaVehicleName(vehicle);
        if (name.isNotEmpty && !companyPlanLooksLikeInternalId(name)) {
          return name;
        }
        return kCompanyAgendaVehicleFallback.of(_lang);
      }
    }
    if (companyPlanLooksLikeInternalId(value)) {
      return kCompanyAgendaVehicleFallback.of(_lang);
    }
    return value;
  }

  String _driverChoiceLabel(Map<String, dynamic> driver) {
    final name = companyAgendaDriverName(driver);
    if (!companyAgendaDriverIsActive(driver)) {
      return '$name · ${kCompanyAgendaDriverInactive.of(_lang)}';
    }
    return name;
  }

  String _vehicleChoiceLabel(Map<String, dynamic> vehicle) {
    final label = companyAgendaVehicleLabel(vehicle);
    if (!companyAgendaVehicleIsActive(vehicle)) {
      return '$label · ${kCompanyAgendaDriverInactive.of(_lang)}';
    }
    final capacity = companyAgendaVehicleCapacity(vehicle);
    if (capacity > 0 && capacity < _passengers) {
      return '$label · te klein voor $_passengers';
    }
    return label;
  }

  String _rideOptionsVehicleLabel(CompanyRideOptions options) {
    final type = parseCompanyPlanVehicleType(options.vehicleType);
    if (type == null) return '';
    return companyPlanVehicleTypeLabel(type, _lang);
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

Future<void> openCompanyBookingDetail(
  BuildContext context, {
  required String bookingId,
  AppLanguage? language,
  Future<Map<String, dynamic>> Function(String bookingId)? loader,
  Future<List<Map<String, dynamic>>> Function()? driversLoader,
  Future<List<Map<String, dynamic>>> Function()? vehiclesLoader,
  CompanyAgendaRepository? agendaRepository,
  CompanyBookingOpenedFrom openedFrom = CompanyBookingOpenedFrom.bookingsList,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => CompanyBookingDetailPage(
        bookingId: bookingId,
        language: language,
        loader: loader,
        driversLoader: driversLoader,
        vehiclesLoader: vehiclesLoader,
        agendaRepository: agendaRepository,
        openedFrom: openedFrom,
      ),
    ),
  );
}
